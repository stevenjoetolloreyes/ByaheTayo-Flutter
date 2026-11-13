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

/// GPS position smoothing for Live Follow (Nov 11, 2026): the
/// raw fixes jitter ±5–20 m even when the bus is still, which
/// yanks the marker and the follow camera off the road. This
/// filter keeps the last few ACCEPTED fixes and returns their
/// accuracy-weighted mean, so jitter averages out. It never
/// invents a position: the smoothed point only changes when a
/// real fix is accepted, and a wild jump — farther than the bus
/// could possibly have travelled since the last fix — is
/// dropped outright instead of dragging the marker across the
/// map. No sensor fusion, no dead reckoning, no snap-to-road:
/// only the fixes themselves are used.
class PositionSmoother {
  PositionSmoother({
    this.capacity = 3,
    this.maxPlausibleSpeedMps = 35,
    this.minPlausibleSpeedMps = 15,
  });

  /// Fixes kept for the weighted mean (a few only, so the
  /// filter adds at most ~1 fix of lag).
  final int capacity;

  /// Fastest the bus could plausibly travel (m/s) — used when
  /// the device reports no speed. 35 m/s ≈ 126 km/h, generous
  /// for a bus, so a real fix is never rejected for speed.
  final double maxPlausibleSpeedMps;

  /// Slowest speed the filter ever assumes (m/s): the device
  /// sometimes reports 0 while the bus is already rolling, so
  /// a fix is always allowed at least this much travel. 15 m/s
  /// still rejects a 100 m jump in one second at a stop.
  final double minPlausibleSpeedMps;

  final List<_PositionFix> _fixes = [];

  /// Feeds one raw fix. Returns the new smoothed position, or
  /// null when the fix was rejected as an outlier (the smoothed
  /// position is unchanged then). [accuracy] is the fix's
  /// reported accuracy in metres; [speedMps] the device's
  /// reported speed in m/s (null = unknown).
  LatLng? add(
    LatLng point, {
    required double accuracy,
    required DateTime at,
    double? speedMps,
  }) {
    if (_fixes.isNotEmpty) {
      final last = _fixes.last;
      final dtSeconds =
          at.difference(last.at).inMilliseconds / 1000;
      final speed = math.max(
        speedMps ?? maxPlausibleSpeedMps,
        minPlausibleSpeedMps,
      );
      final maxDistance = speed * (dtSeconds > 0 ? dtSeconds : 0) +
          last.accuracy +
          accuracy;
      final movedKm = distanceAlongPath([last.point, point], 0, 1);
      if (movedKm * 1000 > maxDistance) return null;
    }
    _fixes.add(_PositionFix(point, accuracy, at));
    if (_fixes.length > capacity) _fixes.removeAt(0);
    return smoothed;
  }

  /// Current smoothed position, or null before any fix.
  LatLng? get smoothed {
    if (_fixes.isEmpty) return null;
    var wSum = 0.0;
    var latSum = 0.0;
    var lngSum = 0.0;
    for (final f in _fixes) {
      // Weight by accuracy: a 5 m fix counts 4x a 20 m fix.
      // Accuracy is clamped to >= 5 m so a (possibly
      // optimistic) 1 m report cannot dominate the mean.
      final w = 1 / math.max(f.accuracy, 5);
      wSum += w;
      latSum += f.point.latitude * w;
      lngSum += f.point.longitude * w;
    }
    return LatLng(latSum / wSum, lngSum / wSum);
  }

  bool get hasFixes => _fixes.isNotEmpty;

  void clear() => _fixes.clear();
}

class _PositionFix {
  const _PositionFix(this.point, this.accuracy, this.at);
  final LatLng point;
  final double accuracy;
  final DateTime at;
}

