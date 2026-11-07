// Admin-added bus companies / operators (Nov 7, 2026 —
// Steven: "maglagay ka nh sa admin access, Add Transportation
// Bus. Kasi madami Bus dito samin ibat ibat bus company").
//
// The Add Route sheet shipped with 12 fixed operator presets
// (customRouteOperatorPresets in custom_routes.dart). There are
// more bus companies in Steven's area than that list holds, so
// an admin can now add a company by name; it is stored in
// Firestore collection `bus_companies` (admin-only writes,
// signed-in reads) with a SharedPreferences cache, and then
// appears as an operator chip in the Add / Edit Route sheet for
// all admins. The operator stays a plain string — a custom
// company flows through the existing CustomRoute.operator save
// path unchanged — and a company exists only because an admin
// added it (never invented).
//
// Names are deduplicated case-insensitively (trimmed): adding a
// name that already exists — a preset or a saved company —
// returns the existing company instead of a second entry.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_access.dart';
import 'custom_routes.dart';
import 'onboarding/auth_service.dart';

/// Firestore collection for admin-added bus companies.
const busCompaniesCollection = 'bus_companies';

/// SharedPreferences key for the local bus-companies cache.
const busCompaniesCacheKey = 'bus_companies_cache_v1';

/// One admin-added bus company (transportation provider).
class BusCompany {
  const BusCompany({
    this.id,
    required this.name,
    this.authorUid = '',
    this.authorEmail = '',
    this.createdAt,
    this.updatedAt,
  });

  /// Firestore document id (null until saved).
  final String? id;

  /// Company name as typed by the admin, e.g. 'Farinas Transit'.
  final String name;

