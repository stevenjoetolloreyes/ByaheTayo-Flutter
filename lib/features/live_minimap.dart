// Live minimap (Nov 11, 2026): a pure-Dart overview of the
// active route — NO second native map. The route polyline, the
// origin / destination dots and the live position dot are drawn
// with CustomPaint from the data passed in, so there is no GPS
// and no network here: the dot reflects the real device GPS
// position the Map tab passes in, never a simulated vehicle.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// The route + live position normalised to fit inside a box of
/// [size] (see [liveMinimapPoints]). Immutable.
class LiveMinimapPoints {
  const LiveMinimapPoints({
    required this.route,
    required this.origin,
    required this.destination,
    required this.live,
  });

  /// Route polyline in box coordinates (empty when the route
  /// has fewer than two points — nothing to draw).
  final List<Offset> route;

  /// Origin dot in box coordinates, or null when the route is
  /// too short to draw.
  final Offset? origin;

  /// Destination dot in box coordinates, or null when the route
  /// is too short to draw.
  final Offset? destination;

  /// Live position dot in box coordinates, or null when no live
  /// position was given (or the route is too short to draw).
  final Offset? live;

  /// True when there is a route to draw.
  bool get isEmpty => route.isEmpty;
}

/// Normalises [routePoints] (+ the optional [livePos]) to fit
/// inside a box of [size], inset by [padding] on every side.
///
/// A single uniform scale preserves the route's aspect ratio
/// (a tall route is never stretched wide); the fitted shape is
/// centred in the box, so the padding is respected on all sides
/// and a live dot at the route's midpoint lands at the centre
/// of the box. North is up (latitude maps to -y).
///
/// Empty routes and single-point routes return an empty result
/// (nothing to draw); the live dot is included in the bounds so
/// it can never fall outside the box.
LiveMinimapPoints liveMinimapPoints({
  required List<LatLng> routePoints,
  required LatLng? livePos,
  required Size size,
  double padding = 8,
}) {
  const empty = LiveMinimapPoints(
    route: [],
    origin: null,
    destination: null,
    live: null,
  );
  if (routePoints.length < 2) return empty;
  var minLat = routePoints.first.latitude;
  var maxLat = routePoints.first.latitude;
  var minLng = routePoints.first.longitude;
  var maxLng = routePoints.first.longitude;
  for (final p in routePoints) {
    minLat = math.min(minLat, p.latitude);
    maxLat = math.max(maxLat, p.latitude);
    minLng = math.min(minLng, p.longitude);
    maxLng = math.max(maxLng, p.longitude);
  }
  if (livePos != null) {
    minLat = math.min(minLat, livePos.latitude);
    maxLat = math.max(maxLat, livePos.latitude);
    minLng = math.min(minLng, livePos.longitude);
    maxLng = math.max(maxLng, livePos.longitude);
  }
  final latRange = maxLat - minLat;
  final lngRange = maxLng - minLng;
  if (latRange == 0 && lngRange == 0) {
    // All points coincide: one dot in the centre.
    final centre = Offset(size.width / 2, size.height / 2);
    return LiveMinimapPoints(
      route: [centre],
      origin: centre,
      destination: centre,
      live: livePos == null ? null : centre,
    );
  }
  final availW = math.max(0.0, size.width - padding * 2);
  final availH = math.max(0.0, size.height - padding * 2);
  var scale = double.infinity;
  if (lngRange > 0) scale = math.min(scale, availW / lngRange);
  if (latRange > 0) scale = math.min(scale, availH / latRange);
  if (!scale.isFinite) scale = 1;
  final contentW = lngRange * scale;
  final contentH = latRange * scale;
  final offsetX = (size.width - contentW) / 2;
  final offsetY = (size.height - contentH) / 2;
  Offset toOffset(LatLng p) => Offset(
        offsetX + (p.longitude - minLng) * scale,
        offsetY + (maxLat - p.latitude) * scale,
      );
  return LiveMinimapPoints(
    route: [for (final p in routePoints) toOffset(p)],
    origin: toOffset(routePoints.first),
    destination: toOffset(routePoints.last),
    live: livePos == null ? null : toOffset(livePos),
  );
}

/// The minimap card: route polyline + origin / destination /
/// live dots on a surface card with a small "ROUTE" label.
/// Tapping it calls [onTap] (the Map tab fits the whole route).
class LiveMinimap extends StatelessWidget {
  const LiveMinimap({
    super.key,
    required this.routePoints,
    required this.livePos,
    this.live = false,
    this.size = const Size(120, 120),
    this.onTap,
  });

  /// The route's points (road geometry, or origin→dest line).
  final List<LatLng> routePoints;

  /// The live GPS position, or null when there is none.
  final LatLng? livePos;

  /// True while Live Follow is active (cyan route line);
  /// false draws the standard green route line.
  final bool live;

  /// Card size (default 120×120).
  final Size size;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final points = liveMinimapPoints(
      routePoints: routePoints,
      livePos: livePos,
      size: size,
    );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            CustomPaint(
              size: size,
              painter: _LiveMinimapPainter(points, live: live),
            ),
            Positioned(
              left: 6,
              top: 4,
              child: Text(
                'ROUTE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveMinimapPainter extends CustomPainter {
  _LiveMinimapPainter(this.points, {required this.live});

  final LiveMinimapPoints points;
  final bool live;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.route.isEmpty) return;
    final routePaint = Paint()
      ..color = live
          ? const Color(0xFF22D3EE)
          : const Color(0xFF16A34A)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(points.route.first.dx, points.route.first.dy);
    for (var i = 1; i < points.route.length; i++) {
      path.lineTo(points.route[i].dx, points.route[i].dy);
    }
    canvas.drawPath(path, routePaint);
    if (points.origin != null) {
      canvas.drawCircle(
        points.origin!,
        4,
        Paint()..color = const Color(0xFF16A34A),
      );
    }
    if (points.destination != null) {
      canvas.drawCircle(
        points.destination!,
        4,
        Paint()..color = const Color(0xFFDC2626),
      );
    }
    if (points.live != null) {
      canvas.drawCircle(
        points.live!,
        5,
        Paint()
          ..color = const Color(0xFF16A34A)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        points.live!,
        5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_LiveMinimapPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.live != live;
}
