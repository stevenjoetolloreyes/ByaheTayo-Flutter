// Unit tests for Live Follow's pure logic (Nov 8, 2026): the
// nearest-stop / remaining-distance / ETA computation from a
// fake GPS position — no device, no GPS. The road is a straight
// north–south line of 11 points (Cabugao 17.79 → Vigan 17.56,
// lng fixed), so every expected value is derived from the
// geometry itself, never hardcoded from the app.
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/live_follow.dart';
import 'package:estudyantego/features/osm_routing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Straight road: 10 equal segments, lat 17.79 → 17.56.
List<LatLng> _road() => [
      for (var i = 0; i <= 10; i++) LatLng(17.79 - i * 0.023, 120.40),
    ];

List<RouteStop> _stops(double totalKm) => [
      const RouteStop(
        name: 'Cabugao',
        region: 'Ilocos Sur',
        lat: 17.79,
        lng: 120.40,
        isOrigin: true,
        isDestination: false,
        pathIndex: 0,
        kmFromOrigin: 0,
      ),
      RouteStop(
        name: 'San Juan',
        region: 'Ilocos Sur',
        lat: 17.675,
        lng: 120.40,
        isOrigin: false,
        isDestination: false,
        pathIndex: 5,
        kmFromOrigin: totalKm / 2,
      ),
      RouteStop(
        name: 'Vigan Bus Terminal',
        region: 'Ilocos Sur',
        lat: 17.56,
        lng: 120.40,
        isOrigin: false,
        isDestination: true,
        pathIndex: 10,
        kmFromOrigin: totalKm,
      ),
    ];

/// Point [metres] north of [p] (1° of latitude ≈ 111,320 m) —
/// places GPS fixes a known distance apart for the smoother
/// tests.
LatLng _northOf(LatLng p, double metres) =>
    LatLng(p.latitude + metres / 111320, p.longitude);

