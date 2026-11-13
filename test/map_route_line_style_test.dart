// Approved route-line style (Steven, Nov 13, 2026 — Preview v3,
// artifact map-line-thickness-preview, "Okay na, ganyan na"):
// Google Maps blue #1A73E8 core, 28 px wide, white casing
// (36 px total), covering the whole road, with a draw-in
// animation and a travelling pulse. Pure-logic tests only —
// MapLibre cannot render in flutter test, so the drawn line
// itself is only checkable on Steven's phone after a green
// build.
import 'package:estudyantego/features/map_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const _blue = Color(0xFF1A73E8);
const _origin = LatLng(17.7943, 120.4534); // Cabugao
const _dest = LatLng(17.56641, 120.3859); // Vigan Bus Terminal
const _road = [
  LatLng(17.7943, 120.4534),
  LatLng(17.75, 120.44),
  LatLng(17.70, 120.41),
  LatLng(17.56641, 120.3859),
];

List<MapLineLayerSpec> _layers({
  double drawProgress = 1.0,
  double? pulseHead,
  bool routeSolid = true,
}) =>
    mapLineLayers(
      routePoints: _road,
      routeSolid: routeSolid,
      selectedStopIndex: null,
      routeStops: const [],
      roadPoints: _road,
      drawMode: false,
      draftWaypoints: const [],
      draftOrigin: _origin,
      draftDest: _dest,
      draftRoadPoints: null,
      drawProgress: drawProgress,
      pulseHead: pulseHead,
    );

void main() {
  group('approved route-line style', () {
    test('constants are the approved Preview v3 numbers', () {
      expect(kRouteLineBlue, _blue);
      expect(kRouteLineCoreWidth, 28);
      expect(kRouteLineCasingWidth, 36);
      // Casing = core + 8, like the preview (28 core, 36 total).
      expect(kRouteLineCasingWidth, kRouteLineCoreWidth + 8);
      expect(kRouteLineGlowWidth, kRouteLineCoreWidth + 16);
    });

    test('plain line is white casing under a blue core', () {
      final layers = _layers();
      expect(layers.length, 2);
      expect(layers.map((l) => l.width), [36, 28]);
      expect(layers.map((l) => l.color), [Colors.white, _blue]);
      expect(layers.map((l) => l.points), [_road, _road]);
      expect(layers.every((l) => l.solid), isTrue);
    });

    test('dashed fallback keeps both layers dashed', () {
      final layers = _layers(routeSolid: false);
      expect(layers.length, 2);
      expect(layers.every((l) => l.solid), isFalse);
      expect(layers[0].color, Colors.white);
      expect(layers[1].color, _blue);
    });
  });

  group('routeSubPath / draw-in geometry', () {
    test('full progress returns the whole road', () {
      expect(routeDrawPoints(_road, 1.0), _road);
      expect(routeDrawPoints(_road, 1.5), _road);
    });

    test('zero progress is just the origin point', () {
      final drawn = routeDrawPoints(_road, 0.0);
      expect(drawn.length, 2);
      expect(drawn.every((p) => p == _road.first), isTrue);
    });

    test('half progress ends mid-road, interpolated on the road', () {
      final drawn = routeDrawPoints(_road, 0.5);
      // Half of 3 segments = 1.5 segments in: origin, 2nd
      // point, then the midpoint of the 2nd–3rd segment.
      expect(drawn.length, 3);
      expect(drawn.first, _road.first);
      expect(drawn[1], _road[1]);
      expect(drawn[2].latitude, closeTo(17.725, 0.000001));
      expect(drawn[2].longitude, closeTo(120.425, 0.000001));
    });

    test('a path with fewer than 2 points comes back unchanged', () {
      expect(routeSubPath(const [], 0, 1), isEmpty);
      expect(
        routeSubPath(const [LatLng(17.8, 120.45)], 0, 1),
        [const LatLng(17.8, 120.45)],
      );
    });

    test('drawProgress trims casing and core together', () {
      final layers = _layers(drawProgress: 0.5);
      expect(layers.length, 2);
      expect(layers[0].points, layers[1].points);
      expect(layers[0].points.first, _road.first);
      expect(layers[0].points.length, 3);
      // The casing never outruns the core mid-draw.
      expect(layers[0].points.last, layers[1].points.last);
    });
  });

  group('travelling pulse', () {
    test('pulseHead adds a bright band on top of the core', () {
      final layers = _layers(pulseHead: 0.5);
      expect(layers.length, 3);
      expect(layers[2].width, kRouteLineCoreWidth);
      expect(layers[2].color, Colors.white.withValues(alpha: 0.9));
      expect(layers[2].solid, isTrue);
    });

    test('pulse window trails the head and stays on the road', () {
      final pulse = routePulsePoints(_road, 0.5);
      expect(pulse.length, 2);
      // Both ends lie between the 2nd and 3rd road points.
      for (final p in pulse) {
        expect(p.latitude, lessThanOrEqualTo(_road[1].latitude));
        expect(p.latitude, greaterThanOrEqualTo(_road[2].latitude));
      }
      // The head is the last point: the band ends where the
      // head is, never ahead of it.
      expect(pulse.last.latitude, closeTo(17.725, 0.000001));
    });

    test('no pulseHead means no pulse layer', () {
      expect(_layers().length, 2);
    });
  });
}
