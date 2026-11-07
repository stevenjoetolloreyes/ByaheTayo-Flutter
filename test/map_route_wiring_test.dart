// Wiring: the Map tab loads admin-added routes + fare overrides in
// production (Nov 7, 2026 — follow-up to the fare/direction
// editing work). Before this, MapTab accepted a
// customRouteRepository but never loaded it, and the Map sheet
// used only its own knownBusFares table — so Add Route via stops
// never changed the map line and Fares-side edits never reached
// the Map sheet. These tests cover the matching + effective-fare
// + via-points logic (pure helpers) and the sheet end to end
// (MapTab pumped with fake repos — the native MapLibre view
// cannot render in flutter test, but the sheet + controls work).
import 'package:estudyantego/features/bus_stops.dart';
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/map_tab.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/route_fare_overrides.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCustomRouteRepository implements CustomRouteRepository {
  _FakeCustomRouteRepository(this.routes);
  final List<CustomRoute> routes;

  @override
  Future<List<CustomRoute>> loadAll() async => routes;

  @override
  Future<CustomRoute> create(
    CustomRoute route,
    AuthUser author, {
    List<BusStop> busStops = const [],
  }) =>
      throw UnimplementedError();

  @override
  Future<CustomRoute> update(
    CustomRoute route,
    AuthUser author, {
    List<BusStop> busStops = const [],
  }) =>
      throw UnimplementedError();

  @override
  Future<void> delete(CustomRoute route, AuthUser author) =>
      throw UnimplementedError();
}

class _FakeOverrideRepository implements RouteFareOverrideRepository {
  _FakeOverrideRepository(this.overrides);
  final Map<String, RouteFareOverride> overrides;

  @override
  Future<Map<String, RouteFareOverride>> loadAll() async => overrides;

  @override
  Future<RouteFareOverride> save(
    RouteFareOverride override,
    AuthUser author,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String routeKey, AuthUser author) =>
      throw UnimplementedError();
}

const _viganTerminal = 'Vigan Bus Terminal';

CustomRoute _customRoute({
  String from = 'Cabugao',
  String to = _viganTerminal,
  double fare = 70,
  double? studentFare,
  List<String> viaHubs = const [],
}) =>
    CustomRoute(
      from: from,
      to: to,
      operator: 'Partas',
      vehicle: 'Bus',
      fare: fare,
      studentFare: studentFare,
      viaHubs: viaHubs,
    );

