// Map tab — full-screen Meta vector map + draggable bottom sheet
// (Peek / Half only, no Full). The basemap is Meta's "Canterbury"
// vector style (the same map the Fares Phone Preview renders),
// via the maplibre plugin; if that style fails to load, the map
// falls back to a CartoDB Dark Matter raster style (same dark
// look). Routing is OSRM road geometry (never a straight line)
// and place lookup is Nominatim — the Google Maps SDK, Routes API,
// and Places API are gone, because the map was blank without
// linked billing (REQUEST_DENIED).
//
// Reference-based redesign (Oct 31 spec): floating search bar, category
// chips, custom zoom + my-location controls, and a draggable sheet with
// Collapsed / Half / Full states holding route search, direction filters,
// AM/PM selection, nearby routes, and locally saved routes. Destination
// Mode adds origin/destination selection with ETA, rides, walking
// distance, and a fare estimate.
//
// Data honesty (all numbers come from real sources, never invented):
// - Hubs, fare rates, and the fare formula are imported from fares_tab.dart
//   (the LTFRB calculator) — the map never carries its own copy.
// - ETA uses the web app's estimateTripTime model (mapController.js):
//   roadKm = max(1, direct x 1.22); per-mode typical paces; same-region and
//   Cordillera (Baguio City, Bontoc, Banaue) adjustments; 5-minute rounding.
// - Known user-verified bus fares are the web app's knownBusFares table.
// - Live Tracking follows the USER's own location (position stream).
//   There is no vehicle fleet feed, so no live vehicle positions are shown.
// - AM/PM selection is present, but there is no verified timetable dataset
//   yet, so it cannot filter departures — the sheet says so plainly.
// - Malls / Schools / Hospitals chips have no verified POI dataset
//   yet, so they answer with an honest note instead of fake places.
// - Churches loads REAL Catholic churches across Northern Luzon
//   from Nominatim (bounded to Northern Luzon) — markers + a list
//   sheet — on top of the verified churches bundled in the app.
//   Nominatim has no photos, so church photos stay empty.
// - Search covers the 16 hubs only (the web app's barangay search is not
//   ported to Flutter).
// - Road path shape comes from OSRM (DRIVE mode, road routing);
//   only the two endpoint coordinates are sent, plus the Avenida
//   Quezon via-point when the destination is the Vigan Bus
//   Terminal. The dashed direct line is the fallback when OSRM is
//   unreachable.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' hide Marker;
import 'package:maplibre/maplibre.dart' hide Position;
import 'package:url_launcher/url_launcher.dart';

import 'community_posts.dart';
import 'custom_routes.dart';
import 'fares_tab.dart';
import 'onboarding/auth_service.dart';
import 'osm_routing.dart';

/// Map tab's OWN ChatGPT tokens (loose UI base, Nov 5): Premium Dark +
/// Emerald Green with a matching Light Mode. Only the chrome around
/// the map is retokened — the map tiles, markers, polylines, the
/// draggable sheet's layout and the Google-style nav banner layout
/// stay exactly as approved. The map is the approved reference, so
/// the retoken is deliberately light: hardcoded off-system colors
/// move to these tokens, nothing else changes shape or behavior.
const kMapPrimary = Color(0xFF14532D);
const kMapDarkCard = Color(0xFF202B25);
const kMapLightText = Color(0xFF17231C);
const kMapError = Color(0xFFEF4444);
const kMapInfo = Color(0xFF3B82F6);
const kMapSuccess = Color(0xFF22C55E);
const kMapCardRadius = 20.0;

/// Top offset of the floating stop card (Steven, Nov 7: the card
/// floats over the map in the upper area, not docked at the
/// bottom). It sits just below the top-right control cluster —
/// five 48px buttons + four 10px gaps starting at top:16, so the
/// cluster ends at 16 + 5 * 48 + 4 * 10 = 296; the card starts
/// 16dp below that, clear of the buttons and of the peeked sheet
/// below. Same card, same content — only the position changed.
const kMapStopCardTop = 312.0;

/// Travel modes for the destination ETA, mirroring the web planner.
enum TravelMode { transit, motorcycle, bicycle, walking }

/// Icon per travel mode, shared by the destination panel and the
/// route-preview mode tabs.
IconData modeIcon(TravelMode mode) => switch (mode) {
  TravelMode.transit => Icons.directions_bus,
  TravelMode.motorcycle => Icons.two_wheeler,
  TravelMode.bicycle => Icons.directions_bike,
  TravelMode.walking => Icons.directions_walk,
};

/// Sheet vehicle selection (reference "Select Vehicle Type"). ONE state
/// on the Map tab drives the selector cards, the user cursor icon, and
/// route filtering — never separate states.
enum VehicleType { bus, car, train, motorcycle, anyVehicle }

String vehicleLabel(VehicleType v) => switch (v) {
  VehicleType.bus => 'Bus',
  VehicleType.car => 'Car',
  VehicleType.train => 'Train',
  VehicleType.motorcycle => 'Motorcycle',
  VehicleType.anyVehicle => 'Any Vehicle',
};

IconData vehicleIcon(VehicleType v) => switch (v) {
  VehicleType.bus => Icons.directions_bus,
  VehicleType.car => Icons.directions_car,
  VehicleType.train => Icons.train,
  VehicleType.motorcycle => Icons.two_wheeler,
  VehicleType.anyVehicle => Icons.place,
};

/// Honest vehicle filtering over the app's own hub routes: Bus, Car,
/// Motorcycle, and Any Vehicle all run on the same road network, so
/// they see every route; Train sees none — there is no passenger
/// train service on these Northern Luzon routes, so inventing train
/// routes would be fabrication. Callers show the empty state for [].
List<RouteInfo> filterRoutesByVehicle(List<RouteInfo> routes, VehicleType v) {
  if (v == VehicleType.train) return const [];
  return routes;
}

extension TravelModeLabel on TravelMode {
  String get label {
    switch (this) {
      case TravelMode.transit:
        return 'Public transport';
      case TravelMode.motorcycle:
        return 'Motorcycle';
      case TravelMode.bicycle:
        return 'Bicycle';
      case TravelMode.walking:
        return 'Walking';
    }
  }
}

/// Road distance in km: straight-line x 1.22 (same rule as the Fares tab).
double roadKmBetween(double lat1, double lng1, double lat2, double lng2) {
  return math.max(0.1, haversineKm(lat1, lng1, lat2, lng2) * 1.22);
}

/// Cordillera hubs, per the web app's places list (shared.js group field).
bool isMountainHub(Hub hub) {
  return const {'Baguio City', 'Bontoc', 'Banaue'}.contains(hub.name);
}

/// Web formatTripTime: "45 min" / "1 hr 10 min".
String formatTripTime(int minutes) {
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return '$mins min';
  if (mins == 0) return '$hours hr';
  return '$hours hr $mins min';
}

/// Spanish trip-planner "Llegada" style: clock time of arrival, computed
/// from now + ETA minutes. Real arithmetic on the app's own ETA — the
/// time is approximate because the ETA itself is approximate.
String estimatedArrivalText(DateTime now, int minutes) {
  final arrival = now.add(Duration(minutes: minutes));
  final hour12 = arrival.hour % 12 == 0 ? 12 : arrival.hour % 12;
  final period = arrival.hour < 12 ? 'AM' : 'PM';
  return '$hour12:${arrival.minute.toString().padLeft(2, '0')} $period';
}

/// Web estimateTripTime, exactly: per-mode pace, same-region and mountain
/// adjustments, waiting allowance, 5-minute rounding, per-mode minimum.
int estimateTripMinutes({
  required double roadKm,
  required bool mountain,
  required bool sameRegion,
  required TravelMode mode,
}) {
  double kph;
  int allowance;
  switch (mode) {
    case TravelMode.walking:
      kph = mountain ? 3.5 : 4.5;
      allowance = 0;
    case TravelMode.bicycle:
      kph = mountain ? 9 : 14;
      allowance = 5;
    case TravelMode.motorcycle:
      kph = mountain ? 25 : (sameRegion ? 35 : 45);
      allowance = 5;
    case TravelMode.transit:
      kph = mountain ? 28 : (sameRegion ? 32 : 40);
      allowance = sameRegion ? 10 : 20;
  }
  final minimum = mode == TravelMode.walking || mode == TravelMode.bicycle
      ? 10
      : 15;
  final raw = (roadKm / kph) * 60 + allowance;
  return math.max(minimum, (raw / 5).round() * 5);
}

/// Northbound = destination is further north than the origin.
enum Direction { northbound, southbound }

Direction directionOf(double originLat, double destLat) {
  return destLat >= originLat ? Direction.northbound : Direction.southbound;
}

/// One hub-to-hub route from an origin point, sorted nearest-first by
/// [routesFrom].
class RouteInfo {
  const RouteInfo({
    required this.originName,
    required this.dest,
    required this.roadKm,
    required this.direction,
    this.customRoute,
  });

  final String originName;
  final Hub dest;
  final double roadKm;
  final Direction direction;

  /// Set only for admin-added routes (see custom_routes.dart): the
  /// card shows this route's own operator/fare, and the map draws
  /// its own via-stops line instead of the generic hub line. Null
  /// for every generated hub-to-hub route.
  final CustomRoute? customRoute;
}

/// All hubs reachable from [lat]/[lng], nearest first. A hub closer than
/// 0.5 km to the origin is the origin itself, so it is skipped.
List<RouteInfo> routesFrom(double lat, double lng, String originName) {
  final list = <RouteInfo>[];
  for (final hub in hubs) {
    final direct = haversineKm(lat, lng, hub.lat, hub.lng);
    if (direct < 0.5) continue;
    list.add(
      RouteInfo(
        originName: originName,
        dest: hub,
        roadKm: roadKmBetween(lat, lng, hub.lat, hub.lng),
        direction: directionOf(lat, hub.lat),
      ),
    );
  }
  list.sort((a, b) => a.roadKm.compareTo(b.roadKm));
  return list;
}

/// Groups routes by direction, northbound first (picture-1 sheet style).
Map<Direction, List<RouteInfo>> groupRoutesByDirection(List<RouteInfo> routes) {
  return {
    Direction.northbound: routes
        .where((r) => r.direction == Direction.northbound)
        .toList(),
    Direction.southbound: routes
        .where((r) => r.direction == Direction.southbound)
        .toList(),
  };
}

/// Filters routes by destination name or region (in-sheet search).
List<RouteInfo> filterRoutesByQuery(List<RouteInfo> routes, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return routes;
  return routes
      .where(
        (r) =>
            r.dest.name.toLowerCase().contains(q) ||
            r.dest.region.toLowerCase().contains(q),
      )
      .toList();
}

/// Via waypoint forcing the Google road shape into Vigan through
/// Avenida Quezon when the destination is the Vigan Bus Terminal.
/// Verified Nov 6, 2026 against the real OSRM road path for
/// Cabugao → terminal (Route 2 → Govantes Dike Road → Avenida
/// Quezon → Liberation Boulevard → Jose Singson Street): this point
/// is the start of the Avenida Quezon leg. Without it Google may
/// route the final leg via Quirino Boulevard instead. Only the
/// terminal destination gets a waypoint — leaving the terminal
/// northbound, the road path is Calle Rivero → Calle Rizal →
/// Route 2, so no waypoint is added there.
const LatLng _quezonAveViaPoint = LatLng(17.576831, 120.387462);

/// Via waypoints for a Routes API request to [dest]: the Quezon Ave
/// point when the destination is the Vigan Bus Terminal, none
/// otherwise.
List<LatLng> viaWaypointsForDestination(Hub dest) =>
    dest.name == 'Vigan Bus Terminal'
        ? const [_quezonAveViaPoint]
        : const [];

