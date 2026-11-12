// Login Alerts + Session Manager — orchestration.
//
// Owns the per-sign-in session lifecycle: creates the Firestore
// session record at sign-in, records observable sign-in attempts,
// watches for foreign sessions (the login alert) and for the
// current session's deletion (revocation from another device), and
// runs the secure-my-account flow.
//
// BEST-EFFORT BY CONTRACT: session recording must never block or
// break sign-in. Every repository call is guarded — a storage
// failure (offline, rules, unconfigured Firebase) is swallowed
// and the sign-in proceeds. The only hard rule is the revocation
// check: a stored current-session id whose document is GONE means
// another device revoked this one, so [onRevoked] fires and the
// app signs out. A sign-in whose record could not be created
// stores NO current id, so it can never false-revoke on restart.
//
// No dart:io here (web build): the platform comes from
// [defaultTargetPlatform], never `Platform.operatingSystem`.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../onboarding/auth_service.dart';
import 'session_location.dart';
import 'session_models.dart';
import 'session_repository.dart';

/// SharedPreferences keys (all local-only; the server never sees
/// the pending-failure queue or the known-session list).
const _kCurrentSessionId = 'estudyantego_current_session_id';
const _kCurrentSessionUid = 'estudyantego_current_session_uid';
const _kKnownSessionIds = 'estudyantego_known_session_ids';
const _kPendingFailedAttempts = 'estudyantego_pending_failed_attempts';

/// Pending failed attempts kept per device (max 20, oldest
/// dropped). Flushed into the account's login history after a later
/// successful sign-in for the same email — the only moment the
/// account's UID is known.
const maxPendingFailedAttempts = 20;

/// Minimum gap between last-active touches (avoids a Firestore
/// write on every resume).
const _touchThrottle = Duration(minutes: 5);

/// One pending failed attempt, as stored locally.
class PendingFailedAttempt {
  const PendingFailedAttempt({
    required this.email,
    required this.reason,
    required this.signInMethod,
    required this.deviceLabel,
    required this.platform,
    required this.attemptedAt,
  });

  final String email;
  final String reason;
  final String signInMethod;
  final String deviceLabel;
  final String platform;
  final DateTime attemptedAt;

  Map<String, dynamic> toJson() => {
        'email': email,
        'reason': reason,
        'signInMethod': signInMethod,
        'deviceLabel': deviceLabel,
        'platform': platform,
        'millis': attemptedAt.millisecondsSinceEpoch,
      };

  static PendingFailedAttempt? fromJson(Map<String, dynamic> json) {
    try {
      final millis = json['millis'] as int?;
      if (millis == null) return null;
      return PendingFailedAttempt(
        email: (json['email'] as String?) ?? '',
        reason: (json['reason'] as String?) ?? 'sign-in failed',
        signInMethod: (json['signInMethod'] as String?) ?? 'email',
        deviceLabel: (json['deviceLabel'] as String?) ?? 'Unknown device',
        platform: (json['platform'] as String?) ?? 'unknown',
        attemptedAt: DateTime.fromMillisecondsSinceEpoch(millis),
      );
    } catch (_) {
      return null;
    }
  }
}

class SessionService {
  SessionService({
    required SharedPreferences prefs,
    SessionRepository? repository,
    Future<String?> Function()? locationLabelProvider,
    Future<void> Function({
      required String title,
      required String body,
    })? notify,
    String Function()? deviceLabelProvider,
  })  : _prefs = prefs,
        _repository = repository,
        _locationLabelProvider =
            locationLabelProvider ?? bestEffortLocationLabel,
        _notify = notify,
        _deviceLabelProvider =
            deviceLabelProvider ?? _defaultDeviceLabel;

  final SharedPreferences _prefs;
  final SessionRepository? _repository;
  final Future<String?> Function() _locationLabelProvider;
  final Future<void> Function({
    required String title,
    required String body,
  })? _notify;
  final String Function() _deviceLabelProvider;

  /// Fired (once per foreign session) when a session that is not
  /// this device appears. The app shows the local notification and
  /// the 'Was this you?' dialog.
  void Function(UserSession session)? onForeignSession;

  /// Fired when this device's own session record was deleted from
  /// another device: the app must sign out locally.
  void Function()? onRevoked;

  String? _currentSessionId;
  String? _currentUid;
  DateTime? _lastTouch;
  StreamSubscription<List<UserSession>>? _sessionsSubscription;
  StreamSubscription<UserSession?>? _ownSessionSubscription;
  bool _signingOut = false;
  bool _disposed = false;

  /// The current sign-in's session id, or null when this install
  /// has no recorded session (signed out, or recording failed).
  String? get currentSessionId => _currentSessionId;

  /// True when a session record exists for this sign-in.
  bool get hasCurrentSession => _currentSessionId != null;

