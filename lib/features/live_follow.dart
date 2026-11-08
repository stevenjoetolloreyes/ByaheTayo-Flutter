// Live Follow (Nov 8, 2026): the pure math behind the Map tab's
// real-GPS follow mode. No widgets, no GPS — every function here
// is testable from a fake position, so the ETA / stop / progress
// rules are verified without a device.
//
// The rules (Steven, Nov 8, 21:45): the arrival time is
// CALCULATED from the bus's real running speed (live GPS) and the
// remaining distance ALONG the route geometry — never guessed.
// Remaining distance / smoothed speed = remaining time;
// arrival clock time = now + remaining time. When the speed is
// unavailable or the bus is stopped, the ETA is null — the panel
// shows an honest state instead of inventing a time.
import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'osm_routing.dart';

/// No GPS fix for this long = the signal is lost (the panel says
/// so honestly and keeps the last known position).
const liveGpsLostAfter = Duration(seconds: 10);

/// Below this smoothed speed (km/h) the bus counts as stopped
/// for ETA purposes — dividing by ~0 would invent an arrival.
const liveMinMovingKmh = 3.0;

/// Within this distance of the destination (km) the trip counts
/// as arrived.
const liveArrivedWithinKm = 0.1;

/// A snapshot of a live ride, computed from one GPS position +
/// the route geometry. Immutable: the Map tab recomputes it on
/// every fix (and on its clock tick) and renders it as-is.
class LiveFollowSnapshot {
  const LiveFollowSnapshot({
    required this.traveledKm,
    required this.remainingKm,
    required this.totalKm,
    required this.progress,
    required this.currentStopIndex,
    required this.arrived,
    required this.speedKmh,
    required this.remainingMinutes,
    required this.arrivalTime,
  });

  /// Distance already travelled along the route (km).
  final double traveledKm;

  /// Distance left along the route to the destination (km) —
  /// measured along the road geometry, never straight-line.
  final double remainingKm;

  /// The route's total length (km).
  final double totalKm;

  /// [traveledKm] / [totalKm], clamped to 0..1 (the progress
  /// bar fill).
  final double progress;

  /// Index into the route's stops of the stop the bus is at /
  /// has most recently passed (0 = origin).
  final int currentStopIndex;

  /// True when [remainingKm] is within [liveArrivedWithinKm].
  final bool arrived;

  /// The smoothed live speed (km/h), or null when no speed
  /// sample has been recorded yet.
  final double? speedKmh;

  /// Remaining minutes = remainingKm / smoothed speed, or null
  /// when the speed is unavailable or below [liveMinMovingKmh]
  /// — null means "do not show an arrival", never a guess.
  final int? remainingMinutes;

  /// Clock time of arrival = now + [remainingMinutes], or null
  /// when [remainingMinutes] is null.
  final DateTime? arrivalTime;
}

