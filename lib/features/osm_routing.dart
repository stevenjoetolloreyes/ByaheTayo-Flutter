// OpenStreetMap routing + lookup helpers for the Map tab.
//
// This file is the OSM side of the Map tab: OSRM road routing
// (replacing the Google Routes API), Nominatim place lookup
// (replacing Google Places where a lookup is needed), the map
// style URLs (Meta's Canterbury vector style by default, CartoDB
// raster as the theme-aware fallback — Dark Matter in dark mode,
// Positron in light mode), and the pure route-stop
// math (stops along the way, distances along the real road
// geometry, segment split).
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

import 'bus_stops.dart';
import 'fares_tab.dart';

/// Standard OSM raster tiles (light mode).
const osmStandardTileUrl =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// CartoDB Dark Matter raster tiles — the FALLBACK basemap when
/// the Meta vector style fails to load (see [metaMapStyleUrl]).
/// Same dark look as the preview's map (dark background, light
/// roads/labels), served from OpenStreetMap data, so the
/// attribution stays OSM + CARTO. The `{r}` is flutter_map's
/// retina placeholder, kept for [tileUrlTemplate]; the MapLibre
/// fallback style document ([cartoFallbackStyleJson]) uses
/// [cartoDarkRasterTileUrl] instead — MapLibre only expands
/// {z}/{x}/{y}.
const cartoDarkTileUrl =
    'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

/// CartoDB Dark Matter tiles without the `{r}` retina
/// placeholder, for the MapLibre fallback style document.
const cartoDarkRasterTileUrl =
    'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';

/// CartoDB Positron (light) tiles, for the MapLibre fallback
/// style document in light mode — the light twin of
/// [cartoDarkRasterTileUrl].
const cartoLightRasterTileUrl =
    'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';

/// CARTO attribution page, opened from the attribution chip in
/// dark mode (the tiles are CARTO's Dark Matter rendering of OSM
/// data).
const cartoAttributionUrl = 'https://carto.com/attributions';

/// OSM copyright page, opened from the attribution chip.
const osmCopyrightUrl = 'https://www.openstreetmap.org/copyright';

/// Tile URL template for the FALLBACK raster layer (dark mode
/// gets CartoDB Dark Matter, light mode standard OSM tiles).
/// Kept for the tile tests; the live map uses the Meta vector
/// styles below by default and this layer only on fallback.
/// (The old Standard/Satellite pill is gone — no satellite path.)
String tileUrlTemplate({bool dark = false}) =>
    dark ? cartoDarkTileUrl : osmStandardTileUrl;

/// Attribution line for the fallback tile layer (CARTO requires
/// the © CARTO credit alongside OSM in dark mode).
String mapAttributionText({required bool dark}) => dark
    ? '© OpenStreetMap contributors © CARTO'
    : '© OpenStreetMap contributors';

/// Attribution page for the fallback tile layer.
String mapAttributionUrl({required bool dark}) =>
    dark ? cartoAttributionUrl : osmCopyrightUrl;

/// Meta "Canterbury" vector styles — the app's DEFAULT basemap
/// (the same map the Fares Phone Preview renders), via the
/// maplibre plugin. Dark = "Canterbury Dark", light =
/// "Canterbury Light" (the /style/light/ path returns HTTP 500,
/// so canterbury_1_0 is the correct light URL). Served from
/// Meta's internal CDN with no auth and no public third-party
/// terms — reachable and rendering (verified Nov 7), but
/// availability is NOT guaranteed. If a style fails to load, the
/// map falls back to the CartoDB raster style below
/// ([cartoFallbackStyleJson]).
const metaDarkMapStyleUrl =
    'https://external.xx.fbcdn.net/maps/vt/style/dark/';
const metaLightMapStyleUrl =
    'https://external.xx.fbcdn.net/maps/vt/style/canterbury_1_0/';

/// MapLibre style URL for the current theme.
String metaMapStyleUrl({required bool dark}) =>
    dark ? metaDarkMapStyleUrl : metaLightMapStyleUrl;

/// Attribution for the Meta basemap. The Canterbury style
/// documents declare NO attribution string of their own (verified
/// Nov 7 — each has a single 'facebook' vector source with no
/// attribution field), so the credit is Meta itself, whose CDN
/// serves the map. There is no Meta attribution page to link, so
/// the chip shows this as plain text (see map_tab.dart).
const metaMapAttributionText = '© Meta';

