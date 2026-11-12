import 'dart:async';

import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/route_fare_overrides.dart';
import 'package:estudyantego/features/student/fares_widget_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Fares home screen widgets (Nov 11, 2026): small 4x2 "Fares" +
// big 4x3 "Popular Routes", approved preview v1. The routes below
// are the app's REAL built-in list (popularRoutes) plus TEST
// fixtures for the admin-set data — the widget itself reads the
// merged Fares-tab list and never hardcodes a route or a fare.
// Distance / ETA expectations come from the app's own models
// (PopularRoute.roadKm, estimateTripMinutes), not the preview:
// the preview's 32.3 km was the live OSRM road distance, while
// the widget shows the formula distance the Fares list card shows
// ("≈ 31.6 km").
void main() {
  test('featured route is the first route in Fares-tab order', () {
    final data = FaresWidgetService.decodeData(
        FaresWidgetService.encodeData([], {}, {}));
    expect(data, isNotNull);
    final featured = data!.featured;
    expect(featured, isNotNull);
    expect(featured!.from, 'Cabugao');
    expect(featured.to, 'Vigan Bus Terminal');
    expect(featured.fare, 60);
    // Student fare derives 20% off: ₱60 -> ₱48.
    expect(featured.studentFare, 48);
  });

  test('Cabugao to Vigan: formula distance and ETA from app models', () {
    final data = FaresWidgetService.decodeData(
        FaresWidgetService.encodeData([], {}, {}));
    final featured = data!.featured!;
    // haversine x 1.22 between the Cabugao and Vigan Bus Terminal hubs.
    expect(featured.distanceKm, isNotNull);
    expect(featured.distanceKm!, closeTo(31.6, 0.1));
    // Same-region transit ETA: 31.6 km at 32 kph + 10 min, 5-min rounding.
    expect(featured.etaMin, 70);
    expect(formatTripTimeShort(featured.etaMin!), '1 hr 10 min');
  });

  test('built-in routes with no fare carry null, never a sample', () {
    final data = FaresWidgetService.decodeData(
        FaresWidgetService.encodeData([], {}, {}));
    final viganToSanJuan = data!.routes.firstWhere(
        (r) => r.from == 'Vigan Bus Terminal' && r.to == 'San Juan, Ilocos Sur');
    expect(viganToSanJuan.fare, isNull);
    expect(viganToSanJuan.studentFare, isNull);
    final laoagToVigan = data.routes.firstWhere(
        (r) => r.from == 'Laoag Terminal' && r.to == 'Vigan Bus Terminal');
    expect(laoagToVigan.fare, isNull);
  });

  test('an admin fare override replaces the built-in fare', () {
    final data = FaresWidgetService.decodeData(FaresWidgetService.encodeData(
      [],
      {
        'Cabugao|Vigan Bus Terminal': const RouteFareOverride(
          routeKey: 'Cabugao|Vigan Bus Terminal',
          fare: 65,
        ),
      },
      {},
    ));
    final featured = data!.featured!;
    expect(featured.fare, 65);
    // Student fare still derives 20% off the overridden fare.
    expect(featured.studentFare, 52);
  });

  test('an admin-set student fare wins over the 20% derivation', () {
    final data = FaresWidgetService.decodeData(FaresWidgetService.encodeData(
      [],
      {
        'Cabugao|Vigan Bus Terminal': const RouteFareOverride(
          routeKey: 'Cabugao|Vigan Bus Terminal',
          studentFare: 50,
        ),
      },
      {},
    ));
    expect(data!.featured!.fare, 60);
    expect(data.featured!.studentFare, 50);
  });

  test('hidden built-in routes are dropped from the widget list', () {
    final data = FaresWidgetService.decodeData(FaresWidgetService.encodeData(
      [],
      {},
      {'Cabugao|Vigan Bus Terminal'},
    ));
    expect(
        data!.routes.any((r) =>
            r.from == 'Cabugao' && r.to == 'Vigan Bus Terminal'),
        isFalse);
    expect(data.featured!.from, 'Cabugao');
    expect(data.featured!.to, 'San Juan, Ilocos Sur');
  });

  test('admin-added custom routes are appended with their own fares', () {
    const custom = CustomRoute(
      from: 'Cabugao',
      to: 'Sinait',
      operator: 'Partas',
      vehicle: 'Bus',
      fare: 25,
    );
    final data = FaresWidgetService.decodeData(
        FaresWidgetService.encodeData([custom], {}, {}));
    final added = data!.routes
        .firstWhere((r) => r.from == 'Cabugao' && r.to == 'Sinait');
    expect(added.fare, 25);
    expect(added.operator, 'Partas');
    expect(added.studentFare, 20); // 20% off ₱25.
  });

  test('no routes are invented: count is built-ins plus customs', () {
    final builtIns = popularRoutes.length;
    final data = FaresWidgetService.decodeData(
        FaresWidgetService.encodeData([], {}, {}));
    expect(data!.routes.length, builtIns);
    const custom = CustomRoute(
      from: 'Vigan Bus Terminal',
      to: 'Bantay',
      operator: '',
      vehicle: 'Bus',
      fare: 15,
    );
    final withCustom = FaresWidgetService.decodeData(
        FaresWidgetService.encodeData([custom], {}, {}));
    expect(withCustom!.routes.length, builtIns + 1);
  });

  test('big widget lists the first three routes in tab order', () {
    final data = FaresWidgetService.decodeData(
        FaresWidgetService.encodeData([], {}, {}));
    final top = data!.top(FaresWidgetService.bigListCount);
    expect(top.length, 3);
    expect(top[0].title, 'Cabugao → Vigan Bus Terminal');
    expect(top[1].title, 'Cabugao → San Juan, Ilocos Sur');
    expect(top[2].title, 'Sinait → Cabugao');
  });

  test('decodeData returns null for missing or malformed JSON', () {
    expect(FaresWidgetService.decodeData(null), isNull);
    expect(FaresWidgetService.decodeData(''), isNull);
    expect(FaresWidgetService.decodeData('not json'), isNull);
    expect(FaresWidgetService.decodeData('{"routes": "x"}'), isNull);
    expect(FaresWidgetService.decodeData('[]'), isNull);
  });

  test('encode/decode round-trips the payload', () {
    final raw = FaresWidgetService.encodeData([], {}, {});
    final first = FaresWidgetService.decodeData(raw);
    final second = FaresWidgetService.decodeData(raw);
    expect(second, first);
  });

  testWidgets(
    'sync() leaves no pending timers when Firebase is unconfigured',
    (tester) async {
      // Regression pin (Nov 11, 2026): sync() used to attempt
      // Firestore unconditionally, and the 8-second .timeout()
      // left a pending Timer in fake_async — which failed every
      // Fares tab widget test. With Firebase uninitialized the
      // service must go straight to the local caches and create
      // no timer at all. The test framework fails this test at
      // teardown if any timer is left pending, so no explicit
      // expectation is needed here.
      await tester.pumpWidget(
        const MaterialApp(home: _SyncProbe()),
      );
      await tester.pump();
    },
  );
}

class _SyncProbe extends StatefulWidget {
  const _SyncProbe();

  @override
  State<_SyncProbe> createState() => _SyncProbeState();
}

class _SyncProbeState extends State<_SyncProbe> {
  @override
  void initState() {
    super.initState();
    unawaited(FaresWidgetService.sync());
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