void main() {
  final road = _road();
  final totalKm = distanceAlongPath(road, 0, road.length - 1);
  final stops = _stops(totalKm);
  final now = DateTime(2026, 11, 8, 7, 0);

  LiveFollowSnapshot snapAt(
    LatLng pos, {
    double? speedKmh,
    List<LatLng>? points,
    double? total,
    bool noRoad = false,
  }) =>
      computeLiveFollow(
        roadPoints: noRoad ? null : (points ?? road),
        origin: road.first,
        stops: stops,
        position: pos,
        totalKm: total ?? totalKm,
        speedKmh: speedKmh,
        now: now,
      );

  test('at the origin: nothing travelled, full distance remains', () {
    final snap = snapAt(road.first, speedKmh: 40);
    expect(snap.traveledKm, closeTo(0, 0.001));
    expect(snap.remainingKm, closeTo(totalKm, 0.001));
    expect(snap.progress, 0);
    expect(snap.currentStopIndex, 0);
    expect(snap.arrived, isFalse);
  });

  test('at the origin the ETA is remaining distance / live speed', () {
    final snap = snapAt(road.first, speedKmh: 40);
    expect(snap.remainingMinutes, ((totalKm / 40) * 60).round());
    expect(
      snap.arrivalTime,
      now.add(Duration(minutes: snap.remainingMinutes!)),
    );
  });

  test('slower bus = later arrival, faster bus = earlier arrival', () {
    final slow = snapAt(road.first, speedKmh: 20);
    final fast = snapAt(road.first, speedKmh: 60);
    expect(slow.remainingMinutes, greaterThan(fast.remainingMinutes!));
    expect(slow.arrivalTime!.isAfter(fast.arrivalTime!), isTrue);
  });

  test('mid-route: half travelled, next stop is the destination', () {
    final snap = snapAt(road[5], speedKmh: 40);
    expect(snap.traveledKm, closeTo(totalKm / 2, 0.01));
    expect(snap.remainingKm, closeTo(totalKm / 2, 0.01));
    expect(snap.progress, closeTo(0.5, 0.01));
    expect(snap.arrived, isFalse);
    expect(snap.remainingMinutes, ((totalKm / 2 / 40) * 60).round());
  });

  test('just past the middle stop: the current stop moves to it', () {
    // road[5] sits exactly on the midpoint, where the stop
    // boundary is a floating-point knife-edge — road[6] is
    // clearly past it.
    final snap = snapAt(road[6], speedKmh: 40);
    expect(snap.currentStopIndex, 1);
  });

  test('before the middle stop the current stop is still the origin', () {
    final snap = snapAt(road[4], speedKmh: 40);
    expect(snap.currentStopIndex, 0);
  });

  test('at the destination: arrived, progress full, no ETA needed', () {
    final snap = snapAt(road.last, speedKmh: 40);
    expect(snap.traveledKm, closeTo(totalKm, 0.01));
    expect(snap.remainingKm, closeTo(0, 0.01));
    expect(snap.progress, closeTo(1, 0.001));
    expect(snap.currentStopIndex, 2);
    expect(snap.arrived, isTrue);
    expect(snap.remainingMinutes, isNull);
    expect(snap.arrivalTime, isNull);
  });

  test('stopped bus (speed ~0): no invented arrival', () {
    final snap = snapAt(road[5], speedKmh: 0);
    expect(snap.remainingMinutes, isNull);
    expect(snap.arrivalTime, isNull);
    // The trip numbers are still honest: the bus is halfway.
    expect(snap.progress, closeTo(0.5, 0.01));
    expect(snap.arrived, isFalse);
  });

  test('no speed yet: no invented arrival', () {
    final snap = snapAt(road[5]);
    expect(snap.remainingMinutes, isNull);
    expect(snap.arrivalTime, isNull);
  });

  test('no road geometry yet: progress 0, no ETA, position still followed',
      () {
    final snap = snapAt(
      road[5],
      speedKmh: 40,
      noRoad: true,
      total: totalKm,
    );
    expect(snap.progress, 0);
    expect(snap.traveledKm, 0);
    expect(snap.remainingMinutes, isNull);
  });

  test('speed smoother averages the last samples and ignores unknowns',
      () {
    final smoother = SpeedSmoother();
    expect(smoother.averageKmh, isNull);
    smoother.add(30);
    smoother.add(40);
    smoother.add(50);
    expect(smoother.averageKmh, 40);
    // -1 is the platform's "unknown speed" sentinel: ignored.
    smoother.add(-1);
    expect(smoother.averageKmh, 40);
    // Only the last 5 samples are kept.
    smoother.add(60);
    smoother.add(70);
    smoother.add(80);
    expect(smoother.averageKmh, 60);
  });

  test('speed from two fixes: 1 km in 60 s is 60 km/h', () {
    final kmh = speedKmhBetween(
      prev: const LatLng(17.79, 120.40),
      next: const LatLng(17.799, 120.40),
      delta: const Duration(seconds: 60),
    );
    expect(kmh, closeTo(60, 0.5));
    expect(
      speedKmhBetween(
        prev: const LatLng(17.79, 120.40),
        next: const LatLng(17.799, 120.40),
        delta: Duration.zero,
      ),
      isNull,
    );
  });

  test('bearing follows the direction of travel', () {
    expect(
      bearingBetween(
        const LatLng(17.79, 120.40),
        const LatLng(17.80, 120.40),
      ),
      closeTo(0, 0.5),
    );
    expect(
      bearingBetween(
        const LatLng(17.79, 120.40),
        const LatLng(17.79, 120.41),
      ),
      closeTo(90, 0.5),
    );
    expect(
      bearingBetween(
        const LatLng(17.79, 120.40),
        const LatLng(17.78, 120.40),
      ),
      closeTo(180, 0.5),
    );
  });

  test('angle lerp takes the short way around the 0/360 seam', () {
    expect(lerpAngleDeg(350, 10, 0.5), closeTo(0, 0.001));
    expect(lerpAngleDeg(10, 350, 0.5), closeTo(0, 0.001));
    expect(lerpAngleDeg(0, 90, 0.5), closeTo(45, 0.001));
  });

  test('marker lerp glides halfway toward the latest fix', () {
    final mid = lerpLatLng(
      const LatLng(17.79, 120.40),
      const LatLng(17.80, 120.42),
      0.5,
    );
    expect(mid.latitude, closeTo(17.795, 0.0001));
    expect(mid.longitude, closeTo(120.41, 0.0001));
  });

  test('position smoother accepts the first fix as-is', () {
    final smoother = PositionSmoother();
    expect(smoother.smoothed, isNull);
    final t0 = DateTime(2026, 11, 11, 13, 0);
    final out = smoother.add(
      const LatLng(17.70, 120.40),
      accuracy: 10,
      at: t0,
    );
    expect(out, isNotNull);
    expect(out!.latitude, closeTo(17.70, 0.00001));
    expect(smoother.hasFixes, isTrue);
  });

  test('position smoother averages jitter so a stopped bus stays put',
      () {
    final smoother = PositionSmoother();
    const base = LatLng(17.70, 120.40);
    var t = DateTime(2026, 11, 11, 13, 0);
    // Jitter ±15 m around the true point, 1 s apart.
    smoother.add(_northOf(base, 15), accuracy: 10, at: t);
    t = t.add(const Duration(seconds: 1));
    smoother.add(_northOf(base, -15), accuracy: 10, at: t);
    t = t.add(const Duration(seconds: 1));
    final out = smoother.add(_northOf(base, 10), accuracy: 10, at: t);
    expect(out, isNotNull);
    // Raw fixes wander ±15 m; the mean of the last 3 sits
    // ~3 m from the true point.
    final driftKm = distanceAlongPath([base, out!], 0, 1);
    expect(driftKm, lessThan(0.006));
  });

  test('position smoother drops a wild jump and keeps the last good point',
      () {
    final smoother = PositionSmoother();
    const base = LatLng(17.70, 120.40);
    var t = DateTime(2026, 11, 11, 13, 0);
    smoother.add(base, accuracy: 10, at: t);
    t = t.add(const Duration(seconds: 1));
    // 500 m in one second at 5 m/s: impossible — rejected.
    final out = smoother.add(
      _northOf(base, 500),
      accuracy: 10,
      at: t,
      speedMps: 5,
    );
    expect(out, isNull);
    expect(smoother.smoothed!.latitude, closeTo(17.70, 0.00001));
  });

  test('position smoother accepts real movement along the road', () {
    final smoother = PositionSmoother();
    var t = DateTime(2026, 11, 11, 13, 0);
    var p = const LatLng(17.70, 120.40);
    smoother.add(p, accuracy: 8, at: t);
    // 10 m/s north, one fix per second.
    for (var i = 1; i <= 4; i++) {
      t = t.add(const Duration(seconds: 1));
      p = _northOf(p, 10);
      final out = smoother.add(p, accuracy: 8, at: t, speedMps: 10);
      expect(out, isNotNull, reason: 'fix $i must be accepted');
    }
    // Smoothed point trails the latest fix by ~1 fix (~10 m)
    // but has moved with the bus, not stayed at the start.
    final movedKm =
        distanceAlongPath([const LatLng(17.70, 120.40), smoother.smoothed!], 0, 1);
    expect(movedKm, greaterThan(0.02));
    expect(movedKm, lessThan(0.045));
  });

  test('position smoother never invents a position when fixes stop', () {
    final smoother = PositionSmoother();
    final t0 = DateTime(2026, 11, 11, 13, 0);
    smoother.add(const LatLng(17.70, 120.40), accuracy: 10, at: t0);
    final before = smoother.smoothed;
    // No more fixes: the smoothed point is unchanged (there is
    // no time-based extrapolation in the filter).
    expect(smoother.smoothed, before);
    expect(smoother.smoothed!.latitude, closeTo(17.70, 0.00001));
  });

  test('position smoother weights accurate fixes more', () {
    final smoother = PositionSmoother();
    const base = LatLng(17.70, 120.40);
    final t0 = DateTime(2026, 11, 11, 13, 0);
    smoother.add(base, accuracy: 50, at: t0);
    final out = smoother.add(
      _northOf(base, 20),
      accuracy: 5,
      at: t0.add(const Duration(seconds: 1)),
    );
    expect(out, isNotNull);
    // Weights 1/50 vs 1/5: the accurate fix counts 10x, so the
    // mean sits ~18 m north, not 10 m.
    final driftKm = distanceAlongPath([base, out!], 0, 1);
    expect(driftKm, greaterThan(0.015));
    expect(driftKm, lessThan(0.02));
  });

  test('position smoother clear resets to no fix', () {
    final smoother = PositionSmoother();
    smoother.add(
      const LatLng(17.70, 120.40),
      accuracy: 10,
      at: DateTime(2026, 11, 11, 13, 0),
    );
    smoother.clear();
    expect(smoother.smoothed, isNull);
    expect(smoother.hasFixes, isFalse);
  });

  test('camera tick skips a barely-moved marker, moves on a real move',
      () {
    const target = LatLng(17.70, 120.40);
    // No camera move yet: always move.
    expect(
      liveCameraShouldMove(
        lastTarget: null,
        lastBearing: 0,
        target: target,
        bearing: 0,
      ),
      isTrue,
    );
    // Same spot, same bearing: skip.
    expect(
      liveCameraShouldMove(
        lastTarget: target,
        lastBearing: 0,
        target: target,
        bearing: 0,
      ),
      isFalse,
    );
    // Same spot, 1° bearing change: still skip.
    expect(
      liveCameraShouldMove(
        lastTarget: target,
        lastBearing: 0,
        target: target,
        bearing: 1,
      ),
      isFalse,
    );
    // Same spot, 5° bearing change: move.
    expect(
      liveCameraShouldMove(
        lastTarget: target,
        lastBearing: 0,
        target: target,
        bearing: 5,
      ),
      isTrue,
    );
    // 10 m away: move.
    expect(
      liveCameraShouldMove(
        lastTarget: target,
        lastBearing: 0,
        target: _northOf(target, 10),
        bearing: 0,
      ),
      isTrue,
    );
    // Bearing across the 0/360 seam: 359° vs 1° is a 2° change.
    expect(
      liveCameraShouldMove(
        lastTarget: target,
        lastBearing: 359,
        target: target,
        bearing: 1,
      ),
      isTrue,
    );
  });

  test('arrival clock time formats 12-hour with AM/PM', () {
    expect(formatArrivalTime(DateTime(2026, 11, 8, 7, 55)), '7:55 AM');
    expect(formatArrivalTime(DateTime(2026, 11, 8, 12, 5)), '12:05 PM');
    expect(formatArrivalTime(DateTime(2026, 11, 8, 0, 0)), '12:00 AM');
    expect(formatArrivalTime(DateTime(2026, 11, 8, 13, 30)), '1:30 PM');
  });

  test('faresMapJump record carries startLive for Start Ride', () {
    faresMapJump.value = (
      from: 'Cabugao',
      to: 'Vigan Bus Terminal',
      fromLat: null,
      fromLng: null,
      startLive: true,
    );
    expect(faresMapJump.value?.startLive, isTrue);
    faresMapJump.value = null;
  });
}
