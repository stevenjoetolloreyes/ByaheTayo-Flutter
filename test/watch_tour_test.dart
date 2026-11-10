// Widget + controller tests for the Watch demo guided tour
// (Feature 3) on the Student tab.
//
// The tab is pumped bare (no shell), so it owns its tour
// controller and renders the overlay itself over its own list —
// the shell's nav target is absent, so stop 1 shows its caption
// centred with no highlight ring; every other stop highlights
// its real card. All tab content is real (empty SharedPreferences
// seeds the honest zero states), never mocked.
//
// NOTE: while the tour is active the highlight ring pulses on a
// repeating animation controller, so pumpAndSettle never settles
// — these tests pump explicit durations instead.
import 'package:estudyantego/features/student/student_theme.dart';
import 'package:estudyantego/features/student/watch_tour.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tall viewport so the full StudentTab list builds (every tour
/// target laid out); the short-viewport test overrides it.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Phone-sized viewport: below-the-fold cards are NOT built until
/// the tour scrolls them into view.
void _phoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpTab(
  WidgetTester tester, {
  bool startWatchTour = false,
  VoidCallback? onWatchTourConsumed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light(),
      themeMode: ThemeMode.light,
      home: Scaffold(
        body: StudentHubTheme(
          child: StudentTab(
            startWatchTour: startWatchTour,
            onWatchTourConsumed: onWatchTourConsumed,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pumps an ARMED tour (startWatchTour true) without pumpAndSettle:
/// once the tour starts, its pulsing ring keeps scheduling frames
/// and pumpAndSettle would run the whole tour to completion (each
/// settle pump advances fake time 100ms). Zero-duration pumps let
/// the tab load and the tour start without the 2.5s clock firing.
Future<void> _pumpTabArmed(
  WidgetTester tester, {
  VoidCallback? onWatchTourConsumed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light(),
      themeMode: ThemeMode.light,
      home: Scaffold(
        body: StudentHubTheme(
          child: StudentTab(
            startWatchTour: true,
            onWatchTourConsumed: onWatchTourConsumed,
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 50; i++) {
    await tester.pump();
    if (find.byKey(const ValueKey('watch-demo-button'))
        .evaluate()
        .isNotEmpty) {
      return;
    }
  }
  fail('Student tab did not load');
}

/// The caption bubble's "N of 9 · How to use" line.
Finder _caption(int n) => find.text('$n of 9 · How to use');

/// The tour is up when its caption line is on screen.
bool _tourUp(WidgetTester tester) =>
    find.textContaining('· How to use').evaluate().isNotEmpty;

/// Pump a little at a time until the caption reaches stop [n]
/// (bounded, so a stuck tour fails instead of hanging).
Future<void> _waitForStop(WidgetTester tester, int n) async {
  for (var i = 0; i < 60; i++) {
    if (_caption(n).evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('tour did not reach stop $n');
}

/// Pump until the pulsing highlight ring appears for the current
/// stop (bounded). The ring is measured in a post-frame reveal,
/// one frame after the caption updates, so waiting on the caption
/// alone is a frame too early.
Future<void> _waitForHighlight(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    if (find
        .byKey(const ValueKey('watch-tour-highlight'))
        .evaluate()
        .isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('tour highlight ring did not appear');
}

/// Real Student tab content that must be present under the tour.
void _expectRealTabContent() {
  expect(find.text('7-Day Sign-in'), findsOneWidget);
  expect(find.text('Classes & Timetable'), findsOneWidget);
  expect(find.text('Allowance & Budgeting'), findsOneWidget);
  expect(find.text('School Calendar'), findsOneWidget);
  expect(find.text('Daily Quotes'), findsOneWidget);
}

void main() {
  group('WatchTourController (no widget)', () {
    test('start / next / previous / play-pause / end', () {
      final controller = WatchTourController();
      addTearDown(controller.dispose);

      expect(controller.isActive, isFalse);
      expect(controller.stops.length, 9);
      expect(controller.currentStop.id, 'nav');

      controller.start();
      expect(controller.isActive, isTrue);
      expect(controller.currentIndex, 0);
      expect(controller.currentNumber, 1);
      expect(controller.isPlaying, isTrue);

      // Starting twice is a no-op (no restart mid-run).
      controller.next();
      controller.start();
      expect(controller.currentIndex, 1);

      controller.previous();
      expect(controller.currentIndex, 0);
      controller.previous();
      expect(controller.currentIndex, 0);

      controller.togglePlayPause();
      expect(controller.isPlaying, isFalse);
      controller.togglePlayPause();
      expect(controller.isPlaying, isTrue);

      // Next past the last stop ends the tour.
      for (var i = 0; i < 8; i++) {
        controller.next();
      }
      expect(controller.currentIndex, 8);
      expect(controller.isLastStop, isTrue);
      controller.next();
      expect(controller.isActive, isFalse);
      expect(controller.currentIndex, 0);
    });

    test('target registry: first laid-out key wins', () {
      final controller = WatchTourController();
      addTearDown(controller.dispose);
      final key = GlobalKey();
      expect(controller.targetKeyFor('walking'), isNull);
      expect(controller.anyTargetKeyFor('walking'), isNull);
      controller.registerTarget('walking', key);
      expect(controller.anyTargetKeyFor('walking'), key);
      // Unbuilt: no context, so no laid-out key.
      expect(controller.targetKeyFor('walking'), isNull);
      controller.registerTarget('walking', key);
      controller.unregisterTarget('walking', key);
      expect(controller.anyTargetKeyFor('walking'), isNull);
    });
  });

  group('Watch demo button (manual start)', () {
    testWidgets('button starts the tour; real tab content stays underneath',
        (WidgetTester tester) async {
      _tallScreen(tester);
      SharedPreferences.setMockInitialValues({});
      await _pumpTab(tester);

      _expectRealTabContent();
      expect(find.byKey(const ValueKey('watch-demo-button')), findsOneWidget);
      expect(find.text('Watch demo'), findsOneWidget);
      expect(_tourUp(tester), isFalse);

      await tester.tap(find.byKey(const ValueKey('watch-demo-button')));
      await tester.pump();
      await _waitForStop(tester, 1);

      expect(_caption(1), findsOneWidget);
      expect(find.text('Switch tabs'), findsOneWidget);
      expect(find.byKey(const ValueKey('watch-tour-back')), findsOneWidget);
      expect(find.byKey(const ValueKey('watch-tour-play-pause')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('watch-tour-next')), findsOneWidget);
      expect(find.byKey(const ValueKey('watch-tour-end')), findsOneWidget);
      // The real cards are still there, under the overlay.
      _expectRealTabContent();
    });

    testWidgets('tour overlay blocks taps on the tab underneath',
        (WidgetTester tester) async {
      _tallScreen(tester);
      SharedPreferences.setMockInitialValues({});
      await _pumpTab(tester);

      await tester.tap(find.byKey(const ValueKey('watch-demo-button')));
      await tester.pump();
      await _waitForStop(tester, 1);

      // The 7-Day Sign-in card is a tap target into its screen —
      // under the tour dim the tap must go nowhere: no navigation,
      // tour still on stop 1.
      await tester.tap(find.text('7-Day Sign-in'));
      await tester.pump();
      expect(_caption(1), findsOneWidget);
      expect(find.text('7-Day Sign-in'), findsWidgets);
    });
  });

  group('auto-start hook', () {
    testWidgets('startWatchTour starts the tour and fires consumed once',
        (WidgetTester tester) async {
      _tallScreen(tester);
      SharedPreferences.setMockInitialValues({});
      var consumed = 0;
      await _pumpTabArmed(
        tester,
        onWatchTourConsumed: () => consumed++,
      );
      await _waitForStop(tester, 1);

      expect(_caption(1), findsOneWidget);
      expect(consumed, 1);

      // Let it run on: the callback must not fire again.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(consumed, 1);
    });

    testWidgets('flag false never auto-starts',
        (WidgetTester tester) async {
      _tallScreen(tester);
      SharedPreferences.setMockInitialValues({});
      var consumed = 0;
      await _pumpTab(
        tester,
        startWatchTour: false,
        onWatchTourConsumed: () => consumed++,
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();

      expect(_tourUp(tester), isFalse);
      expect(consumed, 0);
    });

    testWidgets('flag flipped while mounted auto-starts (didUpdateWidget)',
        (WidgetTester tester) async {
      _tallScreen(tester);
      SharedPreferences.setMockInitialValues({});
      var consumed = 0;
      await _pumpTab(tester, startWatchTour: false);
      expect(_tourUp(tester), isFalse);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          themeMode: ThemeMode.light,
          home: Scaffold(
            body: StudentHubTheme(
              child: StudentTab(
                startWatchTour: true,
                onWatchTourConsumed: () => consumed++,
              ),
            ),
          ),
        ),
      );
      await _waitForStop(tester, 1);
      expect(consumed, 1);
    });

    testWidgets('manual restart after auto-start does not re-fire consumed',
        (WidgetTester tester) async {
      _tallScreen(tester);
      SharedPreferences.setMockInitialValues({});
      var consumed = 0;
      await _pumpTabArmed(
        tester,
        onWatchTourConsumed: () => consumed++,
      );
      await _waitForStop(tester, 1);
      expect(consumed, 1);

      await tester.tap(find.byKey(const ValueKey('watch-tour-end')));
      await tester.pump();
      expect(_tourUp(tester), isFalse);

      await tester.tap(find.byKey(const ValueKey('watch-demo-button')));
      await _waitForStop(tester, 1);
      expect(consumed, 1);
    });
  });

  group('stop advancement', () {
    testWidgets('auto-advances every ~2.5s once a stop is shown',
        (WidgetTester tester) async {
      _tallScreen(tester);
      SharedPreferences.setMockInitialValues({});
      await _pumpTab(tester);

      await tester.tap(find.byKey(const ValueKey('watch-demo-button')));
      await _waitForStop(tester, 1);

      await tester.pump(const Duration(seconds: 3));
      await _waitForStop(tester, 2);
      expect(find.text('Walking Goal'), findsWidgets);

      await tester.pump(const Duration(seconds: 3));
      await _waitForStop(tester, 3);
      expect(find.text('7-Day Sign-in'), findsWidgets);
    });

    testWidgets('Next / Back move one stop; Back is disabled on stop 1',
        (WidgetTester tester) async {
      _tallScreen(tester);
      SharedPreferences.setMockInitialValues({});
      await _pumpTab(tester);

      await tester.tap(find.byKey(const ValueKey('watch-demo-button')));
      await _waitForStop(tester, 1);

      final back = tester.widget<IconButton>(
        find.byKey(const ValueKey('watch-tour-back')),
      );
      expect(back.onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('watch-tour-next')));
      await _waitForStop(tester, 2);

      await tester.tap(find.byKey(const ValueKey('watch-tour-back')));
      await _waitForStop(tester, 1);
      expect(_caption(1), findsOneWidget);
    });

    testWidgets('finishing stop 9 ends the tour and leaves the tab intact',
        (WidgetTester tester) async {
      _tallScreen(tester);
      SharedPreferences.setMockInitialValues({});
      await _pumpTab(tester);

      await tester.tap(find.byKey(const ValueKey('watch-demo-button')));
      await _waitForStop(tester, 1);

      // Pause so the clock cannot advance past a tap.
      await tester.tap(find.byKey(const ValueKey('watch-tour-play-pause')));
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byKey(const ValueKey('watch-tour-next')));
        await _waitForStop(tester, i + 2);
      }
      expect(_caption(9), findsOneWidget);
      expect(find.text('Daily Quotes'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('watch-tour-next')));
      await tester.pump();
      expect(_tourUp(tester), isFalse);
      _expectRealTabContent();
    });
  });

  group('Play / Pause', () {
    testWidgets('pause holds the stop; resume restarts the dwell',
        (WidgetTester tester) async {
      _tallScreen(tester);
      SharedPreferences.setMockInitialValues({});
      await _pumpTab(tester);

      await tester.tap(find.byKey(const ValueKey('watch-demo-button')));
      await _waitForStop(tester, 1);

      await tester.tap(find.byKey(const ValueKey('watch-tour-play-pause')));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('watch-tour-play-pause')),
            )
            .icon,
        isA<Icon>().having((i) => i.icon, 'icon', Icons.play_arrow),
      );

      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(_caption(1), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('watch-tour-play-pause')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await _waitForStop(tester, 2);
    });
  });

  group('End', () {
    testWidgets('End dismisses the overlay; tab untouched; tour restarts',
        (WidgetTester tester) async {
      _tallScreen(tester);
      SharedPreferences.setMockInitialValues({});
      await _pumpTab(tester);

      await tester.tap(find.byKey(const ValueKey('watch-demo-button')));
      await _waitForStop(tester, 1);
      await tester.tap(find.byKey(const ValueKey('watch-tour-next')));
      await _waitForStop(tester, 2);

      await tester.tap(find.byKey(const ValueKey('watch-tour-end')));
      await tester.pump();
      expect(_tourUp(tester), isFalse);
      _expectRealTabContent();

      // The tour can start again from the button.
      await tester.tap(find.byKey(const ValueKey('watch-demo-button')));
      await _waitForStop(tester, 1);
      expect(_caption(1), findsOneWidget);
    });
  });

  group('tap the highlight to advance', () {
    testWidgets('tapping the highlighted card advances to the next stop',
        (WidgetTester tester) async {
      _tallScreen(tester);
      SharedPreferences.setMockInitialValues({});
      await _pumpTab(tester);

      await tester.tap(find.byKey(const ValueKey('watch-demo-button')));
      await _waitForStop(tester, 1);
      // Stop 1 has no shell target in a bare tab, so no ring yet.
      // Let the reveal finish first so the findsNothing is real.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('watch-tour-highlight')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('watch-tour-next')));
      await _waitForStop(tester, 2);
      // Stop 2 (Walking Goal) is a real card: the ring is up.
      await _waitForHighlight(tester);
      expect(find.byKey(const ValueKey('watch-tour-highlight')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('watch-tour-highlight')));
      await _waitForStop(tester, 3);
      expect(_caption(3), findsOneWidget);
    });
  });

  group('below-the-fold targets (phone viewport)', () {
    testWidgets('tour scrolls each stop into view, down to Daily Quotes',
        (WidgetTester tester) async {
      _phoneScreen(tester);
      SharedPreferences.setMockInitialValues({});
      await _pumpTab(tester);

      await tester.tap(find.byKey(const ValueKey('watch-demo-button')));
      await _waitForStop(tester, 1);

      // Pause so only Next taps move the tour.
      await tester.tap(find.byKey(const ValueKey('watch-tour-play-pause')));
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byKey(const ValueKey('watch-tour-next')));
        await _waitForStop(tester, i + 2);
      }
      expect(_caption(9), findsOneWidget);
      expect(find.text('Daily Quotes'), findsWidgets);
      // The last stop's card was scrolled into view and highlighted.
      await _waitForHighlight(tester);
      expect(find.byKey(const ValueKey('watch-tour-highlight')), findsOneWidget);
    });
  });
}
