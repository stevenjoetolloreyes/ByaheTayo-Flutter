// Admin-added bus stops + the route line maker's waypoints
// (Nov 7, 2026 — Steven: "Idagdag mo yung pag add ng bagong
// bus stop, line maker sa mapa", and "ako na mag guguhit line
// at mag aano bus stop" — the tools are his to use by hand).
//
// The app shipped with 16 fixed hubs (const hubs in
// fares_tab.dart). An admin can now place a NEW stop on the map
// and name it; the stop is stored in Firestore collection
// `bus_stops` (admin-only writes, signed-in reads) with a
// SharedPreferences cache, and then behaves exactly like a hub:
// it appears in the From/To pickers, the via-stops picker, and
// the map (as a stop pin), and it can be an endpoint or a via
// stop of a route. A stop exists only because an admin placed +
// named it — nothing is ever invented, and no stop is ever
// pre-placed for him.
//
// Names are the key: a stop's name is unique across hubs + stops
// (case-insensitive) and is never renamed after creation — routes
// reference stops by name, so renaming would orphan them. Only
// the region can be edited. Deletion is blocked while any custom
// route or override references the stop (the manage sheet checks
// that; the repository itself cannot see routes).
//
// A [RouteWaypoint] is one point of a drawn line: a raw map tap
// (name null) or a named hub/stop. The line maker stores the
// tapped waypoints, in tap order, as the active route's
// direction (see CustomRoute.viaWaypoints /
// RouteFareOverride.viaWaypoints) — the line is the admin's own
// drawing, never pre-drawn.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_access.dart';
import 'fares_tab.dart';
import 'onboarding/auth_service.dart';

/// Firestore collection for admin-added bus stops.
const busStopsCollection = 'bus_stops';

/// SharedPreferences key for the local bus-stops cache.
const busStopsCacheKey = 'bus_stops_cache_v1';

/// Bumped after every successful bus-stop mutation (create /
/// update / delete), so the Fares tab reloads its stop list
/// without a restart. Reads never bump.
final busStopsChanged = ValueNotifier<int>(0);

/// Request from another tab to open the Map tab's line maker:
/// `drawLine` = tap points in order to draw a route line;
/// `addStop` = tap once to place a new bus stop. Set by the
/// Fares tab (the Add Route sheet's "+ Add bus stop" chip);
/// consumed once by MapTab, which clears it. Lives here (not in
/// map_tab.dart) so fares_tab.dart can set it without importing
/// map_tab.dart.
final mapLineMakerRequest =
    ValueNotifier<({bool drawLine, bool addStop})?>(null);

/// One point of a drawn route line: a raw map tap ([name] null)
/// or a named hub / bus stop. The name is the display name in
/// "Stops along the way"; an unnamed point shows as "Point N".
class RouteWaypoint {
  const RouteWaypoint({this.name, required this.lat, required this.lng});

  /// Hub / bus-stop name, or null for a raw tapped point.
  final String? name;
  final double lat;
  final double lng;

  LatLng get point => LatLng(lat, lng);

