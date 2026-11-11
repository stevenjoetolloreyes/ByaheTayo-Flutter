// Live Follow tap-to-zoom / drag-break / rotating car marker /
// cyan route line (Nov 11, 2026). Pure-logic tests only — the
// native MapLibre map cannot render in flutter test, so the
// camera moves, the drag pause, and the marker tap are only
// checkable on Steven's phone after a green build. What IS
// pinned here: the cyan line spec (liveMode), the marker
// screen rotation, and the tap-zoom target zoom.
import 'package:estudyantego/features/bus_stops.dart';
import 'package:estudyantego/features/live_follow.dart';
import 'package:estudyantego/features/map_tab.dart';
import 'package:estudyantego/features/osm_routing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const _green = Color(0xFF16A34A);
const _cyan = Color(0xFF22D3EE);
const _lightGreen = Color(0xFF4ADE80);
const _amber = Color(0xFFF59E0B);
const _origin = LatLng(17.7943, 120.4534); // Cabugao
const _dest = LatLng(17.56641, 120.3859); // Vigan Bus Terminal
const _road = [
  LatLng(17.7943, 120.4534),
  LatLng(17.75, 120.44),
  LatLng(17.70, 120.41),
  LatLng(17.56641, 120.3859),
];
const _stops = [
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
    lat: 17.70,
    lng: 120.41,
    isOrigin: false,
    isDestination: false,
    pathIndex: 2,
    kmFromOrigin: 16,
  ),
  RouteStop(
    name: 'Vigan Bus Terminal',
    region: 'Ilocos Sur',
    lat: 17.56641,
    lng: 120.3859,
    isOrigin: false,
    isDestination: true,
    pathIndex: 3,
    kmFromOrigin: 32,
  ),
];

List<MapLineLayerSpec> _layers({
  bool liveMode = false,
  int? selectedStopIndex,
  bool drawMode = false,
  List<RouteWaypoint> draftWaypoints = const [],
}) =>
    mapLineLayers(
      routePoints: _road,
      routeSolid: true,
      selectedStopIndex: selectedStopIndex,
      routeStops: _stops,
      roadPoints: _road,
      drawMode: drawMode,
      draftWaypoints: draftWaypoints,
      draftOrigin: _origin,
      draftDest: _dest,
      draftRoadPoints: null,
      liveMode: liveMode,
    );

void main() {
  group('mapLineLayers liveMode — cyan route line', () {
    test('liveMode draws the plain route line cyan, not green', () {
      final layers = _layers(liveMode: true);
      expect(layers.length, 1);
      expect(layers[0].color, _cyan);
      expect(layers[0].points, _road);
      expect(layers[0].solid, isTrue);
    });

    test('liveMode defaults off: the plain line stays green', () {
      final layers = _layers();
      expect(layers.length, 1);
      expect(layers[0].color, _green);
      // Explicit false matches the default.
      expect(_layers(liveMode: false)[0].color, _green);
    });

    test('liveMode split: before dims cyan, after core is cyan', () {
      final layers = _layers(liveMode: true, selectedStopIndex: 1);
      expect(layers.length, 4);
      expect(layers.map((l) => l.width), [6, 16, 11, 7]);
      expect(
        layers.map((l) => l.color),
        [
          _cyan.withValues(alpha: 0.15),
          _cyan.withValues(alpha: 0.25),
          Colors.white,
          _cyan,
        ],
      );
      expect(layers.every((l) => l.solid), isTrue);
    });

    test('liveMode off split: green dim / light-green core, unchanged',
        () {
      final layers = _layers(selectedStopIndex: 1);
      expect(layers.length, 4);
      expect(
        layers.map((l) => l.color),
        [
          _green.withValues(alpha: 0.15),
          _green.withValues(alpha: 0.25),
          Colors.white,
          _lightGreen,
        ],
      );
    });

    test('liveMode draw mode: reference line cyan, draft stays amber',
        () {
      final layers = _layers(
        liveMode: true,
        drawMode: true,
        draftWaypoints: const [
          RouteWaypoint(lat: 17.72, lng: 120.42),
        ],
      );
      expect(layers.length, 2);
      expect(layers[0].color, _cyan);
      expect(layers[1].color, _amber);
    });
  });

  group('liveMarkerScreenRotationDeg', () {
    test('heading-up: live bearing equals map bearing -> 0', () {
      expect(
        liveMarkerScreenRotationDeg(liveBearing: 90, mapBearing: 90),
        0,
      );
    });

    test('north-up: live east on a north-up map -> 90', () {
      expect(
        liveMarkerScreenRotationDeg(liveBearing: 90, mapBearing: 0),
        90,
      );
    });

    test('wraps across 0/360: live 10, map 350 -> 20', () {
      expect(
        liveMarkerScreenRotationDeg(liveBearing: 10, mapBearing: 350),
        20,
      );
    });

    test('wraps the other way: live 350, map 10 -> -20', () {
      expect(
        liveMarkerScreenRotationDeg(liveBearing: 350, mapBearing: 10),
        -20,
      );
    });

    test('opposite headings stay inside -180..180', () {
      expect(
        liveMarkerScreenRotationDeg(liveBearing: 180, mapBearing: 0),
        180,
      );
      // 0 - 180 wraps to 180 (Dart % is non-negative) — the
      // same angle as -180, and inside the range either way.
      expect(
        liveMarkerScreenRotationDeg(liveBearing: 0, mapBearing: 180),
        180,
      );
    });
  });

  group('liveTapZoomTarget', () {
    test('zoom 13 taps to 15', () {
      expect(liveTapZoomTarget(13), 15);
    });

    test('exactly at the Live follow zoom (18.3) the tap recentres',
        () {
      expect(liveTapZoomTarget(liveCloseFollowZoom), liveCloseFollowZoom);
      // 16 is no longer the follow zoom (Nov 11 close-follow):
      // a tap there steps by 2 as usual.
      expect(liveTapZoomTarget(16), 18);
    });

    test('zoom 18 taps to 19 (clamped at the max)', () {
      expect(liveTapZoomTarget(18), 19);
    });

    test('zoom 19 stays at 19', () {
      expect(liveTapZoomTarget(19), 19);
    });

    test('low zooms still step by 2', () {
      expect(liveTapZoomTarget(3), 5);
      expect(liveTapZoomTarget(8), 10);
    });
  });
}
