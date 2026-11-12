// Widget tests for the Sign In screen's session hooks (no
// Firebase, no device): a successful email sign-in creates a
// session record + success attempt, a failed sign-in is queued and
// flushed into Login History after the next successful sign-in,
// and the Google login-only gate's rejection is recorded as a
// failed attempt for the known UID.
import 'package:estudyantego/features/onboarding/auth_screen.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/security/session_repository.dart';
import 'package:estudyantego/features/security/session_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthService fake;
  late InMemorySessionRepository repository;
  late SessionService service;
  AuthUser? signedInUser;

  Future<void> pumpSignIn(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(
          service: fake,
          onSignedIn: (user) => signedInUser = user,
          onCreateAccountRequested: () {},
          sessionService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> signInWith(
    WidgetTester tester, {
    required String email,
    required String password,
  }) async {
    await tester.enterText(
      find.byType(TextField).at(0),
      email,
    );
    await tester.enterText(
      find.byType(TextField).at(1),
      password,
    );
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    fake = FakeAuthService();
    repository = InMemorySessionRepository();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = SessionService(
      prefs: prefs,
      repository: repository,
      locationLabelProvider: () async => null,
      deviceLabelProvider: () => 'Android phone',
    );
    signedInUser = null;
    addTearDown(service.dispose);
  });

  testWidgets('email sign-in creates a session and a success attempt',
      (tester) async {
    await fake.createAccount(
      email: 'student@example.com',
      password: 'secret123',
      displayName: 'Test Student',
    );
    await fake.signOut();
    await pumpSignIn(tester);
    await signInWith(
      tester,
      email: 'student@example.com',
      password: 'secret123',
    );

    expect(signedInUser, isNotNull);
    final sessions = await repository.listSessions(signedInUser!.uid);
    expect(sessions.length, 1);
    expect(sessions.first.deviceLabel, 'Android phone');
    expect(sessions.first.signInMethod, 'email');
    final attempts = await repository.listAttempts(signedInUser!.uid);
    expect(attempts.length, 1);
    expect(attempts.first.success, isTrue);
  });

  testWidgets(
      'failed sign-in is queued, then flushed after the next success',
      (tester) async {
    await fake.createAccount(
      email: 'student@example.com',
      password: 'secret123',
      displayName: 'Test Student',
    );
    await fake.signOut();
    await pumpSignIn(tester);

    // Wrong password: the screen shows the error and queues the
    // failure (no UID is known yet, so nothing is in history).
    await signInWith(
      tester,
      email: 'student@example.com',
      password: 'wrong-password',
    );
    expect(find.text('Incorrect email or password.'), findsOneWidget);
    expect(signedInUser, isNull);

    // Correct password: sign-in succeeds and the queued failure
    // lands in Login History alongside the success.
    await signInWith(
      tester,
      email: 'student@example.com',
      password: 'secret123',
    );
    expect(signedInUser, isNotNull);
    final attempts = await repository.listAttempts(signedInUser!.uid);
    expect(attempts.length, 2);
    expect(
      attempts.where((a) => !a.success).map((a) => a.reason),
      ['sign-in failed'],
    );
    expect(attempts.where((a) => a.success).length, 1);
  });

  testWidgets('Google no-account rejection is recorded as a failure',
      (tester) async {
    fake.googleUser = const AuthUser(
      uid: 'google-unknown-uid',
      email: 'ana@example.com',
      displayName: 'Ana Santos',
      emailVerified: true,
    );
    await pumpSignIn(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(signedInUser, isNull);
    expect(fake.signOutCount, 1);
    expect(find.text(noAccountFoundMessage), findsOneWidget);
    final attempts =
        await repository.listAttempts('google-unknown-uid');
    expect(attempts.length, 1);
    expect(attempts.first.success, isFalse);
    expect(attempts.first.reason, 'no account found');
    expect(attempts.first.signInMethod, 'google');
  });
}
