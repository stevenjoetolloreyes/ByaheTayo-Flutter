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
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_access.dart';
import 'fares_tab.dart';
import 'map_tab.dart';
import 'onboarding/auth_service.dart';

/// Firestore collection for admin-added routes.
const customRoutesCollection = 'custom_routes';

/// SharedPreferences key for the local custom-routes cache.
const customRoutesCacheKey = 'custom_routes_cache_v1';

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
    this.viaHubs = const [],
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

  /// Ordered via-stops (hub names) the line must pass through.
  /// Empty = the generic From → To line.
  final List<String> viaHubs;

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
    List<String>? viaHubs,
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
      viaHubs: viaHubs ?? this.viaHubs,
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
    'viaHubs': viaHubs,
    if (authorUid.isNotEmpty) 'authorUid': authorUid,
    if (authorEmail.isNotEmpty) 'authorEmail': authorEmail,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  static CustomRoute fromJson(String id, Map<String, dynamic> data) {
    final via = data['viaHubs'];
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
      viaHubs: via is List ? via.whereType<String>().toList() : const [],
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

/// Hub by name, or null when the name is not one of [hubs].
Hub? hubByName(String name) {
  for (final hub in hubs) {
    if (hub.name == name) return hub;
  }
  return null;
}

/// Validates an Add Route form. Returns the first problem, or null
/// when the route may be saved. Never invents a value: a missing or
/// invalid field blocks the save.
String? validateCustomRoute({
  required String? from,
  required String? to,
  required String operator,
  required String? vehicle,
  required String fareText,
}) {
  if (from == null || from.isEmpty || hubByName(from) == null) {
    return 'Choose a From hub.';
  }
  if (to == null || to.isEmpty || hubByName(to) == null) {
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

/// The line a custom route draws: From → via-stops in order → To,
/// as coordinates. Unknown hub names are skipped (validation
/// prevents them on save; this guards old or corrupt data).
List<LatLng> customRouteLinePoints(CustomRoute route) {
  final points = <LatLng>[];
  final from = hubByName(route.from);
  if (from != null) points.add(LatLng(from.lat, from.lng));
  for (final name in route.viaHubs) {
    final hub = hubByName(name);
    if (hub != null) points.add(LatLng(hub.lat, hub.lng));
  }
  final to = hubByName(route.to);
  if (to != null) points.add(LatLng(to.lat, to.lng));
  return points;
}

/// Road distance for a custom route: the app's ×1.22 rule summed
/// over each leg (From → via… → To).
double customRouteRoadKm(CustomRoute route) {
  final points = customRouteLinePoints(route);
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
int customRouteEtaMinutes(CustomRoute route) {
  final from = hubByName(route.from);
  final to = hubByName(route.to);
  final roadKm = customRouteRoadKm(route);
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

/// A custom route as a [RouteInfo] for the Map sheet list, carrying
/// the custom route so the card and the line can use its operator,
/// fare, and via-stops instead of the generic hub route.
RouteInfo customRouteToRouteInfo(CustomRoute route) {
  final to = hubByName(route.to);
  final from = hubByName(route.from);
  final roadKm = customRouteRoadKm(route);
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
  Future<CustomRoute> create(CustomRoute route, AuthUser author);

  /// Updates a route as [author]. Same admin + validation rules.
  Future<CustomRoute> update(CustomRoute route, AuthUser author);

  /// Deletes a route as [author]. Throws [StateError] unless admin.
  Future<void> delete(CustomRoute route, AuthUser author);
}

/// Validates a route object itself (repository-side, same rules as
/// the form validator, minus the text parsing).
String? validateCustomRouteObject(CustomRoute route) {
  return validateCustomRoute(
    from: route.from,
    to: route.to,
    operator: route.operator,
    vehicle: route.vehicle,
    fareText: route.fare.toString(),
  );
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
  Future<CustomRoute> create(CustomRoute route, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can add routes.');
    }
    final error = validateCustomRouteObject(route);
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
    return created;
  }

  @override
  Future<CustomRoute> update(CustomRoute route, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can edit routes.');
    }
    final error = validateCustomRouteObject(route);
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
      'viaHubs': route.viaHubs,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final updated = route.copyWith(updatedAt: DateTime.now());
    final current = await loadAll();
    await _writeCache(
      current.map((r) => r.id == id ? updated : r).toList(),
    );
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
  Future<CustomRoute> create(CustomRoute route, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can add routes.');
    }
    final error = validateCustomRouteObject(route);
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
    return created;
  }

  @override
  Future<CustomRoute> update(CustomRoute route, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can edit routes.');
    }
    final error = validateCustomRouteObject(route);
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
  }
}
