// Hidden (removed) built-in routes (Nov 8, 2026 — Steven: "sana
// meron remove routes" in the list).
//
// The built-in routes live in code (const popularRoutes in
// fares_tab.dart), so they can never be hard-deleted. A remove is
// stored as a hidden-route record in Firestore collection
// `hidden_routes`, keyed by the route's From|To pair
// ([seededRouteKey]). The Fares tab skips hidden routes when it
// builds Popular Routes; restoring deletes the record and the
// route comes back — with any fare/direction override intact,
// because hiding never touches the override.
//
// Same admin enforcement as route_fare_overrides (repository-side
// allowlist check; Firestore rules follow the same pattern —
// rules are Steven's to publish in Console, never written here).
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_access.dart';
import 'onboarding/auth_service.dart';
import 'route_fare_overrides.dart';

/// Firestore collection for hidden built-in routes.
const hiddenRoutesCollection = 'hidden_routes';

/// SharedPreferences key for the local hidden-routes cache.
const hiddenRoutesCacheKey = 'hidden_routes_cache_v1';

/// Bumped after every successful hide / unhide, so the Fares tab
/// reloads its route list without a restart. Reads never bump.
final hiddenRoutesChanged = ValueNotifier<int>(0);

/// One hidden built-in route. The record carries only the route
/// key plus who hid it — the route itself (From/To, vehicle,
/// operator) still lives in code, so restoring needs nothing
/// more than deleting this record.
class HiddenRoute {
  const HiddenRoute({
    required this.routeKey,
    this.authorUid = '',
    this.authorEmail = '',
    this.updatedAt,
  });

  /// The hidden route, from [seededRouteKey] ('From|To').
  final String routeKey;

  /// Stamped from the authenticated admin, never from form input.
  final String authorUid;
  final String authorEmail;
  final DateTime? updatedAt;

