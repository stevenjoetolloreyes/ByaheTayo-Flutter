// Shared community posts — Firestore repository.
//
// The Communities tab shows TWO kinds of posts: shared posts from
// Firestore (collection `community_posts`) and local posts from
// SharedPreferences (see community_posts.dart). This file owns the
// shared side only: the repository abstraction, the Firestore
// implementation, and the visibility rule that decides which shared
// posts a given user may see.
//
// VISIBILITY (client mirror of firestore.rules — the rules are the
// real enforcement; this only decides what the UI fetches/shows):
//   approved  → any signed-in user
//   pending   → only its author + allowlisted admins
//   rejected  → nobody (hidden everywhere)
// Signed-out users see no shared posts (the rules deny unauthenticated
// reads, so the repository returns [] without querying).
//
// PHOTO GUARD: Firestore documents cap at 1MB. A post whose base64
// photo would push its document over ~800KB is shared WITHOUT the
// photo (honest omission, flagged to the caller) — never failed over
// its photo.
//
// NO AUTO-MIGRATION: this repository never reads or uploads local
// posts. Old local posts stay local; the CTransco sample stays local.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'admin_access.dart';
import 'community_posts.dart';
import 'onboarding/auth_service.dart';

/// Firestore collection for shared community posts.
const communityPostsCollection = 'community_posts';

/// Documents are kept well under Firestore's 1MB cap: a post whose
/// estimated size exceeds this is shared without its photo.
const kMaxSharedDocBytes = 800 * 1024;

/// Result of sharing a post: the stored post plus whether its photo
/// was dropped by the photo guard.
typedef SharedPostCreation = ({CommunityPost post, bool photoDropped});

/// Whether a SHARED post may be shown to [user]. Local posts use
/// [showPostInCommunityList] instead; this rule is shared-only.
bool sharedPostVisibleTo(CommunityPost post, AuthUser? user) {
  if (!post.isShared) return false;
  if (post.status == PostStatus.rejected) return false;
  if (user == null) return false;
  if (post.status == PostStatus.approved) return true;
  return post.authorUid == user.uid || isAdminUser(user);
}

/// Shared-post storage. Tests use an in-memory fake; production uses
/// [FirestorePostRepository]. Methods throw on Firestore errors — the
/// caller shows the honest message and never falls back to a silent
/// local save.
abstract class PostRepository {
  /// Shared posts visible to [user], newest first. Empty for
  /// signed-out users (shared reads require sign-in).
  Future<List<CommunityPost>> loadVisiblePosts(AuthUser? user);

  /// Shares a new post as pending. The author's UID is stamped from
  /// [author], never from editable input.
  Future<SharedPostCreation> createPost(
    CommunityPost post,
    AuthUser author,
  );

  /// Admin-only status change (rules enforce; UI gates by allowlist).
  /// [post] must be a shared post (non-null id).
  Future<void> updatePostStatus(CommunityPost post, PostStatus status);

  /// Admin-only delete. [post] must be a shared post (non-null id).
  Future<void> deletePost(CommunityPost post);
}

