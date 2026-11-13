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
import 'top_popup.dart';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import 'ios_components.dart';
import 'live_follow.dart';
import 'live_minimap.dart';
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

/// DIAGNOSTIC TEST FLAG — Nov 9, 2026 (Huawei P30 Lite blank map).
///
/// The Map tab is blank on Steven's phone only (the tablet
/// renders fine). Ruled out: signal, theme, old build, VPN,
/// clock, corrupt cache. Decisive clue: on the updated build the
/// "Couldn't load the map" banner never appears, which means the
/// Meta style reported loaded and the tile probe passed — tiles
/// DOWNLOAD fine, but the native MapLibre view does not DRAW the
/// vector tiles on this phone.
///
/// While this flag is true, the Map tab STARTS on the
/// theme-aware CartoDB raster basemap (Dark Matter / Positron)
/// instead of Meta's Canterbury vector style, so we can test
/// whether raster tiles render where vector does not. Theme
/// switches swap the raster variant only and never jump back to
/// Meta; Retry re-attempts raster too. Flip this to false to
/// restore the Meta vector start — nothing else changes, the
/// Meta path is untouched. DO NOT SHIP with this flag on without
/// Steven's say-so: it is a diagnostic, not a product decision.
const bool kMapStartsOnRaster = false;

/// The basemap style the Map tab starts on — and returns to on a
/// theme change or a Retry — for [dark] theme. While the Nov 9
/// raster diagnostic ([kMapStartsOnRaster]) is on, this is the
/// theme-aware CartoDB raster style document; with the flag off
/// it is Meta's Canterbury vector style URL, as before. The
/// [startsOnRaster] parameter exists so tests can exercise both
/// branches; production callers omit it and use the flag.
String mapStartStyle({
  required bool dark,
  bool startsOnRaster = kMapStartsOnRaster,
}) => startsOnRaster
    ? cartoFallbackStyleJson(dark: dark)
    : metaMapStyleUrl(dark: dark);

/// What the banner's Retry button re-attempts for [dark] theme:
/// the style to set, and whether it is the raster basemap. While
/// the raster diagnostic is on, Retry re-attempts the raster
/// style (the thing under test) — if raster tiles also fail, the
/// banner shows again, same honesty as before. With the flag off,
/// Retry goes back to Meta. [startsOnRaster] is the test hook
/// (see [mapStartStyle]).
({bool isRaster, String style}) mapRetryTarget({
  required bool dark,
  bool startsOnRaster = kMapStartsOnRaster,
}) => (
  isRaster: startsOnRaster,
  style: mapStartStyle(dark: dark, startsOnRaster: startsOnRaster),
);

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

/// ID of the runtime 3D buildings layer (added to the live style
/// by [_MapTabState._syncBuildingsExtrusion] — it is NOT part of
/// the Meta style document, which draws buildings as flat fills).
const String kBuildings3dLayerId = 'estudyantego-buildings-3d';

/// Minimum extrusion height (metres) applied to a building's
/// real tile "height" — a 3.4 m shed still reads as a 3D block
/// instead of a flat slab. Verified Nov 11, 2026 from a decoded
/// z16 vector tile for Vigan: the buildings layer DOES carry a
/// real "height" property (double, metres — e.g. 3.4, 6.8).
const double kBuildings3dMinHeightM = 5;

/// Default extrusion height (metres) for a building whose tile
/// feature carries no "height" property — the fallback that
/// still makes the building read as a 3D block.
const double kBuildings3dDefaultHeightM = 10;

/// Default extrusion height (metres) for an "elevated" building
/// (feature property elevated == "yes") with no "height"
/// property — taller than a normal building, still modest.
/// (Was 24 m; lowered to 18 m, Nov 11.)
const double kBuildings3dElevatedHeightM = 18;

/// The layer the extrusion is inserted above: the Meta style's
/// flat "buildings-elevated" fill, so the 3D blocks sit exactly
/// where the flat footprints sit, with the style's roads,
/// bridges and labels above them as before.
const String kBuildings3dAnchorLayerId = 'buildings-elevated';

/// Runtime fill-extrusion layer that renders the Meta Canterbury
/// style's building footprints as 3D blocks. Source and
/// source-layer are the style's own ("facebook" /
/// "buildings" — verified against the live style document,
/// Nov 11: two flat fill layers, minzoom 16, no extrusion).
/// Height uses the feature's real "height" when present
/// (verified from a decoded z16 tile for Vigan, Nov 11:
/// double, metres — e.g. 3.4, 6.8), floored at 5 m so small
/// real heights still read as blocks; otherwise the defaults
/// above (10 m normal, 18 m elevated). Base uses
/// "min_height" when present, else ground level. Colour is a
/// shade lighter than the flat building fill
/// (hsl(204.8, 26.8%, 25.7%)) so the blocks read against the
/// dark map; the vertical gradient shades the sides darker.
/// Honest limit: building data in the rural Cabugao → Vigan
/// corridor is sparse in the tiles (a few footprints per
/// tile), so extrusions appear only where the map data has
/// buildings. Active only in 3D mode on the Meta style — see
/// [_MapTabState._syncBuildingsExtrusion]. Pure value: tested
/// in test/map_buildings_3d_test.dart without a live map.
const FillExtrusionStyleLayer kBuildings3dExtrusionLayer =
    FillExtrusionStyleLayer(
      id: kBuildings3dLayerId,
      sourceId: 'facebook',
      sourceLayerId: 'buildings',
      minZoom: 16,
      maxZoom: 24,
      layout: {'visibility': 'visible'},
      paint: {
        'fill-extrusion-color': '#47657b',
        'fill-extrusion-height': [
          'case',
          ['==', ['get', 'elevated'], 'yes'],
          [
            'max',
            ['to-number', ['get', 'height'], kBuildings3dElevatedHeightM],
            kBuildings3dElevatedHeightM,
          ],
          [
            'max',
            ['to-number', ['get', 'height'], kBuildings3dDefaultHeightM],
            kBuildings3dMinHeightM,
          ],
        ],
        'fill-extrusion-base': ['to-number', ['get', 'min_height'], 0],
        'fill-extrusion-opacity': 0.9,
        'fill-extrusion-vertical-gradient': true,
      },
    );

/// One-time auto-focus decision for the Map tab opening
/// (Nov 11, 2026): true only when the tab has not auto-focused
/// yet, the location service is on, and permission is ALREADY
/// granted (whileInUse / always). Never prompts — the permission
/// prompt stays on My Location / Live Follow. Extracted as a
/// pure function so the guard matrix is unit-testable without
/// a live map or a Geolocator mock.
bool shouldAutoFocusOnLocation({
  required bool alreadyDone,
  required bool locationServiceEnabled,
  required LocationPermission permission,
}) {
  if (alreadyDone) return false;
  if (!locationServiceEnabled) return false;
  return permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always;
}

/// View modes the Map tab's 2D/3D toggle offers: 2D top-down and
/// 3D perspective only. Satellite is NOT offered — it needs a
/// separate imagery tile source (not Meta vector) and was not
/// part of the Nov 8 approval ("Oo, lagyan mo ng 3D toggle").
const List<MapViewMode> mapViewModeOptions = [
  MapViewMode.standard2d,
  MapViewMode.perspective3d,
];

/// Short label for a view mode in the 2D/3D toggle.
String mapViewModeLabel(MapViewMode mode) => switch (mode) {
  MapViewMode.standard2d => '2D',
  MapViewMode.perspective3d => '3D',
  MapViewMode.satellite => 'Satellite',
};

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

/// Whether the Map tab just became visible (a false → true
/// `visible` transition). Pure, so the guard is testable. The
/// re-validate in didUpdateWidget runs only on this transition —
/// never on a parent rebuild while the tab stays visible, and
/// never while it is hidden. (MapTab guard fix, Nov 8, 2026:
/// the old guard `!oldWidget.visible || !widget.visible`
/// returned on exactly this transition, so the re-validate
/// never ran on return — it only ran on rebuilds while the tab
/// was already visible. Same form as StudyTab's reload guard.)
bool mapTabBecameVisible({
  required bool oldVisible,
  required bool visible,
}) =>
    !oldVisible && visible;

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

/// Approved route-line style (Steven, Nov 13, 2026 — Preview v4,
/// artifact map-line-thickness-preview, "Okay na, i-apply na sa
/// real app"): Google Maps blue core, 10 logical px wide, with
/// a white casing around it (14 px total), rounded caps/joins
/// in the preview. The 10 px is the blue core's width in the
/// map's logical pixels — PolylineLayer takes an int width in
/// logical pixels, the same unit the old 6 px green line used,
/// so the preview's visual weight carries over 1:1 (the web
/// preview's 10 px core + 14 px total is the same pair of
/// numbers). This replaces the Preview v3 28 px core: on
/// Steven's phone the 28 px line covered the road and
/// overlapped the stop pins.
/// The casing is drawn as a wider white layer underneath the
/// core, exactly like the stop-highlight branch already did
/// (white 11 under core 7); the numbers are scaled to the new
/// style. The glow layer in the highlight branch is core + 16
/// (26 px), matching the preview's shadow = width + 16.
const kRouteLineBlue = Color(0xFF1A73E8);
const kRouteLineCoreWidth = 10;
const kRouteLineCasingWidth = 14;
const kRouteLineGlowWidth = 26;

/// The travelling highlight that rides the route line after the
/// draw-in: a short bright band, same width as the core, so it
/// reads as a pulse on top of the blue line. It covers this
/// fraction of the whole path at any instant.
const kRouteLinePulseWindow = 0.08;

/// Sub-path of [points] between [start] and [end] as fractions
/// of the path (0..1, by point count), with the cut points
/// interpolated between the bracketing points so the head lands
/// exactly on the road. Used by the draw-in animation
/// ([routeDrawPoints]) and the travelling pulse
/// ([routePulsePoints]). Pure, so the animation geometry is
/// unit-testable without the native map. Out-of-range fractions
/// clamp; a path with fewer than 2 points comes back unchanged.
List<LatLng> routeSubPath(
  List<LatLng> points,
  double start,
  double end,
) {
  if (points.length < 2) return List<LatLng>.of(points);
  final s = start.clamp(0.0, 1.0);
  final e = end.clamp(0.0, 1.0);
  if (e <= s) return <LatLng>[points.first, points.first];
  final segments = points.length - 1;
  LatLng at(double fraction) {
    final pos = fraction * segments;
    final i = pos.floor().clamp(0, segments - 1);
    final f = pos - i;
    if (f <= 0) return points[i];
    final a = points[i];
    final b = points[i + 1];
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * f,
      a.longitude + (b.longitude - a.longitude) * f,
    );
  }

  final out = <LatLng>[at(s)];
  final firstIndex = (s * segments).ceil();
  final lastIndex = (e * segments).floor();
  for (var i = firstIndex; i <= lastIndex; i++) {
    // The start point is already in the list — never repeat it.
    if (points[i] != out.last) out.add(points[i]);
  }
  final head = at(e);
  if (out.last != head) out.add(head);
  return out;
}

