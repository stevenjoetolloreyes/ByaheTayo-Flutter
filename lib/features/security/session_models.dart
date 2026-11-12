// Login Alerts + Session Manager — data models and pure helpers.
//
// HONEST LIMITS (see also the Security Center screens):
// - A session record exists only because the app wrote one at
//   sign-in. A device that never signed in through this app (or an
//   old install from before this feature) has no record and cannot
//   appear in Sessions.
// - A failed sign-in can only be linked to an account when the app
//   knows the account: either the failure happened while signed in,
//   or it was observed on this device and flushed after a later
//   successful sign-in for the same email. A failed attempt from an
//   unknown device that never signs in cannot be attributed to an
//   account, so it never appears in Login History. The history
//   screen says so instead of claiming completeness.
// - Location is best-effort and only when already available (see
//   session_location.dart): never requested at sign-in, never
//   invented.

/// Firestore collection for active sign-in sessions (one document
/// per sign-in, created by the app at sign-in, deleted on log-out).
const userSessionsCollection = 'user_sessions';

/// Firestore collection for sign-in attempts (append-only; success
/// and failure records the app could observe).
const loginAttemptsCollection = 'login_attempts';

/// Firestore collection for per-account security flags (one document
/// per user, document ID = UID).
const userSecurityCollection = 'user_security';

/// Sign-in methods the app records. 'restored' is a session the app
/// re-adopted on start (Firebase still signed in, no fresh sign-in).
const signInMethods = {'email', 'google', 'restored'};

/// A signed-in session (one per sign-in, per device).
class UserSession {
  const UserSession({
    required this.id,
    required this.uid,
    required this.deviceLabel,
    required this.platform,
    required this.formFactor,
    required this.signInMethod,
    required this.createdAt,
    required this.lastActiveAt,
    this.locationLabel,
    this.trusted = false,
  });

  /// Document ID = the per-sign-in session UUID generated on this
  /// device at sign-in (see SessionService).
  final String id;
  final String uid;

  /// Human device label, e.g. 'Android phone', 'iPhone', 'Web browser'.
  final String deviceLabel;

  /// Raw platform ('android', 'ios', 'web', 'windows', ...).
  final String platform;

  /// 'phone', 'tablet', 'desktop', or 'unknown'.
  final String formFactor;

  /// 'email', 'google', or 'restored'.
  final String signInMethod;

  final DateTime createdAt;
  final DateTime lastActiveAt;

  /// City/province label when a location was available at sign-in,
  /// e.g. 'Vigan City, Ilocos Sur'. Null when unavailable — the UI
  /// hides the row instead of inventing a place.
  final String? locationLabel;

