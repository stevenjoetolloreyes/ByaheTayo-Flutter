// Tests for the Login Alerts + Session Manager service (no
// Firebase, no device): session creation, attempt recording and
// pending-failure flush, foreign-session alerts, revocation,
// secure-my-account, and sign-out cleanup. Uses the in-memory
// repository and mocked SharedPreferences.
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/security/session_models.dart';
import 'package:estudyantego/features/security/session_repository.dart';
import 'package:estudyantego/features/security/session_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _user = AuthUser(
  uid: 'uid-1',
  email: 'student@example.com',
  displayName: 'Test Student',
  emailVerified: true,
);

Future<SessionService> _service(
  InMemorySessionRepository repository, {
  List<String>? notifyLog,
  List<UserSession>? foreignLog,
  bool Function()? onRevokedFlag,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final service = SessionService(
    prefs: prefs,
    repository: repository,
    locationLabelProvider: () async => null,
    deviceLabelProvider: () => 'Android phone',
    notify: notifyLog == null
        ? null
        : ({required String title, required String body}) async {
            notifyLog.add('$title|$body');
          },
  );
  if (foreignLog != null) {
    service.onForeignSession = foreignLog.add;
  }
  if (onRevokedFlag != null) {
    service.onRevoked = () => onRevokedFlag();
  }
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sign-in recording', () {
    test('creates a session and a success attempt', () async {
      final repository = InMemorySessionRepository();
      final service = await _service(repository);
      final session =
          await service.onSignedIn(_user, signInMethod: 'email');
      expect(session, isNotNull);
      expect(session!.uid, 'uid-1');
      expect(session.signInMethod, 'email');
      expect(service.currentSessionId, session.id);
      final sessions = await service.loadSessions('uid-1');
      expect(sessions.map((s) => s.id), [session.id]);
      final attempts = await service.loadAttempts('uid-1');
      expect(attempts.length, 1);
      expect(attempts.first.success, isTrue);
      service.dispose();
    });

    test('no repository means no session, but sign-in is unaffected',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SessionService(
        prefs: prefs,
        repository: null,
        locationLabelProvider: () async => null,
        deviceLabelProvider: () => 'Android phone',
      );
      final session =
          await service.onSignedIn(_user, signInMethod: 'email');
      expect(session, isNull);
      expect(service.currentSessionId, isNull);
      service.dispose();
    });

    test('a failed create stores no current id (never false-revokes)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SessionService(
        prefs: prefs,
        repository: _FailingRepository(),
        locationLabelProvider: () async => null,
        deviceLabelProvider: () => 'Android phone',
      );
      final session =
          await service.onSignedIn(_user, signInMethod: 'email');
      expect(session, isNull);
      expect(service.currentSessionId, isNull);
      service.dispose();
    });
  });

  group('failed attempts', () {
    test('queued failures flush into history after a later sign-in',
        () async {
      final repository = InMemorySessionRepository();
      final service = await _service(repository);
      await service.onSignInFailed(
        email: 'student@example.com',
        reason: 'wrong password',
      );
      await service.onSignInFailed(
        email: 'other@example.com',
        reason: 'wrong password',
      );
      await service.onSignedIn(_user, signInMethod: 'email');
      final attempts = await service.loadAttempts('uid-1');
      // One success + the one matching-email failure. The other
      // email's failure stays queued (different account).
      expect(attempts.length, 2);
      expect(
        attempts.where((a) => !a.success).map((a) => a.reason),
        ['wrong password'],
      );
      service.dispose();
    });

    test('known-user failures record directly', () async {
      final repository = InMemorySessionRepository();
      final service = await _service(repository);
      await service.recordKnownUserFailure(
        user: _user,
        reason: 'no account found',
        signInMethod: 'google',
      );
      final attempts = await service.loadAttempts('uid-1');
      expect(attempts.length, 1);
      expect(attempts.first.success, isFalse);
      expect(attempts.first.reason, 'no account found');
      expect(attempts.first.signInMethod, 'google');
      service.dispose();
    });
  });

  group('foreign sessions (login alert)', () {
    test('a second device fires the alert once, then is known', () async {
      final repository = InMemorySessionRepository();
      final notifyLog = <String>[];
      final foreignLog = <UserSession>[];
      final service = await _service(
        repository,
        notifyLog: notifyLog,
        foreignLog: foreignLog,
      );
      await service.onSignedIn(_user, signInMethod: 'email');
      // A sign-in from another device (a second session record).
      final foreign = UserSession(
        id: 'foreign-1',
        uid: 'uid-1',
        deviceLabel: 'Android tablet',
        platform: 'android',
        formFactor: 'tablet',
        signInMethod: 'email',
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
        locationLabel: 'Cabugao, Ilocos Sur',
      );
      await repository.createSession(foreign);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(foreignLog.map((s) => s.id), ['foreign-1']);
      expect(notifyLog.length, 1);
      expect(notifyLog.first, contains('New sign-in'));
      expect(notifyLog.first, contains('Android tablet'));
      expect(notifyLog.first, contains('Cabugao, Ilocos Sur'));
      // Touching the foreign session again does not re-alert.
      await repository.touchSession('foreign-1');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(foreignLog.length, 1);
      expect(notifyLog.length, 1);
      service.dispose();
    });
  });

  group('revocation', () {
    test('deleting the current session elsewhere fires onRevoked',
        () async {
      final repository = InMemorySessionRepository();
      var revoked = false;
      final service = await _service(
        repository,
        onRevokedFlag: () {
          revoked = true;
          return true;
        },
      );
      final session =
          await service.onSignedIn(_user, signInMethod: 'email');
      await repository.deleteSession(session!.id);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(revoked, isTrue);
      expect(service.currentSessionId, isNull);
      service.dispose();
    });

    test('restored session with a missing record is a revocation',
        () async {
      final repository = InMemorySessionRepository();
      final first = await _service(repository);
      final session =
          await first.onSignedIn(_user, signInMethod: 'email');
      first.dispose();
      // Another device revoked this one while the app was closed.
      await repository.deleteSession(session!.id);
      // A fresh service instance (app restart) with the same prefs.
      // onRestoredSession reports the revocation as its return
      // value (the onRevoked callback is only for the mid-session
      // watcher path).
      final prefs = await SharedPreferences.getInstance();
      final second = SessionService(
        prefs: prefs,
        repository: repository,
        locationLabelProvider: () async => null,
        deviceLabelProvider: () => 'Android phone',
      );
      expect(await second.onRestoredSession(_user), isTrue);
      // No replacement session was created for a revoked device.
      expect(await repository.listSessions('uid-1'), isEmpty);
      second.dispose();
    });

    test('restored session with a live record is adopted', () async {
      final repository = InMemorySessionRepository();
      final first = await _service(repository);
      final session =
          await first.onSignedIn(_user, signInMethod: 'email');
      first.dispose();
      final prefs = await SharedPreferences.getInstance();
      final second = SessionService(
        prefs: prefs,
        repository: repository,
        locationLabelProvider: () async => null,
        deviceLabelProvider: () => 'Android phone',
      );
      await second.onRestoredSession(_user);
      expect(second.currentSessionId, session!.id);
      second.dispose();
    });
  });

  group('secure-my-account and sign-out', () {
    test('secureAccount revokes the foreign session and flags the account',
        () async {
      final repository = InMemorySessionRepository();
      final service = await _service(repository);
      final own =
          await service.onSignedIn(_user, signInMethod: 'email');
      final foreign = UserSession(
        id: 'foreign-1',
        uid: 'uid-1',
        deviceLabel: 'Web browser',
        platform: 'web',
        formFactor: 'desktop',
        signInMethod: 'email',
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
      );
      await repository.createSession(foreign);
      await service.secureAccount(foreignSession: foreign, uid: 'uid-1');
      final sessions = await service.loadSessions('uid-1');
      expect(sessions.map((s) => s.id), [own!.id]);
      expect(await service.isPasswordChangeRequired('uid-1'), isTrue);
      await service.clearPasswordChangeRequired('uid-1');
      expect(await service.isPasswordChangeRequired('uid-1'), isFalse);
      service.dispose();
    });

    test('revokeAllOtherSessions keeps only this device', () async {
      final repository = InMemorySessionRepository();
      final service = await _service(repository);
      final own =
          await service.onSignedIn(_user, signInMethod: 'email');
      for (final id in ['f1', 'f2']) {
        await repository.createSession(UserSession(
          id: id,
          uid: 'uid-1',
          deviceLabel: 'Web browser',
          platform: 'web',
          formFactor: 'desktop',
          signInMethod: 'email',
          createdAt: DateTime.now(),
          lastActiveAt: DateTime.now(),
        ));
      }
      await service.revokeAllOtherSessions('uid-1');
      final sessions = await service.loadSessions('uid-1');
      expect(sessions.map((s) => s.id), [own!.id]);
      service.dispose();
    });

    test('signOutCurrent deletes the record and signs out of auth',
        () async {
      final repository = InMemorySessionRepository();
      final service = await _service(repository);
      final session =
          await service.onSignedIn(_user, signInMethod: 'email');
      var authSignedOut = false;
      await service.signOutCurrent(signOutAuth: () async {
        authSignedOut = true;
      });
      expect(authSignedOut, isTrue);
      expect(await repository.getSession(session!.id), isNull);
      expect(service.currentSessionId, isNull);
      service.dispose();
    });
  });
}

class _FailingRepository extends InMemorySessionRepository {
  @override
  Future<void> createSession(UserSession session) async {
    throw Exception('Simulated Firestore failure.');
  }
}
