// Cloud friend codes + friend requests for the Friends tab.
//
// Collections:
// - friend_codes/{code}: {uid, code, createdAt}. The document ID IS
//   the code, so lookup is a get-only read — codes can never be
//   listed or enumerated. A code doc is created by its owner only,
//   and only the owner may change or delete it.
// - Invite codes are ESK-XXXXXX (see friend_store.dart). A user
//   whose mapping still points at a legacy UUID code is migrated
//   to an invite code by ensureInviteCode below: the mapping is
//   updated to the new code and the OLD code document is KEPT as
//   an alias (never deleted), so old QRs, shared codes, and
//   pending requests still resolve to the same UID. Friendships
//   are derived from friend_requests by UID, so they are intact
//   through a migration.
// - user_friend_codes/{uid}: {code, updatedAt}. Owner-only mapping
//   so a user can find their own cloud code on any device without
//   listing anyone else's code.
// - friend_requests/{id}: {from, to, fromName, toName, fromCode,
//   toCode, status, createdAt, updatedAt}. Status is 'pending' |
//   'accepted' | 'declined'. Only the recipient may answer a pending
//   request, and only its status may change.
//
// HONESTY: the cloud friends list is DERIVED from accepted requests
// only. Local friends (FriendEntry, no UID) are never promoted into
// cloud friendships — they stay local cache until a real
// request/accept happens for a real UID. No fake requests, chats,
// or presence are ever produced here.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'friend_store.dart';

/// Exact-code lookup collection: document ID == the friend code.
const friendCodesCollection = 'friend_codes';

/// Per-user code mapping collection: document ID == the user's UID.
const userFriendCodesCollection = 'user_friend_codes';

/// Friend request collection.
const friendRequestsCollection = 'friend_requests';

/// A friend request is waiting for the recipient's answer.
const requestStatusPending = 'pending';

/// A friend request the recipient accepted.
const requestStatusAccepted = 'accepted';

/// A friend request the recipient declined.
const requestStatusDeclined = 'declined';

/// What an exact-code lookup returns: the code owner's UID.
class CloudCodeLookup {
  const CloudCodeLookup({required this.uid, required this.code});

  final String uid;
  final String code;
}

/// One friend request. Names are snapshots taken when the request
/// was sent (the recipient's name is unknown at send time, so
/// [toName] is null until the recipient is known another way).
/// The UI falls back to the code when a name snapshot is missing.
class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.fromCode,
    required this.toCode,
    required this.status,
    this.fromName,
    this.toName,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String fromUid;
  final String toUid;
  final String fromCode;
  final String toCode;
  final String status;
  final String? fromName;
  final String? toName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Display name for one side of the request: the snapshot, or the
  /// code when no name was captured.
  String nameFor(bool isSenderSide) =>
      (isSenderSide ? fromName : toName) ??
      (isSenderSide ? fromCode : toCode);

  bool get isPending => status == requestStatusPending;
  bool get isAccepted => status == requestStatusAccepted;
  bool get isDeclined => status == requestStatusDeclined;

  static FriendRequest fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    DateTime? asDate(Object? value) =>
        value is Timestamp ? value.toDate() : null;
    return FriendRequest(
      id: doc.id,
      fromUid: data['from'] as String? ?? '',
      toUid: data['to'] as String? ?? '',
      fromCode: data['fromCode'] as String? ?? '',
      toCode: data['toCode'] as String? ?? '',
      status: data['status'] as String? ?? requestStatusPending,
      fromName: data['fromName'] as String?,
      toName: data['toName'] as String?,
      createdAt: asDate(data['createdAt']),
      updatedAt: asDate(data['updatedAt']),
    );
  }
}

/// One cloud friend: the counterpart of an accepted request.
class CloudFriend {
  const CloudFriend({
    required this.uid,
    required this.code,
    this.name,
  });

  final String uid;
  final String code;
  final String? name;

  /// Display name: the snapshot, or the code when none was captured.
  String get displayName =>
      (name != null && name!.trim().isNotEmpty) ? name! : code;
}

/// Cloud friend-code + request storage. The UI talks only through
/// this interface so widget tests can use a fake; production uses
/// [FirestoreFriendCloudRepository].
abstract class FriendCloudRepository {
  /// Returns this user's cloud code, claiming [localCode] exactly
  /// once when no cloud code exists yet. An existing cloud code is
  /// never overwritten — a later call with a different local code
  /// still returns the established cloud code. On a (near-impossible)
  /// local-code collision with another user, a fresh code is minted
  /// and returned instead.
  Future<String> ensureCloudCode({
    required String uid,
    required String localCode,
  });

  /// Returns this user's invite code (ESK-XXXXXX), claiming it
  /// exactly once. If the user's mapping already points at an
  /// invite code, that code is returned unchanged. If the mapping
  /// points at a legacy UUID code, a fresh invite code is claimed,
  /// the mapping is updated to it, and the old code document is
  /// KEPT as an alias (never deleted). If no mapping exists, a
  /// fresh invite code is claimed — or [localCode] is claimed when
  /// it is already an invite code and unclaimed. A collision with
  /// another user's code mints a new invite code; it NEVER falls
  /// back to a UUID.
  Future<String> ensureInviteCode({
    required String uid,
    String? localCode,
  });

