// Map 3D toggle (Steven, Nov 8, 2026: "Oo, lagyan mo ng 3D
// toggle"): a 2D/3D switch on the Map tab — 2D is the flat
// top-down default, 3D is a perspective tilt (60°) keeping the
// bearing. Satellite is NOT offered (separate imagery source,
// not approved). The native MapLibre map cannot render in
// flutter test (mapLibreSupported is false on the Linux host),
// so these tests cover the pure mode mapping and the toggle
// widget: the pill offers exactly 2D + 3D, tapping flips the
// selected mode without a native map, and the switch never
// touches route state. The camera animation itself is verified
// by analyze + the on-device check.
import 'package:estudyantego/features/bus_stops.dart';
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/ios_components.dart';
import 'package:estudyantego/features/map_tab.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/route_fare_overrides.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCustomRouteRepository implements CustomRouteRepository {
  @override
  Future<List<CustomRoute>> loadAll() async => const [];

  @override
  Future<CustomRoute> create(
    CustomRoute route,
    AuthUser author, {
    List<BusStop> busStops = const [],
  }) => throw UnimplementedError();

  @override
  Future<CustomRoute> update(
    CustomRoute route,
    AuthUser author, {
    List<BusStop> busStops = const [],
  }) => throw UnimplementedError();

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
  ) => throw UnimplementedError();

  @override
  Future<void> delete(String routeKey, AuthUser author) =>
      throw UnimplementedError();
}

void main() {
  group('mapViewModeOptions', () {
    test('offers exactly 2D and 3D — never Satellite', () {
      expect(mapViewModeOptions, [
        MapViewMode.standard2d,
        MapViewMode.perspective3d,
      ]);
      expect(mapViewModeOptions, isNot(contains(MapViewMode.satellite)));
    });

    test('labels are short 2D / 3D', () {
      expect(mapViewModeLabel(MapViewMode.standard2d), '2D');
      expect(mapViewModeLabel(MapViewMode.perspective3d), '3D');
    });

    test('3D is a 60-degree tilt keeping bearing; 2D is flat north-up',
        () {
      expect(tiltForMode(MapViewMode.perspective3d), 60);
      expect(bearingForMode(MapViewMode.perspective3d, 45), 45);
      expect(tiltForMode(MapViewMode.standard2d), 0);
      expect(bearingForMode(MapViewMode.standard2d, 45), 0);
    });
  });

  group('2D/3D toggle widget', () {
    Future<void> pumpMap(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapTab(
              customRouteRepository: _FakeCustomRouteRepository(),
              fareOverrideRepository: _FakeOverrideRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    IosSegmentedControl<MapViewMode> toggle(WidgetTester tester) =>
        tester.widget<IosSegmentedControl<MapViewMode>>(
          find.byKey(const ValueKey('map-view-mode-toggle')),
        );

    testWidgets('pill shows 2D and 3D only, starts on 2D', (tester) async {
      await pumpMap(tester);
      expect(
        find.byKey(const ValueKey('map-view-mode-toggle')),
        findsOneWidget,
      );
      expect(find.text('2D'), findsOneWidget);
      expect(find.text('3D'), findsOneWidget);
      expect(find.text('Satellite'), findsNothing);
      expect(toggle(tester).groupValue, MapViewMode.standard2d);
    });

    testWidgets('tapping 3D selects 3D, tapping 2D selects 2D again',
        (tester) async {
      await pumpMap(tester);
      await tester.tap(find.text('3D'));
      await tester.pumpAndSettle();
      expect(toggle(tester).groupValue, MapViewMode.perspective3d);
      await tester.tap(find.text('2D'));
      await tester.pumpAndSettle();
      expect(toggle(tester).groupValue, MapViewMode.standard2d);
    });

    testWidgets('switching modes keeps the active route on screen',
        (tester) async {
      await pumpMap(tester);
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsWidgets);
      await tester.tap(find.text('3D'));
      await tester.pumpAndSettle();
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsWidgets);
      expect(find.text('₱60'), findsOneWidget);
    });
  });
}
