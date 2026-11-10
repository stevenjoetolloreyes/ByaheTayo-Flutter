// Tests for Feature 2: the post-setup celebration + "You know how
// to use the app?" prompt.
//
// Covers the celebration overlay on its own (shows, auto-advances
// after ~2.2 s, tap-to-skip fires once), the prompt overlay on its
// own (both buttons, correct callbacks), and the full gate flow:
// "Finish setup" -> celebration -> prompt -> Student tab, with the
// Watch demo tour hook (`StudentTab.startWatchTour`) true only for
// "No, show me how".
//
// The tour itself is Feature 3 — these tests only check the hook
// plumbing, never a tour UI.
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:estudyantego/features/onboarding/profile_setup_screen.dart';
import 'package:estudyantego/features/onboarding/setup_celebration.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:estudyantego/main.dart';
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

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Taps a widget that may sit below the fold in a scroll view.
Future<void> _tapVisible(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// Like [_tapVisible], but settles only BEFORE the tap: the tap
/// lands on the celebration overlay, whose 2.2 s auto-advance
/// timer must not be fast-forwarded by a settle.
Future<void> _tapIntoCelebration(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pump();
}

/// Pumps the real app through the gate as a verified user whose
/// profile setup is not done yet, landing on Profile Setup (step 8).
/// The notification prompt is pre-marked shown so it never pops
/// over the dashboard at the end of the flow.
Future<void> _pumpAppAtProfileSetup(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'byahetayo_onboarding_done': true,
    'byahetayo_notification_prompt_shown': true,
  });
  await tester.pumpWidget(
    EstudyanteGOApp(authService: FakeAuthService(user: _verifiedUser)),
  );
  // Anime splash (~4.9 s intro); a single settle carries it to the
  // gate handoff, as in widget_test.dart.
  await tester.pumpAndSettle();
  expect(find.text('Set up your profile'), findsOneWidget);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SetupCelebrationOverlay', () {
    testWidgets('shows the success text', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        SetupCelebrationOverlay(onFinished: () {}),
      ));
      await tester.pump();
      expect(find.text('Handa ka na!'), findsOneWidget);
      expect(find.text('Welcome to EstudyanteGO!'), findsOneWidget);
    });

    testWidgets('auto-advances after ~2.2 s, not before', (
      WidgetTester tester,
    ) async {
      var finished = false;
      await tester.pumpWidget(_wrap(
        SetupCelebrationOverlay(onFinished: () => finished = true),
      ));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(finished, isFalse);
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump();
      expect(finished, isTrue);
    });

    testWidgets('tap skips ahead immediately and fires once', (
      WidgetTester tester,
    ) async {
      var finishedCount = 0;
      await tester.pumpWidget(_wrap(
        SetupCelebrationOverlay(onFinished: () => finishedCount++),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Handa ka na!'));
      await tester.pump();
      expect(finishedCount, 1);
      // The auto-advance timer must not fire a second time.
      await tester.pump(const Duration(seconds: 3));
      expect(finishedCount, 1);
    });
  });

  group('SetupGuidePromptOverlay', () {
    testWidgets('shows the question and both buttons', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(
        SetupGuidePromptOverlay(onTakeMeIn: () {}, onShowMeHow: () {}),
      ));
      expect(find.text('You know how to use the app?'), findsOneWidget);
      expect(find.text('Yes, take me in'), findsOneWidget);
      expect(find.text('No, show me how'), findsOneWidget);
    });

    testWidgets('"Yes, take me in" calls only onTakeMeIn', (
      WidgetTester tester,
    ) async {
      var takeMeIn = false;
      var showMeHow = false;
      await tester.pumpWidget(_wrap(
        SetupGuidePromptOverlay(
          onTakeMeIn: () => takeMeIn = true,
          onShowMeHow: () => showMeHow = true,
        ),
      ));
      await tester.tap(find.text('Yes, take me in'));
      await tester.pump();
      expect(takeMeIn, isTrue);
      expect(showMeHow, isFalse);
    });

    testWidgets('"No, show me how" calls only onShowMeHow', (
      WidgetTester tester,
    ) async {
      var takeMeIn = false;
      var showMeHow = false;
      await tester.pumpWidget(_wrap(
        SetupGuidePromptOverlay(
          onTakeMeIn: () => takeMeIn = true,
          onShowMeHow: () => showMeHow = true,
        ),
      ));
      await tester.tap(find.text('No, show me how'));
      await tester.pump();
      expect(takeMeIn, isFalse);
      expect(showMeHow, isTrue);
    });
  });

  group('Post-setup gate flow', () {
    testWidgets(
      'Finish setup -> celebration -> auto-advance -> prompt -> '
      '"No, show me how" lands on the Student tab with the tour '
      'hook armed',
      (WidgetTester tester) async {
        await _pumpAppAtProfileSetup(tester);

        await _tapIntoCelebration(tester, 'Finish setup');
        expect(find.text('Handa ka na!'), findsOneWidget);
        expect(find.text('You know how to use the app?'), findsNothing);

        // Auto-advance after ~2.2 s.
        await tester.pump(const Duration(milliseconds: 2300));
        await tester.pumpAndSettle();
        expect(find.text('Handa ka na!'), findsNothing);
        expect(find.text('You know how to use the app?'), findsOneWidget);

        await tester.tap(find.text('No, show me how'));
        // TOUR HOOK: "No, show me how" arms the Watch demo tour —
        // check the flag on the first frame, before the tour
        // starts and consumes it (Feature 3 clears the flag the
        // moment the tour starts, by design).
        await tester.pump();
        expect(
          tester.widget<StudentTab>(find.byType(StudentTab)).startWatchTour,
          isTrue,
        );
        // Feature 3: the tour auto-starts on landing — pump in
        // small steps (never settle here: a settle would run the
        // whole 2.5 s-per-stop tour to completion and scroll the
        // list to the bottom) until the first stop's caption shows.
        for (var i = 0; i < 30; i++) {
          if (find.text('1 of 9 · How to use').evaluate().isNotEmpty) break;
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('1 of 9 · How to use'), findsOneWidget);
        // End the tour on stop 1 (before it scrolls anywhere) and
        // the header is back in view.
        await tester.tap(find.byKey(const ValueKey('watch-tour-end')));
        await tester.pumpAndSettle();
        expect(find.text('Student Hub', skipOffstage: true), findsOneWidget);
      },
    );

    testWidgets(
      'Finish setup -> celebration -> tap skips to prompt -> '
      '"Yes, take me in" lands on the Student tab with the tour '
      'hook disarmed',
      (WidgetTester tester) async {
        await _pumpAppAtProfileSetup(tester);

        await _tapIntoCelebration(tester, 'Finish setup');
        expect(find.text('Handa ka na!'), findsOneWidget);

        // Tap-to-skip reaches the same prompt as auto-advance.
        await tester.tap(find.text('Handa ka na!'));
        await tester.pumpAndSettle();
        expect(find.text('Handa ka na!'), findsNothing);
        expect(find.text('You know how to use the app?'), findsOneWidget);

        await tester.tap(find.text('Yes, take me in'));
        await tester.pumpAndSettle();
        expect(find.text('Student Hub', skipOffstage: true), findsOneWidget);
        // TOUR HOOK: "Yes, take me in" leaves the tour disarmed.
        expect(
          tester.widget<StudentTab>(find.byType(StudentTab)).startWatchTour,
          isFalse,
        );
      },
    );

    testWidgets(
      'Edit-profile saves do not show the celebration (gate path only)',
      (WidgetTester tester) async {
        // Direct ProfileSetupScreen in edit mode: onSaved fires
        // without any overlay — the celebration lives in the gate's
        // first-time flow only, never in the Account edit path.
        final prefs = await SharedPreferences.getInstance();
        final store = ProfileStore(prefs);
        var saved = false;
        await tester.pumpWidget(_wrap(
          ProfileSetupScreen(
            user: _verifiedUser,
            store: store,
            isEdit: true,
            onSaved: (_) => saved = true,
          ),
        ));
        await _tapVisible(tester, 'Save changes');
        expect(saved, isTrue);
        expect(find.text('Handa ka na!'), findsNothing);
        expect(find.text('You know how to use the app?'), findsNothing);
      },
    );
  });
}
