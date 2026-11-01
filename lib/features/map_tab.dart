// Map tab — full-screen map + draggable bottom sheet (dark redesign).
// In dark theme the Google tiles themselves use the charcoal style
// from the approved iPhone preview; in light theme they stay default.
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
//   from Google Places (New) Text Search — markers + a list sheet.
//   It needs the Places API enabled and billing linked on the key,
//   like Routes.
// - Search covers the 14 hubs only (the web app's barangay search is not
//   ported to Flutter).
// - Road path shape comes from the Google Routes API (DRIVE mode,
//   main-road routing); only the two endpoint coordinates are sent,
//   and the dashed direct line is the fallback when routing is
//   unreachable.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'community_posts.dart';
import 'fares_tab.dart';

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
  });

  final String originName;
  final Hub dest;
  final double roadKm;
  final Direction direction;
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

/// Google Maps API key for the Routes API web-service call, injected
/// at build time (--dart-define=MAPS_API_KEY=...). Empty in builds
/// that did not pass it — routing then reports unavailable instead
/// of calling without a key.
const _googleApiKey = String.fromEnvironment('MAPS_API_KEY', defaultValue: '');

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
  'Cabugao|San Juan, Ilocos Sur': 20,
  'San Juan, Ilocos Sur|Cabugao': 20,
  'Sinait|Cabugao': 20,
  'Cabugao|Sinait': 20,
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

enum _StopView { nearby, all, nearest }

enum _AmPm { am, pm }

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

/// Bottom offset of the floating map controls (right column + the
/// 2D/3D/Satellite pill). The collapsed sheet occupies the bottom
/// ~190dp, so controls float above it; when the sheet is hidden
/// for a full-map view they drop to just above the screen bottom
/// (bottom:16 — the phone bottom nav bar sits below the Scaffold
/// body, so 16 clears it). During navigation the nav bar owns the
/// bottom, so the controls keep their sheet-era offset there.
double mapControlsBottomOffset({
  required bool sheetHidden,
  required bool navigating,
}) => (sheetHidden && !navigating) ? 16 : 190;

