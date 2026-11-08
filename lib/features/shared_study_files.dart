// Shared study files (Nov 8, 2026 — Steven: share a file with a
// friend, user-to-user only).
//
// A study file is metadata-only (StudyFile: name, size, type,
// folder, added date — never file bytes), so a share is a metadata
// snapshot too: the file's metadata as it was when shared, plus
// who shared it and who it is for. There is no public link and no
// broadcast — a share names ONE recipient UID (a cloud friend, from
// an accepted friend request) and only the sender and that
// recipient can read it.
//
// Storage: Firestore collection `shared_study_files`, doc id is a
// uuid. The recipient's Study tab loads shares addressed to them
// (fetchSharedWithMe) and shows them under "Shared with me".
// Shares are immutable snapshots: no update is allowed (rules
// allow update: false) — rename the file and share it again
// instead. Deleting the file removes the sender's shares of it, so
// a share never points at a file that no longer exists.
//
// Same repository shape as route_fare_overrides (abstract +
// Firestore + Local, SharedPreferences cache fallback, change
// notifier). Single-field queries + client-side filters on purpose:
// no composite index is needed for these lookups.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'onboarding/auth_service.dart';

/// Firestore collection for user-to-user shared study files.
const sharedStudyFilesCollection = 'shared_study_files';

/// SharedPreferences key for the local shares cache.
const sharedStudyFilesCacheKey = 'shared_study_files_cache_v1';

/// Bumped after every successful share mutation (share / delete),
/// so the Study tab reloads its "Shared with me" list without a
/// restart. Reads never bump.
final sharedStudyFilesChanged = ValueNotifier<int>(0);

/// One study file shared with ONE friend: the file's metadata
/// snapshot plus the sender and recipient. The file itself is
/// never copied — StudyFile stores no bytes, so there is nothing
/// to copy.
class SharedStudyFile {
  const SharedStudyFile({
    required this.id,
    required this.fileId,
    required this.name,
    required this.sizeBytes,
    required this.kind,
    required this.folder,
    required this.added,
    required this.fromUid,
    required this.fromName,
    required this.toUid,
    required this.sharedAt,
  });

  /// Document id (uuid).
  final String id;

  /// The sender's StudyFile id the snapshot was taken from.
  final String fileId;

  /// Snapshot of the file's metadata at share time.
  final String name;
  final int sizeBytes;
  final String kind;
  final String folder;
  final DateTime added;

  /// Sender snapshot (stamped from the authenticated sender,
  /// never from form input).
  final String fromUid;
  final String fromName;

  /// The ONE recipient UID. A share is never public.
  final String toUid;

  final DateTime sharedAt;

