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
