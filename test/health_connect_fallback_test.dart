// Health Connect fallback tests: Manila day-window math, the
// controller's sensor-first fallback selection, the grant flow,
// refresh, and the hub card's fallback states.
//
// No test ever asserts a fabricated step count: every count comes
// from the fake Health Connect source driven by the test itself.
import 'package:estudyantego/features/student/health_connect_steps.dart';
import 'package:estudyantego/features/student/walking_goal_card.dart';
import 'package:estudyantego/features/student/walking_repository.dart';
import 'package:estudyantego/features/student/walking_sensor.dart';
import 'package:estudyantego/features/student/student_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('healthConnectTodayRange', () {
    test('Manila morning starts at Manila midnight', () {
      // 10:00 Manila on Nov 5 == 02:00 UTC Nov 5.
      final range =
          healthConnectTodayRange(DateTime.utc(2026, 11, 5, 2, 0));
      expect(
        DateTime.fromMillisecondsSinceEpoch(range.startMillis,
            isUtc: true),
        DateTime.utc(2026, 11, 4, 16, 0),
      );
      expect(range.endMillis,
          DateTime.utc(2026, 11, 5, 2, 0).millisecondsSinceEpoch);
      expect(range.startMillis, lessThan(range.endMillis));
    });

    test('just before Manila midnight stays on the same Manila day',
        () {
      // 23:59 Manila on Nov 4 == 15:59 UTC Nov 4.
      final range =
          healthConnectTodayRange(DateTime.utc(2026, 11, 4, 15, 59));
      expect(
        DateTime.fromMillisecondsSinceEpoch(range.startMillis,
            isUtc: true),
        DateTime.utc(2026, 11, 3, 16, 0),
      );
    });
  });

  group('WalkingController Health Connect fallback', () {
    late FakeWalkingSensor sensor;
    late FakeActivityPermission permission;
    late FakeHealthConnectSteps healthConnect;

    WalkingController controller() => WalkingController(
          sensor: sensor,
          permission: permission,
          healthConnect: healthConnect,
        );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      sensor = FakeWalkingSensor();
      permission = FakeActivityPermission(
        current: ActivityPermissionStatus.granted,
      );
      healthConnect = FakeHealthConnectSteps(
        hasPermission: true,
        todaySteps: 3450,
      );
    });

    test('sensor present: sensor path wins, Health Connect untouched',
        () async {
      final c = controller();
      await c.init();
      expect(c.status, WalkingStatus.ready);
      expect(c.stepSource, WalkingStepSource.sensor);
      expect(healthConnect.readCount, 0);
      expect(healthConnect.requestCount, 0);
      c.dispose();
    });

    test('sensor absent + granted: today\'s aggregate is the total',
        () async {
      sensor.available = false;
      final c = controller();
      await c.init();
      expect(c.status, WalkingStatus.ready);
      expect(c.stepSource, WalkingStepSource.healthConnect);
      expect(c.todaySteps, 3450);
      expect(c.receivedEvent, isTrue);
      expect(c.lastHealthConnectReadLabel, isNotEmpty);
      expect(healthConnect.readCount, 1);
      c.dispose();
    });

    test('sensor absent + ungranted: connect prompt, then grant reads',
        () async {
      sensor.available = false;
      healthConnect.hasPermission = false;
      final c = controller();
      await c.init();
      expect(c.status, WalkingStatus.healthConnectRequired);
      expect(c.todaySteps, 0);
      expect(healthConnect.readCount, 0);

      await c.requestHealthConnectPermission();
      expect(healthConnect.requestCount, 1);
      expect(c.status, WalkingStatus.ready);
      expect(c.stepSource, WalkingStepSource.healthConnect);
      expect(c.todaySteps, 3450);
      c.dispose();
    });

    test('grant denied stays on the connect prompt', () async {
      sensor.available = false;
      healthConnect.hasPermission = false;
      healthConnect.requestResult = false;
      final c = controller();
      await c.init();
      expect(c.status, WalkingStatus.healthConnectRequired);
      await c.requestHealthConnectPermission();
      expect(c.status, WalkingStatus.healthConnectRequired);
      expect(healthConnect.readCount, 0);
      c.dispose();
    });

    test('Health Connect unavailable is still an honest noSensor',
        () async {
      sensor.available = false;
      healthConnect.sdkStatusValue = HealthConnectSdkStatus.unavailable;
      final c = controller();
      await c.init();
      expect(c.status, WalkingStatus.noSensor);
      expect(c.todaySteps, 0);
      expect(healthConnect.readCount, 0);
      c.dispose();
    });

    test('Health Connect needing an update is still noSensor',
        () async {
      sensor.available = false;
      healthConnect.sdkStatusValue =
          HealthConnectSdkStatus.updateRequired;
      final c = controller();
      await c.init();
      expect(c.status, WalkingStatus.noSensor);
      c.dispose();
    });

    test('refresh re-reads the aggregate (fallback mode only)',
        () async {
      sensor.available = false;
      final c = controller();
      await c.init();
      expect(c.todaySteps, 3450);
      healthConnect.todaySteps = 4000;
      await c.refreshSteps();
      expect(c.todaySteps, 4000);
      expect(healthConnect.readCount, 2);
      c.dispose();
    });

    test('refresh is a no-op on the sensor path', () async {
      final c = controller();
      await c.init();
      expect(c.stepSource, WalkingStepSource.sensor);
      await c.refreshSteps();
      expect(healthConnect.readCount, 0);
      c.dispose();
    });

    test('grant in the Health Connect app recovers via recheck',
        () async {
      sensor.available = false;
      healthConnect.hasPermission = false;
      final c = controller();
      await c.init();
      expect(c.status, WalkingStatus.healthConnectRequired);
      healthConnect.hasPermission = true;
      await c.recheckHealthConnect();
      expect(c.status, WalkingStatus.ready);
      expect(c.todaySteps, 3450);
      c.dispose();
    });

    test('stored old-day state archives into history on HC init',
        () async {
      sensor.available = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        WalkingStore.stateKey,
        '{"day":"2000-01-01","todaySteps":1234,"lastCumulative":9000}',
      );
      final c = controller();
      await c.init();
      expect(c.history['2000-01-01'], 1234);
      expect(c.todaySteps, 3450);
      c.dispose();
    });
  });

  group('WalkingGoalCard Health Connect states', () {
    Widget wrap(Widget child) => MaterialApp(
          theme: studentTheme,
          home: Scaffold(body: child),
        );

    testWidgets('connect prompt unlocks on grant', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final healthConnect = FakeHealthConnectSteps(
        hasPermission: false,
        todaySteps: 3450,
      );
      final c = WalkingController(
        sensor: FakeWalkingSensor(available: false),
        permission: FakeActivityPermission(),
        healthConnect: healthConnect,
      );
      await c.init();
      expect(c.status, WalkingStatus.healthConnectRequired);
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(
        WalkingGoalCard(controller: c, onOpen: () {}),
      ));
      expect(find.text('Connect Health Connect'), findsOneWidget);
      await tester.tap(find.text('Connect Health Connect'));
      await tester.pumpAndSettle();
      expect(c.status, WalkingStatus.ready);
      expect(find.textContaining('Steps from Health Connect'),
          findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('3,450 / 8,000 steps'), findsOneWidget);
    });

    testWidgets('no-sensor state names Health Connect', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = WalkingController(
        sensor: FakeWalkingSensor(available: false),
        permission: FakeActivityPermission(),
        healthConnect: FakeHealthConnectSteps(
          sdkStatusValue: HealthConnectSdkStatus.unavailable,
        ),
      );
      await c.init();
      expect(c.status, WalkingStatus.noSensor);
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(
        WalkingGoalCard(controller: c, onOpen: () {}),
      ));
      expect(find.text('Step counting isn\'t available on this device.'),
          findsOneWidget);
      expect(find.textContaining('Health Connect'), findsOneWidget);
    });

    testWidgets('Refresh re-reads the aggregate', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final healthConnect = FakeHealthConnectSteps(
        hasPermission: true,
        todaySteps: 3450,
      );
      final c = WalkingController(
        sensor: FakeWalkingSensor(available: false),
        permission: FakeActivityPermission(),
        healthConnect: healthConnect,
      );
      await c.init();
      expect(c.status, WalkingStatus.ready);
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(
        WalkingGoalCard(controller: c, onOpen: () {}),
      ));
      await tester.pump();
      expect(find.text('3,450 / 8,000 steps'), findsOneWidget);
      healthConnect.todaySteps = 4000;
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('4,000 / 8,000 steps'), findsOneWidget);
    });
  });
}