/// MapLibre style document for the CartoDB raster fallback: a
/// single raster source + layer. If the Meta style fails to load
/// — or loads but its tiles never render (Steven's white map,
/// Nov 7) — the map switches to this document via setStyle.
/// Theme-aware: dark mode gets Dark Matter (same dark look as
/// the preview's map), light mode gets Positron (the light
/// twin), so the fallback never flips the theme. The route line
/// and pins keep working on a raster basemap either way.
String cartoFallbackStyleJson({required bool dark}) {
  final sourceId = dark ? 'carto-dark' : 'carto-light';
  final tiles = dark ? cartoDarkRasterTileUrl : cartoLightRasterTileUrl;
  final name = dark
      ? 'CartoDB Dark Matter (fallback)'
      : 'CartoDB Positron (fallback)';
  return jsonEncode({
    'version': 8,
    'name': name,
    'sources': {
      sourceId: {
        'type': 'raster',
        'tiles': [tiles],
        'tileSize': 256,
        'attribution': mapAttributionText(dark: dark),
      },
    },
    'layers': [
      {'id': sourceId, 'type': 'raster', 'source': sourceId},
    ],
  });
}

/// Meta vector tile endpoint — the same tiles the Canterbury
/// styles fetch: verified live Nov 7 (HTTP 200, protobuf).
/// The tile probe below fetches this exact URL, so a probe
/// success means the native map's own tile requests can
/// succeed too.
const metaVectorTileUrlTemplate =
    'https://external.xx.fbcdn.net/maps/vtp/s1/88/{z}/{x}/{y}/';

/// One Meta vector tile URL for slippy coordinates ([z], [x],
/// [y]). Pure, so the URL is testable.
String metaVectorTileUrl({
  required int z,
  required int x,
  required int y,
}) =>
    'https://external.xx.fbcdn.net/maps/vtp/s1/88/$z/$x/$y/';

/// Slippy-map tile coordinates covering ([lat], [lng]) at zoom
/// [z] (standard Web Mercator math). Pure, so the tile math is
/// testable. [z] is clamped to the Meta tiles' range (0–16).
({int x, int y}) metaTileXy({
  required double lat,
  required double lng,
  required int z,
}) {
  final zoom = z.clamp(0, 16);
  final n = 1 << zoom;
  final x = ((lng + 180) / 360 * n).floor().clamp(0, n - 1);
  final latRad = lat * math.pi / 180;
  final y = ((1 -
              math.log(math.tan(latRad) + 1 / math.cos(latRad)) /
                  math.pi) /
          2 *
          n)
      .floor()
      .clamp(0, n - 1);
  return (x: x, y: y);
}

/// Probes whether the Meta vector tile CDN is reachable from
/// this device right now: GETs the single vector tile covering
/// ([lat], [lng]) at zoom [z]. True on HTTP 200 with a
/// non-empty body, false on any failure or timeout (8 s —
/// inside the tile watchdog's 10 s window, so a slow-but-
/// successful probe still cancels the watchdog in time).
/// Never throws. Modelled on [fetchOsrmRoute]: one HTTP GET,
/// no invented data.
Future<bool> probeMetaVectorTile({
  required double lat,
  required double lng,
  required int z,
}) async {
  final tile = metaTileXy(lat: lat, lng: lng, z: z);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(
      Uri.parse(metaVectorTileUrl(z: z, x: tile.x, y: tile.y)),
    );
    request.headers.set('User-Agent', 'EstudyanteGO/1.0');
    final response = await request.close().timeout(
      const Duration(seconds: 8),
    );
    if (response.statusCode != 200) return false;
    final bytes = await response
        .fold<List<int>>(<int>[], (a, b) => a..addAll(b))
        .timeout(const Duration(seconds: 8));
    return bytes.isNotEmpty;
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
}

/// The one CartoDB raster tile under [z]/[x]/[y] for the
/// fallback basemap (Dark Matter in dark theme, Positron in
/// light — the same sources `cartoFallbackStyleJson` declares).
/// Pure: the fallback-tile probe uses it, and the fallback
/// style JSON must stay consistent with it.
String cartoTileUrl({
  required bool dark,
  required int z,
  required int x,
  required int y,
}) =>
    dark
        ? 'https://basemaps.cartocdn.com/dark_all/$z/$x/$y.png'
        : 'https://basemaps.cartocdn.com/light_all/$z/$x/$y.png';

/// CartoDB fallback tile-reachability probe (the symmetric
/// partner of `probeMetaVectorTile`): downloads the one
/// fallback tile under the camera and reports true when a
/// non-empty tile arrives (HTTP 200 + body). Used after the
/// CartoDB fallback style loads — a style document can load
/// while its tiles never arrive (Steven's phone on WiFi, Nov 7,
/// 20:08–20:13: Meta AND CartoDB blocked, blank map in both
/// themes). A failed probe means both tile sources are
/// unreachable. Never throws. Same 8 s timeouts as the Meta
/// probe, same caveat: it proves the tile is downloadable, not
/// that the native renderer drew it.
Future<bool> probeCartoTile({
  required double lat,
  required double lng,
  required int z,
  required bool dark,
}) async {
  final tile = metaTileXy(lat: lat, lng: lng, z: z);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(
      Uri.parse(cartoTileUrl(dark: dark, z: z, x: tile.x, y: tile.y)),
    );
    request.headers.set('User-Agent', 'EstudyanteGO/1.0');
    final response = await request.close().timeout(
      const Duration(seconds: 8),
    );
    if (response.statusCode != 200) return false;
    final bytes = await response
        .fold<List<int>>(<int>[], (a, b) => a..addAll(b))
        .timeout(const Duration(seconds: 8));
    return bytes.isNotEmpty;
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
}

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