/// Whether the follow camera should re-target on this tick
/// (Nov 11, 2026): skip when the marker has barely moved since
/// the last camera move (< 2 m and < 2° bearing change), so a
/// stopped bus does not re-animate the camera on every tick.
/// A null [lastTarget] (no camera move yet) always moves.
bool liveCameraShouldMove({
  required LatLng? lastTarget,
  required double lastBearing,
  required LatLng target,
  required double bearing,
}) {
  if (lastTarget == null) return true;
  final movedKm = distanceAlongPath([lastTarget, target], 0, 1);
  if (movedKm >= 0.002) return true;
  var diff = (bearing - lastBearing).abs() % 360;
  if (diff > 180) diff = 360 - diff;
  return diff >= 2;
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

/// Screen rotation of the Live Follow vehicle marker, in
/// degrees, normalised to -180..180: the live bearing minus the
/// map's current bearing, so the marker points along the
/// direction of travel ON SCREEN. In heading-up Live mode the
/// map bearing equals the live bearing, so the marker points
/// straight up; in north-up it points along the heading.
/// Wraps across the 0/360 seam (live 10, map 350 -> 20, not
/// -340; live 350, map 10 -> -20).
double liveMarkerScreenRotationDeg({
  required double liveBearing,
  required double mapBearing,
}) {
  var diff = (liveBearing - mapBearing) % 360;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  return diff;
}

/// Live Follow arrow marker style (Nov 13, 2026 — approved
/// Preview v2, Arrow option): the current-position marker is a
/// navigation arrow, NOT a bus/car glyph. The arrow itself
/// rotates to the heading; the cone + halo behind it are the
/// "GPS is live" chrome. When the signal is lost the marker
/// goes grey with an amber dashed ring and NO cone / NO pulse,
/// so a stale position never looks live — the panel text stays
/// honest ("GPS signal lost — showing your last known
/// position"). Pure decision, no widgets, so the two states
/// are pinned in tests. Colours are raw ARGB ints so this file
/// stays free of flutter/material imports.
class LiveArrowMarkerStyle {
  const LiveArrowMarkerStyle({
    required this.coreStart,
    required this.coreEnd,
    required this.showHeadingCone,
    required this.showHalo,
    required this.showLostRing,
  });

  /// Top-left gradient colour of the 56dp arrow core.
  final int coreStart;

  /// Bottom-right gradient colour of the 56dp arrow core.
  final int coreEnd;

  /// Heading cone behind the arrow (locked only).
  final bool showHeadingCone;

  /// Pulsing GPS halo around the core (locked only).
  final bool showHalo;

  /// Amber dashed ring around the core (lost only).
  final bool showLostRing;
}

/// Style for the Live Follow arrow marker for [gpsLost].
LiveArrowMarkerStyle liveArrowMarkerStyle({required bool gpsLost}) {
  if (gpsLost) {
    return const LiveArrowMarkerStyle(
      coreStart: 0xFF9CA3AF,
      coreEnd: 0xFF6B7280,
      showHeadingCone: false,
      showHalo: false,
      showLostRing: true,
    );
  }
  return const LiveArrowMarkerStyle(
    coreStart: 0xFF17CE62,
    coreEnd: 0xFF0AA84C,
    showHeadingCone: true,
    showHalo: true,
    showLostRing: false,
  );
}

/// Google-level smoothing (Nov 13, 2026 — approved Preview v2):
/// snap-to-road + per-frame prediction. Every helper here is
/// pure, so the rules are pinned in tests without a device.
///
/// Snap-to-road never invents a position: it only projects the
/// real (smoothed) GPS fix onto the nearest point of the loaded
/// OSRM road geometry. Prediction never invents movement either:
/// it advances the last real fix along the road at the last
/// measured speed, and only for [livePredictionCoast] after the
/// fix — after that the arrow holds until a new fix arrives.

/// A GPS fix snapped onto the road geometry.
class SnappedRoadPosition {
  const SnappedRoadPosition({
    required this.point,
    required this.segmentIndex,
    required this.distanceAlongKm,
    required this.offRoadKm,
  });

  /// The fix projected onto the road.
  final LatLng point;

  /// Index of the road segment's start vertex.
  final int segmentIndex;

  /// Distance from the road's start to [point], along the road.
  final double distanceAlongKm;

  /// How far the raw fix was from the road.
  final double offRoadKm;
}

/// Projects [position] onto the nearest segment of [roadPoints]
/// (equirectangular metres around the fix — fine at road scale).
/// Null when there is no usable geometry (< 2 points): the
/// caller falls back to the smoothed fix itself.
SnappedRoadPosition? snapToRoad({
  required LatLng position,
  required List<LatLng>? roadPoints,
}) {
  if (roadPoints == null || roadPoints.length < 2) return null;
  const earthMPerDegLat = 110540.0;
  final mPerDegLng = 111320.0 * math.cos(position.latitude * math.pi / 180);
  double toX(LatLng p) => (p.longitude - position.longitude) * mPerDegLng;
  double toY(LatLng p) => (p.latitude - position.latitude) * earthMPerDegLat;
  var bestDistM = double.infinity;
  var bestPoint = roadPoints.first;
  var bestSegment = 0;
  var bestAlongKm = 0.0;
  var alongKm = 0.0;
  for (var i = 0; i < roadPoints.length - 1; i++) {
    final a = roadPoints[i];
    final b = roadPoints[i + 1];
    final segKm = distanceAlongPath([a, b], 0, 1);
    final ax = toX(a);
    final ay = toY(a);
    final bx = toX(b);
    final by = toY(b);
    final dx = bx - ax;
    final dy = by - ay;
    final lenSq = dx * dx + dy * dy;
    // t = where the fix projects onto the segment, clamped to
    // the segment (0 = at a, 1 = at b).
    var t = lenSq == 0 ? 0.0 : (-(ax * dx) - ay * dy) / lenSq;
    t = t.clamp(0.0, 1.0);
    final px = ax + dx * t;
    final py = ay + dy * t;
    final distM = math.sqrt(px * px + py * py);
    if (distM < bestDistM) {
      bestDistM = distM;
      bestPoint = LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );
      bestSegment = i;
      bestAlongKm = alongKm + distanceAlongPath([a, bestPoint], 0, 1);
    }
    alongKm += segKm;
  }
  return SnappedRoadPosition(
    point: bestPoint,
    segmentIndex: bestSegment,
    distanceAlongKm: bestAlongKm,
    offRoadKm: bestDistM / 1000,
  );
}

