// Admin-added routes for the Map and Fares tabs (Add Route, Nov 6, 2026).
//
// ADMIN-ONLY: only the two allowlisted admin emails (see
// admin_access.dart) may create, edit, or delete these routes. The
// check runs on the AUTHENTICATED Firebase user (AuthUser.email),
// never on an editable profile field and never on a UI toggle — and
// it is enforced again in the repository methods, not just by hiding
// the Add Route button. Regular users only ever SEE the routes an
// admin added; their own route-sharing path stays Communities →
// Share a Local Route, which needs admin approval before it is public.
//
// A custom route is the admin's OWN route: From/To are hubs, the
// operator and fare are typed by the admin (never invented by the
// app), and the line is the admin's OWN ordered via-stops — so a
// Partas route can draw a different line from a Dominion route for
// the same From → To. Distance/ETA come from the app's existing
// formulas (roadKmBetween / estimateTripMinutes) over the chosen
// From → via → To coordinates, or show '—' where no verified value
// exists. The sample fares (₱45 Vigan → San Juan, ₱120 Laoag →
// Vigan) are NOT seeded here: an admin types the real fare, or the
// route is not saved.
//
// Persistence: Firestore collection `custom_routes` when signed in
// (rules: reads signed-in, writes admin-only), with a
// SharedPreferences cache so added routes survive restarts and
// load offline. The cache is never presented as shared/public.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_access.dart';
import 'bus_stops.dart';
import 'fares_tab.dart';
import 'map_tab.dart';
import 'onboarding/auth_service.dart';
import 'osm_routing.dart';
import 'route_fare_overrides.dart';

/// Firestore collection for admin-added routes.
const customRoutesCollection = 'custom_routes';

/// SharedPreferences key for the local custom-routes cache.
const customRoutesCacheKey = 'custom_routes_cache_v1';

/// Bumped after every successful custom-route mutation (create /
/// update / delete), so the Fares tab reloads its route list
/// without a restart — e.g. after the Map tab's line maker saves
/// a drawn line. Reads never bump.
final customRoutesChanged = ValueNotifier<int>(0);

/// Operators already in the app (operator fares dataset + the
/// Northern Luzon operator scope). Presets only — the admin can
/// always type a different operator name.
const customRouteOperatorPresets = <String>[
  'Partas',
  'Dominion Bus Lines',
  'GV Florida Transport',
  'Viron Transit',
  'Victory Liner',
  'Solid North Transit',
  'Dagupan Bus',
  'Genesis Transport',
  'Five Star Bus',
  'JAC Liner',
  'ALPS The Bus',
  'Bicol Isarog',
];

/// Vehicles an added route may use. No train: there is no passenger
/// train service on these Northern Luzon routes.
const customRouteVehicles = <String>['Bus', 'Jeepney', 'Van', 'Tricycle'];

/// VehicleType used for route filtering: Bus maps to bus, the rest
/// are transit (anyVehicle) — the filter only ever excludes trains.
VehicleType customRouteVehicleType(String vehicle) =>
    vehicle == 'Bus' ? VehicleType.bus : VehicleType.anyVehicle;

/// One admin-added route.
class CustomRoute {
  const CustomRoute({
    this.id,
    required this.from,
    required this.to,
    required this.operator,
    required this.vehicle,
    required this.fare,
    this.studentFare,
    this.pwdFare,
    this.seniorFare,
    this.viaHubs = const [],
    this.viaWaypoints = const [],
    this.authorUid = '',
    this.authorEmail = '',
    this.createdAt,
    this.updatedAt,
  });

  /// Firestore document id (null until saved).
  final String? id;

  /// Hub names — always members of [hubs].
  final String from;
  final String to;

  /// Bus company / operator, typed by the admin.
  final String operator;

  /// One of [customRouteVehicles].
  final String vehicle;

  /// Fare in pesos, typed by the admin. Always > 0.
  final double fare;

  /// Student fare in pesos, typed by the admin — or null to derive
  /// 20% off [fare] (see [discountedFareOf] in fares_tab.dart).
  /// Null is the default: an admin only types this when the
  /// student fare is NOT the plain 20% discount.
  final double? studentFare;