/// Tooltip for the logo toggle: what tapping it will do next.
String sheetToggleTooltip(bool sheetHidden) =>
    sheetHidden ? 'Show bottom panel' : 'Hide bottom panel';

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  static const _initialCamera = CameraPosition(
    target: LatLng(16.9, 121.05),
    zoom: 8,
  );
  static const _savedKey = 'byahetayo_saved_routes';
  static const _homeHub = 2; // Cabugao — his home hub (Fares default origin).

  GoogleMapController? _controller;
  final _sheetController = DraggableScrollableController();
  final _searchController = TextEditingController();
  final _sheetSearchController = TextEditingController();
  StreamSubscription<Position>? _trackSub;

  bool _locationGranted = false;
  bool _locating = false;
  Position? _userPos;
  Hub? _selectedHub;
  // Church whose details panel is open in the bottom sheet (null =
  // the sheet shows Nearby Routes). Set by tapping a church marker
  // or a churches-list entry; cleared by the panel's close button,
  // by hiding church markers, by selecting a hub, and by DIRECTIONS
  // (the route preview card takes over then).
  ChurchPlace? _selectedChurch;
  // Count-badge icons for church cluster markers, keyed by count.
  // Generated on first sight of a count (async canvas draw), then
  // cached; until ready the cluster shows a plain orange marker.
  final _clusterIcons = <int, BitmapDescriptor>{};
  final _pendingClusterIcons = <int>{};

  /// Draws a numbered badge icon for a church cluster marker
  /// (orange circle, white count). Async canvas work; on success
  /// the marker rebuilds with the badge. Failures keep the plain
  /// orange marker — clustering never breaks on icon drawing.
  Future<void> _ensureClusterIcon(int count) async {
    if (_clusterIcons.containsKey(count) ||
        _pendingClusterIcons.contains(count)) {
      return;
    }
    _pendingClusterIcons.add(count);
    try {
      const size = 120.0;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final center = const Offset(size / 2, size / 2);
      canvas.drawCircle(
        center,
        size / 2 - 4,
        Paint()..color = const Color(0xFFEA580C),
      );
      canvas.drawCircle(
        center,
        size / 2 - 4,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6,
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: '$count',
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 48,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        center - Offset(textPainter.width / 2, textPainter.height / 2),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(size.toInt(), size.toInt());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted || bytes == null) return;
      setState(() {
        _clusterIcons[count] = BitmapDescriptor.bytes(
          bytes.buffer.asUint8List(),
        );
      });
    } catch (_) {
      // Plain orange marker stays.
    } finally {
      _pendingClusterIcons.remove(count);
    }
  }

  // True while the sheet shows a route preview opened from a church
  // (the church panel's DIRECTIONS flow, which builds a synthetic
  // Hub destination). While set, the Nearby Routes browsing chrome
  // — stops row, direction chips, AM/PM row, and the
  // direction-grouped stops list — is hidden from the sheet, so
  // only the church route card shows. Set in
  // _selectChurchDestination; cleared when the preview closes
  // (card X, a new hub/route selection, swap, navigation end).
  // Visibility only: it never clears the route, destination,
  // markers, or polylines. Note the existing behavior clears
  // _selectedChurch on DIRECTIONS, so this flag — not the selected
  // church — is the trigger.
  bool _churchPreview = false;
  // Tapped-location path: the hub-to-hub route whose line is drawn
  // on the map, plus the origin point it starts from.
  RouteInfo? _activeRoute;
  LatLng? _activeRouteOrigin;
  // Road-following shape from Google (null = still loading or failed;
  // the dashed direct line shows until real geometry arrives).
  List<LatLng>? _roadPoints;
  String? _routeError;
  double _routeDurationSec = 0;
  // Google's own route length (km) from routes.distanceMeters.
  // 0 = not loaded yet; the bottom bar then falls back to the
  // app's roadKm estimate for the minutes fraction.
  double _routeDistanceKm = 0;
  double _navSpeedKmh = -1;
  DateTime? _lastRerouteAt;
  DateTime? _lastPreviewRefreshAt;
  bool _northUp = false;
  bool _voiceOn = true;
  int _spokenStepIndex = -1;
  bool _avoidHighways = false;
  bool _avoidTolls = false;
  bool _avoidFerries = false;
  final FlutterTts _tts = FlutterTts();
  int _roadRequestId = 0;
  // Animated direction arrow flowing along the active path.
  BitmapDescriptor? _arrowIcon;
  BitmapDescriptor? _carIcon;
  VehicleType _vehicle = VehicleType.bus;
  Map<VehicleType, BitmapDescriptor>? _vehicleIcons;
  // Start Navigation mode.
  bool _navigating = false;
  // Map view mode (2D standard default, 3D perspective, Satellite).
  // Switching modes only changes tiles + camera — it never touches
  // the route, markers, or polylines.
  MapViewMode _mapMode = MapViewMode.standard2d;
  // Bottom-sheet visibility toggle (logo button, main mode only).
  // Visibility only: the sheet stays in the tree wrapped in
  // Offstage, so hiding never clears routes, destinations, church
  // selection, markers, polylines, or sheet content — tapping the
  // logo again restores the sheet exactly as it was, same snap
  // size included. Never used during navigation: nav owns its own
  // bottom bar and the toggle is main-mode only.
  bool _sheetHidden = false;
  // Last camera position reported by the SDK. No setState here: it
  // only feeds mode switches and the compass needle.
  CameraPosition? _lastCamera;
  // Live bearing for the compass needle only (a ValueNotifier so
  // the needle rebuilds alone, never the whole map).
  final ValueNotifier<double> _bearing = ValueNotifier<double>(0);
  bool _arrived = false;
  double _navBearing = 0;
  List<NavStep>? _navSteps;
  List<int> _maneuverIdx = const [];
  int _navStepIndex = 0;
  StreamSubscription<Position>? _navSub;
  String _searchQuery = '';
  String _sheetSearchQuery = '';
  String? _chip;
  // Catholic churches from Google Places (Churches chip, whole
  // Luzon). Markers show only while the chip is active and not
  // navigating, so they never clutter a route.
  List<ChurchPlace> _churches = [];
  bool _churchesLoading = false;
  _StopView _stopView = _StopView.nearby;
  String _direction = 'All';
  _AmPm _amPm = _AmPm.am;
  bool _tracking = false;
  bool _destinationMode = false;
  int _fromIndex = _homeHub; // -1 = My location.
  int _toIndex = 1; // Vigan City.
  TravelMode _travelMode = TravelMode.transit;
  TravelMode _previewMode = TravelMode.transit;
  Set<String> _savedRoutes = {};

  @override
  void initState() {
    super.initState();
    _refreshLocationGranted();
    _loadSaved();
    _loadArrowIcon();
    _loadCarIcon();
    _loadVehicleIcons();
    communityMapJump.addListener(_onCommunityJump);
  }

  // The style is passed to the GoogleMap widget itself (not via the
  // deprecated controller.setMapStyle), so a theme change — e.g.
  // Account > Appearance — re-styles the tiles on the next rebuild.

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

  @override
  void dispose() {
    communityMapJump.removeListener(_onCommunityJump);
    _controller?.dispose();
    _sheetController.dispose();
    _bearing.dispose();
    _searchController.dispose();
    _sheetSearchController.dispose();
    _trackSub?.cancel();
    _navSub?.cancel();
    super.dispose();
  }

  /// Draws one emerald arrow (pointing north at rotation 0) for the
  /// flow marker. Falls back to the default marker if drawing fails.
  Future<void> _loadArrowIcon() async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, 64, 64));
      final paint = ui.Paint()
        ..color = const Color(0xFF16A34A)
        ..style = ui.PaintingStyle.fill;
      final path = ui.Path()
        ..moveTo(32, 6)
        ..lineTo(56, 54)
        ..lineTo(32, 42)
        ..lineTo(8, 54)
        ..close();
      canvas.drawPath(path, paint);
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 64);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null && mounted) {
        setState(
          () => _arrowIcon = BitmapDescriptor.bytes(bytes.buffer.asUint8List()),
        );
      }
    } catch (_) {
      // Fallback: the default green marker (rotation stays 0).
    }
  }

  /// Draws one emerald-circle vehicle icon per VehicleType (white
  /// Material glyph on emerald) for the user cursor. Falls back to the
  /// arrow icon, then the default marker, if drawing fails.
  Future<void> _loadVehicleIcons() async {
    try {
      final icons = <VehicleType, BitmapDescriptor>{};
      for (final v in VehicleType.values) {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(
          recorder,
          const ui.Rect.fromLTWH(0, 0, 96, 96),
        );
        final bg = ui.Paint()
          ..color = const Color(0xFF16A34A)
          ..style = ui.PaintingStyle.fill;
        canvas.drawCircle(const ui.Offset(48, 48), 44, bg);
        final glyph = vehicleIcon(v);
        final painter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(glyph.codePoint),
            style: TextStyle(
              fontFamily: glyph.fontFamily,
              fontSize: 52,
              color: const Color(0xFFFFFFFF),
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          ui.Offset(48 - painter.width / 2, 48 - painter.height / 2),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(96, 96);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          icons[v] = BitmapDescriptor.bytes(bytes.buffer.asUint8List());
        }
      }
      if (mounted && icons.isNotEmpty) {
        setState(() => _vehicleIcons = icons);
      }
    } catch (_) {
      // Fallback: the arrow icon, then the default marker.
    }
  }

  /// Draws a realistic top-down car (Google-style nav cursor): blue
  /// body with a white rim, dark roof, light windows, black wheels,
  /// headlights and taillights. Points up; the marker rotation turns
  /// it to the heading. Falls back to the vehicle/arrow icons.
  Future<void> _loadCarIcon() async {
    try {
      const size = 128.0;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
        recorder,
        const ui.Rect.fromLTWH(0, 0, size, size),
      );
      canvas.translate(size / 2, size / 2);
      // Car body outline, front at the top (y negative).
      final body = ui.Path()
        ..moveTo(0, -52)
        ..cubicTo(26, -50, 30, -30, 30, -10)
        ..lineTo(30, 30)
        ..cubicTo(30, 48, 18, 52, 0, 52)
        ..cubicTo(-18, 52, -30, 48, -30, 30)
        ..lineTo(-30, -10)
        ..cubicTo(-30, -30, -26, -50, 0, -52)
        ..close();
      // Wheels first (the body overlaps their inner edges).
      final wheel = ui.Paint()
        ..color = const Color(0xFF111827)
        ..style = ui.PaintingStyle.fill;
      for (final dy in <double>[-28.0, 18.0]) {
        for (final dx in <double>[-38.0, 28.0]) {
          canvas.drawRRect(
            ui.RRect.fromRectAndRadius(
              ui.Rect.fromLTWH(dx, dy, 10, 20),
              const ui.Radius.circular(4),
            ),
            wheel,
          );
        }
      }
      // White rim, then the blue body slightly inset.
      canvas.drawPath(
        body,
        ui.Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = ui.PaintingStyle.fill,
      );
      canvas.save();
      canvas.scale(0.9, 0.94);
      canvas.drawPath(
        body,
        ui.Paint()
          ..color = const Color(0xFF4285F4)
          ..style = ui.PaintingStyle.fill,
      );
      canvas.restore();
      final glass = ui.Paint()
        ..color = const Color(0xFFB8D4F0)
        ..style = ui.PaintingStyle.fill;
      // Windshield (front) and rear window.
      canvas.drawPath(
        ui.Path()
          ..moveTo(-20, -28)
          ..lineTo(20, -28)
          ..lineTo(16, -12)
          ..lineTo(-16, -12)
          ..close(),
        glass,
      );
      canvas.drawPath(
        ui.Path()
          ..moveTo(-18, 22)
          ..lineTo(18, 22)
          ..lineTo(15, 34)
          ..lineTo(-15, 34)
          ..close(),
        glass,
      );
      // Roof.
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          const ui.Rect.fromLTWH(-20, -12, 40, 34),
          const ui.Radius.circular(8),
        ),
        ui.Paint()
          ..color = const Color(0xFF1E40AF)
          ..style = ui.PaintingStyle.fill,
      );
      // Headlights (front) and taillights (rear).
      final lamp = ui.Paint()..style = ui.PaintingStyle.fill;
      lamp.color = const Color(0xFFFFF9C4);
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          const ui.Rect.fromLTWH(-24, -46, 12, 6),
          const ui.Radius.circular(3),
        ),
        lamp,
      );
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          const ui.Rect.fromLTWH(12, -46, 12, 6),
          const ui.Radius.circular(3),
        ),
        lamp,
      );
      lamp.color = const Color(0xFFEF4444);
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          const ui.Rect.fromLTWH(-22, 46, 10, 5),
          const ui.Radius.circular(2),
        ),
        lamp,
      );
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          const ui.Rect.fromLTWH(12, 46, 10, 5),
          const ui.Radius.circular(2),
        ),
        lamp,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(size.toInt(), size.toInt());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null && mounted) {
        setState(
          () => _carIcon = BitmapDescriptor.bytes(bytes.buffer.asUint8List()),
        );
      }
    } catch (_) {
      // Fallback: the vehicle/arrow icons, then the default marker.
    }
  }

  Future<void> _loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _savedRoutes = prefs.getStringList(_savedKey)?.toSet() ?? {};
        });
      }
    } catch (_) {
      // No saved routes without storage (e.g. widget tests) — stay empty.
    }
  }

  Future<void> _persistSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_savedKey, _savedRoutes.toList());
    } catch (_) {
      // Saving is best-effort; the in-memory set still works this session.
    }
  }

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
      _snack('Buksan mo muna yung Location (GPS) ng phone.');
      return null;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _snack('Kailangan ng location permission para makita kung nasaan ka.');
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

  Future<void> _moveTo(LatLng target, {double zoom = 13}) async {
    // Mode-aware: a jump (my-location, hub tap, nav start) keeps
    // the current view mode instead of flattening a 3D view.
    await _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        cameraForMode(
          mode: _mapMode,
          target: target,
          zoom: zoom,
          bearing: _lastCamera?.bearing ?? 0,
        ),
      ),
    );
  }

  /// Switches the view mode with a smooth animated transition
  /// (animateCamera, never a jump). Only the tiles + camera
  /// change: the active route, destination, vehicle marker,
  /// polylines, stops, church markers, and hub pins are untouched
  /// (they are separate GoogleMap params, not rebuilt here).
  /// During navigation the nav camera owns the view, so only the
  /// tiles change and the nav camera keeps driving; [_endNavigation]
  /// re-applies the mode camera once navigation ends.
  Future<void> _applyMapMode(MapViewMode mode) async {
    setState(() => _mapMode = mode);
    if (_navigating) return;
    final controller = _controller;
    if (controller == null) return;
    final current = _lastCamera;
    final target =
        current?.target ??
        (_userPos != null
            ? LatLng(_userPos!.latitude, _userPos!.longitude)
            : _initialCamera.target);
    final zoom = current?.zoom ?? _initialCamera.zoom;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        cameraForMode(
          mode: mode,
          target: target,
          zoom: zoom,
          bearing: current?.bearing ?? 0,
        ),
      ),
    );
  }

  /// Compass tap: face north again, keeping target, zoom, and the
  /// current tilt (so a 3D view stays perspective, just north-up).
  Future<void> _resetBearing() async {
    final current = _lastCamera;
    if (current == null) return;
    await _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: current.target,
          zoom: current.zoom,
          tilt: current.tilt,
          bearing: 0,
        ),
      ),
    );
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

  /// Swaps origin and destination for hub-to-hub preview routes
  /// (Google-style swap). A live user-location origin cannot swap:
  /// it is not a hub destination, so the button hides there.
  void _swapRouteEnds() {
    final route = _activeRoute;
    if (route == null) return;
    Hub? originHub;
    for (final h in hubs) {
      if (h.name == route.originName) originHub = h;
    }
    final destHub = route.dest;
    if (originHub == null) return;
    final matches = routesFrom(
      destHub.lat,
      destHub.lng,
      destHub.name,
    ).where((r) => r.dest.name == originHub!.name);
    final swapped = matches.isEmpty ? null : matches.first;
    if (_navigating) {
      _navSub?.cancel();
      _navSub = null;
    }
    setState(() {
      _selectedHub = originHub;
      _activeRoute = swapped;
      _activeRouteOrigin = swapped == null
          ? null
          : LatLng(destHub.lat, destHub.lng);
      _roadPoints = null;
      _routeError = null;
      _churchPreview = false;
      _resetNavFields();
    });
    if (swapped != null) {
      _controller?.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(
              math.min(destHub.lat, originHub.lat) - 0.01,
              math.min(destHub.lng, originHub.lng) - 0.01,
            ),
            northeast: LatLng(
              math.max(destHub.lat, originHub.lat) + 0.01,
              math.max(destHub.lng, originHub.lng) + 0.01,
            ),
          ),
          80,
        ),
      );
      _fetchRoadPath(destHub.lat, destHub.lng, originHub);
    } else {
      _moveTo(LatLng(originHub.lat, originHub.lng), zoom: 13);
    }
  }

  /// Google-style floating location card for an active preview
  /// route: origin dot, connector, destination pin, swap (hub routes
  /// only), and a more-options menu with the real Share/Save
  /// actions. Replaces search + chips while a route is active; the
  /// sheet card's X restores search.
  Widget _routePreviewCard() {
    final route = _activeRoute!;
    Hub? originHub;
    for (final h in hubs) {
      if (h.name == route.originName) originHub = h;
    }
    final savedKey = '${route.originName}>${route.dest.name}';
    final saved = _savedRoutes.contains(savedKey);
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
                Container(width: 2, height: 20, color: Colors.black26),
                const Icon(Icons.place, color: Colors.red, size: 20),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.originName,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    route.dest.name,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    route.dest.region,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (originHub != null)
              IconButton(
                icon: const Icon(Icons.swap_vert, color: Colors.black54),
                tooltip: 'Swap origin and destination',
                onPressed: _swapRouteEnds,
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.black54),
              onSelected: (v) {
                if (v == 'share') _shareActiveRoute();
                if (v == 'save') _toggleSaved(route);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'share', child: Text('Share route')),
                PopupMenuItem(
                  value: 'save',
                  child: Text(saved ? 'Remove from saved' : 'Save route'),
                ),
              ],
            ),
          ],
        ),
      ),
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
    if (_navigating) {
      _navSub?.cancel();
      _navSub = null;
    }
    setState(() {
      _selectedChurch = null;
      _selectedHub = hub;
      _activeRoute = route;
      _activeRouteOrigin = route == null ? null : LatLng(oLat, oLng);
      _roadPoints = null;
      _routeError = null;
      _churchPreview = false;
      _resetNavFields();
    });
    if (route != null) {
      // Fit both endpoints, padded so the bounds never degenerate.
      _controller?.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(
              math.min(oLat, hub.lat) - 0.01,
              math.min(oLng, hub.lng) - 0.01,
            ),
            northeast: LatLng(
              math.max(oLat, hub.lat) + 0.01,
              math.max(oLng, hub.lng) + 0.01,
            ),
          ),
          80,
        ),
      );
      _fetchRoadPath(oLat, oLng, hub);
    } else {
      _moveTo(LatLng(hub.lat, hub.lng), zoom: 13);
    }
  }

  /// Fetches the road-following shape for the active route from the
  /// Google Routes API (DRIVE mode, main-road routing). Only the two
  /// endpoint coordinates are sent, plus the app's Android key
  /// headers. On any failure the dashed direct line simply stays
  /// and [_routeError] explains why — the route never breaks. A
  /// stale response (user tapped elsewhere since) is ignored via
  /// [_roadRequestId].
  /// Loads Catholic churches across Luzon from Google Places (New)
  /// Text Search. The sheet always opens afterwards: verified
  /// bundled churches show even when Places fails or is unconfigured,
  /// and the failure reason is shown in the sheet instead of a fake
  /// list. Places needs its API enabled and billing linked on the
  /// key (same Cloud Console trip as Routes).
  Future<void> _fetchChurches() async {
    if (_googleApiKey.isEmpty) {
      setState(() => _chip = 'Churches');
      _showChurchesSheet(
        placesError: 'Google Places key is missing in this build — showing verified churches only.',
      );
      return;
    }
    setState(() {
      _churchesLoading = true;
      _chip = 'Churches';
    });
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      // Up to 3 Places pages (60 churches max per search — the API
      // cap, not literally every church in Northern Luzon; the
      // verified list is what grows toward "all"). A later page
      // failing keeps the earlier pages, silently.
      final found = <ChurchPlace>[];
      String? pageToken;
      String? firstError;
      for (var page = 0; page < 3; page++) {
        if (page > 0) {
          // Places tokens need a short delay before they validate.
          await Future.delayed(const Duration(seconds: 2));
        }
        final request = await client.postUrl(
          Uri.parse('https://places.googleapis.com/v1/places:searchText'),
        );
        request.headers
          ..set('Content-Type', 'application/json')
          ..set('X-Goog-Api-Key', _googleApiKey)
          ..set(
            'X-Goog-FieldMask',
            'places.displayName,places.location,places.formattedAddress,places.photos,nextPageToken',
          )
          ..set('X-Android-Package', 'com.byahetayo.app')
          ..set('X-Android-Cert', '89D1B79AD3344B1344A5D72694A1E863953F8534');
        request.write(jsonEncode(placesChurchesBody(pageToken: pageToken)));
        final response = await request.close().timeout(
          const Duration(seconds: 20),
        );
        final body = await response.transform(utf8.decoder).join();
        if (!mounted) return;
        if (response.statusCode != 200) {
          if (page == 0) {
            var message =
                'Could not load churches. Check that the Places API is enabled and billing is linked.';
            try {
              final err = jsonDecode(body) as Map<String, dynamic>;
              final detail = err['error'];
              if (detail is Map && detail['message'] is String) {
                message = detail['message'] as String;
              }
            } catch (_) {}
            firstError = message;
          }
          break;
        }
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        found.addAll(parsePlacesChurches(decoded));
        pageToken = placesNextPageToken(decoded);
        if (pageToken == null) break;
      }
      if (!mounted) return;
      setState(() {
        _churches = dedupePlacesChurches(found, verifiedChurches);
        _churchesLoading = false;
      });
      _showChurchesSheet(placesError: found.isEmpty ? firstError : null);
    } catch (_) {
      if (!mounted) return;
      setState(() => _churchesLoading = false);
      _showChurchesSheet(placesError: 'Could not reach Google Places.');
    } finally {
      client.close();
    }
  }

  void _showChurchesSheet({String? placesError}) {
    // Sheet-lifetime search state: the controller lives only while
    // the sheet is open; the sheet's own rebuilds read its text.
    final searchController = TextEditingController();
    var filter = ChurchSourceFilter.all;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) {
          final visible = visibleChurches(
            verified: verifiedChurches,
            places: _churches,
            query: searchController.text,
            filter: filter,
          );
          final shown = visible.verified.length + visible.places.length;
          final filtering =
              searchController.text.trim().isNotEmpty ||
              filter != ChurchSourceFilter.all;
          return ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text('Catholic Churches · Northern Luzon ($shown)'),
                subtitle: const Text(
                  'Verified entries first, then results from Google Places for "Catholic church".',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search churches…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Clear search',
                            onPressed: () {
                              searchController.clear();
                              setSheetState(() {});
                            },
                          ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setSheetState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final entry in const [
                      (ChurchSourceFilter.all, 'All'),
                      (ChurchSourceFilter.verified, 'Verified'),
                      (ChurchSourceFilter.places, 'From Places'),
                    ])
                      ChoiceChip(
                        label: Text(entry.$2),
                        selected: filter == entry.$1,
                        onSelected: (_) =>
                            setSheetState(() => filter = entry.$1),
                      ),
                  ],
                ),
              ),
              if (placesError != null)
                ListTile(
                  leading: const Icon(Icons.info_outlined),
                  title: Text(placesError),
                ),
              if (visible.verified.isNotEmpty)
                const ListTile(
                  title: Text(
                    'Verified',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              for (final church in visible.verified)
                ListTile(
                  leading: const Icon(Icons.church_outlined),
                  title: Text(church.name),
                  subtitle: Text(church.address),
                  onTap: () {
                    Navigator.pop(context);
                    _selectChurch(church);
                  },
                ),
              if (visible.places.isNotEmpty)
                const ListTile(
                  title: Text(
                    'From Google Places',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              for (final church in visible.places)
                ListTile(
                  leading: const Icon(Icons.church_outlined),
                  title: Text(church.name),
                  subtitle: Text(
                    church.address.isEmpty
                        ? 'Northern Luzon, Philippines'
                        : church.address,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _selectChurch(church);
                  },
                ),
              if (shown == 0)
                ListTile(
                  title: Text(
                    filtering
                        ? 'No churches match your search.'
                        : 'No churches to show.',
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Hide church markers'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _churches = [];
                    _chip = null;
                    _selectedChurch = null;
                  });
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// True when [church] is the one whose details panel is open.
  /// Compared by name + coordinates, not object identity, so two
  /// listings of one church can never highlight twice.
  bool _isSelectedChurch(ChurchPlace church) {
    final selected = _selectedChurch;
    return selected != null &&
        selected.name == church.name &&
        selected.lat == church.lat &&
        selected.lng == church.lng;
  }

  /// Marker tap: select the church and open its details panel in
  /// the bottom sheet (half-expanded so name + buttons show at
  /// once). During a route preview the panel stays out of the way
  /// and only the camera flies.
  void _selectChurch(ChurchPlace church) {
    if (_activeRoute == null) {
      setState(() => _selectedChurch = church);
      try {
        if (_sheetController.isAttached) {
          _sheetController.animateTo(
            0.5,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      } catch (_) {}
    }
    _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(church.lat, church.lng), 16),
    );
  }

  /// DIRECTIONS from the church panel: the church becomes the route
  /// destination through the existing hub flow. Preview card, road
  /// shape, Start, voice, and re-route all run unchanged — they
  /// only ever read dest name + coordinates. The church panel
  /// closes; the preview card takes over.
  void _selectChurchDestination(ChurchPlace church) {
    final oLat = _userPos?.latitude ?? hubs[_homeHub].lat;
    final oLng = _userPos?.longitude ?? hubs[_homeHub].lng;
    final oName = _userPos != null ? 'Your location' : hubs[_homeHub].name;
    final dest = churchDestinationHub(church);
    final route = RouteInfo(
      originName: oName,
      dest: dest,
      roadKm: roadKmBetween(oLat, oLng, church.lat, church.lng),
      direction: directionOf(oLat, church.lat),
    );
    if (_navigating) {
      _navSub?.cancel();
      _navSub = null;
    }
    setState(() {
      _selectedChurch = null;
      _selectedHub = dest;
      _activeRoute = route;
      _activeRouteOrigin = LatLng(oLat, oLng);
      _roadPoints = null;
      _routeError = null;
      _churchPreview = true;
      _resetNavFields();
    });
    _controller?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            math.min(oLat, church.lat) - 0.01,
            math.min(oLng, church.lng) - 0.01,
          ),
          northeast: LatLng(
            math.max(oLat, church.lat) + 0.01,
            math.max(oLng, church.lng) + 0.01,
          ),
        ),
        80,
      ),
    );
    _fetchRoadPath(oLat, oLng, dest);
  }

  /// Photo slot for the church details panel. Shows the real
  /// Places photo when the entry carries photo data and the build
  /// has an API key; anything else — every verified church, every
  /// Places entry without photos, a failed load — shows the plain
  /// honest empty state, never a placeholder picture. A standalone
  /// widget so it stays widget-testable without the map.
  Widget _churchPhotoSlot(ChurchPlace church) =>
      ChurchPhotoSlot(church: church, apiKey: _googleApiKey);

  /// Church details panel: replaces the Nearby Routes content while
  /// a church is selected. Collapsed it shows the photo slot, name,
  /// address, and the three actions; the detail rows below appear
  /// as the sheet expands (OPEN animates it to full). No rating,
  /// hours, or contact rows: none are verified, so none are shown.
  Widget _churchDetailsPanel(ColorScheme scheme, ChurchPlace church) {
    final verified = verifiedChurches.any(
      (c) =>
          c.name == church.name && c.lat == church.lat && c.lng == church.lng,
    );
    final pos = _userPos;
    final straightKm = pos == null
        ? null
        : haversineKm(pos.latitude, pos.longitude, church.lat, church.lng);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.church_outlined, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          church.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (verified)
                        const Icon(
                          Icons.verified,
                          color: Colors.green,
                          size: 20,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    church.address.isEmpty
                        ? 'Northern Luzon, Philippines'
                        : church.address,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: () => setState(() => _selectedChurch = null),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _churchPhotoSlot(church),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  try {
                    if (_sheetController.isAttached) {
                      _sheetController.animateTo(
                        0.92,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  } catch (_) {}
                },
                icon: const Icon(Icons.keyboard_arrow_up),
                label: const Text('OPEN'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _copyChurchAddress(church),
                icon: const Icon(Icons.link_outlined),
                label: const Text('ADDRESS'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _selectChurchDestination(church),
                icon: const Icon(Icons.directions),
                label: const Text('DIRECTIONS'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.church_outlined),
          title: const Text('Denomination'),
          subtitle: Text(verified ? 'Roman Catholic' : 'Catholic Church'),
        ),
        if (straightKm != null)
          ListTile(
            leading: const Icon(Icons.straighten),
            title: const Text('Straight-line distance'),
            subtitle: Text('${straightKm.toStringAsFixed(1)} km'),
          ),
        ListTile(
          leading: const Icon(Icons.place_outlined),
          title: const Text('Coordinates'),
          subtitle: Text(
            '${church.lat.toStringAsFixed(5)}, '
            '${church.lng.toStringAsFixed(5)}',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.info_outlined),
          title: const Text('Source'),
          subtitle: Text(verified ? 'Verified listing' : 'Google Places'),
        ),
      ],
    );
  }

  /// ADDRESS: copies the full address, with a snackbar action to
  /// open the church in Google Maps.
  Future<void> _copyChurchAddress(ChurchPlace church) async {
    final address = church.address.isEmpty
        ? '${church.name}, Northern Luzon, Philippines'
        : church.address;
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Address copied.'),
        action: SnackBarAction(
          label: 'Open in Maps',
          onPressed: () {
            launchUrl(
              Uri.parse(
                'https://www.google.com/maps/search/?api=1&query='
                '${church.lat},${church.lng}',
              ),
              mode: LaunchMode.externalApplication,
            );
          },
        ),
      ),
    );
  }

  Future<void> _fetchRoadPath(double oLat, double oLng, Hub dest) async {
    final requestId = ++_roadRequestId;
    if (_googleApiKey.isEmpty) {
      if (mounted) {
        setState(
          () => _routeError = 'Google routing key is missing in this build.',
        );
      }
      return;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(
        Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes'),
      );
      request.headers
        ..set('Content-Type', 'application/json')
        ..set('X-Goog-Api-Key', _googleApiKey)
        ..set(
          'X-Goog-FieldMask',
          'routes.duration,routes.distanceMeters,'
              'routes.polyline.encodedPolyline,'
              'routes.legs.steps.navigationInstruction,'
              'routes.legs.steps.distanceMeters,'
              'routes.legs.steps.startLocation',
        )
        ..set('X-Android-Package', 'com.byahetayo.app')
        ..set('X-Android-Cert', '89D1B79AD3344B1344A5D72694A1E863953F8534');
      request.write(
        jsonEncode({
          'origin': {
            'location': {
              'latLng': {'latitude': oLat, 'longitude': oLng},
            },
          },
          'destination': {
            'location': {
              'latLng': {'latitude': dest.lat, 'longitude': dest.lng},
            },
          },
          'travelMode': 'DRIVE',
          'routingPreference': 'TRAFFIC_UNAWARE',
          'routeModifiers': routeModifiersJson(
            avoidHighways: _avoidHighways,
            avoidTolls: _avoidTolls,
            avoidFerries: _avoidFerries,
          ),
          'languageCode': 'en',
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await response.transform(utf8.decoder).join();
      if (!mounted || requestId != _roadRequestId) return;
      if (response.statusCode != 200) {
        var message = 'Google routing unavailable.';
        try {
          final err = jsonDecode(body) as Map<String, dynamic>;
          final detail = err['error'];
          if (detail is Map && detail['message'] is String) {
            message = detail['message'] as String;
          }
        } catch (_) {}
        setState(() => _routeError = message);
        return;
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final firstRoute =
          decoded['routes'] is List && (decoded['routes'] as List).isNotEmpty
          ? (decoded['routes'] as List).first
          : null;
      final polyline = firstRoute is Map ? firstRoute['polyline'] : null;
      final duration = firstRoute is Map ? firstRoute['duration'] : null;
      final distanceM = firstRoute is Map ? firstRoute['distanceMeters'] : null;
      final encoded = polyline is Map ? polyline['encodedPolyline'] : null;
      final points = encoded is String
          ? decodePolyline(encoded)
          : const <LatLng>[];
      final steps = parseGoogleSteps(decoded);
      if (points.isNotEmpty && requestId == _roadRequestId) {
        setState(() {
          _roadPoints = points;
          _routeError = null;
          _routeDurationSec = parseGoogleDuration(duration);
          _routeDistanceKm = distanceM is num ? distanceM.toDouble() / 1000 : 0;
          _navSteps = steps.isEmpty ? null : steps;
          _maneuverIdx = steps
              .map((s) => nearestPointIndex(points, s.location))
              .toList();
          _navStepIndex = 0;
        });
      } else if (requestId == _roadRequestId) {
        setState(() => _routeError = 'Google returned no route shape.');
      }
    } catch (_) {
      if (mounted && requestId == _roadRequestId) {
        setState(() => _routeError = 'Could not reach Google routing.');
      }
    } finally {
      client.close();
    }
  }

  /// Resets navigation fields only (no stream work — callers that
  /// need it cancel the subscription themselves first).
  void _resetNavFields() {
    _navigating = false;
    _arrived = false;
    _navBearing = 0;
    _navSteps = null;
    _maneuverIdx = const [];
    _navStepIndex = 0;
    _navSpeedKmh = -1;
    _lastRerouteAt = null;
    _lastPreviewRefreshAt = null;
    _northUp = false;
    _spokenStepIndex = -1;
    _routeDurationSec = 0;
    _routeDistanceKm = 0;
    _previewMode = TravelMode.transit;
  }

  /// Zooms the nav camera out to fit the whole remaining route
  /// (Google-style overview). Re-center resumes follow.
  void _overviewNav() {
    final user = _userPos;
    final dest = _activeRoute?.dest;
    if (user == null || dest == null) return;
    _controller?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            math.min(user.latitude, dest.lat) - 0.01,
            math.min(user.longitude, dest.lng) - 0.01,
          ),
          northeast: LatLng(
            math.max(user.latitude, dest.lat) + 0.01,
            math.max(user.longitude, dest.lng) + 0.01,
          ),
        ),
        80,
      ),
    );
  }

  /// Asks before ending navigation from the bottom bar (arrival
  /// and selection changes still end directly — they already have
  /// their own dialogs or are explicit user taps).
  Future<void> _confirmEndNavigation() async {
    final dest = _activeRoute?.dest;
    final end = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End navigation?'),
        content: Text(
          dest == null
              ? 'Stop GPS navigation?'
              : 'Stop GPS navigation to ${dest.name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End'),
          ),
        ],
      ),
    );
    if (end == true) _endNavigation();
  }

  void _endNavigation() {
    _navSub?.cancel();
    _tts.stop();
    _navSub = null;
    if (!mounted) return;
    // Ending navigation also ends a church-preview session: the
    // browsing chrome returns with the sheet (the route card itself
    // persists — only the hiding lifts).
    setState(() {
      _resetNavFields();
      _churchPreview = false;
    });
    // Navigation's tilt-45 camera is over: restore the current
    // mode's camera (2D snaps back to top-down).
    _applyMapMode(_mapMode);
  }

  /// Enters navigation for the active route: the camera follows the
  /// user with heading, the user arrow replaces the blue dot, and
  /// the nav card shows the next real turn + remaining distance.
  /// Navigation takes over following from the Live Tracking pill.
  Future<void> _startNavigation() async {
    final route = _activeRoute;
    final origin = _activeRouteOrigin;
    if (route == null || origin == null || _navigating) return;
    final position = await _ensurePosition();
    if (position == null || !mounted) return;
    await _trackSub?.cancel();
    _trackSub = null;
    setState(() {
      _userPos = position;
      _locationGranted = true;
      _tracking = false;
      _navigating = true;
      _arrived = false;
      _navStepIndex = 0;
    });
    await _moveTo(LatLng(position.latitude, position.longitude), zoom: 17);
    // If road routing failed earlier, retry now that navigation
    // needs the shape + steps.
    if (_roadPoints == null) {
      _fetchRoadPath(origin.latitude, origin.longitude, route.dest);
    }
    _navSub?.cancel();
    _navSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_onNavPosition);
  }

  void _onNavPosition(Position pos) {
    if (!_navigating || !mounted) return;
    final user = LatLng(pos.latitude, pos.longitude);
    final moving = pos.speed > 1;
    final bearing = moving ? pos.heading : _navBearing;
    final dest = _activeRoute?.dest;
    setState(() {
      _userPos = pos;
      _navBearing = bearing;
      _navSpeedKmh = pos.speed >= 0 ? pos.speed * 3.6 : -1;
      final pts = _roadPoints;
      if (pts != null && _navSteps != null && _maneuverIdx.isNotEmpty) {
        final userIdx = nearestPointIndex(pts, user);
        while (_navStepIndex < _maneuverIdx.length - 1 &&
            _maneuverIdx[_navStepIndex] <= userIdx) {
          _navStepIndex++;
        }
      }
    });
    // The camera follows the snapped position, so the view stays
    // on the road even when raw GPS drifts a few metres off it.
    final display = snapToRoute(user, _roadPoints);
    _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: display,
          zoom: 17,
          bearing: _northUp ? 0 : bearing,
          tilt: 45,
        ),
      ),
    );
    if (_voiceOn &&
        _navSteps != null &&
        _navSteps!.isNotEmpty &&
        _navStepIndex != _spokenStepIndex) {
      _spokenStepIndex = _navStepIndex;
      _speakInstruction(
        _navSteps![_navStepIndex.clamp(0, _navSteps!.length - 1)].instruction,
      );
    }
    if (dest != null && !_arrived) {
      final d = haversineKm(pos.latitude, pos.longitude, dest.lat, dest.lng);
      if (d <= 0.15) {
        _arrived = true;
        _showArrivalDialog(dest);
      }
    }
    // Re-route when the user is off the line (or the road shape never
    // loaded): Google re-calculates instead of drawing a long straight
    // connector. Throttled to once per 30 seconds.
    if (dest != null && !_arrived && mounted) {
      final pts = _roadPoints;
      final double offKm;
      if (pts == null) {
        offKm = double.infinity;
      } else {
        final idx = nearestPointIndex(pts, user);
        offKm = haversineKm(
          user.latitude,
          user.longitude,
          pts[idx].latitude,
          pts[idx].longitude,
        );
      }
      if (needsReroute(
        offRouteKm: offKm,
        lastRerouteAt: _lastRerouteAt,
        now: DateTime.now(),
      )) {
        _lastRerouteAt = DateTime.now();
        _fetchRoadPath(user.latitude, user.longitude, dest);
      }
    }
  }

  /// Speaks one instruction via the platform text-to-speech engine.
  /// Any failure is swallowed — voice must never break navigation.
  Future<void> _speakInstruction(String text) async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.speak(text);
    } catch (_) {}
  }

  /// Re-centers the nav camera on the user (Google's Re-center pill).
  void _recenterNav() {
    final pos = _userPos;
    if (pos == null) return;
    _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: 17,
          bearing: _northUp ? 0 : _navBearing,
          tilt: 45,
        ),
      ),
    );
  }

  void _showArrivalDialog(Hub dest) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your destination'),
        content: Text('You have arrived at ${dest.name}.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _endNavigation();
            },
            child: const Text('End Navigation'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleTracking() async {
    if (_tracking) {
      await _trackSub?.cancel();
      _trackSub = null;
      setState(() => _tracking = false);
      return;
    }
    final position = await _ensurePosition();
    if (position == null || !mounted) return;
    setState(() {
      _userPos = position;
      _locationGranted = true;
      _tracking = true;
    });
    await _moveTo(LatLng(position.latitude, position.longitude), zoom: 15);
    _trackSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 20,
          ),
        ).listen((pos) {
          if (!_tracking || !mounted) return;
          setState(() => _userPos = pos);
          _controller?.animateCamera(
            CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
          );
          // Live preview: a user-origin preview route refreshes when
          // the user actually moves (no camera yank — the follow above
          // already moves the view). Hub-origin routes never refresh:
          // their origin does not move.
          final route = _activeRoute;
          final origin = _activeRouteOrigin;
          if (!_navigating &&
              route != null &&
              route.originName == 'Your location' &&
              origin != null &&
              _selectedHub != null) {
            final moved = haversineKm(
              pos.latitude,
              pos.longitude,
              origin.latitude,
              origin.longitude,
            );
            if (shouldRefreshPreview(
              movedKm: moved,
              lastRefreshAt: _lastPreviewRefreshAt,
              now: DateTime.now(),
            )) {
              _lastPreviewRefreshAt = DateTime.now();
              _refreshPreviewRoute();
            }
          }
        });
  }

  /// Recomputes a user-origin preview route from the current
  /// position (no camera move, no sheet change): the preview
  /// follows the user the way the Google preview's blue dot does.
  /// Navigation is untouched (it has its own live re-route).
  void _refreshPreviewRoute() {
    final hub = _selectedHub;
    final pos = _userPos;
    if (hub == null || pos == null || _navigating) return;
    final matches = routesFrom(
      pos.latitude,
      pos.longitude,
      'Your location',
    ).where((r) => r.dest.name == hub.name);
    if (matches.isEmpty) return;
    setState(() {
      _activeRoute = matches.first;
      _activeRouteOrigin = LatLng(pos.latitude, pos.longitude);
      _roadPoints = null;
      _navSteps = null;
      _routeError = null;
    });
    _fetchRoadPath(pos.latitude, pos.longitude, hub);
  }

  void _refetchActiveRoute() {
    final origin = _activeRouteOrigin;
    final route = _activeRoute;
    if (origin == null || route == null) return;
    _fetchRoadPath(origin.latitude, origin.longitude, route.dest);
  }

  Future<void> _shareRouteText(String text) async {
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (_) {
      if (mounted) _snack('Could not open the share sheet.');
    }
  }

  Future<void> _shareActiveRoute() async {
    final route = _activeRoute;
    if (route == null) return;
    final fare = resolveTransitFare(
      from: route.originName,
      to: route.dest.name,
      vehicle: _vehicle,
      roadKm: route.roadKm,
    );
    _shareRouteText(
      'EstudyanteGO route: ${route.originName} → ${route.dest.name} · '
      '${route.roadKm.toStringAsFixed(1)} km · '
      '${fare == null ? 'No fare' : peso(fare)} · '
      '${route.direction == Direction.northbound ? 'Northbound' : 'Southbound'}',
    );
  }

  /// Fare segment for the tapped-route summary line: the vehicle-aware
  /// resolved fare, or 'No fare' when the vehicle has no rate.
  String _previewSummaryFare() {
    final route = _activeRoute;
    if (route == null) return 'No fare';
    final fare = resolveTransitFare(
      from: route.originName,
      to: route.dest.name,
      vehicle: _vehicle,
      roadKm: route.roadKm,
    );
    return fare == null ? 'No fare' : peso(fare);
  }

  void _toggleSaved(RouteInfo route) {
    final key = '${route.originName}>${route.dest.name}';
    setState(() {
      if (_savedRoutes.contains(key)) {
        _savedRoutes.remove(key);
        _snack('Tinanggal sa saved routes.');
      } else {
        _savedRoutes.add(key);
        _snack('Saved na ang rutang ito.');
      }
    });
    _persistSaved();
  }

  void _openSavedRoute(String key) {
    final parts = key.split('>');
    if (parts.length != 2) return;
    final fromName = parts[0];
    final toName = parts[1];
    final toIndex = hubs.indexWhere((h) => h.name == toName);
    if (toIndex < 0) return;
    setState(() {
      _fromIndex = fromName == 'Your location'
          ? -1
          : hubs.indexWhere((h) => h.name == fromName);
      if (_fromIndex < -1) _fromIndex = _homeHub;
      _toIndex = toIndex;
      _destinationMode = true;
    });
    _sheetController.animateTo(
      0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  ({double lat, double lng, String name, Hub? hub}) _origin() {
    if (_fromIndex == -1) {
      final pos = _userPos;
      if (pos != null) {
        return (
          lat: pos.latitude,
          lng: pos.longitude,
          name: 'Your location',
          hub: null,
        );
      }
      final fallback = hubs[_homeHub];
      return (
        lat: fallback.lat,
        lng: fallback.lng,
        name: fallback.name,
        hub: fallback,
      );
    }
    final hub = hubs[_fromIndex];
    return (lat: hub.lat, lng: hub.lng, name: hub.name, hub: hub);
  }

  List<RouteInfo> _currentRoutes() {
    final origin = _userPos != null && _stopView != _StopView.all
        ? (
            lat: _userPos!.latitude,
            lng: _userPos!.longitude,
            name: 'Your location',
          )
        : (
            lat: hubs[_homeHub].lat,
            lng: hubs[_homeHub].lng,
            name: hubs[_homeHub].name,
          );
    var routes = routesFrom(origin.lat, origin.lng, origin.name);
    if (_stopView == _StopView.nearest && routes.isNotEmpty) {
      routes = [routes.first];
    }
    if (_stopView == _StopView.all) {
      routes.sort((a, b) => a.dest.name.compareTo(b.dest.name));
    }
    if (_direction != 'All') {
      final want = _direction == 'Northbound'
          ? Direction.northbound
          : Direction.southbound;
      routes = routes.where((r) => r.direction == want).toList();
    }
    routes = filterRoutesByVehicle(routes, _vehicle);
    return routes;
  }

  /// Points + style for the active-route line. Solid = real road shape
  /// from Google; dashed = direct-line fallback. During navigation the
  /// line starts at the user's CURRENT position (trimmed road points
  /// from the nearest point onward), so it always runs current
  /// location -> destination even as the user moves away from the
  /// position where the route was first tapped.
  Set<Polyline> _routePolylines(ColorScheme scheme) {
    if (_activeRoute == null || _activeRouteOrigin == null) {
      return const {};
    }
    final dest = LatLng(_activeRoute!.dest.lat, _activeRoute!.dest.lng);
    final List<LatLng> points;
    final bool solid;
    if (_navigating && _userPos != null) {
      points = navLinePoints(
        user: LatLng(_userPos!.latitude, _userPos!.longitude),
        roadPoints: _roadPoints,
        dest: dest,
      );
      solid = _roadPoints != null;
    } else {
      points = _roadPoints ?? [_activeRouteOrigin!, dest];
      solid = _roadPoints != null;
    }
    return {
      Polyline(
        polylineId: const PolylineId('active-route'),
        points: points,
        color: scheme.primary,
        width: 15,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        // Empty pattern list = solid line (road shape);
        // dashed = direct-line fallback.
        patterns: solid
            ? const []
            : [PatternItem.dash(24), PatternItem.gap(12)],
      ),
    };
  }

  Set<Marker> _markers() {
    final markers = <Marker>{};
    for (final hub in hubs) {
      // During navigation the other hub pins are clutter (and a tap
      // on one would cancel navigation): only the destination stays.
      if (_navigating && hub.name != _selectedHub?.name) continue;
      // Churches mode shows ONLY churches: hub pins hide while no
      // route is active (a selected route still needs its pins).
      if (_chip == 'Churches' && _activeRoute == null) continue;
      final selected = _selectedHub?.name == hub.name;
      markers.add(
        Marker(
          markerId: MarkerId(hub.name),
          position: LatLng(hub.lat, hub.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            selected ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueGreen,
          ),
          onTap: () => _selectHub(hub),
        ),
      );
    }
    // Nav cursor only: the realistic car when Car is the selected
    // vehicle, otherwise the selected vehicle's own icon. Rotates
    // with heading. In main mode there is no custom marker: the
    // native blue dot (myLocationEnabled) is the live location.
    // The in-nav vehicle chips change this live.
    if (_userPos != null && _navigating) {
      final BitmapDescriptor? customIcon;
      if (_carIcon != null && _vehicle == VehicleType.car) {
        customIcon = _carIcon;
      } else {
        customIcon = _vehicleIcons?[_vehicle] ?? _arrowIcon;
      }
      markers.add(
        Marker(
          markerId: const MarkerId('user-vehicle'),
          position: _navigating
              ? snapToRoute(
                  LatLng(_userPos!.latitude, _userPos!.longitude),
                  _roadPoints,
                )
              : LatLng(_userPos!.latitude, _userPos!.longitude),
          icon:
              customIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          rotation: customIcon == null ? 0 : (_navigating ? _navBearing : 0),
          anchor: const Offset(0.5, 0.5),
          flat: true,
        ),
      );
    }
    // Catholic church markers, grid-clustered by zoom: verified
    // bundled churches + Google Places results. Only while the
    // Churches chip is active and not navigating, so they never
    // clutter a route. Tapping one flies the camera there;
    // tapping a cluster zooms toward it until it splits.
    if (!_navigating && _chip == 'Churches') {
      final zoom = _lastCamera?.zoom ?? _initialCamera.zoom;
      final clusters = clusterChurches([
        ...verifiedChurches,
        ..._churches,
      ], zoom);
      for (final cluster in clusters) {
        if (cluster.isSingle) {
          final church = cluster.churches.first;
          final verified = verifiedChurches.any(
            (c) =>
                c.name == church.name &&
                c.lat == church.lat &&
                c.lng == church.lng,
          );
          markers.add(
            Marker(
              markerId: MarkerId(
                '${verified ? 'verified-church' : 'church'}:${church.name}',
              ),
              position: LatLng(church.lat, church.lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                _isSelectedChurch(church)
                    ? BitmapDescriptor.hueAzure
                    : BitmapDescriptor.hueViolet,
              ),
              infoWindow: InfoWindow(
                title: church.name,
                snippet: church.address,
              ),
              onTap: () => _selectChurch(church),
            ),
          );
        } else {
          final count = cluster.count;
          markers.add(
            Marker(
              markerId: MarkerId(
                'church-cluster:${cluster.lat.toStringAsFixed(5)},'
                '${cluster.lng.toStringAsFixed(5)}',
              ),
              position: LatLng(cluster.lat, cluster.lng),
              icon:
                  _clusterIcons[count] ??
                  BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueOrange,
                  ),
              infoWindow: InfoWindow(
                title: '$count churches',
                snippet: 'Tap to zoom in',
              ),
              onTap: () {
                _controller?.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(cluster.lat, cluster.lng),
                    math.min(zoom + 2, 20.0),
                  ),
                );
              },
            ),
          );
          _ensureClusterIcon(count);
        }
      }
    }
    return markers;
  }

  List<Hub> _searchResults() {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return hubs
        .where(
          (h) =>
              h.name.toLowerCase().contains(q) ||
              h.region.toLowerCase().contains(q),
        )
        .take(6)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Churches mode: hide every other base-map POI so the map shows
    // only churches. Navigation keeps its own style.
    final baseMapStyle = mapStyleForBrightness(Theme.of(context).brightness);
    final mapStyle = _chip == 'Churches' && !_navigating
        ? churchesOnlyStyle(baseMapStyle)
        : baseMapStyle;
    final routes = _currentRoutes();
    final allRoutes = routesFrom(
      _userPos?.latitude ?? hubs[_homeHub].lat,
      _userPos?.longitude ?? hubs[_homeHub].lng,
      _userPos != null ? 'Your location' : hubs[_homeHub].name,
    );
    final northCount = allRoutes
        .where((r) => r.direction == Direction.northbound)
        .length;
    final southCount = allRoutes.length - northCount;
    final searchResults = _searchResults();

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: _initialCamera,
          // Dark tiles in dark theme, exactly like the approved
          // iPhone preview; Google default in light theme.
          style: mapStyle,
          markers: _markers(),
          // During navigation the line starts at the user's current
          // position; otherwise it runs origin -> destination.
          polylines: _routePolylines(scheme),
          // View mode: real SDK map type + buildings + gestures.
          // Mode switches never touch the markers/polylines above.
          mapType: mapTypeForMode(_mapMode),
          buildingsEnabled: buildingsForMode(_mapMode),
          compassEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          onCameraMove: (position) {
            _lastCamera = position;
            _bearing.value = position.bearing;
          },
          // The vehicle marker replaces the blue dot once a position
          // is known; the dot stays until then, and stays off in nav.
          // Native Google blue dot = live location in main mode.
          // Off during nav: the vehicle cursor is the marker there.
          myLocationEnabled: _locationGranted && !_navigating,
          myLocationButtonEnabled: false,
          // Google's own +/- zoom buttons sat behind the my-location
          // FAB; pinch zoom still works, so they stay off.
          zoomControlsEnabled: false,
          onMapCreated: (controller) => _controller = controller,
          // A plain map tap dismisses the open church panel.
          onTap: (_) {
            if (_selectedChurch != null) {
              setState(() => _selectedChurch = null);
            }
          },
        ),
        // Floating search bar + chips.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_navigating && _activeRoute != null) _routePreviewCard(),
                if (!_navigating && _activeRoute == null)
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(28),
                    // Light search bar on the dark map, exactly like the
                    // approved iPhone preview (and the Davao reference).
                    color: Colors.white,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Search places, landmarks, or streets',
                        hintStyle: const TextStyle(color: Colors.black54),
                        prefixIcon: const Icon(
                          Icons.menu,
                          color: Colors.black54,
                        ),
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  color: Colors.black54,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                if (!_navigating &&
                    _activeRoute == null &&
                    (searchResults.isNotEmpty ||
                        _searchQuery.trim().isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white,
                      child: searchResults.isEmpty
                          ? const ListTile(
                              title: Text(
                                'Walang hub na nakita.',
                                style: TextStyle(color: Colors.black87),
                              ),
                              subtitle: Text(
                                'Hubs lang ang nase-search dito sa ngayon.',
                                style: TextStyle(color: Colors.black54),
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: searchResults
                                  .map(
                                    (hub) => ListTile(
                                      leading: const Icon(
                                        Icons.place_outlined,
                                        color: Colors.black54,
                                      ),
                                      title: Text(
                                        hub.name,
                                        style: const TextStyle(
                                          color: Colors.black87,
                                        ),
                                      ),
                                      subtitle: Text(
                                        hub.region,
                                        style: const TextStyle(
                                          color: Colors.black54,
                                        ),
                                      ),
                                      onTap: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                        FocusScope.of(context).unfocus();
                                        _selectHub(hub);
                                      },
                                    ),
                                  )
                                  .toList(),
                            ),
                    ),
                  ),
                if (!_navigating && _activeRoute == null)
                  const SizedBox(height: 8),
                if (!_navigating && _activeRoute == null)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final chip in const [
                          'Malls',
                          'Schools',
                          'Hospitals',
                          'Churches',
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text(chip),
                              backgroundColor: _chip == chip
                                  ? scheme.primary
                                  : scheme.surface,
                              labelStyle: TextStyle(
                                color: _chip == chip
                                    ? scheme.onPrimary
                                    : scheme.onSurface,
                              ),
                              side: BorderSide(color: scheme.outline),
                              onPressed: () {
                                if (chip == 'Churches') {
                                  // Toggle: tap = churches-only map,
                                  // tap again = back to the normal map
                                  // (hub pins + base POIs return).
                                  // While loading, ignore taps.
                                  if (_churchesLoading) return;
                                  if (_chip == 'Churches') {
                                    setState(() {
                                      _churches = [];
                                      _chip = null;
                                      _selectedChurch = null;
                                    });
                                  } else {
                                    _fetchChurches();
                                  }
                                } else {
                                  _snack(
                                    'Walang verified places data pa para sa $chip.',
                                  );
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                if (_navigating) _navBanner(),
                // Vehicle selector inside navigation: switching
                // changes the live cursor (Car = the realistic car)
                // and the shared vehicle state for the preview
                // cards. The driving route itself does not change:
                // routing is always DRIVE mode.
                if (_navigating) const SizedBox(height: 8),
                if (_navigating)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final v in VehicleType.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              avatar: Icon(vehicleIcon(v), size: 18),
                              label: Text(vehicleLabel(v)),
                              selected: _vehicle == v,
                              onSelected: (_) => setState(() => _vehicle = v),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Floating map controls (above the collapsed sheet, or
        // just above the screen bottom when the sheet is hidden).
        Positioned(
          right: 16,
          bottom: mapControlsBottomOffset(
            sheetHidden: _sheetHidden,
            navigating: _navigating,
          ),
          child: Column(
            children: [
              // ByaheTayo logo toggle (main mode only): hides the
              // bottom sheet completely for a full-map view; tap
              // again to bring it back. The button itself stays
              // visible while the sheet is hidden — it is the way
              // back. Never shown during navigation: nav owns its
              // bottom bar and must not be hidden.
              if (!_navigating) ...[
                _LogoToggleButton(
                  tooltip: sheetToggleTooltip(_sheetHidden),
                  onPressed: () => setState(() => _sheetHidden = !_sheetHidden),
                ),
                const SizedBox(height: 10),
              ],
              _MapControlButton(
                icon: Icons.add,
                tooltip: 'Zoom in',
                onPressed: () =>
                    _controller?.animateCamera(CameraUpdate.zoomIn()),
              ),
              const SizedBox(height: 10),
              _MapControlButton(
                icon: Icons.remove,
                tooltip: 'Zoom out',
                onPressed: () =>
                    _controller?.animateCamera(CameraUpdate.zoomOut()),
              ),
              const SizedBox(height: 10),
              _MapControlButton(
                icon: Icons.my_location,
                tooltip: 'My location',
                busy: _locating,
                onPressed: _goToMyLocation,
              ),
              // Compass needle (main mode only: navigation already
              // has its own north-up toggle). The needle rotates
              // with the live bearing and always points north on
              // screen; tapping it faces the map north again. The
              // SDK compass is also enabled, but it renders under
              // the top search bar, so this button is the usable one.
              if (!_navigating) ...[
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
              if (_navigating) ...[
                const SizedBox(height: 10),
                _MapControlButton(
                  icon: Icons.explore,
                  tooltip: _northUp ? 'Heading up' : 'North up',
                  onPressed: () {
                    setState(() => _northUp = !_northUp);
                    _recenterNav();
                  },
                ),
                const SizedBox(height: 10),
                _MapControlButton(
                  icon: Icons.map,
                  tooltip: 'Route overview',
                  onPressed: _overviewNav,
                ),
              ],
            ],
          ),
        ),
        // Floating 2D / 3D / Satellite selector (left side, above
        // the collapsed sheet and clear of the nav bottom bar at
        // bottom:16; it drops with the right column when the sheet
        // is hidden). Works during navigation too — there it only
        // changes tiles, since the nav camera owns the view.
        Positioned(
          left: 16,
          bottom: mapControlsBottomOffset(
            sheetHidden: _sheetHidden,
            navigating: _navigating,
          ),
          child: Material(
            color: const Color(0xFF1F2226),
            borderRadius: BorderRadius.circular(24),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final mode in MapViewMode.values)
                    _MapModeSegment(
                      label: switch (mode) {
                        MapViewMode.standard2d => '2D',
                        MapViewMode.perspective3d => '3D',
                        MapViewMode.satellite => 'Satellite',
                      },
                      selected: _mapMode == mode,
                      onTap: () {
                        if (_mapMode != mode) _applyMapMode(mode);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        // Navigator bottom bar + re-center pill (Google-style).
        if (_navigating)
          Positioned(left: 16, right: 16, bottom: 16, child: _navBottomBar()),
        if (_navigating)
          Positioned(
            right: 16,
            bottom: 100,
            child: Material(
              color: const Color(0xFF1F2226),
              borderRadius: BorderRadius.circular(24),
              elevation: 6,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _recenterNav,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.navigation, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Re-center',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Draggable bottom sheet: Collapsed / Half / Full.
        // Wrapped in Offstage (never removed from the tree) so the
        // logo toggle hides it without losing any state: same
        // content, same snap size when it comes back. Offstage
        // children take no hit tests, so the hidden sheet never
        // steals map gestures.
        if (!_navigating)
          Offstage(
            offstage: _sheetHidden,
            child: DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.18,
              minChildSize: 0.18,
              maxChildSize: 0.92,
              snap: true,
              snapSizes: const [0.18, 0.5, 0.92],
              builder: (context, scrollController) {
                return Material(
                  color: scheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                  elevation: 8,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: scheme.outline,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // A selected church replaces the Nearby Routes
                      // content (the sheet's own drag handle + snaps
                      // give it collapsed / half / expanded states).
                      // Closing it restores Nearby Routes.
                      if (_selectedChurch != null && _activeRoute == null)
                        _churchDetailsPanel(scheme, _selectedChurch!)
                      else ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _sheetTitle(),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _toggleDestinationMode,
                              child: Text(
                                _destinationMode
                                    ? 'Back to routes'
                                    : 'Plan a Trip',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_destinationMode)
                          _destinationPanel(scheme)
                        else
                          ..._routeSheetContent(
                            scheme: scheme,
                            routes: routes,
                            allCount: allRoutes.length,
                            northCount: northCount,
                            southCount: southCount,
                          ),
                      ],
                    ],
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
  void _toggleDestinationMode() {
    setState(() {
      if (!_destinationMode && _activeRoute != null) {
        final route = _activeRoute!;
        final toIdx = hubs.indexWhere((h) => h.name == route.dest.name);
        _toIndex = toIdx < 0 ? 1 : toIdx;
        if (route.originName == 'Your location') {
          _fromIndex = -1;
        } else {
          final fromIdx = hubs.indexWhere((h) => h.name == route.originName);
          _fromIndex = fromIdx < 0 ? _homeHub : fromIdx;
        }
      }
      _destinationMode = !_destinationMode;
    });
  }

  /// Sheet title follows the stop view: "All routes" when every stop is
  /// listed (picture-1 directory style), "Nearby Routes" otherwise.
  String _sheetTitle() {
    if (_destinationMode) return 'Choose a way to get there';
    switch (_stopView) {
      case _StopView.all:
        return 'All routes';
      case _StopView.nearest:
        return 'Nearest route';
      case _StopView.nearby:
        return 'Nearby Routes';
    }
  }

  List<Widget> _routeSheetContent({
    required ColorScheme scheme,
    required List<RouteInfo> routes,
    required int allCount,
    required int northCount,
    required int southCount,
  }) {
    final visible = filterRoutesByQuery(routes, _sheetSearchQuery);
    return [
      // In-sheet route search (picture-1 style).
      TextField(
        controller: _sheetSearchController,
        onChanged: (v) => setState(() => _sheetSearchQuery = v),
        decoration: InputDecoration(
          hintText: 'Search route, e.g. Vigan, Baguio',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _sheetSearchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _sheetSearchController.clear();
                    setState(() => _sheetSearchQuery = '');
                  },
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      const SizedBox(height: 12),
      // Stops, direction, and AM/PM stay here per his Nov 1 correction
      // ("wag mo ilipat to") — only vehicle + avoid moved to Plan a
      // Trip. Vehicle selection itself is no longer in this sheet.
      // In a church-originated preview these three rows hide, so
      // only the church route card shows below the search bar.
      if (showBrowsingChrome(_churchPreview)) ...[
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All stops'),
              selected: _stopView == _StopView.all,
              onSelected: (_) => setState(() => _stopView = _StopView.all),
            ),
            ChoiceChip(
              label: const Text('Nearest stop'),
              selected: _stopView == _StopView.nearest,
              onSelected: (_) => setState(() => _stopView = _StopView.nearest),
            ),
            FilterChip(
              label: const Text('Live Tracking'),
              selected: _tracking,
              onSelected: (_) => _toggleTracking(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Direction filters with live counts.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in {
                'All': allCount,
                'Northbound': northCount,
                'Southbound': southCount,
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${entry.key} (${entry.value})'),
                    selected: _direction == entry.key,
                    onSelected: (_) => setState(() => _direction = entry.key),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // AM/PM selection + honest schedule note.
        Row(
          children: [
            SegmentedButton<_AmPm>(
              segments: const [
                ButtonSegment(value: _AmPm.am, label: Text('AM')),
                ButtonSegment(value: _AmPm.pm, label: Text('PM')),
              ],
              selected: {_amPm},
              onSelectionChanged: (values) =>
                  setState(() => _amPm = values.first),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Walang verified timetable pa — hindi pa makakapag-filter '
                'ng departures ang AM/PM.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      if (_selectedHub != null)
        Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: const Icon(Icons.place),
                title: Text(_selectedHub!.name),
                subtitle: Text(_selectedHub!.region),
                trailing: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _selectedHub = null;
                      _activeRoute = null;
                      _activeRouteOrigin = null;
                      _roadPoints = null;
                      _routeError = null;
                      _churchPreview = false;
                    });
                  },
                ),
              ),
              // The tapped location's flow: origin → destination plus
              // the real computed numbers. No intermediate stops exist
              // in ByaheTayo's data, so the flow is the two endpoints.
              if (_activeRoute != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_activeRoute!.originName} → ${_selectedHub!.name} · '
                        '${_activeRoute!.roadKm.toStringAsFixed(1)} km · '
                        '${_previewSummaryFare()} · '
                        '${_activeRoute!.direction == Direction.northbound ? 'Northbound' : 'Southbound'}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _roadPoints == null
                            ? 'Dashed line = direct line, not the road path.'
                            : 'Solid line = road path (Google Maps route).',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (_routeError != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _routeError!,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                      // Google-style mode tabs: every mode's real ETA
                      // on the Google road distance. Tapping a tab
                      // switches the ETA + arrival shown below.
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final m in TravelMode.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  avatar: Icon(modeIcon(m), size: 18),
                                  label: Text(
                                    formatTripTime(_previewMinutes(m)),
                                  ),
                                  selected: _previewMode == m,
                                  onSelected: (_) =>
                                      setState(() => _previewMode = m),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Estimated arrival: About ${estimatedArrivalText(DateTime.now(), _previewMinutes(_previewMode))}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      // Real Google steps for this route, when loaded.
                      // No steps exist without a routing response, so
                      // the section simply stays hidden until then.
                      if (_navSteps != null && _navSteps!.isNotEmpty)
                        ExpansionTile(
                          title: Text(
                            'Route details (${_navSteps!.length} steps)',
                          ),
                          tilePadding: EdgeInsets.zero,
                          children: [
                            for (final s in _navSteps!)
                              ListTile(
                                leading: Icon(navArrowIcon(s.instruction)),
                                title: Text(shortAction(s.instruction)),
                                trailing: Text(
                                  formatNavDistance(s.distanceMeters / 1000),
                                ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              if (_activeRoute != null && !_navigating) ...[
                // Avoid controls moved Nov 1 to Plan a Trip.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _shareActiveRoute,
                          icon: const Icon(Icons.share),
                          label: const Text('Share route'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _toggleSaved(_activeRoute!),
                        icon: Icon(
                          _savedRoutes.contains(
                                '${_activeRoute!.originName}>${_activeRoute!.dest.name}',
                              )
                              ? Icons.favorite
                              : Icons.favorite_border,
                        ),
                        label: Text(
                          _savedRoutes.contains(
                                '${_activeRoute!.originName}>${_activeRoute!.dest.name}',
                              )
                              ? 'Saved'
                              : 'Save',
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_activeRoute != null && !_navigating)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _startNavigation,
                      icon: const Icon(Icons.navigation),
                      label: const Text('Start Navigation'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      // The direction-grouped stops list (and its empty state) hides
      // in a church-originated preview, like the rows above.
      if (showBrowsingChrome(_churchPreview)) ...[
        if (visible.isEmpty)
          Card(
            child: ListTile(
              title: Text(
                _vehicle == VehicleType.train
                    ? 'No available routes for this vehicle type.'
                    : _sheetSearchQuery.trim().isEmpty
                    ? 'Walang ruta sa filter na ito.'
                    : 'Walang rutang nakita para sa "$_sheetSearchQuery".',
              ),
              subtitle: Text(
                _vehicle == VehicleType.train
                    ? 'There is no passenger train service on these routes.'
                    : 'Subukan ang ibang search, direksyon o stop view.',
              ),
              trailing: _vehicle == VehicleType.train
                  ? TextButton(
                      onPressed: () =>
                          setState(() => _vehicle = VehicleType.anyVehicle),
                      child: const Text('View other vehicles'),
                    )
                  : null,
            ),
          )
        else if (_direction == 'All')
          for (final dir in Direction.values)
            ..._directionGroup(dir, visible, scheme)
        else
          for (final route in visible) _routeCard(route, scheme),
      ],
      if (_savedRoutes.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text(
          'Saved routes',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final key in _savedRoutes)
          Card(
            child: ListTile(
              leading: const Icon(Icons.favorite, color: Colors.red),
              title: Text(key.replaceAll('>', ' → ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openSavedRoute(key),
            ),
          ),
      ],
    ];
  }

  /// One picture-1-style direction section: a header plus its routes.
  /// Empty groups render nothing, so a one-direction origin shows a
  /// single section instead of a dangling header.
  List<Widget> _directionGroup(
    Direction dir,
    List<RouteInfo> routes,
    ColorScheme scheme,
  ) {
    final group = groupRoutesByDirection(routes)[dir]!;
    if (group.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          dir == Direction.northbound
              ? '↑ NORTHBOUND (${group.length})'
              : '↓ SOUTHBOUND (${group.length})',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
      for (final route in group) _routeCard(route, scheme),
    ];
  }

  /// One vehicle card: emerald border + green check when selected.
  Widget _vehicleCard(VehicleType v, ColorScheme scheme) {
    final selected = _vehicle == v;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _vehicle = v),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Column(
                children: [
                  Icon(
                    vehicleIcon(v),
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    vehicleLabel(v),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected ? scheme.primary : null,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                top: 4,
                right: 4,
                child: CircleAvatar(
                  radius: 9,
                  backgroundColor: scheme.primary,
                  child: Icon(Icons.check, size: 12, color: scheme.onPrimary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Vehicle selection, moved Nov 1 into Plan a Trip
  /// ("Plan a Trip" = _destinationPanel). The state is shared, so the
  /// same cards still drive the cursor and route filtering — they
  /// are no longer shown in the main route sheet.
  Widget _vehicleSelection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Vehicle Type',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < VehicleType.values.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == VehicleType.values.length - 1 ? 0 : 6,
                  ),
                  child: _vehicleCard(VehicleType.values[i], scheme),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _avoidControls() {
    return Wrap(
      spacing: 8,
      children: [
        FilterChip(
          label: const Text('Avoid highways'),
          selected: _avoidHighways,
          onSelected: (v) {
            setState(() => _avoidHighways = v);
            _refetchActiveRoute();
          },
        ),
        FilterChip(
          label: const Text('Avoid tolls'),
          selected: _avoidTolls,
          onSelected: (v) {
            setState(() => _avoidTolls = v);
            _refetchActiveRoute();
          },
        ),
        FilterChip(
          label: const Text('Avoid ferries'),
          selected: _avoidFerries,
          onSelected: (v) {
            setState(() => _avoidFerries = v);
            _refetchActiveRoute();
          },
        ),
      ],
    );
  }

  Widget _routeCard(RouteInfo route, ColorScheme scheme) {
    final key = '${route.originName}>${route.dest.name}';
    final saved = _savedRoutes.contains(key);
    // Vehicle-aware fare: bus previews use the provincial bus rate, a
    // user-verified fare wins for its pair, and car/motorcycle/train
    // previews show no fare instead of an invented one.
    final fare = resolveTransitFare(
      from: route.originName,
      to: route.dest.name,
      vehicle: _vehicle,
      roadKm: route.roadKm,
    );
    final modeLabel = previewModeLabel(_vehicle);
    return Card(
      child: ListTile(
        leading: Icon(
          _vehicle == VehicleType.car
              ? Icons.directions_car_outlined
              : _vehicle == VehicleType.motorcycle
              ? Icons.two_wheeler_outlined
              : _vehicle == VehicleType.train
              ? Icons.train_outlined
              : Icons.directions_bus_outlined,
        ),
        title: Text('${route.originName} → ${route.dest.name}'),
        subtitle: Text(
          '$modeLabel · ${route.roadKm.toStringAsFixed(1)} km · '
          '${route.direction == Direction.northbound ? 'Northbound' : 'Southbound'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fare != null)
              Text(
                peso(fare),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            IconButton(
              icon: Icon(
                saved ? Icons.favorite : Icons.favorite_border,
                color: saved ? Colors.red : null,
              ),
              tooltip: saved ? 'Remove from saved' : 'Save route',
              onPressed: () => _toggleSaved(route),
            ),
          ],
        ),
        onTap: () => _selectHub(route.dest),
      ),
    );
  }

  /// Navigator top banner (Google-style): the upcoming turn card
  /// (teal) + the turn after it (gray), each with its arrow, distance
  /// and short action — all derived from the real Google steps.
  Widget _navBanner() {
    final dest = _activeRoute?.dest;
    final pts = _roadPoints;
    final pos = _userPos;
    if (dest == null || pts == null || pos == null) {
      return const Material(
        elevation: 4,
        borderRadius: BorderRadius.all(Radius.circular(16)),
        color: Color(0xFF0E7C66),
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'Getting your location…',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    final user = LatLng(pos.latitude, pos.longitude);
    final userIdx = nearestPointIndex(pts, user);
    final remaining = pathKmBetween(pts, userIdx, pts.length - 1);
    final steps = _navSteps;
    if (steps == null || steps.isEmpty || _maneuverIdx.isEmpty) {
      return Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF0E7C66),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'Road directions unavailable — follow the line. '
            'Remaining: ${remaining.toStringAsFixed(1)} km to ${dest.name}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    final i = _navStepIndex.clamp(0, _maneuverIdx.length - 1);
    final step = steps[i.clamp(0, steps.length - 1)];
    final toTurn = pathKmBetween(pts, userIdx, _maneuverIdx[i]);
    final hasNext = i + 1 < _maneuverIdx.length && i + 1 < steps.length;
    Widget turnCard({
      required Color bg,
      required IconData icon,
      required String distance,
      required String action,
    }) {
      return Expanded(
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 32),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        distance,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        action,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        turnCard(
          bg: const Color(0xFF0E7C66),
          icon: navArrowIcon(step.instruction),
          distance: formatNavDistance(toTurn),
          action: shortAction(step.instruction),
        ),
        if (hasNext) ...[
          const SizedBox(width: 8),
          turnCard(
            bg: const Color(0xFF5B6470),
            icon: navArrowIcon(steps[i + 1].instruction),
            distance: formatNavDistance(
              pathKmBetween(pts, _maneuverIdx[i], _maneuverIdx[i + 1]),
            ),
            action: shortAction(steps[i + 1].instruction),
          ),
        ],
      ],
    );
  }

  /// Navigator bottom bar (Google-style): End button, remaining time
  /// + distance + arrival, voice toggle, and live speed.
  Widget _navBottomBar() {
    final dest = _activeRoute?.dest;
    final pts = _roadPoints;
    final pos = _userPos;
    var timeText = '--';
    var subText = '';
    if (dest != null && pts != null && pos != null) {
      final user = LatLng(pos.latitude, pos.longitude);
      final userIdx = nearestPointIndex(pts, user);
      final remaining = pathKmBetween(pts, userIdx, pts.length - 1);
      // Purely Google when available: remaining (Google polyline
      // sum) over Google's own distance, times Google's duration.
      // The x1.22 roadKm estimate is only the fallback.
      final full = _routeDistanceKm > 0
          ? _routeDistanceKm
          : (_activeRoute?.roadKm ?? 0);
      final mins = remainingMinutes(
        remainingKm: remaining,
        fullKm: full,
        durationSec: _routeDurationSec,
      );
      if (mins > 0) {
        timeText = '$mins min';
        subText =
            '${remaining.toStringAsFixed(1)} km • ${estimatedArrivalText(DateTime.now(), mins)}';
      } else {
        subText = '${remaining.toStringAsFixed(1)} km to ${dest.name}';
      }
    }
    final speedText = _navSpeedKmh > 0.5
        ? '${_navSpeedKmh.round()} km/h'
        : '-- km/h';
    return Material(
      color: const Color(0xFF1F2226),
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'End navigation',
              onPressed: _confirmEndNavigation,
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                  Text(
                    subText,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                _voiceOn ? Icons.volume_up : Icons.volume_off,
                color: Colors.white,
              ),
              tooltip: _voiceOn ? 'Mute voice' : 'Unmute voice',
              onPressed: () {
                setState(() => _voiceOn = !_voiceOn);
                if (_voiceOn && _navSteps != null && _navSteps!.isNotEmpty) {
                  _speakInstruction(
                    _navSteps![_navStepIndex.clamp(0, _navSteps!.length - 1)]
                        .instruction,
                  );
                } else {
                  _tts.stop();
                }
              },
            ),
            const SizedBox(width: 4),
            Text(
              speedText,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _destinationPanel(ColorScheme scheme) {
    final origin = _origin();
    final dest = hubs[_toIndex];
    final sameHub = origin.hub?.name == dest.name;
    final direct = haversineKm(origin.lat, origin.lng, dest.lat, dest.lng);
    final roadKm = math.max(1.0, direct * 1.22);
    final mountain =
        (origin.hub != null && isMountainHub(origin.hub!)) ||
        isMountainHub(dest);
    final sameRegion = origin.hub != null && origin.hub!.region == dest.region;
    final minutes = estimateTripMinutes(
      roadKm: roadKm,
      mountain: mountain,
      sameRegion: sameRegion,
      mode: _travelMode,
    );
    // Best-options comparison (Davao reference "Choose a way to get
    // there"): every mode's real ETA; the quickest gets the FASTEST
    // badge. Tapping a card selects that mode for the detail below.
    final modeMinutes = {
      for (final m in TravelMode.values)
        m: estimateTripMinutes(
          roadKm: roadKm,
          mountain: mountain,
          sameRegion: sameRegion,
          mode: m,
        ),
    };
    final fastest = modeMinutes.values.reduce(math.min);
    // The transit card's fare is the bus fare: a user-verified fare
    // wins for the pair, otherwise the provincial bus formula fare.
    final transitFare = resolveTransitFare(
      from: origin.hub?.name ?? '',
      to: dest.name,
      vehicle: VehicleType.bus,
      roadKm: roadKm,
    );
    final transitFareText = transitFare == null ? 'No fare' : peso(transitFare);
    double? walkKm;
    if (_fromIndex == -1) {
      walkKm = 0;
    } else if (_userPos != null) {
      walkKm = roadKmBetween(
        _userPos!.latitude,
        _userPos!.longitude,
        origin.lat,
        origin.lng,
      );
    }
    String fareText;
    String? fareNote;
    if (_travelMode == TravelMode.transit) {
      // Same resolved bus fare as the transit card above, so the
      // panel and the card never disagree; the note below now
      // describes the fare actually shown.
      fareText = transitFareText;
      final verified = origin.hub != null
          ? knownBusFares['${origin.hub!.name}|${dest.name}']
          : null;
      if (verified != null) {
        fareNote =
            'User-verified bus fare: ₱$verified (reported Oct 16, 2026).';
      }
    } else {
      fareText = 'No fare';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          value: _fromIndex,
          decoration: const InputDecoration(labelText: 'From'),
          items: [
            const DropdownMenuItem(value: -1, child: Text('My location')),
            for (var i = 0; i < hubs.length; i++)
              DropdownMenuItem(value: i, child: Text(hubs[i].name)),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _fromIndex = v);
            if (v >= 0) _selectHub(hubs[v]);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: _toIndex,
          decoration: const InputDecoration(labelText: 'To'),
          items: [
            for (var i = 0; i < hubs.length; i++)
              DropdownMenuItem(value: i, child: Text(hubs[i].name)),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _toIndex = v);
            _selectHub(hubs[v]);
          },
        ),
        const SizedBox(height: 12),
        // Start sits here, not at the bottom of the detail card:
        // at half sheet the old spot was below the fold, so the
        // panel looked like it had no navigate action at all.
        if (!sameHub) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                if (_activeRoute?.dest.name != dest.name) {
                  _selectHub(dest);
                }
                _startNavigation();
              },
              icon: const Icon(Icons.navigation),
              label: const Text('Start Navigation'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Moved Nov 1 from the main route sheet, per his order:
        // vehicle + avoid controls now live in Plan a Trip.
        // Stops, direction, and AM/PM were NOT moved, per his
        // correction ("wag mo ilipat to") — they stay in the main
        // route sheet.
        if (!sameHub) ...[
          _vehicleSelection(scheme),
          const SizedBox(height: 12),
          _avoidControls(),
          const SizedBox(height: 12),
        ],
        if (!sameHub) ...[
          const Text(
            'Best options',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final mode in TravelMode.values)
            Card(
              child: ListTile(
                leading: Icon(
                  mode == TravelMode.transit
                      ? Icons.directions_bus_outlined
                      : mode == TravelMode.motorcycle
                      ? Icons.two_wheeler_outlined
                      : mode == TravelMode.bicycle
                      ? Icons.directions_bike_outlined
                      : Icons.directions_walk_outlined,
                ),
                title: Text(mode.label),
                subtitle: Text(
                  'About ${formatTripTime(modeMinutes[mode]!)}'
                  '${mode == TravelMode.transit ? ' · 1 direct ride' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (modeMinutes[mode] == fastest)
                      Chip(
                        label: const Text('FASTEST'),
                        backgroundColor: scheme.primary,
                        labelStyle: TextStyle(
                          color: scheme.onPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (modeMinutes[mode] == fastest) const SizedBox(width: 8),
                    Text(
                      mode == TravelMode.transit ? transitFareText : 'No fare',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                selected: _travelMode == mode,
                onTap: () => setState(() => _travelMode = mode),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (sameHub)
          const Card(child: ListTile(title: Text('Choose two different hubs.')))
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${origin.name} → ${dest.name}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _resultRow('Distance', '${roadKm.toStringAsFixed(1)} km'),
                  _resultRow(
                    'Estimated time',
                    'About ${formatTripTime(minutes)}',
                  ),
                  _resultRow(
                    'Estimated arrival',
                    'About ${estimatedArrivalText(DateTime.now(), minutes)}',
                  ),
                  _resultRow('Rides', '1 direct ride'),
                  _resultRow(
                    'Walking distance',
                    walkKm == null
                        ? '—'
                        : walkKm == 0
                        ? 'You are here'
                        : '${walkKm.toStringAsFixed(1)} km to origin',
                  ),
                  _resultRow('Estimated fare', fareText),
                  if (fareNote != null) ...[
                    const SizedBox(height: 8),
                    Text(fareNote, style: const TextStyle(fontSize: 12)),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Estimated from approximate road distance and a typical '
                    'pace. Actual routes can vary.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _shareRouteText(
                            'EstudyanteGO route: ${origin.name} → ${dest.name} · '
                            '${roadKm.toStringAsFixed(1)} km · '
                            'About ${formatTripTime(minutes)} · '
                            'Estimated fare $fareText',
                          ),
                          icon: const Icon(Icons.share),
                          label: const Text('Share'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final matches = routesFrom(
                              origin.lat,
                              origin.lng,
                              origin.name,
                            ).where((r) => r.dest.name == dest.name).toList();
                            if (matches.isNotEmpty) {
                              _toggleSaved(matches.first);
                            }
                          },
                          icon: Icon(
                            _savedRoutes.contains('${origin.name}>${dest.name}')
                                ? Icons.favorite
                                : Icons.favorite_border,
                          ),
                          label: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
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

/// ByaheTayo logo toggle: same look as the sidebar header logo
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
      borderRadius: BorderRadius.circular(10),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
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

/// One segment of the floating 2D / 3D / Satellite selector.
class _MapModeSegment extends StatelessWidget {
  const _MapModeSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF16A34A) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
