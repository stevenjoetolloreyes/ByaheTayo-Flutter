// OpenStreetMap routing + lookup helpers for the Map tab.
//
// This file is the OSM side of the Map tab: OSRM road routing
// (replacing the Google Routes API), Nominatim place lookup
// (replacing Google Places where a lookup is needed), the OSM /
// Esri tile URLs, and the pure route-stop math (stops along the
// way, distances along the real road geometry, segment split).
//
// Everything here is pure except the two fetchers at the bottom,
// which only do one HTTP GET each and hand the body to the pure
// parsers. No geometry is ever invented: the road line is OSRM's
// GeoJSON geometry, and stops are real hubs from fares_tab.dart
// that sit on that geometry (plus a custom route's own via-hubs).
// The preview's Partas-70 / GMW-33 municipality lists were
// preview-side derivations from OSRM sampling; they are NOT
// reproduced here — the app only knows its own hubs.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'fares_tab.dart';

/// Standard OSM raster tiles (the "Standard" map-type pill).
const osmStandardTileUrl =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Esri World Imagery tiles (the "Satellite" map-type pill).
const osmSatelliteTileUrl =
    'https://server.arcgisonline.com/ArcGIS/rest/services/'
    'World_Imagery/MapServer/tile/{z}/{y}/{x}';

/// OSM copyright page, opened from the attribution chip.
const osmCopyrightUrl = 'https://www.openstreetmap.org/copyright';

/// Tile URL template for a map-type pill choice.
String tileUrlTemplate({required bool satellite}) =>
    satellite ? osmSatelliteTileUrl : osmStandardTileUrl;

/// One route from OSRM: the road-following geometry (GeoJSON
/// [lng, lat] pairs, converted here), the routed length and
/// duration, and turn steps. Null fields mean "not loaded".
class OsrmRoute {
  const OsrmRoute({
    required this.points,
    required this.distanceKm,
    required this.durationSec,
    required this.steps,
  });

  /// Road geometry, origin first, destination last.
  final List<LatLng> points;

  /// Routed length in km (OSRM `distance` / 1000).
  final double distanceKm;

  /// Routed duration in seconds (OSRM `duration`).
  final double durationSec;

  /// Turn steps, in route order.
  final List<OsrmStep> steps;
}

/// One OSRM turn step: a human-readable instruction built from
/// the maneuver + road name, its location, and its length.
class OsrmStep {
  const OsrmStep({
    required this.instruction,
    required this.location,
    required this.distanceMeters,
  });

  final String instruction;
  final LatLng location;
  final double distanceMeters;
}

/// OSRM route URL for a drive from ([oLat], [oLng]) to [dest],
/// through [via] in order. Coordinates are `lng,lat` per the
/// OSRM API; `overview=full` returns the full road geometry and
/// `steps=true` returns turn steps. Pure, so the URL is testable.
String osrmRouteUrl({
  required double oLat,
  required double oLng,
  required Hub dest,
  List<LatLng> via = const [],
}) {
  String coord(double lat, double lng) => '$lng,$lat';
  final parts = <String>[
    coord(oLat, oLng),
    for (final p in via) coord(p.latitude, p.longitude),
    coord(dest.lat, dest.lng),
  ];
  return 'https://router.project-osrm.org/route/v1/driving/'
      '${parts.join(';')}'
      '?overview=full&geometries=geojson&steps=true';
}

/// Parses an OSRM `/route/v1/driving` JSON body into an
/// [OsrmRoute], or null when the body has no usable route.
/// Coordinates arrive as GeoJSON [lng, lat] and are flipped
/// here; anything unusable yields null, never a guessed line.
OsrmRoute? parseOsrmRoute(Map<String, dynamic> json) {
  final routes = json['routes'];
  if (routes is! List || routes.isEmpty) return null;
  final first = routes.first;
  if (first is! Map<String, dynamic>) return null;
  final geometry = first['geometry'];
  if (geometry is! Map<String, dynamic>) return null;
  final coords = geometry['coordinates'];
  if (coords is! List) return null;
  final points = <LatLng>[];
  for (final c in coords) {
    if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
      points.add(
        LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      );
    }
  }
  if (points.length < 2) return null;
  final distance = first['distance'];
  final duration = first['duration'];
  final steps = <OsrmStep>[];
  final legs = first['legs'];
  if (legs is List) {
    for (final leg in legs) {
      if (leg is! Map<String, dynamic>) continue;
      final legSteps = leg['steps'];
      if (legSteps is! List) continue;
      for (final s in legSteps) {
        final step = _parseOsrmStep(s);
        if (step != null) steps.add(step);
      }
    }
  }
  return OsrmRoute(
    points: points,
    distanceKm: distance is num ? distance.toDouble() / 1000 : 0,
    durationSec: duration is num ? duration.toDouble() : 0,
    steps: steps,
  );
}

