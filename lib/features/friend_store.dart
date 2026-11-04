// On-device friend data for the Friends tab.
//
// HONESTY RULES:
// - The friend code is REAL: a short invite code (ESK-XXXXXX,
//   generated once on this device, see generateInviteCode) and
//   persisted. Older devices may still hold a UUID v4 code from
//   before the invite-code patch; that stored value is returned
//   unchanged until cloud sync migrates it (see
//   friend_cloud_repository.dart), and is never deleted here.
//   When cloud sync is available, the invite code is claimed once
//   as the user's cloud code; an established cloud code is
//   never overwritten, and on a (near-impossible) collision the
//   minted cloud code replaces the local one so the shown code is
//   always the code other devices can look up.
// - The friends list is REAL local data only: it starts empty and is
//   only ever filled with entries that were actually stored. Nothing
//   is seeded, and no friend is ever fabricated from a typed code.
//   Cloud friends (accepted requests only) are kept separate and are
//   never written into this local list.
// - Chats still have NO backend: the tab shows the honest empty
//   state, never fake conversations.
//
// ADDITIVE ONLY: the cloud-code key below is new. No existing
// SharedPreferences key is read with a new meaning or overwritten.
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Invite-code prefix. Every invite code is ESK- followed by six
/// uppercase alphanumeric characters, e.g. ESK-7K9P2X.
const inviteCodePrefix = 'ESK-';

/// Number of characters after the ESK- prefix.
const inviteCodeBodyLength = 6;

/// Alphabet for invite-code bodies: uppercase letters + digits.
/// Full A-Z0-9 (36 symbols); 36^6 combinations, so random
/// collisions are rare and the code-doc claim is the uniqueness
/// enforcement (see friend_cloud_repository.dart).
const _inviteCodeAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

/// Generates a fresh invite code, e.g. ESK-7K9P2X, using a
/// cryptographically secure random source. [random] is injectable
/// so tests can use a deterministic source.
String generateInviteCode({Random? random}) {
  final rng = random ?? Random.secure();
  final body = String.fromCharCodes(
    List.generate(
      inviteCodeBodyLength,
      (_) => _inviteCodeAlphabet.codeUnitAt(
        rng.nextInt(_inviteCodeAlphabet.length),
      ),
    ),
  );
  return '$inviteCodePrefix$body';
}

/// True only for the exact invite-code format: ESK- plus six
/// uppercase alphanumeric characters. UUIDs and any other stored
/// code return false — they are legacy codes, not invite codes.
bool isInviteCodeFormat(String code) {
  return RegExp(r'^ESK-[A-Z0-9]{6}$').hasMatch(code);
}

/// Normalizes a code a user typed for Add Friend. ESK codes are
/// uppercased, and a bare six-character body gains the ESK-
/// prefix, so 'esk-7k9p2x' and '7k9p2x' both become 'ESK-7K9P2X'.
/// Any other input (including legacy UUID codes, whose document
/// IDs are case-sensitive) is returned trimmed but otherwise
/// unchanged, so old codes keep working exactly as stored.
String normalizeInviteCode(String raw) {
  final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), '');
  final upper = cleaned.toUpperCase();
  if (RegExp(r'^ESK-[A-Z0-9]{6}$').hasMatch(upper)) return upper;
  if (RegExp(r'^[A-Z0-9]{6}$').hasMatch(upper)) {
    return '$inviteCodePrefix$upper';
  }
  return cleaned;
}

/// This device's own friend code. New codes are invite codes;
/// a stored legacy UUID code is returned unchanged (see above).
const friendCodeKey = 'byahetayo_friend_code';

/// JSON list of locally stored friends.
const friendsListKey = 'byahetayo_friends';

/// The cloud code established for this user, cached after the first
/// successful backfill (see friend_cloud_repository.dart). Kept
/// separate from [friendCodeKey] so the local code is never silently
/// replaced by a cloud value except through [saveFriendCode].
const cloudFriendCodeKey = 'byahetayo_cloud_friend_code';

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

  /// Returns the stored code, generating and persisting a fresh
  /// invite code (ESK-XXXXXX) on first call. [generate] is
  /// injectable so tests can use a deterministic code.
  Future<String> loadOrCreateFriendCode({String Function()? generate}) async {
    final existing = _prefs.getString(friendCodeKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final code = generate?.call() ?? generateInviteCode();
    await _prefs.setString(friendCodeKey, code);
    return code;
  }

  String? get friendCode => _prefs.getString(friendCodeKey);

  /// Overwrites the local code. Used only when cloud backfill mints
  /// a fresh code on collision, so the displayed code stays the code
  /// other devices can look up.
  Future<void> saveFriendCode(String code) =>
      _prefs.setString(friendCodeKey, code);

  String? get cloudFriendCode => _prefs.getString(cloudFriendCodeKey);

  Future<void> saveCloudFriendCode(String code) =>
      _prefs.setString(cloudFriendCodeKey, code);

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