/// Decodes a Google encoded polyline into map points. Standard
/// algorithm (5-bit chunks, zigzag deltas, 1e5 scale). Anything
/// unusable yields an empty list.
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  try {
    var index = 0;
    var lat = 0;
    var lng = 0;
    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dLat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dLng;
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
  } catch (_) {
    return const [];
  }
  return points.length >= 2 ? points : const [];
}

/// Map style for Churches mode: the base style (dark tiles or
/// Google default) plus a rule hiding every other base-map POI, so
/// the map shows only churches. Pure (unit-tested). An unparseable
/// base is returned unchanged rather than breaking the map.
String? churchesOnlyStyle(String? baseStyle) {
  const poiOff = {
    'featureType': 'poi',
    'stylers': [
      {'visibility': 'off'},
    ],
  };
  if (baseStyle == null) return jsonEncode([poiOff]);
  try {
    final list = (jsonDecode(baseStyle) as List).toList()..add(poiOff);
    return jsonEncode(list);
  } catch (_) {
    return baseStyle;
  }
}

/// A Catholic church returned by Google Places (New) Text Search.
/// Only the fields the sheet shows; nothing is invented — every
/// entry comes from the API response. [photoName] is the Places
/// photo resource name (places/.../photos/...) when the API
/// returned one; null for every verified church and for Places
/// entries without photo data — never a guessed picture.
class ChurchPlace {
  const ChurchPlace({
    required this.name,
    required this.lat,
    required this.lng,
    this.address = '',
    this.photoName,
  });

  final String name;
  final double lat;
  final double lng;
  final String address;
  final String? photoName;
}

/// Photo URL for a church's Places photo, or null when there is no
/// photo to show (no photo data, or no API key in this build).
/// Built from the same --dart-define=MAPS_API_KEY route the Routes
/// and Places calls use. Pure (unit-tested). The media endpoint
/// takes the key as a query parameter; if the key rejects the
/// request, the photo slot's errorBuilder falls back to the honest
/// empty state instead of breaking the panel.
String? churchPhotoUrl(ChurchPlace church, String apiKey) {
  final photo = church.photoName;
  if (photo == null || photo.isEmpty) return null;
  if (apiKey.isEmpty) return null;
  return 'https://places.googleapis.com/v1/$photo/media'
      '?maxWidthPx=800&key=$apiKey';
}

/// Source filter for the churches sheet. Pure (unit-tested) with
/// [visibleChurches] below.
enum ChurchSourceFilter { all, verified, places }

/// Applies the churches sheet's search + source filter to both
/// lists. Search matches the church name only (case-insensitive,
/// substring); the source filter picks which list survives. Both
/// apply together. Pure (unit-tested).
({List<ChurchPlace> verified, List<ChurchPlace> places}) visibleChurches({
  required List<ChurchPlace> verified,
  required List<ChurchPlace> places,
  required String query,
  required ChurchSourceFilter filter,
}) {
  final q = query.trim().toLowerCase();
  bool matches(ChurchPlace c) => q.isEmpty || c.name.toLowerCase().contains(q);
  return (
    verified: filter == ChurchSourceFilter.places
        ? const <ChurchPlace>[]
        : verified.where(matches).toList(),
    places: filter == ChurchSourceFilter.verified
        ? const <ChurchPlace>[]
        : places.where(matches).toList(),
  );
}

/// One marker group from grid clustering: a single church, or
/// several churches close together at the current zoom, shown as
/// one marker with a count. [lat]/[lng] is the centroid.
class ChurchCluster {
  const ChurchCluster({
    required this.churches,
    required this.lat,
    required this.lng,
  });

  final List<ChurchPlace> churches;
  final double lat;
  final double lng;

  bool get isSingle => churches.length == 1;
  int get count => churches.length;
}

/// Groups churches into grid clusters for the current zoom, so
/// close markers collapse into one count marker at low zoom and
/// split apart as the user zooms in. Pure (unit-tested),
/// dependency-free: the grid cell is ~60 screen pixels wide
/// (256 * 2^zoom pixels span 360 degrees of longitude), so the
/// grouping tracks what the user actually sees. Latitude uses the
/// same cell size — a small approximation at Northern Luzon
/// latitudes, fine for grouping markers.
List<ChurchCluster> clusterChurches(List<ChurchPlace> churches, double zoom) {
  if (churches.isEmpty) return const [];
  final cell = 84.375 / math.pow(2, zoom);
  final cells = <String, List<ChurchPlace>>{};
  for (final church in churches) {
    final key = '${(church.lat / cell).floor()}:${(church.lng / cell).floor()}';
    (cells[key] ??= []).add(church);
  }
  return cells.values.map((group) {
    var lat = 0.0;
    var lng = 0.0;
    for (final church in group) {
      lat += church.lat;
      lng += church.lng;
    }
    return ChurchCluster(
      churches: group,
      lat: lat / group.length,
      lng: lng / group.length,
    );
  }).toList();
}

/// Photo slot for the church details panel. Shows the real Places
/// photo when the entry carries photo data and the build has an
/// API key; anything else — every verified church, every Places
/// entry without photos, a failed load — shows the plain honest
/// empty state, never a placeholder picture. Standalone so it stays
/// widget-testable without the map.
class ChurchPhotoSlot extends StatelessWidget {
  const ChurchPhotoSlot({
    super.key,
    required this.church,
    required this.apiKey,
  });

  final ChurchPlace church;
  final String apiKey;

  @override
  Widget build(BuildContext context) {
    final url = churchPhotoUrl(church, apiKey);
    if (url == null) return const _ChurchPhotoEmpty();
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: Image.network(
        url,
        height: 180,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _ChurchPhotoEmpty(),
      ),
    );
  }
}

class _ChurchPhotoEmpty extends StatelessWidget {
  const _ChurchPhotoEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_outlined),
            SizedBox(height: 8),
            Text('No photo available'),
          ],
        ),
      ),
    );
  }
}

/// Verified Catholic churches bundled in the app (source-checked,
/// never guessed). Shown whenever the Churches chip is active, even
/// if Google Places is unavailable. Each entry's Catholic identity
/// comes from a published parish source (Wikipedia parish list,
/// parish directory, or diocese page) and its coordinates from a
/// FULL_ADDRESS geocode match in the right town. Geocode mismatches
/// (wrong province, a school, a street) were REJECTED, not bundled:
/// Sinait, Santa Cruz (Ilocos Sur), Tagudin, Bacarra, and the first
/// Laoag attempt all failed that check and stay out until a correct
/// source is found. Grow this list the same way only.
const verifiedChurches = [
  // St. Mark the Evangelist Parish, Cabugao, Ilocos Sur
  // (Archdiocese of Nueva Segovia). Coordinates from Mapcarta /
  // OpenStreetMap (17.79479, 120.45627), denomination Roman
  // Catholic, near Rizal Park, Cabugao.
  ChurchPlace(
    name: 'St. Mark the Evangelist Parish',
    lat: 17.79479,
    lng: 120.45627,
    address: 'Cabugao, Ilocos Sur',
  ),
  // Vigan Cathedral (Conversion of St. Paul), Calle Burgos, Vigan.
  ChurchPlace(
    name: 'St. Paul Metropolitan Cathedral',
    lat: 17.57467,
    lng: 120.3889,
    address: 'Vigan City, Ilocos Sur',
  ),
  // Bantay Church (Our Lady of Charity / St. Augustine), Real St.
  ChurchPlace(
    name: 'St. Augustine Parish Church',
    lat: 17.58109,
    lng: 120.39111,
    address: 'Bantay, Ilocos Sur',
  ),
  // Santa Maria Church (Our Lady of the Assumption), Poblacion Sur.
  ChurchPlace(
    name: 'Santa Maria Church',
    lat: 17.36684,
    lng: 120.4828,
    address: 'Santa Maria, Ilocos Sur',
  ),
  // St. John of Sahagun Parish, Marina St, Candon.
  ChurchPlace(
    name: 'St. John of Sahagun Parish',
    lat: 17.19313,
    lng: 120.44987,
    address: 'Candon City, Ilocos Sur',
  ),
  // St. William the Hermit, Rizal St, Magsingal.
  ChurchPlace(
    name: 'St. William the Hermit Church',
    lat: 17.6845,
    lng: 120.42617,
    address: 'Magsingal, Ilocos Sur',
  ),
  // St. James the Greater, Poblacion Norte, Santiago.
  ChurchPlace(
    name: 'St. James the Greater Parish',
    lat: 17.2934,
    lng: 120.44644,
    address: 'Santiago, Ilocos Sur',
  ),
  // Santa Lucia Parish Church, Ayusan, Santa Lucia.
  ChurchPlace(
    name: 'Santa Lucia Parish Church',
    lat: 17.11638,
    lng: 120.44781,
    address: 'Santa Lucia, Ilocos Sur',
  ),
  // St. Stephen Protomartyr, Maharlika Hwy, San Esteban.
  ChurchPlace(
    name: 'St. Stephen Protomartyr Parish',
    lat: 17.32995,
    lng: 120.44514,
    address: 'San Esteban, Ilocos Sur',
  ),
  // St. Vincent Ferrer, Poblacion, San Vicente.
  ChurchPlace(
    name: 'St. Vincent Ferrer Parish',
    lat: 17.59454,
    lng: 120.37436,
    address: 'San Vicente, Ilocos Sur',
  ),
  // St. Dominic of Guzman, Nalasin, Santo Domingo.
  ChurchPlace(
    name: 'St. Dominic of Guzman Parish',
    lat: 17.63768,
    lng: 120.41034,
    address: 'Santo Domingo, Ilocos Sur',
  ),
  // Santa Catalina Parish Church, Poblacion, Santa Catalina.
  ChurchPlace(
    name: 'Santa Catalina Parish Church',
    lat: 17.58922,
    lng: 120.36279,
    address: 'Santa Catalina, Ilocos Sur',
  ),
  // San Ildefonso Parish Church, Poblacion East, San Ildefonso.
  ChurchPlace(
    name: 'San Ildefonso Parish Church',
    lat: 17.62377,
    lng: 120.39488,
    address: 'San Ildefonso, Ilocos Sur',
  ),
  // San Isidro Parish (St. Isidore the Farmer), San Juan.
  ChurchPlace(
    name: 'San Isidro Parish',
    lat: 17.71992,
    lng: 120.42273,
    address: 'San Juan, Ilocos Sur',
  ),
  // St. William Cathedral (Diocese of Laoag), F. R. Castro St.
  ChurchPlace(
    name: 'St. William Cathedral',
    lat: 18.19457,
    lng: 120.59334,
    address: 'Laoag City, Ilocos Norte',
  ),
  // Paoay Church (St. Augustine), MC Arthur St, Paoay.
  ChurchPlace(
    name: 'Paoay Church',
    lat: 18.062,
    lng: 120.52039,
    address: 'Paoay, Ilocos Norte',
  ),
  // Santa Monica Parish Church, Molina, Sarrat.
  ChurchPlace(
    name: 'Santa Monica Parish Church',
    lat: 18.15574,
    lng: 120.64526,
    address: 'Sarrat, Ilocos Norte',
  ),
  // Immaculate Conception Parish, Taft St, Batac.
  ChurchPlace(
    name: 'Immaculate Conception Parish',
    lat: 18.06664,
    lng: 120.56133,
    address: 'Batac, Ilocos Norte',
  ),
];

/// whole Northern Luzon, Catholic only). The rectangle is a hard
/// locationRestriction — churches outside it cannot leak in.
const double _nLuzonSouth = 16.0;
const double _nLuzonWest = 119.8;
const double _nLuzonNorth = 20.6;
const double _nLuzonEast = 122.4;