/// One OSRM leg step -> an [OsrmStep], or null when the step
/// carries no usable maneuver. The instruction is built from
/// the maneuver's own type/modifier + the road name the API
/// returned — never an invented road name.
OsrmStep? _parseOsrmStep(Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  final maneuver = raw['maneuver'];
  if (maneuver is! Map<String, dynamic>) return null;
  final location = maneuver['location'];
  if (location is! List ||
      location.length < 2 ||
      location[0] is! num ||
      location[1] is! num) {
    return null;
  }
  final type = maneuver['type']?.toString() ?? '';
  final modifier = maneuver['modifier']?.toString() ?? '';
  final name = raw['name']?.toString() ?? '';
  final distance = raw['distance'];
  return OsrmStep(
    instruction: _osrmInstruction(type, modifier, name),
    location: LatLng(
      (location[1] as num).toDouble(),
      (location[0] as num).toDouble(),
    ),
    distanceMeters: distance is num ? distance.toDouble() : 0,
  );
}

/// Human-readable instruction from an OSRM maneuver. `depart`
/// / `arrive` keep the road name when the API gave one; turns
/// name their direction and road; anything unknown falls back
/// to "Continue" rather than a fabricated turn.
String _osrmInstruction(String type, String modifier, String road) {
  final onRoad = road.isEmpty ? '' : ' onto $road';
  switch (type) {
    case 'depart':
      return road.isEmpty ? 'Head out' : 'Head out on $road';
    case 'arrive':
      return 'Arrive at destination';
    case 'turn':
      return switch (modifier) {
        'left' => 'Turn left$onRoad',
        'right' => 'Turn right$onRoad',
        'sharp left' => 'Turn sharp left$onRoad',
        'sharp right' => 'Turn sharp right$onRoad',
        'slight left' => 'Turn slight left$onRoad',
        'slight right' => 'Turn slight right$onRoad',
        'uturn' => 'Make a U-turn$onRoad',
        _ => 'Turn$onRoad',
      };
    case 'roundabout':
    case 'rotary':
      return road.isEmpty
          ? 'At the roundabout, take the exit'
          : 'At the roundabout, take the exit onto $road';
    case 'merge':
      return 'Merge$onRoad';
    case 'on ramp':
      return 'Take the ramp$onRoad';
    case 'off ramp':
      return 'Take the exit$onRoad';
    case 'fork':
      return switch (modifier) {
        'left' => 'Keep left$onRoad',
        'right' => 'Keep right$onRoad',
        _ => 'Keep going$onRoad',
      };
    case 'end of road':
      return switch (modifier) {
        'left' => 'Turn left at the end of the road$onRoad',
        'right' => 'Turn right at the end of the road$onRoad',
        _ => 'At the end of the road$onRoad',
      };
    default:
      return road.isEmpty ? 'Continue' : 'Continue on $road';
  }
}

/// Fetches the OSRM road route for a drive from ([oLat], [oLng])
/// to [dest] through [via]. Returns null on any failure (no
/// network, non-200, unusable body) — the caller then keeps the
/// dashed direct line and explains why, exactly like the old
/// Google routing failure path.
Future<OsrmRoute?> fetchOsrmRoute({
  required double oLat,
  required double oLng,
  required Hub dest,
  List<LatLng> via = const [],
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(
      Uri.parse(osrmRouteUrl(oLat: oLat, oLng: oLng, dest: dest, via: via)),
    );
    request.headers.set('User-Agent', 'EstudyanteGO/1.0');
    final response = await request.close().timeout(
      const Duration(seconds: 20),
    );
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    return parseOsrmRoute(decoded);
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

/// Nominatim search URL for Catholic churches inside the
/// Northern Luzon viewbox (west, south, east, north). `bounded=1`
/// keeps results inside the box; the query is deliberately the
/// generic "Catholic church" because Nominatim has no
/// denomination filter. Pure, so the URL is testable.
String nominatimChurchesUrl() {
  return 'https://nominatim.openstreetmap.org/search'
      '?q=Catholic%20church'
      '&format=jsonv2'
      '&addressdetails=0'
      '&limit=50'
      '&viewbox=119.9,15.9,122.3,18.7'
      '&bounded=1';
}

/// One parsed Nominatim place: the name shown, coordinates, and
/// the full display name as the address. The caller turns these
/// into ChurchPlace entries.
typedef NominatimPlace = ({
  String name,
  double lat,
  double lng,
  String address,
});

/// Parses a Nominatim search response (a JSON array) into
/// places. Entries without a usable name + coordinates are
/// skipped, never guessed; the name is the first component of
/// the display name.
List<NominatimPlace> parseNominatimChurches(List<dynamic> json) {
  final places = <NominatimPlace>[];
  for (final entry in json) {
    if (entry is! Map<String, dynamic>) continue;
    final display = entry['display_name']?.toString() ?? '';
    final lat = entry['lat'];
    final lng = entry['lon'];
    if (display.isEmpty || lat is! String || lng is! String) continue;
    final parsedLat = double.tryParse(lat);
    final parsedLng = double.tryParse(lng);
    if (parsedLat == null || parsedLng == null) continue;
    final name = display.split(',').first.trim();
    if (name.isEmpty) continue;
    places.add((
      name: name,
      lat: parsedLat,
      lng: parsedLng,
      address: display,
    ));
  }
  return places;
}

/// Fetches Catholic churches across Northern Luzon from
/// Nominatim. Returns an empty list on any failure — the caller
/// still shows the bundled verified churches and explains why
/// the lookup failed, instead of a fake list.
Future<List<NominatimPlace>> fetchNominatimChurches() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(Uri.parse(nominatimChurchesUrl()));
    request.headers.set('User-Agent', 'EstudyanteGO/1.0');
    final response = await request.close().timeout(
      const Duration(seconds: 20),
    );
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) return const [];
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    return parseNominatimChurches(decoded);
  } catch (_) {
    return const [];
  } finally {
    client.close();
  }
}

