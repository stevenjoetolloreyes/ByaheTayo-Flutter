// Fare/direction overrides for the built-in (seeded) Popular Routes
// (Nov 7, 2026 — Steven: fares, student fares, and direction must
// be editable per route).
//
// The built-in routes live in code (const popularRoutes in
// fares_tab.dart), so an admin edit cannot rewrite them. Instead
// the edit is stored as an override record in Firestore collection
// `route_fare_overrides`, keyed by the route's From|To pair (the
// same key convention as map_tab's knownBusFares table). The Fares
// tab merges overrides onto the built-in list at load time; a
// missing field means "use the built-in value", so nothing is ever
// invented and an unset fare stays "Fare not set" until the admin
// sets it.
//
// A separate collection (not custom_routes): custom_routes docs are
// whole admin-added routes, while an override is a partial patch
// (fare / student fare / via stops, each optional) on a built-in
// route. Same admin enforcement as custom_routes (repository-side
// allowlist check; Firestore rules follow the custom_routes
// pattern — rules are Steven's to publish in Console, never
// written here).
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_access.dart';
import 'bus_stops.dart';
import 'onboarding/auth_service.dart';

/// Firestore collection for seeded-route fare/direction overrides.
const routeFareOverridesCollection = 'route_fare_overrides';

/// SharedPreferences key for the local overrides cache.
const routeFareOverridesCacheKey = 'route_fare_overrides_cache_v1';

/// Bumped after every successful override mutation (save /
/// delete), so the Fares tab reloads its overrides without a
/// restart — e.g. after the Map tab's line maker saves a drawn
/// line. Reads never bump.
final routeFareOverridesChanged = ValueNotifier<int>(0);

/// Stable key for a built-in route: its From|To pair (the same
/// convention as map_tab's knownBusFares table). The seven built-in
/// routes all have distinct From|To pairs.
String seededRouteKey(String from, String to) => '$from|$to';

/// One admin override on a built-in route. Every value field is
/// optional: null means "not overridden — use the built-in value".
class RouteFareOverride {
  const RouteFareOverride({
    required this.routeKey,
    this.fare,
    this.studentFare,
    this.pwdFare,
    this.seniorFare,
    this.viaHubs,
    this.viaWaypoints,
    this.authorUid = '',
    this.authorEmail = '',
    this.updatedAt,
  });

  /// The route this overrides, from [seededRouteKey].
  final String routeKey;

  /// Regular fare in pesos, or null to keep the built-in fare
  /// (which may itself be unset — "Fare not set").
  final double? fare;

  /// Student fare in pesos, or null to derive 20% off the
  /// (effective) regular fare.
  final double? studentFare;

  /// PWD fare in pesos, or null to derive 20% off the
  /// (effective) regular fare. Same pattern as [studentFare].
  final double? pwdFare;

  /// Senior Citizen fare in pesos, or null to derive 20% off
  /// the (effective) regular fare. Same pattern as [studentFare].
  final double? seniorFare;

  /// Ordered via-stops replacing the built-in route's own
  /// (built-in routes have none), or null to keep them.
  final List<String>? viaHubs;

  /// Ordered waypoints of a line the admin drew on the map
  /// (line maker), replacing [viaHubs] for the line when
  /// non-empty — or null to keep the named via stops.
  final List<RouteWaypoint>? viaWaypoints;

  /// Stamped from the authenticated admin, never from form input.
  final String authorUid;
  final String authorEmail;
  final DateTime? updatedAt;

