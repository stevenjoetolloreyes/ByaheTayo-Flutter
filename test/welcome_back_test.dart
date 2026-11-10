// Tests for Feature 4: the Welcome Back overlay after Sign In.
//
// Covers the overlay on its own (greeting with/without a first
// name, avatar photo vs initials fallback, auto-advance after
// ~2 s, tap-to-skip fires once), the first-name helper, and the
// full gate flow: Sign In (email/password and Google) ->
// Welcome Back -> Student tab, with the tour hook disarmed and
// the "You know how to use the app?" prompt never shown. Also
// covers the entry points: the verify-email path after an
// unverified sign-in still shows the overlay, while the Create
// Account Google sign-up path lands on the dashboard with no
// overlay at all.
import 'dart:convert';
import 'dart:typed_data';

import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:estudyantego/features/onboarding/welcome_back_overlay.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:estudyantego/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

/// 1x1 transparent PNG, usable as an in-memory avatar photo in
/// widget tests (no network image in tests).
final _tinyPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Waits (stepped pumps, never a settle — a settle would
/// fast-forward the overlay's 2 s auto-advance timer) until
/// [text] appears, or fails after ~4 s.
Future<void> _waitForText(WidgetTester tester, String text) async {
  for (var i = 0; i < 40; i++) {
    if (find.text(text).evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for "$text"');
}

/// Pumps the real app through the gate with no current session, so
/// it lands on the Sign In page (step 7). [auth] must already hold
/// the account under test; [profileUid] is the UID whose profile +
/// setup-done flag are seeded in SharedPreferences. The
/// notification prompt is pre-marked shown so it never pops over
/// the dashboard at the end of the flow.
Future<void> _pumpAppAtSignIn(
  WidgetTester tester, {
  required FakeAuthService auth,
  required String profileUid,
  required UserProfile profile,
  bool profileSetupDone = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'byahetayo_onboarding_done': true,
    'byahetayo_notification_prompt_shown': true,
    'byahetayo_profile_setup_done_$profileUid': profileSetupDone,
    'byahetayo_profile_$profileUid': jsonEncode(profile.toJson()),
  });
  await tester.pumpWidget(EstudyanteGOApp(authService: auth));
  // Anime splash (~4.9 s intro); a single settle carries it to the
  // gate handoff, as in widget_test.dart.
  await tester.pumpAndSettle();
  expect(find.text('Welcome Back'), findsOneWidget);
}

/// Taps a widget that may sit below the fold in a scroll view, then
/// pumps once (no settle — the tap lands on a flow whose 2 s
/// auto-advance timer must not be fast-forwarded).
Future<void> _tapNoSettle(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('welcomeBackFirstName', () {
    test('profile display name wins, first word only', () {
      expect(
        welcomeBackFirstName(
          profile: const UserProfile(
            displayName: 'Steven Joe Reyes',
            email: 's@example.com',
          ),
          user: const AuthUser(
            uid: 'u',
            email: 's@example.com',
            displayName: 'Other Name',
            emailVerified: true,
          ),
        ),
        'Steven',
      );
    });

    test('falls back to the Firebase display name', () {
      expect(
        welcomeBackFirstName(
          user: const AuthUser(
            uid: 'u',
            email: 'a@example.com',
            displayName: 'Ana Santos',
            emailVerified: true,
          ),
        ),
        'Ana',
      );
    });

    test('null when no name is available anywhere', () {
      expect(welcomeBackFirstName(), isNull);
      expect(
        welcomeBackFirstName(
          profile: const UserProfile(displayName: '   ', email: 'e@x.com'),
          user: const AuthUser(uid: 'u', email: 'e@x.com', emailVerified: true),
        ),
        isNull,
      );
    });

    test('never uses the email local-part as a name', () {
      expect(
        welcomeBackFirstName(
          user: const AuthUser(
            uid: 'u',
            email: 'steven@example.com',
            emailVerified: true,
          ),
        ),
        isNull,
      );
    });
  });

  group('WelcomeBackOverlay', () {
    testWidgets('shows the first-name greeting', (tester) async {
      await tester.pumpWidget(_wrap(
        WelcomeBackOverlay(
          firstName: 'Steven',
          displayName: 'Steven Reyes',
          onFinished: () {},
        ),
      ));
      await tester.pump();
      expect(find.text('Welcome back, Steven!'), findsOneWidget);
      expect(find.text('Good to see you again.'), findsOneWidget);
    });

    testWidgets('no name falls back to plain "Welcome back!"', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(
        const WelcomeBackOverlay(
          firstName: null,
          onFinished: _noop,
        ),
      ));
      await tester.pump();
      expect(find.text('Welcome back!'), findsOneWidget);
      expect(find.text('Welcome back, Steven!'), findsNothing);
    });

    testWidgets('shows initials when there is no photo', (tester) async {
      await tester.pumpWidget(_wrap(
        WelcomeBackOverlay(
          firstName: 'Steven',
          displayName: 'Steven Reyes',
          onFinished: () {},
        ),
      ));
      await tester.pump();
      expect(find.text('SR'), findsOneWidget);
    });

    testWidgets('shows the photo instead of initials when one exists', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(
        WelcomeBackOverlay(
          firstName: 'Steven',
          displayName: 'Steven Reyes',
          photoImage: MemoryImage(_tinyPng),
          onFinished: () {},
        ),
      ));
      await tester.pump();
      expect(find.text('SR'), findsNothing);
      // The photo avatar is a CircleAvatar with an image.
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('shows a person icon when there is no photo and no name', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(
        const WelcomeBackOverlay(
          firstName: null,
          onFinished: _noop,
        ),
      ));
      await tester.pump();
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('auto-advances after ~2 s, not before', (tester) async {
      var finished = false;
      await tester.pumpWidget(_wrap(
        WelcomeBackOverlay(
          firstName: 'Steven',
          onFinished: () => finished = true,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(finished, isFalse);
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();
      expect(finished, isTrue);
    });

    testWidgets('tap skips ahead immediately and fires once', (
      tester,
    ) async {
      var finishedCount = 0;
      await tester.pumpWidget(_wrap(
        WelcomeBackOverlay(
          firstName: 'Steven',
          onFinished: () => finishedCount++,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Welcome back, Steven!'));
      await tester.pump();
      expect(finishedCount, 1);
      // The auto-advance timer must not fire a second time.
      await tester.pump(const Duration(seconds: 3));
      expect(finishedCount, 1);
    });
  });

  group('Welcome Back gate flow', () {
    testWidgets(
      'email/password Sign In -> Welcome Back -> auto-advance -> '
      'Student tab, no how-to prompt, tour hook disarmed',
      (tester) async {
        final auth = FakeAuthService();
        await auth.createAccount(
          email: 'steven@example.com',
          password: 'secret1',
          displayName: 'Steven Reyes',
        );
        // createAccount leaves the user unverified (which would
        // divert to Verify Email); mark verified so this is a
        // returning verified user landing straight on the dashboard.
        auth.markCurrentUserVerified();
        await auth.signOut();
        final uid = 'uid-${'steven@example.com'.hashCode}';
        await _pumpAppAtSignIn(
          tester,
          auth: auth,
          profileUid: uid,
          profile: const UserProfile(
            displayName: 'Steven Reyes',
            email: 'steven@example.com',
          ),
        );

        await tester.enterText(
          find.widgetWithText(TextField, 'Email'),
          'steven@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Password'),
          'secret1',
        );
        await _tapNoSettle(
          tester,
          find.widgetWithText(FilledButton, 'Sign In'),
        );
        await _waitForText(tester, 'Welcome back, Steven!');
        expect(find.text('You know how to use the app?'), findsNothing);
        expect(find.text('Handa ka na!'), findsNothing);
        expect(find.byKey(const Key('welcome-back-overlay')), findsOneWidget);

        // Auto-advance after ~2 s.
        await tester.pump(const Duration(milliseconds: 2100));
        await tester.pumpAndSettle();
        expect(find.text('Welcome back, Steven!'), findsNothing);
        expect(find.text('Student Hub', skipOffstage: true), findsOneWidget);
        // TOUR HOOK: a returning sign-in never arms the tour.
        expect(
          tester.widget<StudentTab>(find.byType(StudentTab)).startWatchTour,
          isFalse,
        );
      },
    );

    testWidgets(
      'email/password Sign In -> Welcome Back -> tap skips to the '
      'Student tab',
      (tester) async {
        final auth = FakeAuthService();
        await auth.createAccount(
          email: 'steven@example.com',
          password: 'secret1',
          displayName: 'Steven Reyes',
        );
        // See the auto-advance test above: verified, or the gate
        // diverts to Verify Email instead of the overlay.
        auth.markCurrentUserVerified();
        await auth.signOut();
        final uid = 'uid-${'steven@example.com'.hashCode}';
        await _pumpAppAtSignIn(
          tester,
          auth: auth,
          profileUid: uid,
          profile: const UserProfile(
            displayName: 'Steven Reyes',
            email: 'steven@example.com',
          ),
        );

        await tester.enterText(
          find.widgetWithText(TextField, 'Email'),
          'steven@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Password'),
          'secret1',
        );
        await _tapNoSettle(
          tester,
          find.widgetWithText(FilledButton, 'Sign In'),
        );
        await _waitForText(tester, 'Welcome back, Steven!');

        await tester.tap(find.text('Welcome back, Steven!'));
        await tester.pumpAndSettle();
        expect(find.text('Welcome back, Steven!'), findsNothing);
        expect(find.text('You know how to use the app?'), findsNothing);
        expect(find.text('Student Hub', skipOffstage: true), findsOneWidget);
      },
    );

    testWidgets(
      'Google Sign In -> Welcome Back with the profile first name',
      (tester) async {
        final auth = FakeAuthService();
        auth.googleUser = const AuthUser(
          uid: 'google-uid-1',
          email: 'ana@example.com',
          displayName: 'Ana Santos',
          emailVerified: true,
        );
        await _pumpAppAtSignIn(
          tester,
          auth: auth,
          profileUid: 'google-uid-1',
          profile: const UserProfile(
            displayName: 'Ana Santos',
            email: 'ana@example.com',
          ),
        );

        await _tapNoSettle(tester, find.text('Continue with Google'));
        await _waitForText(tester, 'Welcome back, Ana!');
        expect(find.text('You know how to use the app?'), findsNothing);

        await tester.pump(const Duration(milliseconds: 2100));
        await tester.pumpAndSettle();
        expect(find.text('Welcome back, Ana!'), findsNothing);
        expect(find.text('Student Hub', skipOffstage: true), findsOneWidget);
        expect(
          tester.widget<StudentTab>(find.byType(StudentTab)).startWatchTour,
          isFalse,
        );
      },
    );

    testWidgets(
      'unverified Sign In -> verify email -> Welcome Back -> '
      'Student tab',
      (tester) async {
        final auth = FakeAuthService();
        await auth.createAccount(
          email: 'steven@example.com',
          password: 'secret1',
          displayName: 'Steven Reyes',
        );
        await auth.signOut();
        final uid = 'uid-${'steven@example.com'.hashCode}';
        await _pumpAppAtSignIn(
          tester,
          auth: auth,
          profileUid: uid,
          profile: const UserProfile(
            displayName: 'Steven Reyes',
            email: 'steven@example.com',
          ),
        );

        await tester.enterText(
          find.widgetWithText(TextField, 'Email'),
          'steven@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Password'),
          'secret1',
        );
        await _tapNoSettle(
          tester,
          find.widgetWithText(FilledButton, 'Sign In'),
        );
        // Unverified: the gate diverts to Verify Email first, with
        // no overlay yet.
        await _waitForText(tester, 'Check your email');
        expect(find.text('Welcome back, Steven!'), findsNothing);

        auth.markCurrentUserVerified();
        await _tapNoSettle(
          tester,
          find.text("I've verified — check again"),
        );
        await _waitForText(tester, 'Welcome back, Steven!');
        expect(find.text('You know how to use the app?'), findsNothing);

        await tester.pump(const Duration(milliseconds: 2100));
        await tester.pumpAndSettle();
        expect(find.text('Student Hub', skipOffstage: true), findsOneWidget);
      },
    );

    testWidgets(
      'Create Account Google sign-up lands on the dashboard with '
      'NO Welcome Back overlay',
      (tester) async {
        final auth = FakeAuthService();
        auth.googleUser = const AuthUser(
          uid: 'google-uid-2',
          email: 'bea@example.com',
          displayName: 'Bea Cruz',
          emailVerified: true,
        );
        await _pumpAppAtSignIn(
          tester,
          auth: auth,
          profileUid: 'google-uid-2',
          profile: const UserProfile(
            displayName: 'Bea Cruz',
            email: 'bea@example.com',
          ),
        );

        // Cross to the Create Account page via the gate link.
        await _tapNoSettle(
          tester,
          find.textContaining("Don't have an account?"),
        );
        await tester.pumpAndSettle();
        expect(find.text('Create Your Account'), findsOneWidget);

        await _tapNoSettle(tester, find.text('Continue with Google'));
        // Lands straight on the Student tab — the overlay never
        // appears on the Create Account path.
        for (var i = 0; i < 40; i++) {
          if (find
              .text('Student Hub', skipOffstage: true)
              .evaluate()
              .isNotEmpty) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Student Hub', skipOffstage: true), findsOneWidget);
        expect(find.text('Welcome back, Bea!'), findsNothing);
        expect(
          find.byKey(const Key('welcome-back-overlay')),
          findsNothing,
        );
        expect(find.text('You know how to use the app?'), findsNothing);
      },
    );
  });
}

void _noop() {}