Future<void> _pumpMap(
  WidgetTester tester, {
  List<CustomRoute> customs = const [],
  Map<String, RouteFareOverride> overrides = const {},
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => faresMapJump.value = null);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MapTab(
          customRouteRepository: _FakeCustomRouteRepository(customs),
          fareOverrideRepository: _FakeOverrideRepository(overrides),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('matchCustomRoute', () {
    final customs = [
      _customRoute(),
      _customRoute(from: 'Laoag Terminal', to: 'Vigan Bus Terminal'),
    ];

    test('finds a custom route by exact From|To', () {
      final match = matchCustomRoute(customs, 'Cabugao', _viganTerminal);
      expect(match, isNotNull);
      expect(match!.operator, 'Partas');
      expect(match.fare, 70);
    });

    test('returns null when no custom route matches the pair', () {
      expect(
        matchCustomRoute(customs, 'Cabugao', 'San Juan, Ilocos Sur'),
        isNull,
      );
      expect(
        matchCustomRoute(customs, 'Sinait', _viganTerminal),
        isNull,
      );
    });

    test('a GPS origin never matches a hub-named custom route', () {
      expect(
        matchCustomRoute(customs, 'Your location', _viganTerminal),
        isNull,
      );
    });
  });

  group('routeViaPoints', () {
    test('custom route: via stops in order, endpoints excluded', () {
      final route = customRouteToRouteInfo(
        _customRoute(viaHubs: ['San Juan, Ilocos Sur']),
      );
      final via = routeViaPoints(route, null);
      expect(via, hasLength(1));
      final sanJuan = hubByName('San Juan, Ilocos Sur')!;
      expect(via.first.latitude, sanJuan.lat);
      expect(via.first.longitude, sanJuan.lng);
    });

    test('custom route with no via stops has no via points', () {
      final route = customRouteToRouteInfo(_customRoute());
      expect(routeViaPoints(route, null), isEmpty);
    });

    test('seeded route: override via stops in order', () {
      final route = RouteInfo(
        originName: 'Cabugao',
        dest: hubByName(_viganTerminal)!,
        roadKm: 31.6,
        direction: Direction.northbound,
      );
      final override = RouteFareOverride(
        routeKey: 'Cabugao|$_viganTerminal',
        viaHubs: ['San Juan, Ilocos Sur', 'Sinait'],
      );
      final via = routeViaPoints(route, override);
      expect(via, hasLength(2));
      expect(via.first.latitude, hubByName('San Juan, Ilocos Sur')!.lat);
      expect(via.last.latitude, hubByName('Sinait')!.lat);
    });

    test('seeded route with no override has no via points', () {
      final route = RouteInfo(
        originName: 'Cabugao',
        dest: hubByName(_viganTerminal)!,
        roadKm: 31.6,
        direction: Direction.northbound,
      );
      expect(routeViaPoints(route, null), isEmpty);
      expect(
        routeViaPoints(
          route,
          const RouteFareOverride(routeKey: 'Cabugao|$_viganTerminal'),
        ),
        isEmpty,
      );
    });
  });

  group('resolveMapSheetFares', () {
    test('no override: the verified fare wins (Cabugao → Vigan ₱60/₱48)',
        () {
      final fares = resolveMapSheetFares(
        from: 'Cabugao',
        to: _viganTerminal,
      );
      expect(fares.regular, 60);
      expect(fares.discounted, 48);
    });

    test('override fare wins over the verified fare', () {
      final fares = resolveMapSheetFares(
        from: 'Cabugao',
        to: _viganTerminal,
        override: const RouteFareOverride(
          routeKey: 'Cabugao|$_viganTerminal',
          fare: 65,
        ),
      );
      expect(fares.regular, 65);
      // Blank student fare still derives 20% off the EFFECTIVE fare.
      expect(fares.discounted, 52);
    });

    test('override student fare is used as-is', () {
      final fares = resolveMapSheetFares(
        from: 'Cabugao',
        to: _viganTerminal,
        override: const RouteFareOverride(
          routeKey: 'Cabugao|$_viganTerminal',
          fare: 65,
          studentFare: 50,
        ),
      );
      expect(fares.regular, 65);
      expect(fares.discounted, 50);
    });

    test('override with only via stops leaves the verified fare alone',
        () {
      final fares = resolveMapSheetFares(
        from: 'Cabugao',
        to: _viganTerminal,
        override: const RouteFareOverride(
          routeKey: 'Cabugao|$_viganTerminal',
          viaHubs: ['San Juan, Ilocos Sur'],
        ),
      );
      expect(fares.regular, 60);
      expect(fares.discounted, 48);
    });

    test('unset pair stays "Fare not set" (null, never a formula fare)',
        () {
      final fares = resolveMapSheetFares(
        from: _viganTerminal,
        to: 'San Juan, Ilocos Sur',
      );
      expect(fares.regular, isNull);
      expect(fares.discounted, isNull);
    });

    test('an unset pair can be set by an override', () {
      final fares = resolveMapSheetFares(
        from: _viganTerminal,
        to: 'San Juan, Ilocos Sur',
        override: const RouteFareOverride(
          routeKey: '$_viganTerminal|San Juan, Ilocos Sur',
          fare: 45,
        ),
      );
      expect(fares.regular, 45);
      expect(fares.discounted, 36);
    });

    test('custom route fares win, student fare derives when blank', () {
      final custom = resolveMapSheetFares(
        customRoute: _customRoute(fare: 70),
        from: 'Cabugao',
        to: _viganTerminal,
      );
      expect(custom.regular, 70);
      expect(custom.discounted, 56);
      final explicit = resolveMapSheetFares(
        customRoute: _customRoute(fare: 70, studentFare: 55),
        from: 'Cabugao',
        to: _viganTerminal,
      );
      expect(explicit.regular, 70);
      expect(explicit.discounted, 55);
    });
  });

  group('Map sheet wiring (fake repos)', () {
    testWidgets('sheet shows an admin override fare + student fare',
        (tester) async {
      await _pumpMap(
        tester,
        overrides: {
          'Cabugao|$_viganTerminal': const RouteFareOverride(
            routeKey: 'Cabugao|$_viganTerminal',
            fare: 65,
            studentFare: 50,
          ),
        },
      );

      expect(find.text('Cabugao → Vigan Bus Terminal'), findsWidgets);
      expect(find.text('₱65'), findsOneWidget);
      expect(find.text('₱50'), findsOneWidget);
      // An admin-set fare supersedes the Oct 16 verified claim.
      expect(find.text('VERIFIED FARE'), findsNothing);
    });

    testWidgets('sheet falls back to the verified fare with no override',
        (tester) async {
      await _pumpMap(tester);

      expect(find.text('Cabugao → Vigan Bus Terminal'), findsWidgets);
      expect(find.text('₱60'), findsOneWidget);
      expect(find.text('₱48'), findsOneWidget);
      expect(find.text('VERIFIED FARE'), findsOneWidget);
    });

    testWidgets('sheet shows "Fare not set" for an unset pair',
        (tester) async {
      await _pumpMap(tester);

      faresMapJump.value = (
        from: _viganTerminal,
        to: 'San Juan, Ilocos Sur',
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Vigan Bus Terminal → San Juan, Ilocos Sur'),
        findsWidgets,
      );
      expect(find.text('Fare not set'), findsWidgets);
      expect(find.text('VERIFIED FARE'), findsNothing);
    });

    testWidgets('a matched custom route drives the sheet fares',
        (tester) async {
      await _pumpMap(
        tester,
        customs: [
          _customRoute(
            fare: 70,
            studentFare: 55,
            viaHubs: ['San Juan, Ilocos Sur'],
          ),
        ],
      );

      expect(find.text('Cabugao → Vigan Bus Terminal'), findsWidgets);
      expect(find.text('₱70'), findsOneWidget);
      expect(find.text('₱55'), findsOneWidget);
      expect(find.text('VERIFIED FARE'), findsNothing);
    });
  });
}