  RouteFareOverride copyWith({
    String? routeKey,
    double? fare,
    double? studentFare,
    double? pwdFare,
    double? seniorFare,
    List<String>? viaHubs,
    List<RouteWaypoint>? viaWaypoints,
    String? authorUid,
    String? authorEmail,
    DateTime? updatedAt,
  }) {
    return RouteFareOverride(
      routeKey: routeKey ?? this.routeKey,
      fare: fare ?? this.fare,
      studentFare: studentFare ?? this.studentFare,
      pwdFare: pwdFare ?? this.pwdFare,
      seniorFare: seniorFare ?? this.seniorFare,
      viaHubs: viaHubs ?? this.viaHubs,
      viaWaypoints: viaWaypoints ?? this.viaWaypoints,
      authorUid: authorUid ?? this.authorUid,
      authorEmail: authorEmail ?? this.authorEmail,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'routeKey': routeKey,
    if (fare != null) 'fare': fare,
    if (studentFare != null) 'studentFare': studentFare,
    if (pwdFare != null) 'pwdFare': pwdFare,
    if (seniorFare != null) 'seniorFare': seniorFare,
    if (viaHubs != null && viaHubs!.isNotEmpty) 'viaHubs': viaHubs,
    if (viaWaypoints != null && viaWaypoints!.isNotEmpty)
      'viaWaypoints': viaWaypoints!.map((w) => w.toJson()).toList(),
    if (authorUid.isNotEmpty) 'authorUid': authorUid,
    if (authorEmail.isNotEmpty) 'authorEmail': authorEmail,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  static RouteFareOverride fromJson(
    String routeKey,
    Map<String, dynamic> data,
  ) {
    final via = data['viaHubs'];
    final waypoints = data['viaWaypoints'];
    // Cached JSON carries the key inside the map; Firestore docs
    // carry it as the document id. Either source wins over ''.
    final storedKey = data['routeKey'] is String
        ? data['routeKey'] as String
        : '';
    return RouteFareOverride(
      routeKey: routeKey.isNotEmpty ? routeKey : storedKey,
      fare: data['fare'] is num ? (data['fare'] as num).toDouble() : null,
      studentFare: data['studentFare'] is num
          ? (data['studentFare'] as num).toDouble()
          : null,
      pwdFare: data['pwdFare'] is num
          ? (data['pwdFare'] as num).toDouble()
          : null,
      seniorFare: data['seniorFare'] is num
          ? (data['seniorFare'] as num).toDouble()
          : null,
      viaHubs: via is List ? via.whereType<String>().toList() : null,
      viaWaypoints: waypoints is List
          ? waypoints
                .map(RouteWaypoint.fromJson)
                .whereType<RouteWaypoint>()
                .toList()
          : null,
      authorUid: data['authorUid'] is String ? data['authorUid'] : '',
      authorEmail: data['authorEmail'] is String ? data['authorEmail'] : '',
      updatedAt: data['updatedAt'] is String
          ? DateTime.tryParse(data['updatedAt'] as String)
          : null,
    );
  }
}

/// Parses an optional fare field: blank = no value (null),
/// otherwise a number > 0. Returns (value, error) — error is null
/// on success. Never throws.
(double?, String?) parseOptionalFare(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return (null, null);
  final value = double.tryParse(trimmed);
  if (value == null) {
    return (null, 'Enter the fare in pesos (numbers only).');
  }
  if (value <= 0) return (null, 'The fare must be more than ₱0.');
  return (value, null);
}

/// Validates an override object itself. Returns the first problem,
/// or null when it may be saved. A null fare / student fare /
/// PWD fare / Senior Citizen fare is always fine (it means "not
/// overridden").
String? validateRouteFareOverride(RouteFareOverride override) {
  if (override.routeKey.isEmpty) return 'Missing route.';
  if (override.fare != null && override.fare! <= 0) {
    return 'The fare must be more than ₱0.';
  }
  if (override.studentFare != null && override.studentFare! <= 0) {
    return 'The student fare must be more than ₱0.';
  }
  if (override.pwdFare != null && override.pwdFare! <= 0) {
    return 'The PWD fare must be more than ₱0.';
  }
  if (override.seniorFare != null && override.seniorFare! <= 0) {
    return 'The Senior Citizen fare must be more than ₱0.';
  }
  return null;
}

/// True when the override carries no value at all — saving it
/// would be a no-op, so the caller deletes the stored override
/// instead (the route resets to its built-in values).
bool routeFareOverrideIsEmpty(RouteFareOverride override) {
  return override.fare == null &&
      override.studentFare == null &&
      override.pwdFare == null &&
      override.seniorFare == null &&
      (override.viaHubs == null || override.viaHubs!.isEmpty) &&
      (override.viaWaypoints == null || override.viaWaypoints!.isEmpty);
}

/// Seeded-route override storage. Mutations enforce the admin
/// allowlist here — a caller that forgets the UI gate still cannot
/// write.
abstract class RouteFareOverrideRepository {
  /// All overrides, keyed by route key. Reads never throw: a
  /// Firestore failure returns the local cache (possibly empty).
  Future<Map<String, RouteFareOverride>> loadAll();

  /// Creates or replaces the override for its route as [author].
  /// Throws [StateError] unless the author is an admin;
  /// throws [ArgumentError] on invalid input.
  Future<RouteFareOverride> save(
    RouteFareOverride override,
    AuthUser author,
  );

  /// Deletes the override for [routeKey] as [author] (a no-op
  /// when none exists). Throws [StateError] unless admin.
  Future<void> delete(String routeKey, AuthUser author);
}

/// Firestore implementation with a SharedPreferences cache fallback.
class FirestoreRouteFareOverrideRepository
    implements RouteFareOverrideRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection(routeFareOverridesCollection);

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> _writeCache(Map<String, RouteFareOverride> overrides) async {
    final prefs = await _prefs;
    final jsonList = overrides.values.map((o) => o.toJson()).toList();
    await prefs.setString(routeFareOverridesCacheKey, jsonEncode(jsonList));
  }

  Future<Map<String, RouteFareOverride>> _readCache() async {
    final prefs = await _prefs;
    final raw = prefs.getString(routeFareOverridesCacheKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      final out = <String, RouteFareOverride>{};
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final override = RouteFareOverride.fromJson('', item);
          if (override.routeKey.isNotEmpty) {
            out[override.routeKey] = override;
          }
        }
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<Map<String, RouteFareOverride>> loadAll() async {
    try {
      final snap = await _collection.get();
      final out = <String, RouteFareOverride>{};
      for (final doc in snap.docs) {
        out[doc.id] = RouteFareOverride.fromJson(doc.id, doc.data());
      }
      await _writeCache(out);
      return out;
    } catch (_) {
      // Offline / Firestore unavailable: the local cache is the
      // honest fallback, never an invented list.
      return _readCache();
    }
  }

  @override
  Future<RouteFareOverride> save(
    RouteFareOverride override,
    AuthUser author,
  ) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can edit route fares.');
    }
    final error = validateRouteFareOverride(override);
    if (error != null) throw ArgumentError(error);
    final stamped = override.copyWith(
      authorUid: author.uid,
      authorEmail: author.email,
    );
    // Full replace (no merge): toJson omits null fields, so a
    // merge would leave a previously-set student fare behind when
    // the admin clears it back to "derive 20% off".
    await _collection.doc(override.routeKey).set({
      ...stamped.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final current = await loadAll();
    final saved = current[override.routeKey] ?? stamped;
    if (!current.containsKey(override.routeKey)) {
      await _writeCache({...current, override.routeKey: stamped});
    }
    routeFareOverridesChanged.value++;
    return saved;
  }

  @override
  Future<void> delete(String routeKey, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can edit route fares.');
    }
    await _collection.doc(routeKey).delete();
    final current = await loadAll();
    final next = Map<String, RouteFareOverride>.of(current)
      ..remove(routeKey);
    await _writeCache(next);
    routeFareOverridesChanged.value++;
  }
}

/// SharedPreferences-only implementation, used when Firebase is not
/// configured. Same admin enforcement; overrides stay on this device.
class LocalRouteFareOverrideRepository
    implements RouteFareOverrideRepository {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<Map<String, RouteFareOverride>> _readAll() async {
    final prefs = await _prefs;
    final raw = prefs.getString(routeFareOverridesCacheKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      final out = <String, RouteFareOverride>{};
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final override = RouteFareOverride.fromJson('', item);
          if (override.routeKey.isNotEmpty) {
            out[override.routeKey] = override;
          }
        } else if (item is Map) {
          final override = RouteFareOverride.fromJson(
            '',
            Map<String, dynamic>.from(item),
          );
          if (override.routeKey.isNotEmpty) {
            out[override.routeKey] = override;
          }
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeAll(Map<String, RouteFareOverride> overrides) async {
    final prefs = await _prefs;
    await prefs.setString(
      routeFareOverridesCacheKey,
      jsonEncode(overrides.values.map((o) => o.toJson()).toList()),
    );
  }

  @override
  Future<Map<String, RouteFareOverride>> loadAll() => _readAll();

  @override
  Future<RouteFareOverride> save(
    RouteFareOverride override,
    AuthUser author,
  ) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can edit route fares.');
    }
    final error = validateRouteFareOverride(override);
    if (error != null) throw ArgumentError(error);
    final stamped = override.copyWith(
      authorUid: author.uid,
      authorEmail: author.email,
      updatedAt: DateTime.now(),
    );
    final current = await _readAll();
    current[override.routeKey] = stamped;
    await _writeAll(current);
    routeFareOverridesChanged.value++;
    return stamped;
  }

  @override
  Future<void> delete(String routeKey, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can edit route fares.');
    }
    final current = await _readAll();
    current.remove(routeKey);
    await _writeAll(current);
    routeFareOverridesChanged.value++;
  }
}