  RouteWaypoint copyWith({String? name, double? lat, double? lng}) {
    return RouteWaypoint(
      name: name ?? this.name,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    if (name != null) 'name': name,
  };

  /// Null when the shape is unusable — a bad waypoint is
  /// skipped, never guessed.
  static RouteWaypoint? fromJson(dynamic data) {
    if (data is! Map) return null;
    final lat = data['lat'];
    final lng = data['lng'];
    if (lat is! num || lng is! num) return null;
    final name = data['name'];
    return RouteWaypoint(
      name: name is String && name.isNotEmpty ? name : null,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RouteWaypoint &&
      other.name == name &&
      other.lat == lat &&
      other.lng == lng;

  @override
  int get hashCode => Object.hash(name, lat, lng);
}

/// One admin-added bus stop.
class BusStop {
  const BusStop({
    this.id,
    required this.name,
    required this.region,
    required this.lat,
    required this.lng,
    this.authorUid = '',
    this.authorEmail = '',
    this.createdAt,
    this.updatedAt,
  });

  /// Firestore document id (null until saved).
  final String? id;

  /// Stop name, unique across hubs + stops (case-insensitive).
  /// Never renamed after creation — routes reference it by name.
  final String name;

  /// One of the regions in [hubRegions] — never invented.
  final String region;

  /// Placed by the admin tapping the map. Never typed in.
  final double lat;
  final double lng;

  /// Stamped from the authenticated admin, never from form input.
  final String authorUid;
  final String authorEmail;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  BusStop copyWith({
    String? id,
    String? name,
    String? region,
    double? lat,
    double? lng,
    String? authorUid,
    String? authorEmail,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BusStop(
      id: id ?? this.id,
      name: name ?? this.name,
      region: region ?? this.region,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      authorUid: authorUid ?? this.authorUid,
      authorEmail: authorEmail ?? this.authorEmail,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'region': region,
    'lat': lat,
    'lng': lng,
    if (authorUid.isNotEmpty) 'authorUid': authorUid,
    if (authorEmail.isNotEmpty) 'authorEmail': authorEmail,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  static BusStop fromJson(String id, Map<String, dynamic> data) {
    final storedId = data['id'] is String ? data['id'] as String : '';
    return BusStop(
      id: id.isNotEmpty ? id : storedId,
      name: data['name'] is String ? data['name'] as String : '',
      region: data['region'] is String ? data['region'] as String : '',
      lat: data['lat'] is num ? (data['lat'] as num).toDouble() : 0,
      lng: data['lng'] is num ? (data['lng'] as num).toDouble() : 0,
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

/// A bus stop as a [Hub] — admin stops behave exactly like hubs
/// everywhere a hub is used.
Hub busStopAsHub(BusStop stop) =>
    Hub(stop.name, stop.region, stop.lat, stop.lng);

/// Every place a picker can offer: the 16 built-in hubs first,
/// then the admin-added stops in creation order. Appended last
/// so the built-in hub indices never shift.
List<Hub> allHubs(List<BusStop> stops) =>
    [...hubs, ...stops.map(busStopAsHub)];

/// Hub by name, built-in first, then admin stops. Null when the
/// name is neither — never invented.
Hub? resolveHub(String name, List<BusStop> stops) {
  for (final hub in hubs) {
    if (hub.name == name) return hub;
  }
  for (final stop in stops) {
    if (stop.name == name) return busStopAsHub(stop);
  }
  return null;
}

/// The regions an admin may pick for a new stop: the distinct
/// regions of the built-in hubs, in first-seen order. No new
/// region string is ever invented.
List<String> hubRegions() {
  final seen = <String>{};
  final out = <String>[];
  for (final hub in hubs) {
    if (seen.add(hub.region)) out.add(hub.region);
  }
  return out;
}

/// True when [name] is already a hub or a bus stop
/// (case-insensitive, trimmed) — names must stay unique.
bool busStopNameTaken(String name, List<BusStop> stops) {
  final wanted = name.trim().toLowerCase();
  if (wanted.isEmpty) return false;
  for (final hub in hubs) {
    if (hub.name.toLowerCase() == wanted) return true;
  }
  for (final stop in stops) {
    if (stop.name.trim().toLowerCase() == wanted) return true;
  }
  return false;
}

/// Validates an Add Bus Stop form. Returns the first problem, or
/// null when the stop may be saved. Never invents a value: a
/// missing or invalid field blocks the save.
String? validateBusStop({
  required String name,
  required String region,
  required double lat,
  required double lng,
  List<BusStop> existingStops = const [],
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Enter a name for the bus stop.';
  if (trimmed.length > 100) {
    return 'The name must be 100 characters or fewer.';
  }
  if (trimmed.toLowerCase() == 'your location') {
    return 'That name is reserved for the GPS origin.';
  }
  if (!hubRegions().contains(region)) {
    return 'Choose a region.';
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return 'That point is not a valid place on the map.';
  }
  if (busStopNameTaken(trimmed, existingStops)) {
    return 'A stop with this name already exists.';
  }
  return null;
}

/// Admin-added bus-stop storage. Mutations enforce the admin
/// allowlist here — a caller that forgets the UI gate still
/// cannot write.
abstract class BusStopRepository {
  /// All admin-added stops, oldest first (creation order — the
  /// order they appear after the built-in hubs). Reads never
  /// throw: a Firestore failure returns the local cache
  /// (possibly empty).
  Future<List<BusStop>> loadAll();

  /// Creates a stop as [author]. Throws [StateError] unless the
  /// author is an admin; throws [ArgumentError] on invalid input
  /// (bad name / region / coordinates, or a duplicate name).
  Future<BusStop> create(BusStop stop, AuthUser author);

  /// Updates a stop's region as [author]. The name and the
  /// coordinates never change after creation (routes reference
  /// the name; the point was placed by hand). Throws
  /// [StateError] unless admin; [ArgumentError] on a rename
  /// attempt or a bad region.
  Future<BusStop> update(BusStop stop, AuthUser author);

  /// Deletes a stop as [author]. Throws [StateError] unless
  /// admin. The caller must check references first (see the
  /// manage sheet) — deleting a referenced stop orphans the
  /// routes that name it.
  Future<void> delete(BusStop stop, AuthUser author);
}

/// Validates a stop object itself (repository-side, same rules as
/// the form validator). [existingStops] must include the stops
/// already stored, so a duplicate name is caught.
String? validateBusStopObject(
  BusStop stop, {
  List<BusStop> existingStops = const [],
}) {
  return validateBusStop(
    name: stop.name,
    region: stop.region,
    lat: stop.lat,
    lng: stop.lng,
    existingStops: existingStops
        .where((s) => s.id != stop.id)
        .toList(),
  );
}

/// Firestore implementation with a SharedPreferences cache fallback.
class FirestoreBusStopRepository implements BusStopRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection(busStopsCollection);

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> _writeCache(List<BusStop> stops) async {
    final prefs = await _prefs;
    final jsonList = stops.map((s) => s.toJson()).toList();
    await prefs.setString(busStopsCacheKey, jsonEncode(jsonList));
  }

  Future<List<BusStop>> _readCache() async {
    final prefs = await _prefs;
    final raw = prefs.getString(busStopsCacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((m) => BusStop.fromJson('', m))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> _doc(BusStop stop, AuthUser author) {
    return {
      ...stop
          .copyWith(authorUid: author.uid, authorEmail: author.email)
          .toJson(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  @override
  Future<List<BusStop>> loadAll() async {
    try {
      final snap = await _collection
          .orderBy('createdAt')
          .get();
      final stops = snap.docs
          .map((d) => BusStop.fromJson(d.id, d.data()))
          .toList();
      await _writeCache(stops);
      return stops;
    } catch (_) {
      // Offline / Firestore unavailable: the local cache is the
      // honest fallback, never an invented list.
      return _readCache();
    }
  }

  @override
  Future<BusStop> create(BusStop stop, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can add bus stops.');
    }
    final current = await loadAll();
    final error = validateBusStopObject(stop, existingStops: current);
    if (error != null) throw ArgumentError(error);
    final ref = await _collection.add(_doc(stop, author));
    final snap = await ref.get();
    final data = snap.data();
    final created = BusStop.fromJson(ref.id, data ?? stop.toJson())
        .copyWith(authorUid: author.uid, authorEmail: author.email);
    if (current.every((s) => s.id != ref.id)) {
      await _writeCache([...current, created]);
    }
    busStopsChanged.value++;
    return created;
  }

  @override
  Future<BusStop> update(BusStop stop, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can edit bus stops.');
    }
    final id = stop.id;
    if (id == null || id.isEmpty) {
      throw StateError('Cannot update a bus stop that was never saved.');
    }
    final current = await loadAll();
    final stored = current.where((s) => s.id == id).firstOrNull;
    if (stored == null) {
      throw StateError('That bus stop no longer exists.');
    }
    if (stop.name != stored.name ||
        stop.lat != stored.lat ||
        stop.lng != stored.lng) {
      throw ArgumentError(
        'A bus stop name and location cannot be changed.',
      );
    }
    final error = validateBusStopObject(stop, existingStops: current);
    if (error != null) throw ArgumentError(error);
    await _collection.doc(id).update({
      'region': stop.region,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final updated = stop.copyWith(updatedAt: DateTime.now());
    await _writeCache(
      current.map((s) => s.id == id ? updated : s).toList(),
    );
    busStopsChanged.value++;
    return updated;
  }

  @override
  Future<void> delete(BusStop stop, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can delete bus stops.');
    }
    final id = stop.id;
    if (id == null || id.isEmpty) {
      throw StateError('Cannot delete a bus stop that was never saved.');
    }
    await _collection.doc(id).delete();
    final current = await loadAll();
    await _writeCache(current.where((s) => s.id != id).toList());
    busStopsChanged.value++;
  }
}

/// SharedPreferences-only implementation, used when Firebase is not
/// configured. Same admin enforcement; stops stay on this device.
class LocalBusStopRepository implements BusStopRepository {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<BusStop>> _readAll() async {
    final prefs = await _prefs;
    final raw = prefs.getString(busStopsCacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final stops = <BusStop>[];
      for (final item in decoded) {
        // Pass '' so fromJson uses the id stored inside the map —
        // a positional id here would orphan every saved stop on
        // the next read (update/delete would never find it again).
        if (item is Map<String, dynamic>) {
          stops.add(BusStop.fromJson('', item));
        } else if (item is Map) {
          stops.add(
            BusStop.fromJson('', Map<String, dynamic>.from(item)),
          );
        }
      }
      return stops;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeAll(List<BusStop> stops) async {
    final prefs = await _prefs;
    await prefs.setString(
      busStopsCacheKey,
      jsonEncode(stops.map((s) => s.toJson()).toList()),
    );
  }

  @override
  Future<List<BusStop>> loadAll() => _readAll();

  @override
  Future<BusStop> create(BusStop stop, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can add bus stops.');
    }
    final current = await _readAll();
    final error = validateBusStopObject(stop, existingStops: current);
    if (error != null) throw ArgumentError(error);
    final now = DateTime.now();
    final created = stop.copyWith(
      id: 'local-${now.microsecondsSinceEpoch}',
      authorUid: author.uid,
      authorEmail: author.email,
      createdAt: now,
      updatedAt: now,
    );
    await _writeAll([...current, created]);
    busStopsChanged.value++;
    return created;
  }

  @override
  Future<BusStop> update(BusStop stop, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can edit bus stops.');
    }
    final id = stop.id;
    if (id == null || id.isEmpty) {
      throw StateError('Cannot update a bus stop that was never saved.');
    }
    final current = await _readAll();
    final stored = current.where((s) => s.id == id).firstOrNull;
    if (stored == null) {
      throw StateError('That bus stop no longer exists.');
    }
    if (stop.name != stored.name ||
        stop.lat != stored.lat ||
        stop.lng != stored.lng) {
      throw ArgumentError(
        'A bus stop name and location cannot be changed.',
      );
    }
    final error = validateBusStopObject(stop, existingStops: current);
    if (error != null) throw ArgumentError(error);
    final updated = stop.copyWith(updatedAt: DateTime.now());
    await _writeAll(
      current.map((s) => s.id == id ? updated : s).toList(),
    );
    busStopsChanged.value++;
    return updated;
  }

  @override
  Future<void> delete(BusStop stop, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can delete bus stops.');
    }
    final id = stop.id;
    if (id == null || id.isEmpty) {
      throw StateError('Cannot delete a bus stop that was never saved.');
    }
    final current = await _readAll();
    await _writeAll(current.where((s) => s.id != id).toList());
    busStopsChanged.value++;
  }
}
