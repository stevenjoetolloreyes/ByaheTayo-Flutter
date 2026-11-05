// Tests for the first-time installation experience: splash,
// onboarding, auth screens, email verification, profile setup,
// notification prompt, admin allowlist, Communities gating, and the
// premium Account tab states.
//
// All auth/permission behavior goes through the fakes in
// test_fakes.dart — no real Firebase config is ever required.
import 'package:estudyantego/features/account_tab.dart';
import 'package:estudyantego/features/admin_access.dart';
import 'package:estudyantego/features/communities_tab.dart';
import 'package:estudyantego/features/onboarding/auth_screen.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/onboarding/entry_theme.dart';
import 'package:estudyantego/features/onboarding/notification_prompt.dart';
import 'package:estudyantego/features/onboarding/onboarding_screen.dart';
import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:estudyantego/features/onboarding/permission_service.dart';
import 'package:estudyantego/features/onboarding/profile_setup_screen.dart';
import 'package:estudyantego/features/onboarding/splash_screen.dart';
import 'package:estudyantego/features/onboarding/verify_email_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

const _verifiedUser = AuthUser(
  uid: 'uid-1',
  email: 'steven@example.com',
  displayName: 'Steven Reyes',
  emailVerified: true,
);
const _unverifiedUser = AuthUser(
  uid: 'uid-1',
  email: 'steven@example.com',
  displayName: 'Steven Reyes',
  emailVerified: false,
);

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

/// Finds a TextField by its InputDecoration label (labels render as
/// decorated text, not as a TextField descendant with exact text).
Finder _fieldByLabel(String label) => find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == label,
    );

