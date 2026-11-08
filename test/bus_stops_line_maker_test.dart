// Bus stop adder + map line maker + PWD/Senior editable fares +
// Add Transportation Bus (Nov 7, 2026): an admin taps the map to
// place a new bus stop (saved to Firestore, usable at once as a
// From/To endpoint and a via stop), draws a route's line by
// tapping points in order (saved as the route's direction), sets
// the PWD / Senior Citizen discount fares per route, and adds bus
// companies to the operator chips. These tests cover the models +
// validation + repositories + pure line/fare helpers, and the
// entry points at widget level (the native MapLibre view cannot
// render in flutter test, but the sheet + controls work).
import 'package:estudyantego/features/add_route_sheet.dart';
import 'package:estudyantego/features/bus_companies.dart';
import 'package:estudyantego/features/bus_stops.dart';
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/map_tab.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/osm_routing.dart';
import 'package:estudyantego/features/philippine_places.dart';
import 'package:estudyantego/features/route_fare_overrides.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _admin = AuthUser(uid: 'admin-1', email: 'stevenjoereyes0625@gmail.com');
const _nonAdmin = AuthUser(uid: 'user-1', email: 'someone@example.com');
const _viganTerminal = 'Vigan Bus Terminal';

BusStop _stop({
  String name = 'Cabugao Public Market',
  String region = 'Ilocos Sur',
  double lat = 17.79,
  double lng = 120.45,
}) =>
    BusStop(name: name, region: region, lat: lat, lng: lng);

CustomRoute _customRoute({
  String from = 'Cabugao',
  String to = _viganTerminal,
  double fare = 60,
  double? pwdFare,
  double? seniorFare,
  List<String> viaHubs = const [],
  List<RouteWaypoint> viaWaypoints = const [],
}) =>
    CustomRoute(
      from: from,
      to: to,
      operator: 'Partas',
      vehicle: 'Bus',
      fare: fare,
      pwdFare: pwdFare,
      seniorFare: seniorFare,
      viaHubs: viaHubs,
      viaWaypoints: viaWaypoints,
    );

class _FakeBusStopRepository implements BusStopRepository {
  _FakeBusStopRepository(this.stops);
  List<BusStop> stops;

  @override
  Future<List<BusStop>> loadAll() async => stops;

  @override
  Future<BusStop> create(BusStop stop, AuthUser author) =>
      throw UnimplementedError();

  @override
  Future<BusStop> update(BusStop stop, AuthUser author) =>
      throw UnimplementedError();

  @override
  Future<void> delete(BusStop stop, AuthUser author) =>
      throw UnimplementedError();
}

class _FakeBusCompanyRepository implements BusCompanyRepository {
  _FakeBusCompanyRepository(this.companies);
  List<BusCompany> companies;

  @override
  Future<List<BusCompany>> loadAll() async => companies;

  @override
  Future<BusCompany> create(BusCompany company, AuthUser author) =>
      throw UnimplementedError();

  @override
  Future<void> delete(BusCompany company, AuthUser author) =>
      throw UnimplementedError();
}

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

