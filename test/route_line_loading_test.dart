// Sinait stale-line regression (Steven, Nov 7, 20:40: the Map
// showed Sinait → Cabugao in the sheet — VERIFIED FARE, ₱20/₱16,
// 19 min, 13.1 km, stops 1 Sinait Start / 2 Cabugao End — but
// the green route line did NOT connect the two pins; instead a
// green segment ran SOUTH from Cabugao, i.e. the PREVIOUS
// route's line, Cabugao → Vigan).
//
// Root cause: a route change produced TWO layer-spec cycles in
// quick succession (old solid line → dashed direct line → new
// solid OSRM shape), and the maplibre plugin reconciles layers
// by index with un-awaited remove+add — so one update could be
// lost, and once the Dart list settled on the new spec the
// memoization suppressed every later update (the spec was
// unchanged, so the plugin saw no change and the wrong line
// stayed forever).
//
// The fix (mapLineLayers, pure + _roadLoading in the state):
// while the new route's road shape is loading, NO route line
// is drawn at all — the old line is gone the instant the route
// changes, so the transition is a single cycle (nothing →
// solid, or nothing → dashed on failure), and a post-fetch
// re-sync busts the memo once to recover a lost update. These
// tests cover the pure contract: roadLoading suppresses the
// route-line slot (including the stop-highlight branch) while
// leaving the admin's in-progress draft alone. The drawn line
// itself is only checkable on Steven's phone after a green
// build (MapLibre cannot render in flutter test).
import 'package:estudyantego/features/bus_stops.dart';
import 'package:estudyantego/features/map_tab.dart';
import 'package:estudyantego/features/osm_routing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const _green = Color(0xFF16A34A);
const _amber = Color(0xFFF59E0B);
const _origin = LatLng(17.87538, 120.48078); // Sinait
const _dest = LatLng(17.78916, 120.45838); // Cabugao
const _mid = LatLng(17.83, 120.47);

List<MapLineLayerSpec> _layers({
  bool roadLoading = false,
  bool routeSolid = false,
  int? selectedStopIndex,
  List<RouteStop> routeStops = const [],
  List<LatLng>? roadPoints,
  bool drawMode = false,
  List<RouteWaypoint> draftWaypoints = const [],
  List<LatLng>? draftRoadPoints,
}) =>
    mapLineLayers(
      routePoints: const [_origin, _dest],
      routeSolid: routeSolid,
      selectedStopIndex: selectedStopIndex,
      routeStops: routeStops,
      roadPoints: roadPoints,
      drawMode: drawMode,
      draftWaypoints: draftWaypoints,
      draftOrigin: _origin,
      draftDest: _dest,
      draftRoadPoints: draftRoadPoints,
      roadLoading: roadLoading,
    );

void main() {
  group('mapLineLayers roadLoading', () {
    test('loading suppresses the route line even with a road shape', () {
      final layers = _layers(
        roadLoading: true,
        routeSolid: true,
        roadPoints: const [_origin, _mid, _dest],
      );
      // No green line for the wrong (previous) route, not even
      // briefly — the map shows no line until the new shape
      // arrives.
      expect(layers, isEmpty);
    });

    test('loading suppresses the stop-highlight branch too', () {
      final layers = _layers(
        roadLoading: true,
        routeSolid: true,
        roadPoints: const [_origin, _mid, _dest],
        selectedStopIndex: 0,
        routeStops: const [
          RouteStop(
            name: 'Sinait',
            region: 'Ilocos Sur',
            lat: 17.87538,
            lng: 120.48078,
            isOrigin: true,
            isDestination: false,
            pathIndex: 0,
            kmFromOrigin: 0,
          ),
        ],
      );
      expect(layers, isEmpty);
    });

    test('loading keeps the in-progress draft (admin work stays)', () {
      final layers = _layers(
        roadLoading: true,
        drawMode: true,
        draftWaypoints: const [RouteWaypoint(lat: 17.83, lng: 120.47)],
      );
      // Exactly one layer: the amber draft only. No green route
      // line under it while loading.
      expect(layers.length, 1);
      expect(layers.first.color, _amber);
      expect(layers.first.points, [_origin, _mid, _dest]);
    });

    test('not loading draws the solid route line once loaded', () {
      final layers = _layers(
        roadLoading: false,
        routeSolid: true,
        roadPoints: const [_origin, _mid, _dest],
      );
      expect(layers.length, 1);
      expect(layers.first.color, _green);
      expect(layers.first.solid, isTrue);
      // The pure helper draws the routePoints it is handed (the
      // state passes the loaded road shape there); roadPoints
      // only feeds the highlight branch's split.
      expect(layers.first.points, [_origin, _dest]);
    });

    test('not loading + tapped stop still highlights the remainder', () {
      final layers = _layers(
        roadLoading: false,
        routeSolid: true,
        roadPoints: const [_origin, _mid, _dest],
        selectedStopIndex: 0,
        routeStops: const [
          RouteStop(
            name: 'Sinait',
            region: 'Ilocos Sur',
            lat: 17.87538,
            lng: 120.48078,
            isOrigin: true,
            isDestination: false,
            pathIndex: 0,
            kmFromOrigin: 0,
          ),
        ],
      );
      // The four highlight layers (dimmed before + glow +
      // casing + core after) — the pre-fix behaviour, unchanged
      // when nothing is loading.
      expect(layers.length, 4);
      expect(layers.every((l) => l.color != _amber), isTrue);
    });

    test('roadLoading defaults to false', () {
      // A caller that does not pass the flag gets the old
      // behaviour — the route line renders.
      final layers = mapLineLayers(
        routePoints: const [_origin, _dest],
        routeSolid: false,
        selectedStopIndex: null,
        routeStops: const [],
        roadPoints: null,
        drawMode: false,
        draftWaypoints: const [],
        draftOrigin: _origin,
        draftDest: _dest,
        draftRoadPoints: null,
      );
      expect(layers.length, 1);
      expect(layers.first.color, _green);
      expect(layers.first.solid, isFalse);
    });
  });
}