  /// True once the account owner answered 'Yes, that was me' to the
  /// login alert for this session.
  final bool trusted;

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'deviceLabel': deviceLabel,
      'platform': platform,
      'formFactor': formFactor,
      'signInMethod': signInMethod,
      'locationLabel': locationLabel,
      'trusted': trusted,
      // Timestamps are written by the repository with
      // FieldValue.serverTimestamp(); toMap carries them only for
      // tests / the in-memory repository.
      'createdAtMillis': createdAt.millisecondsSinceEpoch,
      'lastActiveAtMillis': lastActiveAt.millisecondsSinceEpoch,
    };
  }

  static UserSession fromMap(String id, Map<String, dynamic> map) {
    DateTime readTime(Object? value, DateTime fallback) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value is DateTime) return value;
      // Firestore Timestamp.
      try {
        final millis = (value as dynamic)?.millisecondsSinceEpoch as int?;
        if (millis != null) {
          return DateTime.fromMillisecondsSinceEpoch(millis);
        }
      } catch (_) {}
      return fallback;
    }

    final now = DateTime.now();
    return UserSession(
      id: id,
      uid: (map['uid'] as String?) ?? '',
      deviceLabel: (map['deviceLabel'] as String?) ?? 'Unknown device',
      platform: (map['platform'] as String?) ?? 'unknown',
      formFactor: (map['formFactor'] as String?) ?? 'unknown',
      signInMethod: (map['signInMethod'] as String?) ?? 'email',
      createdAt: readTime(map['createdAt'] ?? map['createdAtMillis'], now),
      lastActiveAt:
          readTime(map['lastActiveAt'] ?? map['lastActiveAtMillis'], now),
      locationLabel: map['locationLabel'] as String?,
      trusted: (map['trusted'] as bool?) ?? false,
    );
  }

  UserSession copyWith({
    DateTime? lastActiveAt,
    String? locationLabel,
    bool? trusted,
  }) {
    return UserSession(
      id: id,
      uid: uid,
      deviceLabel: deviceLabel,
      platform: platform,
      formFactor: formFactor,
      signInMethod: signInMethod,
      createdAt: createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      locationLabel: locationLabel ?? this.locationLabel,
      trusted: trusted ?? this.trusted,
    );
  }

  /// 'Active now' when touched in the last 5 minutes, otherwise a
  /// short 'Last active' stamp. Mirrors the approved preview.
  String lastActiveLabel({DateTime? now}) {
    final at = now ?? DateTime.now();
    if (at.difference(lastActiveAt).inMinutes < 5 &&
        !lastActiveAt.isAfter(at)) {
      return 'Active now';
    }
    return 'Last active: ${formatDayTime(lastActiveAt, now: at)}';
  }

  /// Second line under the device label, as in the preview:
  /// 'Android phone · EstudyanteGO app' / 'Web browser sign-in'.
  String get detailLine {
    if (platform == 'web') return 'Web browser sign-in';
    return '$deviceLabel · EstudyanteGO app';
  }
}

/// One sign-in attempt the app could observe.
class LoginAttempt {
  const LoginAttempt({
    required this.id,
    required this.uid,
    required this.success,
    required this.reason,
    required this.deviceLabel,
    required this.platform,
    required this.signInMethod,
    required this.createdAt,
    this.locationLabel,
  });

  /// Document ID = `'<millis>_<random>'` (time-ordered, unique).
  final String id;
  final String uid;

  /// True for a successful sign-in, false for a failure.
  final bool success;

  /// Failure reason label, e.g. 'wrong password' (see
  /// [failureReasonForCode]). Empty for successes.
  final String reason;

  final String deviceLabel;
  final String platform;
  final String signInMethod;
  final DateTime createdAt;
  final String? locationLabel;

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'success': success,
      'reason': reason,
      'deviceLabel': deviceLabel,
      'platform': platform,
      'signInMethod': signInMethod,
      'locationLabel': locationLabel,
      'createdAtMillis': createdAt.millisecondsSinceEpoch,
    };
  }

  static LoginAttempt fromMap(String id, Map<String, dynamic> map) {
    DateTime readTime(Object? value, DateTime fallback) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value is DateTime) return value;
      try {
        final millis = (value as dynamic)?.millisecondsSinceEpoch as int?;
        if (millis != null) {
          return DateTime.fromMillisecondsSinceEpoch(millis);
        }
      } catch (_) {}
      return fallback;
    }

    return LoginAttempt(
      id: id,
      uid: (map['uid'] as String?) ?? '',
      success: (map['success'] as bool?) ?? false,
      reason: (map['reason'] as String?) ?? '',
      deviceLabel: (map['deviceLabel'] as String?) ?? 'Unknown device',
      platform: (map['platform'] as String?) ?? 'unknown',
      signInMethod: (map['signInMethod'] as String?) ?? 'email',
      createdAt: readTime(
        map['createdAt'] ?? map['createdAtMillis'],
        DateTime.now(),
      ),
      locationLabel: map['locationLabel'] as String?,
    );
  }

  /// Preview wording: 'Signed in' / 'Signed in with Google' for
  /// successes, `Failed sign-in — <reason>` for failures.
  String get titleLine {
    if (success) {
      return signInMethod == 'google'
          ? 'Signed in with Google'
          : 'Signed in';
    }
    return reason.isEmpty
        ? 'Failed sign-in'
        : 'Failed sign-in — $reason';
  }
}