  static String _defaultDeviceLabel() {
    if (kIsWeb) return 'Web browser';
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
    var isTablet = false;
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        final view = views.first;
        final size = view.physicalSize / view.devicePixelRatio;
        isTablet = size.shortestSide >= 600;
      }
    } catch (_) {
      isTablet = false;
    }
    return deviceLabelFor(platform: platform, isTablet: isTablet);
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  String get _deviceLabel {
    try {
      return _deviceLabelProvider();
    } catch (_) {
      return 'Unknown device';
    }
  }

  // ---- sign-in / restore ----

  /// Records a fresh sign-in: creates the session document and the
  /// success attempt, flushes pending failures for this email, and
  /// starts the watchers. Returns the created session, or null when
  /// there is no repository or recording failed (sign-in itself is
  /// unaffected). Never throws.
  Future<UserSession?> onSignedIn(
    AuthUser user, {
    required String signInMethod,
  }) async {
    final repository = _repository;
    if (repository == null) return null;
    final sessionId = const Uuid().v4();
    final now = DateTime.now();
    final session = UserSession(
      id: sessionId,
      uid: user.uid,
      deviceLabel: _deviceLabel,
      platform: _platformName(),
      formFactor: _deviceLabel.toLowerCase().contains('tablet')
          ? 'tablet'
          : _platformName() == 'web'
              ? 'desktop'
              : 'phone',
      signInMethod: signInMethods.contains(signInMethod)
          ? signInMethod
          : 'email',
      createdAt: now,
      lastActiveAt: now,
    );
    try {
      // Bounded: an unreachable Firestore must degrade to "no
      // record" instead of stalling sign-in (or app start) forever.
      await repository
          .createSession(session)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // No record, no current id: a failed create must never
      // false-revoke this device on restart.
      return null;
    }
    _currentSessionId = sessionId;
    _currentUid = user.uid;
    _lastTouch = now;
    await _persistCurrentSession();
    _markKnown(sessionId);
    // Success attempt + pending-failure flush are independent of
    // the session record: each is best-effort on its own.
    try {
      await repository.recordAttempt(LoginAttempt(
        id: _attemptId(now),
        uid: user.uid,
        success: true,
        reason: '',
        deviceLabel: session.deviceLabel,
        platform: session.platform,
        signInMethod: session.signInMethod,
        createdAt: now,
      ));
    } catch (_) {}
    await _flushPendingFailures(user);
    _fillLocationLater(session);
    _startWatchers(user.uid);
    return session;
  }

  /// Re-adopts a restored Firebase session on app start.
  /// - Stored current id + live document → adopt it, touch it,
  ///   start watchers, check for foreign sessions.
  /// - Stored current id + MISSING document → this device was
  ///   revoked elsewhere: returns true and records nothing (the
  ///   caller signs out; [onRevoked] is reserved for the
  ///   mid-session watcher path, so a start-up revocation is never
  ///   reported twice).
  /// - No stored id → first run of this feature on this install:
  ///   creates a fresh 'restored' session.
  /// Returns true when this device was revoked. Never throws.
  Future<bool> onRestoredSession(AuthUser user) async {
    try {
      return await _onRestoredSession(user);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _onRestoredSession(AuthUser user) async {
    final repository = _repository;
    if (repository == null) return false;
    final storedId = _prefs.getString(_kCurrentSessionId);
    final storedUid = _prefs.getString(_kCurrentSessionUid);
    if (storedId != null && storedUid == user.uid) {
      UserSession? existing;
      try {
        existing = await repository.getSession(storedId);
      } catch (_) {
        existing = null;
      }
      if (existing != null) {
        _currentSessionId = storedId;
        _currentUid = user.uid;
        _markKnown(storedId);
        await touchSession();
        _startWatchers(user.uid);
        await _checkForeignSessions(user.uid);
        return false;
      }
      // A stored id whose document is gone is a revocation, not a
      // missing record: do NOT create a replacement session.
      _currentSessionId = null;
      _currentUid = null;
      await _persistCurrentSession();
      return true;
    }
    await onSignedIn(user, signInMethod: 'restored');
    return false;
  }

  /// Records a failed attempt for a user whose UID is known (still
  /// signed in at the time — e.g. the Google login-only gate
  /// rejecting an account with no profile). Best-effort, never
  /// throws.
  Future<void> recordKnownUserFailure({
    required AuthUser user,
    required String reason,
    required String signInMethod,
  }) async {
    final repository = _repository;
    if (repository == null) return;
    final now = DateTime.now();
    try {
      await repository.recordAttempt(LoginAttempt(
        id: _attemptId(now),
        uid: user.uid,
        success: false,
        reason: reason,
        deviceLabel: _deviceLabel,
        platform: _platformName(),
        signInMethod: signInMethod,
        createdAt: now,
      ));
    } catch (_) {}
  }

  /// Queues a failed sign-in observed on this device (UID unknown
  /// at failure time). Flushed into the account's history after a
  /// later successful sign-in for the same email. Never throws.
  Future<void> onSignInFailed({
    required String email,
    required String reason,
    String signInMethod = 'email',
  }) async {
    final pending = _readPendingFailures();
    pending.add(PendingFailedAttempt(
      email: email.trim().toLowerCase(),
      reason: reason,
      signInMethod: signInMethod,
      deviceLabel: _deviceLabel,
      platform: _platformName(),
      attemptedAt: DateTime.now(),
    ));
    while (pending.length > maxPendingFailedAttempts) {
      pending.removeAt(0);
    }
    try {
      await _prefs.setStringList(
        _kPendingFailedAttempts,
        pending.map((e) => jsonEncode(e.toJson())).toList(),
      );
    } catch (_) {}
  }

  List<PendingFailedAttempt> _readPendingFailures() {
    final raw = _prefs.getStringList(_kPendingFailedAttempts) ?? const [];
    final parsed = <PendingFailedAttempt>[];
    for (final entry in raw) {
      try {
        final attempt = PendingFailedAttempt.fromJson(
          jsonDecode(entry) as Map<String, dynamic>,
        );
        if (attempt != null) parsed.add(attempt);
      } catch (_) {}
    }
    return parsed;
  }

  Future<void> _flushPendingFailures(AuthUser user) async {
    final repository = _repository;
    if (repository == null) return;
    final email = user.email.trim().toLowerCase();
    final pending = _readPendingFailures();
    final matching =
        pending.where((e) => e.email == email).toList();
    final remaining =
        pending.where((e) => e.email != email).toList();
    for (final attempt in matching) {
      try {
        await repository.recordAttempt(LoginAttempt(
          id: _attemptId(attempt.attemptedAt),
          uid: user.uid,
          success: false,
          reason: attempt.reason,
          deviceLabel: attempt.deviceLabel,
          platform: attempt.platform,
          signInMethod: attempt.signInMethod,
          createdAt: attempt.attemptedAt,
        ));
      } catch (_) {}
    }
    try {
      await _prefs.setStringList(
        _kPendingFailedAttempts,
        remaining.map((e) => jsonEncode(e.toJson())).toList(),
      );
    } catch (_) {}
  }

  static String _attemptId(DateTime at) {
    final random = Random().nextInt(9000) + 1000;
    return '${at.millisecondsSinceEpoch}_$random';
  }

  /// Resolves the location in the background and patches the
  /// session record. The sign-in never waits for it.
  void _fillLocationLater(UserSession session) {
    final repository = _repository;
    if (repository == null) return;
    unawaited(_locationLabelProvider().then((label) async {
      if (label == null || _disposed) return;
      try {
        await repository.updateSessionLocation(session.id, label);
      } catch (_) {}
    }).catchError((_) {}));
  }

  // ---- heartbeat ----

  /// Updates last-active (at most once per 5 minutes). Never throws.
  Future<void> touchSession() async {
    final repository = _repository;
    final sessionId = _currentSessionId;
    if (repository == null || sessionId == null) return;
    final now = DateTime.now();
    if (_lastTouch != null &&
        now.difference(_lastTouch!) < _touchThrottle) {
      return;
    }
    _lastTouch = now;
    try {
      await repository.touchSession(sessionId);
    } catch (_) {}
  }

  // ---- reads (screens) ----

  Future<List<UserSession>> loadSessions(String uid) async {
    final repository = _repository;
    if (repository == null) return const [];
    try {
      final sessions = await repository.listSessions(uid);
      return sortSessions(sessions, currentSessionId: _currentSessionId);
    } catch (_) {
      return const [];
    }
  }

  Future<List<LoginAttempt>> loadAttempts(String uid) async {
    final repository = _repository;
    if (repository == null) return const [];
    try {
      return await repository.listAttempts(uid);
    } catch (_) {
      return const [];
    }
  }

  Future<bool> isPasswordChangeRequired(String uid) async {
    final repository = _repository;
    if (repository == null) return false;
    try {
      return await repository.isPasswordChangeRequired(uid);
    } catch (_) {
      return false;
    }
  }

  Future<void> clearPasswordChangeRequired(String uid) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.setPasswordChangeRequired(uid, false);
    } catch (_) {}
  }

  // ---- actions (screens / alert) ----

  Future<void> markSessionTrusted(UserSession session) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.markSessionTrusted(session.id);
    } catch (_) {}
  }

  Future<void> revokeSession(UserSession session) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.deleteSession(session.id);
    } catch (_) {}
  }

  Future<void> revokeAllOtherSessions(String uid) async {
    final repository = _repository;
    final sessionId = _currentSessionId;
    if (repository == null || sessionId == null) return;
    try {
      await repository.deleteAllSessionsExcept(uid, sessionId);
    } catch (_) {}
  }

  /// 'No, secure my account': revokes the foreign session and
  /// flags the account as needing a password change (the UI then
  /// sends the reset email through the app's existing
  /// password-reset flow). Never throws.
  Future<void> secureAccount({
    required UserSession foreignSession,
    required String uid,
  }) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.deleteSession(foreignSession.id);
    } catch (_) {}
    try {
      await repository.setPasswordChangeRequired(uid, true);
    } catch (_) {}
  }

  // ---- sign-out ----

  /// Deletes this device's session record, stops the watchers,
  /// clears the local id, then signs out of Firebase via
  /// [signOutAuth]. The Firebase sign-out still runs even if the
  /// record delete fails. Never throws.
  Future<void> signOutCurrent({
    required Future<void> Function() signOutAuth,
  }) async {
    _signingOut = true;
    await stopWatchers();
    final repository = _repository;
    final sessionId = _currentSessionId;
    if (repository != null && sessionId != null) {
      try {
        await repository.deleteSession(sessionId);
      } catch (_) {}
    }
    _currentSessionId = null;
    _currentUid = null;
    await _persistCurrentSession();
    try {
      await signOutAuth();
    } catch (_) {}
    _signingOut = false;
  }

  /// Stops the watchers without touching any record (used when the
  /// app clears local state after a sign-out performed elsewhere).
  Future<void> stopWatchers() async {
    await _sessionsSubscription?.cancel();
    await _ownSessionSubscription?.cancel();
    _sessionsSubscription = null;
    _ownSessionSubscription = null;
  }

  void dispose() {
    _disposed = true;
    unawaited(stopWatchers());
  }

  // ---- watchers ----

  void _startWatchers(String uid) {
    final repository = _repository;
    if (repository == null || _disposed) return;
    unawaited(stopWatchers().then((_) {
      if (_disposed) return;
      _sessionsSubscription =
          repository.watchSessions(uid).listen((sessions) {
        unawaited(_checkForeignSessions(uid, sessions: sessions));
      }, onError: (_) {});
      final sessionId = _currentSessionId;
      if (sessionId != null) {
        _ownSessionSubscription =
            repository.watchSession(sessionId).listen((session) {
          if (session == null && !_signingOut && !_disposed) {
            // Our own record was deleted from another device.
            _currentSessionId = null;
            _currentUid = null;
            unawaited(_persistCurrentSession());
            onRevoked?.call();
          }
        }, onError: (_) {});
      }
    }));
  }

  /// Finds sessions that are not this device and have never had
  /// their alert shown. Notifies (local notification + callback)
  /// about the newest one and marks all of them known, so the
  /// alert fires once per session.
  Future<void> _checkForeignSessions(
    String uid, {
    List<UserSession>? sessions,
  }) async {
    final repository = _repository;
    if (repository == null || _disposed) return;
    final all = sessions ?? await loadSessions(uid);
    final known = _readKnownIds();
    final fresh = all
        .where((s) => s.id != _currentSessionId && !known.contains(s.id))
        .toList();
    if (fresh.isEmpty) return;
    // Prune known ids that no longer exist, so the list stays small.
    final existingIds = all.map((s) => s.id).toSet();
    final pruned = known.where(existingIds.contains).toSet();
    for (final session in fresh) {
      pruned.add(session.id);
    }
    await _persistKnownIds(pruned);
    final newest = fresh.first;
    try {
      await _notify?.call(
        title: 'New sign-in to your EstudyanteGO account',
        body:
            '${newest.deviceLabel} signed in${newest.locationLabel == null ? '' : ' in ${newest.locationLabel}'} — was this you?',
      );
    } catch (_) {}
    onForeignSession?.call(newest);
  }

  Set<String> _readKnownIds() {
    return _prefs.getStringList(_kKnownSessionIds)?.toSet() ?? {};
  }

  Future<void> _persistKnownIds(Set<String> ids) async {
    try {
      await _prefs.setStringList(_kKnownSessionIds, ids.toList());
    } catch (_) {}
  }

  void _markKnown(String sessionId) {
    final known = _readKnownIds()..add(sessionId);
    unawaited(_persistKnownIds(known));
  }

  Future<void> _persistCurrentSession() async {
    try {
      final id = _currentSessionId;
      final uid = _currentUid;
      if (id == null || uid == null) {
        await _prefs.remove(_kCurrentSessionId);
        await _prefs.remove(_kCurrentSessionUid);
      } else {
        await _prefs.setString(_kCurrentSessionId, id);
        await _prefs.setString(_kCurrentSessionUid, uid);
      }
    } catch (_) {}
  }
}