/// Taps a widget that may sit below the fold in a scroll view.
Future<void> _tapVisible(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('resolveStartDestination', () {
    test('onboarding first, regardless of everything else', () {
      expect(
        resolveStartDestination(
          firebaseConfigured: true,
          onboardingDone: false,
          user: _verifiedUser,
          profileSetupDone: true,
        ),
        AppStartDestination.onboarding,
      );
    });

    test('unconfigured Firebase skips auth (legacy dashboard fallback)', () {
      expect(
        resolveStartDestination(
          firebaseConfigured: false,
          onboardingDone: true,
          user: null,
          profileSetupDone: false,
        ),
        AppStartDestination.dashboard,
      );
    });

    test('configured, no session -> sign in', () {
      expect(
        resolveStartDestination(
          firebaseConfigured: true,
          onboardingDone: true,
          user: null,
          profileSetupDone: false,
        ),
        AppStartDestination.signIn,
      );
    });

    test('signed in but unverified -> verify email', () {
      expect(
        resolveStartDestination(
          firebaseConfigured: true,
          onboardingDone: true,
          user: _unverifiedUser,
          profileSetupDone: false,
        ),
        AppStartDestination.verifyEmail,
      );
    });

    test('verified but profile incomplete -> profile setup', () {
      expect(
        resolveStartDestination(
          firebaseConfigured: true,
          onboardingDone: true,
          user: _verifiedUser,
          profileSetupDone: false,
        ),
        AppStartDestination.profileSetup,
      );
    });

    test('verified + profile complete -> dashboard', () {
      expect(
        resolveStartDestination(
          firebaseConfigured: true,
          onboardingDone: true,
          user: _verifiedUser,
          profileSetupDone: true,
        ),
        AppStartDestination.dashboard,
      );
    });
  });

  group('ProfileStore keys', () {
    test('onboarding flag, per-uid profile, per-uid setup flag', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      expect(store.onboardingDone, isFalse);
      await store.markOnboardingDone();
      expect(store.onboardingDone, isTrue);

      const profile = UserProfile(
        displayName: 'Steven Reyes',
        email: 'steven@example.com',
        school: 'University of Northern Philippines',
        program: 'Diploma in Computer Technology',
      );
      await store.saveProfile('uid-1', profile);
      // Saving the JSON alone does not mark setup done; the setup
      // screen marks it when the user completes the flow.
      expect(store.isProfileSetupDone('uid-1'), isFalse);
      await store.markProfileSetupDone('uid-1');
      expect(store.isProfileSetupDone('uid-1'), isTrue);
      expect(store.isProfileSetupDone('uid-2'), isFalse);
      final loaded = store.loadProfile('uid-1');
      expect(loaded?.displayName, 'Steven Reyes');
      expect(loaded?.school, 'University of Northern Philippines');
      expect(loaded?.hasStudentInfo, isTrue);
      expect(store.loadProfile('uid-2'), isNull);

      // Exact keys, additive only (no existing key is touched).
      expect(prefs.getBool('byahetayo_onboarding_done'), isTrue);
      expect(prefs.getBool('byahetayo_profile_setup_done_uid-1'), isTrue);
      expect(prefs.getString('byahetayo_profile_uid-1'), contains('Steven'));
    });

    test('school field migrates to the flat calendar contract key', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);

      // Saving a profile writes the flat key the School Calendar reads.
      await store.saveProfile(
        'uid-1',
        const UserProfile(
          displayName: 'Steven Reyes',
          email: 'steven@example.com',
          school: 'University of Northern Philippines',
        ),
      );
      expect(
        prefs.getString('byahetayo_profile_school'),
        'University of Northern Philippines',
      );
      expect(store.loadProfile('uid-1')?.school,
          'University of Northern Philippines');

      // Flat key wins over a stale school inside the JSON.
      await prefs.setString('byahetayo_profile_school', 'Ilocos Sur NHS');
      expect(store.loadProfile('uid-1')?.school, 'Ilocos Sur NHS');

      // Clearing the school clears the flat key (empty is valid).
      await store.saveProfile(
        'uid-1',
        const UserProfile(
          displayName: 'Steven Reyes',
          email: 'steven@example.com',
        ),
      );
      expect(prefs.getString('byahetayo_profile_school'), '');
      expect(store.loadProfile('uid-1')?.school, isNull);

      // Absent flat key (written before the contract existed) keeps
      // the JSON value until the next save migrates it.
      await prefs.remove('byahetayo_profile_school');
      await store.saveProfile(
        'uid-1',
        const UserProfile(
          displayName: 'Steven Reyes',
          email: 'steven@example.com',
          school: 'Old School Name',
        ),
      );
      await prefs.remove('byahetayo_profile_school');
      expect(store.loadProfile('uid-1')?.school, 'Old School Name');
    });

    test('UNP normalization rule for the School Calendar', () {
      expect(isUniversityOfNorthernPhilippines('UNP'), isTrue);
      expect(isUniversityOfNorthernPhilippines('  unp  '), isTrue);
      expect(isUniversityOfNorthernPhilippines('My UNP campus'), isTrue);
      expect(
        isUniversityOfNorthernPhilippines(
            'University of Northern Philippines'),
        isTrue,
      );
      expect(
        isUniversityOfNorthernPhilippines(
            '  University Of Northern Philippines  '),
        isTrue,
      );
      expect(isUniversityOfNorthernPhilippines('Ilocos Sur NHS'), isFalse);
      expect(isUniversityOfNorthernPhilippines(''), isFalse);
      expect(isUniversityOfNorthernPhilippines(null), isFalse);
    });

    test('notification prompt flag is independent and sticky', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      expect(store.notificationPromptShown, isFalse);
      await store.markNotificationPromptShown();
      expect(store.notificationPromptShown, isTrue);
      expect(prefs.getBool('byahetayo_notification_prompt_shown'), isTrue);
    });

    test('profile initials and empty-info helpers', () {
      expect(
        const UserProfile(displayName: 'Steven Reyes', email: 's@e.com')
            .initials,
        'SR',
      );
      expect(
        const UserProfile(displayName: 'Steven', email: 's@e.com').initials,
        'S',
      );
      expect(
        const UserProfile(displayName: '', email: 's@e.com').hasStudentInfo,
        isFalse,
      );
      expect(
        const UserProfile(
          displayName: 'S',
          email: 's@e.com',
          jobTitle: 'Developer',
        ).hasEmploymentInfo,
        isTrue,
      );
    });
  });

  group('FakeAuthService', () {
    test('create -> sign out -> sign in round trip', () async {
      final auth = FakeAuthService();
      final created = await auth.createAccount(
        email: 'a@b.com',
        password: 'secret1',
        displayName: 'Ana',
      );
      expect(created.emailVerified, isFalse);
      await auth.signOut();
      expect(auth.currentUser, isNull);
      final signedIn = await auth.signIn(email: 'a@b.com', password: 'secret1');
      expect(signedIn.displayName, 'Ana');
    });

    test('wrong password and duplicate registration throw', () async {
      final auth = FakeAuthService();
      await auth.createAccount(
        email: 'a@b.com',
        password: 'secret1',
        displayName: 'Ana',
      );
      await expectLater(
        auth.signIn(email: 'a@b.com', password: 'nope'),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        auth.createAccount(
          email: 'a@b.com',
          password: 'secret1',
          displayName: 'Ana',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('not-configured service throws AuthNotConfiguredException', () async {
      final auth = FakeAuthService(configured: false);
      await expectLater(
        auth.signIn(email: 'a@b.com', password: 'secret1'),
        throwsA(isA<AuthNotConfiguredException>()),
      );
      await expectLater(
        auth.createAccount(
          email: 'a@b.com',
          password: 'secret1',
          displayName: 'Ana',
        ),
        throwsA(isA<AuthNotConfiguredException>()),
      );
      await expectLater(
        auth.sendPasswordReset(email: 'a@b.com'),
        throwsA(isA<AuthNotConfiguredException>()),
      );
    });

    test('password reset and verification are recorded', () async {
      final auth = FakeAuthService(user: _unverifiedUser);
      await auth.sendPasswordReset(email: 'steven@example.com');
      expect(auth.resetEmailsSent, ['steven@example.com']);
      await auth.sendEmailVerification();
      expect(auth.verificationEmailSent, isTrue);
      auth.markCurrentUserVerified();
      final reloaded = await auth.reloadUser();
      expect(reloaded?.emailVerified, isTrue);
    });
  });

  group('SplashScreen', () {
    testWidgets('renders branding and hands off exactly once',
        (WidgetTester tester) async {
      AppStartDestination? handed;
      var calls = 0;
      await tester.pumpWidget(_wrap(
        SplashScreen(
          resolve: () async => AppStartDestination.dashboard,
          onDestination: (next) {
            handed = next;
            calls++;
          },
        ),
      ));
      expect(find.text('EstudyanteGO'), findsOneWidget);
      expect(find.text('Your Student Companion'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(handed, AppStartDestination.dashboard);
      expect(calls, 1);
    });
  });

  group('OnboardingScreen', () {
    testWidgets('pages, Skip, Next, Get Started, Sign In',
        (WidgetTester tester) async {
      var gotStarted = false;
      var signedIn = false;
      await tester.pumpWidget(_wrap(
        OnboardingScreen(
          onGetStarted: () => gotStarted = true,
          onSignIn: () => signedIn = true,
        ),
      ));
      expect(find.text('Explore the Map'), findsOneWidget);
      expect(find.text('Get Started'), findsNothing);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(signedIn, isTrue);

      // Fresh screen: Next walks pages 0 -> 3.
      signedIn = false;
      await tester.pumpWidget(_wrap(
        OnboardingScreen(
          onGetStarted: () => gotStarted = true,
          onSignIn: () => signedIn = true,
        ),
      ));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Plan Your Trip'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Know Your Fare'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Community Updates'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      // Skip stays visible on every screen, including the last one,
      // and routes to the existing sign-in flow.
      expect(find.text('Skip'), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(signedIn, isTrue);

      await tester.tap(find.text('Get Started'));
      expect(gotStarted, isTrue);
    });
  });

  group('AuthScreen', () {
    testWidgets('sign-in success calls onSignedIn',
        (WidgetTester tester) async {
      final auth = FakeAuthService();
      await auth.createAccount(
        email: 'a@b.com',
        password: 'secret1',
        displayName: 'Ana',
      );
      await auth.signOut();
      AuthUser? signedIn;
      await tester.pumpWidget(_wrap(
        AuthScreen(
          service: auth,
          initialMode: AuthMode.signIn,
          onSignedIn: (user) => signedIn = user,
          onAccountCreated: (_) {},
        ),
      ));
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'a@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'secret1',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pumpAndSettle();
      expect(signedIn?.email, 'a@b.com');
    });

    testWidgets('wrong password shows the error, stays on screen',
        (WidgetTester tester) async {
      final auth = FakeAuthService();
      await auth.createAccount(
        email: 'a@b.com',
        password: 'secret1',
        displayName: 'Ana',
      );
      await auth.signOut();
      await tester.pumpWidget(_wrap(
        AuthScreen(
          service: auth,
          initialMode: AuthMode.signIn,
          onSignedIn: (_) {},
          onAccountCreated: (_) {},
        ),
      ));
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'a@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'wrong',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pumpAndSettle();
      expect(find.text('Incorrect email or password.'), findsOneWidget);
      expect(find.text('Welcome Back'), findsOneWidget);
    });

    testWidgets('create-account mode creates and calls onAccountCreated',
        (WidgetTester tester) async {
      final auth = FakeAuthService();
      AuthUser? created;
      await tester.pumpWidget(_wrap(
        AuthScreen(
          service: auth,
          initialMode: AuthMode.createAccount,
          onSignedIn: (_) {},
          onAccountCreated: (user) => created = user,
        ),
      ));
      await tester.enterText(
        find.widgetWithText(TextField, 'Full name'),
        'Ana',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'ana@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'secret1',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pumpAndSettle();
      expect(created?.email, 'ana@b.com');
      expect(created?.emailVerified, isFalse);
    });

    testWidgets('forgot password sends a reset email',
        (WidgetTester tester) async {
      final auth = FakeAuthService();
      await tester.pumpWidget(_wrap(
        AuthScreen(
          service: auth,
          initialMode: AuthMode.signIn,
          onSignedIn: (_) {},
          onAccountCreated: (_) {},
        ),
      ));
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      // The dialog's Email field, not the sign-in screen's field
      // underneath it.
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextField, 'Email'),
        ),
        'a@b.com',
      );
      await tester.tap(find.text('Send link'));
      await tester.pumpAndSettle();
      expect(auth.resetEmailsSent, ['a@b.com']);
      expect(
        find.text('Password reset link sent. Check your email.'),
        findsOneWidget,
      );
    });

    testWidgets('not-configured banner shows and submit is disabled',
        (WidgetTester tester) async {
      final auth = FakeAuthService(configured: false);
      await tester.pumpWidget(_wrap(
        AuthScreen(
          service: auth,
          initialMode: AuthMode.signIn,
          onSignedIn: (_) {},
          onAccountCreated: (_) {},
        ),
      ));
      expect(find.textContaining('Firebase is not configured yet'),
          findsOneWidget);
      final button =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Sign In'));
      expect(button.onPressed, isNull);
    });
  });

  group('VerifyEmailScreen', () {
    testWidgets('send, re-check after verification, escape hatch',
        (WidgetTester tester) async {
      final auth = FakeAuthService(user: _unverifiedUser);
      var verified = false;
      var escaped = false;
      await tester.pumpWidget(_wrap(
        VerifyEmailScreen(
          service: auth,
          user: _unverifiedUser,
          onVerified: (_) => verified = true,
          onUseDifferentAccount: () => escaped = true,
        ),
      ));
      expect(find.text('Verify your email'), findsOneWidget);
      // The email sits inside a longer sentence on this screen.
      expect(find.textContaining('steven@example.com'), findsOneWidget);

      await tester.tap(find.text('Send verification email'));
      await tester.pumpAndSettle();
      expect(auth.verificationEmailSent, isTrue);
      expect(find.text('Verification email sent. Check your inbox.'),
          findsOneWidget);

      // Not verified yet: re-check keeps the user on screen.
      await tester.tap(find.text("I've verified — check again"));
      await tester.pumpAndSettle();
      expect(verified, isFalse);

      auth.markCurrentUserVerified();
      await tester.tap(find.text("I've verified — check again"));
      await tester.pumpAndSettle();
      expect(verified, isTrue);

      // Snackbars queue ('Verification email sent', then
      // 'Not verified yet') and the overlay sits over the bottom
      // button; clear current + queued snackbars before tapping it.
      ScaffoldMessenger.of(
        tester.element(find.text('Use a different account')),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use a different account'));
      await tester.pumpAndSettle();
      expect(escaped, isTrue);
      expect(auth.currentUser, isNull);
    });
  });

  group('ProfileSetupScreen', () {
    testWidgets('saves required + optional fields under the uid keys',
        (WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      UserProfile? saved;
      await tester.pumpWidget(_wrap(
        ProfileSetupScreen(
          user: _verifiedUser,
          store: store,
          onSaved: (profile) => saved = profile,
        ),
      ));
      expect(find.text('Set up your profile'), findsOneWidget);
      // Email is read-only, name prefilled from the Firebase user.
      expect(_fieldByLabel('Full name *'), findsOneWidget);

      // School: searchable dropdown, select the listed UNP entry.
      await tester.ensureVisible(_fieldByLabel('School'));
      await tester.pumpAndSettle();
      await tester.tap(_fieldByLabel('School'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('dropdown-search')),
        'northern',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('University of Northern Philippines'));
      await tester.pumpAndSettle();
      // Program: not a listed program, so it goes through manual entry.
      await tester.ensureVisible(_fieldByLabel('Program / course'));
      await tester.pumpAndSettle();
      await tester.tap(_fieldByLabel('Program / course'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other / Enter manually'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _fieldByLabel('Enter program / course'),
        'Diploma in Computer Technology',
      );
      await tester.enterText(
        _fieldByLabel('Job title'),
        'Student',
      );
      // The form is taller than the default viewport; scroll first.
      await _tapVisible(tester, 'Continue');

      expect(saved?.displayName, 'Steven Reyes');
      expect(saved?.school, 'University of Northern Philippines');
      expect(saved?.program, 'Diploma in Computer Technology');
      expect(saved?.jobTitle, 'Student');
      expect(store.isProfileSetupDone('uid-1'), isTrue);
      expect(
        prefs.getString('byahetayo_profile_uid-1'),
        contains('University of Northern Philippines'),
      );
      // The save also writes the flat calendar contract key.
      expect(
        prefs.getString('byahetayo_profile_school'),
        'University of Northern Philippines',
      );
    });

    testWidgets('empty name blocks save', (WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      var saved = false;
      await tester.pumpWidget(_wrap(
        ProfileSetupScreen(
          user: const AuthUser(
            uid: 'uid-9',
            email: 'noname@example.com',
            emailVerified: true,
          ),
          store: store,
          onSaved: (_) => saved = true,
        ),
      ));
      await tester.enterText(
        _fieldByLabel('Full name *'),
        '',
      );
      await _tapVisible(tester, 'Continue');
      expect(saved, isFalse);
      expect(store.isProfileSetupDone('uid-9'), isFalse);
    });
  });

  group('Notification prompt', () {
    testWidgets('Allow requests and returns true; Not now returns false',
        (WidgetTester tester) async {
      final permissions = FakePermissionService();
      var allowResult = false;
      var notNowResult = true;
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () async {
                  allowResult = await showNotificationPermissionPrompt(
                    context,
                    permissions,
                  );
                },
                child: const Text('Prompt A'),
              ),
              TextButton(
                onPressed: () async {
                  notNowResult = await showNotificationPermissionPrompt(
                    context,
                    permissions,
                  );
                },
                child: const Text('Prompt B'),
              ),
            ],
          ),
        ),
      ));
      await tester.tap(find.text('Prompt A'));
      await tester.pumpAndSettle();
      expect(find.text('Stay updated?'), findsOneWidget);
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(allowResult, isTrue);
      expect(permissions.requestCount, 1);

      await tester.tap(find.text('Prompt B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(notNowResult, isFalse);
    });
  });

  group('Admin allowlist', () {
    test('exactly the two allowlisted emails, case-insensitive', () {
      expect(isAdminEmail('stevenjoereyes0625@gmail.com'), isTrue);
      expect(isAdminEmail('stevenjoereyes23@gmail.com'), isTrue);
      expect(isAdminEmail('StevenJoeReyes0625@Gmail.com'), isTrue);
      expect(isAdminEmail('  stevenjoereyes23@gmail.com  '), isTrue);
      expect(isAdminEmail('stevenjoereyes24@gmail.com'), isFalse);
      expect(isAdminEmail('admin@byahetayo.app'), isFalse);
      expect(isAdminEmail(null), isFalse);
      expect(isAdminEmail(''), isFalse);
    });

    test('isAdminUser reads the auth email, never the profile', () {
      expect(isAdminUser(_verifiedUser), isFalse);
      expect(
        isAdminUser(const AuthUser(
          uid: 'u',
          email: 'stevenjoereyes23@gmail.com',
          emailVerified: true,
        )),
        isTrue,
      );
      expect(isAdminUser(null), isFalse);
    });

    testWidgets('Communities shows admin actions only to admins',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const CommunitiesTab(
          currentUser: AuthUser(
            uid: 'u',
            email: 'stevenjoereyes0625@gmail.com',
            emailVerified: true,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Post approvals'), findsOneWidget);
      expect(find.text('LGU directory'), findsOneWidget);

      await tester.pumpWidget(_wrap(
        const CommunitiesTab(currentUser: _verifiedUser),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Post approvals'), findsNothing);
      expect(find.text('LGU directory'), findsNothing);

      await tester.pumpWidget(_wrap(const CommunitiesTab()));
      await tester.pumpAndSettle();
      expect(find.text('Post approvals'), findsNothing);
    });
  });

  group('Premium Account tab', () {
    Future<void> pumpAccount(
      WidgetTester tester, {
      AuthUser? user,
      UserProfile? profile,
      FakeAuthService? auth,
      FakePermissionService? permissions,
      VoidCallback? onSignedOut,
    }) async {
      await tester.pumpWidget(_wrap(
        AccountTab(
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          authService: auth ?? FakeAuthService(user: user),
          user: user,
          profile: profile,
          permissionService: permissions ?? FakePermissionService(),
          onSignedOut: onSignedOut ?? () {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('signed-in header: name, email, Verified badge, no Guest',
        (WidgetTester tester) async {
      await pumpAccount(tester, user: _verifiedUser);
      expect(find.text('Steven Reyes'), findsOneWidget);
      expect(find.text('steven@example.com'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Guest'), findsNothing);
    });

    testWidgets('unverified user gets a real Verify email action',
        (WidgetTester tester) async {
      final auth = FakeAuthService(user: _unverifiedUser);
      await pumpAccount(tester, user: _unverifiedUser, auth: auth);
      expect(find.text('Verified'), findsNothing);
      await tester.tap(find.text('Verify email'));
      await tester.pumpAndSettle();
      expect(auth.verificationEmailSent, isTrue);
    });

    testWidgets('wallet keeps the existing 0 balance + Earn Points',
        (WidgetTester tester) async {
      var viewedStudent = false;
      await tester.pumpWidget(_wrap(
        AccountTab(
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          authService: FakeAuthService(user: _verifiedUser),
          user: _verifiedUser,
          permissionService: FakePermissionService(),
          onViewStudent: () => viewedStudent = true,
          onSignedOut: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Points Wallet'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('points-balance'))).data,
        '0 points',
      );
      // The brand hero above the profile card makes the page taller,
      // so the wallet button can sit below the fold on small
      // surfaces: scroll it into view before tapping.
      await tester.ensureVisible(find.text('Earn Points'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Earn Points'));
      expect(viewedStudent, isTrue);
    });

    testWidgets('quick actions: student ID empty state + rewards',
        (WidgetTester tester) async {
      // Signed in with a profile that has no student info (student
      // info is optional), so the ID card shows its honest empty state.
      await pumpAccount(
        tester,
        user: _verifiedUser,
        profile: const UserProfile(
          displayName: 'Steven Reyes',
          email: 'steven@example.com',
        ),
      );
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('My Student ID'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('Rewards'), findsOneWidget);

      await _tapVisible(tester, 'My Student ID');
      expect(find.text('My Student ID'), findsWidgets);
      expect(find.text('No student info yet'), findsOneWidget);
      expect(find.text('Open Profile Setup'), findsOneWidget);
      expect(
        find.textContaining('does not issue student ID numbers'),
        findsOneWidget,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      await _tapVisible(tester, 'Rewards');
      expect(find.text('Rewards'), findsWidgets);
      expect(find.text('Your points'), findsOneWidget);
      expect(find.text('0 points'), findsWidgets);
      // Queue #2: the old 'How to earn' explainer now lives under
      // 'Daily Rewards', and 'Redemptions' became the full
      // 'Redemption History' section — same content, new titles.
      expect(find.text('Daily Rewards'), findsOneWidget);
      expect(find.textContaining('Day 1–6 earn 10 points'), findsOneWidget);
      expect(find.text('Open Student Hub'), findsOneWidget);
      expect(find.text('Redemption History'), findsOneWidget);
      expect(find.textContaining('No redemptions yet'),
          findsOneWidget);
    });

    testWidgets('student ID card renders real student info when present',
        (WidgetTester tester) async {
      const profile = UserProfile(
        displayName: 'Steven Reyes',
        email: 'steven@example.com',
        school: 'University of Northern Philippines',
        program: 'Diploma in Computer Technology',
        year: '1st Year',
      );
      await pumpAccount(tester, user: _verifiedUser, profile: profile);
      await _tapVisible(tester, 'My Student ID');
      expect(find.text('No student info yet'), findsNothing);
      expect(find.text('University of Northern Philippines'), findsOneWidget);
      expect(find.text('Diploma in Computer Technology'), findsOneWidget);
    });

    testWidgets('signed-out card has no Guest wording, has Sign In',
        (WidgetTester tester) async {
      var signInRequested = false;
      await tester.pumpWidget(_wrap(
        AccountTab(
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          authService: FakeAuthService(),
          user: null,
          permissionService: FakePermissionService(),
          onSignInRequested: () => signInRequested = true,
          onSignedOut: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No account signed in'), findsOneWidget);
      expect(find.text('Guest'), findsNothing);
      await tester.tap(find.text('Sign In'));
      expect(signInRequested, isTrue);
    });

    testWidgets('admin section renders only for allowlisted admins',
        (WidgetTester tester) async {
      await pumpAccount(
        tester,
        user: const AuthUser(
          uid: 'u',
          email: 'stevenjoereyes23@gmail.com',
          emailVerified: true,
        ),
      );
      expect(find.text('Post approvals'), findsOneWidget);
      expect(find.text('LGU directory'), findsOneWidget);

      await pumpAccount(tester, user: _verifiedUser);
      expect(find.text('Post approvals'), findsNothing);
    });

    testWidgets('sign out calls the service and the callback',
        (WidgetTester tester) async {
      final auth = FakeAuthService(user: _verifiedUser);
      var signedOut = false;
      await pumpAccount(
        tester,
        user: _verifiedUser,
        auth: auth,
        onSignedOut: () => signedOut = true,
      );
      await _tapVisible(tester, 'Sign Out');
      expect(auth.signOutCount, 1);
      expect(signedOut, isTrue);
    });

    testWidgets('notification row shows real status, not a dead toggle',
        (WidgetTester tester) async {
      final permissions = FakePermissionService(
        initial: NotificationPermissionStatus.denied,
      );
      await pumpAccount(tester, user: _verifiedUser, permissions: permissions);
      expect(find.text('Notification Settings'), findsOneWidget);
      expect(find.text('Not allowed'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('language row honestly shows English only',
        (WidgetTester tester) async {
      await pumpAccount(tester, user: _verifiedUser);
      expect(find.text('Language Settings'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      await _tapVisible(tester, 'Language Settings');
      expect(find.textContaining('English'), findsWidgets);
    });

    testWidgets('transaction history bottom sheet is honestly empty',
        (WidgetTester tester) async {
      await pumpAccount(tester, user: _verifiedUser);
      await _tapVisible(tester, 'Transactions');
      // The dashboard tile and the opened sheet both show these texts.
      expect(find.text('Transaction History'), findsWidgets);
      expect(find.text('No transactions yet.'), findsWidgets);
    });
  });

  group('Entry theme (Modern Minimalist redesign)', () {
    test('exact spec tokens, light and dark', () {
      expect(EntryColors.light.primary, const Color(0xFF079B61));
      expect(EntryColors.light.primaryDark, const Color(0xFF067A4D));
      expect(EntryColors.light.background, const Color(0xFFF8FAFC));
      expect(EntryColors.light.surface, const Color(0xFFFFFFFF));
      expect(EntryColors.light.secondarySurface, const Color(0xFFF1F5F3));
      expect(EntryColors.light.primaryText, const Color(0xFF17211D));
      expect(EntryColors.light.secondaryText, const Color(0xFF64748B));
      expect(EntryColors.light.border, const Color(0xFFE2E8F0));
      expect(EntryColors.dark.primary, const Color(0xFF12C98A));
      expect(EntryColors.dark.primaryDark, const Color(0xFF079B61));
      expect(EntryColors.dark.background, const Color(0xFF101816));
      expect(EntryColors.dark.surface, const Color(0xFF19231F));
      expect(EntryColors.dark.secondarySurface, const Color(0xFF202D27));
      expect(EntryColors.dark.primaryText, const Color(0xFFF5F7F6));
      expect(EntryColors.dark.secondaryText, const Color(0xFFA0ADA6));
      expect(EntryColors.dark.border, const Color(0xFF2D3B34));
      expect(entryColorsFor(Brightness.light), EntryColors.light);
      expect(entryColorsFor(Brightness.dark), EntryColors.dark);
    });

    testWidgets('auth screen follows light and dark themes',
        (WidgetTester tester) async {
      final auth = FakeAuthService();
      await tester.pumpWidget(_wrap(
        AuthScreen(
          service: auth,
          initialMode: AuthMode.signIn,
          onSignedIn: (_) {},
          onAccountCreated: (_) {},
          themeMode: ThemeMode.light,
        ),
      ));
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
        const Color(0xFFF8FAFC),
      );

      await tester.pumpWidget(_wrap(
        AuthScreen(
          service: auth,
          initialMode: AuthMode.signIn,
          onSignedIn: (_) {},
          onAccountCreated: (_) {},
          themeMode: ThemeMode.dark,
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
        const Color(0xFF101816),
      );
    });

    testWidgets('theme toggle flips light to dark and back',
        (WidgetTester tester) async {
      ThemeMode? changed;
      await tester.pumpWidget(_wrap(
        AuthScreen(
          service: FakeAuthService(),
          initialMode: AuthMode.signIn,
          onSignedIn: (_) {},
          onAccountCreated: (_) {},
          themeMode: ThemeMode.light,
          onThemeModeChanged: (mode) => changed = mode,
        ),
      ));
      // Light mode shows the moon (tap for dark).
      expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
      await tester.tap(find.byKey(const Key('theme-mode-toggle')));
      expect(changed, ThemeMode.dark);

      await tester.pumpWidget(_wrap(
        AuthScreen(
          service: FakeAuthService(),
          initialMode: AuthMode.signIn,
          onSignedIn: (_) {},
          onAccountCreated: (_) {},
          themeMode: ThemeMode.dark,
          onThemeModeChanged: (mode) => changed = mode,
        ),
      ));
      await tester.pumpAndSettle();
      // Dark mode shows the sun (tap for light).
      expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
      await tester.tap(find.byKey(const Key('theme-mode-toggle')));
      expect(changed, ThemeMode.light);
    });

    testWidgets('auth back button only exists when onBack is supplied',
        (WidgetTester tester) async {
      var backed = false;
      await tester.pumpWidget(_wrap(
        AuthScreen(
          service: FakeAuthService(),
          initialMode: AuthMode.signIn,
          onSignedIn: (_) {},
          onAccountCreated: (_) {},
          onBack: () => backed = true,
        ),
      ));
      expect(find.byKey(const Key('auth-back')), findsOneWidget);
      await tester.tap(find.byKey(const Key('auth-back')));
      expect(backed, isTrue);

      await tester.pumpWidget(_wrap(
        AuthScreen(
          service: FakeAuthService(),
          initialMode: AuthMode.signIn,
          onSignedIn: (_) {},
          onAccountCreated: (_) {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('auth-back')), findsNothing);
    });

    testWidgets('onboarding welcome state shows toggle, earlier pages do not',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        OnboardingScreen(
          onGetStarted: () {},
          onSignIn: () {},
          themeMode: ThemeMode.light,
          onThemeModeChanged: (_) {},
        ),
      ));
      expect(find.byKey(const Key('theme-mode-toggle')), findsNothing);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Community Updates'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.byKey(const Key('theme-mode-toggle')), findsOneWidget);
    });

    testWidgets('onboarding initialPage lands on the welcome state',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        OnboardingScreen(
          onGetStarted: () {},
          onSignIn: () {},
          initialPage: 3,
        ),
      ));
      expect(find.text('Community Updates'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('auth titles and bottom links match the spec exactly',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        AuthScreen(
          service: FakeAuthService(),
          initialMode: AuthMode.createAccount,
          onSignedIn: (_) {},
          onAccountCreated: (_) {},
        ),
      ));
      expect(find.text('Create Your Account'), findsOneWidget);
      expect(find.text('Join EstudyanteGO and get started.'), findsOneWidget);
      expect(find.text('Already have an account? Sign In'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('OR'), findsOneWidget);

      // The link sits below the fold in the default viewport on the
      // taller create-account layout; scroll it into view first.
      await _tapVisible(tester, 'Already have an account? Sign In');
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Sign in to continue to EstudyanteGO.'), findsOneWidget);
      expect(find.text("Don't have an account? Create Account"), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
    });
  });

  group('Onboarding layout (Modern Minimalist refinement)', () {
    // The shared frame: one contain-fit illustration canvas on every
    // page, so swiping never jumps in size. (The header brand uses a
    // scaleDown FittedBox, which this predicate excludes.)
    Finder containIllustration() => find.byWidgetPredicate(
          (widget) =>
              widget is FittedBox && widget.fit == BoxFit.contain,
        );
    Finder illustrationCanvas() => find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox &&
              widget.width == 320 &&
              widget.height == 300,
        );
    const titles = [
      'Explore the Map',
      'Plan Your Trip',
      'Know Your Fare',
      'Community Updates',
    ];

    testWidgets('identical illustration frame on all four pages',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        OnboardingScreen(
          onGetStarted: () {},
          onSignIn: () {},
        ),
      ));
      for (var i = 0; i < titles.length; i++) {
        expect(find.text(titles[i]), findsOneWidget);
        expect(containIllustration(), findsOneWidget);
        expect(illustrationCanvas(), findsOneWidget);
        if (i < titles.length - 1) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('light and dark themes paint the onboarding background',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        OnboardingScreen(
          onGetStarted: () {},
          onSignIn: () {},
          themeMode: ThemeMode.light,
        ),
      ));
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
        const Color(0xFFF8FAFC),
      );
      await tester.pumpWidget(_wrap(
        OnboardingScreen(
          onGetStarted: () {},
          onSignIn: () {},
          themeMode: ThemeMode.dark,
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
        const Color(0xFF101816),
      );
    });

    testWidgets('small phone renders every page without overflow',
        (WidgetTester tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(_wrap(
        OnboardingScreen(
          onGetStarted: () {},
          onSignIn: () {},
        ),
      ));
      await tester.pumpAndSettle();
      for (var i = 0; i < titles.length; i++) {
        expect(find.text(titles[i]), findsOneWidget);
        if (i < titles.length - 1) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
        }
      }
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });
  });
}