  /// Exact-code lookup (get-only, never a list). Null when no code
  /// document with that ID exists.
  Future<CloudCodeLookup?> lookupCode(String code);

  /// Sends a pending request. Throws [ArgumentError] for a request
  /// to oneself and [StateError] when a pending request to the same
  /// user already exists.
  Future<FriendRequest> sendRequest({
    required String fromUid,
    required String? fromName,
    required String fromCode,
    required String toUid,
    required String toCode,
  });

  /// Requests sent to [uid], newest first.
  Future<List<FriendRequest>> fetchIncoming(String uid);

  /// Requests sent by [uid], newest first.
  Future<List<FriendRequest>> fetchOutgoing(String uid);

  /// Answers a pending request. Only the recipient ([uid] == the
  /// request's `to`) may answer, and only once. Throws [StateError]
  /// otherwise.
  Future<void> respondToRequest({
    required String requestId,
    required String uid,
    required bool accept,
  });

  /// Friends derived from accepted requests only, in both
  /// directions, deduplicated by UID.
  Future<List<CloudFriend>> fetchFriends(String uid);
}

/// Firestore implementation of [FriendCloudRepository].
class FirestoreFriendCloudRepository implements FriendCloudRepository {
  /// Lazily resolved on first use (same pattern as the post, profile,
  /// and wallet repositories): constructing the repository must never
  /// touch Firebase, so widget tests can pump the shell without an
  /// initialized Firebase app.
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _codeDoc(String code) =>
      _db.collection(friendCodesCollection).doc(code);

  DocumentReference<Map<String, dynamic>> _mappingDoc(String uid) =>
      _db.collection(userFriendCodesCollection).doc(uid);

  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection(friendRequestsCollection);

