// Line-maker stale-line regression (Steven, Nov 7, 19:17: "nag
// iinvento sariling line" — an amber draft line and a green
// dashed direct line stayed visible on the map after Draw-line
// mode was closed, even though the sheet was back in PEEK).
//
// Root cause: the old _routePolylineLayers REPLACED slot 0's
// content on every draw-mode enter/exit (amber draft in, green
// route back out) and rebuilt a fresh layer list on every
// rebuild — the maplibre plugin reconciles layers by index and
// its remove+add is un-awaited, so the pair raced and orphaned
// stale native layers. It also drew a straight origin→dest
// amber line the moment draw mode opened with an empty draft —
// a line the admin never tapped.
//
// The fix (mapLineLayers, pure): slot 0 is ALWAYS the saved
// route line (green, including in draw mode as the reference
// under the draft); the amber draft is a trailing slot that
// exists ONLY while drawing AND at least one point was tapped
// (or pre-filled from a saved direction). These tests cover the
// spec the state memoizes — MapLibre cannot render in
// flutter test, so the drawn line itself is only checkable on
// Steven's phone after a green build.
import 'package:estudyantego/features/bus_stops.dart';
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/map_tab.dart';
import 'package:estudyantego/features/osm_routing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const _green = Color(0xFF16A34A);
const _amber = Color(0xFFF59E0B);
const _origin = LatLng(17.7943, 120.4534); // Cabugao
const _dest = LatLng(17.56641, 120.3859); // Vigan Bus Terminal
const _mid1 = LatLng(17.72, 120.42);
const _mid2 = LatLng(17.65, 120.40);

List<MapLineLayerSpec> _layers({
  List<LatLng> routePoints = const [_origin, _dest],
  bool routeSolid = false,
  int? selectedStopIndex,
  List<RouteStop> routeStops = const [],
  List<LatLng>? roadPoints,
  bool drawMode = false,
  List<RouteWaypoint> draftWaypoints = const [],
  List<LatLng>? draftRoadPoints,
}) =>
    mapLineLayers(
      routePoints: routePoints,
      routeSolid: routeSolid,
      selectedStopIndex: selectedStopIndex,
      routeStops: routeStops,
      roadPoints: roadPoints,
      drawMode: drawMode,
      draftWaypoints: draftWaypoints,
      draftOrigin: _origin,
      draftDest: _dest,
      draftRoadPoints: draftRoadPoints,
    );

