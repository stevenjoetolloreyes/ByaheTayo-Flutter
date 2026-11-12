// Login Alerts + Session Manager — session/attempt storage.
//
// Pattern mirrors the app's other repositories (repository
// abstraction + Firestore implementation + in-memory fake in
// tests). The Firestore queries deliberately use ONLY a `uid`
// equality filter and sort client-side: adding orderBy would need
// a composite index (a Console step for Steven). No orderBy, no
// index, no Console work.
//
// Collections (rules in firestore.rules, owner-only, placed ABOVE
// the pre-existing friend_requests brace break):
//   user_sessions/{sessionId}  — one doc per sign-in
//   login_attempts/{attemptId} — append-only sign-in attempts
//   user_security/{uid}        — passwordChangeRequired flag
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'session_models.dart';

/// Storage contract for sessions, attempts, and the security flag.
/// All methods are safe to call when the backend is absent: the
/// Firestore implementation throws on failure and the caller
/// (SessionService) treats storage as best-effort, never blocking
/// sign-in.
abstract class SessionRepository {
  Future<void> createSession(UserSession session);
  Future<void> touchSession(String sessionId);
  Future<void> updateSessionLocation(String sessionId, String locationLabel);
  Future<void> markSessionTrusted(String sessionId);
  Future<void> deleteSession(String sessionId);
  Future<void> deleteAllSessionsExcept(String uid, String keepSessionId);
  Future<UserSession?> getSession(String sessionId);
  Future<List<UserSession>> listSessions(String uid);
  Stream<List<UserSession>> watchSessions(String uid);

  /// Emits the session, or null once its document is deleted (the
  /// revocation signal other devices listen for).
  Stream<UserSession?> watchSession(String sessionId);

  Future<void> recordAttempt(LoginAttempt attempt);
  Future<List<LoginAttempt>> listAttempts(String uid);

  Future<bool> isPasswordChangeRequired(String uid);
  Future<void> setPasswordChangeRequired(String uid, bool value);
}

/// Firestore implementation of [SessionRepository].
class FirestoreSessionRepository implements SessionRepository {
  FirestoreSessionRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _firestore.collection(userSessionsCollection);
  CollectionReference<Map<String, dynamic>> get _attempts =>
      _firestore.collection(loginAttemptsCollection);
  CollectionReference<Map<String, dynamic>> get _security =>
      _firestore.collection(userSecurityCollection);