/// Maps a Firebase Auth error code (see FirebaseAuthService) to the
/// honest history label. 'invalid-credential' is what Firebase
/// returns for a wrong password on current SDKs, so it maps to
/// 'wrong password' — the same label the preview shows.
String failureReasonForCode(String? code) {
  switch (code) {
    case 'wrong-password':
    case 'invalid-credential':
      return 'wrong password';
    case 'user-not-found':
      return 'account not found';
    case 'too-many-requests':
      return 'too many attempts';
    case 'network-request-failed':
      return 'network error';
    case 'invalid-email':
      return 'invalid email';
    case 'no-account':
      return 'no account found';
    case 'user-disabled':
      return 'account disabled';
    default:
      return 'sign-in failed';
  }
}

/// Human device label from the raw platform + form factor, matching
/// the preview's wording ('Android phone', 'Android tablet',
/// 'Chrome · Windows' is approximated as 'Windows PC' — the app
/// cannot see the browser brand).
String deviceLabelFor({required String platform, required bool isTablet}) {
  switch (platform) {
    case 'android':
      return isTablet ? 'Android tablet' : 'Android phone';
    case 'ios':
      return isTablet ? 'iPad' : 'iPhone';
    case 'web':
      return 'Web browser';
    case 'windows':
      return 'Windows PC';
    case 'macos':
      return 'Mac';
    case 'linux':
      return 'Linux PC';
    default:
      return 'Unknown device';
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _monthName(int month) => _months[month - 1];
String _weekdayShort(int weekday) => _weekdays[weekday - 1];

/// '10:24 PM'.
String formatTimeOfDay(DateTime time) {
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final period = time.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

/// 'Nov 11'.
String formatMonthDay(DateTime time) =>
    '${_monthName(time.month)} ${time.day}';

/// 'Today, 8:12 PM' / 'Yesterday, 9:47 PM' / 'Nov 10, 7:05 AM'.
/// Mirrors the preview's per-session stamps.
String formatDayTime(DateTime time, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final today = DateTime(at.year, at.month, at.day);
  final day = DateTime(time.year, time.month, time.day);
  final diff = today.difference(day).inDays;
  final clock = formatTimeOfDay(time);
  if (diff == 0) return 'Today, $clock';
  if (diff == 1) return 'Yesterday, $clock';
  return '${formatMonthDay(time)}, $clock';
}

/// Date-group header for the login history, as in the preview:
/// ('TODAY', 'Wed · Nov 11').
({String label, String sublabel}) dayGroupHeader(
  DateTime day, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final today = DateTime(at.year, at.month, at.day);
  final diff = today.difference(day).inDays;
  final sub = '${_weekdayShort(day.weekday)} · ${formatMonthDay(day)}';
  if (diff == 0) return (label: 'TODAY', sublabel: sub);
  if (diff == 1) return (label: 'YESTERDAY', sublabel: sub);
  return (label: formatMonthDay(day).toUpperCase(), sublabel: sub);
}

/// Groups attempts newest-first into day groups, each newest-first.
/// Returns (day, attempts) pairs in newest-day-first order.
List<({DateTime day, List<LoginAttempt> attempts})> groupAttemptsByDay(
  List<LoginAttempt> attempts, {
  DateTime? now,
}) {
  final sorted = List<LoginAttempt>.from(attempts)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final groups = <DateTime, List<LoginAttempt>>{};
  for (final attempt in sorted) {
    final day = DateTime(
      attempt.createdAt.year,
      attempt.createdAt.month,
      attempt.createdAt.day,
    );
    (groups[day] ??= []).add(attempt);
  }
  final days = groups.keys.toList()
    ..sort((a, b) => b.compareTo(a));
  return [
    for (final day in days) (day: day, attempts: groups[day]!),
  ];
}

/// Newest-first sessions, current session first regardless of time.
List<UserSession> sortSessions(
  List<UserSession> sessions, {
  String? currentSessionId,
}) {
  final sorted = List<UserSession>.from(sessions)
    ..sort((a, b) => b.lastActiveAt.compareTo(a.lastActiveAt));
  if (currentSessionId == null) return sorted;
  final current =
      sorted.where((s) => s.id == currentSessionId).toList();
  final others =
      sorted.where((s) => s.id != currentSessionId).toList();
  return [...current, ...others];
}