void main() {
  group('mapLineLayers — stale-line regression', () {
    test('inactive mode draws only the green route line, no amber', () {
      // Even with a leftover draft (the stale state after an
      // exit), the mode being inactive means no draft layer.
      final layers = _layers(
        draftWaypoints: const [
          RouteWaypoint(lat: 17.72, lng: 120.42),
          RouteWaypoint(lat: 17.65, lng: 120.40),
        ],
      );
      expect(layers.length, 1);
      expect(layers[0].color, _green);
      expect(layers[0].points, [_origin, _dest]);
      expect(layers[0].solid, isFalse);
    });

    test('draw mode with an empty draft draws only the green line', () {
      // The bug's second half: entering Draw line on a route
      // with no saved direction used to draw a straight
      // origin→destination amber line nobody tapped.
      final layers = _layers(drawMode: true);
      expect(layers.length, 1);
      expect(layers[0].color, _green);
      expect(layers[0].points, [_origin, _dest]);
    });

    test('draw mode with tapped points draws green + amber', () {
      final layers = _layers(
        drawMode: true,
        draftWaypoints: const [
          RouteWaypoint(lat: 17.72, lng: 120.42),
          RouteWaypoint(lat: 17.65, lng: 120.40),
        ],
      );
      expect(layers.length, 2);
      // Slot 0 stays the saved route line (green reference).
      expect(layers[0].color, _green);
      expect(layers[0].points, [_origin, _dest]);
      // Trailing slot: the amber draft through the tapped points.
      expect(layers[1].color, _amber);
      expect(layers[1].points, [_origin, _mid1, _mid2, _dest]);
      expect(layers[1].solid, isFalse); // dashed until OSRM arrives
    });

    test('draw mode with a draft road shape draws a solid amber line',
        () {
      const road = [
        LatLng(17.7943, 120.4534),
        LatLng(17.75, 120.44),
        LatLng(17.70, 120.41),
        LatLng(17.56641, 120.3859),
      ];
      final layers = _layers(
        drawMode: true,
        draftWaypoints: const [
          RouteWaypoint(lat: 17.72, lng: 120.42),
        ],
        draftRoadPoints: road,
      );
      expect(layers.length, 2);
      expect(layers[1].color, _amber);
      expect(layers[1].points, road);
      expect(layers[1].solid, isTrue);
    });

    test('pre-filled draft from a saved direction shows the saved line',
        () {
      // A custom route with saved drawn waypoints: the draft
      // pre-fill IS those points, so the amber line follows them.
      final custom = CustomRoute(
        from: 'Cabugao',
        to: 'Vigan Bus Terminal',
        operator: 'Partas',
        vehicle: 'Bus',
        fare: 60,
        viaWaypoints: const [
          RouteWaypoint(lat: 17.72, lng: 120.42),
          RouteWaypoint(lat: 17.65, lng: 120.40),
        ],
      );
      final prefill = effectiveRouteWaypoints(customRoute: custom);
      expect(prefill.length, 2);
      final layers = _layers(drawMode: true, draftWaypoints: prefill);
      expect(layers.length, 2);
      expect(layers[1].color, _amber);
      expect(layers[1].points, [_origin, _mid1, _mid2, _dest]);
    });

    test('pre-filled draft from named via stops matches the route line',
        () {
      // Named via stops resolve to the same points the route
      // line uses, so the pre-filled draft never invents a line.
      final custom = CustomRoute(
        from: 'Cabugao',
        to: 'Vigan Bus Terminal',
        operator: 'Partas',
        vehicle: 'Bus',
        fare: 60,
        viaHubs: const ['San Juan, Ilocos Sur'],
      );
      final prefill = effectiveRouteWaypoints(customRoute: custom);
      expect(prefill.length, 1);
      expect(prefill[0].name, 'San Juan, Ilocos Sur');
      final layers = _layers(drawMode: true, draftWaypoints: prefill);
      expect(layers.length, 2);
      expect(layers[1].points.first, _origin);
      expect(layers[1].points.last, _dest);
      expect(layers[1].points[1], prefill[0].point);
    });

    test('spec equality holds across fresh instances', () {
      // The memoization prerequisite: two specs built from
      // equal-but-distinct point lists compare equal, so the
      // state can return the identical layer list instance
      // while nothing moved.
      final a = _layers(drawMode: true, draftWaypoints: const [
        RouteWaypoint(lat: 17.72, lng: 120.42),
      ]);
      final b = _layers(drawMode: true, draftWaypoints: const [
        RouteWaypoint(lat: 17.72, lng: 120.42),
      ]);
      expect(listEquals(a, b), isTrue);
      expect(a[0], isNot(same(b[0]))); // distinct objects…
      expect(a[0], b[0]); // …but equal by value
    });

    test('stop highlight still renders four layers, unchanged', () {
      const road = [
        LatLng(17.7943, 120.4534),
        LatLng(17.75, 120.44),
        LatLng(17.70, 120.41),
        LatLng(17.56641, 120.3859),
      ];
      const stops = [
        RouteStop(
          name: 'Cabugao',
          region: 'Ilocos Sur',
          lat: 17.7943,
          lng: 120.4534,
          isOrigin: true,
          isDestination: false,
          pathIndex: 0,
          kmFromOrigin: 0,
        ),
        RouteStop(
          name: 'San Juan',
          region: 'Ilocos Sur',
          lat: 17.75,
          lng: 120.44,
          isOrigin: false,
          isDestination: false,
          pathIndex: 1,
          kmFromOrigin: 8,
        ),
        RouteStop(
          name: 'Vigan Bus Terminal',
          region: 'Ilocos Sur',
          lat: 17.56641,
          lng: 120.3859,
          isOrigin: false,
          isDestination: true,
          pathIndex: 3,
          kmFromOrigin: 31.6,
        ),
      ];
      final layers = _layers(
        routePoints: road,
        routeSolid: true,
        selectedStopIndex: 1,
        routeStops: stops,
        roadPoints: road,
      );
      expect(layers.length, 4);
      expect(layers.map((l) => l.width), [6, 16, 11, 7]);
      expect(
        layers.map((l) => l.color),
        [
          _green.withValues(alpha: 0.15),
          _green.withValues(alpha: 0.25),
          Colors.white,
          const Color(0xFF4ADE80),
        ],
      );
      expect(layers.every((l) => l.solid), isTrue);
      // The split point belongs to both parts: no gap.
      expect(layers[0].points.last, layers[1].points.first);
    });

    test('draw mode never shows the highlight branch', () {
      // Entering draw mode clears the selection; even if one
      // were set, the draft slots win over the highlight.
      const road = [
        LatLng(17.7943, 120.4534),
        LatLng(17.75, 120.44),
        LatLng(17.56641, 120.3859),
      ];
      const stops = [
        RouteStop(
          name: 'Cabugao',
          region: 'Ilocos Sur',
          lat: 17.7943,
          lng: 120.4534,
          isOrigin: true,
          isDestination: false,
          pathIndex: 0,
          kmFromOrigin: 0,
        ),
      ];
      final layers = _layers(
        routePoints: road,
        routeSolid: true,
        selectedStopIndex: 0,
        routeStops: stops,
        roadPoints: road,
        drawMode: true,
        draftWaypoints: const [
          RouteWaypoint(lat: 17.72, lng: 120.42),
        ],
      );
      expect(layers.length, 2);
      expect(layers[0].color, _green);
      expect(layers[1].color, _amber);
    });
  });
}
