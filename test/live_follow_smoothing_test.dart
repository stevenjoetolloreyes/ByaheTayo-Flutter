// Google-level smoothing (Nov 13, 2026 — approved Preview v2):
// snap-to-road projection + prediction / honest coasting.
// Pure-logic tests only — the per-frame Ticker that drives the
// arrow on the phone cannot run in flutter test, so what is
// pinned here is the math it runs on: the snap, the along-road
// advance, and the coast rule.
import 'package:estudyantego/features/live_follow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Straight north–south road at lng 120.45, Cabugao area.
const _road = [
  LatLng(17.80, 120.45),
  LatLng(17.75, 120.45),
  LatLng(17.70, 120.45),
];

void main() {
  group('snapToRoad', () {
    test('a fix ~30 m off the road snaps onto it', () {
      final snapped = snapToRoad(
        position: const LatLng(17.75, 120.4503),
        roadPoints: _road,
      );
      expect(snapped, isNotNull);
      // On the road (lng back to 120.45) and ~30 m was the error.
      expect(snapped!.point.longitude, closeTo(120.45, 0.00001));
      expect(snapped.point.latitude, closeTo(17.75, 0.0005));
      expect(snapped.offRoadKm, closeTo(0.03, 0.01));
      // Halfway along the 2-segment road (~11.1 km total).
      expect(snapped.distanceAlongKm, closeTo(5.56, 0.1));
    });

    test('a fix already on the road barely moves', () {
      final snapped = snapToRoad(
        position: const LatLng(17.77, 120.45),
        roadPoints: _road,
      );
      expect(snapped, isNotNull);
      expect(snapped!.offRoadKm, closeTo(0, 0.001));
      expect(snapped.point.latitude, closeTo(17.77, 0.0005));
    });

    test('no geometry: null, caller falls back to the fix', () {
      expect(
        snapToRoad(position: const LatLng(17.75, 120.45), roadPoints: null),
        isNull,
      );
      expect(
        snapToRoad(
          position: const LatLng(17.75, 120.45),
          roadPoints: const [LatLng(17.75, 120.45)],
        ),
        isNull,
      );
    });

    test('snaps to the nearest segment, not the nearest vertex', () {
      // L-shaped road: the fix sits beside the middle of the
      // second leg, far from both its vertices.
      const lRoad = [
        LatLng(17.80, 120.45),
        LatLng(17.75, 120.45),
        LatLng(17.75, 120.50),
      ];
      final snapped = snapToRoad(
        position: const LatLng(17.7503, 120.48),
        roadPoints: lRoad,
      );
      expect(snapped, isNotNull);
      expect(snapped!.segmentIndex, 1);
      expect(snapped.point.latitude, closeTo(17.75, 0.0005));
      expect(snapped.point.longitude, closeTo(120.48, 0.0005));
    });
  });

  group('pointAtDistanceAlongRoad', () {
    test('halfway along the road', () {
      final p = pointAtDistanceAlongRoad(_road, 5.56);
      expect(p.latitude, closeTo(17.75, 0.002));
      expect(p.longitude, closeTo(120.45, 0.00001));
    });

    test('past the end clamps to the last road point', () {
      final p = pointAtDistanceAlongRoad(_road, 999);
      expect(p.latitude, closeTo(17.70, 0.00001));
      expect(p.longitude, closeTo(120.45, 0.00001));
    });

    test('zero distance is the road start', () {
      final p = pointAtDistanceAlongRoad(_road, 0);
      expect(p.latitude, closeTo(17.80, 0.00001));
    });
  });

  group('predictLivePosition', () {
    test('advances along the road at the measured speed', () {
      // 60 km/h for 60 s = 1 km south along the road.
      final p = predictLivePosition(
        from: const LatLng(17.75, 120.45),
        bearingDeg: 180,
        speedKmh: 60,
        elapsed: const Duration(seconds: 60),
        roadPoints: _road,
        distanceAlongKm: 5.56,
      );
      expect(p.longitude, closeTo(120.45, 0.00001));
      // ~1 km south of 17.75 (1 deg lat ~= 111 km).
      expect(p.latitude, closeTo(17.741, 0.001));
    });

    test('no geometry: dead-reckons along the bearing', () {
      final p = predictLivePosition(
        from: const LatLng(17.75, 120.45),
        bearingDeg: 180,
        speedKmh: 60,
        elapsed: const Duration(seconds: 60),
      );
      expect(p.latitude, closeTo(17.741, 0.001));
      expect(p.longitude, closeTo(120.45, 0.001));
    });

    test('stopped bus does not drift', () {
      const from = LatLng(17.75, 120.45);
      expect(
        predictLivePosition(
          from: from,
          bearingDeg: 180,
          speedKmh: 0,
          elapsed: const Duration(seconds: 10),
          roadPoints: _road,
          distanceAlongKm: 5.56,
        ),
        from,
      );
      expect(
        predictLivePosition(
          from: from,
          bearingDeg: 180,
          speedKmh: null,
          elapsed: const Duration(seconds: 10),
        ),
        from,
      );
    });

    test('prediction past the road end holds at the destination', () {
      final p = predictLivePosition(
        from: const LatLng(17.75, 120.45),
        bearingDeg: 180,
        speedKmh: 60,
        elapsed: const Duration(minutes: 30),
        roadPoints: _road,
        distanceAlongKm: 5.56,
      );
      expect(p.latitude, closeTo(17.70, 0.00001));
    });
  });

  group('livePredictionShouldCoast', () {
    test('coasts within 3 s of the last fix', () {
      final fix = DateTime(2026, 11, 13, 18, 0, 0);
      expect(
        livePredictionShouldCoast(
          lastFixAt: fix,
          now: fix.add(const Duration(seconds: 2)),
        ),
        isTrue,
      );
      expect(
        livePredictionShouldCoast(
          lastFixAt: fix,
          now: fix.add(const Duration(seconds: 3)),
        ),
        isTrue,
      );
    });

    test('holds after 3 s — no fake movement on a dead GPS', () {
      final fix = DateTime(2026, 11, 13, 18, 0, 0);
      expect(
        livePredictionShouldCoast(
          lastFixAt: fix,
          now: fix.add(const Duration(seconds: 4)),
        ),
        isFalse,
      );
      expect(
        livePredictionShouldCoast(
          lastFixAt: fix,
          now: fix.add(const Duration(seconds: 10)),
        ),
        isFalse,
      );
    });
  });
}