/// OSRM route URL for a drive through raw [points] in order (2+
/// points). Pure, so the URL is testable. Same endpoint +
/// options as [osrmRouteUrl], minus the Hub wrapper — used by
/// the line maker, whose points are map taps, not hubs.
String osrmRouteUrlForPoints(List<LatLng> points) {
  String coord(LatLng p) => '${p.longitude},${p.latitude}';
  return 'https://router.project-osrm.org/route/v1/driving/'
      '${points.map(coord).join(';')}'
      '?overview=full&geometries=geojson&steps=true';
}

/// Fetches the OSRM road route through raw [points] in order.
/// Returns null on any failure — the caller keeps the dashed
/// direct line. Never throws. Modelled on [fetchOsrmRoute].
Future<OsrmRoute?> fetchOsrmRouteForPoints(List<LatLng> points) async {
  if (points.length < 2) return null;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(
      Uri.parse(osrmRouteUrlForPoints(points)),
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
    this.waypointIndex,
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

  /// Index into the route's effective drawn waypoints
  /// ([viaWaypoints]) when this stop IS one of them; null for
  /// the origin, the destination, on-the-way hubs, and named
  /// via stops. Lets the Map tab offer a rename for exactly the
  /// drawn points (Steven, Nov 7, 20:54: "Point 1" / "Point 2"
  /// must be renamable to real place names) — the index maps
  /// the stop card back to the waypoint the name is saved on.
  final int? waypointIndex;

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
/// [viaWaypoints] (a line the admin drew on the map) wins over
/// [viaHubNames] for the intermediate stops; unnamed waypoints
/// are labelled "Point N" in tap order — a positional label,
/// never an invented place name. [extraStops] are the
/// admin-added stops the names may resolve to, and which count
/// as on-the-way stops like any hub.
List<RouteStop> routeStops({
  required LatLng origin,
  required String originName,
  required Hub dest,
  required List<LatLng>? roadPoints,
  required double totalKm,
  List<String> viaHubNames = const [],
  List<RouteWaypoint> viaWaypoints = const [],
  List<BusStop> extraStops = const [],
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

  // The effective intermediates: a drawn line's waypoints win
  // over the named via stops. Unnamed waypoints are labelled
  // "Point N" in tap order — a positional label, never an
  // invented place name.
  final viaStops = <({
    String name,
    String region,
    double lat,
    double lng,
    int? waypointIndex,
  })>[];
  if (viaWaypoints.isNotEmpty) {
    for (var i = 0; i < viaWaypoints.length; i++) {
      final w = viaWaypoints[i];
      viaStops.add((
        name: w.name ?? 'Point ${i + 1}',
        region: w.name == null ? '' : _regionOf(w.name!, extraStops),
        lat: w.lat,
        lng: w.lng,
        waypointIndex: i,
      ));
    }
  } else {
    for (final name in viaHubNames) {
      final hub = resolveHub(name, extraStops);
      if (hub != null) {
        viaStops.add((
          name: hub.name,
          region: hub.region,
          lat: hub.lat,
          lng: hub.lng,
          waypointIndex: null,
        ));
      }
    }
  }

  final intermediates = <RouteStop>[];
  if (pts != null && pts.length >= 2) {
    final lo = math.min(originIdx, destIdx);
    final hi = math.max(originIdx, destIdx);
    for (final hub in allHubs(extraStops)) {
      if (hub.name == dest.name || hub.name == originName) continue;
      if (viaStops.any((s) => s.name == hub.name)) continue;
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
  for (final stop in viaStops) {
    if (stop.name == dest.name || stop.name == originName) continue;
    final idx = pts == null || pts.isEmpty
        ? 0
        : nearestPathIndex(pts, LatLng(stop.lat, stop.lng));
    intermediates.add(
      RouteStop(
        name: stop.name,
        region: stop.region,
        lat: stop.lat,
        lng: stop.lng,
        isOrigin: false,
        isDestination: false,
        pathIndex: idx,
        kmFromOrigin: kmFrom(idx),
        waypointIndex: stop.waypointIndex,
      ),
    );
  }
  // Via stops keep the admin's order; geometry hubs are in road
  // order. When both exist, road order wins for the combined
  // list (a via stop off the loaded geometry still appears,
  // at its nearest point).
  intermediates.sort((a, b) => a.pathIndex.compareTo(b.pathIndex));

  stops.add(
    RouteStop(
      name: originName,
      region: _regionOf(originName, extraStops),
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

String _regionOf(String originName, [List<BusStop> extraStops = const []]) {
  final hub = resolveHub(originName, extraStops);
  return hub?.region ?? '';
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