/// Request body for the Churches chip: Google Places (New) Text
/// Search for Catholic churches, restricted to Northern Luzon.
/// Pure (unit-tested) so the query never drifts from the promise:
/// Catholic only, Northern Luzon. pageToken pages through results
/// (20 per page, up to 3 pages = 60 max per search — the API cap).
Map<String, dynamic> placesChurchesBody({String? pageToken}) {
  return {
    'textQuery': 'Catholic church',
    'includedType': 'church',
    'regionCode': 'PH',
    'pageSize': 20,
    'locationRestriction': {
      'rectangle': {
        'low': {'latitude': _nLuzonSouth, 'longitude': _nLuzonWest},
        'high': {'latitude': _nLuzonNorth, 'longitude': _nLuzonEast},
      },
    },
    if (pageToken != null) 'pageToken': pageToken,
  };
}

/// Next-page token from a Places searchText response, or null when
/// there are no more pages. Pure (unit-tested).
String? placesNextPageToken(Map<String, dynamic> json) {
  final token = json['nextPageToken'];
  return token is String && token.isNotEmpty ? token : null;
}

/// The church as a route destination: a synthetic Hub carrying the
/// church's name + coordinates. Pure (unit-tested).
Hub churchDestinationHub(ChurchPlace church) =>
    Hub(church.name, church.address, church.lat, church.lng);

/// Whether the Nearby Routes browsing chrome (stops row, direction
/// chips, AM/PM row, direction-grouped stops list) shows in the
/// bottom sheet. It hides only while a church-originated route
/// preview is open; every other sheet state keeps the full browsing
/// UI. Pure (unit-tested); the sheet gates on this helper.
bool showBrowsingChrome(bool churchPreview) => !churchPreview;

/// Normalizes a church name for duplicate detection: lowercase,
/// Saint -> St, common words dropped as whole words only (so
/// "Matthew" never loses its "the").
String _normalizeChurchName(String name) {
  const drop = {
    'church',
    'parish',
    'cathedral',
    'basilica',
    'shrine',
    'the',
    'of',
  };
  final words = name
      .toLowerCase()
      .replaceAll('saint', 'st')
      .split(RegExp(r'[^a-z0-9]+'));
  return words.where((w) => w.isNotEmpty && !drop.contains(w)).join();
}

/// Drops Places results that duplicate a verified church (same
/// church, different listing). Name-based: an exact normalized
/// match, or one name containing the other. Pure (unit-tested).
List<ChurchPlace> dedupePlacesChurches(
  List<ChurchPlace> places,
  List<ChurchPlace> verified,
) {
  final verifiedNames = verified
      .map((c) => _normalizeChurchName(c.name))
      .toSet();
  return places.where((p) {
    final n = _normalizeChurchName(p.name);
    if (n.isEmpty) return true;
    return !verifiedNames.any(
      (v) =>
          v.isNotEmpty &&
          (v == n ||
              (n.length >= 8 && v.contains(n)) ||
              (v.length >= 8 && n.contains(v))),
    );
  }).toList();
}

/// Parses a Places (New) searchText response into church places.
/// Entries without a usable name + coordinates are skipped, never
/// guessed.
List<ChurchPlace> parsePlacesChurches(Map<String, dynamic> json) {
  final places = json['places'];
  if (places is! List) return const [];
  final out = <ChurchPlace>[];
  for (final p in places) {
    if (p is! Map) continue;
    final name = p['displayName'] is Map
        ? (p['displayName'] as Map)['text']
        : null;
    final loc = p['location'] is Map ? p['location'] as Map : null;
    final lat = loc?['latitude'];
    final lng = loc?['longitude'];
    if (name is! String || name.isEmpty) continue;
    if (lat is! num || lng is! num) continue;
    final address = p['formattedAddress'];
    // First photo only (the details panel has one slot). No
    // photos field, or an unusable entry, means no photo — never
    // a substitute picture.
    String? photoName;
    final photos = p['photos'];
    if (photos is List && photos.isNotEmpty) {
      final first = photos.first;
      if (first is Map && first['name'] is String) {
        photoName = first['name'] as String;
      }
    }
    out.add(
      ChurchPlace(
        name: name,
        lat: lat.toDouble(),
        lng: lng.toDouble(),
        address: address is String ? address : '',
        photoName: photoName,
      ),
    );
  }
  return out;
}

