// Google-level smoothing (Nov 13, 2026 — approved Preview v2):
// snap-to-road projection + prediction / honest coasting.
// Pure-logic tests only — the per-frame Ticker that drives the
// arrow on the phone cannot run in flutter test, so what is
// pinned here is the math it runs on: the snap, the along-road
// advance, and the coast rule.
import 'package:estudyantego/features/live_follow.dart';
import 'package:estudyantego/features/osm_routing.dart';
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

  group('liveSnapIsOnRoute', () {
    test('a fix ~20 m off the road snaps (within the 50 m limit)', () {
      final snapped = snapToRoad(
        position: const LatLng(17.75, 120.45019),
        roadPoints: _road,
      );
      expect(snapped, isNotNull);
      expect(snapped!.offRoadKm, closeTo(0.02, 0.01));
      expect(liveSnapIsOnRoute(snapped), isTrue);
      // And the snapped point is on the road, not at the fix.
      expect(snapped.point.longitude, closeTo(120.45, 0.00001));
    });

    test('a fix 500 m off the road does NOT snap (caller keeps the true fix)', () {
      // Aragan at home: far off the Cabugao → Vigan route.
      final snapped = snapToRoad(
        position: const LatLng(17.75, 120.45472),
        roadPoints: _road,
      );
      expect(snapped, isNotNull);
      expect(snapped!.offRoadKm, closeTo(0.5, 0.05));
      expect(liveSnapIsOnRoute(snapped), isFalse);
      // The projection still exists, but the caller must not use it.
      expect(snapped.point.longitude, closeTo(120.45, 0.00001));
    });

    test('boundary: exactly 50 m snaps, just over 50 m does not', () {
      const atLimit = SnappedRoadPosition(
        point: LatLng(17.75, 120.45),
        segmentIndex: 1,
        distanceAlongKm: 5.56,
        offRoadKm: 0.05,
      );
      expect(liveSnapIsOnRoute(atLimit), isTrue);
      const overLimit = SnappedRoadPosition(
        point: LatLng(17.75, 120.45),
        segmentIndex: 1,
        distanceAlongKm: 5.56,
        offRoadKm: 0.050001,
      );
      expect(liveSnapIsOnRoute(overLimit), isFalse);
    });

    test('no geometry: null snap is never on-route', () {
      expect(liveSnapIsOnRoute(null), isFalse);
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

  group('PositionSmoother jump cap (Baguio teleport, Nov 14, 2026)', () {
    // ~111 km per degree of latitude at these latitudes.
    LatLng northOf(LatLng base, double meters) =>
        LatLng(base.latitude + meters / 111000, base.longitude);

    const base = LatLng(16.42, 120.59); // Baguio downtown.
    final t0 = DateTime(2026, 11, 14, 0, 0, 0);

    test('a 10 km jump in 1 s is rejected even with a huge '
        'reported speed and accuracy', () {
      final smoother = PositionSmoother();
      smoother.add(base, accuracy: 10, at: t0);
      // speed 9000 m/s + accuracy 2000 m would pass the old
      // speed×dt gate (11010 m > 10000 m) — the 250 m cap
      // must still reject it.
      final out = smoother.add(
        northOf(base, 10000),
        accuracy: 2000,
        at: t0.add(const Duration(seconds: 1)),
        speedMps: 9000,
      );
      expect(out, isNull);
      expect(smoother.smoothed!.latitude, closeTo(base.latitude, 0.00001));
    });

    test('a 10 km jump after a 5-minute fix gap is ALSO rejected '
        'on the first occurrence (cap holds regardless of dt)', () {
      final smoother = PositionSmoother();
      smoother.add(base, accuracy: 10, at: t0);
      // 35 m/s × 300 s would pass the old gate (10520 m) — the
      // cap must still reject the first far fix after silence.
      final out = smoother.add(
        northOf(base, 10000),
        accuracy: 10,
        at: t0.add(const Duration(minutes: 5)),
      );
      expect(out, isNull);
      expect(smoother.smoothed!.latitude, closeTo(base.latitude, 0.00001));
    });

    test('a legitimate 30 m move in 1 s is accepted', () {
      final smoother = PositionSmoother();
      smoother.add(base, accuracy: 10, at: t0);
      final out = smoother.add(
        northOf(base, 30),
        accuracy: 10,
        at: t0.add(const Duration(seconds: 1)),
      );
      expect(out, isNotNull);
      // Mean of the two equally-weighted fixes: ~15 m north.
      final movedKm = distanceAlongPath([base, out!], 0, 1);
      expect(movedKm, greaterThan(0.01));
      expect(movedKm, lessThan(0.02));
    });

    test('cap boundary: 240 m accepted, 260 m rejected at the '
        'same (generous) reported speed', () {
      final ok = PositionSmoother();
      ok.add(base, accuracy: 10, at: t0);
      expect(
        ok.add(
          northOf(base, 240),
          accuracy: 10,
          at: t0.add(const Duration(seconds: 1)),
          speedMps: 300,
        ),
        isNotNull,
      );
      final capped = PositionSmoother();
      capped.add(base, accuracy: 10, at: t0);
      expect(
        capped.add(
          northOf(base, 260),
          accuracy: 10,
          at: t0.add(const Duration(seconds: 1)),
          speedMps: 300,
        ),
        isNull,
      );
    });

    test('after 5 consecutive far fixes the next one is accepted '
        'as re-acquisition and the marker moves', () {
      final smoother = PositionSmoother();
      smoother.add(base, accuracy: 10, at: t0);
      final far = northOf(base, 10000);
      var t = t0;
      for (var i = 0; i < 5; i++) {
        t = t.add(const Duration(seconds: 1));
        expect(
          smoother.add(far, accuracy: 10, at: t),
          isNull,
          reason: 'far fix ${i + 1} must be rejected',
        );
        expect(
          smoother.smoothed!.latitude,
          closeTo(base.latitude, 0.00001),
        );
      }
      // 6th far fix: sustained disagreement → re-acquire.
      t = t.add(const Duration(seconds: 1));
      final out = smoother.add(far, accuracy: 10, at: t);
      expect(out, isNotNull);
      expect(out!.latitude, closeTo(far.latitude, 0.00001));
      // And normal tracking resumes at the new cluster.
      t = t.add(const Duration(seconds: 1));
      expect(
        smoother.add(northOf(far, 10), accuracy: 10, at: t),
        isNotNull,
      );
    });

    test('re-acquisition also fires on the time rule: 10 s of '
        'only rejections, even with few fixes', () {
      final smoother = PositionSmoother();
      smoother.add(base, accuracy: 10, at: t0);
      final far = northOf(base, 10000);
      expect(
        smoother.add(far, accuracy: 10, at: t0.add(const Duration(seconds: 1))),
        isNull,
      );
      // Second far fix 11 s after the first rejection: the
      // 10 s window has elapsed, so this one re-acquires
      // even though only 1 fix was rejected before it.
      final out = smoother.add(
        far,
        accuracy: 10,
        at: t0.add(const Duration(seconds: 12)),
      );
      expect(out, isNotNull);
      expect(out!.latitude, closeTo(far.latitude, 0.00001));
    });

    test('clear() resets the rejection count, so a fresh session '
        'does not inherit a re-acquisition', () {
      final smoother = PositionSmoother();
      smoother.add(base, accuracy: 10, at: t0);
      final far = northOf(base, 10000);
      for (var i = 0; i < 3; i++) {
        expect(
          smoother.add(far, accuracy: 10, at: t0.add(Duration(seconds: i + 1))),
          isNull,
        );
      }
      smoother.clear();
      smoother.add(base, accuracy: 10, at: t0.add(const Duration(seconds: 10)));
      expect(
        smoother.add(far, accuracy: 10, at: t0.add(const Duration(seconds: 11))),
        isNull,
      );
    });
  });
}