/// Point [distanceKm] along [roadPoints] from its start
/// (linear within a segment). Past the end clamps to the last
/// road point — prediction never runs off the road.
LatLng pointAtDistanceAlongRoad(List<LatLng> roadPoints, double distanceKm) {
  if (roadPoints.isEmpty) return const LatLng(0, 0);
  if (distanceKm <= 0) return roadPoints.first;
  var remaining = distanceKm;
  for (var i = 0; i < roadPoints.length - 1; i++) {
    final segKm = distanceAlongPath(
      [roadPoints[i], roadPoints[i + 1]],
      0,
      1,
    );
    if (remaining <= segKm) {
      final t = segKm == 0 ? 0.0 : remaining / segKm;
      return LatLng(
        roadPoints[i].latitude +
            (roadPoints[i + 1].latitude - roadPoints[i].latitude) * t,
        roadPoints[i].longitude +
            (roadPoints[i + 1].longitude - roadPoints[i].longitude) * t,
      );
    }
    remaining -= segKm;
  }
  return roadPoints.last;
}

/// Destination point [distanceKm] from [from] along
/// [bearingDeg] (haversine destination formula). Used only when
/// there is no road geometry to advance along.
LatLng destinationPoint({
  required LatLng from,
  required double bearingDeg,
  required double distanceKm,
}) {
  const earthKm = 6371.0;
  final d = distanceKm / earthKm;
  final br = bearingDeg * math.pi / 180;
  final lat1 = from.latitude * math.pi / 180;
  final lng1 = from.longitude * math.pi / 180;
  final lat2 = math.asin(
    math.sin(lat1) * math.cos(d) +
        math.cos(lat1) * math.sin(d) * math.cos(br),
  );
  final lng2 = lng1 +
      math.atan2(
        math.sin(br) * math.sin(d) * math.cos(lat1),
        math.cos(d) - math.sin(lat1) * math.sin(lat2),
      );
  return LatLng(lat2 * 180 / math.pi, lng2 * 180 / math.pi);
}

/// How long after the last GPS fix the arrow may keep coasting
/// on prediction (3 s): long enough to bridge the normal ~1 s
/// fix gap and brief dropouts, short enough that a dead GPS
/// never looks alive. After this the arrow holds its last
/// position until a new fix arrives (and the 10 s
/// [liveGpsLostAfter] timer raises the honest lost state).
const livePredictionCoast = Duration(seconds: 3);

/// True while prediction may still coast: the last fix is no
/// older than [coast] (default [livePredictionCoast]).
bool livePredictionShouldCoast({
  required DateTime lastFixAt,
  required DateTime now,
  Duration coast = livePredictionCoast,
}) =>
    !now.difference(lastFixAt).isNegative &&
    now.difference(lastFixAt) <= coast;

