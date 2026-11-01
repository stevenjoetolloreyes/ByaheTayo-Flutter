// Shared fakes for the onboarding/auth/account tests.
//
// No real Firebase, no real permission dialogs: FakeAuthService keeps an
// in-memory user registry (email -> password, verified flag, display
// name) and FakePermissionService keeps an in-memory notification
// status. Both implement the production interfaces exactly, so the
// screens under test exercise their real code paths.
import 'dart:async';

import 'package:byahetayo/features/onboarding/auth_service.dart';
import 'package:byahetayo/features/onboarding/permission_service.dart';

class _Record {
  _Record(this.password, this.displayName, this.verified);
  String password;
  String displayName;
  bool verified;
}

class FakeAuthService implements AuthService {
  FakeAuthService({AuthUser? user, this.configured = true}) {
    if (user != null) {
      _user = user;
      _records[user.email] =
          _Record('', user.displayName ?? '', user.emailVerified);
    }
  }

  final bool configured;

  @override
  bool get isConfigured => configured;

  AuthUser? _user;
  final Map<String, _Record> _records = {};
  final List<String> resetEmailsSent = [];
  bool verificationEmailSent = false;
  int signOutCount = 0;

  final _controller = StreamController<AuthUser?>.broadcast();

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  void _checkConfigured() {
    if (!configured) throw const AuthNotConfiguredException();
  }

  /// Marks the current user verified, as if they clicked the email link.
  void markCurrentUserVerified() {
    final user = _user;
    if (user == null) return;
    _user = user.copyWith(emailVerified: true);
    _records[user.email]?.verified = true;
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    _checkConfigured();
    final record = _records[email];
    if (record == null || record.password != password) {
      throw const AuthException('Incorrect email or password.');
    }
    _user = AuthUser(
      uid: 'uid-${email.hashCode}',
      email: email,
      displayName: record.displayName,
      emailVerified: record.verified,
    );
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<AuthUser> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _checkConfigured();
    if (_records.containsKey(email)) {
      throw const AuthException('That email is already registered.');
    }
    _records[email] = _Record(password, displayName, false);
    _user = AuthUser(
      uid: 'uid-${email.hashCode}',
      email: email,
      displayName: displayName,
      emailVerified: false,
    );
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    _checkConfigured();
    resetEmailsSent.add(email);
  }

  @override
  Future<void> sendEmailVerification() async {
    _checkConfigured();
    if (_user == null) {
      throw const AuthException('No account signed in.');
    }
    verificationEmailSent = true;
  }

  @override
  Future<AuthUser?> reloadUser() async {
    _checkConfigured();
    return _user;
  }

  @override
  Future<void> signOut() async {
    _checkConfigured();
    _user = null;
    signOutCount++;
    _controller.add(null);
  }
}

class FakePermissionService implements PermissionService {
  FakePermissionService({
    NotificationPermissionStatus initial =
        NotificationPermissionStatus.denied,
    this.requestResult = NotificationPermissionStatus.granted,
  }) : _status = initial;

  NotificationPermissionStatus _status;
  final NotificationPermissionStatus requestResult;
  int requestCount = 0;
  int settingsOpenedCount = 0;

  @override
  Future<NotificationPermissionStatus> notificationStatus() async =>
      _status;

  @override
  Future<NotificationPermissionStatus> requestNotification() async {
    requestCount++;
    _status = requestResult;
    return _status;
  }

  @override
  Future<void> openAppSettings() async {
    settingsOpenedCount++;
  }
}
