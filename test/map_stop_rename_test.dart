// Stop rename dialog (Nov 8, 2026): the pencil in a drawn
// stop's card renames the stop (admin only, Steven Nov 7, 20:54:
// "Dapat May Name: Stops along the way, Hindi lang puro Point
// nga name."). The dialog used to dispose its
// TextEditingController right after `await showDialog` returned
// — too early: the route is still in the overlay animating out,
// its dependencies change on pop, and the rebuilding TextField
// reads the disposed controller ("TextEditingController was used
// after being disposed"). The fix owns the controller in a
// StatefulWidget dialog (same fix as the Files rename in
// study_tab.dart). These tests drive the full flow: open the
// stop card, tap the pencil, rename, save — and assert no
// disposed-controller error is reported.
import 'package:estudyantego/features/bus_stops.dart';
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/map_tab.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/route_fare_overrides.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _admin = AuthUser(uid: 'admin-1', email: 'stevenjoereyes0625@gmail.com');
const _viganTerminal = 'Vigan Bus Terminal';

CustomRoute _customRoute({List<RouteWaypoint> viaWaypoints = const []}) =>
    CustomRoute(
      from: 'Cabugao',
      to: _viganTerminal,
      operator: 'Partas',
      vehicle: 'Bus',
      fare: 60,
      viaWaypoints: viaWaypoints,
    );

class _FakeCustomRouteRepository implements CustomRouteRepository {
  _FakeCustomRouteRepository(this.routes);

  final List<CustomRoute> routes;
  CustomRoute? updated;

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
  }) async {
    updated = route;
    // Persist like the real repos, so a reload after the save
    // shows the renamed stop.
    final index =
        routes.indexWhere((r) => r.from == route.from && r.to == route.to);
    if (index >= 0) routes[index] = route;
    return route;
  }

  @override
  Future<void> delete(CustomRoute route, AuthUser author) =>
      throw UnimplementedError();
}

class _FakeOverrideRepository implements RouteFareOverrideRepository {
  @override
  Future<Map<String, RouteFareOverride>> loadAll() async => const {};

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

class _FakeBusStopRepository implements BusStopRepository {
  @override
  Future<List<BusStop>> loadAll() async => const [];

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

Future<_FakeCustomRouteRepository> _pumpMap(
  WidgetTester tester, {
  List<RouteWaypoint> viaWaypoints = const [],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => faresMapJump.value = null);
  addTearDown(() => mapLineMakerRequest.value = null);
  final customs = _FakeCustomRouteRepository([_customRoute(
    viaWaypoints: viaWaypoints,
  )]);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MapTab(
          currentUser: _admin,
          customRouteRepository: customs,
          fareOverrideRepository: _FakeOverrideRepository(),
          busStopRepository: _FakeBusStopRepository(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return customs;
}

/// Opens the rename dialog for the drawn stop whose list row
/// reads [stopLabel] (e.g. 'Point 1' for an unnamed waypoint).
Future<void> _openRenameDialog(
  WidgetTester tester,
  String stopLabel,
) async {
  await tester.ensureVisible(find.text(stopLabel));
  await tester.pumpAndSettle();
  await tester.tap(find.text(stopLabel));
  await tester.pumpAndSettle();
  expect(find.byTooltip('Rename this stop'), findsOneWidget);
  await tester.tap(find.byTooltip('Rename this stop'));
  await tester.pumpAndSettle();
  expect(find.text('Rename this stop'), findsOneWidget);
}

void main() {
  group('stop rename dialog', () {
    testWidgets('renaming a drawn stop saves the new name',
        (tester) async {
      final customs = await _pumpMap(
        tester,
        viaWaypoints: const [
          RouteWaypoint(lat: 17.65, lng: 120.40),
        ],
      );
      await _openRenameDialog(tester, 'Point 1');
      await tester.enterText(
        find.widgetWithText(TextField, 'Stop name'),
        'Sinait Market',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      // The disposed-controller error (if the dialog still
      // disposes its controller right after showDialog returns)
      // is reported during the pop animation's rebuilds.
      expect(tester.takeException(), isNull);
      expect(find.text('Stop renamed.'), findsOneWidget);
      expect(
        customs.updated?.viaWaypoints.first.name,
        'Sinait Market',
      );
      expect(find.text('Sinait Market'), findsOneWidget);
    });

    testWidgets('empty and over-long names are rejected',
        (tester) async {
      final customs = await _pumpMap(
        tester,
        viaWaypoints: const [
          RouteWaypoint(lat: 17.65, lng: 120.40),
        ],
      );
      await _openRenameDialog(tester, 'Point 1');
      await tester.enterText(
        find.widgetWithText(TextField, 'Stop name'),
        '   ',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name for the stop.'), findsOneWidget);
      // Dialog stays open; nothing was saved.
      expect(find.text('Rename this stop'), findsOneWidget);
      expect(customs.updated, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Stop name'),
        'a' * 101,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('The name must be 100 characters or fewer.'),
        findsOneWidget,
      );
      expect(customs.updated, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(customs.updated, isNull);
    });

    testWidgets('the dialog pre-fills the stop\'s current name',
        (tester) async {
      await _pumpMap(
        tester,
        viaWaypoints: const [
          RouteWaypoint(name: 'Old Market', lat: 17.65, lng: 120.40),
        ],
      );
      await _openRenameDialog(tester, 'Old Market');
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Stop name'),
      );
      expect(field.controller?.text, 'Old Market');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