  /// Stamped from the authenticated admin, never from form input.
  final String authorUid;
  final String authorEmail;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  BusCompany copyWith({
    String? id,
    String? name,
    String? authorUid,
    String? authorEmail,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BusCompany(
      id: id ?? this.id,
      name: name ?? this.name,
      authorUid: authorUid ?? this.authorUid,
      authorEmail: authorEmail ?? this.authorEmail,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    if (authorUid.isNotEmpty) 'authorUid': authorUid,
    if (authorEmail.isNotEmpty) 'authorEmail': authorEmail,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  static BusCompany fromJson(String id, Map<String, dynamic> data) {
    final storedId = data['id'] is String ? data['id'] as String : '';
    return BusCompany(
      id: id.isNotEmpty ? id : storedId,
      name: data['name'] is String ? data['name'] as String : '',
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

/// All operator chips the sheet may offer: the 12 built-in
/// presets first, then the admin-added companies in creation
/// order. A custom company that duplicates a preset
/// (case-insensitive) is dropped — the preset already covers it.
List<String> allOperators(List<BusCompany> companies) {
  final out = List<String>.of(customRouteOperatorPresets);
  for (final company in companies) {
    final name = company.name.trim();
    if (name.isEmpty) continue;
    final lower = name.toLowerCase();
    if (out.any((o) => o.toLowerCase() == lower)) continue;
    out.add(name);
  }
  return out;
}

/// Validates a company name. Returns the first problem, or null
/// when the name may be saved.
String? validateBusCompany(
  String name, {
  List<BusCompany> existingCompanies = const [],
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Enter the company name.';
  if (trimmed.length > 100) {
    return 'The name must be 100 characters or fewer.';
  }
  final lower = trimmed.toLowerCase();
  if (customRouteOperatorPresets.any(
    (p) => p.toLowerCase() == lower,
  )) {
    return 'That company is already in the list.';
  }
  if (existingCompanies.any(
    (c) => c.name.trim().toLowerCase() == lower,
  )) {
    return 'That company is already in the list.';
  }
  return null;
}

/// Admin-added bus-company storage. Mutations enforce the admin
/// allowlist here — a caller that forgets the UI gate still
/// cannot write.
abstract class BusCompanyRepository {
  /// All admin-added companies, oldest first. Reads never throw:
  /// a Firestore failure returns the local cache (possibly
  /// empty).
  Future<List<BusCompany>> loadAll();

  /// Creates a company as [author]. Throws [StateError] unless
  /// the author is an admin; throws [ArgumentError] on invalid
  /// input. Adding a name that already exists returns the
  /// existing company instead of a second entry (no duplicate
  /// doc is ever written).
  Future<BusCompany> create(BusCompany company, AuthUser author);

  /// Deletes a company as [author]. Throws [StateError] unless
  /// admin. Routes that already use the name keep working — the
  /// operator is a plain string on the route, not a reference.
  Future<void> delete(BusCompany company, AuthUser author);
}

/// Firestore implementation with a SharedPreferences cache fallback.
class FirestoreBusCompanyRepository implements BusCompanyRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection(busCompaniesCollection);

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> _writeCache(List<BusCompany> companies) async {
    final prefs = await _prefs;
    final jsonList = companies.map((c) => c.toJson()).toList();
    await prefs.setString(busCompaniesCacheKey, jsonEncode(jsonList));
  }

  Future<List<BusCompany>> _readCache() async {
    final prefs = await _prefs;
    final raw = prefs.getString(busCompaniesCacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((m) => BusCompany.fromJson('', m))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<BusCompany>> loadAll() async {
    try {
      final snap = await _collection.orderBy('createdAt').get();
      final companies = snap.docs
          .map((d) => BusCompany.fromJson(d.id, d.data()))
          .toList();
      await _writeCache(companies);
      return companies;
    } catch (_) {
      // Offline / Firestore unavailable: the local cache is the
      // honest fallback, never an invented list.
      return _readCache();
    }
  }

  @override
  Future<BusCompany> create(BusCompany company, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can add bus companies.');
    }
    final current = await loadAll();
    // A duplicate (preset or saved) is not an error here — the
    // sheet already guards it, and the repository returns the
    // existing company so no second doc is ever written.
    final lower = company.name.trim().toLowerCase();
    for (final preset in customRouteOperatorPresets) {
      if (preset.toLowerCase() == lower) {
        return BusCompany(name: preset);
      }
    }
    for (final existing in current) {
      if (existing.name.trim().toLowerCase() == lower) return existing;
    }
    final error = validateBusCompany(
      company.name,
      existingCompanies: current,
    );
    if (error != null) throw ArgumentError(error);
    final ref = await _collection.add({
      ...company
          .copyWith(authorUid: author.uid, authorEmail: author.email)
          .toJson(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final snap = await ref.get();
    final data = snap.data();
    final created = BusCompany.fromJson(ref.id, data ?? company.toJson())
        .copyWith(authorUid: author.uid, authorEmail: author.email);
    if (current.every((c) => c.id != ref.id)) {
      await _writeCache([...current, created]);
    }
    return created;
  }

  @override
  Future<void> delete(BusCompany company, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can delete bus companies.');
    }
    final id = company.id;
    if (id == null || id.isEmpty) {
      throw StateError('Cannot delete a bus company that was never saved.');
    }
    await _collection.doc(id).delete();
    final current = await loadAll();
    await _writeCache(current.where((c) => c.id != id).toList());
  }
}

/// SharedPreferences-only implementation, used when Firebase is not
/// configured. Same admin enforcement; companies stay on this device.
class LocalBusCompanyRepository implements BusCompanyRepository {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<BusCompany>> _readAll() async {
    final prefs = await _prefs;
    final raw = prefs.getString(busCompaniesCacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final companies = <BusCompany>[];
      for (final item in decoded) {
        // Pass '' so fromJson uses the id stored inside the map —
        // a positional id here would orphan every saved company
        // on the next read (delete would never find it again).
        if (item is Map<String, dynamic>) {
          companies.add(BusCompany.fromJson('', item));
        } else if (item is Map) {
          companies.add(
            BusCompany.fromJson('', Map<String, dynamic>.from(item)),
          );
        }
      }
      return companies;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeAll(List<BusCompany> companies) async {
    final prefs = await _prefs;
    await prefs.setString(
      busCompaniesCacheKey,
      jsonEncode(companies.map((c) => c.toJson()).toList()),
    );
  }

  @override
  Future<List<BusCompany>> loadAll() => _readAll();

  @override
  Future<BusCompany> create(BusCompany company, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can add bus companies.');
    }
    final current = await _readAll();
    final lower = company.name.trim().toLowerCase();
    for (final preset in customRouteOperatorPresets) {
      if (preset.toLowerCase() == lower) {
        return BusCompany(name: preset);
      }
    }
    for (final existing in current) {
      if (existing.name.trim().toLowerCase() == lower) return existing;
    }
    final error = validateBusCompany(
      company.name,
      existingCompanies: current,
    );
    if (error != null) throw ArgumentError(error);
    final now = DateTime.now();
    final created = company.copyWith(
      id: 'local-${now.microsecondsSinceEpoch}',
      authorUid: author.uid,
      authorEmail: author.email,
      createdAt: now,
      updatedAt: now,
    );
    await _writeAll([...current, created]);
    return created;
  }

  @override
  Future<void> delete(BusCompany company, AuthUser author) async {
    if (!isAdminUser(author)) {
      throw StateError('Only admins can delete bus companies.');
    }
    final id = company.id;
    if (id == null || id.isEmpty) {
      throw StateError('Cannot delete a bus company that was never saved.');
    }
    final current = await _readAll();
    await _writeAll(current.where((c) => c.id != id).toList());
  }
}