/// Parses a Google Routes API computeRoutes response into turn steps.
/// Instructions come verbatim from the API (they already name the
/// road); anything unusable yields an empty list.
List<NavStep> parseGoogleSteps(Map<String, dynamic> json) {
  try {
    final routes = json['routes'];
    if (routes is! List || routes.isEmpty) return const [];
    final legs = routes.first['legs'];
    if (legs is! List || legs.isEmpty) return const [];
    final steps = legs.first['steps'];
    if (steps is! List) return const [];
    final out = <NavStep>[];
    for (final s in steps) {
      if (s is! Map) continue;
      final start = s['startLocation'];
      final latLng = start is Map ? start['latLng'] : null;
      if (latLng is! Map) continue;
      final lat = (latLng['latitude'] as num?)?.toDouble();
      final lng = (latLng['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final nav = s['navigationInstruction'];
      final instruction = nav is Map && nav['instructions'] is String
          ? nav['instructions'] as String
          : 'Continue';
      out.add(
        NavStep(
          instruction: instruction,
          location: LatLng(lat, lng),
          distanceMeters: (s['distanceMeters'] as num?)?.toDouble() ?? 0,
        ),
      );
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Arrow icon for a turn instruction, derived from the instruction's
/// own words (never invented): left / right / U-turn / roundabout /
/// straight ahead.
IconData navArrowIcon(String instruction) {
  final text = instruction.toLowerCase();
  if (text.contains('u-turn') || text.contains('u turn')) {
    return Icons.u_turn_left;
  }
  if (text.contains('roundabout') || text.contains('rotary')) {
    return Icons.rotate_right;
  }
  if (text.contains('left')) return Icons.turn_left;
  if (text.contains('right')) return Icons.turn_right;
  return Icons.arrow_upward;
}

/// Short action phrase for the navigator banner, e.g. "Turn left",
/// "Head south", "Make a U-turn" — cut from the instruction itself.
String shortAction(String instruction) {
  final text = instruction.toLowerCase();
  if (text.contains('u-turn') || text.contains('u turn')) {
    return 'Make a U-turn';
  }
  if (text.contains('roundabout') || text.contains('rotary')) {
    return 'At the roundabout';
  }
  if (text.contains('arrive')) return 'Arrive';
  if (text.contains('left')) return 'Turn left';
  if (text.contains('right')) return 'Turn right';
  if (text.startsWith('head ')) {
    final parts = instruction.split(' ');
    if (parts.length >= 2) return 'Head ${parts[1]}';
    return 'Head on';
  }
  return 'Continue';
}

/// Google-style distance: meters below 1 km, one decimal above.
String formatNavDistance(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(1)} km';
}

/// Google Routes duration is a string like "1136s" (or a number).
/// Anything unusable yields 0 — the caller then hides the time.
double parseGoogleDuration(Object? value) {
  try {
    if (value is num) return value.toDouble();
    if (value is String) {
      final trimmed = value.trim();
      final numeric = trimmed.endsWith('s')
          ? trimmed.substring(0, trimmed.length - 1)
          : trimmed;
      return double.parse(numeric);
    }
  } catch (_) {}
  return 0;
}

/// Remaining minutes from the fraction of the route left, rounded to
/// the nearest 5 like a navigator estimate. Zero when inputs are
/// unusable — the caller then hides the time.
int remainingMinutes({
  required double remainingKm,
  required double fullKm,
  required double durationSec,
}) {
  if (fullKm <= 0 || durationSec <= 0 || remainingKm < 0) return 0;
  final minutes = remainingKm / fullKm * durationSec / 60;
  return (minutes / 5).round() * 5;
}

/// Whether navigation should re-calculate the route: the user is
/// more than 200 m from the nearest route point (or the road shape
/// never loaded), and the last re-route was at least 30 seconds ago.
/// Throttling keeps a drifting GPS from spamming the API.
/// Snaps a raw GPS fix to the nearest route point when it is within
/// 50 m (map matching lite): raw GPS can sit metres off the road,
/// which looks like the car driving through buildings. Farther away
/// the raw fix is kept, so a genuinely off-route position is never
/// hidden, and the re-route logic still sees it.
LatLng snapToRoute(LatLng raw, List<LatLng>? pts, {double maxKm = 0.05}) {
  if (pts == null || pts.isEmpty) return raw;
  final idx = nearestPointIndex(pts, raw);
  final d = haversineKm(
    raw.latitude,
    raw.longitude,
    pts[idx].latitude,
    pts[idx].longitude,
  );
  return d <= maxKm ? pts[idx] : raw;
}

/// Whether a user-origin preview route should refresh: the user
/// moved more than 100 m from the preview origin and the last
/// refresh was at least 15 seconds ago. The camera is never yanked
/// by a refresh (Live Tracking's own follow already moves it).
bool shouldRefreshPreview({
  required double movedKm,
  required DateTime? lastRefreshAt,
  required DateTime now,
}) {
  if (movedKm <= 0.1) return false;
  if (lastRefreshAt == null) return true;
  return now.difference(lastRefreshAt).inSeconds >= 15;
}

bool needsReroute({
  required double offRouteKm,
  required DateTime? lastRerouteAt,
  required DateTime now,
}) {
  if (offRouteKm <= 0.2) return false;
  if (lastRerouteAt == null) return true;
  return now.difference(lastRerouteAt).inSeconds >= 30;
}

/// Routes API routeModifiers object for the avoid toggles.
Map<String, Object> routeModifiersJson({
  required bool avoidHighways,
  required bool avoidTolls,
  required bool avoidFerries,
}) {
  return {
    'avoidHighways': avoidHighways,
    'avoidTolls': avoidTolls,
    'avoidFerries': avoidFerries,
  };
}

/// Navigation line points: during navigation the line must start at
/// the user's CURRENT position, not at the position where the route
/// was first tapped. With road points, trim to the nearest point
/// onward and prepend the user position; without them, fall back to
/// the direct user -> destination line.
List<LatLng> navLinePoints({
  required LatLng user,
  required List<LatLng>? roadPoints,
  required LatLng dest,
}) {
  if (roadPoints != null) {
    final idx = nearestPointIndex(roadPoints, user);
    return [user, ...roadPoints.sublist(idx)];
  }
  return [user, dest];
}

/// One turn-by-turn step from a route leg.
class NavStep {
  const NavStep({
    required this.instruction,
    required this.location,
    required this.distanceMeters,
  });

  final String instruction;
  final LatLng location;
  final double distanceMeters;
}

/// Index of the path point nearest to [pos] (straight-line distance).
int nearestPointIndex(List<LatLng> pts, LatLng pos) {
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

/// Road distance in km along [pts] from index [from] to index [to].
double pathKmBetween(List<LatLng> pts, int from, int to) {
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

/// User-verified bus fares from the web planner (reported Oct 16, 2026).
/// A verified fare WINS for its origin|destination pair: the preview
/// shows it instead of the formula fare (the destination panel still
/// notes it as user-verified).
const knownBusFares = <String, int>{
  'Cabugao|Vigan City': 60,
  'Vigan City|Cabugao': 60,
  // Same verified Cabugao ↔ Vigan bus trip, with its real Vigan
  // endpoint: the Vigan Bus Terminal (Jose Singson / Rivero).
  // NOT a new fare — the ₱60 Steven verified Oct 16, 2026 for
  // Cabugao ↔ Vigan, applied to the terminal hub as well.
  'Cabugao|Vigan Bus Terminal': 60,
  'Vigan Bus Terminal|Cabugao': 60,
  'Cabugao|San Juan, Ilocos Sur': 20,
  'San Juan, Ilocos Sur|Cabugao': 20,
  'Sinait|Cabugao': 20,
  'Cabugao|Sinait': 20,
  // Deliberately ABSENT: Vigan Bus Terminal ↔ San Juan (₱45 sample)
  // and Laoag Terminal ↔ Vigan Bus Terminal (₱120 sample) are
  // unverified samples only, so they are NOT in this table. Those
  // pairs fall through to the LTFRB formula fare like every other
  // unverified pair — never a sample presented as verified.
};

/// User-verified fare for an origin|destination pair, or null.
int? knownBusFare(String from, String to) => knownBusFares['$from|$to'];

/// Vehicle-aware preview rate: bus and any-vehicle previews use the
/// provincial bus rate (prov-aircon — the generic provincial class;
/// deluxe/super/luxury are classes, not the generic category). Car,
/// motorcycle, and train previews have no table rate, so callers show
/// 'No fare' instead of an invented number. This mirrors
/// VehicleCategory.provincialBus.rateId, kept local here because this
/// file's own vehicleLabel/vehicleIcon(VehicleType) helpers would clash
/// with the same-named String helpers in vehicle_categories.dart.
FareRate? previewRateForVehicle(VehicleType vehicle) {
  switch (vehicle) {
    case VehicleType.bus:
    case VehicleType.anyVehicle:
      for (final rate in fareRates) {
        if (rate.id == 'prov-aircon') return rate;
      }
      return null;
    case VehicleType.car:
    case VehicleType.motorcycle:
    case VehicleType.train:
      return null;
  }
}

/// The transit fare to display for a preview route: a user-verified
/// fare wins when the pair is present; otherwise the vehicle-aware
/// formula fare; null when the vehicle has no rate (caller shows
/// 'No fare'). This replaces the old behavior where every preview
/// used the traditional-jeepney rate — e.g. Cabugao → Tuguegarao
/// 168.7 km showed ₱344 — even for bus travel.
double? resolveTransitFare({
  required String from,
  required String to,
  required VehicleType vehicle,
  required double roadKm,
}) {
  final verified = knownBusFare(from, to);
  if (verified != null) return verified.toDouble();
  final rate = previewRateForVehicle(vehicle);
  if (rate == null) return null;
  return computeFare(rate, roadKm, false).regular;
}

/// Preview label for a route card, following the vehicle selection.
String previewModeLabel(VehicleType vehicle) => switch (vehicle) {
  VehicleType.car => 'Car route',
  VehicleType.motorcycle => 'Motorcycle route',
  VehicleType.bus => 'Provincial bus',
  VehicleType.train => 'Train route',
  VehicleType.anyVehicle => 'Transit route',
};

/// Dark Google Maps tile style, matching the approved iPhone preview
/// (charcoal map, muted roads, light labels) and the app's dark theme
/// (#17191D background, #1E2126 surfaces, #33373E borders). The map
/// widget itself had no style before this, so even in dark theme the
/// tiles stayed light — the one piece of the preview the real map
/// was missing. Light theme returns null, i.e. Google's default map.
const String _darkMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#1e2126"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#b0b7c3"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#1e2126"}]},
  {"featureType": "administrative", "elementType": "geometry", "stylers": [{"color": "#1e2126"}]},
  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#1e2126"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#1f2a22"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#33373e"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#1e2126"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#3a3f47"}]},
  {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#1e2126"}]},
  {"featureType": "transit", "elementType": "geometry", "stylers": [{"color": "#2a2e34"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#121417"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#6b7280"}]}
]
''';

/// Map tile style for a theme brightness: dark style in dark mode,
/// null (Google default) in light mode.
String? mapStyleForBrightness(Brightness brightness) =>
    brightness == Brightness.dark ? _darkMapStyle : null;


/// Bottom-sheet snaps in the OSM design: Peek (handle + fixed
/// header only) and Half (~55% of the screen). No Full.
enum _SheetSnap { peek, half }

/// Which basemap the Map tab is showing: Meta's Canterbury
/// vector style, or the CartoDB Dark Matter raster fallback after
/// a failed Meta load.
enum _MapStyleMode { meta, cartoFallback }


/// Map view modes for the Map tab. Real Google Maps SDK
/// functionality only — no simulated 3D graphics, no fake
/// buildings. Where the SDK has no 3D building coverage the
/// perspective view still works: the tiles just show no extruded
/// buildings, with no error and no geometry invented.
enum MapViewMode { standard2d, perspective3d, satellite }

/// Google Maps map type for a view mode: satellite imagery (with
/// road labels) for Satellite, standard tiles otherwise.
MapType mapTypeForMode(MapViewMode mode) =>
    mode == MapViewMode.satellite ? MapType.satellite : MapType.normal;

/// Camera tilt for a view mode: perspective tilt in 3D, flat
/// top-down everywhere else.
double tiltForMode(MapViewMode mode) =>
    mode == MapViewMode.perspective3d ? 60 : 0;

/// Camera bearing for a view mode: 2D and Satellite always face
/// north; 3D keeps the user's current bearing so a rotated view
/// does not snap back north on a mode switch.
double bearingForMode(MapViewMode mode, double currentBearing) =>
    mode == MapViewMode.perspective3d ? currentBearing : 0;

/// 3D buildings render only in 3D mode.
bool buildingsForMode(MapViewMode mode) => mode == MapViewMode.perspective3d;

/// Full camera position for a view mode over [target].
CameraPosition cameraForMode({
  required MapViewMode mode,
  required LatLng target,
  required double zoom,
  double bearing = 0,
}) => CameraPosition(
  target: target,
  zoom: zoom,
  tilt: tiltForMode(mode),
  bearing: bearingForMode(mode, bearing),
);

/// Bottom offset of the floating bottom-left attribution ⓘ button.
/// (It used to position the right-hand control column too, until
/// Nov 7 moved that cluster to the top-right.) The collapsed sheet
/// occupies the bottom ~190dp, so the button floats above it; when
/// the sheet is hidden for a full-map view it drops to just above
/// the screen bottom (bottom:16 — the phone bottom nav bar sits
/// below the Scaffold body, so 16 clears it).
double mapControlsBottomOffset({required bool sheetHidden}) =>
    sheetHidden ? 16 : 190;

/// Tooltip for the logo toggle: what tapping it will do next.
String sheetToggleTooltip(bool sheetHidden) =>
    sheetHidden ? 'Show bottom panel' : 'Hide bottom panel';

/// Data for one numbered stop pin on the map (pure — see
/// [_MapTabState._stopMarkers]): [number] is 1-based in stop
/// order, [selected] while its card is open.
class MapStopPin {
  const MapStopPin({
    required this.number,
    required this.lat,
    required this.lng,
    required this.selected,
  });

  final int number;
  final double lat;
  final double lng;
  final bool selected;
}

/// Numbered stop pins for a route's stops (pure): one pin per
/// stop, 1..N in stop order — the clean map shows ONLY these pins
/// (plus the user's own blue dot, added separately in
/// [_MapTabState._stopMarkers]). Tested without pumping the
/// native map view, which cannot render in flutter test.
List<MapStopPin> routeStopPins(
  List<RouteStop> stops,
  int? selectedStopIndex,
) {
  return [
    for (var i = 0; i < stops.length; i++)
      MapStopPin(
        number: i + 1,
        lat: stops[i].lat,
        lng: stops[i].lng,
        selected: selectedStopIndex == i,
      ),
  ];
}

/// Whether the native MapLibre map can render on this platform:
/// Android, iOS, and web have federated implementations; desktop
/// (and the Linux test host) do not — the plugin's own stub throws
/// UnsupportedError there. This deliberately uses dart:io's
/// [Platform], not Flutter's [defaultTargetPlatform]: widget
/// tests report android for [defaultTargetPlatform] even on the
/// Linux host, while [Platform] tells the host truth. The app is
/// Android/iOS-only by design, so off those platforms the tab
/// shows a placeholder box and the sheet + controls keep working.
bool get mapLibreSupported =>
    kIsWeb || Platform.isAndroid || Platform.isIOS;

class MapTab extends StatefulWidget {
  /// The signed-in user (null when signed out). Drives the
  /// admin-only Add Route entry point — see admin_access.dart.
  /// Null keeps the old behaviour: no Add Route button, and the
  /// tab shows only the generated hub routes.
  const MapTab({
    super.key,
    this.currentUser,
    this.customRouteRepository,
  });

  final AuthUser? currentUser;

  /// Admin-added routes source. Null = no custom routes are loaded
  /// (e.g. tests, or Firebase not configured and no local repo).
  final CustomRouteRepository? customRouteRepository;

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> with WidgetsBindingObserver {
  static const _initialCenter = LatLng(16.9, 121.05);
  static const _initialZoom = 8.0;
  static const _homeHub = 2; // Cabugao — his home hub (Fares default origin).

  /// Placeholder in [_activeStyleUrl] while the CartoDB raster
  /// fallback is live (it is a style document, not a URL).
  static const _cartoFallbackSentinel = 'carto-fallback';

  // MapLibre controller, set in onMapCreated (null until the
  // native map exists — every camera call null-checks it, so a
  // tap before the map is ready is a no-op, as before). The
  // basemap is Meta's Canterbury vector style, routing is OSRM,
  // lookup is Nominatim. The google_maps_flutter LatLng value
  // type is kept for the pure route helpers + their tests.
  MapController? _mapController;
  // The style URL the map is showing (Meta by default, the
  // sentinel above once the CartoDB fallback fires). Kept in
  // sync with the theme in didChangeDependencies.
  String _activeStyleUrl = '';
  // The theme brightness the style was last switched for, so a
  // rebuild from another cause (rotation, locale) does not
  // re-attempt the Meta style while the fallback is live.
  bool? _lastStyleDark;
  // Which basemap is live: Meta vector, or the CartoDB raster
  // fallback after a failed Meta load.
  _MapStyleMode _styleMode = _MapStyleMode.meta;
  // True once the current style has reported loaded (cleared on
  // every style switch, so the fallback timer only fires for a
  // style that never loads).
  bool _styleLoaded = false;
  // Fallback timer for a Meta style that never loads.
  Timer? _styleLoadTimer;
  // Tile watchdog for a Meta style that LOADS but whose tiles
  // never render (Steven's phone, Nov 7, 15:24, light theme:
  // pins visible, basemap white, no route line). The 8 s timer
  // above only covers a style that never loads; once the style
  // reports loaded, this 10 s timer is the backup — it fires
  // the same CartoDB fallback unless the tile probe (below)
  // shows the tiles are reachable first. Armed only for the
  // initial load window after each style switch, never on
  // camera moves.
  Timer? _tileWatchdogTimer;
  // Flight generation: a newer _flyTo retargets the camera, and
  // the older flight's 1900 ms fallback must not yank it back.
  int _flyGeneration = 0;
  // Last known camera centre/zoom, updated (without setState) by
  // onPositionChanged — the same role _lastCamera played.
  LatLng _mapCenter = _initialCenter;
  double _mapZoom = _initialZoom;
  final _sheetController = DraggableScrollableController();

  bool _locationGranted = false;
  bool _locating = false;
  Position? _userPos;

  // Tapped-location path: the hub-to-hub route whose line is drawn
  // on the map, plus the origin point it starts from.
  RouteInfo? _activeRoute;
  LatLng? _activeRouteOrigin;
  // Road-following shape from OSRM (null = still loading or failed;
  // the dashed direct line shows until real geometry arrives).
  List<LatLng>? _roadPoints;
  double _routeDurationSec = 0;
  // Google's own route length (km) from routes.distanceMeters.
  // 0 = not loaded yet; the bottom bar then falls back to the
  // app's roadKm estimate for the minutes fraction.
  double _routeDistanceKm = 0;
  int _roadRequestId = 0;
  final VehicleType _vehicle = VehicleType.bus;
  // Bottom-sheet visibility toggle (logo button).
  // Visibility only: the sheet stays in the tree wrapped in
  // Offstage, so hiding never clears routes, destinations, church
  // selection, markers, polylines, or sheet content — tapping the
  // logo again restores the sheet exactly as it was, same snap
  // size included.
  bool _sheetHidden = false;
  // Stops on the active route (origin, on-the-way hubs, dest),
  // recomputed whenever the route or its road geometry changes.
  // See osm_routing.dart: no stop is ever invented.
  List<RouteStop> _routeStops = const [];
  // Stop whose card is open (null = no card). Set only AFTER the
  // flyTo animation lands, so the zoom always precedes the card.
  int? _selectedStopIndex;
  // Stop a flight is currently flying to; a newer tap retargets
  // and the stale landing is ignored.
  int? _pendingStopIndex;
  // Peek/Half snap the sheet is on (no Full in the OSM design).
  _SheetSnap _sheetSnap = _SheetSnap.peek;
  // Sheet body scroll, captured from the sheet builder so snap /
  // route / resize changes can reset it to the top.
  ScrollController? _sheetScrollController;
  // Keyboard focus for the sheet (Arrow Up/Down, Home, End).
  final FocusNode _sheetFocusNode = FocusNode();
  // Live bearing for the compass needle only (a ValueNotifier so
  // the needle rebuilds alone, never the whole map).
  final ValueNotifier<double> _bearing = ValueNotifier<double>(0);
  // Catholic churches from Google Places (Churches chip, whole
  // Luzon). Markers show only while the chip is active and not
  // navigating, so they never clutter a route.

  /// Admin-added routes (Add Route), newest first. Visible to
  /// everyone; only admins may add, edit, or delete them.

  @override
  void initState() {
    super.initState();
    _refreshLocationGranted();
    _sheetController.addListener(_onSheetExtentChanged);
    WidgetsBinding.instance.addObserver(this);
    communityMapJump.addListener(_onCommunityJump);
    faresMapJump.addListener(_onFaresJump);
    // Preview parity: the map always opens on the default route
    // (Cabugao → Vigan Bus Terminal, the Fares default pair), so
    // the tab shows the clean route + ETA • FARE sheet at once
    // instead of an empty map. A later Fares / community jump
    // retargets it as before. Deferred past the first frame so
    // the map controller is attached for the fit + road fetch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeRoute != null) return;
      _selectHub(hubs[14]); // Vigan Bus Terminal.
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Theme changes re-run this: switch the basemap style to
    // match (MapOptions.initStyle only applies at creation). The
    // [_lastStyleDark] guard keeps a rebuild from another cause
    // (rotation, locale) from re-attempting the Meta style while
    // the CartoDB fallback is live — only a real theme change
    // retries it.
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark == _lastStyleDark) return;
    _lastStyleDark = dark;
    final desired = metaMapStyleUrl(dark: dark);
    if (desired == _activeStyleUrl) return;
    _activeStyleUrl = desired;
    _styleMode = _MapStyleMode.meta;
    _styleLoaded = false;
    _tileWatchdogTimer?.cancel(); // Old style's watchdog is moot.
    final controller = _mapController;
    if (controller == null) return; // First build: initStyle covers it.
    _armStyleFallbackTimer();
    controller.setStyle(desired);
  }

  /// Theme brightness of the style currently loading (or live):
  /// the theme didChangeDependencies last switched for, falling
  /// back to the live theme before the first switch.
  bool get _fallbackDark =>
      _lastStyleDark ?? Theme.of(context).brightness == Brightness.dark;

  /// Switches the live basemap to the theme-aware CartoDB raster
  /// fallback (dark → Dark Matter, light → Positron) and updates
  /// the attribution chip. Called by the 8 s style-load timer
  /// (style never loads) and the 10 s tile watchdog (style loads
  /// but tiles never render). No-op once the fallback is live or
  /// the map is gone.
  void _switchToCartoFallback() {
    if (!mounted || _styleMode != _MapStyleMode.meta) return;
    final controller = _mapController;
    if (controller == null) return;
    _styleLoadTimer?.cancel();
    _tileWatchdogTimer?.cancel();
    _styleMode = _MapStyleMode.cartoFallback;
    _activeStyleUrl = _cartoFallbackSentinel;
    controller.setStyle(cartoFallbackStyleJson(dark: _fallbackDark));
    setState(() {}); // Attribution chip switches to OSM + CARTO.
  }

  /// Starts (or restarts) the fallback timer for the Meta style
  /// currently loading: if it never reports loaded within 8 s,
  /// the map switches to the CartoDB raster fallback (theme-aware)
  /// instead of sitting on a blank map.
  void _armStyleFallbackTimer() {
    _styleLoadTimer?.cancel();
    _styleLoadTimer = Timer(const Duration(seconds: 8), () {
      if (_styleLoaded) return;
      _switchToCartoFallback();
    });
  }

  /// Arms the tile watchdog for the Meta style that just loaded:
  /// if its tiles still have not rendered 10 s later, the map
  /// switches to the CartoDB raster fallback. This is the hole
  /// the 8 s timer does not cover — a style that loads but whose
  /// tiles never arrive (Steven's phone, Nov 7, 15:24).
  ///
  /// Plain time-based on purpose: the maplibre 0.3.7 plugin has
  /// NO tiles-rendered signal on Android — MapEventIdle is only
  /// emitted by the iOS implementation, and Android emits only
  /// MapEventCameraIdle, which fires when the camera stops
  /// moving and says nothing about tiles (it fires on a white
  /// map too). So the watchdog fires on time alone unless the
  /// tile probe below cancels it first.
  void _armTileWatchdog() {
    _tileWatchdogTimer?.cancel();
    _tileWatchdogTimer = Timer(const Duration(seconds: 10), () {
      _switchToCartoFallback();
    });
  }

  /// Tile-reachability probe: fetches the one Meta vector tile
  /// under the current camera. If it arrives, the CDN is
  /// reachable from this phone — the native map's own tile
  /// requests can succeed too — so the tile watchdog is
  /// cancelled and the Meta map stays. If it fails or times
  /// out, the watchdog is left armed and fires the CartoDB
  /// fallback at 10 s. A probe result is ignored if the style
  /// changed meanwhile (theme switch) or the widget is gone.
  Future<void> _probeMetaTiles() async {
    final styleUrl = _activeStyleUrl;
    final zoom = _mapZoom.floor();
    final reachable = await probeMetaVectorTile(
      lat: _mapCenter.latitude,
      lng: _mapCenter.longitude,
      z: zoom,
    );
    if (!mounted ||
        !reachable ||
        _styleMode != _MapStyleMode.meta ||
        _activeStyleUrl != styleUrl) {
      return;
    }
    _tileWatchdogTimer?.cancel();
    _tileWatchdogTimer = null;
  }

  /// The native map is ready: the fallback timer starts for the
  /// initial style, and a default route selected before creation
  /// (post-frame _selectHub) can finally fit its bounds.
  void _onMapCreated(MapController controller) {
    _mapController = controller;
    if (_styleMode == _MapStyleMode.meta && !_styleLoaded) {
      _armStyleFallbackTimer();
    }
    _fitActiveRoute();
  }

  /// A style finished loading (Meta, or the CartoDB fallback):
  /// the fallback timer is no longer needed for this style.
  /// For the Meta style, the tile watchdog + probe start here:
  /// the style document arrived, but the tiles may still be
  /// stuck (Steven's white map, Nov 7).
  void _onStyleLoaded(StyleController _) {
    _styleLoadTimer?.cancel();
    _styleLoaded = true;
    if (_styleMode != _MapStyleMode.meta) return;
    _armTileWatchdog();
    _probeMetaTiles();
  }

  /// Sheet snap tracking: when the extent crosses the Peek/Half
  /// boundary the snap label updates and the body scroll resets
  /// to the top, so a half-open sheet never starts mid-list.
  void _onSheetExtentChanged() {
    if (!_sheetController.isAttached) return;
    final snap = _sheetController.size >= 0.4
        ? _SheetSnap.half
        : _SheetSnap.peek;
    if (snap != _sheetSnap) {
      setState(() {
        _sheetSnap = snap;
        // The card sits above the Peek sheet; at Half the sheet
        // would cover it, so the card closes with the snap.
        if (snap == _SheetSnap.half) _selectedStopIndex = null;
      });
      _resetSheetScroll();
    }
  }

  @override
  void didChangeMetrics() {
    // Rotation / resize: the sheet body restarts at the top.
    _resetSheetScroll();
  }

  /// Resets the sheet body scroll to the top (snap / route /
  /// resize). No-op before the sheet builds.
  void _resetSheetScroll() {
    final controller = _sheetScrollController;
    if (controller != null && controller.hasClients) {
      controller.jumpTo(0);
    }
  }

  /// Animates the sheet to a snap (Peek 0.20 / Half 0.55).
  void _snapSheet(_SheetSnap snap) {
    if (!_sheetController.isAttached) return;
    _sheetController.animateTo(
      snap == _SheetSnap.half ? 0.55 : 0.20,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Handle tap: cycles Peek <-> Half.
  void _cycleSheetSnap() => _snapSheet(
    _sheetSnap == _SheetSnap.peek ? _SheetSnap.half : _SheetSnap.peek,
  );


  /// A community post's "View on map" sets this notifier; jump the map
  /// to that hub, then clear it so the same hub can be jumped to again.
  void _onCommunityJump() {
    final hubName = communityMapJump.value;
    if (hubName == null) return;
    communityMapJump.value = null;
    if (!mounted) return;
    final match = hubs.where((h) => h.name == hubName);
    if (match.isEmpty) return;
    _selectHub(match.first);
  }

  /// A Fares "Find routes" / "Show direction on Map" sets
  /// [faresMapJump]; draw that hub-to-hub route (direction line +
  /// ETA • FARE sheet, snapped to Half so the route details show),
  /// then clear it so the same route can be jumped to again. A
  /// 'My location' origin resolves to the device position when
  /// known, else the home hub — the same rule as the hub-tap flow.
  /// Non-hub names are ignored: the tab opens with no route rather
  /// than drawing a line to a place the app does not know.
  void _onFaresJump() {
    final jump = faresMapJump.value;
    if (jump == null) return;
    faresMapJump.value = null;
    if (!mounted) return;
    final destMatches = hubs.where((h) => h.name == jump.to);
    if (destMatches.isEmpty) return;
    final destHub = destMatches.first;
    final originMatches = hubs.where((h) => h.name == jump.from);
    final double oLat;
    final double oLng;
    final String oName;
    if (originMatches.isNotEmpty) {
      final originHub = originMatches.first;
      oLat = originHub.lat;
      oLng = originHub.lng;
      oName = originHub.name;
    } else {
      oLat = _userPos?.latitude ?? hubs[_homeHub].lat;
      oLng = _userPos?.longitude ?? hubs[_homeHub].lng;
      oName = _userPos != null ? 'Your location' : hubs[_homeHub].name;
    }
    final matches = routesFrom(
      oLat,
      oLng,
      oName,
    ).where((r) => r.dest.name == destHub.name);
    final route = matches.isEmpty ? null : matches.first;
    setState(() {
      _activeRoute = route;
      _activeRouteOrigin = route == null ? null : LatLng(oLat, oLng);
      _roadPoints = null;
      _selectedStopIndex = null;
      _pendingStopIndex = null;
    });
    _refreshRouteStops();
    _resetSheetScroll();
    if (route != null) {
      _fitActiveRoute();
      _fetchRoadPath(oLat, oLng, destHub);
      _snapSheet(_SheetSnap.half);
    }
  }

  @override
  void dispose() {
    communityMapJump.removeListener(_onCommunityJump);
    faresMapJump.removeListener(_onFaresJump);
    WidgetsBinding.instance.removeObserver(this);
    _sheetController.removeListener(_onSheetExtentChanged);
    _styleLoadTimer?.cancel();
    _tileWatchdogTimer?.cancel();
    _sheetController.dispose();
    _sheetFocusNode.dispose();
    _bearing.dispose();
    super.dispose();
  }






  // ---- Admin-added routes (Add Route) ----







  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Shared location gate with the exact strings the app already uses.
  // No-prompt permission reflection for the blue dot.
  Future<void> _refreshLocationGranted() async {
    final permission = await Geolocator.checkPermission();
    if (!mounted) return;
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      setState(() => _locationGranted = true);
    }
  }

  Future<Position?> _ensurePosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _snack('Turn on Location (GPS) on your phone first.');
      return null;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _snack('Location permission is needed to see where you are.');
      return null;
    }
    return Geolocator.getCurrentPosition();
  }

  Future<void> _goToMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final position = await _ensurePosition();
      if (position == null || !mounted) return;
      setState(() {
        _userPos = position;
        _locationGranted = true;
      });
      await _moveTo(LatLng(position.latitude, position.longitude), zoom: 15);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Fits the map to a southwest/northeast box. Native fitBounds
  /// has no maxZoom, so a short hop (two nearby hubs) is clamped
  /// back to zoom 15 afterwards, like before.
  Future<void> _fitBounds(LatLng sw, LatLng ne) async {
    final controller = _mapController;
    if (controller == null) return;
    try {
      await controller.fitBounds(
        bounds: LngLatBounds(
          longitudeWest: math.min(sw.longitude, ne.longitude),
          longitudeEast: math.max(sw.longitude, ne.longitude),
          latitudeSouth: math.min(sw.latitude, ne.latitude),
          latitudeNorth: math.max(sw.latitude, ne.latitude),
        ),
        padding: const EdgeInsets.all(80),
        nativeDuration: const Duration(milliseconds: 1400),
      );
      final camera = controller.getCamera();
      _mapCenter = LatLng(camera.center.lat, camera.center.lon);
      _mapZoom = camera.zoom;
      _bearing.value = camera.bearing;
      if (camera.zoom > 15) {
        await controller.moveCamera(center: camera.center, zoom: 15);
        _mapZoom = 15;
      }
    } catch (_) {
      // The map is not attached yet (e.g. a tap before the first
      // frame) — the next camera move still lands.
    }
  }

  /// Fits the map to the active route's endpoints (origin +
  /// destination, padded so the bounds never degenerate). Used by
  /// _selectHub / _onFaresJump and once when the native map is
  /// created, when a route selected before creation can finally
  /// fit.
  void _fitActiveRoute() {
    final route = _activeRoute;
    final origin = _activeRouteOrigin;
    if (route == null || origin == null) return;
    _fitBounds(
      LatLng(
        math.min(origin.latitude, route.dest.lat) - 0.01,
        math.min(origin.longitude, route.dest.lng) - 0.01,
      ),
      LatLng(
        math.max(origin.latitude, route.dest.lat) + 0.01,
        math.max(origin.longitude, route.dest.lng) + 0.01,
      ),
    );
  }

  /// Animated move ("flyTo"): the map's own native animation,
  /// so the zoom is slow enough to be seen on a phone. Starting
  /// a new flight retargets the camera; the older flight's
  /// fallback is ignored via [_flyGeneration].
  ///
  /// Timing follows the preview (v34): a 1400 ms flight, plus a
  /// 1900 ms fallback — if the flight has not landed by then
  /// (e.g. the animation was interrupted), the final camera
  /// position is forced directly instead of leaving the map
  /// where it was. The stop card's reveal gate lives in
  /// [_selectStop] (min 650 ms), so the zoom is always visible
  /// before the card opens.
  Future<void> _flyTo(LatLng target, {double zoom = 13}) async {
    final controller = _mapController;
    if (controller == null) return;
    final generation = ++_flyGeneration;
    var landed = false;
    try {
      await controller.animateCamera(
        center: Geographic(lon: target.longitude, lat: target.latitude),
        zoom: zoom,
        nativeDuration: const Duration(milliseconds: 1400),
      );
      _mapCenter = target;
      _mapZoom = zoom;
    } catch (_) {
      // Interrupted by a newer flight — the newer one owns the view.
    }
    landed = true;
    // Fallback (preview v34): force the landing if the flight
    // has not finished 1900 ms after it started. A newer flight
    // owns the view by then, so this only fires for a stuck one.
    Future.delayed(const Duration(milliseconds: 1900), () async {
      if (!mounted || landed || _flyGeneration != generation) return;
      final current = _mapController;
      if (current == null) return;
      try {
        await current.moveCamera(
          center: Geographic(lon: target.longitude, lat: target.latitude),
          zoom: zoom,
        );
        _mapCenter = target;
        _mapZoom = zoom;
      } catch (_) {}
    });
  }

  Future<void> _moveTo(LatLng target, {double zoom = 13}) async {
    // Animated: a jump (my-location, hub tap, nav start) keeps
    // the current rotation instead of flattening it.
    await _flyTo(target, zoom: zoom);
  }

  /// Compass tap: face north again (rotate 0), keeping centre
  /// and zoom.
  Future<void> _resetBearing() async {
    final controller = _mapController;
    if (controller == null) return;
    try {
      final camera = controller.getCamera();
      await controller.moveCamera(
        center: camera.center,
        zoom: camera.zoom,
        bearing: 0,
      );
    } catch (_) {}
    _bearing.value = 0;
  }

  /// Tapping a location selects it AND draws its path: the road
  /// shape from Google (solid line) once it loads, with the dashed
  /// direct line as the instant fallback. Origin =
  /// your location when known, else Cabugao. Tapping a new location
  /// Real ETA minutes for a preview mode, on the Google road
  /// distance (not the hub-distance estimate): same mountain /
  /// same-region rules as the destination panel.
  int _previewMinutes(TravelMode mode) {
    final route = _activeRoute;
    if (route == null) return 0;
    Hub? originHub;
    for (final h in hubs) {
      if (h.name == route.originName) originHub = h;
    }
    final mountain =
        isMountainHub(route.dest) ||
        (originHub != null && isMountainHub(originHub));
    final sameRegion =
        originHub != null && originHub.region == route.dest.region;
    return estimateTripMinutes(
      roadKm: route.roadKm,
      mountain: mountain,
      sameRegion: sameRegion,
      mode: mode,
    );
  }



  /// mid-navigation ends that navigation (start again for the new
  /// destination).
  void _selectHub(Hub hub) {
    final oLat = _userPos?.latitude ?? hubs[_homeHub].lat;
    final oLng = _userPos?.longitude ?? hubs[_homeHub].lng;
    final oName = _userPos != null ? 'Your location' : hubs[_homeHub].name;
    final matches = routesFrom(
      oLat,
      oLng,
      oName,
    ).where((r) => r.dest.name == hub.name);
    final route = matches.isEmpty ? null : matches.first;
    setState(() {
      _activeRoute = route;
      _activeRouteOrigin = route == null ? null : LatLng(oLat, oLng);
      _roadPoints = null;
      _selectedStopIndex = null;
      _pendingStopIndex = null;
    });
    _refreshRouteStops();
    _resetSheetScroll();
    if (route != null) {
      // Fit both endpoints, padded so the bounds never degenerate.
      _fitActiveRoute();
      _fetchRoadPath(oLat, oLng, hub);
    } else {
      _moveTo(LatLng(hub.lat, hub.lng), zoom: 13);
    }
  }






  /// Photo slot for the church details panel. Shows the real
  /// Places photo when the entry carries photo data and the build
  /// has an API key; anything else — every verified church, every
  /// Places entry without photos, a failed load — shows the plain
  /// honest empty state, never a placeholder picture. A standalone
  /// widget so it stays widget-testable without the map.
  // Nominatim has no photos, so the key is always empty here:
  // the slot shows its honest empty state. churchPhotoUrl stays
  // for the Places-photo shape (unit-tested, unused at runtime).

  /// Fetches the road-following shape for the active route from
  /// OSRM (DRIVE mode, road routing via router.project-osrm.org).
  /// Only the two endpoint coordinates are sent, plus the
  /// Avenida Quezon via-point when the destination is the Vigan
  /// Bus Terminal (see viaWaypointsForDestination). No API key,
  /// no billing. On any failure the dashed direct line simply
  /// stays — the route never breaks. A stale response (user
  /// tapped elsewhere since) is ignored via [_roadRequestId].
  Future<void> _fetchRoadPath(
    double oLat,
    double oLng,
    Hub dest, {
    List<LatLng> via = const [],
  }) async {
    final requestId = ++_roadRequestId;
    // A custom route's own via-stops win; otherwise the terminal
    // destination gets its Quezon Ave waypoint (see
    // viaWaypointsForDestination). An explicit empty list means
    // "no via points", so only fall back when none were given.
    final effectiveVia =
        via.isNotEmpty ? via : viaWaypointsForDestination(dest);
    final result = await fetchOsrmRoute(
      oLat: oLat,
      oLng: oLng,
      dest: dest,
      via: effectiveVia,
    );
    if (!mounted || requestId != _roadRequestId) return;
    if (result == null || result.points.isEmpty) {
      // OSRM routing unavailable — the dashed direct line stays.
      return;
    }
    setState(() {
      _roadPoints = result.points;
      _routeDurationSec = result.durationSec;
      _routeDistanceKm = result.distanceKm;
      _selectedStopIndex = null;
      _pendingStopIndex = null;
      if (_activeRoute != null && _activeRouteOrigin != null) {
        _routeStops = routeStops(
          origin: _activeRouteOrigin!,
          originName: _activeRoute!.originName,
          dest: _activeRoute!.dest,
          roadPoints: result.points,
          totalKm: result.distanceKm > 0
              ? result.distanceKm
              : _activeRoute!.roadKm,
          viaHubNames: _activeRoute!.customRoute?.viaHubs ?? const [],
        );
      }
    });
  }













  /// Via points for the active route's own line: a custom route's
  /// via-stops (excluding its endpoints), otherwise none (the
  /// terminal Quezon Ave waypoint is added inside _fetchRoadPath).
  List<LatLng> _customRouteViaPoints(RouteInfo route) {
    final custom = route.customRoute;
    if (custom == null) return const [];
    final points = customRouteLinePoints(custom);
    if (points.length < 3) return const [];
    return points.sublist(1, points.length - 1);
  }








  /// Points + style for the active-route line. Solid = real
  /// OSRM road shape; dashed = direct-line fallback. When a stop
  /// is tapped, only the line from that stop to the destination
  /// lights up (soft glow + white casing + wide light-green core)
  /// while the earlier part dims; tapping the destination leaves
  /// nothing lit. Dismissing the card restores this normal
  /// standard-green line. One [PolylineLayer] per visual style
  /// (MapLibre styles a whole layer one colour/width, so the
  /// highlight is four layers drawn bottom-to-top, as before).
  List<PolylineLayer> _routePolylineLayers() {
    if (_activeRoute == null || _activeRouteOrigin == null) {
      return const [];
    }
    const green = Color(0xFF16A34A);
    final dest = LatLng(_activeRoute!.dest.lat, _activeRoute!.dest.lng);
    final List<LatLng> points;
    final bool solid;
    // No road shape yet: the dashed fallback follows the custom
    // route's own via-stops instead of a straight origin→dest
    // line, so a Partas line already differs from a Dominion line.
    final via = _customRouteViaPoints(_activeRoute!);
    points = _roadPoints ?? [_activeRouteOrigin!, ...via, dest];
    solid = _roadPoints != null;
    Feature<LineString> line(List<LatLng> pts) => Feature<LineString>(
      geometry: LineString(
        pts
            .expand((p) => [p.longitude, p.latitude])
            .toList()
            .positions(Coords.xy),
      ),
    );
    // Route segment highlight: the tapped stop → destination
    // lights up, the earlier part dims.
    if (_selectedStopIndex != null &&
        _routeStops.isNotEmpty &&
        _roadPoints != null &&
        _roadPoints!.length >= 2) {
      final stop = _routeStops[
          _selectedStopIndex!.clamp(0, _routeStops.length - 1)];
      final split = splitPathAt(_roadPoints!, stop.pathIndex);
      final before = split.before;
      final after = split.after;
      return [
        // Earlier part: dimmed to 0.15.
        PolylineLayer(
          polylines: [line(before)],
          color: green.withValues(alpha: 0.15),
          width: 6,
        ),
        // Remaining part: soft glow + white casing + wide
        // light-green core.
        PolylineLayer(
          polylines: [line(after)],
          color: green.withValues(alpha: 0.25),
          width: 16,
        ),
        PolylineLayer(
          polylines: [line(after)],
          color: Colors.white,
          width: 11,
        ),
        PolylineLayer(
          polylines: [line(after)],
          color: const Color(0xFF4ADE80),
          width: 7,
        ),
      ];
    }
    return [
      PolylineLayer(
        polylines: [line(points)],
        color: green,
        width: 6,
        dashArray: solid ? null : const [24, 12],
      ),
    ];
  }

  /// Map markers — clean, like the preview: ONLY the active
  /// route's numbered stop pins (1..N), each tappable to fly to
  /// that stop + open its card. No scattered hub pins across the
  /// region and no church markers: the preview's map shows the
  /// route line + its stops and nothing else. The user's own blue
  /// dot (and the vehicle cursor during navigation) stay — they
  /// are the user's own position, not route clutter. A 'Your
  /// location' origin is stop 1 in [_routeStops] already, so it
  /// needs no special case.
  List<Marker> _stopMarkers() {
    final markers = <Marker>[
      for (final pin in routeStopPins(_routeStops, _selectedStopIndex))
        Marker(
          point: Geographic(lon: pin.lng, lat: pin.lat),
          size: const Size(44, 44),
          child: GestureDetector(
            onTap: () => _selectStop(pin.number - 1),
            child: Center(
              child: _numberedPin(pin.number, selected: pin.selected),
            ),
          ),
        ),
    ];
    // User position: a plain blue-dot circle (MapLibre has no
    // built-in blue dot).
    if (_userPos != null && _locationGranted) {
      markers.add(
        Marker(
          point: Geographic(
            lon: _userPos!.longitude,
            lat: _userPos!.latitude,
          ),
          size: const Size(24, 24),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF4285F4),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  /// Recomputes [_routeStops] from the current route + road
  /// geometry (origin + destination when the geometry has not
  /// loaded yet — no intermediate hub is ever guessed).
  void _refreshRouteStops() {
    final route = _activeRoute;
    final origin = _activeRouteOrigin;
    if (route == null || origin == null) {
      if (_routeStops.isNotEmpty) {
        setState(() => _routeStops = const []);
      }
      return;
    }
    setState(() {
      _routeStops = routeStops(
        origin: origin,
        originName: route.originName,
        dest: route.dest,
        roadPoints: _roadPoints,
        totalKm: _routeDistanceKm > 0 ? _routeDistanceKm : route.roadKm,
        viaHubNames: route.customRoute?.viaHubs ?? const [],
      );
    });
  }

  /// Tapping a stop pin or a stop row: the map flies to that stop
  /// (smooth zoom to ~15) FIRST, and only then does the stop card
  /// open. Tapping another stop retargets the flight; the stale
  /// landing is ignored via [_pendingStopIndex]. The sheet snaps
  /// to Peek so the card has room above it. Preview v34 reveal
  /// gate: the card only opens once at least 650 ms have passed
  /// since the tap, so the zoom is seen before the card covers it.
  Future<void> _selectStop(int index) async {
    if (index < 0 || index >= _routeStops.length) return;
    final stop = _routeStops[index];
    _pendingStopIndex = index;
    _resetSheetScroll();
    _snapSheet(_SheetSnap.peek);
    final startedAt = DateTime.now();
    await _flyTo(LatLng(stop.lat, stop.lng), zoom: 15);
    if (!mounted || _pendingStopIndex != index) return;
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < const Duration(milliseconds: 650)) {
      await Future.delayed(const Duration(milliseconds: 650) - elapsed);
      if (!mounted || _pendingStopIndex != index) return;
    }
    setState(() => _selectedStopIndex = index);
  }

  /// Dismisses the stop card (X, map tap, route change).
  /// Dismissing restores the normal standard-green line: the
  /// highlight only exists while a stop is selected.
  void _dismissStopCard() {
    if (_selectedStopIndex == null) return;
    setState(() => _selectedStopIndex = null);
  }


  /// Numbered stop pin (emerald circle, white number; deep
  /// emerald while its card is open).
  Widget _numberedPin(int number, {required bool selected}) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: selected ? kMapPrimary : const Color(0xFF16A34A),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }

  /// Attribution chip — required credit for the basemap in use.
  /// Meta's Canterbury styles declare no attribution string of
  /// their own, so the Meta map is credited as "© Meta" (plain
  /// text — there is no Meta attribution page to link). On the
  /// CartoDB raster fallback the chip is the OSM + CARTO credit,
  /// tappable to that layer's attribution page, as before.
  Widget _attributionChip({required bool dark}) {
    final fallback = _styleMode == _MapStyleMode.cartoFallback;
    final text = fallback
        ? mapAttributionText(dark: dark)
        : metaMapAttributionText;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
    if (!fallback) return chip;
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(mapAttributionUrl(dark: dark))),
      child: chip,
    );
  }

  /// The ⓘ attribution button: on the CartoDB fallback it opens
  /// that layer's attribution page; on the Meta map (no
  /// attribution page exists) it states the credit plainly.
  void _onAttributionTap({required bool dark}) {
    if (_styleMode == _MapStyleMode.cartoFallback) {
      launchUrl(Uri.parse(mapAttributionUrl(dark: dark)));
      return;
    }
    _snack('Map data $metaMapAttributionText — Canterbury');
  }

  /// One row of the stop card (label left, value right).
  Widget _stopCardRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Stop card: shown only after the flyTo lands. Municipality
  /// (locality + province) is the hub's own name + region — never
  /// invented. Distances come from the real OSRM geometry; the
  /// per-stop time is a scaled estimate, labelled as one.
  Widget _stopCard() {
    final index = _selectedStopIndex;
    if (index == null || index < 0 || index >= _routeStops.length) {
      return const SizedBox.shrink();
    }
    final stop = _routeStops[index];
    final totalKm = _routeDistanceKm > 0
        ? _routeDistanceKm
        : (_activeRoute?.roadKm ?? 0);
    final totalMin = _routeDurationSec > 0
        ? _routeDurationSec / 60
        : _previewMinutes(TravelMode.transit).toDouble();
    final kmToDest = math.max(0, totalKm - stop.kmFromOrigin);
    final estMin = estimatedStopMinutes(
      kmFromOrigin: stop.kmFromOrigin,
      totalKm: totalKm,
      totalMinutes: totalMin,
    );
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(kMapCardRadius),
      color: kMapDarkCard,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stop.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        stop.region.isEmpty
                            ? 'Stop ${index + 1} of ${_routeStops.length}'
                            : '${stop.region} · Stop ${index + 1} of ${_routeStops.length}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    stop.role,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Dismiss',
                  onPressed: _dismissStopCard,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _stopCardRow(
              'Distance from origin',
              '${stop.kmFromOrigin.toStringAsFixed(1)} km',
            ),
            _stopCardRow(
              'KM to destination',
              stop.isDestination
                  ? '0 km · destination'
                  : '${kmToDest.toStringAsFixed(1)} km',
            ),
            _stopCardRow(
              'Travel time',
              'tinatayang (estimate) ${formatTripTime(estMin)} from origin',
            ),
          ],
        ),
      ),
    );
  }

  /// "Stops along the way" for the sheet: one row per route stop.
  /// Tapping a row flies the map to that stop, then opens its card.
  /// "STOPS ALONG THE WAY" for the sheet: one row per route stop —
  /// number circle, name, role (Start / Stop / End) at the right,
  /// like the preview. Tapping a row flies the map to that stop,
  /// then opens its card. (Distance + KM-to-destination live in
  /// the stop card, not the row.)
  List<Widget> _stopsSection(ColorScheme scheme) {
    if (_routeStops.isEmpty) return const [];
    return [
      Text(
        'STOPS ALONG THE WAY',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: scheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < _routeStops.length; i++)
        Material(
          color: _selectedStopIndex == i
              ? scheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _selectStop(i),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: Color(0xFF16A34A),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _routeStops[i].name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    _routeStops[i].role,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  /// Fixed sheet header (below the handle, outside the scrollable
  /// body): the preview's ETA • FARE header — the "ETA • FARE"
  /// label + VERIFIED FARE badge, then the route title. Fixed so
  /// scrolling can never push them up or clip them. No sheet
  /// title, no Plan a Trip, no swap, no Add Route: the preview's
  /// sheet has none of those (Add Route lives in the Fares tab).
  /// The header is compact, so it fits the peeked sheet whole.
  Widget _sheetFixedHeader(ColorScheme scheme) {
    final route = _activeRoute;
    if (route == null) return const SizedBox.shrink();
    final verified = knownBusFare(route.originName, route.dest.name);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                'ETA • FARE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (verified != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 12,
                        color: Colors.white,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'VERIFIED FARE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${route.originName} → ${route.dest.name}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Sheet body (scrollable): the preview's ETA • FARE body —
  /// fare cards, duration + distance, then the stops list. The
  /// ETA • FARE header lives in [_sheetFixedHeader] above this,
  /// outside the scroll. When no route is active (only the brief
  /// moment before the default route loads), an honest
  /// placeholder shows instead of an invented route.
  List<Widget> _sheetBodyWidgets({required ColorScheme scheme}) {
    final route = _activeRoute;
    if (route == null) {
      return const [
        SizedBox(height: 8),
        Text(
          'Pick a route in Fares to see its fare and stops here.',
          style: TextStyle(fontSize: 14),
        ),
      ];
    }
    return [
      const SizedBox(height: 4),
      _fareCards(scheme, route),
      const SizedBox(height: 12),
      _durationDistanceCards(scheme, route),
      const SizedBox(height: 16),
      ..._stopsSection(scheme),
    ];
  }

  /// The preview's fare cards: REGULAR FARE and DISCOUNTED -20%,
  /// side by side. The regular fare is the user-verified fare
  /// when the pair has one (Cabugao ↔ Vigan ₱60), otherwise the
  /// formula fare; the discounted fare is 20% off, rounded to the
  /// nearest ₱0.25 — the same rule as computeFare. A route with
  /// no fare at all (Partas Laoag → Cubao, GMW) says so plainly.
  Widget _fareCards(ColorScheme scheme, RouteInfo route) {
    final regular = route.customRoute?.fare ??
        resolveTransitFare(
          from: route.originName,
          to: route.dest.name,
          vehicle: _vehicle,
          roadKm: route.roadKm,
        );
    final discounted =
        regular == null ? null : (regular * 0.8 * 4).round() / 4;
    return Row(
      children: [
        Expanded(
          child: _etaFareStatCard(
            scheme: scheme,
            label: 'REGULAR FARE',
            value: regular == null ? 'Fare not set' : peso(regular),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _etaFareStatCard(
            scheme: scheme,
            label: 'DISCOUNTED -20%',
            value: discounted == null ? 'Fare not set' : peso(discounted),
            highlight: true,
          ),
        ),
      ],
    );
  }

  /// DURATION + DISTANCE cards, side by side. Distance is the
  /// live OSRM road length when loaded, else the route estimate;
  /// duration is the live OSRM duration when loaded, else the
  /// app's estimateTripTime model — both real, never invented.
  Widget _durationDistanceCards(ColorScheme scheme, RouteInfo route) {
    final km = _routeDistanceKm > 0 ? _routeDistanceKm : route.roadKm;
    final minutes = _routeDurationSec > 0
        ? (_routeDurationSec / 60).round()
        : _previewMinutes(TravelMode.transit);
    return Row(
      children: [
        Expanded(
          child: _etaFareStatCard(
            scheme: scheme,
            label: 'DURATION',
            value: formatTripTime(minutes),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _etaFareStatCard(
            scheme: scheme,
            label: 'DISTANCE',
            value: '${km.toStringAsFixed(1)} km',
          ),
        ),
      ],
    );
  }

  /// One ETA • FARE stat card: a small muted label above a big
  /// bold value. The discounted fare value is green.
  Widget _etaFareStatCard({
    required ColorScheme scheme,
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: highlight
                  ? const Color(0xFF16A34A)
                  : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }


  @override
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // Full-screen Meta vector map under the top nav: no text
        // block above it — the old direction card is gone, route
        // info lives in the sheet. The native map only builds
        // where the plugin has an implementation (see
        // mapLibreSupported); elsewhere a placeholder box keeps
        // the sheet + controls working.
        if (mapLibreSupported)
          MapLibreMap(
          options: MapOptions(
            // Theme-driven style: Meta's Canterbury vector style
            // (dark / light), the same map the preview renders.
            // If it fails to load — or loads but its tiles never
            // render — the timers switch to the theme-aware
            // CartoDB raster fallback style.
            initStyle: metaMapStyleUrl(
              dark: scheme.brightness == Brightness.dark,
            ),
            initCenter: const Geographic(lon: 121.05, lat: 16.9),
            initZoom: _initialZoom,
            minZoom: 3,
            maxZoom: 19,
          ),
          onMapCreated: _onMapCreated,
          onStyleLoaded: _onStyleLoaded,
          onEvent: (event) {
            if (event is MapEventMoveCamera) {
              final camera = event.camera;
              _mapCenter = LatLng(camera.center.lat, camera.center.lon);
              _mapZoom = camera.zoom;
              _bearing.value = camera.bearing;
            } else if (event is MapEventClick) {
              // A plain map tap dismisses the open stop card (and
              // restores the normal line).
              if (_selectedStopIndex != null) {
                setState(() => _selectedStopIndex = null);
              }
            }
          },
          layers: _routePolylineLayers(),
          children: [
            WidgetLayer(
              allowInteraction: true,
              markers: _stopMarkers(),
            ),
          ],
        )
        else
          Container(
            color: scheme.brightness == Brightness.dark
                ? const Color(0xFF0C1410)
                : const Color(0xFFE8EDE9),
            alignment: Alignment.center,
            child: Text(
              'Map unavailable on this platform',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        // Floating map controls, top-right (Steven, Nov 7: the
        // buttons belong at the top). They used to sit bottom-right
        // above the peeked sheet; the top-right is free — no text
        // block or title lives there — so the cluster pins to the
        // top corner and never collides with the sheet, the stop
        // card, or the attribution chip.
        Positioned(
          right: 16,
          top: 16,
          child: Column(
            children: [
              // Green bus button: hides the bottom sheet completely
              // for a full-map view; tap again to bring it back at
              // the current snap. The button itself stays visible
              // while the sheet is hidden — it is the way back.
              _LogoToggleButton(
                tooltip: sheetToggleTooltip(_sheetHidden),
                onPressed: () {
                  setState(() => _sheetHidden = !_sheetHidden);
                  if (!_sheetHidden) {
                    _snapSheet(_sheetSnap);
                    _sheetFocusNode.requestFocus();
                  }
                },
              ),
                const SizedBox(height: 10),
              _MapControlButton(
                icon: Icons.add,
                tooltip: 'Zoom in',
                onPressed: () async {
                  final controller = _mapController;
                  if (controller == null) return;
                  final zoom = (_mapZoom + 1).clamp(3.0, 19.0);
                  try {
                    await controller.moveCamera(
                      center: Geographic(
                        lon: _mapCenter.longitude,
                        lat: _mapCenter.latitude,
                      ),
                      zoom: zoom,
                    );
                    _mapZoom = zoom;
                  } catch (_) {}
                },
              ),
              const SizedBox(height: 10),
              _MapControlButton(
                icon: Icons.remove,
                tooltip: 'Zoom out',
                onPressed: () async {
                  final controller = _mapController;
                  if (controller == null) return;
                  final zoom = (_mapZoom - 1).clamp(3.0, 19.0);
                  try {
                    await controller.moveCamera(
                      center: Geographic(
                        lon: _mapCenter.longitude,
                        lat: _mapCenter.latitude,
                      ),
                      zoom: zoom,
                    );
                    _mapZoom = zoom;
                  } catch (_) {}
                },
              ),
              const SizedBox(height: 10),
              _MapControlButton(
                icon: Icons.my_location,
                tooltip: 'My location',
                busy: _locating,
                onPressed: _goToMyLocation,
              ),
              // Compass needle. The needle rotates with the live
              // bearing and always points north on screen; tapping
              // it faces the map north again.
              const SizedBox(height: 10),
              ValueListenableBuilder<double>(
                valueListenable: _bearing,
                builder: (context, bearing, _) => _MapControlButton(
                  icon: Icons.navigation,
                  iconRotation: -bearing * math.pi / 180,
                  tooltip: 'Compass — north up',
                  onPressed: _resetBearing,
                ),
                ),
            ],
          ),
        ),
        // Basemap attribution (ⓘ button, bottom-left above the sheet):
        // the preview's map carries its attribution as a small
        // corner button, and the preview has no Standard/Satellite
        // pill — the pill is gone, so this spot is free. Tapping
        // opens the fallback layer's attribution page, or states
        // the Meta credit. When the sheet is hidden the full chip
        // shows centred at the bottom instead.
        if (!_sheetHidden)
          Positioned(
            left: 16,
            bottom: mapControlsBottomOffset(sheetHidden: _sheetHidden),
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(999),
              elevation: 4,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _onAttributionTap(
                  dark: scheme.brightness == Brightness.dark,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.info_outline,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        // Basemap attribution: visible whenever the sheet is hidden
        // (when shown, the ⓘ button above carries it).
        if (_sheetHidden)
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: _attributionChip(
                dark: scheme.brightness == Brightness.dark,
              ),
            ),
          ),
        // Stop card, floating over the map in the upper area
        // (Steven, Nov 7: not docked at the bottom above the
        // sheet). It pins just below the top-right control cluster
        // and floats clear of both the cluster and the peeked
        // sheet — same card, same content, only the position
        // changed. It stays put whether the sheet is shown or
        // hidden; a plain map tap or the X still dismisses it.
        if (_selectedStopIndex != null)
          Positioned(
            left: 16,
            right: 16,
            top: kMapStopCardTop,
            child: _stopCard(),
          ),
        // Draggable bottom sheet: Peek / Half ONLY (no Full).
        // Wrapped in Offstage (never removed from the tree) so the
        // logo toggle hides it without losing any state: same
        // content, same snap size when it comes back. Offstage
        // children take no hit tests, so the hidden sheet never
        // steals map gestures.
        Offstage(
          offstage: _sheetHidden,
          child: DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.20,
            minChildSize: 0.20,
            maxChildSize: 0.62,
            snap: true,
            snapSizes: const [0.20, 0.55],
            builder: (context, scrollController) {
              _sheetScrollController = scrollController;
              return CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowUp):
                      () => _snapSheet(_SheetSnap.half),
                  const SingleActivator(LogicalKeyboardKey.arrowDown):
                      () => _snapSheet(_SheetSnap.peek),
                  const SingleActivator(LogicalKeyboardKey.home):
                      () => _snapSheet(_SheetSnap.peek),
                  const SingleActivator(LogicalKeyboardKey.end):
                      () => _snapSheet(_SheetSnap.half),
                },
                child: Focus(
                  focusNode: _sheetFocusNode,
                  child: GestureDetector(
                    onTapDown: (_) => _sheetFocusNode.requestFocus(),
                    child: Material(
                      color: scheme.surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(22),
                      ),
                      elevation: 8,
                      child: Column(
                        children: [
                          // Grab bar + snap label, CENTERED (the
                          // preview's sheet handle): the bar and
                          // the "HALF · DRAG DOWN TO COLLAPSE" /
                          // "PEEK · DRAG UP TO EXPAND" label sit
                          // on the sheet's centre line — the old
                          // row pushed them left because the
                          // attribution chip shared the row.
                          // Tap cycles Peek <-> Half; dragging the
                          // handle drives the sheet (the body
                          // scroll area drags it too). The basemap
                          // attribution lives on the map now (the
                          // ⓘ button, bottom-left above the sheet).
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _cycleSheetSnap,
                            onVerticalDragUpdate: (details) {
                              if (!_sheetController.isAttached) return;
                              final height =
                                  MediaQuery.sizeOf(context).height;
                              if (height <= 0) return;
                              final next =
                                  (_sheetController.size -
                                          details.delta.dy / height)
                                      .clamp(0.20, 0.62);
                              _sheetController.jumpTo(next);
                            },
                            onVerticalDragEnd: (_) {
                              final size = _sheetController.isAttached
                                  ? _sheetController.size
                                  : 0.20;
                              _snapSheet(
                                size >= 0.375
                                    ? _SheetSnap.half
                                    : _SheetSnap.peek,
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                10,
                                20,
                                4,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: scheme.outline,
                                      borderRadius:
                                          BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          _sheetSnap == _SheetSnap.half
                                              ? 'HALF · DRAG DOWN TO COLLAPSE'
                                              : 'PEEK · DRAG UP TO EXPAND',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.5,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        _sheetSnap == _SheetSnap.half
                                            ? Icons.keyboard_arrow_down
                                            : Icons.keyboard_arrow_up,
                                        size: 16,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Fixed header: title + ETA • FARE +
                          // VERIFIED FARE badge — never scrolled.
                          _sheetFixedHeader(scheme),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: scrollController,
                              padding:
                                  const EdgeInsets.fromLTRB(20, 0, 20, 24),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: _sheetBodyWidgets(
                                  scheme: scheme,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Entering destination mode ("Plan a Trip") adopts the active
  // route's ends, so From/To match the preview card instead of
  // showing stale defaults (e.g. Sinait on top, Vigan City below).











}

/// Round dark control button used for zoom and my-location.
class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
    this.iconRotation,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool busy;
  // Clockwise rotation in radians for a needle icon (the compass
  // button); null = unrotated.
  final double? iconRotation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: const CircleBorder(side: BorderSide(color: Color(0xFF33373E))),
      elevation: 4,
      child: IconButton(
        icon: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : iconRotation == null
            ? Icon(icon)
            : Transform.rotate(angle: iconRotation!, child: Icon(icon)),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

/// EstudyanteGO logo toggle: same look as the sidebar header logo
/// mark (green rounded square, white bus icon — 0xFF16A34A),
/// sized to the floating controls column (48x48 like the other
/// buttons). Tapping it hides/shows the main-mode bottom sheet;
/// the button itself never hides with the sheet, so it is always
/// the way back.
class _LogoToggleButton extends StatelessWidget {
  const _LogoToggleButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF16A34A),
      borderRadius: BorderRadius.circular(14),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.directions_bus, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}

