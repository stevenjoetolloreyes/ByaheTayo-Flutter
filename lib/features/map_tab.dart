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

import 'admin_access.dart';
import 'bus_stops.dart';
import 'community_posts.dart';
import 'custom_routes.dart';
import 'fares_tab.dart';
import 'onboarding/auth_service.dart';
import 'osm_routing.dart';
import 'route_fare_overrides.dart';
import 'vehicle_categories.dart';

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
/// [extraStops] are the admin-added stops, reachable like any hub.
List<RouteInfo> routesFrom(
  double lat,
  double lng,
  String originName, [
  List<BusStop> extraStops = const [],
]) {
  final list = <RouteInfo>[];
  for (final hub in allHubs(extraStops)) {
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
///
/// Kept for its unit tests and the preview-rate path: the Map
/// ETA • FARE sheet itself no longer uses it (see
/// [resolveMapSheetFares]) — a pair with no admin-set or verified
/// fare shows "Fare not set" there instead of a computed number.
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

/// Map points for ordered via-stop hub names (unknown names are
/// skipped — never invented). Intermediate points only: the
/// caller supplies the origin and destination separately.
/// [busStops] are the admin-added stops the names may resolve to.
List<LatLng> viaPointsForHubNames(
  List<String> names, [
  List<BusStop> busStops = const [],
]) {
  final points = <LatLng>[];
  for (final name in names) {
    final hub = hubByName(name, busStops);
    if (hub != null) points.add(LatLng(hub.lat, hub.lng));
  }
  return points;
}

/// Via points for the OSRM fetch of a route: a custom route's own
/// effective waypoints (a drawn line wins over its named via
/// stops), else a seeded route's admin-override effective
/// waypoints, else none (the terminal Quezon Ave waypoint is
/// added inside _fetchRoadPath when no via points are given).
List<LatLng> routeViaPoints(
  RouteInfo route,
  RouteFareOverride? override, [
  List<BusStop> busStops = const [],
]) {
  final waypoints = effectiveRouteWaypoints(
    customRoute: route.customRoute,
    override: override,
    busStops: busStops,
  );
  return waypoints.map((w) => w.point).toList();
}

/// The fares the Map ETA • FARE sheet shows for a route — the
/// EFFECTIVE fare, in the same precedence the Fares tab uses
/// (see PopularRoute.applyOverride / effectiveStudentFare):
///
/// * an admin-added custom route's own fare / student fare;
/// * else an admin override's fare / student fare for the
///   built-in pair;
/// * else the user-verified fare from [knownBusFares];
/// * else null — the sheet shows "Fare not set", never a
///   computed number.
///
/// A blank student fare derives 20% off the effective regular
/// fare ([discountedFareOf]), exactly like the Fares tab. The
/// same precedence holds for the PWD and Senior Citizen fares.
({double? regular, double? discounted, double? pwd, double? senior})
resolveMapSheetFares({
  CustomRoute? customRoute,
  RouteFareOverride? override,
  required String from,
  required String to,
}) {
  final regular = customRoute?.fare ??
      override?.fare ??
      knownBusFare(from, to)?.toDouble();
  // The discounted fares exist only when a regular fare exists:
  // an admin-set student/PWD/Senior fare with no regular fare is
  // hidden, exactly like the Fares tab (PopularRoute's effective
  // fares return null when fare is null) — otherwise the Map
  // would show a discount with no fare to discount.
  final discounted = regular == null
      ? null
      : customRoute?.studentFare ??
            override?.studentFare ??
            discountedFareOf(regular);
  final pwd = regular == null
      ? null
      : customRoute?.pwdFare ??
            override?.pwdFare ??
            discountedFareOf(regular);
  final senior = regular == null
      ? null
      : customRoute?.seniorFare ??
            override?.seniorFare ??
            discountedFareOf(regular);
  return (regular: regular, discounted: discounted, pwd: pwd, senior: senior);
}

/// Operator + vehicle for a Map route, for the sheet header (F8)
/// and the unset-fare estimate (F4): the custom route's own when
/// present, else the seeded route's from [popularRoutes], else
/// neither (a generic hub-to-hub route has no operator or vehicle
/// — nothing is invented).
({String? operator, String? vehicle}) mapRouteOperatorVehicle({
  CustomRoute? customRoute,
  required String from,
  required String to,
}) {
  if (customRoute != null) {
    return (operator: customRoute.operator, vehicle: customRoute.vehicle);
  }
  for (final route in popularRoutes) {
    if (route.from == from && route.to == to) {
      return (operator: route.operator, vehicle: route.vehicle);
    }
  }
  return (operator: null, vehicle: null);
}

/// The LTFRB estimate for a route whose fare is NOT set (F4): the
/// same formula fare the Fares breakdown sheet shows, at the
/// route's own vehicle rate (see [rateForVehicleString]) — null
/// when the vehicle has no table rate (Van / Tricycle) or the
/// vehicle is unknown, so the sheet shows "Fare not set" instead
/// of a wrong-rate number. The caller labels it an estimate.
double? mapSheetEstimateFare({
  required String? vehicle,
  required double roadKm,
}) {
  if (vehicle == null) return null;
  final rate = rateForVehicleString(vehicle);
  if (rate == null) return null;
  return computeFare(rate, roadKm, false).regular;
}

/// Label for the Map sheet's discounted-fare card (F6): the card
/// claims "-20%" ONLY when the student fare is derived (20% off
/// by construction); an admin-set student fare shows no
/// percentage — a set fare equal to the regular fare is NOT a
/// 20% discount (Steven's own ₱60 student on ₱60 regular).
String mapDiscountLabel({required bool studentFareSet}) =>
    studentFareSet ? 'DISCOUNTED' : 'DISCOUNTED -20%';

/// Origin for a Fares → Map jump whose From is not a hub
/// ('My location'): the jump's own coordinates win (the Fares
/// tab's device fix, J2), else the Map's own last position, else
/// the home hub. [isUserLocation] is true when the origin is a
/// real device position rather than the home hub.
({double lat, double lng, bool isUserLocation}) resolveJumpOrigin({
  double? jumpLat,
  double? jumpLng,
  LatLng? userPos,
  required Hub homeHub,
}) {
  if (jumpLat != null && jumpLng != null) {
    return (lat: jumpLat, lng: jumpLng, isUserLocation: true);
  }
  if (userPos != null) {
    return (
      lat: userPos.latitude,
      lng: userPos.longitude,
      isUserLocation: true,
    );
  }
  return (lat: homeHub.lat, lng: homeHub.lng, isUserLocation: false);
}

/// Transit ETA minutes for a route's preview (pre-OSRM fallback),
/// from the app's estimateTripMinutes model: mountain /
/// same-region rules from the two hubs. The origin is looked up
/// in the MERGED hub list (built-ins + admin-added stops), so an
/// admin-added stop as origin gets its real mountain/region rules
/// (F9 — the old code looked in `hubs` only and treated every
/// admin stop as non-mountain / other-region).
int previewMinutesForRoute({
  required RouteInfo route,
  List<BusStop> stops = const [],
  required TravelMode mode,
}) {
  final originHub = resolveHub(route.originName, stops);
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

/// Paint order for the stop pins on the map (pure): the
/// intermediate stops first, then the Start pin, then the End
/// pin last — so the route's endpoints always paint ON TOP.
/// A saved waypoint sitting almost exactly on the origin (e.g.
/// Steven's Point 1, tapped next to Cabugao) used to hide the
/// Start pin underneath it; the End pin is the other end of the
/// "Start to End" span Steven asked for (Nov 7, 19:39), so it
/// paints last too. The pin NUMBERS never change — only the
/// paint order does — so taps still select the right stop.
List<MapStopPin> orderStopPinsForMarkers(List<MapStopPin> pins) {
  if (pins.length <= 2) return List.of(pins);
  return [
    ...pins.sublist(1, pins.length - 1),
    pins.first,
    pins.last,
  ];
}

/// Padding for a route fit so the whole route lands in the map
/// area VISIBLE above the draggable sheet (pure): the sheet
/// covers [sheetFraction] of the screen height from the bottom,
/// so the fit's bottom inset must clear it on top of the 80 px
/// base margin. The old fit used EdgeInsets.all(80) against the
/// FULL viewport — with the sheet at Half (0.55) the route's
/// southern end landed behind the sheet, so the End pin was
/// off-screen even though the fit had run (Steven's 19:36
/// screenshot: pins 2 and 4 visible near Cabugao, End pin 5
/// hidden below the sheet edge).
EdgeInsets routeFitPadding({
  required double screenHeight,
  required double sheetFraction,
}) =>
    EdgeInsets.fromLTRB(80, 80, 80, 80 + screenHeight * sheetFraction);

/// Centre the tile probe on: the midpoint of the active route
/// (origin → destination) when a route is selected, otherwise
/// the current camera centre. Pure, so the choice is testable.
/// The old probe always used the camera centre, which at style
/// load is still the init centre (16.9, 121.05 — central Luzon),
/// so the probed tile was not even a viewport tile for the
/// Cabugao → Vigan route (Steven's phone, Nov 7, 22:10). The
/// midpoint sits on the route corridor, so the probed tiles are
/// the ones the map actually needs.
LatLng mapProbeCenter({
  LatLng? origin,
  Hub? dest,
  required LatLng currentCenter,
}) {
  if (origin == null || dest == null) return currentCenter;
  return LatLng(
    (origin.latitude + dest.lat) / 2,
    (origin.longitude + dest.lng) / 2,
  );
}

/// One map line layer, as data: the points to draw, its colour,
/// its width, and whether it is the solid road shape or the
/// dashed direct fallback. Value equality (LatLng compares by
/// value) lets the state memoize the layer list: while the spec
/// is unchanged the previous PolylineLayer list instance is
/// returned untouched, so the maplibre plugin's layer
/// reconciler sees no change and never re-adds a layer.
class MapLineLayerSpec {
  const MapLineLayerSpec({
    required this.points,
    required this.color,
    required this.solid,
    this.width = 6,
  });

  /// Points of the line, in draw order.
  final List<LatLng> points;

  /// Line colour (green = saved route, amber = draft being drawn).
  final Color color;

  /// True = solid road shape; false = dashed direct line.
  final bool solid;

  /// Line width in logical pixels (int: PolylineLayer takes int).
  final int width;

  @override
  bool operator ==(Object other) =>
      other is MapLineLayerSpec &&
      listEquals(points, other.points) &&
      color == other.color &&
      solid == other.solid &&
      width == other.width;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(points), color, solid, width);
}

/// The map's line layers, as pure data — slot 0 is ALWAYS the
/// saved route line (green), and the draft line (amber) is an
/// extra slot that exists ONLY while the admin is actively
/// drawing AND has tapped at least one point. Stable slots
/// matter: the maplibre plugin reconciles layers by index, and
/// the old code REPLACED slot 0's content on every draw-mode
/// enter/exit (amber draft in, green route back out) and rebuilt
/// a fresh layer list on every rebuild — the plugin's
/// remove+add is un-awaited, so the pair raced and orphaned
/// stale native layers: the green dashed direct line and the
/// amber draft line Steven saw lingering on his phone
/// (Nov 7, 19:17) after the mode was closed and the road shape
/// had arrived. With stable slots, entering/exiting draw mode
/// only grows/shrinks the list at the trailing slot, and the
/// route line never changes identity.
///
/// No amber line is ever drawn from an empty draft: with zero
/// tapped points there is nothing the admin drew, so a straight
/// origin→destination amber line would invent a line the admin
/// never tapped. A pre-filled draft (saved drawn waypoints /
/// named via stops — the same points the route line uses) counts
/// as tapped points, so a route with a saved direction still
/// shows its draft on enter.
///
/// The stop-highlight branch (tapped stop → destination lights
/// up) is preserved exactly: the same four layers, same widths,
/// same colours — only expressed as specs. It never runs in
/// draw mode (entering draw mode clears the selection).
///
/// [roadLoading] (Sinait → Cabugao, Nov 7, 20:40): the new
/// route's road shape is still loading — draw NO route line.
/// The old route's line is gone the instant the route changes
/// (the caller nulls _roadPoints and sets roadLoading), so the
/// layer list transitions exactly once per fetch (nothing →
/// solid shape, or nothing → dashed on failure) instead of
/// twice (old solid → dashed → new solid). Two transitions in
/// quick succession are what let the plugin's un-awaited
/// remove+add orphan the previous route's line: the sheet
/// showed Sinait → Cabugao while the map still drew the
/// Cabugao → Vigan line. The draft slot (if any) is the admin's
/// in-progress work and is NOT suppressed by roadLoading.
List<MapLineLayerSpec> mapLineLayers({
  required List<LatLng> routePoints,
  required bool routeSolid,
  required int? selectedStopIndex,
  required List<RouteStop> routeStops,
  required List<LatLng>? roadPoints,
  required bool drawMode,
  required List<RouteWaypoint> draftWaypoints,
  required LatLng draftOrigin,
  required LatLng draftDest,
  required List<LatLng>? draftRoadPoints,
  bool roadLoading = false,
}) {
  const green = Color(0xFF16A34A);
  const amber = Color(0xFFF59E0B);
  final layers = <MapLineLayerSpec>[];
  // Slot 0: the saved route line, always present when a route
  // is active — including in draw mode, as the reference under
  // the draft being drawn. Omitted entirely while the new
  // route's road shape is loading (roadLoading): no line for
  // the wrong route is ever drawn, not even briefly.
  if (!roadLoading) {
    if (drawMode) {
      layers.add(
        MapLineLayerSpec(
          points: routePoints,
          color: green,
          solid: routeSolid,
        ),
      );
    } else if (selectedStopIndex != null &&
        routeStops.isNotEmpty &&
        roadPoints != null &&
        roadPoints.length >= 2) {
      final stop = routeStops[
          selectedStopIndex.clamp(0, routeStops.length - 1)];
      final split = splitPathAt(roadPoints, stop.pathIndex);
      layers.addAll([
        // Earlier part: dimmed to 0.15.
        MapLineLayerSpec(
          points: split.before,
          color: green.withValues(alpha: 0.15),
          solid: true,
        ),
        // Remaining part: soft glow + white casing + wide
        // light-green core.
        MapLineLayerSpec(
          points: split.after,
          color: green.withValues(alpha: 0.25),
          solid: true,
          width: 16,
        ),
        MapLineLayerSpec(
          points: split.after,
          color: Colors.white,
          solid: true,
          width: 11,
        ),
        MapLineLayerSpec(
          points: split.after,
          color: const Color(0xFF4ADE80),
          solid: true,
          width: 7,
        ),
      ]);
    } else {
      layers.add(
        MapLineLayerSpec(
          points: routePoints,
          color: green,
          solid: routeSolid,
        ),
      );
    }
  }
  // Trailing slot, draw mode only and only once the admin has
  // tapped (or the draft was pre-filled from a saved direction):
  // the amber draft line. An empty draft draws NOTHING.
  if (drawMode && draftWaypoints.isNotEmpty) {
    final direct = [
      draftOrigin,
      ...draftWaypoints.map((w) => w.point),
      draftDest,
    ];
    final points = draftRoadPoints ?? direct;
    layers.add(
      MapLineLayerSpec(
        points: points,
        color: amber,
        solid: draftRoadPoints != null,
      ),
    );
  }
  return layers;
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
    this.fareOverrideRepository,
    this.busStopRepository,
    this.visible = true,
  });

  final AuthUser? currentUser;

  /// Admin-added routes source. Null = no custom routes are loaded
  /// (e.g. tests, or Firebase not configured and no local repo).
  final CustomRouteRepository? customRouteRepository;

  /// Admin-set fare / student fare / direction overrides for the
  /// built-in routes. Null = no overrides are applied.
  final RouteFareOverrideRepository? fareOverrideRepository;

  /// Admin-added bus stops source. Null = only the 16 built-in
  /// hubs are known (e.g. tests, or Firebase not configured and
  /// no local repo).
  final BusStopRepository? busStopRepository;

  /// True while this tab is the selected one (the shell passes
  /// `selectedIndex == 3`). Used only to retry the tile sources
  /// when the user returns to a map that failed to load — e.g.
  /// after switching from a network that blocks the tile CDNs
  /// to one that does not. Defaults to true so tests and other
  /// callers keep the old behaviour.
  final bool visible;

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
  // Fallback-load timer: verifies the CartoDB fallback style
  // actually loads after a switch. The Meta-style watchdog
  // above only covers Meta; once the fallback fires, nothing
  // verified the fallback — if its onStyleLoaded never fires
  // (e.g. setStyle lost while the map is offstage in the
  // IndexedStack), _styleLoaded stays true from Meta, the mode
  // is already cartoFallback (so every later switch is a
  // no-op), and the app believes it is on the fallback while
  // the map is still on the broken Meta style, forever. If
  // this timer fires, both tile sources have failed and the
  // "couldn't load the map" banner shows.
  Timer? _fallbackLoadTimer;
  // True once the CartoDB fallback style has reported loaded
  // (cleared on every switch to it). Separate from
  // _styleLoaded, which stays true from the Meta style.
  bool _fallbackLoaded = false;
  // True once both tile sources have failed (Meta probe failed
  // and the CartoDB fallback style never loaded or its tiles
  // never arrived — Steven's phone, Nov 7, 20:08–20:13: blank
  // map in both themes, current build, data available). Shows
  // the "couldn't load the map" banner with a Retry button.
  // Cleared by any successful tile probe or a style switch.
  bool _tilesFailed = false;
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
  // The admin override for the active route, if any — set together
  // with [_activeRoute] by [_resolveRoute]. Drives the sheet's
  // effective fare and the route's via-stops line. Null for
  // admin-added routes (they carry their own fare + via stops)
  // and for built-in routes with no stored override.
  RouteFareOverride? _activeRouteOverride;
  // Admin-added routes (Add Route) and admin-set overrides for the
  // built-in routes, loaded in [_ensureRouteData] before every
  // route selection so an edit made in the Fares tab reaches the
  // map without a restart. Reads are for everyone; writes stay
  // admin-only (repository-side allowlist).
  List<CustomRoute> _customRoutes = [];
  Map<String, RouteFareOverride> _fareOverrides = {};
  // Admin-added bus stops, loaded in [_ensureRouteData] before
  // every route selection so a stop added in the Fares tab is a
  // From/To endpoint and a via stop on the map without a restart.
  List<BusStop> _busStops = [];
  // ---- Line maker (admin-only) ----
  // Draw mode: the admin taps points on the map in order and the
  // line draws live through them; add-stop mode: one tap places a
  // new bus stop, then the name form opens. Both hide the sheet
  // (restored on exit) and suppress the stop card + attribution
  // chip while active. The draft starts pre-filled from the
  // active route's current effective direction, so editing a line
  // never starts from an empty map.
  bool _lineMakerActive = false;
  bool _lineMakerAddStop = false;
  // Set Start/End mode (admin only, Steven Nov 7, 20:52: "Yung
  // Start at End mismo, ako maglalagay"): two map taps place
  // the route's Start pin, then its End pin. The points become
  // named bus stops (he names each one) and the map jumps to
  // the new route between them — no coordinates are ever stored
  // raw, and no stop name is ever invented. Like the line
  // maker it hides the sheet (restored on exit) and suppresses
  // the stop card while active. Mutually exclusive with the
  // line maker: entering one exits the other.
  bool _setEndpointsActive = false;
  LatLng? _pendingStart;
  LatLng? _pendingEnd;
  List<RouteWaypoint> _draftPoints = const [];
  List<LatLng>? _draftRoadPoints;
  // Memoized line-layer spec + the PolylineLayer list built from
  // it (see _routePolylineLayers). Returning the identical list
  // while the spec is unchanged keeps the maplibre plugin from
  // re-adding layers on every rebuild — the churn that orphaned
  // stale green/amber lines on Steven's phone (Nov 7, 19:17).
  List<MapLineLayerSpec>? _lineLayerSpecs;
  List<PolylineLayer> _lineLayers = const [];
  int? _selectedDraftIndex;
  int _draftRequestId = 0;
  bool _lineMakerSaving = false;
  // Road-following shape from OSRM (null = still loading or failed;
  // the dashed direct line shows until real geometry arrives).
  List<LatLng>? _roadPoints;
  // True while a road fetch is in flight for the CURRENT route
  // (set with the route change, cleared when the fetch settles).
  // While true, _routePolylineLayers draws NO line: the old
  // route's line is gone the instant the route changes, and the
  // layer list transitions exactly once per fetch — the stale
  // line Steven saw on Sinait → Cabugao (Nov 7, 20:40) came
  // from two transitions in quick succession (old solid →
  // dashed → new solid) through the plugin's un-awaited
  // remove+add reconciliation.
  bool _roadLoading = false;
  double _routeDurationSec = 0;
  // Google's own route length (km) from routes.distanceMeters.
  // 0 = not loaded yet; the bottom bar then falls back to the
  // app's roadKm estimate for the minutes fraction.
  double _routeDistanceKm = 0;
  int _roadRequestId = 0;
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
    mapLineMakerRequest.addListener(_onLineMakerRequest);
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
  @override
  void didUpdateWidget(covariant MapTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.visible || !widget.visible) return;
    // Returning to the tab after the tiles failed (e.g. the
    // user switched from a network that blocks the tile CDNs to
    // one that does not): retry the tile sources so the map
    // recovers without an app restart.
    if (_tilesFailed) {
      _retryTileSources();
      return;
    }
    // Returning to the tab with a map the app BELIEVES is fine:
    // re-validate it. The one-shot probe from style load can
    // pass on a few small tiles while the viewport tiles never
    // arrive (Steven's phone, Nov 7, 22:10 — blank map, no
    // banner, no Retry, because _tilesFailed was never set and
    // this branch used to do nothing). A passing re-probe
    // cancels the watchdog and nothing changes; a failing one
    // re-arms it, so the CartoDB fallback fires in 10 s. Only
    // on a visible transition — one probe per return, never on
    // every build. On a fast connection the re-probe passes in
    // under a second; on a slow one it costs a few tile
    // downloads and may flip a cache-rendered map to the
    // fallback when the network cannot serve fresh tiles —
    // the fallback is a working map, not a blank one.
    if (_styleMode == _MapStyleMode.meta && _styleLoaded) {
      _probeMetaTiles(armWatchdogOnFailure: true);
    }
  }

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
    _fallbackLoaded = false;
    _tilesFailed = false; // A style switch restarts the flow.
    _fallbackLoadTimer?.cancel();
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
    _fallbackLoaded = false;
    controller.setStyle(cartoFallbackStyleJson(dark: _fallbackDark));
    // The fallback style still has to load: if it never reports
    // loaded within 8 s, both tile sources have failed — show
    // the banner instead of sitting on a blank map silently.
    _fallbackLoadTimer?.cancel();
    _fallbackLoadTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted ||
          _styleMode != _MapStyleMode.cartoFallback ||
          _fallbackLoaded) {
        return;
      }
      setState(() => _tilesFailed = true);
    });
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

  /// Centre for the tile probes: the active route's midpoint
  /// when a route is selected, else the current camera centre
  /// (see [mapProbeCenter]).
  LatLng get _probeCenter => mapProbeCenter(
    origin: _activeRouteOrigin,
    dest: _activeRoute?.dest,
    currentCenter: _mapCenter,
  );

  /// Tile-reachability probe: fetches the Meta vector tiles
  /// under the probe centre (the active route's midpoint, so
  /// the probed tiles are the ones the map actually needs) —
  /// centre tile plus its east and south neighbours, all three
  /// required. If they arrive, the CDN is reachable from this
  /// phone — the native map's own tile requests can succeed
  /// too — so the tile watchdog is cancelled and the Meta map
  /// stays. If they fail or time out, the watchdog is left
  /// armed and fires the CartoDB fallback at 10 s — unless
  /// [armWatchdogOnFailure] (tab-return re-validation) asks
  /// for a fresh 10 s watchdog, because the first probe's
  /// watchdog was already cancelled. A probe result is ignored
  /// if the style changed meanwhile (theme switch) or the
  /// widget is gone. Returns true when the probe passed.
  Future<bool> _probeMetaTiles({bool armWatchdogOnFailure = false}) async {
    final styleUrl = _activeStyleUrl;
    final zoom = _mapZoom.floor();
    final centre = _probeCenter;
    final reachable = await probeMetaVectorTiles(
      lat: centre.latitude,
      lng: centre.longitude,
      z: zoom,
    );
    if (!mounted ||
        _styleMode != _MapStyleMode.meta ||
        _activeStyleUrl != styleUrl) {
      return false;
    }
    if (!reachable) {
      if (armWatchdogOnFailure) _armTileWatchdog();
      return false;
    }
    _tileWatchdogTimer?.cancel();
    _tileWatchdogTimer = null;
    if (_tilesFailed) setState(() => _tilesFailed = false);
    return true;
  }

  /// Tile-reachability probe for the CartoDB fallback: fetches
  /// the fallback tiles under the probe centre (centre tile
  /// plus its east and south neighbours, all three required).
  /// If they arrive, the fallback tiles are reachable — clear
  /// the failed state. If they fail or time out, both tile
  /// sources are unreachable and the banner shows. A probe
  /// result is ignored if the style changed meanwhile (theme
  /// switch, or a retry back to Meta) or the widget is gone.
  Future<void> _probeCartoTiles() async {
    final dark = _fallbackDark;
    final zoom = _mapZoom.floor();
    final centre = _probeCenter;
    final reachable = await probeCartoTiles(
      lat: centre.latitude,
      lng: centre.longitude,
      z: zoom,
      dark: dark,
    );
    if (!mounted || _styleMode != _MapStyleMode.cartoFallback) {
      return;
    }
    if (!reachable) {
      setState(() => _tilesFailed = true);
      return;
    }
    if (_tilesFailed) setState(() => _tilesFailed = false);
  }

  /// Retries the tile sources from scratch: back to the Meta
  /// style (the primary), timers re-armed, banner cleared. The
  /// normal flow re-runs from there — style timer, watchdog,
  /// probe, fallback. Called by the banner's Retry button and
  /// when the user returns to the tab after a failure.
  void _retryTileSources() {
    final controller = _mapController;
    if (!mounted || controller == null) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final metaUrl = metaMapStyleUrl(dark: dark);
    _styleLoadTimer?.cancel();
    _tileWatchdogTimer?.cancel();
    _fallbackLoadTimer?.cancel();
    _styleMode = _MapStyleMode.meta;
    _activeStyleUrl = metaUrl;
    _styleLoaded = false;
    _fallbackLoaded = false;
    _lastStyleDark = dark;
    if (_tilesFailed) {
      setState(() => _tilesFailed = false);
    }
    _armStyleFallbackTimer();
    controller.setStyle(metaUrl);
  }

  /// "Couldn't load the map" banner (shown only when
  /// [_tilesFailed]): a card beside the top-right controls with
  /// a short message and a Retry button that re-attempts the
  /// Meta style. English, matching the app's UI language.
  Widget _tilesFailedBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('map-tiles-failed-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.3),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 20,
            color: Color(0xFFF7B955),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Couldn't load the map",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Check your connection, then try again.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey('map-tiles-retry'),
            onPressed: _retryTileSources,
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
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
    if (_styleMode != _MapStyleMode.meta) {
      // The CartoDB fallback style loaded: its tiles still have
      // to arrive — probe one fallback tile under the camera.
      // A late load (after the 8 s fallback timer fired) still
      // gets validated here and can clear the banner.
      _fallbackLoaded = true;
      _fallbackLoadTimer?.cancel();
      _probeCartoTiles();
      return;
    }
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

  /// Loads the admin-added routes + fare overrides (both repos
  /// never throw — a failure returns the local cache). Called
  /// before every route selection so an edit made in the Fares
  /// tab reaches the map without a restart. A slow load is
  /// bounded at 5 s and keeps the current data, so selection
  /// never stalls on a bad connection.
  Future<void> _ensureRouteData() async {
    final customRepo = widget.customRouteRepository;
    final overrideRepo = widget.fareOverrideRepository;
    final stopRepo = widget.busStopRepository;
    if (customRepo == null && overrideRepo == null && stopRepo == null) {
      return;
    }
    try {
      final loaded = await Future.wait<dynamic>([
        customRepo?.loadAll() ??
            Future<List<CustomRoute>>.value(const []),
        overrideRepo?.loadAll() ??
            Future<Map<String, RouteFareOverride>>.value(const {}),
        stopRepo?.loadAll() ?? Future<List<BusStop>>.value(const []),
      ]).timeout(
        const Duration(seconds: 5),
        onTimeout: () => <dynamic>[_customRoutes, _fareOverrides, _busStops],
      );
      if (!mounted) return;
      setState(() {
        _customRoutes = loaded[0] as List<CustomRoute>;
        _fareOverrides = loaded[1] as Map<String, RouteFareOverride>;
        _busStops = loaded[2] as List<BusStop>;
      });
    } catch (_) {
      // Keep whatever is in state — the generated route still
      // draws, and the next selection retries the load.
    }
  }

  /// Resolves the route for an origin + destination after
  /// refreshing the route data: an admin-added custom route with
  /// the same From|To wins (its own fare, student fare, and
  /// via-stops line); else the generated hub route, with any
  /// admin override for its From|To pair (fare / student fare /
  /// via stops). Returns the route, the override for a generated
  /// route (null for custom routes), and the via points for the
  /// OSRM fetch. A GPS origin ('Your location') never matches a
  /// custom route — those are hub-named only.
  Future<
    ({
      RouteInfo? route,
      RouteFareOverride? override,
      List<LatLng> via,
    })
  >
  _resolveRoute({
    required String originName,
    required double oLat,
    required double oLng,
    required Hub destHub,
  }) async {
    await _ensureRouteData();
    final custom = matchCustomRoute(_customRoutes, originName, destHub.name);
    if (custom != null) {
      final route = customRouteToRouteInfo(custom, _busStops);
      return (
        route: route,
        override: null,
        via: routeViaPoints(route, null, _busStops),
      );
    }
    final matches = routesFrom(
      oLat,
      oLng,
      originName,
      _busStops,
    ).where((r) => r.dest.name == destHub.name);
    final route = matches.isEmpty ? null : matches.first;
    if (route == null) {
      return (route: null, override: null, via: const <LatLng>[]);
    }
    final override =
        _fareOverrides[seededRouteKey(originName, destHub.name)];
    return (
      route: route,
      override: override,
      via: routeViaPoints(route, override, _busStops),
    );
  }

  /// A Fares "Find routes" / "Show direction on Map" sets
  /// [faresMapJump]; draw that hub-to-hub route (direction line +
  /// ETA • FARE sheet, snapped to Half so the route details show),
  /// then clear it so the same route can be jumped to again. A
  /// 'My location' origin resolves to the device position when
  /// known, else the home hub — the same rule as the hub-tap flow.
  /// Non-hub names are ignored: the tab opens with no route rather
  /// than drawing a line to a place the app does not know.
  void _onFaresJump() async {
    final jump = faresMapJump.value;
    if (jump == null) return;
    faresMapJump.value = null;
    if (!mounted) return;
    // Load the stops FIRST: a stop added in the Fares tab moments
    // ago must match below, and the Map tab's in-state list may
    // predate it. _resolveRoute loads again — harmless (cached).
    await _ensureRouteData();
    if (!mounted) return;
    // Match against the merged hub list: a From/To may be an
    // admin-added bus stop, not one of the 16 built-in hubs.
    final destMatches = allHubs(_busStops).where((h) => h.name == jump.to);
    if (destMatches.isEmpty) return;
    final destHub = destMatches.first;
    final originMatches = allHubs(_busStops).where((h) => h.name == jump.from);
    final double oLat;
    final double oLng;
    final String oName;
    if (originMatches.isNotEmpty) {
      final originHub = originMatches.first;
      oLat = originHub.lat;
      oLng = originHub.lng;
      oName = originHub.name;
    } else {
      // J2: the jump's own device coordinates win; else the Map's
      // own last position; else the home hub.
      final origin = resolveJumpOrigin(
        jumpLat: jump.fromLat,
        jumpLng: jump.fromLng,
        userPos: _userPos == null
            ? null
            : LatLng(_userPos!.latitude, _userPos!.longitude),
        homeHub: hubs[_homeHub],
      );
      oLat = origin.lat;
      oLng = origin.lng;
      oName = origin.isUserLocation ? 'Your location' : hubs[_homeHub].name;
    }
    final resolved = await _resolveRoute(
      originName: oName,
      oLat: oLat,
      oLng: oLng,
      destHub: destHub,
    );
    if (!mounted) return;
    final route = resolved.route;
    setState(() {
      _activeRoute = route;
      _activeRouteOverride = resolved.override;
      _activeRouteOrigin = route == null ? null : LatLng(oLat, oLng);
      _roadPoints = null;
      _roadLoading = route != null;
      // J1: the previous route's OSRM totals are cleared, so the
      // sheet falls back to this route's estimate until the new
      // fetch succeeds — never the old route's distance/ETA.
      _routeDistanceKm = 0;
      _routeDurationSec = 0;
      _selectedStopIndex = null;
      _pendingStopIndex = null;
    });
    _refreshRouteStops();
    _resetSheetScroll();
    if (route != null) {
      // Fit for the Half sheet below: the sheet snaps to Half
      // right after, so the fit must already clear it — else
      // the End pin lands behind the sheet (Steven, Nov 7,
      // 19:36: End pin off-screen at Half).
      _fitActiveRoute(sheetFraction: 0.55);
      _fetchRoadPath(oLat, oLng, destHub, via: resolved.via);
      _snapSheet(_SheetSnap.half);
    }
  }

  @override
  void dispose() {
    communityMapJump.removeListener(_onCommunityJump);
    faresMapJump.removeListener(_onFaresJump);
    mapLineMakerRequest.removeListener(_onLineMakerRequest);
    WidgetsBinding.instance.removeObserver(this);
    _sheetController.removeListener(_onSheetExtentChanged);
    _styleLoadTimer?.cancel();
    _tileWatchdogTimer?.cancel();
    _fallbackLoadTimer?.cancel();
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
  /// back to zoom 15 afterwards, like before. [padding] insets
  /// the bounds in the viewport — the route fit passes the
  /// sheet-aware padding from [routeFitPadding] so the bounds
  /// land in the visible area above the sheet, not behind it.
  Future<void> _fitBounds(
    LatLng sw,
    LatLng ne, {
    EdgeInsets padding = const EdgeInsets.all(80),
  }) async {
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
        padding: padding,
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
  /// destination, padded so the bounds never degenerate) in the
  /// area VISIBLE above the draggable sheet — the bottom inset
  /// clears the sheet (see [routeFitPadding]), so the Start and
  /// End pins both land on screen instead of the End hiding
  /// behind the sheet at Half. Used by _selectHub / _onFaresJump
  /// and once when the native map is created, when a route
  /// selected before creation can finally fit. [sheetFraction]
  /// is the fraction the sheet WILL be at when the fit lands
  /// (the jump snaps to Half right after fitting); null = the
  /// sheet's current snap (Peek 0.20 / Half 0.55, same values
  /// as [_snapSheet]).
  void _fitActiveRoute({double? sheetFraction}) {
    final route = _activeRoute;
    final origin = _activeRouteOrigin;
    if (route == null || origin == null) return;
    final fraction =
        sheetFraction ??
        (_sheetSnap == _SheetSnap.half ? 0.55 : 0.20);
    _fitBounds(
      LatLng(
        math.min(origin.latitude, route.dest.lat) - 0.01,
        math.min(origin.longitude, route.dest.lng) - 0.01,
      ),
      LatLng(
        math.max(origin.latitude, route.dest.lat) + 0.01,
        math.max(origin.longitude, route.dest.lng) + 0.01,
      ),
      padding: routeFitPadding(
        screenHeight: MediaQuery.of(context).size.height,
        sheetFraction: fraction,
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
    return previewMinutesForRoute(
      route: route,
      stops: _busStops,
      mode: mode,
    );
  }



  /// mid-navigation ends that navigation (start again for the new
  /// destination).
  void _selectHub(Hub hub) async {
    final oLat = _userPos?.latitude ?? hubs[_homeHub].lat;
    final oLng = _userPos?.longitude ?? hubs[_homeHub].lng;
    final oName = _userPos != null ? 'Your location' : hubs[_homeHub].name;
    final resolved = await _resolveRoute(
      originName: oName,
      oLat: oLat,
      oLng: oLng,
      destHub: hub,
    );
    if (!mounted) return;
    final route = resolved.route;
    setState(() {
      _activeRoute = route;
      _activeRouteOverride = resolved.override;
      _activeRouteOrigin = route == null ? null : LatLng(oLat, oLng);
      _roadPoints = null;
      _roadLoading = route != null;
      // J1: the previous route's OSRM totals are cleared, so the
      // sheet falls back to this route's estimate until the new
      // fetch succeeds — never the old route's distance/ETA.
      _routeDistanceKm = 0;
      _routeDurationSec = 0;
      _selectedStopIndex = null;
      _pendingStopIndex = null;
    });
    _refreshRouteStops();
    _resetSheetScroll();
    if (route != null) {
      // Fit both endpoints, padded so the bounds never degenerate.
      _fitActiveRoute();
      _fetchRoadPath(oLat, oLng, hub, via: resolved.via);
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
      // OSRM routing unavailable — the fetch has settled, so
      // the dashed direct line shows (roadLoading off). The
      // re-sync re-asserts it once, same as the success path.
      // J1: the previous route's OSRM totals are cleared too, so
      // the sheet falls back to the new route's estimate instead
      // of showing the old route's distance/ETA forever.
      if (mounted) {
        setState(() {
          _roadLoading = false;
          _routeDistanceKm = 0;
          _routeDurationSec = 0;
        });
      }
      _resyncLineLayers(requestId);
      return;
    }
    // F1/F2: share the live geometry with the Fares tab (same
    // distance, ETA, and stops for this route).
    routeGeometryCache.put(
      routeGeometryKey(oLat: oLat, oLng: oLng, dest: dest, via: via),
      RouteGeometry.fromOsrm(result),
    );
    setState(() {
      _roadPoints = result.points;
      _roadLoading = false;
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
          viaHubNames: _activeRoute!.customRoute?.viaHubs ??
              _activeRouteOverride?.viaHubs ??
              const [],
          viaWaypoints: effectiveRouteWaypoints(
            customRoute: _activeRoute!.customRoute,
            override: _activeRouteOverride,
            busStops: _busStops,
          ),
          extraStops: _busStops,
        );
      }
    });
    _resyncLineLayers(requestId);
  }













  /// Re-asserts the current line layers once, on the next frame.
  /// The maplibre plugin reconciles layers by index with
  /// un-awaited remove+add, so a single update can be lost — and
  /// once the Dart list has settled on the new spec, the memo in
  /// [_routePolylineLayers] suppresses every later update (the
  /// spec is unchanged, so the plugin sees no change and the
  /// wrong line stays forever — the Sinait → Cabugao bug, Nov 7,
  /// 20:40: the sheet showed the new route while the map still
  /// drew the previous route's line). Busting the memo once
  /// makes the next build hand the plugin a fresh list for the
  /// SAME spec, re-applying the correct line. Guarded by the
  /// fetch's request id + route, so a newer route change wins
  /// and a stale callback never re-asserts an old line.
  void _resyncLineLayers(int requestId) {
    final route = _activeRoute;
    if (route == null) return;
    final originName = route.originName;
    final destName = route.dest.name;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || requestId != _roadRequestId) return;
      final current = _activeRoute;
      if (current == null ||
          current.originName != originName ||
          current.dest.name != destName) {
        return;
      }
      setState(() => _lineLayerSpecs = null);
    });
  }


  /// Via points for the active route's own line: the effective
  /// waypoints — a drawn line wins over the named via stops —
  /// otherwise none (the terminal Quezon Ave waypoint is added
  /// inside _fetchRoadPath).
  List<LatLng> _customRouteViaPoints(RouteInfo route) =>
      routeViaPoints(route, _activeRouteOverride, _busStops);








  /// Points + style for the active-route line. Solid = real
  /// OSRM road shape; dashed = direct-line fallback. When a stop
  /// is tapped, only the line from that stop to the destination
  /// lights up (soft glow + white casing + wide light-green core)
  /// while the earlier part dims; tapping the destination leaves
  /// nothing lit. Dismissing the card restores this normal
  /// standard-green line. One [PolylineLayer] per visual style
  /// (MapLibre styles a whole layer one colour/width, so the
  /// highlight is four layers drawn bottom-to-top, as before).
  /// Line layers for the map, via the stable-slot spec in
  /// [mapLineLayers] (see its doc comment for why the slots are
  /// stable). The returned list instance is cached while the
  /// spec is unchanged, so the maplibre plugin's layer
  /// reconciler sees identical layers and skips its remove+add
  /// cycle on rebuilds where nothing moved — the churn that
  /// orphaned stale green/amber lines on Steven's phone
  /// (Nov 7, 19:17). Entering/exiting draw mode only
  /// grows/shrinks the list at the trailing (draft) slot.
  List<PolylineLayer> _routePolylineLayers() {
    if (_activeRoute == null || _activeRouteOrigin == null) {
      _lineLayerSpecs = null;
      _lineLayers = const [];
      return const [];
    }
    final route = _activeRoute!;
    final origin = _activeRouteOrigin!;
    final dest = LatLng(route.dest.lat, route.dest.lng);
    // No road shape yet: the dashed fallback follows the custom
    // route's own via-stops instead of a straight origin→dest
    // line, so a Partas line already differs from a Dominion line.
    final via = _customRouteViaPoints(route);
    final routePoints = _roadPoints ?? [origin, ...via, dest];
    final drawMode = _lineMakerActive && !_lineMakerAddStop;
    final specs = mapLineLayers(
      routePoints: routePoints,
      routeSolid: _roadPoints != null,
      selectedStopIndex: _selectedStopIndex,
      routeStops: _routeStops,
      roadPoints: _roadPoints,
      drawMode: drawMode,
      draftWaypoints: _draftPoints,
      draftOrigin: origin,
      draftDest: dest,
      draftRoadPoints: _draftRoadPoints,
      roadLoading: _roadLoading,
    );
    if (_lineLayerSpecs != null &&
        listEquals(_lineLayerSpecs, specs)) {
      return _lineLayers;
    }
    _lineLayerSpecs = specs;
    _lineLayers = [
      for (final spec in specs)
        PolylineLayer(
          polylines: [
            Feature<LineString>(
              geometry: LineString(
                spec.points
                    .expand((p) => [p.longitude, p.latitude])
                    .toList()
                    .positions(Coords.xy),
              ),
            ),
          ],
          color: spec.color,
          width: spec.width,
          dashArray: spec.solid ? null : const [24, 12],
        ),
    ];
    return _lineLayers;
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
    final markers = <Marker>[];
    // Set Start/End mode: the route pins hide and the two
    // pending pins show instead (green numbered circles, 1 =
    // Start, 2 = End — the same numbers the new route's stops
    // list will show). They carry NO GestureDetector — taps
    // fall through to the map click handler, which places the
    // pins (see _onSetEndpointsMapTap).
    if (_setEndpointsActive) {
      if (_pendingStart != null) {
        markers.add(
          Marker(
            point: Geographic(
              lon: _pendingStart!.longitude,
              lat: _pendingStart!.latitude,
            ),
            size: const Size(44, 44),
            child: Center(child: _numberedPin(1, selected: false)),
          ),
        );
      }
      if (_pendingEnd != null) {
        markers.add(
          Marker(
            point: Geographic(
              lon: _pendingEnd!.longitude,
              lat: _pendingEnd!.latitude,
            ),
            size: const Size(44, 44),
            child: Center(child: _numberedPin(2, selected: false)),
          ),
        );
      }
    } else if (_lineMakerActive && !_lineMakerAddStop) {
      // Draw mode: the route pins hide and the draft pins show
      // instead (amber numbered circles). They carry NO
      // GestureDetector — taps fall through to the map click
      // handler, whose 100 m guard opens the tapped point's
      // actions (see _onLineMakerMapTap). Add-stop mode keeps the
      // route pins: the route is the context for placing the stop.
      for (var i = 0; i < _draftPoints.length; i++) {
        markers.add(
          Marker(
            point: Geographic(
              lon: _draftPoints[i].lng,
              lat: _draftPoints[i].lat,
            ),
            size: const Size(44, 44),
            child: Center(
              child: _numberedPin(
                i + 1,
                selected: _selectedDraftIndex == i,
                draft: true,
              ),
            ),
          ),
        );
      }
    } else {
      // Start + End paint last (on top) — see
      // [orderStopPinsForMarkers]: a waypoint tapped near the
      // origin must not hide the Start pin underneath it.
      for (final pin in orderStopPinsForMarkers(
        routeStopPins(_routeStops, _selectedStopIndex),
      )) {
        markers.add(
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
        );
      }
    }
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
        viaHubNames: route.customRoute?.viaHubs ??
            _activeRouteOverride?.viaHubs ??
            const [],
        viaWaypoints: effectiveRouteWaypoints(
          customRoute: route.customRoute,
          override: _activeRouteOverride,
          busStops: _busStops,
        ),
        extraStops: _busStops,
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

  // ---- Line maker (admin-only) ----

  /// A Fares "+ Add bus stop" tap (or a Draw line request) sets
  /// [mapLineMakerRequest]; enter the requested mode, then clear
  /// it so the same request can be made again.
  void _onLineMakerRequest() {
    final request = mapLineMakerRequest.value;
    if (request == null) return;
    mapLineMakerRequest.value = null;
    if (!mounted || !isAdminUser(widget.currentUser)) return;
    if (request.addStop) {
      _enterAddStopMode();
    } else if (request.drawLine) {
      _enterDrawLineMode();
    }
  }

  /// Enters draw-line mode for the active route (admin-only,
  /// sheet header button). Requires an active route: the draft
  /// starts pre-filled from that route's current effective
  /// direction. When the route has no saved direction the draft
  /// is empty and NO amber line is drawn until the admin taps —
  /// the green route line stays visible as the reference (a
  /// straight origin→destination amber line would invent a line
  /// the admin never tapped). The sheet hides (restored on
  /// exit) and the stop card dismisses.
  void _enterDrawLineMode() {
    if (!isAdminUser(widget.currentUser)) return;
    if (_setEndpointsActive) _exitSetEndpointsMode();
    final route = _activeRoute;
    final origin = _activeRouteOrigin;
    if (route == null || origin == null) {
      _snack('Pick a route first, then draw its line.');
      return;
    }
    final draft = effectiveRouteWaypoints(
      customRoute: route.customRoute,
      override: _activeRouteOverride,
      busStops: _busStops,
    );
    setState(() {
      _lineMakerActive = true;
      _lineMakerAddStop = false;
      _draftPoints = draft;
      _draftRoadPoints = null;
      _selectedDraftIndex = null;
      _selectedStopIndex = null;
      _sheetHidden = true;
    });
    _refreshDraftOsrm();
  }

  /// Enters add-stop mode (from the Fares "+ Add bus stop" chip):
  /// one map tap places the new stop, then the name form opens.
  /// No active route is needed — the stop is placed, not drawn.
  void _enterAddStopMode() {
    if (!isAdminUser(widget.currentUser)) return;
    if (_setEndpointsActive) _exitSetEndpointsMode();
    setState(() {
      _lineMakerActive = true;
      _lineMakerAddStop = true;
      _draftPoints = const [];
      _draftRoadPoints = null;
      _selectedDraftIndex = null;
      _selectedStopIndex = null;
      _sheetHidden = true;
    });
  }

  /// Leaves either line-maker mode and restores the sheet. The
  /// draft is discarded — nothing is saved unless the admin
  /// tapped Save line / saved the stop.
  void _exitLineMaker() {
    if (!_lineMakerActive) return;
    setState(() {
      _lineMakerActive = false;
      _lineMakerAddStop = false;
      _draftPoints = const [];
      _draftRoadPoints = null;
      _selectedDraftIndex = null;
      _sheetHidden = false;
    });
  }

  /// Enters Set Start/End mode (admin-only, sheet header
  /// button). No active route is needed — the taps CREATE the
  /// route. The sheet hides (restored on exit) and the stop
  /// card dismisses; the line maker exits if it was active.
  void _enterSetEndpointsMode() {
    if (!isAdminUser(widget.currentUser)) return;
    if (_lineMakerActive) _exitLineMaker();
    setState(() {
      _setEndpointsActive = true;
      _pendingStart = null;
      _pendingEnd = null;
      _selectedStopIndex = null;
      _pendingStopIndex = null;
      _sheetHidden = true;
    });
  }

  /// Leaves Set Start/End mode and restores the sheet. The
  /// pending points are discarded — nothing is saved unless the
  /// admin tapped "Name & save".
  void _exitSetEndpointsMode() {
    if (!_setEndpointsActive) return;
    setState(() {
      _setEndpointsActive = false;
      _pendingStart = null;
      _pendingEnd = null;
      _sheetHidden = false;
    });
  }

  /// A map tap while Set Start/End mode is active: the first
  /// tap places the Start pin, the second the End pin. Once
  /// both are placed, further taps do nothing — tap "Name &
  /// save" to continue or "Clear" to start over (predictable;
  /// a mis-tap is fixed with Clear, not by silently moving a
  /// pin the admin already placed).
  void _onSetEndpointsMapTap(Geographic point) {
    final tapped = LatLng(point.lat, point.lon);
    if (_pendingStart == null) {
      setState(() => _pendingStart = tapped);
    } else if (_pendingEnd == null) {
      setState(() => _pendingEnd = tapped);
    }
  }

  /// Discards the placed points and starts the pair over.
  void _clearEndpoints() {
    setState(() {
      _pendingStart = null;
      _pendingEnd = null;
    });
  }

  /// Validates the two endpoint names before either stop is
  /// created: both non-empty, different from each other, and
  /// neither matching an existing hub or bus stop
  /// (case-insensitive) — reuses [validateBusStop], and the
  /// repo re-validates on create as defense in depth.
  String? _validateEndpointNames(
    String startName,
    String endName,
    String region,
  ) {
    final start = _pendingStart;
    final end = _pendingEnd;
    if (start == null || end == null) return 'Place both pins first.';
    if (startName.trim().toLowerCase() ==
        endName.trim().toLowerCase()) {
      return 'The Start and End names must be different.';
    }
    final startError = validateBusStop(
      name: startName,
      region: region,
      lat: start.latitude,
      lng: start.longitude,
      existingStops: _busStops,
    );
    if (startError != null) return startError;
    return validateBusStop(
      name: endName,
      region: region,
      lat: end.latitude,
      lng: end.longitude,
      existingStops: _busStops,
    );
  }

  /// Names the two placed points and saves them as bus stops
  /// (one shared region — they are the two ends of one route),
  /// then jumps the map to the new route between them. The
  /// route itself is a generated route between two stops (no
  /// custom route or override is written); its fare is "not
  /// set" until he sets it via the existing Edit route flow.
  /// If a create still fails midway (rare — the dialog
  /// pre-validates duplicates), the already-created stop
  /// remains as a real stop (harmless), the error is shown,
  /// and he can re-enter the mode.
  Future<void> _showNameEndpointsDialog() async {
    final user = widget.currentUser;
    final repo = widget.busStopRepository;
    final start = _pendingStart;
    final end = _pendingEnd;
    if (user == null || repo == null || start == null || end == null) {
      return;
    }
    final regions = hubRegions();
    var region = regions.first;
    final startController = TextEditingController();
    final endController = TextEditingController();
    final result = await showDialog<(String, String, String)?>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Name the Start and End stops'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'The two points become bus stops, so the route '
                    'can use them as its From and To.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: startController,
                    decoration: const InputDecoration(
                      labelText: 'Start stop name',
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: endController,
                    decoration: const InputDecoration(
                      labelText: 'End stop name',
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in regions)
                        ChoiceChip(
                          label: Text(r),
                          selected: region == r,
                          onSelected: (_) =>
                              setDialogState(() => region = r),
                        ),
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final err = _validateEndpointNames(
                      startController.text,
                      endController.text,
                      region,
                    );
                    if (err != null) {
                      setDialogState(() => error = err);
                      return;
                    }
                    Navigator.pop(
                      dialogContext,
                      (
                        startController.text.trim(),
                        endController.text.trim(),
                        region,
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    startController.dispose();
    endController.dispose();
    if (result == null || !mounted) return;
    final (startName, endName, chosenRegion) = result;
    try {
      await repo.create(
        BusStop(
          name: startName,
          region: chosenRegion,
          lat: start.latitude,
          lng: start.longitude,
        ),
        user,
      );
      await repo.create(
        BusStop(
          name: endName,
          region: chosenRegion,
          lat: end.latitude,
          lng: end.longitude,
        ),
        user,
      );
    } catch (_) {
      if (!mounted) return;
      _snack('Could not save the stops. Check the names and try again.');
      return;
    }
    if (!mounted) return;
    _exitSetEndpointsMode();
    // The jump reloads stops before matching hubs (see
    // _onFaresJump), so the just-added stops match as the
    // route's From/To. Both endpoints are stop names — no
    // device coordinates travel with this jump (J2).
    faresMapJump.value = (
      from: startName,
      to: endName,
      fromLat: null,
      fromLng: null,
    );
    _onFaresJump();
  }

  /// A map tap while the line maker is active. In add-stop mode
  /// the tap IS the placement: the name form opens at once. In
  /// draw mode a tap near an existing draft point (within 100 m)
  /// opens that point's actions instead of adding a duplicate;
  /// any other tap appends a point in order and the line
  /// re-draws live.
  void _onLineMakerMapTap(Geographic point) {
    final tapped = LatLng(point.lat, point.lon);
    if (_lineMakerAddStop) {
      _showNameBusStopForm(tapped);
      return;
    }
    for (var i = 0; i < _draftPoints.length; i++) {
      final p = _draftPoints[i];
      if (haversineKm(p.lat, p.lng, tapped.latitude, tapped.longitude) <=
          0.1) {
        _showDraftPointActions(i);
        return;
      }
    }
    setState(() {
      _draftPoints = [
        ..._draftPoints,
        RouteWaypoint(lat: tapped.latitude, lng: tapped.longitude),
      ];
      _selectedDraftIndex = _draftPoints.length - 1;
    });
    _refreshDraftOsrm();
  }

  /// Refreshes the draft line's road shape through the draft
  /// points (origin → draft points in order → destination). A
  /// stale response is ignored via [_draftRequestId]; on any
  /// failure the dashed direct line stays.
  Future<void> _refreshDraftOsrm() async {
    final route = _activeRoute;
    final origin = _activeRouteOrigin;
    if (route == null || origin == null || _draftPoints.isEmpty) {
      if (_draftRoadPoints != null) {
        setState(() => _draftRoadPoints = null);
      }
      return;
    }
    final requestId = ++_draftRequestId;
    final dest = LatLng(route.dest.lat, route.dest.lng);
    final result = await fetchOsrmRouteForPoints([
      origin,
      ..._draftPoints.map((w) => w.point),
      dest,
    ]);
    if (!mounted || requestId != _draftRequestId || !_lineMakerActive) {
      return;
    }
    if (result == null || result.points.isEmpty) return;
    setState(() => _draftRoadPoints = result.points);
  }

  /// Reloads the route data and re-resolves the active route so
  /// a saved / cleared line is live at once. Keeps the caller in
  /// draw mode — only the route data refreshes.
  Future<void> _reloadActiveRoute() async {
    final route = _activeRoute;
    final origin = _activeRouteOrigin;
    if (route == null || origin == null) return;
    await _ensureRouteData();
    if (!mounted) return;
    final resolved = await _resolveRoute(
      originName: route.originName,
      oLat: origin.latitude,
      oLng: origin.longitude,
      destHub: route.dest,
    );
    if (!mounted) return;
    setState(() {
      _activeRoute = resolved.route ?? route;
      _activeRouteOverride = resolved.override;
      _roadPoints = null;
      _roadLoading = resolved.route != null;
      // J1: same as a jump — the old OSRM totals are cleared so a
      // failed refetch falls back to the route's estimate, not the
      // pre-edit direction's distance/ETA.
      _routeDistanceKm = 0;
      _routeDurationSec = 0;
      _selectedStopIndex = null;
      _pendingStopIndex = null;
    });
    _refreshRouteStops();
    if (resolved.route != null) {
      _fetchRoadPath(
        origin.latitude,
        origin.longitude,
        route.dest,
        via: resolved.via,
      );
    }
  }

  /// Saves the draft points as the active route's direction.
  /// Custom route → its own viaWaypoints; seeded route → the
  /// fare-override doc, merged with the existing override so a
  /// set fare / student fare is NOT wiped (and an otherwise
  /// empty override is deleted = reset to built-in). A GPS
  /// 'Your location' origin cannot be saved — the route has no
  /// hub-named origin to key the override on.
  Future<void> _saveDraftLine() async {
    if (_lineMakerSaving) return;
    final route = _activeRoute;
    final origin = _activeRouteOrigin;
    final author = widget.currentUser;
    if (route == null || origin == null || author == null) return;
    if (!isAdminUser(author)) return;
    final custom = route.customRoute;
    if (custom == null && route.originName == 'Your location') {
      _snack('Start from a named place to save a line.');
      return;
    }
    setState(() => _lineMakerSaving = true);
    try {
      final waypoints = List<RouteWaypoint>.of(_draftPoints);
      if (custom != null) {
        final repo = widget.customRouteRepository;
        if (repo == null) {
          _snack('Routes cannot be saved right now.');
          return;
        }
        await repo.update(
          custom.copyWith(viaWaypoints: waypoints),
          author,
          busStops: _busStops,
        );
      } else {
        final repo = widget.fareOverrideRepository;
        if (repo == null) {
          _snack('Routes cannot be saved right now.');
          return;
        }
        final key = seededRouteKey(route.originName, route.dest.name);
        final existing = _activeRouteOverride;
        final next = (existing ?? RouteFareOverride(routeKey: key))
            .copyWith(viaWaypoints: waypoints);
        if (routeFareOverrideIsEmpty(next)) {
          if (existing != null) await repo.delete(key, author);
        } else {
          await repo.save(next, author);
        }
      }
      if (!mounted) return;
      await _reloadActiveRoute();
      if (!mounted) return;
      _snack('Line saved.');
      _exitLineMaker();
    } on ArgumentError catch (e) {
      if (!mounted) return;
      final message = e.message;
      _snack(message is String ? message : 'Could not save the line.');
    } catch (_) {
      if (!mounted) return;
      _snack('Could not save the line.');
    } finally {
      if (mounted) setState(() => _lineMakerSaving = false);
    }
  }

  /// Clears the drawn line: the draft empties AND the saved
  /// direction resets to built-in at once (custom route →
  /// viaWaypoints []; seeded route → override's viaWaypoints []
  /// with the named via stops kept, or the override deleted when
  /// it would otherwise be empty). The admin stays in draw mode
  /// to re-draw if they want.
  Future<void> _clearDraftLine() async {
    final route = _activeRoute;
    final author = widget.currentUser;
    if (route == null || author == null || !isAdminUser(author)) return;
    if (_lineMakerSaving) return;
    setState(() => _lineMakerSaving = true);
    try {
      final custom = route.customRoute;
      if (custom != null) {
        final repo = widget.customRouteRepository;
        if (repo == null) return;
        await repo.update(
          custom.copyWith(viaWaypoints: const <RouteWaypoint>[]),
          author,
          busStops: _busStops,
        );
      } else {
        final repo = widget.fareOverrideRepository;
        if (repo == null) return;
        final key = seededRouteKey(route.originName, route.dest.name);
        final existing = _activeRouteOverride;
        if (existing != null) {
          final next = existing.copyWith(
            viaWaypoints: const <RouteWaypoint>[],
          );
          if (routeFareOverrideIsEmpty(next)) {
            await repo.delete(key, author);
          } else {
            await repo.save(next, author);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _draftPoints = const [];
        _draftRoadPoints = null;
        _selectedDraftIndex = null;
      });
      await _reloadActiveRoute();
      if (!mounted) return;
      _snack('Line cleared — back to the built-in direction.');
    } catch (_) {
      if (!mounted) return;
      _snack('Could not clear the line.');
    } finally {
      if (mounted) setState(() => _lineMakerSaving = false);
    }
  }

  /// Renames one drawn waypoint (admin only, Steven Nov 7,
  /// 20:54: "Dapat May Name: Stops along the way, Hindi lang
  /// puro Point nga name." + "make it editable"). The name is
  /// typed by the admin — never invented — and saved with the
  /// waypoint in the stored direction (custom route → update;
  /// seeded route → override save, with the empty-override
  /// delete rule applying). The stops list + map pins then show
  /// the saved name (see [routeStops], which displays
  /// `w.name ?? 'Point N'`). Only drawn waypoints are
  /// renamable — hub stops (Cabugao, San Juan, Vigan Terminal)
  /// are fixed hub names. When a drawn point is saved as a bus
  /// stop, its name becomes the stop name (existing flow).
  /// After the save the route reloads and the card closes; the
  /// renamed stop shows in the stops list + on the map.
  Future<void> _showRenameWaypointDialog(int waypointIndex) async {
    final route = _activeRoute;
    final author = widget.currentUser;
    if (route == null || author == null || !isAdminUser(author)) return;
    final waypoints = effectiveRouteWaypoints(
      customRoute: route.customRoute,
      override: _activeRouteOverride,
      busStops: _busStops,
    );
    if (waypointIndex < 0 || waypointIndex >= waypoints.length) return;
    final waypoint = waypoints[waypointIndex];
    final controller = TextEditingController(text: waypoint.name ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Rename this stop'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: 'Stop name',
                      hintText: waypoint.name == null
                          ? 'e.g. Cabugao Public Market'
                          : null,
                    ),
                    textCapitalization: TextCapitalization.words,
                    autofocus: true,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = controller.text.trim();
                    if (name.isEmpty) {
                      setDialogState(
                        () => error = 'Enter a name for the stop.',
                      );
                      return;
                    }
                    if (name.length > 100) {
                      setDialogState(
                        () => error =
                            'The name must be 100 characters or fewer.',
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, name);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (result == null || !mounted) return;
    final renamed = List<RouteWaypoint>.of(waypoints);
    renamed[waypointIndex] = waypoint.copyWith(name: result);
    try {
      final custom = route.customRoute;
      if (custom != null) {
        final repo = widget.customRouteRepository;
        if (repo == null) {
          _snack('Routes cannot be saved right now.');
          return;
        }
        await repo.update(
          custom.copyWith(viaWaypoints: renamed),
          author,
          busStops: _busStops,
        );
      } else {
        final repo = widget.fareOverrideRepository;
        if (repo == null) {
          _snack('Routes cannot be saved right now.');
          return;
        }
        final key = seededRouteKey(route.originName, route.dest.name);
        final existing = _activeRouteOverride;
        final next = (existing ?? RouteFareOverride(routeKey: key))
            .copyWith(viaWaypoints: renamed);
        if (routeFareOverrideIsEmpty(next)) {
          if (existing != null) await repo.delete(key, author);
        } else {
          await repo.save(next, author);
        }
      }
      if (!mounted) return;
      await _reloadActiveRoute();
      if (!mounted) return;
      _snack('Stop renamed.');
    } catch (_) {
      if (!mounted) return;
      _snack('Could not rename the stop.');
    }
  }

  /// Action sheet for one draft point: "Save as bus stop" when
  /// the point is still unnamed (the tie-in to Feature 1), and
  /// "Remove point" always.
  void _showDraftPointActions(int index) {
    if (index < 0 || index >= _draftPoints.length) return;
    final point = _draftPoints[index];
    final name = point.name ?? 'Point ${index + 1}';
    setState(() => _selectedDraftIndex = index);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.push_pin),
                title: Text(name),
                subtitle: Text(
                  '${point.lat.toStringAsFixed(5)}, '
                  '${point.lng.toStringAsFixed(5)}',
                ),
              ),
              if (point.name == null)
                ListTile(
                  leading: const Icon(Icons.add_location_alt),
                  title: const Text('Save as bus stop'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showNameBusStopForm(point.point, draftIndex: index);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove point'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() {
                    final next = [..._draftPoints]..removeAt(index);
                    _draftPoints = next;
                    _selectedDraftIndex = null;
                  });
                  _refreshDraftOsrm();
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Name form for a new bus stop placed on the map: the admin
  /// names it and picks its region (region chips, same list the
  /// hubs use). Saving creates the stop (Firestore when
  /// configured, else local), renames the draft point when this
  /// came from one, and reloads the stops so the new stop is a
  /// From/To endpoint and a via stop at once. Cancelling in
  /// add-stop mode exits the mode — the admin came from the Add
  /// Route sheet, which still holds its draft.
  Future<void> _showNameBusStopForm(
    LatLng point, {
    int? draftIndex,
  }) async {
    final repo = widget.busStopRepository;
    final author = widget.currentUser;
    if (repo == null || author == null) {
      _snack('Bus stops cannot be saved right now.');
      return;
    }
    final nameController = TextEditingController();
    var region = hubRegions().first;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('New bus stop'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${point.latitude.toStringAsFixed(5)}, '
                    '${point.longitude.toStringAsFixed(5)}',
                    style: TextStyle(
                      color: Theme.of(
                        dialogContext,
                      ).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Stop name',
                      hintText: 'e.g. Cabugao Public Market',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Region'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in hubRegions())
                        ChoiceChip(
                          label: Text(r),
                          selected: region == r,
                          onSelected: (_) =>
                              setDialogState(() => region = r),
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Save stop'),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved != true || !mounted) {
      if (_lineMakerAddStop) _exitLineMaker();
      return;
    }
    final name = nameController.text.trim();
    try {
      final created = await repo.create(
        BusStop(
          name: name,
          region: region,
          lat: point.latitude,
          lng: point.longitude,
          authorUid: author.uid,
          authorEmail: author.email,
        ),
        author,
      );
      if (!mounted) return;
      setState(() {
        if (draftIndex != null &&
            draftIndex >= 0 &&
            draftIndex < _draftPoints.length) {
          final next = [..._draftPoints];
          next[draftIndex] = next[draftIndex].copyWith(name: created.name);
          _draftPoints = next;
        }
      });
      await _ensureRouteData();
      if (!mounted) return;
      _snack('Bus stop "${created.name}" added.');
      if (_lineMakerAddStop) _exitLineMaker();
    } on ArgumentError catch (e) {
      if (!mounted) return;
      final message = e.message;
      _snack(message is String ? message : 'Could not save the bus stop.');
    } catch (_) {
      if (!mounted) return;
      _snack('Could not save the bus stop.');
    }
  }

  /// Label for a draft point in the bottom bar: its saved name,
  /// else "Point N" in tap order.
  String _draftPointLabel(int index) {
    final point = _draftPoints[index];
    return point.name ?? 'Point ${index + 1}';
  }

  /// Bottom bar while the line maker is active (the sheet is
  /// hidden, so this takes its place): the instruction, the
  /// point count + selected point, and Save line / Clear / Done
  /// (draw mode) or Cancel (add-stop mode).
  Widget _lineMakerBar(ColorScheme scheme) {
    final selected = _selectedDraftIndex;
    final selectedLabel = selected != null &&
            selected >= 0 &&
            selected < _draftPoints.length
        ? ' • ${_draftPointLabel(selected)}'
        : '';
    final pointsLabel = _draftPoints.isEmpty
        ? ''
        : ' • ${_draftPoints.length} point${_draftPoints.length == 1 ? '' : 's'}$selectedLabel';
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _lineMakerAddStop
                    ? 'Tap the map to place the new bus stop'
                    : 'Tap the map to add points in order$pointsLabel',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              // Wrap, not Row: on a narrow phone the three
              // buttons flow to a second line instead of
              // overflowing the bar.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!_lineMakerAddStop) ...[
                    FilledButton(
                      onPressed: _lineMakerSaving ? null : _saveDraftLine,
                      child: const Text('Save line'),
                    ),
                    OutlinedButton(
                      onPressed: _lineMakerSaving ? null : _clearDraftLine,
                      child: const Text('Clear'),
                    ),
                  ],
                  OutlinedButton(
                    onPressed: _exitLineMaker,
                    child: Text(_lineMakerAddStop ? 'Cancel' : 'Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom bar for Set Start/End mode (admin only): the sheet
  /// is hidden while placing, so this bar takes its place at
  /// the bottom — the same floating card as [_lineMakerBar],
  /// mutually exclusive with it.
  Widget _setEndpointsBar(ColorScheme scheme) {
    final startSet = _pendingStart != null;
    final endSet = _pendingEnd != null;
    final instruction = !startSet
        ? 'Tap the map to place the Start pin'
        : !endSet
            ? 'Tap the map to place the End pin'
            : 'Both pins placed — name them to save the route';
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                instruction,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Start: ${startSet ? 'placed' : 'not placed'}'
                ' · End: ${endSet ? 'placed' : 'not placed'}',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              // Wrap, not Row: on a narrow phone the three
              // buttons flow to a second line instead of
              // overflowing the bar.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed:
                        startSet && endSet ? _showNameEndpointsDialog : null,
                    child: const Text('Name & save'),
                  ),
                  OutlinedButton(
                    onPressed:
                        startSet || endSet ? _clearEndpoints : null,
                    child: const Text('Clear'),
                  ),
                  OutlinedButton(
                    onPressed: _exitSetEndpointsMode,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }


  /// Numbered stop pin (emerald circle, white number; deep
  /// emerald while its card is open). Draft pins are amber
  /// instead (deep amber while selected) so the line being drawn
  /// is visibly distinct from the saved route's pins.
  Widget _numberedPin(
    int number, {
    required bool selected,
    bool draft = false,
  }) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: selected
            ? (draft ? const Color(0xFFD97706) : kMapPrimary)
            : (draft ? const Color(0xFFF59E0B) : const Color(0xFF16A34A)),
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
                // Rename (admin only, Steven Nov 7, 20:54:
                // "Dapat May Name: Stops along the way, Hindi
                // lang puro Point nga name." + "make it
                // editable"): only drawn-waypoint stops carry a
                // waypointIndex, so the pencil shows exactly on
                // those ("Point N" or an already-named point) —
                // never on hub stops (Cabugao, San Juan, Vigan
                // Terminal), whose names are fixed.
                if (isAdminUser(widget.currentUser) &&
                    stop.waypointIndex != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: Colors.white),
                    tooltip: 'Rename this stop',
                    onPressed: () => _showRenameWaypointDialog(
                      stop.waypointIndex!,
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
    // The badge claims the fare is the Oct 16 user-verified one,
    // so it only shows when the fare on display IS that fare: an
    // admin-set fare (custom route or override) supersedes it.
    final adminFare =
        route.customRoute?.fare ?? _activeRouteOverride?.fare;
    final verified = adminFare == null
        ? knownBusFare(route.originName, route.dest.name)
        : null;
    // F8: operator + vehicle for the line under the title (the
    // custom route's own, else the seeded route's).
    final ov = mapRouteOperatorVehicle(
      customRoute: route.customRoute,
      from: route.originName,
      to: route.dest.name,
    );
    return Padding(
      // Bottom padding 2 (not 10): the F8 operator/vehicle line
      // added ~15 px to this fixed header, and the header must
      // still fit the peeked sheet whole (Peek is 0.20 of a short
      // viewport in tests — the overflow was 13 px). The body
      // below starts with its own 4 px gap, so the title-to-cards
      // gap stays 6 px.
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
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
          const SizedBox(height: 2),
          // Title row: the route name (ellipsized when long) and,
          // for admins, the line maker entry. "Draw line" draws
          // the active route's line by tapping the map; it lives
          // here — the header is where the active route is named
          // and the draw action is route-scoped — because the
          // ETA • FARE row cannot take a third element and the
          // top-right cluster is full (a 6th button would collide
          // with the stop card at kMapStopCardTop). The title
          // shrinks instead of overflowing, so the header stays
          // compact enough to fit the peeked sheet whole.
          Row(
            children: [
              Expanded(
                child: Text(
                  '${route.originName} → ${route.dest.name}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isAdminUser(widget.currentUser) && !_lineMakerActive)
                TextButton(
                  onPressed: _enterDrawLineMode,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF16A34A),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Draw line',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              // "Set Start/End" (admin only, Steven Nov 7, 20:52):
              // tap the map twice to place the route's Start and
              // End pins himself. Same header slot as Draw line —
              // the route-scoped direction tool, where the active
              // route is named.
              if (isAdminUser(widget.currentUser) && !_setEndpointsActive)
                TextButton(
                  onPressed: _enterSetEndpointsMode,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF16A34A),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Set Start/End',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          // F8: operator + vehicle under the route name. Nothing
          // when the route has neither — a generic hub-to-hub
          // route.
          if (ov.operator != null || ov.vehicle != null)
            Padding(
              padding: EdgeInsets.zero,
              child: Text(
                [
                  if (ov.operator != null) ov.operator!,
                  if (ov.vehicle != null) ov.vehicle!,
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
  /// side by side, plus a PWD / SENIOR row below (F7). The fares
  /// are the EFFECTIVE fares (see [resolveMapSheetFares]): an
  /// admin-added route's own fares, else an admin override's
  /// fares, else the user-verified fare. A pair with none of
  /// those shows the same LTFRB estimate the Fares breakdown
  /// shows (F4 — labelled ESTIMATE, at the route's own vehicle
  /// rate), or "Fare not set" when the vehicle has no table rate.
  /// A blank student fare derives 20% off the effective regular
  /// fare. The DISCOUNTED card claims "-20%" only when the
  /// student fare is derived (F6).
  Widget _fareCards(ColorScheme scheme, RouteInfo route) {
    final fares = resolveMapSheetFares(
      customRoute: route.customRoute,
      override: _activeRouteOverride,
      from: route.originName,
      to: route.dest.name,
    );
    final regular = fares.regular;
    final vehicle = mapRouteOperatorVehicle(
      customRoute: route.customRoute,
      from: route.originName,
      to: route.dest.name,
    ).vehicle;
    final km = _routeDistanceKm > 0 ? _routeDistanceKm : route.roadKm;
    final estimate = regular == null
        ? mapSheetEstimateFare(vehicle: vehicle, roadKm: km)
        : null;
    final isEstimate = regular == null && estimate != null;
    final regularValue = regular ?? estimate;
    final studentSet = route.customRoute?.studentFare != null ||
        _activeRouteOverride?.studentFare != null;
    final discountedValue =
        fares.discounted ??
        (estimate == null ? null : discountedFareOf(estimate));
    final pwdValue =
        fares.pwd ?? (estimate == null ? null : discountedFareOf(estimate));
    final seniorValue =
        fares.senior ??
        (estimate == null ? null : discountedFareOf(estimate));
    String valueText(double? value) => value == null
        ? 'Fare not set'
        : isEstimate
        ? '≈ ${peso(value)}'
        : peso(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _etaFareStatCard(
                scheme: scheme,
                label: isEstimate ? 'ESTIMATE' : 'REGULAR FARE',
                value: valueText(regularValue),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _etaFareStatCard(
                scheme: scheme,
                label: mapDiscountLabel(studentFareSet: studentSet),
                value: valueText(discountedValue),
                highlight: true,
              ),
            ),
          ],
        ),
        if (regularValue != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _etaFareStatCard(
                  scheme: scheme,
                  label: 'PWD',
                  value: valueText(pwdValue),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _etaFareStatCard(
                  scheme: scheme,
                  label: 'SENIOR',
                  value: valueText(seniorValue),
                ),
              ),
            ],
          ),
        ],
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
              if (_setEndpointsActive) {
                // Set Start/End mode: the tap places the Start
                // pin, then the End pin (see _onSetEndpointsMapTap).
                _onSetEndpointsMapTap(event.point);
              } else if (_lineMakerActive) {
                // Draw / add-stop mode: the tap places or
                // selects a draft point (see _onLineMakerMapTap);
                // it never dismisses a card (none is open).
                _onLineMakerMapTap(event.point);
              } else if (_selectedStopIndex != null) {
                // A plain map tap dismisses the open stop card
                // (and restores the normal line).
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
        // "Couldn't load the map" banner: both tile sources
        // unreachable (Steven's phone, Nov 7, 20:08–20:13: blank
        // map in both themes, current build, data available).
        // Shown only after Meta AND the CartoDB fallback have
        // failed — never during the normal 8–10 s load window.
        // Retry re-attempts the Meta style. Pinned top-left,
        // ending before the top-right control cluster (right 88).
        if (_tilesFailed)
          Positioned(
            top: 16,
            left: 16,
            right: 88,
            child: _tilesFailedBanner(context),
          ),
        // Manual map reload, top-left: the one action that is
        // ALWAYS available, even when the app believes the map
        // is fine. The banner's Retry only exists once
        // [_tilesFailed] is set — and the probe can pass on a
        // few small tiles while the viewport never arrives
        // (Steven's phone, Nov 7, 22:10: blank map, no banner,
        // no Retry at all), leaving the user stuck with no way
        // to re-attempt the tiles short of an app restart. This
        // button calls the same [_retryTileSources] as the
        // banner: back to Meta, timers re-armed, banner cleared.
        // Top-left, not the top-right cluster: the cluster is
        // already 5 buttons tall (it ends 16 px above the stop
        // card at kMapStopCardTop) and a 6th button would cover
        // the stop card's close button. Hidden while the banner
        // shows — the banner occupies this exact spot with its
        // own Retry.
        if (!_tilesFailed)
          Positioned(
            top: 16,
            left: 16,
            child: _MapControlButton(
              key: const ValueKey('map-tiles-reload'),
              icon: Icons.refresh,
              tooltip: 'Reload map',
              onPressed: _retryTileSources,
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
        // (when shown, the ⓘ button above carries it). Hidden
        // while the line maker is active — its bottom bar occupies
        // this spot.
        if (_sheetHidden && !_lineMakerActive)
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
        // Line maker bottom bar (admin-only modes): the sheet is
        // hidden while drawing / placing, so this bar takes its
        // place at the bottom.
        if (_lineMakerActive) _lineMakerBar(scheme),
        if (_setEndpointsActive) _setEndpointsBar(scheme),
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
                              // Bottom padding 0 (not 4): part of
                              // reclaiming the ~13 px the F8 line
                              // added to the fixed header, so the
                              // header still fits the peeked sheet.
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                10,
                                20,
                                0,
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
    super.key,
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

