// Walking Goal Phase 1 tests: daily-delta accumulator rules,
// controller behavior with fake sensor/permission, hub card states,
// hub section order, and details-screen light/dark rendering.
//
// No test ever asserts a fabricated step count: every count comes
// from fake sensor events driven by the test itself.
import 'package:estudyantego/features/student/walking_goal_card.dart';
import 'package:estudyantego/features/student/walking_goal_screen.dart';
import 'package:estudyantego/features/student/walking_repository.dart';
import 'package:estudyantego/features/student/walking_sensor.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:estudyantego/features/student/student_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('manilaDateKey', () {
    test('UTC evening maps to the next Manila day', () {
      expect(manilaDateKey(DateTime.utc(2026, 11, 2, 16, 0)),
          '2026-11-03');
    });

    test('UTC just before midnight Manila stays on the same day', () {
      expect(manilaDateKey(DateTime.utc(2026, 11, 2, 15, 59)),
          '2026-11-02');
    });
  });

  group('estimates', () {
    test('distance, calories, and duration scale with steps', () {
      expect(walkingDistanceKm(10000), closeTo(7.62, 0.001));
      expect(walkingCalories(10000), 400.0);
      expect(walkingDurationMin(10000), 100);
      expect(walkingDistanceKm(0), 0.0);
    });
  });

  group('applyCumulative', () {
    const day = '2026-11-02';
    const nextDay = '2026-11-03';

    test('first event sets the baseline and counts nothing', () {
      final state = applyCumulative(
        const WalkingDayState(
            day: day, todaySteps: 0, lastCumulative: null),
        5000,
        day,
      );
      expect(state.todaySteps, 0);
      expect(state.lastCumulative, 5000);
    });

    test('same-day events accumulate deltas only', () {
      var state = const WalkingDayState(
          day: day, todaySteps: 0, lastCumulative: null);
      state = applyCumulative(state, 5000, day);
      state = applyCumulative(state, 5300, day);
      state = applyCumulative(state, 5800, day);
      expect(state.todaySteps, 800);
      expect(state.lastCumulative, 5800);
    });

    test('app restart never re-adds the cumulative total', () {
      // Persisted state from before the restart: 800 steps counted,
      // last sensor value 5800. The first event after restart must
      // contribute only its delta.
      var state = const WalkingDayState(
          day: day, todaySteps: 800, lastCumulative: 5800);
      state = applyCumulative(state, 6100, day);
      expect(state.todaySteps, 1100);
    });

    test('sensor reboot adds post-reboot steps and keeps the total', () {
      var state = const WalkingDayState(
          day: day, todaySteps: 1500, lastCumulative: 3500);
      state = applyCumulative(state, 300, day);
      expect(state.todaySteps, 1800);
      expect(state.lastCumulative, 300);
    });

    test('new day resets and the caller archives the old day', () {
      final state = applyCumulative(
        const WalkingDayState(
            day: day, todaySteps: 1500, lastCumulative: 3500),
        9000,
        nextDay,
      );
      expect(state.day, nextDay);
      expect(state.todaySteps, 0);
      expect(state.lastCumulative, 9000);
    });
  });

  group('WalkingController with fakes', () {
    late FakeWalkingSensor sensor;
    late FakeActivityPermission permission;

    WalkingController controller() => WalkingController(
          sensor: sensor,
          permission: permission,
        );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      sensor = FakeWalkingSensor();
      permission = FakeActivityPermission(
        current: ActivityPermissionStatus.granted,
      );
    });

    test('unavailable sensor reports noSensor, never zero-as-data',
        () async {
      sensor.available = false;
      final c = controller();
      await c.init();
      expect(c.status, WalkingStatus.noSensor);
      expect(c.todaySteps, 0);
      c.dispose();
    });

    test('permission gate then live deltas', () async {
      permission.current = ActivityPermissionStatus.denied;
      final c = controller();
      await c.init();
      expect(c.status, WalkingStatus.permissionRequired);
      await c.requestPermission();
      expect(c.status, WalkingStatus.ready);
      sensor.emit(1000);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.todaySteps, 0); // baseline, not a count
      sensor.emit(1500);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.todaySteps, 500);
      expect(c.goal, WalkingStore.defaultGoal);
      expect(c.todayProgress, closeTo(500 / 8000, 0.001));
      c.dispose();
    });

    test('restart keeps the counted total (no double-count)', () async {
      final first = controller();
      await first.init();
      sensor.emit(2000);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      sensor.emit(2600);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(first.todaySteps, 600);
      first.dispose();

      final second = controller();
      await second.init();
      expect(second.todaySteps, 600);
      sensor.emit(2900);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(second.todaySteps, 900);
      second.dispose();
    });

    test('reboot mid-day adds post-reboot steps', () async {
      final c = controller();
      await c.init();
      sensor.emit(2000);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      sensor.emit(3500);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.todaySteps, 1500);
      sensor.emit(300);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.todaySteps, 1800);
      c.dispose();
    });

    test('stored old-day state archives into history on init', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        WalkingStore.stateKey,
        '{"day":"2000-01-01","todaySteps":1234,"lastCumulative":9000}',
      );
      final c = controller();
      await c.init();
      expect(c.history['2000-01-01'], 1234);
      expect(c.todaySteps, 0);
      c.dispose();
    });

    test('goal edit persists and clamps', () async {
      final c = controller();
      await c.init();
      await c.setGoal(12000);
      expect(c.goal, 12000);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(WalkingStore.goalKey), 12000);
      await c.setGoal(50);
      expect(c.goal, 1000);
      await c.setGoal(999999);
      expect(c.goal, 100000);
      c.dispose();
    });

    test('permanently denied permission can recover via recheck',
        () async {
      permission.current = ActivityPermissionStatus.permanentlyDenied;
      final c = controller();
      await c.init();
      expect(c.status, WalkingStatus.permissionDenied);
      permission.current = ActivityPermissionStatus.granted;
      await c.recheckPermission();
      expect(c.status, WalkingStatus.ready);
      c.dispose();
    });
  });

  group('WalkingGoalCard states', () {
    // NOTE: widget tests run under FakeAsync, so a plain Future.delayed
    // never fires until the tester pumps. runAsync runs the wait on real
    // timers so the sensor stream events can be delivered before pump.
    Future<WalkingController> readyController(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final sensor = FakeWalkingSensor();
      final permission = FakeActivityPermission(
        current: ActivityPermissionStatus.granted,
      );
      final c = WalkingController(
        sensor: sensor,
        permission: permission,
      );
      await c.init();
      sensor.emit(1000);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      sensor.emit(1500);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      return c;
    }

    Widget wrap(Widget child) => MaterialApp(
          theme: studentTheme,
          home: Scaffold(body: child),
        );

    testWidgets('loading state shows a spinner, not zeros',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = WalkingController(
        sensor: FakeWalkingSensor(),
        permission: FakeActivityPermission(),
      );
      // Deliberately not initialized: status stays loading.
      await tester.pumpWidget(wrap(
        WalkingGoalCard(controller: c, onOpen: () {}),
      ));
      expect(find.text('Loading walking data…'), findsOneWidget);
      c.dispose();
    });

    testWidgets('no-sensor state is honest', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = WalkingController(
        sensor: FakeWalkingSensor(available: false),
        permission: FakeActivityPermission(),
      );
      await c.init();
      await tester.pumpWidget(wrap(
        WalkingGoalCard(controller: c, onOpen: () {}),
      ));
      expect(find.text('Step counting isn\'t available on this device.'),
          findsOneWidget);
      c.dispose();
    });

    testWidgets('permission gate unlocks on grant', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final permission = FakeActivityPermission(
        current: ActivityPermissionStatus.denied,
      );
      final c = WalkingController(
        sensor: FakeWalkingSensor(),
        permission: permission,
      );
      await c.init();
      await tester.pumpWidget(wrap(
        WalkingGoalCard(controller: c, onOpen: () {}),
      ));
      expect(find.text('Allow activity tracking'), findsOneWidget);
      await tester.tap(find.text('Allow activity tracking'));
      await tester.pumpAndSettle();
      expect(c.status, WalkingStatus.ready);
      c.dispose();
    });

    testWidgets('ready card shows real counts, never fabricated ones',
        (tester) async {
      final c = await readyController(tester);
      addTearDown(c.dispose);
      await tester.pumpWidget(wrap(
        WalkingGoalCard(controller: c, onOpen: () {}),
      ));
      await tester.pump();
      expect(find.text('Walking Goal'), findsOneWidget);
      expect(find.text('500 / 8,000 steps'), findsOneWidget);
      expect(find.text('Distance and calories are estimates.'),
          findsOneWidget);
    });
  });

  group('Hub order + details screen', () {
    testWidgets(
        'hub order is greeting, sign-in, rewards, walking, …, bible',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      // Tall surface: the redesigned Hub is taller than the old
      // layout, and the lazy ListView only builds on-screen cards —
      // the Bible card (last group) needs the extra height to be
      // built at all. (Logical height 9000 at devicePixelRatio 3.)
      tester.view.physicalSize = const Size(1080, 27000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final sensor = FakeWalkingSensor();
      final c = WalkingController(
        sensor: sensor,
        permission: FakeActivityPermission(
          current: ActivityPermissionStatus.granted,
        ),
      );
      await c.init();
      sensor.emit(1000);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      sensor.emit(1500);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      addTearDown(c.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: studentTheme,
          home: Scaffold(body: StudentTab(walkingController: c)),
        ),
      );
      await tester.pumpAndSettle();

      double dy(Finder finder) =>
          tester.getTopLeft(finder).dy;
      final greetingDy = dy(find.textContaining('Steven!'));
      final signinDy =
          dy(find.byKey(const ValueKey('signin-hub-card')));
      final rewardsDy =
          dy(find.byKey(const ValueKey('rewards-center')));
      final walkingDy =
          dy(find.byKey(const ValueKey('walking-hub-card')));
      final bibleDy = dy(find.byKey(const ValueKey('bible-hub-card')));
      // Preview port (Nov 6): the Hub is grouped — Rewards & Goals
      // first (sign-in, rewards, walking), Bible in the last group.
      expect(greetingDy, lessThan(signinDy));
      expect(signinDy, lessThan(rewardsDy));
      expect(rewardsDy, lessThan(walkingDy));
      expect(walkingDy, lessThan(bibleDy));
    });

    testWidgets('details screen renders in light and dark', (tester) async {
      // Tall surface so the lazy ListView builds every section at once;
      // scrolling to each section proved flaky across full-file runs.
      tester.view.physicalSize = const Size(1080, 12000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final sensor = FakeWalkingSensor();
      final c = WalkingController(
        sensor: sensor,
        permission: FakeActivityPermission(
          current: ActivityPermissionStatus.granted,
        ),
      );
      await c.init();
      sensor.emit(1000);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      sensor.emit(4500);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      addTearDown(c.dispose);

      for (final theme in [studentTheme, studentDarkTheme]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: WalkingGoalScreen(controller: c),
          ),
        );
        await tester.pump();
        expect(find.text('Walking Goal'), findsOneWidget);
        expect(find.text('Edit'), findsOneWidget);
        expect(find.text('Distance (est.)'), findsOneWidget);
        expect(find.text('Weekly Walking History'), findsOneWidget);
      }
    });

    testWidgets('details goal edit persists', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final sensor = FakeWalkingSensor();
      final c = WalkingController(
        sensor: sensor,
        permission: FakeActivityPermission(
          current: ActivityPermissionStatus.granted,
        ),
      );
      await c.init();
      addTearDown(c.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: studentTheme,
          home: WalkingGoalScreen(controller: c),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '12000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(c.goal, 12000);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(WalkingStore.goalKey), 12000);
    });
  });
}