  HiddenRoute copyWith({
    String? routeKey,
    String? authorUid,
    String? authorEmail,
    DateTime? updatedAt,
  }) {
    return HiddenRoute(
      routeKey: routeKey ?? this.routeKey,
      authorUid: authorUid ?? this.authorUid,
      authorEmail: authorEmail ?? this.authorEmail,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'routeKey': routeKey,
    if (authorUid.isNotEmpty) 'authorUid': authorUid,
    if (authorEmail.isNotEmpty) 'authorEmail': authorEmail,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  static HiddenRoute fromJson(String routeKey, Map<String, dynamic> data) {
    // Cached JSON carries the key inside the map; Firestore docs
    // carry it as the document id. Either source wins over ''.
    final storedKey = data['routeKey'] is String
        ? data['routeKey'] as String
        : '';
    return HiddenRoute(
      routeKey: routeKey.isNotEmpty ? routeKey : storedKey,
      authorUid: data['authorUid'] is String ? data['authorUid'] : '',
      authorEmail: data['authorEmail'] is String
          ? data['authorEmail'] as String
          : '',
      updatedAt: data['updatedAt'] is String
          ? DateTime.tryParse(data['updatedAt'] as String)
          : null,
    );
  }
}

/// Validates a hidden-route key. Returns the first problem, or
/// null when it may be hidden.
String? validateHiddenRouteKey(String routeKey) {
  if (routeKey.isEmpty) return 'Missing route.';
  return null;
}

/// Hidden built-in route storage. Mutations enforce the admin
/// allowlist here — a caller that forgets the UI gate still cannot
/// write.
abstract class HiddenRouteRepository {
  /// Keys of the hidden built-in routes. Reads never throw: a
  /// Firestore failure returns the local cache (possibly empty).
  Future<Set<String>> loadAll();

  /// Hides the built-in route [routeKey] as [author]. Throws
  /// [StateError] unless the author is an admin; throws
  /// [ArgumentError] on an empty key. Hiding an already-hidden
  /// route is a no-op.
  Future<void> hide(String routeKey, AuthUser author);

  /// Restores the built-in route [routeKey] as [author] (a no-op
  /// when it is not hidden). Throws [StateError] unless admin.
  Future<void> unhide(String routeKey, AuthUser author);
}

/// Firestore implementation with a SharedPreferences cache fallback.
class FirestoreHiddenRouteRepository implements HiddenRouteRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection(hiddenRoutesCollection);

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> _writeCache(List<HiddenRoute> hidden) async {
    final prefs = await _prefs;
    final jsonList = hidden.map((h) => h.toJson()).toList();
    await prefs.setString(hiddenRoutesCacheKey, jsonEncode(jsonList));
  }

  Future<List<HiddenRoute>> _readCache() async {
    final prefs = await _prefs;
    final raw = prefs.getString(hiddenRoutesCacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <HiddenRoute>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final hidden = HiddenRoute.fromJson('', item);
          if (hidden.routeKey.isNotEmpty) out.add(hidden);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<Set<String>> loadAll() async {
    try {
      final snap = await _collection.get();
      final hidden = snap.docs
          .map((d) => HiddenRoute.fromJson(d.id, d.data()))
          .toList();
      await _writeCache(hidden);
      return hidden.map((h) => h.routeKey).toSet();
    } catch (_) {
      // Offline / Firestore unavailable: the local cache is the
      // honest fallback, never an invented list.
      final cached = await _readCache();
      return cached.map((h) => h.routeKey).toSet();
    }
  }

  @override
  Future<void> hide(String routeKey, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can remove routes.');
    }
    final error = validateHiddenRouteKey(routeKey);
    if (error != null) throw ArgumentError(error);
    await _collection.doc(routeKey).set({
      ...HiddenRoute(routeKey: routeKey).copyWith(
        authorUid: author.uid,
        authorEmail: author.email,
      ).toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await loadAll();
    hiddenRoutesChanged.value++;
  }

  @override
  Future<void> unhide(String routeKey, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can restore routes.');
    }
    await _collection.doc(routeKey).delete();
    await loadAll();
    hiddenRoutesChanged.value++;
  }
}

/// SharedPreferences-only implementation, used when Firebase is not
/// configured. Same admin enforcement; hidden routes stay on this
/// device.
class LocalHiddenRouteRepository implements HiddenRouteRepository {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<HiddenRoute>> _readAll() async {
    final prefs = await _prefs;
    final raw = prefs.getString(hiddenRoutesCacheKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <HiddenRoute>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final hidden = HiddenRoute.fromJson('', item);
          if (hidden.routeKey.isNotEmpty) out.add(hidden);
        } else if (item is Map) {
          final hidden = HiddenRoute.fromJson(
            '',
            Map<String, dynamic>.from(item),
          );
          if (hidden.routeKey.isNotEmpty) out.add(hidden);
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeAll(List<HiddenRoute> hidden) async {
    final prefs = await _prefs;
    await prefs.setString(
      hiddenRoutesCacheKey,
      jsonEncode(hidden.map((h) => h.toJson()).toList()),
    );
  }

  @override
  Future<Set<String>> loadAll() async {
    final hidden = await _readAll();
    return hidden.map((h) => h.routeKey).toSet();
  }

  @override
  Future<void> hide(String routeKey, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can remove routes.');
    }
    final error = validateHiddenRouteKey(routeKey);
    if (error != null) throw ArgumentError(error);
    final hidden = await _readAll();
    if (hidden.any((h) => h.routeKey == routeKey)) return;
    hidden.add(
      HiddenRoute(
        routeKey: routeKey,
        authorUid: author.uid,
        authorEmail: author.email,
        updatedAt: DateTime.now(),
      ),
    );
    await _writeAll(hidden);
    hiddenRoutesChanged.value++;
  }

  @override
  Future<void> unhide(String routeKey, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can restore routes.');
    }
    final hidden = await _readAll();
    hidden.removeWhere((h) => h.routeKey == routeKey);
    await _writeAll(hidden);
    hiddenRoutesChanged.value++;
  }
}