/// Computes a [LiveFollowSnapshot] from a live GPS [position].
///
/// [roadPoints] is the OSRM road geometry (null / too short =
/// geometry not loaded yet: progress stays 0 and no ETA is
/// computed — the position is still followed). [origin] is the
/// route's start point (the path index it snaps to is the
/// travelled-distance baseline, matching [RouteStop.kmFromOrigin]).
/// [stops] are the route's stops in road order. [totalKm] is the
/// route's total length; [speedKmh] the smoothed live speed
/// (null = no speed yet). [now] is injected so tests can pin the
/// arrival clock time.
LiveFollowSnapshot computeLiveFollow({
  required List<LatLng>? roadPoints,
  required LatLng? origin,
  required List<RouteStop> stops,
  required LatLng position,
  required double totalKm,
  required double? speedKmh,
  required DateTime now,
}) {
  // No geometry / no length yet: nothing to measure along. The
  // caller still follows the position; only the trip numbers
  // wait.
  if (roadPoints == null || roadPoints.length < 2 || totalKm <= 0) {
    return LiveFollowSnapshot(
      traveledKm: 0,
      remainingKm: totalKm > 0 ? totalKm : 0,
      totalKm: totalKm > 0 ? totalKm : 0,
      progress: 0,
      currentStopIndex: 0,
      arrived: false,
      speedKmh: speedKmh,
      remainingMinutes: null,
      arrivalTime: null,
    );
  }
  final originIdx =
      origin == null ? 0 : nearestPathIndex(roadPoints, origin);
  final idx = nearestPathIndex(roadPoints, position);
  // distanceAlongPath returns 0 when idx <= originIdx (the bus
  // is at / behind the origin), so travelled never goes negative.
  final traveled =
      distanceAlongPath(roadPoints, originIdx, idx).clamp(0.0, totalKm);
  final remaining = (totalKm - traveled).clamp(0.0, totalKm);
  final progress = (traveled / totalKm).clamp(0.0, 1.0);
  // The current stop is the last one whose distance from the
  // origin the bus has reached (0 = the origin, before the
  // first stop is passed).
  var currentStop = 0;
  for (var i = 0; i < stops.length; i++) {
    if (stops[i].kmFromOrigin <= traveled) currentStop = i;
  }
  final arrived = remaining <= liveArrivedWithinKm;
  // ETA = remaining distance / smoothed speed. Only when the bus
  // is actually moving — a stopped bus (or no speed yet) yields
  // null, never a guessed time.
  int? remainingMinutes;
  DateTime? arrivalTime;
  if (speedKmh != null && speedKmh > liveMinMovingKmh && remaining > 0) {
    remainingMinutes = (remaining / speedKmh * 60).round();
    arrivalTime = now.add(Duration(minutes: remainingMinutes));
  }
  return LiveFollowSnapshot(
    traveledKm: traveled,
    remainingKm: remaining,
    totalKm: totalKm,
    progress: progress,
    currentStopIndex: currentStop,
    arrived: arrived,
    speedKmh: speedKmh,
    remainingMinutes: remainingMinutes,
    arrivalTime: arrivalTime,
  );
}

/// Smoothed live speed: a moving average over the last few GPS
/// speed samples, so one noisy fix cannot swing the ETA. Samples
/// below 0 (the platform's "unknown" sentinel) are ignored.
class SpeedSmoother {
  SpeedSmoother({this.capacity = 5});

  final int capacity;
  final List<double> _samples = [];

  void add(double kmh) {
    if (kmh.isNaN || kmh.isInfinite || kmh < 0) return;
    _samples.add(kmh);
    if (_samples.length > capacity) _samples.removeAt(0);
  }

  /// Mean of the kept samples (km/h), or null when no valid
  /// sample has been recorded yet.
  double? get averageKmh {
    if (_samples.isEmpty) return null;
    var sum = 0.0;
    for (final s in _samples) {
      sum += s;
    }
    return sum / _samples.length;
  }

  bool get hasSamples => _samples.isNotEmpty;

  void clear() => _samples.clear();
}

/// Speed (km/h) implied by two fixes and the time between them —
/// the fallback when the device reports no speed. Null when the
/// time delta is not positive (no movement can be derived).
double? speedKmhBetween({
  required LatLng prev,
  required LatLng next,
  required Duration delta,
}) {
  if (delta <= Duration.zero) return null;
  final km = distanceAlongPath([prev, next], 0, 1);
  final hours = delta.inMilliseconds / 3600000;
  if (hours <= 0) return null;
  return km / hours;
}

/// Initial bearing from [from] to [to] in degrees, 0..360
/// (0 = north, 90 = east). 0 when the two points coincide.
double bearingBetween(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final dLng = (to.longitude - from.longitude) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  if (y == 0 && x == 0) return 0;
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Interpolates an angle (degrees) toward a target along the
/// shortest arc, so a bearing never spins the long way around
/// the 0/360 seam (350° → 10° passes through 0, not 180).
/// The result is normalised to 0..360.
double lerpAngleDeg(double from, double to, double t) {
  var diff = (to - from) % 360;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  return (from + diff * t) % 360;
}

/// Linear interpolation between two positions (used to glide
/// the bus marker toward the latest GPS fix between updates).
LatLng lerpLatLng(LatLng a, LatLng b, double t) {
  return LatLng(
    a.latitude + (b.latitude - a.latitude) * t,
    a.longitude + (b.longitude - a.longitude) * t,
  );
}

/// Clock time for the arrival chip: "7:55 AM" / "12:05 PM" /
/// "12:00 AM" (12-hour, no leading zero on the hour).
String formatArrivalTime(DateTime t) {
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minutes = t.minute.toString().padLeft(2, '0');
  final suffix = t.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minutes $suffix';
}
