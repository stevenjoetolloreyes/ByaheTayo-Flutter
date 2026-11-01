// On-device friend data for the Friends tab.
//
// HONESTY RULES (this app has NO social backend):
// - The friend code is REAL: a UUID v4 generated once on this device
//   and persisted. It is the device owner's code, not a server-issued
//   identity, and the UI never claims otherwise.
// - The friends list is REAL local data only: it starts empty and is
//   only ever filled with entries that were actually stored. Nothing
//   is seeded, and no friend is ever fabricated from a typed code.
// - Friend requests and chats cannot arrive without a backend, so they
//   have NO storage and NO fake entries — the tab shows empty states.
//
// ADDITIVE ONLY: both keys below are new. No existing
// SharedPreferences key is read with a new meaning or overwritten.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// This device's own friend code (a UUID v4 string).
const friendCodeKey = 'byahetayo_friend_code';

/// JSON list of locally stored friends.
const friendsListKey = 'byahetayo_friends';

/// One locally stored friend. Only a name is required; a code is kept
/// when one was actually stored with the entry.
class FriendEntry {
  const FriendEntry({required this.name, this.code});

  final String name;
  final String? code;

  /// Honest initials placeholder (never a fake photo).
  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  Map<String, dynamic> toJson() => {'name': name, 'code': code};

  static FriendEntry? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) return null;
    return FriendEntry(name: name, code: json['code'] as String?);
  }
}

class FriendStore {
  FriendStore(this._prefs);

  final SharedPreferences _prefs;

  /// Returns the stored code, generating and persisting a fresh UUID
  /// v4 on first call. [generate] is injectable so tests can use a
  /// deterministic code.
  Future<String> loadOrCreateFriendCode({String Function()? generate}) async {
    final existing = _prefs.getString(friendCodeKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final code = generate?.call() ?? const Uuid().v4();
    await _prefs.setString(friendCodeKey, code);
    return code;
  }

  String? get friendCode => _prefs.getString(friendCodeKey);

  List<FriendEntry> loadFriends() {
    final raw = _prefs.getString(friendsListKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(FriendEntry.fromJson)
          .whereType<FriendEntry>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveFriends(List<FriendEntry> friends) =>
      _prefs.setString(
        friendsListKey,
        jsonEncode(friends.map((f) => f.toJson()).toList()),
      );
}