/// Firestore implementation of [PostRepository].
class FirestorePostRepository implements PostRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection(communityPostsCollection);

  @override
  Future<List<CommunityPost>> loadVisiblePosts(AuthUser? user) async {
    if (user == null) return [];
    final approvedSnap =
        await _collection.where('status', isEqualTo: 'approved').get();
    final Query<Map<String, dynamic>> pendingQuery;
    if (isAdminUser(user)) {
      pendingQuery =
          _collection.where('status', isEqualTo: 'pending');
    } else {
      pendingQuery = _collection
          .where('authorUid', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending');
    }
    final pendingSnap = await pendingQuery.get();
    final byId = <String, CommunityPost>{};
    for (final doc in [...approvedSnap.docs, ...pendingSnap.docs]) {
      byId[doc.id] = sharedPostFromDoc(doc.id, doc.data());
    }
    final posts = byId.values.toList();
    posts.sort((a, b) {
      final aTime = a.createdAt;
      final bTime = b.createdAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return posts;
  }

  @override
  Future<SharedPostCreation> createPost(
    CommunityPost post,
    AuthUser author,
  ) async {
    var doc = sharedPostToDoc(post, author.uid);
    var photoDropped = false;
    if (doc['photoBase64'] is String &&
        _estimatedDocBytes(doc) > kMaxSharedDocBytes) {
      doc = Map<String, dynamic>.of(doc)..remove('photoBase64');
      photoDropped = true;
    }
    final ref = await _collection.add({
      ...doc,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final snap = await ref.get();
    final data = snap.data();
    final createdAt = data?['createdAt'];
    return (
      post: post.copyWith(
        id: ref.id,
        authorUid: author.uid,
        status: PostStatus.pending,
        createdAt: createdAt is Timestamp
            ? createdAt.toDate()
            : DateTime.now(),
      ),
      photoDropped: photoDropped,
    );
  }

  @override
  Future<void> updatePostStatus(
    CommunityPost post,
    PostStatus status,
  ) async {
    final id = post.id;
    if (id == null) {
      throw StateError('Cannot update a local post in Firestore.');
    }
    await _collection.doc(id).update({'status': status.name});
  }

  @override
  Future<void> deletePost(CommunityPost post) async {
    final id = post.id;
    if (id == null) {
      throw StateError('Cannot delete a local post from Firestore.');
    }
    await _collection.doc(id).delete();
  }
}

/// Estimated Firestore document size in bytes (JSON encoding of the
/// field map). Only used for the photo guard; the real cap is 1MB.
int _estimatedDocBytes(Map<String, dynamic> doc) =>
    utf8.encode(jsonEncode(doc)).length;

/// Firestore document map for a new shared post (no id — the document
/// id becomes [CommunityPost.id]; no createdAt — the server timestamp
/// is stamped on write). Status is always pending on create.
Map<String, dynamic> sharedPostToDoc(CommunityPost post, String authorUid) {
  return {
    'routeName': post.routeName,
    'vehicles': post.vehicles,
    'hours': post.hours,
    'fare': post.fare,
    'hubName': post.hubName,
    'from': post.from,
    'to': post.to,
    if (post.photoBase64 != null) 'photoBase64': post.photoBase64,
    if (post.faresByVehicle.isNotEmpty)
      'faresByVehicle': Map<String, dynamic>.from(post.faresByVehicle),
    if (post.operatorName.isNotEmpty) 'operatorName': post.operatorName,
    'status': PostStatus.pending.name,
    'authorUid': authorUid,
  };
}

/// Parses a Firestore document into a [CommunityPost]. Unknown or
/// corrupt fields fall back safely, mirroring [CommunityPost.fromJson].
CommunityPost sharedPostFromDoc(
  String id,
  Map<String, dynamic> data,
) {
  final vehicles = data['vehicles'];
  final photo = data['photoBase64'];
  final fares = data['faresByVehicle'];
  final faresMap = <String, double>{};
  if (fares is Map) {
    for (final entry in fares.entries) {
      if (entry.key is String && entry.value is num) {
        faresMap[entry.key as String] = (entry.value as num).toDouble();
      }
    }
  }
  final createdAt = data['createdAt'];
  return CommunityPost(
    routeName: data['routeName'] is String ? data['routeName'] as String : '',
    vehicles: vehicles is List
        ? vehicles.whereType<String>().toList()
        : const <String>[],
    hours: data['hours'] is String ? data['hours'] as String : '',
    fare: data['fare'] is num ? (data['fare'] as num).toDouble() : 0,
    hubName: data['hubName'] is String ? data['hubName'] as String : '',
    from: data['from'] is String ? data['from'] as String : '',
    to: data['to'] is String ? data['to'] as String : '',
    photoBase64: photo is String && photo.isNotEmpty ? photo : null,
    faresByVehicle: faresMap,
    operatorName: data['operatorName'] is String ? data['operatorName'] : '',
    status: postStatusFromString(
      data['status'] is String ? data['status'] as String : null,
    ),
    id: id,
    authorUid: data['authorUid'] is String ? data['authorUid'] as String : '',
    createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
  );
}

/// User-facing message for a shared-posts failure. Firestore errors
/// surface their message (e.g. database not created yet); anything
/// else falls back to a generic honest line.
String sharedPostsErrorMessage(Object error) {
  if (error is FirebaseException) {
    final message = error.message;
    if (message != null && message.trim().isNotEmpty) return message.trim();
    return 'Firestore error (${error.code}).';
  }
  return 'Could not reach the shared posts database.';
}