Future<void> _pumpMap(
  WidgetTester tester, {
  AuthUser? currentUser,
  List<CustomRoute> customs = const [],
  Map<String, RouteFareOverride> overrides = const {},
  List<BusStop> stops = const [],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => faresMapJump.value = null);
  addTearDown(() => mapLineMakerRequest.value = null);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MapTab(
          currentUser: currentUser,
          customRouteRepository: _FakeCustomRouteRepository(customs),
          fareOverrideRepository: _FakeOverrideRepository(overrides),
          busStopRepository: _FakeBusStopRepository(stops),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('validateBusStop', () {
    test('empty name is blocked', () {
      expect(
        validateBusStop(
          name: '  ',
          region: 'Ilocos Sur',
          lat: 17.79,
          lng: 120.45,
        ),
        'Enter a name for the bus stop.',
      );
    });

    test('a name over 100 characters is blocked', () {
      expect(
        validateBusStop(
          name: 'A' * 101,
          region: 'Ilocos Sur',
          lat: 17.79,
          lng: 120.45,
        ),
        'The name must be 100 characters or fewer.',
      );
    });

    test('"Your location" is reserved for the GPS origin', () {
      expect(
        validateBusStop(
          name: 'your LOCATION',
          region: 'Ilocos Sur',
          lat: 17.79,
          lng: 120.45,
        ),
        'That name is reserved for the GPS origin.',
      );
    });

    test('an unknown region is blocked', () {
      expect(
        validateBusStop(
          name: 'New Stop',
          region: 'Not a region',
          lat: 17.79,
          lng: 120.45,
        ),
        'Choose a region.',
      );
    });

    test('coordinates outside the map are blocked', () {
      expect(
        validateBusStop(
          name: 'New Stop',
          region: 'Ilocos Sur',
          lat: 91,
          lng: 120.45,
        ),
        'That point is not a valid place on the map.',
      );
    });

    test('a duplicate of a built-in hub is blocked (case-insensitive)', () {
      expect(
        validateBusStop(
          name: 'cabugao',
          region: 'Ilocos Sur',
          lat: 17.79,
          lng: 120.45,
        ),
        'A stop with this name already exists.',
      );
    });

    test('a duplicate of an existing stop is blocked', () {
      expect(
        validateBusStop(
          name: 'cabugao public market',
          region: 'Ilocos Sur',
          lat: 17.8,
          lng: 120.46,
          existingStops: [_stop()],
        ),
        'A stop with this name already exists.',
      );
    });

    test('a valid new stop passes', () {
      expect(
        validateBusStop(
          name: 'Cabugao Public Market',
          region: 'Ilocos Sur',
          lat: 17.79,
          lng: 120.45,
        ),
        isNull,
      );
    });
  });

  group('allHubs / resolveHub', () {
    test('built-in hubs keep their indices; stops append after them, '
        'then the bundled Philippines list', () {
      final merged = allHubs([_stop()]);
      expect(merged.length, hubs.length + 1 + philippinePlaces.length);
      expect(merged[2].name, 'Cabugao');
      expect(merged[14].name, _viganTerminal);
      expect(merged[16].name, 'Cabugao Public Market');
      expect(merged[16].region, 'Ilocos Sur');
      expect(merged.last.name, philippinePlaces.last.name);
    });

    test('a new stop resolves by name; unknown names stay null', () {
      expect(resolveHub('Cabugao Public Market', [_stop()]), isNotNull);
      expect(resolveHub('No Such Place', [_stop()]), isNull);
      expect(resolveHub('Cabugao', [_stop()])!.lat, 17.78916);
    });

    test('hubRegions lists the built-in regions, first-seen order', () {
      final regions = hubRegions();
      expect(regions, isNotEmpty);
      expect(regions.first, 'Ilocos Region');
      expect(regions, contains('Ilocos Sur'));
    });
  });

  group('RouteWaypoint', () {
    test('JSON round-trips named and unnamed points', () {
      const named = RouteWaypoint(name: 'San Juan', lat: 17.7, lng: 120.4);
      expect(RouteWaypoint.fromJson(named.toJson()), named);
      const raw = RouteWaypoint(lat: 17.7, lng: 120.4);
      final decoded = RouteWaypoint.fromJson(raw.toJson());
      expect(decoded, raw);
      expect(decoded!.name, isNull);
    });

    test('bad JSON is skipped, never guessed', () {
      expect(RouteWaypoint.fromJson({'lat': 'x', 'lng': 120.4}), isNull);
      expect(RouteWaypoint.fromJson('nope'), isNull);
    });

    test('copyWith renames a point (Save as bus stop)', () {
      const raw = RouteWaypoint(lat: 17.7, lng: 120.4);
      final named = raw.copyWith(name: 'Cabugao Public Market');
      expect(named.name, 'Cabugao Public Market');
      expect(named.lat, 17.7);
      expect(named.lng, 120.4);
    });
  });

  group('effectiveRouteWaypoints', () {
    final named = [
      const RouteWaypoint(name: 'San Juan', lat: 17.7, lng: 120.4),
    ];

    test('a drawn line wins over the named via stops', () {
      final waypoints = effectiveRouteWaypoints(
        customRoute: _customRoute(
          viaHubs: ['San Juan, Ilocos Sur'],
          viaWaypoints: named,
        ),
      );
      expect(waypoints, named);
    });

    test('named via stops resolve when nothing was drawn', () {
      final waypoints = effectiveRouteWaypoints(
        customRoute: _customRoute(viaHubs: ['San Juan, Ilocos Sur']),
      );
      expect(waypoints, hasLength(1));
      expect(waypoints.first.name, 'San Juan, Ilocos Sur');
    });

    test('an override drawn line wins for a seeded route', () {
      final waypoints = effectiveRouteWaypoints(
        override: RouteFareOverride(
          routeKey: 'Cabugao|$_viganTerminal',
          viaWaypoints: named,
        ),
      );
      expect(waypoints, named);
    });

    test('no direction at all yields an empty list', () {
      expect(effectiveRouteWaypoints(customRoute: _customRoute()), isEmpty);
      expect(
        effectiveRouteWaypoints(
          override: const RouteFareOverride(routeKey: 'Cabugao|Vigan Bus Terminal'),
        ),
        isEmpty,
      );
    });
  });

  group('LocalBusStopRepository', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('an admin creates a stop; it loads back and bumps the notifier', () async {
      final repo = LocalBusStopRepository();
      final before = busStopsChanged.value;
      final created = await repo.create(_stop(), _admin);
      expect(created.id, isNotNull);
      expect(created.authorEmail, _admin.email);
      expect(busStopsChanged.value, greaterThan(before));
      final loaded = await repo.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.first.name, 'Cabugao Public Market');
    });

    test('a non-admin cannot create a stop', () async {
      final repo = LocalBusStopRepository();
      await expectLater(repo.create(_stop(), _nonAdmin), throwsStateError);
      expect(await repo.loadAll(), isEmpty);
    });

    test('a duplicate name is rejected', () async {
      final repo = LocalBusStopRepository();
      await repo.create(_stop(), _admin);
      await expectLater(
        repo.create(_stop(lat: 17.8, lng: 120.46), _admin),
        throwsArgumentError,
      );
      expect(await repo.loadAll(), hasLength(1));
    });

    test('update changes the region only; a rename is rejected', () async {
      final repo = LocalBusStopRepository();
      final created = await repo.create(_stop(), _admin);
      final updated = await repo.update(
        created.copyWith(region: 'Ilocos Norte'),
        _admin,
      );
      expect(updated.region, 'Ilocos Norte');
      expect(updated.name, 'Cabugao Public Market');
      await expectLater(
        repo.update(created.copyWith(name: 'Renamed'), _admin),
        throwsArgumentError,
      );
    });

    test('delete removes the stop', () async {
      final repo = LocalBusStopRepository();
      final created = await repo.create(_stop(), _admin);
      await repo.delete(created, _admin);
      expect(await repo.loadAll(), isEmpty);
    });
  });

  group('bus companies', () {
    test('validateBusCompany blocks empty, preset, and saved duplicates', () {
      expect(validateBusCompany('  '), 'Enter the company name.');
      expect(validateBusCompany('partas'), 'That company is already in the list.');
      expect(
        validateBusCompany(
          'florida bus',
          existingCompanies: [
            const BusCompany(name: 'Florida Bus'),
          ],
        ),
        'That company is already in the list.',
      );
      expect(validateBusCompany('Florida Bus'), isNull);
    });

    test('allOperators keeps presets first and drops preset duplicates', () {
      final operators = allOperators([
        const BusCompany(name: 'Florida Bus'),
        const BusCompany(name: 'partas'),
      ]);
      expect(operators.sublist(0, 12), customRouteOperatorPresets);
      expect(operators, contains('Florida Bus'));
      expect(operators.where((o) => o.toLowerCase() == 'partas'), hasLength(1));
    });

    test('LocalBusCompanyRepository dedupes: same name twice is one entry', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = LocalBusCompanyRepository();
      final first = await repo.create(
        const BusCompany(name: 'Florida Bus'),
        _admin,
      );
      final second = await repo.create(
        const BusCompany(name: 'florida bus'),
        _admin,
      );
      expect(second.id, first.id);
      expect(await repo.loadAll(), hasLength(1));
      await expectLater(
        repo.create(const BusCompany(name: 'Florida Bus'), _nonAdmin),
        throwsStateError,
      );
    });
  });

  group('PWD / Senior editable fares', () {
    test('CustomRoute JSON round-trips pwdFare and seniorFare', () {
      final route = _customRoute(pwdFare: 40, seniorFare: 45);
      final decoded = CustomRoute.fromJson('r1', route.toJson());
      expect(decoded.pwdFare, 40);
      expect(decoded.seniorFare, 45);
      final blank = _customRoute();
      expect(blank.toJson(), isNot(contains('pwdFare')));
      expect(CustomRoute.fromJson('r2', blank.toJson()).pwdFare, isNull);
    });

    test('validateCustomRouteObject rejects non-positive discount fares', () {
      expect(
        validateCustomRouteObject(_customRoute(pwdFare: 0)),
        'The PWD fare must be more than ₱0.',
      );
      expect(
        validateCustomRouteObject(_customRoute(seniorFare: -5)),
        'The Senior Citizen fare must be more than ₱0.',
      );
      expect(validateCustomRouteObject(_customRoute(pwdFare: 40)), isNull);
    });

    test('RouteFareOverride JSON round-trips; empty check covers the new fields', () {
      const empty = RouteFareOverride(routeKey: 'Cabugao|Vigan Bus Terminal');
      expect(routeFareOverrideIsEmpty(empty), isTrue);
      final withPwd = RouteFareOverride(
        routeKey: 'Cabugao|$_viganTerminal',
        pwdFare: 40,
        viaWaypoints: const [RouteWaypoint(lat: 17.7, lng: 120.4)],
      );
      expect(routeFareOverrideIsEmpty(withPwd), isFalse);
      final decoded = RouteFareOverride.fromJson('k', withPwd.toJson());
      expect(decoded.pwdFare, 40);
      expect(decoded.viaWaypoints, hasLength(1));
      expect(
        validateRouteFareOverride(
          RouteFareOverride(routeKey: 'k', seniorFare: 0),
        ),
        'The Senior Citizen fare must be more than ₱0.',
      );
    });

    test('PopularRoute derives 20% off when no admin fare is set', () {
      const route = PopularRoute(
        from: 'Cabugao',
        to: _viganTerminal,
        vehicle: 'Bus',
        fare: 60,
      );
      expect(route.effectivePwdFare, 48);
      expect(route.effectiveSeniorFare, 48);
      const set = PopularRoute(
        from: 'Cabugao',
        to: _viganTerminal,
        vehicle: 'Bus',
        fare: 60,
        pwdFare: 40,
        seniorFare: 45,
      );
      expect(set.effectivePwdFare, 40);
      expect(set.effectiveSeniorFare, 45);
      final merged = route.applyOverride(
        const RouteFareOverride(
          routeKey: 'Cabugao|Vigan Bus Terminal',
          pwdFare: 42,
        ),
      );
      expect(merged.effectivePwdFare, 42);
      expect(merged.effectiveSeniorFare, 48);
    });
  });

  group('routeStops with a drawn line', () {
    final dest = hubByName(_viganTerminal)!;
    const origin = LatLng(17.78916, 120.45838); // Cabugao.

    test('unnamed waypoints show as "Point N" in tap order', () {
      final stops = routeStops(
        origin: origin,
        originName: 'Cabugao',
        dest: dest,
        roadPoints: null,
        totalKm: 31.6,
        viaWaypoints: const [
          RouteWaypoint(lat: 17.7, lng: 120.4),
          RouteWaypoint(lat: 17.65, lng: 120.39),
        ],
      );
      expect(
        stops.map((s) => s.name).toList(),
        ['Cabugao', 'Point 1', 'Point 2', _viganTerminal],
      );
    });

    test('a named waypoint keeps its name and region', () {
      final stops = routeStops(
        origin: origin,
        originName: 'Cabugao',
        dest: dest,
        roadPoints: null,
        totalKm: 31.6,
        viaWaypoints: const [
          RouteWaypoint(name: 'San Juan, Ilocos Sur', lat: 17.7, lng: 120.4),
        ],
        extraStops: [_stop(name: 'San Juan, Ilocos Sur')],
      );
      final middle = stops[1];
      expect(middle.name, 'San Juan, Ilocos Sur');
      expect(middle.region, 'Ilocos Sur');
    });

    test('a drawn line wins over the named via stops', () {
      final stops = routeStops(
        origin: origin,
        originName: 'Cabugao',
        dest: dest,
        roadPoints: null,
        totalKm: 31.6,
        viaHubNames: const ['San Juan, Ilocos Sur'],
        viaWaypoints: const [RouteWaypoint(lat: 17.7, lng: 120.4)],
      );
      expect(stops.map((s) => s.name), isNot(contains('San Juan, Ilocos Sur')));
      expect(stops.map((s) => s.name), contains('Point 1'));
    });
  });

  group('line maker helpers', () {
    test('osrmRouteUrlForPoints lists the points in order', () {
      final url = osrmRouteUrlForPoints([
        const LatLng(17.78916, 120.45838),
        const LatLng(17.7, 120.4),
        const LatLng(17.56641, 120.38590),
      ]);
      expect(
        url,
        'https://router.project-osrm.org/route/v1/driving/'
        '120.45838,17.78916;120.4,17.7;120.3859,17.56641'
        '?overview=full&geometries=geojson&steps=true',
      );
    });

    test('routesFrom reaches an admin-added stop as a destination', () {
      final routes = routesFrom(17.78916, 120.45838, 'Cabugao', [_stop()]);
      expect(
        routes.map((r) => r.dest.name),
        contains('Cabugao Public Market'),
      );
    });

    test('resolveMapSheetFares honors pwd/senior with custom → override → derived', () {
      final custom = resolveMapSheetFares(
        customRoute: _customRoute(pwdFare: 40, seniorFare: 45),
        from: 'Cabugao',
        to: _viganTerminal,
      );
      expect(custom.pwd, 40);
      expect(custom.senior, 45);
      final overridden = resolveMapSheetFares(
        override: const RouteFareOverride(
          routeKey: 'Cabugao|Vigan Bus Terminal',
          pwdFare: 42,
        ),
        from: 'Cabugao',
        to: _viganTerminal,
      );
      expect(overridden.pwd, 42);
      expect(overridden.senior, 48);
      final derived = resolveMapSheetFares(from: 'Cabugao', to: _viganTerminal);
      expect(derived.regular, 60);
      expect(derived.pwd, 48);
      expect(derived.senior, 48);
      final unset = resolveMapSheetFares(
        from: 'Vigan Bus Terminal',
        to: 'San Juan, Ilocos Sur',
      );
      expect(unset.pwd, isNull);
      expect(unset.senior, isNull);
    });
  });

  group('AddRouteSheet entry points (admin)', () {
    testWidgets('shows Add bus stop, PWD/Senior fields, and Add company',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AddRouteSheet(
                repository: _FakeCustomRouteRepository([]),
                author: _admin,
                busStops: [_stop()],
                busCompanies: const [],
                companyRepository: _FakeBusCompanyRepository([]),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add bus stop'), findsOneWidget);
      expect(find.text('PWD fare (₱)'), findsOneWidget);
      expect(find.text('Senior fare (₱)'), findsOneWidget);
      expect(find.text('Add company'), findsOneWidget);
      // The new stop is a From/To choice — via the searchable
      // picker (the old via-stops chip wall is gone).
      await tester.tap(find.text('Choose a place').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(CupertinoTextField),
        'Cabugao Public Market',
      );
      await tester.pump();
      // The search field itself holds the query text, so scope the
      // finder to the list row.
      final row = find.widgetWithText(ListTile, 'Cabugao Public Market');
      expect(row, findsOneWidget);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
        find.text('Cabugao Public Market · Ilocos Sur'),
        findsOneWidget,
      );
    });
  });

  group('MapTab line maker (widget level)', () {
    testWidgets('admin sees Draw line; tapping it opens the draw bar',
        (tester) async {
      await _pumpMap(tester, currentUser: _admin);

      expect(find.text('Draw line'), findsOneWidget);
      await tester.tap(find.text('Draw line'));
      await tester.pumpAndSettle();

      expect(find.text('Save line'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(
        find.textContaining('Tap the map to add points in order'),
        findsOneWidget,
      );
    });

    testWidgets('a non-admin never sees Draw line', (tester) async {
      await _pumpMap(tester, currentUser: _nonAdmin);
      expect(find.text('Draw line'), findsNothing);
    });

    testWidgets('add-stop mode opens from the Fares request', (tester) async {
      await _pumpMap(tester, currentUser: _admin);
      mapLineMakerRequest.value = (drawLine: false, addStop: true);
      await tester.pumpAndSettle();

      expect(
        find.text('Tap the map to place the new bus stop'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save line'), findsNothing);
    });
  });

  group('FaresTab admin entries', () {
    Future<void> pumpFares(WidgetTester tester, AuthUser? user) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: FaresTab(currentUser: user))),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
        'admin actions moved out of the Fares tab (Admin Access section)',
        (tester) async {
      // Nov 8, 2026 organize: Add Route / Manage bus stops /
      // Reset all directions live in the Account tab's Admin
      // Access section now — the Fares tab keeps only the
      // route-specific entries (Edit route in the sheet, Remove
      // on the card).
      await pumpFares(tester, _admin);
      expect(find.text('Add Route'), findsNothing);
      expect(find.text('Manage bus stops'), findsNothing);
      expect(find.text('Reset all directions'), findsNothing);
    });

    testWidgets('a non-admin sees neither admin entry', (tester) async {
      await pumpFares(tester, _nonAdmin);
      expect(find.text('Add Route'), findsNothing);
      expect(find.text('Manage bus stops'), findsNothing);
    });
  });

  group('set Start/End mode', () {
    testWidgets('admin sees Set Start/End; tapping it opens the bar',
        (tester) async {
      await _pumpMap(tester, currentUser: _admin);

      expect(find.text('Set Start/End'), findsOneWidget);
      await tester.tap(find.text('Set Start/End'));
      await tester.pumpAndSettle();

      expect(
        find.text('Tap the map to place the Start pin'),
        findsOneWidget,
      );
      expect(find.text('Name & save'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('a non-admin never sees Set Start/End', (tester) async {
      await _pumpMap(tester, currentUser: _nonAdmin);
      expect(find.text('Set Start/End'), findsNothing);
    });

    testWidgets('Name & save and Clear are disabled until pins exist',
        (tester) async {
      await _pumpMap(tester, currentUser: _admin);
      await tester.tap(find.text('Set Start/End'));
      await tester.pumpAndSettle();

      // No pins placed yet: the actions wait for the taps.
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Name & save'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.ancestor(
                of: find.text('Clear'),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('Cancel exits the mode and the sheet returns',
        (tester) async {
      await _pumpMap(tester, currentUser: _admin);
      await tester.tap(find.text('Set Start/End'));
      await tester.pumpAndSettle();
      expect(
        find.text('Tap the map to place the Start pin'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(
        find.text('Tap the map to place the Start pin'),
        findsNothing,
      );
      expect(find.text('Set Start/End'), findsOneWidget);
    });
  });
}