  /// PWD fare in pesos, typed by the admin — or null to derive
  /// 20% off [fare]. Same pattern as [studentFare].
  final double? pwdFare;

  /// Senior Citizen fare in pesos, typed by the admin — or null
  /// to derive 20% off [fare]. Same pattern as [studentFare].
  final double? seniorFare;

  /// Ordered via-stops (hub names) the line must pass through.
  /// Empty = the generic From → To line.
  final List<String> viaHubs;

  /// Ordered waypoints of a line the admin drew on the map
  /// (line maker): raw tapped points, named when the admin
  /// saved the point as a bus stop. Non-empty wins over
  /// [viaHubs] for the line — the drawn line IS the direction.
  /// Empty = use [viaHubs].
  final List<RouteWaypoint> viaWaypoints;

  /// Stamped from the authenticated admin, never from form input.
  final String authorUid;
  final String authorEmail;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CustomRoute copyWith({
    String? id,
    String? from,
    String? to,
    String? operator,
    String? vehicle,
    double? fare,
    double? studentFare,
    double? pwdFare,
    double? seniorFare,
    List<String>? viaHubs,
    List<RouteWaypoint>? viaWaypoints,
    String? authorUid,
    String? authorEmail,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomRoute(
      id: id ?? this.id,
      from: from ?? this.from,
      to: to ?? this.to,
      operator: operator ?? this.operator,
      vehicle: vehicle ?? this.vehicle,
      fare: fare ?? this.fare,
      studentFare: studentFare ?? this.studentFare,
      pwdFare: pwdFare ?? this.pwdFare,
      seniorFare: seniorFare ?? this.seniorFare,
      viaHubs: viaHubs ?? this.viaHubs,
      viaWaypoints: viaWaypoints ?? this.viaWaypoints,
      authorUid: authorUid ?? this.authorUid,
      authorEmail: authorEmail ?? this.authorEmail,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'from': from,
    'to': to,
    'operator': operator,
    'vehicle': vehicle,
    'fare': fare,
    if (studentFare != null) 'studentFare': studentFare,
    if (pwdFare != null) 'pwdFare': pwdFare,
    if (seniorFare != null) 'seniorFare': seniorFare,
    'viaHubs': viaHubs,
    if (viaWaypoints.isNotEmpty)
      'viaWaypoints': viaWaypoints.map((w) => w.toJson()).toList(),
    if (authorUid.isNotEmpty) 'authorUid': authorUid,
    if (authorEmail.isNotEmpty) 'authorEmail': authorEmail,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  static CustomRoute fromJson(String id, Map<String, dynamic> data) {
    final via = data['viaHubs'];
    final waypoints = data['viaWaypoints'];
    // Cached JSON carries the id inside the map; Firestore docs
    // carry it as the document id. Either source wins over ''.
    final storedId = data['id'] is String ? data['id'] as String : '';
    return CustomRoute(
      id: id.isNotEmpty ? id : storedId,
      from: data['from'] is String ? data['from'] as String : '',
      to: data['to'] is String ? data['to'] as String : '',
      operator: data['operator'] is String ? data['operator'] as String : '',
      vehicle: data['vehicle'] is String ? data['vehicle'] as String : '',
      fare: data['fare'] is num ? (data['fare'] as num).toDouble() : 0,
      studentFare: data['studentFare'] is num
          ? (data['studentFare'] as num).toDouble()
          : null,
      pwdFare: data['pwdFare'] is num
          ? (data['pwdFare'] as num).toDouble()
          : null,
      seniorFare: data['seniorFare'] is num
          ? (data['seniorFare'] as num).toDouble()
          : null,
      viaHubs: via is List ? via.whereType<String>().toList() : const [],
      viaWaypoints: waypoints is List
          ? waypoints
                .map(RouteWaypoint.fromJson)
                .whereType<RouteWaypoint>()
                .toList()
          : const [],
      authorUid: data['authorUid'] is String ? data['authorUid'] : '',
      authorEmail:
          data['authorEmail'] is String ? data['authorEmail'] : '',
      createdAt: data['createdAt'] is String
          ? DateTime.tryParse(data['createdAt'] as String)
          : null,
      updatedAt: data['updatedAt'] is String
          ? DateTime.tryParse(data['updatedAt'] as String)
          : null,
    );
  }
}

/// Hub by name, or null when the name is not one of [hubs] nor
/// an admin-added stop in [busStops].
Hub? hubByName(String name, [List<BusStop> busStops = const []]) {
  return resolveHub(name, busStops);
}

/// Effective ordered waypoints for a route's line: the drawn
/// line's raw points win; else the named via stops, resolved
/// with [busStops]. A custom route's own waypoints win over an
/// override's (overrides never exist for custom routes, and the
/// override's via stops only apply to generated routes).
List<RouteWaypoint> effectiveRouteWaypoints({
  CustomRoute? customRoute,
  RouteFareOverride? override,
  List<BusStop> busStops = const [],
}) {
  final drawn = customRoute?.viaWaypoints.isNotEmpty == true
      ? customRoute!.viaWaypoints
      : override?.viaWaypoints;
  if (drawn != null && drawn.isNotEmpty) return List.of(drawn);
  final names =
      customRoute?.viaHubs ?? override?.viaHubs ?? const <String>[];
  final out = <RouteWaypoint>[];
  for (final name in names) {
    final hub = hubByName(name, busStops);
    if (hub != null) {
      out.add(RouteWaypoint(name: name, lat: hub.lat, lng: hub.lng));
    }
  }
  return out;
}

/// Validates an Add Route form. Returns the first problem, or null
/// when the route may be saved. Never invents a value: a missing or
/// invalid field blocks the save. [busStops] are the admin-added
/// stops the endpoints / via stops may name.
String? validateCustomRoute({
  required String? from,
  required String? to,
  required String operator,
  required String? vehicle,
  required String fareText,
  List<BusStop> busStops = const [],
}) {
  if (from == null || from.isEmpty || hubByName(from, busStops) == null) {
    return 'Choose a From hub.';
  }
  if (to == null || to.isEmpty || hubByName(to, busStops) == null) {
    return 'Choose a To hub.';
  }
  if (from == to) {
    return 'From and To cannot be the same place.';
  }
  if (operator.trim().isEmpty) {
    return 'Enter the operator / bus company.';
  }
  if (vehicle == null || !customRouteVehicles.contains(vehicle)) {
    return 'Choose a vehicle.';
  }
  final fare = double.tryParse(fareText.trim());
  if (fare == null) {
    return 'Enter the fare in pesos (numbers only).';
  }
  if (fare <= 0) {
    return 'The fare must be more than ₱0.';
  }
  return null;
}

/// The line a custom route draws: From → effective waypoints in
/// order → To, as coordinates. A drawn line's raw points win
/// over the named via stops (see [effectiveRouteWaypoints]).
/// Unknown hub names are skipped (validation prevents them on
/// save; this guards old or corrupt data).
List<LatLng> customRouteLinePoints(
  CustomRoute route, [
  List<BusStop> busStops = const [],
]) {
  final points = <LatLng>[];
  final from = hubByName(route.from, busStops);
  if (from != null) points.add(LatLng(from.lat, from.lng));
  for (final waypoint in effectiveRouteWaypoints(
    customRoute: route,
    busStops: busStops,
  )) {
    points.add(waypoint.point);
  }
  final to = hubByName(route.to, busStops);
  if (to != null) points.add(LatLng(to.lat, to.lng));
  return points;
}

/// Road distance for a custom route: the app's ×1.22 rule summed
/// over each leg (From → via… → To).
double customRouteRoadKm(
  CustomRoute route, [
  List<BusStop> busStops = const [],
]) {
  final points = customRouteLinePoints(route, busStops);
  var total = 0.0;
  for (var i = 0; i + 1 < points.length; i++) {
    total += roadKmBetween(
      points[i].latitude,
      points[i].longitude,
      points[i + 1].latitude,
      points[i + 1].longitude,
    );
  }
  return total;
}

/// Transit ETA minutes for a custom route, from the app's existing
/// estimateTripMinutes model over [customRouteRoadKm].
int customRouteEtaMinutes(
  CustomRoute route, [
  List<BusStop> busStops = const [],
]) {
  final from = hubByName(route.from, busStops);
  final to = hubByName(route.to, busStops);
  final roadKm = customRouteRoadKm(route, busStops);
  final mountain =
      (from != null && isMountainHub(from)) ||
      (to != null && isMountainHub(to));
  final sameRegion =
      from != null && to != null && from.region == to.region;
  return estimateTripMinutes(
    roadKm: roadKm,
    mountain: mountain,
    sameRegion: sameRegion,
    mode: TravelMode.transit,
  );
}

/// Transit ETA minutes for any road distance, using the same
/// estimateTripMinutes model the Map tab uses. Use when neither
/// endpoint is a known hub (e.g. a named terminal that is not in
/// the hub list) — no hub-dependent rule can apply, so the
/// defaults are non-mountain / not same-region.
int transitEtaMinutes({required double roadKm}) {
  return estimateTripMinutes(
    roadKm: roadKm,
    mountain: false,
    sameRegion: false,
    mode: TravelMode.transit,
  );
}

/// Transit ETA minutes for any hub pair over a road distance
/// (preview parity: the Fares breakdown sheet shows an ETA next to
/// the distance, using the same estimateTripMinutes model the Map
/// tab uses — mountain / same-region rules from the two hubs).
/// A null [from] (GPS origin) counts as non-mountain and not
/// same-region, exactly like the custom-route helper.
int hubPairEtaMinutes({
  Hub? from,
  required Hub to,
  required double roadKm,
}) {
  return estimateTripMinutes(
    roadKm: roadKm,
    mountain:
        (from != null && isMountainHub(from)) || isMountainHub(to),
    sameRegion: from != null && from.region == to.region,
    mode: TravelMode.transit,
  );
}

/// Stops along the way for a hub pair, WITHOUT road geometry: the
/// origin, the destination, and a custom route's own via-hubs in
/// the admin's order. No intermediate hub is ever guessed — the
/// Map tab recomputes the full on-the-way list once its OSRM
/// geometry loads (see _refreshRouteStops). Used by the Fares
/// breakdown sheet, which has no geometry of its own.
/// [viaWaypoints] (a drawn line) wins over [viaHubNames] for the
/// intermediate stops; [extraStops] are the admin-added stops
/// the names may resolve to.
List<RouteStop> hubPairStops({
  required Hub from,
  required Hub to,
  required double totalKm,
  List<String> viaHubNames = const [],
  List<RouteWaypoint> viaWaypoints = const [],
  List<BusStop> extraStops = const [],
}) {
  return routeStops(
    origin: LatLng(from.lat, from.lng),
    originName: from.name,
    dest: to,
    roadPoints: null,
    totalKm: totalKm,
    viaHubNames: viaHubNames,
    viaWaypoints: viaWaypoints,
    extraStops: extraStops,
  );
}

/// A custom route as a [RouteInfo] for the Map sheet list, carrying
/// the custom route so the card and the line can use its operator,
/// fare, and via-stops instead of the generic hub route.
RouteInfo customRouteToRouteInfo(
  CustomRoute route, [
  List<BusStop> busStops = const [],
]) {
  final to = hubByName(route.to, busStops);
  final from = hubByName(route.from, busStops);
  final roadKm = customRouteRoadKm(route, busStops);
  return RouteInfo(
    originName: route.from,
    dest: to ?? const Hub('Unknown', '', 0, 0),
    roadKm: roadKm,
    direction: from == null || to == null
        ? Direction.southbound
        : directionOf(from.lat, to.lat),
    customRoute: route,
  );
}

/// Admin-added route storage. Mutations enforce the admin allowlist
/// here — a caller that forgets the UI gate still cannot write.
abstract class CustomRouteRepository {
  /// All admin-added routes, newest first. Reads never throw: a
  /// Firestore failure returns the local cache (possibly empty).
  Future<List<CustomRoute>> loadAll();

  /// Creates a route as [author]. Throws [StateError] unless the
  /// author is an admin; throws [ArgumentError] on invalid input.
  /// [busStops] are the admin-added stops the endpoints / via
  /// stops may name.
  Future<CustomRoute> create(
    CustomRoute route,
    AuthUser author, {
    List<BusStop> busStops = const [],
  });

  /// Updates a route as [author]. Same admin + validation rules.
  Future<CustomRoute> update(
    CustomRoute route,
    AuthUser author, {
    List<BusStop> busStops = const [],
  });

  /// Deletes a route as [author]. Throws [StateError] unless admin.
  Future<void> delete(CustomRoute route, AuthUser author);
}

/// Validates a route object itself (repository-side, same rules as
/// the form validator, minus the text parsing). A student fare is
/// optional, but when present it must be more than ₱0 — same for
/// the PWD and Senior Citizen fares.
String? validateCustomRouteObject(
  CustomRoute route, {
  List<BusStop> busStops = const [],
}) {
  final base = validateCustomRoute(
    from: route.from,
    to: route.to,
    operator: route.operator,
    vehicle: route.vehicle,
    fareText: route.fare.toString(),
    busStops: busStops,
  );
  if (base != null) return base;
  if (route.studentFare != null && route.studentFare! <= 0) {
    return 'The student fare must be more than ₱0.';
  }
  if (route.pwdFare != null && route.pwdFare! <= 0) {
    return 'The PWD fare must be more than ₱0.';
  }
  if (route.seniorFare != null && route.seniorFare! <= 0) {
    return 'The Senior Citizen fare must be more than ₱0.';
  }
  return null;
}

List<CustomRoute> _sortedNewestFirst(List<CustomRoute> routes) {
  final sorted = List<CustomRoute>.of(routes);
  sorted.sort((a, b) {
    final aTime = a.createdAt;
    final bTime = b.createdAt;
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return bTime.compareTo(aTime);
  });
  return sorted;
}

/// Firestore implementation with a SharedPreferences cache fallback.
class FirestoreCustomRouteRepository implements CustomRouteRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection(customRoutesCollection);

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> _writeCache(List<CustomRoute> routes) async {
    final prefs = await _prefs;
    final jsonList = routes.map((r) => r.toJson()).toList();
    await prefs.setString(customRoutesCacheKey, jsonEncode(jsonList));
  }

  Future<List<CustomRoute>> _readCache() async {
    final prefs = await _prefs;
    final raw = prefs.getString(customRoutesCacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((m) => CustomRoute.fromJson('', m))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> _doc(CustomRoute route, AuthUser author) {
    return {
      ...route
          .copyWith(authorUid: author.uid, authorEmail: author.email)
          .toJson(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  @override
  Future<List<CustomRoute>> loadAll() async {
    try {
      final snap = await _collection
          .orderBy('createdAt', descending: true)
          .get();
      final routes = snap.docs
          .map((d) => CustomRoute.fromJson(d.id, d.data()))
          .toList();
      await _writeCache(routes);
      return routes;
    } catch (_) {
      // Offline / Firestore unavailable: the local cache is the
      // honest fallback, never an invented list.
      return _readCache();
    }
  }

  @override
  Future<CustomRoute> create(
    CustomRoute route,
    AuthUser author, {
    List<BusStop> busStops = const [],
  }) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can add routes.');
    }
    final error = validateCustomRouteObject(route, busStops: busStops);
    if (error != null) throw ArgumentError(error);
    final ref = await _collection.add(_doc(route, author));
    final snap = await ref.get();
    final data = snap.data();
    final created = CustomRoute.fromJson(ref.id, data ?? route.toJson())
        .copyWith(authorUid: author.uid, authorEmail: author.email);
    final current = await loadAll();
    if (current.every((r) => r.id != ref.id)) {
      await _writeCache([created, ...current]);
    }
    customRoutesChanged.value++;
    return created;
  }

  @override
  Future<CustomRoute> update(
    CustomRoute route,
    AuthUser author, {
    List<BusStop> busStops = const [],
  }) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can edit routes.');
    }
    final error = validateCustomRouteObject(route, busStops: busStops);
    if (error != null) throw ArgumentError(error);
    final id = route.id;
    if (id == null || id.isEmpty) {
      throw StateError('Cannot update a route that was never saved.');
    }
    await _collection.doc(id).update({
      'from': route.from,
      'to': route.to,
      'operator': route.operator,
      'vehicle': route.vehicle,
      'fare': route.fare,
      'studentFare': route.studentFare,
      'pwdFare': route.pwdFare,
      'seniorFare': route.seniorFare,
      'viaHubs': route.viaHubs,
      'viaWaypoints': route.viaWaypoints.map((w) => w.toJson()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final updated = route.copyWith(updatedAt: DateTime.now());
    final current = await loadAll();
    await _writeCache(
      current.map((r) => r.id == id ? updated : r).toList(),
    );
    customRoutesChanged.value++;
    return updated;
  }

  @override
  Future<void> delete(CustomRoute route, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can delete routes.');
    }
    final id = route.id;
    if (id == null || id.isEmpty) {
      throw StateError('Cannot delete a route that was never saved.');
    }
    await _collection.doc(id).delete();
    final current = await loadAll();
    await _writeCache(current.where((r) => r.id != id).toList());
    customRoutesChanged.value++;
  }
}

/// SharedPreferences-only implementation, used when Firebase is not
/// configured. Same admin enforcement; routes stay on this device.
class LocalCustomRouteRepository implements CustomRouteRepository {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<CustomRoute>> _readAll() async {
    final prefs = await _prefs;
    final raw = prefs.getString(customRoutesCacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final routes = <CustomRoute>[];
      for (final item in decoded) {
        // Pass '' so fromJson uses the id stored inside the map —
        // a positional id here would orphan every saved route on
        // the next read (update/delete would never find it again).
        if (item is Map<String, dynamic>) {
          routes.add(CustomRoute.fromJson('', item));
        } else if (item is Map) {
          routes.add(
            CustomRoute.fromJson('', Map<String, dynamic>.from(item)),
          );
        }
      }
      return _sortedNewestFirst(routes);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeAll(List<CustomRoute> routes) async {
    final prefs = await _prefs;
    await prefs.setString(
      customRoutesCacheKey,
      jsonEncode(routes.map((r) => r.toJson()).toList()),
    );
  }

  @override
  Future<List<CustomRoute>> loadAll() => _readAll();

  @override
  Future<CustomRoute> create(
    CustomRoute route,
    AuthUser author, {
    List<BusStop> busStops = const [],
  }) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can add routes.');
    }
    final error = validateCustomRouteObject(route, busStops: busStops);
    if (error != null) throw ArgumentError(error);
    final now = DateTime.now();
    final created = route.copyWith(
      id: 'local-${now.microsecondsSinceEpoch}',
      authorUid: author.uid,
      authorEmail: author.email,
      createdAt: now,
      updatedAt: now,
    );
    final current = await _readAll();
    await _writeAll([created, ...current]);
    customRoutesChanged.value++;
    return created;
  }

  @override
  Future<CustomRoute> update(
    CustomRoute route,
    AuthUser author, {
    List<BusStop> busStops = const [],
  }) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can edit routes.');
    }
    final error = validateCustomRouteObject(route, busStops: busStops);
    if (error != null) throw ArgumentError(error);
    final id = route.id;
    if (id == null || id.isEmpty) {
      throw StateError('Cannot update a route that was never saved.');
    }
    final current = await _readAll();
    if (current.every((r) => r.id != id)) {
      throw StateError('That route no longer exists.');
    }
    final updated = route.copyWith(updatedAt: DateTime.now());
    await _writeAll(
      current.map((r) => r.id == id ? updated : r).toList(),
    );
    customRoutesChanged.value++;
    return updated;
  }

  @override
  Future<void> delete(CustomRoute route, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can delete routes.');
    }
    final id = route.id;
    if (id == null || id.isEmpty) {
      throw StateError('Cannot delete a route that was never saved.');
    }
    final current = await _readAll();
    await _writeAll(current.where((r) => r.id != id).toList());
    customRoutesChanged.value++;
  }
}
