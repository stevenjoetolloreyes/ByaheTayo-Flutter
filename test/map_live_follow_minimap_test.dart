// Live Follow minimap + Speed / Distance readouts (Nov 11,
// 2026). Pure-logic tests for liveMinimapPoints and the speed /
// distance formatters, plus a widget test for LiveMinimap.
// The Map tab itself cannot render in flutter test (native
// MapLibre map), so the minimap's placement (top-right below
// the control cluster, hidden when a stop card is open) and the
// My Location → Follow ON flow are only checkable on Steven's
// phone after a green build.
import 'package:estudyantego/features/live_follow.dart';
import 'package:estudyantego/features/live_minimap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  group('liveMinimapPoints', () {
    test('3-point diagonal route maps inside the box, padding respected',
        () {
      const size = Size(120, 120);
      final points = liveMinimapPoints(
        routePoints: const [
          LatLng(0, 0),
          LatLng(5, 5),
          LatLng(10, 10),
        ],
        livePos: null,
        size: size,
      );
      expect(points.route, hasLength(3));
      for (final p in points.route) {
        expect(p.dx, greaterThanOrEqualTo(8));
        expect(p.dx, lessThanOrEqualTo(112));
        expect(p.dy, greaterThanOrEqualTo(8));
        expect(p.dy, lessThanOrEqualTo(112));
      }
      // Origin is bottom-left (south-west), destination top-right.
      expect(points.origin!.dx, lessThan(points.destination!.dx));
      expect(points.origin!.dy, greaterThan(points.destination!.dy));
      // Endpoints touch the padded bounds (uniform fit).
      expect(points.origin!.dx, closeTo(8, 0.001));
      expect(points.destination!.dx, closeTo(112, 0.001));
      expect(points.destination!.dy, closeTo(8, 0.001));
      expect(points.origin!.dy, closeTo(112, 0.001));
    });

    test('live dot at the route midpoint lands at the centre of the box',
        () {
      const size = Size(120, 120);
      final points = liveMinimapPoints(
        routePoints: const [
          LatLng(0, 0),
          LatLng(5, 5),
          LatLng(10, 10),
        ],
        livePos: const LatLng(5, 5),
        size: size,
      );
      expect(points.live, isNotNull);
      expect(points.live!.dx, closeTo(60, 0.001));
      expect(points.live!.dy, closeTo(60, 0.001));
    });

    test('empty route -> empty polyline and null dots', () {
      final points = liveMinimapPoints(
        routePoints: const [],
        livePos: const LatLng(5, 5),
        size: const Size(120, 120),
      );
      expect(points.route, isEmpty);
      expect(points.isEmpty, isTrue);
      expect(points.origin, isNull);
      expect(points.destination, isNull);
      expect(points.live, isNull);
    });

    test('single-point route -> empty (nothing to draw)', () {
      final points = liveMinimapPoints(
        routePoints: const [LatLng(5, 5)],
        livePos: const LatLng(5, 5),
        size: const Size(120, 120),
      );
      expect(points.route, isEmpty);
      expect(points.origin, isNull);
      expect(points.destination, isNull);
      expect(points.live, isNull);
    });

    test('tall route fits without distortion (uniform scale)', () {
      const size = Size(120, 120);
      // Latitude range 10x the longitude range: the fit must be
      // limited by height, so the width stays narrow and centred.
      final points = liveMinimapPoints(
        routePoints: const [
          LatLng(0, 0),
          LatLng(10, 1),
        ],
        livePos: null,
        size: size,
      );
      expect(points.route, hasLength(2));
      // Height spans the full padded box; width is 1/10 of it.
      final height = (points.origin!.dy - points.destination!.dy).abs();
      final width = (points.destination!.dx - points.origin!.dx).abs();
      expect(height, closeTo(104, 0.001));
      expect(width, closeTo(10.4, 0.001));
      // Centred horizontally: equal margins left and right.
      expect(points.origin!.dx, closeTo(120 - points.destination!.dx, 0.001));
      for (final p in points.route) {
        expect(p.dx, greaterThanOrEqualTo(8));
        expect(p.dx, lessThanOrEqualTo(112));
        expect(p.dy, greaterThanOrEqualTo(8));
        expect(p.dy, lessThanOrEqualTo(112));
      }
    });

    test('live dot outside the route bounds is still inside the box', () {
      final points = liveMinimapPoints(
        routePoints: const [LatLng(0, 0), LatLng(10, 10)],
        livePos: const LatLng(20, 20),
        size: const Size(120, 120),
      );
      expect(points.live, isNotNull);
      expect(points.live!.dx, lessThanOrEqualTo(112));
      expect(points.live!.dy, greaterThanOrEqualTo(8));
    });
  });

  group('LiveMinimap widget', () {
    testWidgets('renders the route + dots and tapping calls onTap',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveMinimap(
              routePoints: const [
                LatLng(0, 0),
                LatLng(5, 5),
                LatLng(10, 10),
              ],
              livePos: const LatLng(5, 5),
              live: true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      expect(find.text('ROUTE'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      await tester.tap(find.byType(LiveMinimap));
      expect(tapped, isTrue);
    });

    testWidgets('without onTap, tapping does not throw', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiveMinimap(
              routePoints: [LatLng(0, 0), LatLng(10, 10)],
              livePos: null,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(LiveMinimap));
      expect(find.text('ROUTE'), findsOneWidget);
    });
  });

  group('Live panel speed / distance formatting', () {
    test('speed null -> em dash', () {
      expect(formatLiveSpeedKmh(null), '—');
    });

    test('speed 42.4 -> whole km/h', () {
      expect(formatLiveSpeedKmh(42.4), '42 km/h');
    });

    test('speed 0 -> 0 km/h', () {
      expect(formatLiveSpeedKmh(0), '0 km/h');
    });

    test('traveled 12.34 / total 27.09 -> one decimal each', () {
      expect(formatLiveDistanceKm(12.34, 27.09), '12.3 / 27.1 km');
    });

    test('zero distance -> 0.0 / 0.0 km', () {
      expect(formatLiveDistanceKm(0, 0), '0.0 / 0.0 km');
    });
  });
}