/// Road distance in km along [pts] from index [from] to index
/// [to] (straight-line segments summed — the same rule as
/// map_tab's pathKmBetween, kept here so the stop math stays
/// testable without the widget).
double distanceAlongPath(List<LatLng> pts, int from, int to) {
  if (pts.length < 2 || from >= to) return 0;
  final a = from.clamp(0, pts.length - 1);
  final b = to.clamp(0, pts.length - 1);
  var sum = 0.0;
  for (var i = a; i < b; i++) {
    sum += haversineKm(
      pts[i].latitude,
      pts[i].longitude,
      pts[i + 1].latitude,
      pts[i + 1].longitude,
    );
  }
  return sum;
}

/// Index of the path point nearest to [pos] (straight-line
/// distance). Same rule as map_tab's nearestPointIndex.
int nearestPathIndex(List<LatLng> pts, LatLng pos) {
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < pts.length; i++) {
    final d = haversineKm(
      pos.latitude,
      pos.longitude,
      pts[i].latitude,
      pts[i].longitude,
    );
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

/// One stop on an active route: a real hub the road actually
/// passes (or the origin / destination themselves), with its
/// position on the road geometry and its distance from the
/// origin measured along that geometry — never a straight line,
/// never invented.
class RouteStop {
  const RouteStop({
    required this.name,
    required this.region,
    required this.lat,
    required this.lng,
    required this.isOrigin,
    required this.isDestination,
    required this.pathIndex,
    required this.kmFromOrigin,
  });

  /// Stop name (hub name, or 'Your location' for a GPS origin).
  final String name;

  /// Hub region (province / region string, e.g. 'Ilocos Sur').
  final String region;
  final double lat;
  final double lng;

  /// First stop (the origin).
  final bool isOrigin;

  /// Last stop (the destination).
  final bool isDestination;

  /// Index into the road geometry nearest this stop.
  final int pathIndex;

  /// Distance from the origin along the road geometry, in km.
  final double kmFromOrigin;

  /// Start / Stop / End label for the stop card.
  String get role => isOrigin
      ? 'Start'
      : isDestination
      ? 'End'
      : 'Stop';
}

/// How close a hub must sit to the road geometry to count as a
/// stop on the way (1 km). Ground truth, Cabugao → Vigan Bus
/// Terminal on the real OSRM geometry: San Juan hub sits 0.08 km
/// off the line, Vigan City 0.56 km, Sinait 9.9 km — so 1 km
/// keeps the real on-the-way towns and drops the far ones.
const routeStopMaxOffRoadKm = 1.0;

/// Stops for an active route: the origin, then every hub whose
/// coordinates sit within [routeStopMaxOffRoadKm] of the road
/// geometry (in road order), then the destination. A custom
/// route's own via-hubs are always stops, in the admin's order,
/// even if the geometry is still loading. When there is no road
/// geometry yet, only origin + destination (+ via-hubs) are
/// known — no intermediate hub is guessed from a straight line.
List<RouteStop> routeStops({
  required LatLng origin,
  required String originName,
  required Hub dest,
  required List<LatLng>? roadPoints,
  required double totalKm,
  List<String> viaHubNames = const [],
}) {
  final stops = <RouteStop>[];
  final pts = roadPoints;
  final originIdx = pts == null || pts.isEmpty
      ? 0
      : nearestPathIndex(pts, origin);
  final destIdx = pts == null || pts.isEmpty
      ? 0
      : nearestPathIndex(pts, LatLng(dest.lat, dest.lng));
  double kmFrom(int idx) => pts == null || pts.isEmpty
      ? 0
      : distanceAlongPath(pts, math.min(originIdx, idx), math.max(originIdx, idx));

  // Via-hubs of a custom route come first in the admin's order;
  // their path indices are resolved below like any hub.
  final viaHubs = <Hub>[];
  for (final name in viaHubNames) {
    for (final h in hubs) {
      if (h.name == name) viaHubs.add(h);
    }
  }

  final intermediates = <RouteStop>[];
  if (pts != null && pts.length >= 2) {
    final lo = math.min(originIdx, destIdx);
    final hi = math.max(originIdx, destIdx);
    for (final hub in hubs) {
      if (hub.name == dest.name || hub.name == originName) continue;
      if (viaHubs.any((h) => h.name == hub.name)) continue;
      final idx = nearestPathIndex(pts, LatLng(hub.lat, hub.lng));
      if (idx <= lo || idx >= hi) continue;
      final off = haversineKm(
        hub.lat,
        hub.lng,
        pts[idx].latitude,
        pts[idx].longitude,
      );
      if (off > routeStopMaxOffRoadKm) continue;
      intermediates.add(
        RouteStop(
          name: hub.name,
          region: hub.region,
          lat: hub.lat,
          lng: hub.lng,
          isOrigin: false,
          isDestination: false,
          pathIndex: idx,
          kmFromOrigin: kmFrom(idx),
        ),
      );
    }
    intermediates.sort((a, b) => a.pathIndex.compareTo(b.pathIndex));
  }
  for (final hub in viaHubs) {
    if (hub.name == dest.name || hub.name == originName) continue;
    final idx = pts == null || pts.isEmpty
        ? 0
        : nearestPathIndex(pts, LatLng(hub.lat, hub.lng));
    intermediates.add(
      RouteStop(
        name: hub.name,
        region: hub.region,
        lat: hub.lat,
        lng: hub.lng,
        isOrigin: false,
        isDestination: false,
        pathIndex: idx,
        kmFromOrigin: kmFrom(idx),
      ),
    );
  }
  // Via-hubs keep the admin's order; geometry hubs are in road
  // order. When both exist, road order wins for the combined
  // list (a via-hub off the loaded geometry still appears,
  // at its nearest point).
  intermediates.sort((a, b) => a.pathIndex.compareTo(b.pathIndex));

  stops.add(
    RouteStop(
      name: originName,
      region: _regionOf(originName),
      lat: origin.latitude,
      lng: origin.longitude,
      isOrigin: true,
      isDestination: false,
      pathIndex: originIdx,
      kmFromOrigin: 0,
    ),
  );
  stops.addAll(intermediates);
  stops.add(
    RouteStop(
      name: dest.name,
      region: dest.region,
      lat: dest.lat,
      lng: dest.lng,
      isOrigin: false,
      isDestination: true,
      pathIndex: destIdx,
      kmFromOrigin: pts == null || pts.isEmpty
          ? totalKm
          : distanceAlongPath(pts, originIdx, destIdx),
    ),
  );
  return stops;
}

String _regionOf(String originName) {
  for (final h in hubs) {
    if (h.name == originName) return h.region;
  }
  return '';
}

/// Splits a road geometry at [index] into the part before the
/// stop (origin → stop, dimmed) and the part from the stop
/// onward (stop → destination, lit). The split point belongs to
/// both parts so the line never gaps. Pure.
({List<LatLng> before, List<LatLng> after}) splitPathAt(
  List<LatLng> pts,
  int index,
) {
  final i = index.clamp(0, pts.length - 1);
  return (
    before: pts.sublist(0, i + 1),
    after: pts.sublist(i),
  );
}

/// Estimated travel time to a stop, scaled by distance from the
/// route total: (kmFromOrigin / totalKm) * totalMinutes, rounded
/// to the nearest 5 like every other ETA in the app. The caller
/// MUST label this "tinatayang (estimate)" — it is a scaled
/// estimate, never a real timetable time. Zero when inputs are
/// unusable.
int estimatedStopMinutes({
  required double kmFromOrigin,
  required double totalKm,
  required double totalMinutes,
}) {
  if (totalKm <= 0 || totalMinutes <= 0 || kmFromOrigin < 0) return 0;
  final scaled = kmFromOrigin / totalKm * totalMinutes;
  return (scaled / 5).round() * 5;
}