  @override
  Future<String> ensureCloudCode({
    required String uid,
    required String localCode,
  }) async {
    return _db.runTransaction<String>((tx) async {
      final mappingRef = _mappingDoc(uid);
      final mapping = await tx.get(mappingRef);
      final mapped = mapping.data()?['code'] as String?;
      if (mapped != null && mapped.isNotEmpty) {
        final codeSnap = await tx.get(_codeDoc(mapped));
        if (!codeSnap.exists) {
          // Mapping without its code doc (deleted out of band):
          // recreate it under the same code so the identity holds.
          tx.set(_codeDoc(mapped), {
            'uid': uid,
            'code': mapped,
            'createdAt': FieldValue.serverTimestamp(),
          });
          return mapped;
        }
        if (codeSnap.data()?['uid'] == uid) return mapped;
        // Stale mapping pointing at someone else's code: fall
        // through and claim anew below.
      }
      final localSnap = await tx.get(_codeDoc(localCode));
      final String claimed;
      if (!localSnap.exists || localSnap.data()?['uid'] == uid) {
        claimed = localCode;
      } else {
        // Local code belongs to another user: mint a fresh one.
        claimed = const Uuid().v4();
      }
      tx.set(_codeDoc(claimed), {
        'uid': uid,
        'code': claimed,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(mappingRef, {
        'code': claimed,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return claimed;
    });
  }

  @override
  Future<String> ensureInviteCode({
    required String uid,
    String? localCode,
  }) async {
    return _db.runTransaction<String>((tx) async {
      final mappingRef = _mappingDoc(uid);
      final mapping = await tx.get(mappingRef);
      final mapped = mapping.data()?['code'] as String?;
      if (mapped != null && mapped.isNotEmpty) {
        if (isInviteCodeFormat(mapped)) {
          final codeSnap = await tx.get(_codeDoc(mapped));
          if (!codeSnap.exists) {
            // Mapping without its code doc (deleted out of band):
            // recreate it under the same code so the identity holds.
            tx.set(_codeDoc(mapped), {
              'uid': uid,
              'code': mapped,
              'createdAt': FieldValue.serverTimestamp(),
            });
            return mapped;
          } else if (codeSnap.data()?['uid'] != uid) {
            // Stale mapping pointing at someone else's invite code:
            // fall through and claim anew below.
          } else {
            return mapped;
          }
        }
        // Legacy (non-invite) mapping: claim a fresh invite code
        // below and update the mapping. The old code document is
        // deliberately NOT deleted or touched: it stays as an
        // alias so old QRs and requests still resolve.
        if (!isInviteCodeFormat(mapped)) {
          final migrated = await _claimFreshInviteCode(tx, uid);
          tx.set(mappingRef, {
            'code': migrated,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return migrated;
        }
      }
      // No usable mapping: claim the local invite code when it is
      // already an invite code and unclaimed, otherwise mint fresh.
      if (localCode != null && isInviteCodeFormat(localCode)) {
        final localSnap = await tx.get(_codeDoc(localCode));
        if (!localSnap.exists || localSnap.data()?['uid'] == uid) {
          tx.set(_codeDoc(localCode), {
            'uid': uid,
            'code': localCode,
            'createdAt': FieldValue.serverTimestamp(),
          });
          tx.set(mappingRef, {
            'code': localCode,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return localCode;
        }
      }
      final claimed = await _claimFreshInviteCode(tx, uid);
      tx.set(mappingRef, {
        'code': claimed,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return claimed;
    });
  }

  /// Claims a fresh, unclaimed invite code inside [tx]. Reads the
  /// candidate document before any write in this transaction, so
  /// Firestore's read-before-write transaction rule holds. Throws
  /// [StateError] after repeated collisions instead of ever
  /// falling back to a UUID.
  Future<String> _claimFreshInviteCode(
    Transaction tx,
    String uid,
  ) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final candidate = generateInviteCode();
      final snap = await tx.get(_codeDoc(candidate));
      if (!snap.exists || snap.data()?['uid'] == uid) {
        tx.set(_codeDoc(candidate), {
          'uid': uid,
          'code': candidate,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return candidate;
      }
    }
    throw StateError(
      'Could not claim a unique invite code. Please try again.',
    );
  }

  @override
  Future<CloudCodeLookup?> lookupCode(String code) async {
    final snap = await _codeDoc(code).get();
    if (!snap.exists) return null;
    final owner = snap.data()?['uid'] as String?;
    if (owner == null || owner.isEmpty) return null;
    return CloudCodeLookup(uid: owner, code: code);
  }

  @override
  Future<FriendRequest> sendRequest({
    required String fromUid,
    required String? fromName,
    required String fromCode,
    required String toUid,
    required String toCode,
  }) async {
    if (fromUid == toUid) {
      throw ArgumentError('Cannot send a friend request to yourself.');
    }
    // Recipient must own the entered code (it was just looked up,
    // but the doc could have changed since).
    final codeSnap = await _codeDoc(toCode).get();
    if (!codeSnap.exists || codeSnap.data()?['uid'] != toUid) {
      throw StateError('That code is no longer valid.');
    }
    // Duplicate guard: one pending request per (sender, recipient).
    // Single-field query + client-side filter on purpose: no
    // composite index is needed for this lookup.
    final outgoing = await _requests
        .where('from', isEqualTo: fromUid)
        .get();
    final duplicate = outgoing.docs.any((doc) {
      final data = doc.data();
      return data['to'] == toUid && data['status'] == requestStatusPending;
    });
    if (duplicate) {
      throw StateError('A request to this friend is already pending.');
    }
    final ref = _requests.doc();
    await ref.set({
      'from': fromUid,
      'to': toUid,
      'fromName': fromName,
      'toName': null,
      'fromCode': fromCode,
      'toCode': toCode,
      'status': requestStatusPending,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return FriendRequest(
      id: ref.id,
      fromUid: fromUid,
      toUid: toUid,
      fromCode: fromCode,
      toCode: toCode,
      status: requestStatusPending,
      fromName: fromName,
    );
  }

  @override
  Future<List<FriendRequest>> fetchIncoming(String uid) async {
    final snap = await _requests.where('to', isEqualTo: uid).get();
    return _sorted(FriendRequest.fromDoc, snap.docs);
  }

  @override
  Future<List<FriendRequest>> fetchOutgoing(String uid) async {
    final snap = await _requests.where('from', isEqualTo: uid).get();
    return _sorted(FriendRequest.fromDoc, snap.docs);
  }

  /// Newest first, undated entries last. Client-side sort on
  /// purpose: no composite index is needed for these queries.
  List<FriendRequest> _sorted(
    FriendRequest Function(DocumentSnapshot<Map<String, dynamic>>) parse,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final requests = docs.map(parse).toList();
    requests.sort((a, b) {
      final aTime = a.createdAt;
      final bTime = b.createdAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return requests;
  }

  @override
  Future<void> respondToRequest({
    required String requestId,
    required String uid,
    required bool accept,
  }) async {
    await _db.runTransaction<void>((tx) async {
      final ref = _requests.doc(requestId);
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('Request not found.');
      final data = snap.data() ?? {};
      if (data['to'] != uid) {
        throw StateError('Only the recipient can answer this request.');
      }
      if (data['status'] != requestStatusPending) {
        throw StateError('This request was already answered.');
      }
      tx.update(ref, {
        'status': accept ? requestStatusAccepted : requestStatusDeclined,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<List<CloudFriend>> fetchFriends(String uid) async {
    final incoming = await fetchIncoming(uid);
    final outgoing = await fetchOutgoing(uid);
    final byUid = <String, CloudFriend>{};
    for (final request in incoming) {
      if (!request.isAccepted) continue;
      byUid.putIfAbsent(
        request.fromUid,
        () => CloudFriend(
          uid: request.fromUid,
          code: request.fromCode,
          name: request.fromName,
        ),
      );
    }
    for (final request in outgoing) {
      if (!request.isAccepted) continue;
      byUid.putIfAbsent(
        request.toUid,
        () => CloudFriend(
          uid: request.toUid,
          code: request.toCode,
          name: request.toName,
        ),
      );
    }
    final friends = byUid.values.toList();
    friends.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return friends;
  }
}