/// Predicts where the arrow should be [elapsed] after the last
/// fix at [from], travelling at [speedKmh] along [bearingDeg].
/// With road geometry + [distanceAlongKm] it advances along
/// the road (so it follows curves); without geometry it dead-
/// reckons along the bearing. No speed (null / 0) or no time
/// passed = [from]: a stopped bus does not drift.
LatLng predictLivePosition({
  required LatLng from,
  required double bearingDeg,
  required double? speedKmh,
  required Duration elapsed,
  List<LatLng>? roadPoints,
  double? distanceAlongKm,
}) {
  if (speedKmh == null ||
      speedKmh <= 0 ||
      elapsed <= Duration.zero) {
    return from;
  }
  final distanceKm = speedKmh * elapsed.inMilliseconds / 3600000;
  if (roadPoints != null &&
      roadPoints.length >= 2 &&
      distanceAlongKm != null) {
    return pointAtDistanceAlongRoad(
      roadPoints,
      distanceAlongKm + distanceKm,
    );
  }
  return destinationPoint(
    from: from,
    bearingDeg: bearingDeg,
    distanceKm: distanceKm,
  );
}

/// The close street-level zoom Live Follow settles at (Nov 11,
/// 2026 — Live close-follow): the preview's settled zoom, so the
/// street fills the view while driving. Replaces the old follow
/// zoom of 16.
const double liveCloseFollowZoom = 18.3;

/// Ease-in duration for the first Live Follow camera move of a
/// session (Nov 11, 2026): the camera glides into the close view
/// in about a second instead of snapping to it. Later moves keep
/// the existing 900 ms glide. No 360° spin — the spin belongs to
/// the preview fly-in only.
const Duration liveCloseFollowEaseIn = Duration(milliseconds: 1000);

/// Effective Live Follow zoom: a manual zoom the user made during
/// Live (+/−, pinch, double-tap) wins and is respected until
/// Overview / My Location / Resume re-fits; otherwise the close
/// follow zoom. Null [userZoom] = no manual zoom.
double liveFollowZoom({double? userZoom}) => userZoom ?? liveCloseFollowZoom;

/// True when a Live Follow gesture pause was really a zoom
/// (pinch / double-tap): the zoom moved while the gesture ran.
/// A drag or a rotate never changes the zoom, so the zoom delta
/// alone tells them apart. [tolerance] (0.2) ignores the small
/// drift of a follow-camera glide that was still settling when
/// the gesture started — a deliberate pinch moves the zoom by
/// far more than that.
bool liveGestureWasZoom({
  required double startZoom,
  required double zoom,
  double tolerance = 0.2,
}) {
  return (zoom - startZoom).abs() > tolerance;
}

/// Target zoom for a plain map tap (tap-to-zoom, Nov 11,
/// 2026): two levels closer than the current zoom, clamped to
/// the map's 3..19 range. Exactly at the Live follow zoom
/// ([liveCloseFollowZoom]) the tap recentres without zooming
/// further in — the follow camera already sits there, so zooming
/// on every tap would walk the zoom up while the user is only
/// trying to look around. (Above the follow zoom the +2 clamp
/// still applies: 18 -> 19.) The 0.05 tolerance covers native
/// zoom values landing a hair off the constant.
double liveTapZoomTarget(double currentZoom) {
  if ((currentZoom - liveCloseFollowZoom).abs() < 0.05) {
    return liveCloseFollowZoom;
  }
  return (currentZoom + 2).clamp(3.0, 19.0);
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

/// Live speed for the Live panel's Speed chip: whole km/h
/// ("42 km/h"), or "—" when no speed sample exists yet — never
/// a guessed speed.
String formatLiveSpeedKmh(double? kmh) {
  if (kmh == null || kmh.isNaN || kmh.isInfinite) return '—';
  return '${kmh.round()} km/h';
}

/// Live distance for the Live panel's Distance chip:
/// travelled / total route, one decimal ("12.3 / 27.0 km").
String formatLiveDistanceKm(double traveledKm, double totalKm) {
  return '${traveledKm.toStringAsFixed(1)} / '
      '${totalKm.toStringAsFixed(1)} km';
}