  @override
  Future<void> createSession(UserSession session) async {
    await _sessions.doc(session.id).set({
      'uid': session.uid,
      'deviceLabel': session.deviceLabel,
      'platform': session.platform,
      'formFactor': session.formFactor,
      'signInMethod': session.signInMethod,
      'locationLabel': session.locationLabel,
      'trusted': session.trusted,
      'createdAt': FieldValue.serverTimestamp(),
      'lastActiveAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> touchSession(String sessionId) async {
    await _sessions.doc(sessionId).update({
      'lastActiveAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> updateSessionLocation(
    String sessionId,
    String locationLabel,
  ) async {
    await _sessions.doc(sessionId).update({
      'locationLabel': locationLabel,
    });
  }

  @override
  Future<void> markSessionTrusted(String sessionId) async {
    await _sessions.doc(sessionId).update({'trusted': true});
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    await _sessions.doc(sessionId).delete();
  }

  @override
  Future<void> deleteAllSessionsExcept(
    String uid,
    String keepSessionId,
  ) async {
    final others = await listSessions(uid);
    for (final session in others) {
      if (session.id != keepSessionId) {
        await _sessions.doc(session.id).delete();
      }
    }
  }

  @override
  Future<UserSession?> getSession(String sessionId) async {
    final doc = await _sessions.doc(sessionId).get();
    if (!doc.exists) return null;
    return UserSession.fromMap(doc.id, doc.data() ?? {});
  }

  @override
  Future<List<UserSession>> listSessions(String uid) async {
    final snapshot =
        await _sessions.where('uid', isEqualTo: uid).get();
    final sessions = snapshot.docs
        .map((doc) => UserSession.fromMap(doc.id, doc.data()))
        .toList();
    return sortSessions(sessions);
  }

  @override
  Stream<List<UserSession>> watchSessions(String uid) {
    return _sessions
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      final sessions = snapshot.docs
          .map((doc) => UserSession.fromMap(doc.id, doc.data()))
          .toList();
      return sortSessions(sessions);
    });
  }

  @override
  Stream<UserSession?> watchSession(String sessionId) {
    return _sessions.doc(sessionId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserSession.fromMap(doc.id, doc.data() ?? {});
    });
  }

  @override
  Future<void> recordAttempt(LoginAttempt attempt) async {
    await _attempts.doc(attempt.id).set({
      'uid': attempt.uid,
      'success': attempt.success,
      'reason': attempt.reason,
      'deviceLabel': attempt.deviceLabel,
      'platform': attempt.platform,
      'signInMethod': attempt.signInMethod,
      'locationLabel': attempt.locationLabel,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<List<LoginAttempt>> listAttempts(String uid) async {
    final snapshot =
        await _attempts.where('uid', isEqualTo: uid).get();
    final attempts = snapshot.docs
        .map((doc) => LoginAttempt.fromMap(doc.id, doc.data()))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    // Newest 50: history is a recent-activity view, not an archive.
    return attempts.take(50).toList();
  }

  @override
  Future<bool> isPasswordChangeRequired(String uid) async {
    final doc = await _security.doc(uid).get();
    if (!doc.exists) return false;
    return (doc.data() ?? {})['passwordChangeRequired'] as bool? ?? false;
  }

  @override
  Future<void> setPasswordChangeRequired(String uid, bool value) async {
    await _security.doc(uid).set(
      {
        'passwordChangeRequired': value,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}

/// In-memory [SessionRepository] for tests (and for the
/// never-configured path, where SessionService is a no-op anyway).
class InMemorySessionRepository implements SessionRepository {
  final _sessions = <String, UserSession>{};
  final _attempts = <String, LoginAttempt>{};
  final _security = <String, bool>{};
  final _sessionControllers = <String, StreamController<List<UserSession>>>{};
  final _singleControllers =
      <String, StreamController<UserSession?>>{};

  void _emit(String uid) {
    final controller = _sessionControllers[uid];
    if (controller != null && !controller.isClosed) {
      controller.add(listSessionsSync(uid));
    }
  }

  List<UserSession> listSessionsSync(String uid) {
    final sessions =
        _sessions.values.where((s) => s.uid == uid).toList();
    return sortSessions(sessions);
  }

  @override
  Future<void> createSession(UserSession session) async {
    _sessions[session.id] = session;
    _emit(session.uid);
    _singleControllers[session.id]?.add(session);
  }

  @override
  Future<void> touchSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return;
    _sessions[sessionId] =
        session.copyWith(lastActiveAt: DateTime.now());
    _emit(session.uid);
    _singleControllers[sessionId]?.add(_sessions[sessionId]);
  }

  @override
  Future<void> updateSessionLocation(
    String sessionId,
    String locationLabel,
  ) async {
    final session = _sessions[sessionId];
    if (session == null) return;
    _sessions[sessionId] =
        session.copyWith(locationLabel: locationLabel);
    _emit(session.uid);
    _singleControllers[sessionId]?.add(_sessions[sessionId]);
  }

  @override
  Future<void> markSessionTrusted(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return;
    _sessions[sessionId] = session.copyWith(trusted: true);
    _emit(session.uid);
    _singleControllers[sessionId]?.add(_sessions[sessionId]);
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session != null) _emit(session.uid);
    _singleControllers[sessionId]?.add(null);
  }

  @override
  Future<void> deleteAllSessionsExcept(
    String uid,
    String keepSessionId,
  ) async {
    final ids = _sessions.values
        .where((s) => s.uid == uid && s.id != keepSessionId)
        .map((s) => s.id)
        .toList();
    for (final id in ids) {
      await deleteSession(id);
    }
  }

  @override
  Future<UserSession?> getSession(String sessionId) async =>
      _sessions[sessionId];

  @override
  Future<List<UserSession>> listSessions(String uid) async =>
      listSessionsSync(uid);

  @override
  Stream<List<UserSession>> watchSessions(String uid) {
    final controller = _sessionControllers.putIfAbsent(
      uid,
      () => StreamController<List<UserSession>>.broadcast(),
    );
    return Stream<List<UserSession>>.multi((sink) {
      sink.add(listSessionsSync(uid));
      final sub = controller.stream.listen(
        sink.add,
        onError: sink.addError,
        onDone: sink.close,
      );
      sink.onCancel = sub.cancel;
    });
  }

  @override
  Stream<UserSession?> watchSession(String sessionId) {
    final controller = _singleControllers.putIfAbsent(
      sessionId,
      () => StreamController<UserSession?>.broadcast(),
    );
    return Stream<UserSession?>.multi((sink) {
      sink.add(_sessions[sessionId]);
      final sub = controller.stream.listen(
        sink.add,
        onError: sink.addError,
        onDone: sink.close,
      );
      sink.onCancel = sub.cancel;
    });
  }

  @override
  Future<void> recordAttempt(LoginAttempt attempt) async {
    _attempts[attempt.id] = attempt;
  }

  @override
  Future<List<LoginAttempt>> listAttempts(String uid) async {
    final attempts = _attempts.values
        .where((a) => a.uid == uid)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return attempts.take(50).toList();
  }

  @override
  Future<bool> isPasswordChangeRequired(String uid) async =>
      _security[uid] ?? false;

  @override
  Future<void> setPasswordChangeRequired(String uid, bool value) async {
    _security[uid] = value;
  }
}
