// Widget tests for the Login Alerts + Session Manager screens
// (no Firebase, no device): Security Center lists sessions with
// the CURRENT badge and per-session log-out, and Login History
// renders date-grouped attempts with SUCCESS/FAILED pills.
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/security/login_alert_dialog.dart';
import 'package:estudyantego/features/security/login_history_screen.dart';
import 'package:estudyantego/features/security/security_center_screen.dart';
import 'package:estudyantego/features/security/session_models.dart';
import 'package:estudyantego/features/security/session_repository.dart';
import 'package:estudyantego/features/security/session_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

const _user = AuthUser(
  uid: 'uid-1',
  email: 'student@example.com',
  displayName: 'Test Student',
  emailVerified: true,
);

Future<SessionService> _signedInService(
  InMemorySessionRepository repository,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final service = SessionService(
    prefs: prefs,
    repository: repository,
    locationLabelProvider: () async => null,
    deviceLabelProvider: () => 'Android phone',
  );
  await service.onSignedIn(_user, signInMethod: 'email');
  return service;
}

/// Service without a sign-in: for Login History, where the test records
/// its own attempts and a helper sign-in would add a fourth one.
Future<SessionService> _historyService(
  InMemorySessionRepository repository,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return SessionService(
    prefs: prefs,
    repository: repository,
    locationLabelProvider: () async => null,
    deviceLabelProvider: () => 'Android phone',
  );
}

UserSession _foreignSession({
  required String id,
  required String deviceLabel,
  String? locationLabel,
  DateTime? at,
}) {
  final now = at ?? DateTime.now();
  return UserSession(
    id: id,
    uid: 'uid-1',
    deviceLabel: deviceLabel,
    platform: 'android',
    formFactor: 'phone',
    signInMethod: 'email',
    createdAt: now,
    lastActiveAt: now,
    locationLabel: locationLabel,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecurityCenterScreen', () {
    testWidgets('shows this device with CURRENT and others with Log out', (
      tester,
    ) async {
      final repository = InMemorySessionRepository();
      final service = await _signedInService(repository);
      await repository.createSession(
        _foreignSession(
          id: 'foreign-1',
          deviceLabel: 'Android tablet',
          locationLabel: 'Cabugao, Ilocos Sur',
        ),
      );
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SecurityCenterScreen(
            sessionService: service,
            user: _user,
            authService: FakeAuthService(user: _user),
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Security Center'), findsOneWidget);
      expect(find.text('Android phone'), findsOneWidget);
      expect(find.text('CURRENT'), findsOneWidget);
      expect(find.text('Android tablet'), findsOneWidget);
      expect(find.text('Cabugao, Ilocos Sur'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
      expect(find.text('Log out all other devices'), findsOneWidget);
    });

    testWidgets('logging out a session removes it from the list', (
      tester,
    ) async {
      final repository = InMemorySessionRepository();
      final service = await _signedInService(repository);
      await repository.createSession(
        _foreignSession(id: 'foreign-1', deviceLabel: 'Android tablet'),
      );
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SecurityCenterScreen(
            sessionService: service,
            user: _user,
            authService: FakeAuthService(user: _user),
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      // Confirm dialog.
      expect(find.text('Log out this device?'), findsOneWidget);
      await tester.tap(find.text('Log out').last);
      await tester.pumpAndSettle();

      expect(find.text('Android tablet'), findsNothing);
      expect(find.text('Android phone'), findsOneWidget);
      expect(find.text('Log out all other devices'), findsOneWidget);
    });

    testWidgets('password-change banner appears when flagged', (tester) async {
      final repository = InMemorySessionRepository();
      final service = await _signedInService(repository);
      await repository.setPasswordChangeRequired('uid-1', true);
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SecurityCenterScreen(
            sessionService: service,
            user: _user,
            authService: FakeAuthService(user: _user),
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Password change required'), findsOneWidget);
      expect(find.text('Send reset link'), findsOneWidget);
    });
  });

  group('LoginHistoryScreen', () {
    testWidgets('groups attempts by day with SUCCESS/FAILED pills', (
      tester,
    ) async {
      final repository = InMemorySessionRepository();
      final service = await _historyService(repository);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await repository.recordAttempt(
        LoginAttempt(
          id: 'a1',
          uid: 'uid-1',
          success: true,
          reason: '',
          deviceLabel: 'Android phone',
          platform: 'android',
          signInMethod: 'email',
          createdAt: today.add(const Duration(hours: 22, minutes: 24)),
        ),
      );
      await repository.recordAttempt(
        LoginAttempt(
          id: 'a2',
          uid: 'uid-1',
          success: false,
          reason: 'wrong password',
          deviceLabel: 'Web browser',
          platform: 'web',
          signInMethod: 'email',
          createdAt: today.add(const Duration(hours: 21, minutes: 58)),
        ),
      );
      await repository.recordAttempt(
        LoginAttempt(
          id: 'a3',
          uid: 'uid-1',
          success: true,
          reason: '',
          deviceLabel: 'Android phone',
          platform: 'android',
          signInMethod: 'google',
          createdAt: today.subtract(const Duration(hours: 3)),
        ),
      );
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: LoginHistoryScreen(sessionService: service, user: _user),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Login History'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('YESTERDAY'), findsOneWidget);
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text('Signed in with Google'), findsOneWidget);
      expect(find.text('Failed sign-in — wrong password'), findsOneWidget);
      expect(find.text('SUCCESS'), findsNWidgets(2));
      expect(find.text('FAILED'), findsOneWidget);
      // The footer button sits below the fold on the default test
      // surface: scroll it into view like a real user would.
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(find.text('Open Security Center'), findsOneWidget);
    });
  });

  group('showLoginAlertDialog', () {
    testWidgets('Yes and No return the matching choice', (tester) async {
      final session = _foreignSession(
        id: 'foreign-1',
        deviceLabel: 'Android tablet',
        locationLabel: 'Vigan City, Ilocos Sur',
      );
      LoginAlertChoice? choice;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  choice = await showLoginAlertDialog(
                    context: context,
                    session: session,
                  );
                },
                child: const Text('Show alert'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Show alert'));
      await tester.pumpAndSettle();

      expect(
        find.text('New sign-in to your EstudyanteGO account'),
        findsOneWidget,
      );
      expect(find.text('Android tablet · EstudyanteGO app'), findsOneWidget);
      expect(find.text('Vigan City, Ilocos Sur'), findsOneWidget);
      await tester.tap(find.text('Yes, that was me'));
      await tester.pumpAndSettle();
      expect(choice, LoginAlertChoice.yesThatWasMe);

      await tester.tap(find.text('Show alert'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No, secure my account'));
      await tester.pumpAndSettle();
      expect(choice, LoginAlertChoice.noSecureMyAccount);
    });
  });
}