  SharedStudyFile copyWith({
    String? id,
    String? fileId,
    String? name,
    int? sizeBytes,
    String? kind,
    String? folder,
    DateTime? added,
    String? fromUid,
    String? fromName,
    String? toUid,
    DateTime? sharedAt,
  }) {
    return SharedStudyFile(
      id: id ?? this.id,
      fileId: fileId ?? this.fileId,
      name: name ?? this.name,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      kind: kind ?? this.kind,
      folder: folder ?? this.folder,
      added: added ?? this.added,
      fromUid: fromUid ?? this.fromUid,
      fromName: fromName ?? this.fromName,
      toUid: toUid ?? this.toUid,
      sharedAt: sharedAt ?? this.sharedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileId': fileId,
        'name': name,
        'sizeBytes': sizeBytes,
        'kind': kind,
        'folder': folder,
        'added': added.toIso8601String(),
        'fromUid': fromUid,
        'fromName': fromName,
        'toUid': toUid,
        'sharedAt': sharedAt.toIso8601String(),
      };

  static SharedStudyFile fromJson(
    String id,
    Map<String, dynamic> data,
  ) {
    final storedId = data['id'] is String ? data['id'] as String : '';
    DateTime asDate(Object? value, DateTime fallback) {
      if (value is Timestamp) return value.toDate();
      if (value is String) {
        return DateTime.tryParse(value) ?? fallback;
      }
      return fallback;
    }

    return SharedStudyFile(
      id: id.isNotEmpty ? id : storedId,
      fileId: data['fileId'] as String? ?? '',
      name: data['name'] as String? ?? 'Untitled file',
      sizeBytes: (data['sizeBytes'] as num?)?.toInt() ?? 0,
      kind: data['kind'] as String? ?? 'other',
      folder: data['folder'] as String? ?? 'Lectures',
      added: asDate(data['added'], DateTime.fromMillisecondsSinceEpoch(0)),
      fromUid: data['fromUid'] as String? ?? '',
      fromName: data['fromName'] as String? ?? '',
      toUid: data['toUid'] as String? ?? '',
      sharedAt: asDate(
        data['sharedAt'],
        DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  }
}

/// Validates a share itself. Returns the first problem, or null
/// when it may be saved. Never throws.
String? validateSharedStudyFile(SharedStudyFile share) {
  if (share.id.isEmpty) return 'Missing share.';
  if (share.fileId.isEmpty) return 'Missing file.';
  if (share.name.trim().isEmpty) return 'Missing file name.';
  if (share.fromUid.isEmpty) return 'Missing sender.';
  if (share.toUid.isEmpty) return 'Choose a friend to share with.';
  if (share.fromUid == share.toUid) {
    return 'You cannot share a file with yourself.';
  }
  return null;
}

/// User-to-user shared-file storage. The sender is always the
/// author: a caller that forgets the UI gate still cannot share
/// as someone else.
abstract class SharedStudyFileRepository {
  /// Shares [share] as [author]. Throws [StateError] unless the
  /// author is the sender; throws [ArgumentError] on invalid
  /// input. Idempotent: sharing the same file to the same friend
  /// twice returns the existing share instead of a duplicate.
  Future<SharedStudyFile> share(
    SharedStudyFile share,
    AuthUser author,
  );

  /// Shares addressed to [uid], newest first. Reads never throw:
  /// a Firestore failure returns the local cache (possibly empty).
  Future<List<SharedStudyFile>> fetchSharedWithMe(String uid);

  /// Deletes the share [shareId] as [author] — the sender or the
  /// recipient. A no-op when it does not exist. Throws
  /// [StateError] for anyone else.
  Future<void> delete(String shareId, AuthUser author);

  /// Deletes every share of [fileId] sent by [author] (used when
  /// the file itself is deleted, so no share points at a file
  /// that no longer exists).
  Future<void> deleteSharesForFile(String fileId, AuthUser author);
}

/// Firestore implementation with a SharedPreferences cache fallback.
class FirestoreSharedStudyFileRepository
    implements SharedStudyFileRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection(sharedStudyFilesCollection);

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> _writeCache(List<SharedStudyFile> shares) async {
    final prefs = await _prefs;
    await prefs.setString(
      sharedStudyFilesCacheKey,
      jsonEncode(shares.map((s) => s.toJson()).toList()),
    );
  }

  Future<List<SharedStudyFile>> _readCache() async {
    final prefs = await _prefs;
    final raw = prefs.getString(sharedStudyFilesCacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((item) => SharedStudyFile.fromJson('', item))
          .where((s) => s.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<SharedStudyFile> _sortedNewestFirst(
    List<SharedStudyFile> shares,
  ) {
    final sorted = List<SharedStudyFile>.of(shares);
    sorted.sort((a, b) => b.sharedAt.compareTo(a.sharedAt));
    return sorted;
  }

  @override
  Future<SharedStudyFile> share(
    SharedStudyFile share,
    AuthUser author,
  ) async {
    if (author.uid != share.fromUid) {
      throw StateError('Only the sender can share a file.');
    }
    final error = validateSharedStudyFile(share);
    if (error != null) throw ArgumentError(error);
    // Idempotent: the same file to the same friend twice is one
    // share, never a duplicate document.
    final mine = await _collection
        .where('fromUid', isEqualTo: author.uid)
        .get();
    for (final doc in mine.docs) {
      final existing = SharedStudyFile.fromJson(doc.id, doc.data());
      if (existing.fileId == share.fileId &&
          existing.toUid == share.toUid) {
        return existing;
      }
    }
    await _collection.doc(share.id).set({
      ...share.toJson(),
      'sharedAt': FieldValue.serverTimestamp(),
    });
    sharedStudyFilesChanged.value++;
    return share;
  }

  @override
  Future<List<SharedStudyFile>> fetchSharedWithMe(String uid) async {
    try {
      final snap = await _collection.where('toUid', isEqualTo: uid).get();
      final shares = _sortedNewestFirst(
        snap.docs
            .map((doc) => SharedStudyFile.fromJson(doc.id, doc.data()))
            .toList(),
      );
      await _writeCache(shares);
      return shares;
    } catch (_) {
      // Offline / Firestore unavailable: the local cache is the
      // honest fallback, never an invented list.
      return _readCache();
    }
  }

  @override
  Future<void> delete(String shareId, AuthUser author) async {
    final doc = await _collection.doc(shareId).get();
    if (!doc.exists) return;
    final share = SharedStudyFile.fromJson(doc.id, doc.data() ?? {});
    if (author.uid != share.fromUid && author.uid != share.toUid) {
      throw StateError('Only the sender or the recipient can remove '
          'a shared file.');
    }
    await _collection.doc(shareId).delete();
    sharedStudyFilesChanged.value++;
  }

  @override
  Future<void> deleteSharesForFile(String fileId, AuthUser author) async {
    final mine = await _collection
        .where('fromUid', isEqualTo: author.uid)
        .get();
    var removed = false;
    for (final doc in mine.docs) {
      final share = SharedStudyFile.fromJson(doc.id, doc.data());
      if (share.fileId == fileId) {
        await _collection.doc(doc.id).delete();
        removed = true;
      }
    }
    if (removed) sharedStudyFilesChanged.value++;
  }
}

/// SharedPreferences-only implementation, used when Firebase is not
/// configured. Same sender enforcement; shares stay on this device
/// (without Firestore there are no cloud friends to share with, so
/// in practice no shares are created through this path).
class LocalSharedStudyFileRepository
    implements SharedStudyFileRepository {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<SharedStudyFile>> _readAll() async {
    final prefs = await _prefs;
    final raw = prefs.getString(sharedStudyFilesCacheKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((item) => SharedStudyFile.fromJson('', item))
          .where((s) => s.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeAll(List<SharedStudyFile> shares) async {
    final prefs = await _prefs;
    await prefs.setString(
      sharedStudyFilesCacheKey,
      jsonEncode(shares.map((s) => s.toJson()).toList()),
    );
  }

  @override
  Future<SharedStudyFile> share(
    SharedStudyFile share,
    AuthUser author,
  ) async {
    if (author.uid != share.fromUid) {
      throw StateError('Only the sender can share a file.');
    }
    final error = validateSharedStudyFile(share);
    if (error != null) throw ArgumentError(error);
    final current = await _readAll();
    for (final existing in current) {
      if (existing.fileId == share.fileId &&
          existing.toUid == share.toUid &&
          existing.fromUid == share.fromUid) {
        return existing;
      }
    }
    final stamped = share.copyWith(sharedAt: DateTime.now());
    current.add(stamped);
    await _writeAll(current);
    sharedStudyFilesChanged.value++;
    return stamped;
  }

  @override
  Future<List<SharedStudyFile>> fetchSharedWithMe(String uid) async {
    final all = await _readAll();
    final mine = all.where((s) => s.toUid == uid).toList();
    mine.sort((a, b) => b.sharedAt.compareTo(a.sharedAt));
    return mine;
  }

  @override
  Future<void> delete(String shareId, AuthUser author) async {
    final current = await _readAll();
    final index = current.indexWhere((s) => s.id == shareId);
    if (index < 0) return;
    final share = current[index];
    if (author.uid != share.fromUid && author.uid != share.toUid) {
      throw StateError('Only the sender or the recipient can remove '
          'a shared file.');
    }
    current.removeAt(index);
    await _writeAll(current);
    sharedStudyFilesChanged.value++;
  }

  @override
  Future<void> deleteSharesForFile(String fileId, AuthUser author) async {
    final current = await _readAll();
    final next = current
        .where((s) => !(s.fileId == fileId && s.fromUid == author.uid))
        .toList();
    if (next.length == current.length) return;
    await _writeAll(next);
    sharedStudyFilesChanged.value++;
  }
}

/// Generates a share document id. Injectable so tests can use a
/// deterministic id.
String newShareId({String Function()? generate}) =>
    generate?.call() ?? const Uuid().v4();