/// Prefix of [points] drawn so far at [progress] (0..1) of the
/// draw-in animation: 0 = just the origin point, 1 = the whole
/// road. The state drives this from 0 to 1 in ~1.4 s when a
/// route's road shape arrives, so the line draws itself from
/// Cabugao to Vigan instead of appearing all at once.
List<LatLng> routeDrawPoints(List<LatLng> points, double progress) =>
    routeSubPath(points, 0, progress);

/// The short window of [points] the pulse highlight covers when
/// its head is at [head] (0..1 along the path). The window trails
/// [kRouteLinePulseWindow] behind the head, so the band travels
/// from origin to destination as the head advances.
List<LatLng> routePulsePoints(List<LatLng> points, double head) =>
    routeSubPath(
      points,
      head - kRouteLinePulseWindow,
      head,
    );

/// The map's line layers, as pure data — slot 0 is ALWAYS the
/// saved route line (blue, 10 px core on a 14 px white casing), and the draft line (amber) is an
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
/// up) keeps its four layers, re-coloured and re-sized to the
/// approved style: dimmed blue before the stop, then glow 26 /
/// white casing 14 / blue core 10 after it. It never runs in
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
  bool liveMode = false,
  // Draw-in animation progress (0..1) for the plain route line:
  // 1 = the whole road, the default, so every existing caller
  // that does not animate gets the finished line. While a stop
  // is highlighted the animation is already done, so the
  // progress only trims the plain branch.
  double drawProgress = 1.0,
  // Travelling-pulse head (0..1 along the route), null = no
  // pulse layer. Only the plain branch shows it.
  double? pulseHead,
}) {
  const amber = Color(0xFFF59E0B);
  // Approved style (Nov 13, 2026): the route line is Google
  // Maps blue, 10 px core on a 14 px white casing, in normal
  // AND Live Follow mode. The Nov 11 cyan live line is
  // superseded: the preview Steven approved shows the blue
  // line, and Live is still signalled by the Live button,
  // the cyan live marker, the minimap and the Live panel —
  // the line colour was never the only live signal.
  // [liveMode] stays in the signature (callers + tests pass
  // it) but no longer changes the line colour. The amber draft
  // line is unchanged (it is the admin's in-progress work,
  // not the live route).
  const main = kRouteLineBlue;
  const core = kRouteLineBlue;
  final layers = <MapLineLayerSpec>[];
  // Slot 0: the saved route line, always present when a route
  // is active — including in draw mode, as the reference under
  // the draft being drawn. Omitted entirely while the new
  // route's road shape is loading (roadLoading): no line for
  // the wrong route is ever drawn, not even briefly.
  if (!roadLoading) {
    if (drawMode) {
      layers.addAll([
        MapLineLayerSpec(
          points: routePoints,
          color: Colors.white,
          solid: routeSolid,
          width: kRouteLineCasingWidth,
        ),
        MapLineLayerSpec(
          points: routePoints,
          color: main,
          solid: routeSolid,
          width: kRouteLineCoreWidth,
        ),
      ]);
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
          color: main.withValues(alpha: 0.15),
          solid: true,
        ),
        // Remaining part: soft glow + white casing + wide
        // blue core, at the approved widths (26 / 14 / 10).
        MapLineLayerSpec(
          points: split.after,
          color: main.withValues(alpha: 0.25),
          solid: true,
          width: kRouteLineGlowWidth,
        ),
        MapLineLayerSpec(
          points: split.after,
          color: Colors.white,
          solid: true,
          width: kRouteLineCasingWidth,
        ),
        MapLineLayerSpec(
          points: split.after,
          color: core,
          solid: true,
          width: kRouteLineCoreWidth,
        ),
      ]);
    } else {
      // Plain route line: white casing underneath, blue core
      // on top — two layers, drawn bottom-to-top. The draw-in
      // animation trims both to the same prefix, so the casing
      // never outruns the core. The dashed fallback (OSRM
      // failed) keeps both layers dashed with the same
      // dash pattern, so it still reads as one cased line.
      final drawn = drawProgress >= 1.0
          ? routePoints
          : routeDrawPoints(routePoints, drawProgress);
      layers.addAll([
        MapLineLayerSpec(
          points: drawn,
          color: Colors.white,
          solid: routeSolid,
          width: kRouteLineCasingWidth,
        ),
        MapLineLayerSpec(
          points: drawn,
          color: main,
          solid: routeSolid,
          width: kRouteLineCoreWidth,
        ),
      ]);
      if (pulseHead != null) {
        final pulse = routePulsePoints(routePoints, pulseHead);
        if (pulse.length >= 2) {
          layers.add(
            MapLineLayerSpec(
              points: pulse,
              color: Colors.white.withValues(alpha: 0.9),
              solid: true,
              width: kRouteLineCoreWidth,
            ),
          );
        }
      }
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

class _MapTabState extends State<MapTab>
    with WidgetsBindingObserver, TickerProviderStateMixin {
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
  // fallback after a failed Meta load. While the Nov 9 raster
  // diagnostic ([kMapStartsOnRaster]) is on, the tab STARTS on
  // the raster basemap instead of Meta.
  _MapStyleMode _styleMode = kMapStartsOnRaster
      ? _MapStyleMode.cartoFallback
      : _MapStyleMode.meta;
  // 2D/3D view mode (Steven, Nov 8: "Oo, lagyan mo ng 3D
  // toggle"): 2D = flat top-down (the default); 3D = perspective
  // tilt. The toggle only moves the camera — never the route,
  // stops, or fares. In 3D on the Meta style the runtime
  // extrusion layer ([kBuildings3dExtrusionLayer]) is also
  // added, so the style's building footprints rise as 3D
  // blocks (Nov 11, Steven: "Oo, gawin mo yung 3D buildings");
  // in 2D, or on the CartoDB fallback, the layer is removed
  // (see _syncBuildingsExtrusion). Heights come from the tile
  // feature when present (floored at 5 m), else the 10 m /
  // 18 m defaults — nothing is invented beyond that fallback.
  MapViewMode _viewMode = MapViewMode.standard2d;
  // True while the runtime 3D buildings extrusion layer
  // ([kBuildings3dExtrusionLayer]) is added to the live style.
  // A style reload drops runtime layers, so _onStyleLoaded
  // resets this to false before re-syncing.
  bool _buildingsExtruded = false;
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
  // One-time auto-focus on open (Nov 11, 2026): claimed on the
  // first attempt so a style reload / theme switch / route
  // change can never re-fire it. Reset only when the State is
  // created again (a fresh Map tab).
  bool _autoFocusDone = false;

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
  // ---- Approved route-line animation (Steven, Nov 13, 2026) ----
  // Draw-in progress (0..1) for the plain route line, driven by
  // [_routeDrawTimer]: 28 steps of 50 ms ≈ 1.4 s from origin to
  // destination when a route's road shape arrives. [_routePulseHead]
  // is the travelling highlight's head (0..1 along the route);
  // -1 = no pulse layer. The pulse runs two traversals (~3 s
  // each) after the draw-in, then stops — a forever-running
  // pulse would rebuild the whole tab at 20 fps for the life
  // of the tab, and the draw/pulse are an entrance effect, not
  // a live status. Timers (not AnimationController) keep this
  // off the widget ticker: 20 fps is plenty for a line growing
  // along a road, and each tick only re-runs the memoized
  // layer spec — after the animation ends the spec is stable
  // and the memo holds again. Cancelled in dispose and on
  // every route change (the fetch nulls _roadPoints first, so
  // a stale timer can never animate the wrong route's line).
  Timer? _routeDrawTimer;
  Timer? _routePulseTimer;
  double _routeDrawProgress = 1.0;
  double _routePulseHead = -1;
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

  // ---- Live Follow (Nov 8, 2026): real-GPS follow mode ----
  // The camera follows the phone's live GPS in 3D while a route
  // is active; every number on the Live panel is computed from
  // the live position + route geometry (see live_follow.dart),
  // never invented.
  bool _liveFollowActive = false;
  // Camera follow paused while a stop card is open from a
  // stop-chip tap — GPS + stats keep updating; closing the card
  // (or Resume follow) re-centres the camera.
  bool _liveFollowPaused = false;
  DateTime? _liveFollowStartedAt;
  StreamSubscription<Position>? _livePositionSub;
  // Compass heading (Nov 13, 2026 — built-in, no plugin:
  // MainActivity.kt reads the magnetometer / rotation-vector
  // sensor over the "com.estudyantego.app/compass"
  // EventChannel). Listened to only while Live Follow runs,
  // like the GPS stream — no background drain. Null = no
  // sensor / no reading yet: heading falls back to GPS
  // bearing exactly as before (see blendLiveHeading).
  StreamSubscription<dynamic>? _liveCompassSub;
  double? _liveCompassHeading;
  Timer? _liveGpsLostTimer;
  // Per-frame Live interpolation (Nov 13, 2026 — Google-level
  // smoothing, Preview v2): a Ticker drives the arrow every
  // display frame (~60/120 fps) toward the predicted target,
  // replacing the old 200 ms step-wise glide. The halo uses the
  // tab's other ticker, hence TickerProviderStateMixin.
  Ticker? _liveFrameTicker;
  Duration? _liveLastFrameElapsed;
  // Last GPS fix time + the snapped fix's distance along the
  // road: the frame loop predicts from these between fixes.
  DateTime? _liveLastFixAt;
  double? _liveSnappedDistanceKm;
  // Continuous follow-camera tick (Nov 11, 2026): eases the
  // camera toward the gliding marker every 150 ms so it moves
  // continuously between GPS fixes instead of jumping once
  // per fix.
  Timer? _liveCameraTimer;
  Timer? _liveClockTimer;
  // Pulsing halo behind the Live Follow arrow marker (Nov 13,
  // 2026 — approved Preview v2, Arrow option). Owned by the tab
  // state (not the marker widget): the marker rebuilds on every
  // 200 ms marker tick, so a per-marker controller would restart
  // the pulse on every tick. It repeats once first used; the
  // AnimatedBuilder subtree only exists while the live marker
  // is on screen, so it costs nothing when Live is off.
  late final AnimationController _liveHaloController =
      AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);
  // Interpolated bus-marker position: glides toward the latest
  // GPS fix between updates so the marker never teleports.
  LatLng? _liveMarkerPos;
  LatLng? _liveTargetPos;
  double _liveBearing = 0;
  double _liveTargetBearing = 0;
  // GPS-only direction of travel (updated on fixes that moved
  // 10 m+). The compass handler blends this with the compass
  // heading into _liveTargetBearing — keeping the GPS bearing
  // separate means a stale compass value can never survive a
  // moving GPS fix (see blendLiveHeading).
  double _liveGpsBearing = 0;
  final SpeedSmoother _liveSpeed = SpeedSmoother();
  LatLng? _livePrevPos;
  DateTime? _livePrevPosAt;
  // Last time a speed sample above liveMinMovingKmh arrived —
  // the panel treats a longer gap as "bus stopped" and shows
  // the last good ETA, labelled, instead of a fresh guess.
  DateTime? _liveLastMovingAt;
  bool _liveGpsLost = false;
  LiveFollowSnapshot? _liveSnapshot;
  // Last computed ETA kept when the bus stops (speed ~0), so
  // the panel shows it clearly labelled instead of inventing
  // one.
  int? _liveLastGoodRemainingMin;
  DateTime? _liveLastGoodArrival;
  MapViewMode _livePrevViewMode = MapViewMode.standard2d;
  bool _liveCameraBusy = false;
  // GPS position smoothing (Nov 11, 2026): raw fixes jitter,
  // so the marker / camera / snapshot run on the smoothed
  // point, never the raw fix. See PositionSmoother in
  // live_follow.dart.
  final PositionSmoother _livePositionFilter = PositionSmoother();
  LatLng? _liveSmoothedPos;
  // Last camera target + bearing, for the tick's skip rule
  // (liveCameraShouldMove): a stopped bus does not re-animate
  // the camera on every tick.
  LatLng? _liveLastCameraTarget;
  double _liveLastCameraBearing = 0;
  // Live close-follow (Nov 11, 2026): the user's manual zoom
  // during Live (+/−, pinch, double-tap). Null = no manual zoom
  // — the follow camera settles at the close zoom
  // (liveCloseFollowZoom). Cleared by Overview / My Location /
  // Resume, which re-fit to the close zoom.
  double? _liveUserZoom;
  // True once the first Live camera move of the session has run
  // (the ~1 s ease-in into the close view). Reset on start/stop.
  bool _liveEaseInDone = false;
  // A Live gesture (pinch / drag / rotate) paused follow, and
  // the zoom the camera had when the gesture started — used at
  // camera-idle time to tell a zoom gesture (resume at the new
  // zoom) from a drag (stay paused). Only gesture pauses set
  // this; tap-to-zoom, stop-chip and Overview pauses do not.
  bool _livePausedByGesture = false;
  double _liveGestureStartZoom = 0;
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
    mapSetEndpointsRequest.addListener(_onSetEndpointsRequest);
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
  void didUpdateWidget(covariant MapTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapTabBecameVisible(
      oldVisible: oldWidget.visible,
      visible: widget.visible,
    )) {
      return;
    }
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
    if (kMapStartsOnRaster) {
      // NOV 9 RASTER TEST: theme-aware CartoDB raster only — a
      // theme switch swaps the raster variant (Dark Matter /
      // Positron) and NEVER jumps back to Meta, or the test
      // would silently re-test the vector style and confuse
      // the result.
      _activeStyleUrl = _cartoFallbackSentinel;
      _styleMode = _MapStyleMode.cartoFallback;
      _styleLoaded = false;
      _fallbackLoaded = false;
      _tilesFailed = false; // A style switch restarts the flow.
      _styleLoadTimer?.cancel(); // No Meta timer on raster.
      _fallbackLoadTimer?.cancel();
      _tileWatchdogTimer?.cancel(); // No Meta watchdog on raster.
      final controller = _mapController;
      if (controller == null) return; // First build: initStyle covers it.
      _armFallbackLoadTimer();
      controller.setStyle(cartoFallbackStyleJson(dark: dark));
      return;
    }
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
    _armFallbackLoadTimer();
    setState(() {}); // Attribution chip switches to OSM + CARTO.
  }

  /// Arms the 8 s timer that verifies the CartoDB raster style
  /// actually loaded after a switch to it (or after the tab
  /// starts on it under the Nov 9 raster test): if it never
  /// reports loaded, both tile sources have failed — show the
  /// banner instead of sitting on a blank map silently.
  void _armFallbackLoadTimer() {
    _fallbackLoadTimer?.cancel();
    _fallbackLoadTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted ||
          _styleMode != _MapStyleMode.cartoFallback ||
          _fallbackLoaded) {
        return;
      }
      setState(() => _tilesFailed = true);
    });
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

  /// Retries the tile sources from scratch: back to the start
  /// style, timers re-armed, banner cleared. While the Nov 9
  /// raster diagnostic is on, Retry re-attempts the raster style
  /// (the thing under test), never Meta; with the flag off it
  /// goes back to Meta (the primary) and the normal flow re-runs
  /// from there — style timer, watchdog, probe, fallback. Called
  /// by the banner's Retry button and when the user returns to
  /// the tab after a failure.
  void _retryTileSources() {
    final controller = _mapController;
    if (!mounted || controller == null) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final target = mapRetryTarget(dark: dark);
    _styleLoadTimer?.cancel();
    _tileWatchdogTimer?.cancel();
    _fallbackLoadTimer?.cancel();
    _styleMode = target.isRaster
        ? _MapStyleMode.cartoFallback
        : _MapStyleMode.meta;
    _activeStyleUrl = target.isRaster
        ? _cartoFallbackSentinel
        : metaMapStyleUrl(dark: dark);
    _styleLoaded = false;
    _fallbackLoaded = false;
    _lastStyleDark = dark;
    if (_tilesFailed) {
      setState(() => _tilesFailed = false);
    }
    if (target.isRaster) {
      _armFallbackLoadTimer();
    } else {
      _armStyleFallbackTimer();
    }
    controller.setStyle(target.style);
  }

  /// "Couldn't load the map" banner (shown only when
  /// [_tilesFailed]): a card beside the top-right controls with
  /// a short message and a Retry button that re-attempts the
  /// start style (raster while the Nov 9 test flag is on, Meta
  /// otherwise). English, matching the app's UI language.
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
    } else if (_styleMode == _MapStyleMode.cartoFallback &&
        !_fallbackLoaded) {
      // Nov 9 raster test: the tab starts on the raster style,
      // so verify THAT style loads — otherwise a raster style
      // that never reports loaded would sit blank with no banner.
      _armFallbackLoadTimer();
    }
    _fitActiveRoute();
    // A 3D tap before the native map existed only stored the
    // mode — apply it now that the camera exists.
    if (_viewMode == MapViewMode.perspective3d) {
      unawaited(_applyViewMode());
    }
  }

  /// A style finished loading (Meta, or the CartoDB fallback):
  /// the fallback timer is no longer needed for this style.
  /// For the Meta style, the tile watchdog + probe start here:
  /// the style document arrived, but the tiles may still be
  /// stuck (Steven's white map, Nov 7).
  void _onStyleLoaded(StyleController _) {
    _styleLoadTimer?.cancel();
    _styleLoaded = true;
    // A style reload drops runtime layers, so the extrusion
    // layer is gone even if it was added — reset the flag and
    // let _applyViewMode re-sync it below (3D only).
    _buildingsExtruded = false;
    // A style reload can reset the camera pitch: if the user is
    // in 3D, re-apply the tilt instantly (no animation — the
    // style just loaded, and an animation would replay on every
    // theme switch). 2D needs nothing (pitch 0 is the default).
    if (_viewMode == MapViewMode.perspective3d) {
      unawaited(_applyViewMode(animated: false));
    }
    // One-time smooth auto-focus on the user's location when
    // the tab opens (Nov 11, 2026): fires here — map created
    // + style loaded — and only once per tab lifetime (the
    // flag in _autoFocusOnLocation). Silent: never prompts
    // for permission on open.
    unawaited(_autoFocusOnLocation());
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
      if (jump.startLive) {
        // Start Ride (Nov 8): the Fares sheet asked for Live
        // Follow on this route. Permission is requested here —
        // a denial only shows the honest message; the route
        // still draws.
        await _startLiveFollow();
      }
    }
  }

  @override
  void dispose() {
    communityMapJump.removeListener(_onCommunityJump);
    faresMapJump.removeListener(_onFaresJump);
    mapLineMakerRequest.removeListener(_onLineMakerRequest);
    mapSetEndpointsRequest.removeListener(_onSetEndpointsRequest);
    WidgetsBinding.instance.removeObserver(this);
    _sheetController.removeListener(_onSheetExtentChanged);
    _styleLoadTimer?.cancel();
    _tileWatchdogTimer?.cancel();
    _fallbackLoadTimer?.cancel();
    _routeDrawTimer?.cancel();
    _routePulseTimer?.cancel();
    _livePositionSub?.cancel();
    _liveCompassSub?.cancel();
    _liveGpsLostTimer?.cancel();
    _liveFrameTicker?.stop();
    _liveFrameTicker?.dispose();
    _liveCameraTimer?.cancel();
    _liveClockTimer?.cancel();
    _sheetController.dispose();
    _sheetFocusNode.dispose();
    _bearing.dispose();
    _liveHaloController.dispose();
    super.dispose();
  }






  // ---- Admin-added routes (Add Route) ----







  void _snack(String message) {
    if (!mounted) return;
    TopPopup.show(context, message: message);
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

  /// My Location turns Live Follow ON (Nov 11, 2026): while
  /// follow is active but paused it resumes follow; when follow
  /// is not active it starts it. Only when starting fails
  /// (permission denied — [_startLiveFollow] already showed the
  /// honest message) does it fall back to the old behaviour:
  /// one position + a move to it.
  Future<void> _goToMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (_liveFollowActive) {
        if (_liveFollowPaused) _resumeLiveFollow();
        return;
      }
      if (await _startLiveFollow()) return;
      final position = await _ensurePosition();
      if (position == null || !mounted) return;
      setState(() {
        _userPos = position;
        _locationGranted = true;
      });
      // 120 ms (Steven's pick, Nov 11): fast but still eased,
      // so it reads as a smooth glide, not a snap.
      await _moveTo(
        LatLng(position.latitude, position.longitude),
        zoom: 15,
        duration: const Duration(milliseconds: 120),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// One-time smooth auto-focus on the user's location when the
  /// Map tab opens (Nov 11, 2026): once the map + style are
  /// ready (called from [_onStyleLoaded]), if location
  /// permission is ALREADY granted and a position is available,
  /// fly the camera to the user once — the same animated
  /// [_moveTo] the My Location button uses (zoom 15, 120 ms —
  /// Steven's pick: fast but still eased, so it reads as a
  /// smooth glide, not a snap). Never prompts for permission
  /// and never shows a message on open; the permission prompt
  /// stays on My Location / Live Follow. Never starts Live
  /// Follow — a one-time fly-to only; Live Follow still starts
  /// only via My Location / Start. If anything is missing
  /// (service off, permission denied, no position), the tab
  /// keeps today's behaviour: the active route stays fitted.
  /// Takes precedence over the route fit on open (Steven's
  /// pick); the route stays drawn and Overview / fit-route
  /// still shows the whole route.
  Future<void> _autoFocusOnLocation() async {
    if (!mounted || _mapController == null) return;
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    final permission = await Geolocator.checkPermission();
    // One attempt per tab lifetime: the decision reads the
    // flag, and the flag is claimed here regardless of the
    // outcome, so a style reload / theme switch can never
    // re-fire it.
    final fire = shouldAutoFocusOnLocation(
      alreadyDone: _autoFocusDone,
      locationServiceEnabled: serviceEnabled,
      permission: permission,
    );
    _autoFocusDone = true;
    if (!fire) return;
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return;
    }
    // Live Follow started while the fix was loading: the
    // camera is already on the user — do not fight it.
    if (!mounted || _mapController == null || _liveFollowActive) return;
    setState(() {
      _userPos = position;
      _locationGranted = true;
    });
    await _moveTo(
      LatLng(position.latitude, position.longitude),
      zoom: 15,
      duration: const Duration(milliseconds: 120),
    );
  }

  // ---- Live Follow (Nov 8, 2026) ----

  /// Starts Live Follow: the camera follows the phone's live
  /// GPS in 3D (pitch 60°, bearing follows the direction of
  /// travel) while a route is active — or the live position
  /// alone when no route is active. Returns false when follow
  /// could not start: location off, permission denied, or the
  /// location API failed. Follow never starts without
  /// permission and never tracks silently; every denial shows
  /// an honest message with the phone steps to enable it.
  Future<bool> _startLiveFollow() async {
    if (_liveFollowActive) return true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Turn on Location (GPS) on your phone first.');
        return false;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _snack(
          'Location permission is needed to follow your ride. '
          'Turn it on in Settings > Location.',
        );
        return false;
      }
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return false;
        TopPopup.show(context, message: 'Location is blocked for EstudyanteGO. Turn it on in ' 'Settings > Apps > EstudyanteGO > Permissions > ' 'Location.', actionLabel: 'Open Settings', onAction: () => Geolocator.openAppSettings());
        return false;
      }
    } catch (_) {
      _snack('Location is unavailable on this device right now.');
      return false;
    }
    // Permission granted: save the view mode to restore on exit,
    // switch to 3D, and start tracking.
    _livePrevViewMode = _viewMode;
    _liveSpeed.clear();
    _liveGpsBearing = 0;
    _liveTargetBearing = 0;
    _liveCompassSub?.cancel();
    _liveCompassSub = null;
    _liveCompassHeading = null;
    _livePositionFilter.clear();
    _liveSmoothedPos = null;
    _liveLastCameraTarget = null;
    _liveLastCameraBearing = 0;
    _livePrevPos = null;
    _livePrevPosAt = null;
    _liveLastMovingAt = null;
    _liveLastGoodRemainingMin = null;
    _liveLastGoodArrival = null;
    _liveSnapshot = null;
    _liveGpsLost = false;
    _liveFollowPaused = false;
    // Fresh Live session: no manual zoom, and the first camera
    // move eases into the close view.
    _liveUserZoom = null;
    _liveEaseInDone = false;
    _livePausedByGesture = false;
    setState(() {
      _liveFollowActive = true;
      _liveFollowStartedAt = DateTime.now();
      _locationGranted = true;
    });
    await _setViewMode(MapViewMode.perspective3d);
    _snapSheet(_SheetSnap.half);
    // First fix now (centres the camera at once) + a stream for
    // the ride. Stream errors mean the GPS feed died — show the
    // honest lost state and keep the last known position.
    try {
      final first = await Geolocator.getCurrentPosition();
      if (mounted && _liveFollowActive) _onLivePosition(first);
    } catch (_) {
      // The stream below still delivers fixes; a missing first
      // fix only delays the first camera move.
    }
    _livePositionSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen(
      _onLivePosition,
      onError: (_) {
        if (!mounted || !_liveFollowActive) return;
        setState(() => _liveGpsLost = true);
        _snack('GPS signal lost — showing your last known position.');
      },
    );
    _armLiveGpsLostTimer();
    // Compass heading: the native sensor stream (MainActivity
    // EventChannel), Live only. No sensor on this device =
    // the channel errors and heading stays on GPS bearing;
    // malformed / unreliable readings are ignored the same
    // way in _onLiveCompass.
    _liveCompassSub =
        const EventChannel(liveCompassChannelName)
            .receiveBroadcastStream()
            .listen(
              _onLiveCompass,
              onError: (_) {
                // No compass sensor / channel error: Live
                // Follow keeps working on GPS bearing alone.
              },
            );
    _liveLastFrameElapsed = null;
    _liveFrameTicker = createTicker(_onLiveFrame)..start();
    _liveCameraTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => _liveCameraTick(),
    );
    _liveClockTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _liveClockTick(),
    );
    return true;
  }

  /// Ends Live Follow: stops GPS tracking, restores the view
  /// mode from before the ride, and fits the active route back
  /// into view.
  void _stopLiveFollow() {
    if (!_liveFollowActive) return;
    _livePositionSub?.cancel();
    _livePositionSub = null;
    _liveCompassSub?.cancel();
    _liveCompassSub = null;
    _liveCompassHeading = null;
    _liveGpsLostTimer?.cancel();
    _liveFrameTicker?.stop();
    _liveFrameTicker?.dispose();
    _liveFrameTicker = null;
    _liveLastFrameElapsed = null;
    _liveLastFixAt = null;
    _liveSnappedDistanceKm = null;
    _liveCameraTimer?.cancel();
    _liveClockTimer?.cancel();
    _liveUserZoom = null;
    _liveEaseInDone = false;
    _livePausedByGesture = false;
    final prevMode = _livePrevViewMode;
    setState(() {
      _liveFollowActive = false;
      _liveFollowPaused = false;
      _liveGpsLost = false;
      _liveSnapshot = null;
      _liveMarkerPos = null;
      _liveTargetPos = null;
      _livePositionFilter.clear();
      _liveSmoothedPos = null;
      _liveLastCameraTarget = null;
      _liveLastCameraBearing = 0;
      _liveFollowStartedAt = null;
      _liveLastMovingAt = null;
      _liveLastGoodRemainingMin = null;
      _liveLastGoodArrival = null;
    });
    unawaited(_setViewMode(prevMode));
    if (_activeRoute != null) _fitActiveRoute();
  }

  /// One compass reading from the native channel: low-pass
  /// filters the heading, then steers the target bearing —
  /// the compass wins while stopped or slow (so rotating the
  /// phone turns the map with no GPS movement), GPS bearing
  /// wins at speed (see [blendLiveHeading]). The smoothed
  /// live bearing eases toward the target (shortest arc); the
  /// 150 ms camera tick follows it, so the map turns smoothly
  /// instead of snapping. A malformed event is ignored, and a
  /// reading from an unreliable sensor (uncalibrated
  /// magnetometer) is ignored too — the previous heading
  /// stands, never a guessed one.
  ///
  /// Note on the old accuracy filter: the plugin reported
  /// accuracy as a degree deviation mapped from the sensor
  /// status (high 15 / medium 30 / low 45 / unreliable
  /// absent), so the old `accuracy > 45` check could never
  /// fire. The native channel reports the raw status
  /// instead, and unreliable (0) is rejected here.
  void _onLiveCompass(dynamic event) {
    if (!_liveFollowActive || !mounted) return;
    final reading = parseNativeCompassEvent(event);
    if (reading == null) return;
    if (!isCompassReadingUsable(reading)) return;
    final heading = reading.heading;
    _liveCompassHeading = _liveCompassHeading == null
        ? heading
        : smoothCompassHeading(
            previous: _liveCompassHeading!,
            compass: heading,
          );
    _liveTargetBearing = blendLiveHeading(
      gpsBearing: _liveGpsBearing,
      compassHeading: _liveCompassHeading,
      speedKmh: _liveSpeed.averageKmh,
    );
    _liveBearing = lerpAngleDeg(_liveBearing, _liveTargetBearing, 0.3);
  }

  /// One live GPS fix: smooths the position (see
  /// PositionSmoother) and the speed, steers the bearing, and
  /// recomputes the trip snapshot. The camera is NOT moved
  /// here — the 150 ms camera tick follows the gliding marker
  /// continuously instead (see _liveCameraTick). The position
  /// itself is never faked — a missing fix simply leaves the
  /// last known position in place (see the lost timer).
  void _onLivePosition(Position pos) {
    if (!_liveFollowActive || !mounted) return;
    final now = DateTime.now();
    final raw = LatLng(pos.latitude, pos.longitude);
    // Smooth the fix first (Nov 11, 2026): jitter averages
    // out and wild jumps are dropped outright — the marker,
    // camera, bearing and snapshot all run on the smoothed
    // point, never the raw fix. A rejected fix means the GPS
    // is alive but this one fix is nonsense: keep the last
    // good position and re-arm the lost timer.
    final smoothed = _livePositionFilter.add(
      raw,
      accuracy: pos.accuracy,
      at: now,
      speedMps: pos.speed >= 0 ? pos.speed : null,
    );
    if (smoothed == null) {
      _armLiveGpsLostTimer();
      return;
    }
    final here = smoothed;
    _liveSmoothedPos = here;
    // Speed: the GPS-reported speed when the device gives one
    // (>= 0 m/s), else derived from the last two fixes. The
    // smoother averages the last few samples so one noisy fix
    // cannot swing the ETA.
    double? kmh;
    if (pos.speed >= 0) {
      kmh = pos.speed * 3.6;
    } else if (_livePrevPos != null && _livePrevPosAt != null) {
      kmh = speedKmhBetween(
        prev: _livePrevPos!,
        next: here,
        delta: now.difference(_livePrevPosAt!),
      );
    }
    if (kmh != null) {
      _liveSpeed.add(kmh);
      if (kmh > liveMinMovingKmh) _liveLastMovingAt = now;
    }
    // Bearing follows the direction of travel: only when the bus
    // actually moved (10 m+), so GPS jitter at a stop does not
    // spin the camera. The bearing is approached gradually
    // (shortest arc), never snapped. The GPS bearing is kept
    // separate from the blended target: on every fix the target
    // is re-blended from it (see blendLiveHeading), so a stale
    // compass value never survives a moving fix.
    if (_livePrevPos != null) {
      final movedKm =
          distanceAlongPath([_livePrevPos!, here], 0, 1);
      if (movedKm >= 0.01) {
        _liveGpsBearing = bearingBetween(_livePrevPos!, here);
      }
    }
    _liveTargetBearing = blendLiveHeading(
      gpsBearing: _liveGpsBearing,
      compassHeading: _liveCompassHeading,
      speedKmh: _liveSpeed.averageKmh,
    );
    _liveBearing = lerpAngleDeg(_liveBearing, _liveTargetBearing, 0.3);
    _livePrevPos = here;
    _livePrevPosAt = now;
    // Snap-to-road (Nov 13, 2026 — Google-level smoothing):
    // the marker + camera follow the fix projected onto the
    // road, so GPS jitter never pulls the arrow onto buildings
    // or side streets — but ONLY when the fix is actually near
    // the road ([liveSnapIsOnRoute], 50 m). A fix far from the
    // route (at home in Aragan, off the Cabugao → Vigan road)
    // keeps its true smoothed position instead of being dragged
    // onto the highway, and its distance-along-road is cleared
    // so prediction dead-reckons along the bearing instead of
    // advancing along the road. No geometry loaded yet = the
    // smoothed fix itself. The Live panel snapshot below still
    // uses the smoothed fix, so its numbers do not change.
    final snapped = snapToRoad(position: here, roadPoints: _roadPoints);
    final onRoute = liveSnapIsOnRoute(snapped);
    _liveTargetPos = onRoute ? snapped!.point : here;
    _liveSnappedDistanceKm =
        onRoute ? snapped?.distanceAlongKm : null;
    _liveLastFixAt = now;
    _liveMarkerPos ??= _liveTargetPos;
    setState(() {
      _userPos = pos;
      _liveGpsLost = false;
      final route = _activeRoute;
      final totalKm =
          _routeDistanceKm > 0 ? _routeDistanceKm : (route?.roadKm ?? 0);
      _liveSnapshot = computeLiveFollow(
        roadPoints: _roadPoints,
        origin: _activeRouteOrigin,
        stops: _routeStops,
        position: here,
        totalKm: totalKm,
        speedKmh: _liveSpeed.averageKmh,
        now: now,
      );
      final snap = _liveSnapshot!;
      if (snap.remainingMinutes != null) {
        _liveLastGoodRemainingMin = snap.remainingMinutes;
        _liveLastGoodArrival = snap.arrivalTime;
      }
    });
    _armLiveGpsLostTimer();
  }

  /// Re-arms the GPS-lost timer: no fix for [liveGpsLostAfter]
  /// shows the honest lost state (the camera stays at the last
  /// known position — movement is never faked).
  void _armLiveGpsLostTimer() {
    _liveGpsLostTimer?.cancel();
    _liveGpsLostTimer = Timer(liveGpsLostAfter, () {
      if (!mounted || !_liveFollowActive) return;
      setState(() => _liveGpsLost = true);
    });
  }

  /// Per-frame Live interpolation (Nov 13, 2026 — Google-level
  /// smoothing, Preview v2): on every display frame the arrow
  /// eases toward the predicted target (see
  /// [_livePredictedTarget]) with frame-rate-independent
  /// exponential smoothing (tau ~0.25 s), so it moves every
  /// frame at the real speed between the ~1/sec GPS fixes
  /// instead of stepping every 200 ms — and a new fix corrects
  /// it smoothly instead of teleporting it. The dt clamp (0.1 s)
  /// covers a resumed / backgrounded app. Skips the rebuild
  /// when the move is under ~0.3 m (invisible).
  void _onLiveFrame(Duration elapsed) {
    if (!_liveFollowActive || !mounted) return;
    final prev = _liveLastFrameElapsed;
    _liveLastFrameElapsed = elapsed;
    final dtSeconds = prev == null
        ? 0.016
        : ((elapsed - prev).inMilliseconds / 1000).clamp(0.0, 0.1);
    final predicted = _livePredictedTarget();
    final current = _liveMarkerPos;
    if (predicted == null) return;
    if (current == null) {
      setState(() => _liveMarkerPos = predicted);
      return;
    }
    final k = 1 - math.exp(-dtSeconds / 0.25);
    final next = lerpLatLng(current, predicted, k);
    if (distanceAlongPath([current, next], 0, 1) < 0.0003) return;
    setState(() => _liveMarkerPos = next);
  }

  /// Where the arrow should be right now: the last fix advanced
  /// at the last smoothed speed for the time since that fix —
  /// along the road when the fix was snapped on-route
  /// ([_liveSnappedDistanceKm] set), or dead-reckoned along the
  /// bearing when the fix is off-route (distance cleared, so an
  /// off-route position is never dragged onto the road) — but
  /// only while prediction may coast ([livePredictionShouldCoast],
  /// 3 s). After that the arrow holds its last position (the
  /// target itself) until a new fix arrives; the 10 s
  /// [liveGpsLostAfter] timer then raises the honest lost state.
  /// Movement is never faked beyond the brief coast.
  LatLng? _livePredictedTarget() {
    final target = _liveTargetPos;
    final lastFix = _liveLastFixAt;
    if (target == null || lastFix == null) return target;
    if (!livePredictionShouldCoast(
      lastFixAt: lastFix,
      now: DateTime.now(),
    )) {
      return target;
    }
    return predictLivePosition(
      from: target,
      bearingDeg: _liveTargetBearing,
      speedKmh: _liveSpeed.averageKmh,
      elapsed: DateTime.now().difference(lastFix),
      roadPoints: _roadPoints,
      distanceAlongKm: _liveSnappedDistanceKm,
    );
  }

  /// Refreshes the Live panel clock (elapsed / arrival) while
  /// the bus is stopped — no new GPS fixes arrive then, so the
  /// elapsed time would freeze without it. Only recomputes the
  /// snapshot while the bus is still moving; a stopped bus keeps
  /// its last good ETA (labelled in the panel), never a fresh
  /// guess from a stale speed.
  void _liveClockTick() {
    if (!_liveFollowActive || !mounted) return;
    final pos = _liveSmoothedPos ??
        (_userPos == null
            ? null
            : LatLng(_userPos!.latitude, _userPos!.longitude));
    if (pos == null) return;
    setState(() {
      final snap = _liveSnapshot;
      if (snap != null && snap.remainingMinutes != null) {
        // Still moving: the arrival clock time advances with now.
        final route = _activeRoute;
        final totalKm = _routeDistanceKm > 0
            ? _routeDistanceKm
            : (route?.roadKm ?? 0);
        _liveSnapshot = computeLiveFollow(
          roadPoints: _roadPoints,
          origin: _activeRouteOrigin,
          stops: _routeStops,
          position: pos,
          totalKm: totalKm,
          speedKmh: _liveSpeed.averageKmh,
          now: DateTime.now(),
        );
      }
      // Stopped / no speed yet: no recompute — the panel keeps
      // the last good ETA (labelled) or "calculating…", and the
      // elapsed chip still ticks from _liveFollowStartedAt.
    });
  }

  /// Continuous follow-camera tick (Nov 11, 2026): every
  /// 150 ms the camera eases toward the gliding marker with a
  /// short (200 ms) animation, so it moves continuously
  /// between GPS fixes instead of sitting still and then
  /// jumping once per fix. Skipped while paused or while a
  /// move is in flight, and skipped when the marker has
  /// barely moved since the last camera move (see
  /// liveCameraShouldMove) — a stopped bus does not
  /// re-animate the camera on every tick.
  void _liveCameraTick() {
    if (!_liveFollowActive || !mounted) return;
    unawaited(_liveMoveCameraToMarker());
  }

  /// One smooth follow-camera move: a short (200 ms) glide to
  /// the interpolated marker position in 3D, bearing
  /// following the direction of travel. The 150 ms tick is the
  /// cadence — there is no per-fix throttle any more, so a
  /// move is never stacked behind a 900 ms wait. [force]
  /// bypasses the barely-moved skip rule (resume after a
  /// stop-chip pause: the camera flew to a stop and must come
  /// back to the marker even if the bus barely moved). The
  /// camera settles at the close follow zoom
  /// ([liveCloseFollowZoom]) — or at the user's manual zoom
  /// while one is set (see [_liveUserZoom]). The first move of
  /// a session eases in over ~1 s ([liveCloseFollowEaseIn]);
  /// later moves use the 200 ms glide. No 360° spin.
  Future<void> _liveMoveCameraToMarker({bool force = false}) async {
    final controller = _mapController;
    final target = _liveMarkerPos ??
        _liveSmoothedPos ??
        (_userPos == null
            ? null
            : LatLng(_userPos!.latitude, _userPos!.longitude));
    if (controller == null || target == null) return;
    if (_liveFollowPaused || _liveCameraBusy) return;
    if (!force &&
        !liveCameraShouldMove(
          lastTarget: _liveLastCameraTarget,
          lastBearing: _liveLastCameraBearing,
          target: target,
          bearing: _liveBearing,
        )) {
      return;
    }
    _liveLastCameraTarget = target;
    _liveLastCameraBearing = _liveBearing;
    _liveCameraBusy = true;
    // First move of the session: ease into the close view
    // (~1 s) instead of snapping to it.
    final duration = _liveEaseInDone
        ? const Duration(milliseconds: 200)
        : liveCloseFollowEaseIn;
    _liveEaseInDone = true;
    try {
      await controller.animateCamera(
        center: Geographic(lon: target.longitude, lat: target.latitude),
        zoom: liveFollowZoom(userZoom: _liveUserZoom),
        pitch: 60,
        bearing: _liveBearing,
        nativeDuration: duration,
      );
    } catch (_) {
      // Interrupted by a newer camera move — the next one lands.
    } finally {
      _liveCameraBusy = false;
    }
  }

  /// A Live stop-chip tap: pauses the follow camera so the stop
  /// flight is not yanked back by the next GPS update, then
  /// flies to the stop (GPS + stats keep running).
  Future<void> _onLiveStopTap(int index) async {
    if (!_liveFollowActive) return;
    setState(() => _liveFollowPaused = true);
    await _selectStop(index);
  }

  /// Resumes the follow camera after a stop-chip pause.
  /// Resume re-fits: a manual zoom made during Live is dropped
  /// and the follow camera settles back at the close zoom.
  /// Forced: the camera flew to a stop while paused, so it
  /// must come back to the marker even if the bus barely
  /// moved since the last camera move.
  void _resumeLiveFollow() {
    if (!_liveFollowActive) return;
    _liveUserZoom = null;
    _livePausedByGesture = false;
    setState(() => _liveFollowPaused = false);
    unawaited(_liveMoveCameraToMarker(force: true));
  }

  /// Camera idle after a Live gesture pause (Nov 11, 2026 —
  /// Live close-follow): a pinch / double-tap zoom paused
  /// follow on gesture start, but the user only changed the
  /// zoom — keep following at the new zoom instead of snapping
  /// back to the close zoom. A drag or rotate leaves follow
  /// paused (today's behaviour); the Resume control re-centres.
  /// Only gesture pauses are reconsidered here — tap-to-zoom,
  /// stop-chip and Overview pauses stay paused until Resume.
  void _onLiveCameraIdle() {
    if (!_liveFollowActive || !_liveFollowPaused || !_livePausedByGesture) {
      return;
    }
    if (!liveGestureWasZoom(
      startZoom: _liveGestureStartZoom,
      zoom: _mapZoom,
    )) {
      // A drag / rotate: follow stays paused.
      _livePausedByGesture = false;
      return;
    }
    _liveUserZoom = _mapZoom;
    _livePausedByGesture = false;
    setState(() => _liveFollowPaused = false);
    unawaited(_liveMoveCameraToMarker());
  }

  /// A plain map tap (no special mode, no stop card open):
  /// zoom in on the tapped point — two levels closer
  /// ([liveTapZoomTarget]), eased over ~0.85 s. While Live
  /// Follow is active the tap first pauses follow (same as a
  /// stop-chip tap), so the next GPS update does not yank the
  /// camera back to the marker mid-zoom.
  Future<void> _onPlainMapTapZoom(Geographic point) async {
    final controller = _mapController;
    if (controller == null) return;
    if (_liveFollowActive && !_liveFollowPaused) {
      setState(() => _liveFollowPaused = true);
    }
    final target = LatLng(point.lat, point.lon);
    final zoom = liveTapZoomTarget(_mapZoom);
    try {
      await controller.animateCamera(
        center: Geographic(lon: target.longitude, lat: target.latitude),
        zoom: zoom,
        nativeDuration: const Duration(milliseconds: 850),
      );
      _mapCenter = target;
      _mapZoom = zoom;
    } catch (_) {
      // Interrupted by a newer camera move — the newer one
      // owns the view.
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
  ///
  /// [duration] overrides the flight time: the My Location
  /// jump and the one-time auto-focus on open use 120 ms
  /// (Steven's pick, Nov 11 — fast but still eased, so it
  /// reads as a smooth glide, not a snap). Hub / stop / nav
  /// flights keep the 1400 ms default.
  Future<void> _flyTo(
    LatLng target, {
    double zoom = 13,
    Duration duration = const Duration(milliseconds: 1400),
  }) async {
    final controller = _mapController;
    if (controller == null) return;
    final generation = ++_flyGeneration;
    var landed = false;
    try {
      await controller.animateCamera(
        center: Geographic(lon: target.longitude, lat: target.latitude),
        zoom: zoom,
        nativeDuration: duration,
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

  Future<void> _moveTo(
    LatLng target, {
    double zoom = 13,
    Duration duration = const Duration(milliseconds: 1400),
  }) async {
    // Animated: a jump (my-location, hub tap, nav start) keeps
    // the current rotation instead of flattening it.
    await _flyTo(target, zoom: zoom, duration: duration);
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

  /// Switches the map between 2D (flat, north-up) and 3D
  /// (perspective tilt, bearing kept). Camera-only: no route,
  /// stop, or fare state changes. A tap before the native map
  /// exists only stores the mode; the camera applies once the
  /// map is created (see _onMapCreated).
  Future<void> _setViewMode(MapViewMode mode) async {
    if (mode == _viewMode) return;
    setState(() => _viewMode = mode);
    await _applyViewMode();
  }

  /// Applies [_viewMode] to the live camera: 3D tilts to 60°
  /// ([tiltForMode]) keeping the current bearing; 2D flattens to
  /// 0° and faces north again ([bearingForMode]). [animated]
  /// picks the 800 ms tilt animation (mode taps, map creation)
  /// or an instant move (style reloads, where an animation
  /// would replay on every theme switch). No-op when the native
  /// map is not created yet — the mode is stored and applied on
  /// creation / style load.
  ///
  /// Buildings: after the camera move, [_syncBuildingsExtrusion]
  /// adds the runtime fill-extrusion layer in 3D (Meta style
  /// only) and removes it in 2D, so the style's building
  /// footprints rise as 3D blocks only while 3D is on.
  Future<void> _applyViewMode({bool animated = true}) async {
    final controller = _mapController;
    if (controller == null) return;
    final pitch = tiltForMode(_viewMode);
    try {
      if (animated) {
        final camera = controller.getCamera();
        await controller.animateCamera(
          pitch: pitch,
          bearing: bearingForMode(_viewMode, camera.bearing),
          nativeDuration: const Duration(milliseconds: 800),
        );
      } else {
        await controller.moveCamera(pitch: pitch);
      }
    } catch (_) {
      // Interrupted by a newer camera move, or the map is not
      // attached yet — the next camera move still lands.
    }
    unawaited(_syncBuildingsExtrusion());
  }

  /// Adds or removes the runtime 3D buildings extrusion layer
  /// ([kBuildings3dExtrusionLayer]) so it matches [_viewMode]
  /// and [_styleMode]: present only in 3D on the Meta style,
  /// absent in 2D and on the CartoDB fallback (a raster style
  /// has no vector building source to extrude). Called from
  /// [_applyViewMode] (mode taps, map creation, style loads).
  /// Never throws — a native failure just leaves the map as it
  /// was (flat buildings), so a missing layer can never break
  /// the map. [_buildingsExtruded] tracks whether the layer is
  /// currently added; it is reset in [_onStyleLoaded] because a
  /// style reload drops runtime layers.
  Future<void> _syncBuildingsExtrusion() async {
    final style = _mapController?.style;
    if (style == null) return;
    final want =
        _styleMode == _MapStyleMode.meta &&
        buildingsForMode(_viewMode);
    if (want == _buildingsExtruded) return;
    try {
      if (want) {
        try {
          await style.addLayer(
            kBuildings3dExtrusionLayer,
            aboveLayerId: kBuildings3dAnchorLayerId,
          );
        } catch (_) {
          // Anchor layer missing (style revision) — append on
          // top instead; still 3D, just above the labels.
          await style.addLayer(kBuildings3dExtrusionLayer);
        }
        _buildingsExtruded = true;
      } else {
        await style.removeLayer(kBuildings3dLayerId);
        _buildingsExtruded = false;
      }
    } catch (_) {
      // Native layer call failed (map tearing down, style
      // reloading) — leave the flag as it was; the next style
      // load / mode tap re-syncs.
    }
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
      // The dashed fallback line draws in too.
      _startRouteLineAnimation();
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
    // The road shape just landed: draw the line in from the
    // origin, then run the pulse. Starts after the setState
    // above so the animation's first frame already trims it.
    _startRouteLineAnimation();
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
  /// lights up (soft glow + white casing + wide blue core)
  /// while the earlier part dims; tapping the destination leaves
  /// nothing lit. Dismissing the card restores this normal
  /// approved blue line (10 px core on a 14 px white casing).
  /// One [PolylineLayer] per visual style
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
      liveMode: _liveFollowActive,
      drawProgress: _routeDrawProgress,
      pulseHead: _routePulseHead >= 0 ? _routePulseHead : null,
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

  /// Starts the approved route-line entrance animation for the
  /// current route: the line draws itself from origin to
  /// destination over ~1.4 s, then the highlight pulse travels
  /// it twice. No-op while the admin is drawing (the amber
  /// draft is the focus there) and when no route is active.
  /// Called when a road fetch settles (success or dashed
  /// fallback) and by the Replay button. A running animation
  /// is cancelled first, so a fast route change never leaves
  /// two timers stepping the same progress.
  void _startRouteLineAnimation() {
    _routeDrawTimer?.cancel();
    _routePulseTimer?.cancel();
    if (_activeRoute == null ||
        _activeRouteOrigin == null ||
        _lineMakerActive) {
      _routeDrawProgress = 1.0;
      _routePulseHead = -1;
      return;
    }
    // Reset visibly in the same frame the fetch settles, so
    // the full line never flashes for one frame before the
    // draw-in starts trimming it.
    if (mounted) {
      setState(() {
        _routeDrawProgress = 0.0;
        _routePulseHead = -1;
      });
    }
    var steps = 0;
    _routeDrawTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        steps++;
        setState(() {
          _routeDrawProgress = (steps / 28).clamp(0.0, 1.0);
        });
        if (steps >= 28) {
          timer.cancel();
          _startRoutePulse();
        }
      },
    );
  }

  /// Travelling highlight after the draw-in: the pulse head
  /// advances 1/60 of the route per 50 ms tick (~3 s per
  /// traversal) for two traversals, then the pulse layer is
  /// removed and the timers stop.
  void _startRoutePulse() {
    _routePulseTimer?.cancel();
    _routePulseHead = 0.0;
    var loops = 0;
    _routePulseTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _routePulseHead += 1 / 60;
          if (_routePulseHead >= 1.0) {
            _routePulseHead = 0.0;
            loops++;
            if (loops >= 2) {
              timer.cancel();
              _routePulseHead = -1;
            }
          }
        });
      },
    );
  }

  /// Replay control (bottom-left, next to the attribution
  /// button): re-runs the draw-in + pulse for the current
  /// route. No-op with no active route.
  void _replayRouteLineAnimation() {
    if (_activeRoute == null || _activeRouteOrigin == null) return;
    _startRouteLineAnimation();
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
    // built-in blue dot). During Live Follow it is a navigation
    // ARROW (Nov 13, 2026 — approved Preview v2, Arrow option),
    // riding the interpolated position so it glides instead of
    // jumping between fixes. Only the arrow itself rotates, to
    // point along the direction of travel ON SCREEN (live
    // bearing minus the map's bearing — in heading-up Live mode
    // that is 0, so it points straight up). The old marker
    // rotated the whole green circle + car glyph, so at an angle
    // the glyph read like a sideways door; the arrow never does.
    // A heading cone + pulsing halo sit behind the arrow while
    // GPS is locked; when the signal is lost the arrow goes
    // grey with an amber dashed ring and NO cone / NO pulse, so
    // a stale position never looks live. Tapping it focuses the
    // live marker and resumes Follow (see _resumeLiveFollow).
    // Style decision lives in liveArrowMarkerStyle() (see
    // live_follow.dart) and is pinned in tests.
    if (_userPos != null && _locationGranted) {
      if (_liveFollowActive) {
        final markerPos = _liveMarkerPos ??
            LatLng(_userPos!.latitude, _userPos!.longitude);
        final rotationDeg = liveMarkerScreenRotationDeg(
          liveBearing: _liveBearing,
          mapBearing: _bearing.value,
        );
        final style = liveArrowMarkerStyle(gpsLost: _liveGpsLost);
        markers.add(
          Marker(
            point: Geographic(
              lon: markerPos.longitude,
              lat: markerPos.latitude,
            ),
            size: const Size(104, 104),
            child: GestureDetector(
              onTap: _resumeLiveFollow,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Heading cone (locked only): apex points along
                  // the direction of travel, same rotation as the
                  // arrow.
                  if (style.showHeadingCone)
                    Transform.rotate(
                      angle: rotationDeg * math.pi / 180,
                      child: const CustomPaint(
                        size: Size(104, 104),
                        painter: _LiveHeadingConePainter(),
                      ),
                    ),
                  // Pulsing GPS halo (locked only): breathes via
                  // the tab-owned controller so the 200 ms marker
                  // ticks never restart it.
                  if (style.showHalo)
                    AnimatedBuilder(
                      animation: _liveHaloController,
                      builder: (context, child) {
                        final t = _liveHaloController.value;
                        return Container(
                          width: 74 + 14 * t,
                          height: 74 + 14 * t,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF17CE62)
                                .withValues(alpha: 0.28 - 0.14 * t),
                          ),
                        );
                      },
                    ),
                  // Amber dashed ring (lost only): the stale
                  // position marker, no cone, no pulse.
                  if (style.showLostRing)
                    const CustomPaint(
                      size: Size(84, 84),
                      painter: _LiveLostRingPainter(),
                    ),
                  // 56dp arrow core: green gradient when locked,
                  // grey when lost. Only the arrow rotates.
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Color(style.coreStart),
                          Color(style.coreEnd),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Transform.rotate(
                      angle: rotationDeg * math.pi / 180,
                      child: const Icon(
                        Icons.navigation,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
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
    // A stop card opened from a Live stop chip paused the follow
    // camera — closing the card resumes it.
    final resumeFollow = _liveFollowActive && _liveFollowPaused;
    setState(() {
      _selectedStopIndex = null;
      if (resumeFollow) _liveFollowPaused = false;
    });
    if (resumeFollow) unawaited(_liveMoveCameraToMarker(force: true));
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

  /// A request from the Account tab's Admin Access section (Nov 8,
  /// 2026 organize) to open this tab with Set Start/End mode
  /// ready. Consumed once, like [mapLineMakerRequest] — the
  /// request is set together with the tab jump, so the mode is
  /// active by the time the tab is visible.
  void _onSetEndpointsRequest() {
    if (!mapSetEndpointsRequest.value) return;
    mapSetEndpointsRequest.value = false;
    if (!mounted || !isAdminUser(widget.currentUser)) return;
    _enterSetEndpointsMode();
  }

  /// Enters draw-line mode for the active route (admin-only,
  /// sheet header button). Requires an active route: the draft
  /// starts pre-filled from that route's current effective
  /// direction. When the route has no saved direction the draft
  /// is empty and NO amber line is drawn until the admin taps —
  /// the blue route line stays visible as the reference (a
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
      startLive: false,
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
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) =>
          _RenameStopDialog(initialName: waypoint.name),
    );
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
    // Live Follow panel replaces the route sheet while follow
    // is active (Steven's Live screen layout).
    if (_liveFollowActive) return _livePanelWidgets(scheme);
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

  /// The Live Follow panel (Nov 8, 2026): Steven's Live screen
  /// layout — header, progress bar with stop dots, three stat
  /// chips, arrived banner, tappable stop chips — in English.
  /// Every number is computed from the live GPS position +
  /// route geometry ([_liveSnapshot]); nothing is hardcoded.
  /// When no route is active the panel says so honestly and
  /// shows only the live position.
  List<Widget> _livePanelWidgets(ColorScheme scheme) {
    final route = _activeRoute;
    final snap = _liveSnapshot;
    final widgets = <Widget>[const SizedBox(height: 4)];
    // Header: bus icon + "Bus · Cabugao → Vigan" + "≈45 min trip".
    // The trip label is the route's own estimate (same model as
    // the preview cards, marked ≈); the ARRIVAL chip below is
    // the live-GPS calculation, never this estimate.
    if (route != null) {
      final totalMin = _previewMinutes(TravelMode.transit);
      widgets.add(
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.directions_bus,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Bus · ${route.originName} → ${route.dest.name}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (totalMin > 0)
              Text(
                '≈${formatTripTime(totalMin)} trip',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      );
    } else {
      widgets.add(
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.directions_bus,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Live · Your position',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
      widgets.add(const SizedBox(height: 8));
      widgets.add(
        Text(
          'No route selected — showing your live position. Pick a '
          'route in Fares to see trip info here.',
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (route != null && snap != null) {
      widgets.add(const SizedBox(height: 14));
      widgets.add(_liveProgressBar(scheme, snap));
      widgets.add(const SizedBox(height: 14));
      widgets.add(_liveStatChips(scheme, snap));
      // Speed + distance row (Nov 11, 2026): the live speed
      // from the GPS snapshot and the travelled / total route
      // distance, in the same chip style as the row above.
      widgets.add(const SizedBox(height: 8));
      widgets.add(
        Row(
          children: [
            Expanded(
              child: _liveStatChip(
                scheme,
                formatLiveSpeedKmh(snap.speedKmh),
                'Speed',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _liveStatChip(
                scheme,
                formatLiveDistanceKm(snap.traveledKm, snap.totalKm),
                'Distance travelled',
              ),
            ),
          ],
        ),
      );
      // Honest status line (only when something is not live).
      final status = _liveStatusText();
      if (status != null) {
        widgets.add(const SizedBox(height: 8));
        widgets.add(
          Text(
            status,
            style: TextStyle(
              fontSize: 12,
              color: _liveGpsLost
                  ? const Color(0xFFB45309)
                  : scheme.onSurfaceVariant,
            ),
          ),
        );
      }
      if (snap.arrived) {
        widgets.add(const SizedBox(height: 12));
        widgets.add(
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.flag,
                  color: Color(0xFF16A34A),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Arrived at ${route.dest.name}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      if (_routeStops.isNotEmpty) {
        widgets.add(const SizedBox(height: 14));
        widgets.add(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _routeStops.length; i++)
                _liveStopChip(scheme, i),
            ],
          ),
        );
      }
    }
    if (_liveFollowPaused) {
      widgets.add(const SizedBox(height: 14));
      widgets.add(
        FilledButton.icon(
          onPressed: _resumeLiveFollow,
          icon: const Icon(Icons.my_location),
          label: const Text('Resume follow'),
        ),
      );
    }
    // Overview (Nov 11, 2026): pauses follow and fits the whole
    // active route, so the user can see the full trip at a
    // glance. Only shown while a route is active — with no route
    // there is nothing to fit.
    if (route != null) {
      widgets.add(const SizedBox(height: 14));
      widgets.add(
        OutlinedButton.icon(
          onPressed: () {
            // Overview re-fits: drop the manual zoom so the
            // next follow move settles at the close zoom again.
            _liveUserZoom = null;
            _livePausedByGesture = false;
            setState(() => _liveFollowPaused = true);
            _fitActiveRoute();
          },
          icon: const Icon(Icons.zoom_out_map),
          label: const Text('Overview'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF16A34A),
            side: const BorderSide(color: Color(0xFF16A34A)),
          ),
        ),
      );
    }
    widgets.add(const SizedBox(height: 14));
    widgets.add(
      OutlinedButton.icon(
        onPressed: _stopLiveFollow,
        icon: const Icon(Icons.stop),
        label: const Text('Stop live follow'),
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.error,
          side: BorderSide(color: scheme.error),
        ),
      ),
    );
    return widgets;
  }

  /// The honest one-line status for the Live panel, or null when
  /// everything is live. Priority: GPS lost > stopped (last
  /// known) > calculating.
  String? _liveStatusText() {
    if (_liveGpsLost) {
      return 'GPS signal lost — showing your last known position.';
    }
    final snap = _liveSnapshot;
    if (snap == null) return 'Calculating arrival from live speed…';
    if (snap.remainingMinutes == null) {
      if (_liveLastGoodRemainingMin != null) {
        return 'Bus stopped — showing the last known arrival.';
      }
      return 'Calculating arrival from live speed…';
    }
    if (_liveBusStopped) {
      return 'Bus stopped — showing the last known arrival.';
    }
    return null;
  }

  /// True when no speed sample above [liveMinMovingKmh] has
  /// arrived for 30 s — the bus counts as stopped, so the panel
  /// shows the last good ETA (labelled) instead of a fresh
  /// guess from a stale speed.
  bool get _liveBusStopped {
    final lastMoving = _liveLastMovingAt;
    if (lastMoving == null) return false;
    if (_liveLastGoodRemainingMin == null) return false;
    return DateTime.now().difference(lastMoving) >
        const Duration(seconds: 30);
  }

  /// Elapsed / Remaining / Arriving chips. Elapsed = time since
  /// Start Ride was tapped. Remaining + arrival come from the
  /// live GPS speed; when the bus is stopped they show the last
  /// good values (labelled by [_liveStatusText]); when no speed
  /// exists yet they show "…" — never a guessed time.
  Widget _liveStatChips(ColorScheme scheme, LiveFollowSnapshot snap) {
    final now = DateTime.now();
    final showLastGood = _liveBusStopped;
    final remainingMin = showLastGood
        ? _liveLastGoodRemainingMin
        : snap.remainingMinutes;
    final arrival =
        showLastGood ? _liveLastGoodArrival : snap.arrivalTime;
    final elapsedMin = _liveFollowStartedAt == null
        ? 0
        : now.difference(_liveFollowStartedAt!).inMinutes;
    return Row(
      children: [
        Expanded(
          child: _liveStatChip(
            scheme,
            formatTripTime(elapsedMin),
            'Elapsed',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _liveStatChip(
            scheme,
            remainingMin == null ? '…' : formatTripTime(remainingMin),
            'Remaining',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _liveStatChip(
            scheme,
            arrival == null ? '…' : formatArrivalTime(arrival),
            'Arriving at terminal',
          ),
        ),
      ],
    );
  }

  Widget _liveStatChip(ColorScheme scheme, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Green progress bar with a dot per stop (Steven's Live
  /// screen): the fill is the travelled fraction of the route,
  /// each dot sits at its stop's fraction along the route
  /// (filled once passed, outlined while upcoming).
  Widget _liveProgressBar(ColorScheme scheme, LiveFollowSnapshot snap) {
    final totalKm = snap.totalKm > 0 ? snap.totalKm : 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 24,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Container(
                height: 8,
                width: width * snap.progress,
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              for (var i = 0; i < _routeStops.length; i++)
                Positioned(
                  left: (width *
                              (_routeStops[i].kmFromOrigin / totalKm) -
                          6)
                      .clamp(0.0, width - 12),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: i <= snap.currentStopIndex
                          ? const Color(0xFF16A34A)
                          : scheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF16A34A),
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// One tappable stop chip: number circle + name. The current
  /// stop (the one the bus is at / last passed) is dark green
  /// filled with white text; the rest are outlined. Tapping
  /// pauses the follow camera and flies to the stop.
  Widget _liveStopChip(ColorScheme scheme, int index) {
    final stop = _routeStops[index];
    final current = index == _liveSnapshot?.currentStopIndex;
    final number = Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: current ? Colors.white : const Color(0xFF16A34A),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '${index + 1}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color:
                current ? const Color(0xFF14532D) : Colors.white,
          ),
        ),
      ),
    );
    final label = Text(
      stop.name,
      style: TextStyle(
        fontSize: 13,
        fontWeight: current ? FontWeight.w700 : FontWeight.w500,
        color: current ? Colors.white : scheme.onSurface,
      ),
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [number, const SizedBox(width: 6), label],
    );
    if (current) {
      return Material(
        color: const Color(0xFF14532D),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _onLiveStopTap(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            child: content,
          ),
        ),
      );
    }
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _onLiveStopTap(index),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF16A34A)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: content,
        ),
      ),
    );
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
            // Theme-driven style: while the Nov 9 raster test
            // flag is on, the CartoDB raster style (dark / light);
            // with the flag off, Meta's Canterbury vector style
            // (dark / light), the same map the preview renders.
            // If it fails to load — or loads but its tiles never
            // render — the timers switch to the theme-aware
            // CartoDB raster fallback style.
            initStyle: mapStartStyle(
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
            } else if (event is MapEventStartMoveCamera) {
              // A user drag breaks Live Follow: pause the follow
              // camera so the next GPS update does not yank the
              // view back while the user is looking around. The
              // Resume control re-centres. Programmatic moves
              // (developerAnimation / apiAnimation — the follow
              // camera itself, flights, view-mode tilts) never
              // pause follow. The zoom the gesture started at is
              // recorded so camera-idle time can tell a pinch /
              // double-tap zoom (resume at the new zoom, see
              // [_onLiveCameraIdle]) from a drag (stay paused).
              if (event.reason == CameraChangeReason.apiGesture &&
                  _liveFollowActive &&
                  !_liveFollowPaused) {
                _liveGestureStartZoom = _mapZoom;
                _livePausedByGesture = true;
                setState(() => _liveFollowPaused = true);
              }
            } else if (event is MapEventCameraIdle) {
              // A gesture (or a camera transition) ended — a
              // zoom gesture paused follow only to be resumed
              // at the new zoom (see [_onLiveCameraIdle]).
              _onLiveCameraIdle();
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
              } else {
                // Plain tap on the open map: zoom in on the
                // tapped point (see _onPlainMapTapZoom). While
                // Live Follow is active the tap first pauses
                // follow, so the zoom is not yanked back.
                _onPlainMapTapZoom(event.point);
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
        // Retry re-attempts the start style (raster while the
        // Nov 9 test flag is on, Meta otherwise). Pinned top-left,
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
        // 2D/3D view-mode toggle (Steven, Nov 8: "Oo, lagyan mo
        // ng 3D toggle"): a compact segmented pill, top-centre.
        // The corners are taken — Reload top-left, the control
        // cluster top-right (already 5 buttons tall; a 6th would
        // cover the stop card's close button) — and the pill must
        // clear the "couldn't load the map" banner (top-left,
        // right 88), so it hides while the banner shows, like
        // the Reload button. Satellite is not offered here: it
        // needs a separate imagery tile source and was not part
        // of the approval. Tapping a segment only moves the
        // camera (see _setViewMode) — never the route or fares.
        if (!_tilesFailed)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 132,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: IosSegmentedControl<MapViewMode>(
                    key: const ValueKey('map-view-mode-toggle'),
                    segments: [
                      for (final mode in mapViewModeOptions)
                        IosSegment<MapViewMode>(
                          value: mode,
                          label: mapViewModeLabel(mode),
                        ),
                    ],
                    groupValue: _viewMode,
                    onValueChanged: _setViewMode,
                  ),
                ),
              ),
            ),
          ),
        // Live Follow (Nov 8, 2026): starts the real-GPS follow
        // for the active route (or the live position when no
        // route is active). Below the 2D|3D pill — the only free
        // top-centre slot; the control cluster is already 5
        // buttons tall (a 6th would cover the stop card's close
        // button). Tapping again stops follow.
        if (!_tilesFailed)
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(999),
                clipBehavior: Clip.antiAlias,
                color: _liveFollowActive
                    ? const Color(0xFFDC2626)
                    : Theme.of(context).colorScheme.surface,
                child: InkWell(
                  onTap: () {
                    if (_liveFollowActive) {
                      _stopLiveFollow();
                    } else {
                      _startLiveFollow();
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _liveFollowActive
                              ? Icons.stop
                              : Icons.play_arrow,
                          size: 16,
                          color: _liveFollowActive
                              ? Colors.white
                              : const Color(0xFF16A34A),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _liveFollowActive ? 'Stop' : 'Live',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _liveFollowActive
                                ? Colors.white
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
                    // A manual zoom during Live is respected: the
                    // follow camera keeps following at this zoom
                    // instead of snapping back to the close zoom.
                    if (_liveFollowActive && !_liveFollowPaused) {
                      _liveUserZoom = zoom;
                    }
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
                    // A manual zoom during Live is respected: the
                    // follow camera keeps following at this zoom
                    // instead of snapping back to the close zoom.
                    if (_liveFollowActive && !_liveFollowPaused) {
                      _liveUserZoom = zoom;
                    }
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
        // Live minimap (Nov 11, 2026): a pure-Dart overview of
        // the active route, top-right directly below the control
        // cluster. Only while Live Follow is active AND no stop
        // card is open — the stop card pins just below the
        // cluster (kMapStopCardTop) and would collide. Tapping
        // it fits the whole route. Hides when Live stops or a
        // stop card opens.
        if (_liveFollowActive &&
            _selectedStopIndex == null &&
            _activeRoute != null &&
            _activeRouteOrigin != null)
          Positioned(
            right: 16,
            top: 364,
            child: LiveMinimap(
              routePoints:
                  _roadPoints ??
                  [
                    _activeRouteOrigin!,
                    ..._customRouteViaPoints(_activeRoute!),
                    LatLng(
                      _activeRoute!.dest.lat,
                      _activeRoute!.dest.lng,
                    ),
                  ],
              livePos: _liveMarkerPos,
              live: true,
              onTap: _fitActiveRoute,
            ),
          ),
        // Basemap attribution (ⓘ button, bottom-left above the sheet):
        // the preview's map carries its attribution as a small
        // corner button, and the preview has no Standard/Satellite
        // pill — the pill is gone, so this spot is free. Tapping
        // opens the fallback layer's attribution page, or states
        // the Meta credit. When the sheet is hidden the full chip
        // shows centred at the bottom instead. The Replay button
        // sits beside it (approved line animation, Nov 13, 2026):
        // it re-runs the route line's draw-in + pulse. It lives
        // here, not in the top-right cluster — a 6th button there
        // would end below kMapStopCardTop and cover the stop
        // card's close button. Hidden while drawing / placing
        // endpoints (the bottom bars own this spot then) and
        // with no active route (nothing to replay).
        if (!_sheetHidden)
          Positioned(
            left: 16,
            bottom: mapControlsBottomOffset(sheetHidden: _sheetHidden),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
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
                if (_activeRoute != null &&
                    !_lineMakerActive &&
                    !_setEndpointsActive) ...[
                  const SizedBox(width: 10),
                  _MapControlButton(
                    icon: Icons.replay,
                    tooltip: 'Replay route animation',
                    onPressed: _replayRouteLineAnimation,
                  ),
                ],
              ],
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
                          // Hidden during Live Follow: the Live
                          // panel carries its own header.
                          if (!_liveFollowActive) _sheetFixedHeader(scheme),
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

/// Rename dialog for one drawn stop. A StatefulWidget so the
/// TextEditingController is owned by the dialog itself and disposed
/// only when the dialog subtree unmounts (after the pop animation):
/// disposing it right after `await showDialog` returns is too
/// early — the route is still in the overlay animating out, its
/// dependencies change on pop, and the rebuilding TextField reads
/// the disposed controller. The error is State too, so it survives
/// the dialog rebuilding (an error held in the showDialog builder
/// closure resets on every outer rebuild).
class _RenameStopDialog extends StatefulWidget {
  const _RenameStopDialog({this.initialName});

  final String? initialName;

  @override
  State<_RenameStopDialog> createState() => _RenameStopDialogState();
}

class _RenameStopDialogState extends State<_RenameStopDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName ?? '');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename this stop'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: 'Stop name',
              hintText: widget.initialName == null
                  ? 'e.g. Cabugao Public Market'
                  : null,
            ),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isEmpty) {
              setState(() => _error = 'Enter a name for the stop.');
              return;
            }
            if (name.length > 100) {
              setState(
                () => _error = 'The name must be 100 characters or fewer.',
              );
              return;
            }
            Navigator.pop(context, name);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Heading cone behind the Live Follow arrow marker (Nov 13,
/// 2026 — approved Preview v2, Arrow option): a translucent
/// green wedge whose apex points UP in its own coordinates; the
/// marker rotates it by the screen rotation so the apex points
/// along the direction of travel. Drawn in a 104x104 box whose
/// centre is the marker position.
class _LiveHeadingConePainter extends CustomPainter {
  const _LiveHeadingConePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF17CE62).withValues(alpha: 0.30)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, 4)
      ..lineTo(size.width / 2 + 20, size.height / 2)
      ..lineTo(size.width / 2 - 20, size.height / 2)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LiveHeadingConePainter oldDelegate) => false;
}

/// Amber dashed ring around the Live Follow arrow marker when
/// GPS is lost (Nov 13, 2026 — approved Preview v2, Arrow
/// option): the stale-position marker. 16 short arcs read as a
/// dashed circle; drawn in an 84x84 box centred on the core.
class _LiveLostRingPainter extends CustomPainter {
  const _LiveLostRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    const dashes = 16;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: size.width / 2 - 2,
    );
    for (var i = 0; i < dashes; i++) {
      final start = i * 2 * math.pi / dashes;
      canvas.drawArc(rect, start, math.pi / dashes, false, paint);
    }
  }

  @override
  bool shouldRepaint(_LiveLostRingPainter oldDelegate) => false;
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

