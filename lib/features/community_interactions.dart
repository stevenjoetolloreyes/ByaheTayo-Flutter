// Community post interactions — Like / Dislike / Comment.
//
// Reusable widget ([CommunityPostInteractionWidget]) plus the storage
// behind it. The widget renders on APPROVED shared posts and on
// local-only posts; it renders NOTHING on pending or rejected shared
// posts (those are not public — see community_post_repository.dart).
//
// TWO BACKENDS, ONE INTERFACE ([PostInteractionRepository]):
//   shared posts → Firestore (see [FirestorePostInteractionRepository])
//   local posts  → SharedPreferences on this device only (see
//                  [LocalPostInteractionRepository]); a local post is
//                  NEVER uploaded by interacting with it.
//
// FIRESTORE SHAPE (rules in firestore.rules are the real enforcement):
//   community_reactions/{postId_uid}
//     One document per user per post — the document ID binds the
//     reaction to its post and author, so a duplicate reaction is
//     impossible by construction. Fields: postId, userId,
//     value ('like' | 'dislike'), updatedAt. Toggle-off deletes the
//     document; switching rewrites it.
//   community_post_stats/{postId}
//     Display counters (likeCount, dislikeCount, commentCount),
//     maintained by the SAME transaction that writes the reaction or
//     comment, so honest clients never drift from the source docs.
//   community_comments/{commentId}
//     Fields: postId, userId, displayName, photoUrl (optional), text,
//     createdAt (server timestamp), parentCommentId (optional: null
//     for a top-level comment, else the id of the comment replied
//     to). No edits; only the author may delete.
//   community_comment_reactions/{commentId_uid}
//     One document per user per comment — the document ID binds the
//     reaction to its comment and author, so a duplicate reaction
//     is impossible by construction. Fields: commentId, postId,
//     userId, value ('like' | 'dislike'), updatedAt. Toggle-off
//     deletes the document; switching rewrites it. Mirrors the
//     post-reaction pattern exactly.
//   community_comment_stats/{commentId}
//     Display counters (likeCount, dislikeCount), maintained by the
//     SAME transaction that writes the comment reaction, mirroring
//     community_post_stats. The sheet counts reactions from the
//     reaction documents themselves, so a drifted stats document
//     never misleads; the stats document is kept for parity with
//     post stats and for the future rules.
//   Replies are comments, not a second system: reply counts are
//     derived from the comment list itself (direct children in the
//     tree), so a reply needs no stats write and works on approved
//     posts under the EXISTING community_comments create rule.
//   RULES DEPENDENCY (honest, read before testing on a device):
//     comment reactions touch two collections that have NO rules
//     yet (comment_reactions, comment_stats). Until Steven
//     publishes an updated firestore.rules in the Console, those
//     reads/writes are denied by default deny on SHARED posts, and
//     the sheet shows comments with zeroed reaction buttons that
//     surface the error on tap. Replies and comment deletion work
//     before that publish because they only touch
//     community_comments / community_post_stats, which already have
//     rules. Local posts are unaffected: their reactions and
//     replies live in SharedPreferences on this device only.
//   ORPHAN RULE: deleting a comment removes only that comment.
//     Its replies are NOT cascade-deleted, because the rules allow
//     deleting only your own comment — a cascade would try to
//     delete other users' replies and the whole transaction would
//     fail. The tree builder instead promotes replies whose parent
//     is gone to top level, so no reply ever disappears silently.
// HONEST LIMIT (same shape as the points ledger): there are no Cloud
// Functions, so the counters are display values kept exact by app
// transactions, with rules bounding every write to a single valid
// step (one counter ±1, or a like↔dislike switch). The reaction and
// comment documents themselves are the auditable source; a client
// that bypasses the app could step a counter without a matching
// reaction, but it cannot forge, alter, or delete another user's
// reaction or comment, and it cannot interact with a post that is
// not approved (the rules check the parent post's status).
//
// COUNTS ARE NEVER FAKED: the widget shows a progress indicator
// until the first load completes, shows an honest error + Retry on
// failure, and never displays a zero it did not read. Reaction and
// comment writes show their own in-flight state; a failed write
// surfaces an error and leaves the previous state untouched.
//
// COMMENTER IDENTITY (real sources only, never invented):
// displayName comes from Firebase Auth ([AuthUser.displayName]) and
// falls back to the local part of the user's email, then to
// "Student". The photo comes from Auth ([AuthUser.photoUrl], the
// Google profile photo) when available; otherwise an initials avatar
// shows. A local photoPath file cannot be shared with other users,
// so it is never used here — the comment stores the name + photoUrl
// it was posted with, so reads never need a profile lookup.
//
// RATE GUARD: comments are capped at 500 characters, must contain a
// non-space character, and are limited to one per user per post per
// 10 seconds (client-side; the rules independently enforce shape).
// Reactions are idempotent single-document writes, so rapid taps
// cannot double-count; the widget additionally ignores taps while a
// reaction write is in flight.
import 'dart:convert';
import 'top_popup.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_layout.dart';
import 'app_rating.dart';
import 'community_posts.dart';
import 'onboarding/auth_service.dart';

/// A user's reaction to a post. Null means "no reaction".
enum PostReaction { like, dislike }

/// Counts plus the viewing user's own reaction for one post.
class PostInteractionState {
  const PostInteractionState({
    required this.likeCount,
    required this.dislikeCount,
    required this.commentCount,
    this.myReaction,
  });

  final int likeCount;
  final int dislikeCount;
  final int commentCount;
  final PostReaction? myReaction;
}

/// One comment on a post.
class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.displayName,
    this.photoUrl,
    required this.text,
    required this.createdAt,
    this.parentCommentId,
  });

  final String id;
  final String postId;
  final String userId;
  final String displayName;
  final String? photoUrl;
  final String text;
  final DateTime createdAt;

  /// Id of the comment this comment replies to, or null for a
  /// top-level comment. Depth is derived from the comment list
  /// (see [commentDepth]), never stored as a second source of
  /// truth — a stored depth could drift from the parent chain.
  final String? parentCommentId;

  bool get isReply => parentCommentId != null;

  /// Parses a Firestore comment document. Corrupt fields fall back
  /// safely (empty text is still shown, never crashed on).
  factory PostComment.fromDoc(String id, Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    return PostComment(
      id: id,
      postId: data['postId'] is String ? data['postId'] as String : '',
      userId: data['userId'] is String ? data['userId'] as String : '',
      displayName:
          data['displayName'] is String ? data['displayName'] as String : '',
      photoUrl: data['photoUrl'] is String ? data['photoUrl'] as String : null,
      text: data['text'] is String ? data['text'] as String : '',
      parentCommentId: data['parentCommentId'] is String
          ? data['parentCommentId'] as String
          : null,
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : createdAt is DateTime
              ? createdAt
              : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'postId': postId,
        'userId': userId,
        'displayName': displayName,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'text': text,
        if (parentCommentId != null) 'parentCommentId': parentCommentId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PostComment.fromJson(Map<String, dynamic> json) {
    final createdAt = json['createdAt'];
    return PostComment(
      id: json['id'] is String ? json['id'] as String : '',
      postId: json['postId'] is String ? json['postId'] as String : '',
      userId: json['userId'] is String ? json['userId'] as String : '',
      displayName:
          json['displayName'] is String ? json['displayName'] as String : '',
      photoUrl:
          json['photoUrl'] is String ? json['photoUrl'] as String : null,
      text: json['text'] is String ? json['text'] as String : '',
      parentCommentId: json['parentCommentId'] is String
          ? json['parentCommentId'] as String
          : null,
      createdAt: createdAt is String
          ? DateTime.tryParse(createdAt) ?? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Error thrown by interaction repositories with a message safe to
/// show in the UI.
class PostInteractionException implements Exception {
  const PostInteractionException(this.message);

  final String message;

  @override
  String toString() => 'PostInteractionException: $message';
}

/// Maximum comment length, enforced client-side and by the rules.
const kMaxCommentLength = 500;

/// Minimum gap between two comments from the same user on the same
/// post (client-side spam guard; rules enforce shape, not timing).
const kMinCommentInterval = Duration(seconds: 10);

/// Toggle semantics for a reaction tap: tapping the reaction you
/// already hold removes it; tapping the other one switches to it.
/// Pure — unit-tested, shared by both repository implementations.
PostReaction? resolveReaction(PostReaction? current, PostReaction tapped) {
  if (current == tapped) return null;
  return tapped;
}

/// Maximum nesting depth for comment replies: a top-level comment
/// is depth 0, a reply is depth 1, a reply to a reply is depth 2,
/// and depth-2 comments show NO Reply button.
const kMaxCommentDepth = 2;

/// Reaction document id for one user on one comment: comment +
/// author, so one user can hold at most one reaction per comment.
/// Pure — unit-tested.
String commentReactionId(String commentId, String uid) =>
    '${commentId}_$uid';

/// Depth of [comment] in [all], by walking its parent chain.
/// A comment with no parent (or a parent missing from the list,
/// e.g. deleted) is depth 0 — this is what promotes orphan replies
/// to top level instead of hiding them. Cycle-safe: a repeated id
/// in the chain stops the walk. Pure — unit-tested.
int commentDepth(List<PostComment> all, PostComment comment) {
  final byId = {for (final c in all) c.id: c};
  var depth = 0;
  final seen = <String>{comment.id};
  var parentId = comment.parentCommentId;
  while (parentId != null && !seen.contains(parentId)) {
    final parent = byId[parentId];
    if (parent == null) break;
    seen.add(parentId);
    depth += 1;
    parentId = parent.parentCommentId;
  }
  return depth;
}

/// True when [comment] may still be replied to (depth < max).
bool canReplyTo(List<PostComment> all, PostComment comment) =>
    commentDepth(all, comment) < kMaxCommentDepth;

/// One node of a comment thread: a comment plus its direct
/// replies, already sorted. Roots are newest first (the sheet's
/// existing order); replies under a parent are oldest first, so a
/// conversation reads top to bottom.
class CommentNode {
  const CommentNode({
    required this.comment,
    required this.children,
    this.depth = 0,
  });

  final PostComment comment;
  final List<CommentNode> children;
  final int depth;
}

/// Builds the thread tree for [comments]. Replies whose parent is
/// missing from the list become roots (see the orphan rule in the
/// file header). Pure — unit-tested.
List<CommentNode> buildCommentTree(List<PostComment> comments) {
  final byId = {for (final c in comments) c.id: c};
  final childrenOf = <String, List<PostComment>>{};
  final roots = <PostComment>[];
  for (final comment in comments) {
    final parentId = comment.parentCommentId;
    if (parentId != null && byId.containsKey(parentId)) {
      childrenOf.putIfAbsent(parentId, () => []).add(comment);
    } else {
      roots.add(comment);
    }
  }
  CommentNode build(PostComment comment, int depth) {
    final kids = (childrenOf[comment.id] ?? [])
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return CommentNode(
      comment: comment,
      children: kids.map((k) => build(k, depth + 1)).toList(),
      depth: depth,
    );
  }

  roots.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return roots.map((r) => build(r, 0)).toList();
}

/// Counts plus the viewing user's own reaction for one comment.
class CommentReactionState {
  const CommentReactionState({
    required this.likeCount,
    required this.dislikeCount,
    this.myReaction,
  });

  final int likeCount;
  final int dislikeCount;
  final PostReaction? myReaction;
}

/// Display name for a commenter, from real sources only: the auth
/// display name, else the local part of the email, else "Student".
/// Pure — unit-tested.
String commentDisplayName(AuthUser user) {
  final name = user.displayName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final email = user.email.trim();
  final at = email.indexOf('@');
  if (at > 0) return email.substring(0, at);
  if (email.isNotEmpty) return email;
  return 'Student';
}

/// Initials for the fallback avatar: first letter of the display
/// name, uppercased. The name is never empty (see
/// [commentDisplayName]), so this never falls back to '?'.
String commentInitials(String displayName) {
  final trimmed = displayName.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed[0].toUpperCase();
}

/// Comment validation shared by the sheet and both repositories.
/// Returns the error message, or null when [rawText] is acceptable.
String? commentValidationError(String rawText) {
  final text = rawText.trim();
  if (text.isEmpty) return 'Write a comment first.';
  if (text.length > kMaxCommentLength) {
    return 'Comments are limited to $kMaxCommentLength characters.';
  }
  return null;
}

/// Short timestamp for a comment ("Nov 2, 2026 · 7:41 PM", device
/// local time). No intl dependency — month names are inlined.
String formatCommentTime(DateTime time) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = time.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final ampm = local.hour < 12 ? 'AM' : 'PM';
  return '${months[local.month - 1]} ${local.day}, ${local.year} '
      '· $hour12:$minute $ampm';
}

/// Stable device-local key for a local-only post. Local posts have no
/// document id, so the key is derived from their identifying fields;
/// two identical local posts share one local thread (harmless — same
/// route, same device). Pure — unit-tested.
String localPostKey(CommunityPost post) {
  final raw = [
    post.from,
    post.to,
    post.operatorName,
    post.routeName,
    post.hubName,
  ].join('|');
  var hash = 5381;
  for (final unit in raw.codeUnits) {
    hash = ((hash << 5) + hash + unit) & 0xFFFFFFFF;
  }
  return 'local_$hash';
}

/// Storage for post interactions. Tests use an in-memory fake;
/// production uses [FirestorePostInteractionRepository] for shared
/// posts and [LocalPostInteractionRepository] for local posts.
/// Methods throw [PostInteractionException] (or FirebaseException,
/// surfaced honestly by the caller) on failure — never a fake success.
abstract class PostInteractionRepository {
  /// Counts plus the viewing user's own reaction. [uid] null means
  /// signed out: counts still load, [PostInteractionState.myReaction]
  /// is null.
  Future<PostInteractionState> loadState({
    required String postId,
    required String? uid,
  });

  /// Comments for a post, newest first.
  Future<List<PostComment>> loadComments(String postId);

  /// Reactions for every comment on a post, keyed by comment id.
  /// Missing entries mean "no reactions". [uid] null means signed
  /// out: counts still load, [CommentReactionState.myReaction] is
  /// null.
  Future<Map<String, CommentReactionState>> loadCommentReactions({
    required String postId,
    required String? uid,
  });

  /// Applies a comment-reaction tap: same-as-current removes it,
  /// otherwise switches to [tapped]. One document per user per
  /// comment.
  Future<void> setCommentReaction({
    required String postId,
    required String commentId,
    required AuthUser user,
    required PostReaction tapped,
  });

  /// Stores a reply to [parentCommentId]. Throws when the parent
  /// does not exist, belongs to another post, or is already at
  /// [kMaxCommentDepth]. The reply counts as a comment for the
  /// post (post comment count +1) and for the rate guard.
  Future<void> addReply({
    required String postId,
    required String parentCommentId,
    required AuthUser user,
    required String text,
  });

  /// Applies a reaction tap: same-as-current removes it, otherwise
  /// switches to [tapped]. One document per user per post.
  Future<void> setReaction({
    required String postId,
    required AuthUser user,
    required PostReaction tapped,
  });

  /// Validates, rate-guards, and stores a comment. The display name
  /// and photo are derived from [user] (see [commentDisplayName]).
  Future<void> addComment({
    required String postId,
    required AuthUser user,
    required String text,
  });

  /// Deletes a comment. Only the comment's author may delete it;
  /// anything else throws.
  Future<void> deleteComment({
    required String postId,
    required String commentId,
    required AuthUser user,
  });
}

/// Client-side per-user-per-post comment rate guard. In-memory (a
/// restart resets it); the rules independently enforce shape.
class CommentRateGuard {
  final Map<String, DateTime> _lastSubmit = {};

  /// True when [user] may comment on [postId] at [now].
  bool canSubmit({
    required String postId,
    required String uid,
    required DateTime now,
  }) {
    final last = _lastSubmit['$postId|$uid'];
    if (last == null) return true;
    return now.difference(last) >= kMinCommentInterval;
  }

  void markSubmitted({
    required String postId,
    required String uid,
    required DateTime now,
  }) {
    _lastSubmit['$postId|$uid'] = now;
  }
}

/// User-facing message for an interaction failure. Firestore errors
/// surface their message; anything else falls back to a generic
/// honest line.
String interactionErrorMessage(Object error) {
  if (error is PostInteractionException) return error.message;
  if (error is FirebaseException) {
    final message = error.message;
    if (message != null && message.trim().isNotEmpty) return message.trim();
    return 'Firestore error (${error.code}).';
  }
  return 'Could not reach the community database.';
}

/// Firestore implementation of [PostInteractionRepository] for
/// APPROVED shared posts. Every mutation runs in a transaction that
/// writes the source document (reaction or comment) together with the
/// post's stats document, so counts stay exact for honest clients.
/// The transaction reads the reaction document first (it may not
/// exist yet — the rules' null arm permits that read); the stats
/// document read needs no null arm (its rule dereferences nothing).
class FirestorePostInteractionRepository
    implements PostInteractionRepository {
  FirestorePostInteractionRepository({CommentRateGuard? rateGuard})
      : _rateGuard = rateGuard ?? CommentRateGuard();

  final CommentRateGuard _rateGuard;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _reactions =>
      _db.collection('community_reactions');

  CollectionReference<Map<String, dynamic>> get _comments =>
      _db.collection('community_comments');

  CollectionReference<Map<String, dynamic>> get _commentReactions =>
      _db.collection('comment_reactions');

  DocumentReference<Map<String, dynamic>> _statsRef(String postId) =>
      _db.collection('community_post_stats').doc(postId);

  DocumentReference<Map<String, dynamic>> _commentStatsRef(
    String commentId,
  ) =>
      _db.collection('comment_stats').doc(commentId);

  /// Reaction document id: post + author, so one user can hold at
  /// most one reaction per post.
  String _reactionId(String postId, String uid) => '${postId}_$uid';

  @override
  Future<PostInteractionState> loadState({
    required String postId,
    required String? uid,
  }) async {
    final statsSnap = await _statsRef(postId).get();
    final stats = statsSnap.data();
    final likeCount = (stats?['likeCount'] as num?)?.toInt() ?? 0;
    final dislikeCount = (stats?['dislikeCount'] as num?)?.toInt() ?? 0;
    final commentCount = (stats?['commentCount'] as num?)?.toInt() ?? 0;
    PostReaction? mine;
    if (uid != null) {
      final reactionSnap =
          await _reactions.doc(_reactionId(postId, uid)).get();
      final value = reactionSnap.data()?['value'];
      if (value == 'like') {
        mine = PostReaction.like;
      } else if (value == 'dislike') {
        mine = PostReaction.dislike;
      }
    }
    return PostInteractionState(
      likeCount: likeCount,
      dislikeCount: dislikeCount,
      commentCount: commentCount,
      myReaction: mine,
    );
  }

  @override
  Future<List<PostComment>> loadComments(String postId) async {
    // Single-field equality query: no composite index needed.
    // Sorted client-side (newest first) for the same reason.
    final snap =
        await _comments.where('postId', isEqualTo: postId).get();
    final comments = snap.docs
        .map((doc) => PostComment.fromDoc(doc.id, doc.data()))
        .toList();
    comments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return comments;
  }

  @override
  Future<Map<String, CommentReactionState>> loadCommentReactions({
    required String postId,
    required String? uid,
  }) async {
    // Reaction documents carry postId, so one query covers the
    // whole sheet. Counts come from the reaction documents
    // themselves (the auditable source), not from the stats doc.
    final snap = await _commentReactions
        .where('postId', isEqualTo: postId)
        .get();
    final byComment = <String, List<Map<String, dynamic>>>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final commentId = data['commentId'] as String?;
      if (commentId == null) continue;
      byComment.putIfAbsent(commentId, () => []).add(data);
    }
    final result = <String, CommentReactionState>{};
    for (final entry in byComment.entries) {
      var likes = 0;
      var dislikes = 0;
      PostReaction? mine;
      for (final data in entry.value) {
        final value = data['value'];
        if (value == 'like') likes += 1;
        if (value == 'dislike') dislikes += 1;
        if (uid != null && data['userId'] == uid) {
          mine = value == 'like'
              ? PostReaction.like
              : value == 'dislike'
                  ? PostReaction.dislike
                  : null;
        }
      }
      result[entry.key] = CommentReactionState(
        likeCount: likes,
        dislikeCount: dislikes,
        myReaction: mine,
      );
    }
    return result;
  }

  @override
  Future<void> setCommentReaction({
    required String postId,
    required String commentId,
    required AuthUser user,
    required PostReaction tapped,
  }) async {
    await _db.runTransaction((tx) async {
      final reactionRef =
          _commentReactions.doc(commentReactionId(commentId, user.uid));
      final statsRef = _commentStatsRef(commentId);
      final existing = await tx.get(reactionRef);
      final statsSnap = await tx.get(statsRef);
      final stats = statsSnap.data();
      var likes = (stats?['likeCount'] as num?)?.toInt() ?? 0;
      var dislikes = (stats?['dislikeCount'] as num?)?.toInt() ?? 0;
      final existingData = existing.data();
      String? oldValue;
      if (existing.exists && existingData != null) {
        oldValue = existingData['value'] as String?;
      }
      final oldReaction = oldValue == 'like'
          ? PostReaction.like
          : oldValue == 'dislike'
              ? PostReaction.dislike
              : null;
      final next = resolveReaction(oldReaction, tapped);
      if (oldReaction == PostReaction.like) likes -= 1;
      if (oldReaction == PostReaction.dislike) dislikes -= 1;
      if (next == PostReaction.like) likes += 1;
      if (next == PostReaction.dislike) dislikes += 1;
      if (likes < 0) likes = 0;
      if (dislikes < 0) dislikes = 0;
      if (next == null) {
        tx.delete(reactionRef);
      } else {
        tx.set(reactionRef, {
          'commentId': commentId,
          'postId': postId,
          'userId': user.uid,
          'value': next.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      // Same skip rule as post reactions: a removal with no stats
      // document has nothing to decrement.
      if (statsSnap.exists || likes + dislikes > 0) {
        tx.set(statsRef, {
          'likeCount': likes,
          'dislikeCount': dislikes,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  @override
  Future<void> addReply({
    required String postId,
    required String parentCommentId,
    required AuthUser user,
    required String text,
  }) async {
    final validation = commentValidationError(text);
    if (validation != null) {
      throw PostInteractionException(validation);
    }
    final now = DateTime.now();
    if (!_rateGuard.canSubmit(postId: postId, uid: user.uid, now: now)) {
      throw const PostInteractionException(
        'You are commenting too quickly. Wait a few seconds and try again.',
      );
    }
    final trimmed = text.trim();
    final photoUrl = user.photoUrl?.trim();
    // Depth is checked BEFORE the transaction: a query is not a
    // transactional read, so it must not run inside runTransaction.
    // The transaction below re-checks the parent document itself,
    // so a parent deleted in between still aborts the write.
    final all = await loadComments(postId);
    PostComment? parent;
    for (final c in all) {
      if (c.id == parentCommentId) parent = c;
    }
    if (parent == null) {
      throw const PostInteractionException(
        'That comment no longer exists.',
      );
    }
    if (!canReplyTo(all, parent)) {
      throw const PostInteractionException(
        'Replies cannot go deeper than 2 levels.',
      );
    }
    await _db.runTransaction((tx) async {
      final parentSnap = await tx.get(_comments.doc(parentCommentId));
      if (!parentSnap.exists ||
          (parentSnap.data() ?? {})['postId'] != postId) {
        throw const PostInteractionException(
          'That comment no longer exists.',
        );
      }
      final statsRef = _statsRef(postId);
      final statsSnap = await tx.get(statsRef);
      final stats = statsSnap.data();
      final likes = (stats?['likeCount'] as num?)?.toInt() ?? 0;
      final dislikes = (stats?['dislikeCount'] as num?)?.toInt() ?? 0;
      final comments = (stats?['commentCount'] as num?)?.toInt() ?? 0;
      final commentRef = _comments.doc();
      tx.set(commentRef, {
        'postId': postId,
        'userId': user.uid,
        'displayName': commentDisplayName(user),
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
        'text': trimmed,
        'parentCommentId': parentCommentId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(statsRef, {
        'likeCount': likes,
        'dislikeCount': dislikes,
        'commentCount': comments + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    _rateGuard.markSubmitted(postId: postId, uid: user.uid, now: now);
  }

  @override
  Future<void> setReaction({
    required String postId,
    required AuthUser user,
    required PostReaction tapped,
  }) async {
    await _db.runTransaction((tx) async {
      final reactionRef = _reactions.doc(_reactionId(postId, user.uid));
      final statsRef = _statsRef(postId);
      final existing = await tx.get(reactionRef);
      final statsSnap = await tx.get(statsRef);
      final stats = statsSnap.data();
      var likes = (stats?['likeCount'] as num?)?.toInt() ?? 0;
      var dislikes = (stats?['dislikeCount'] as num?)?.toInt() ?? 0;
      final comments = (stats?['commentCount'] as num?)?.toInt() ?? 0;
      final existingData = existing.data();
      String? oldValue;
      if (existing.exists && existingData != null) {
        oldValue = existingData['value'] as String?;
      }
      final oldReaction = oldValue == 'like'
          ? PostReaction.like
          : oldValue == 'dislike'
              ? PostReaction.dislike
              : null;
      final next = resolveReaction(oldReaction, tapped);
      if (oldReaction == PostReaction.like) likes -= 1;
      if (oldReaction == PostReaction.dislike) dislikes -= 1;
      if (next == PostReaction.like) likes += 1;
      if (next == PostReaction.dislike) dislikes += 1;
      // Clamp: a drifted counter must never block removing a real
      // reaction (the rules reject negatives, which would fail the
      // whole transaction). Counts converge on later reactions.
      if (likes < 0) likes = 0;
      if (dislikes < 0) dislikes = 0;
      if (next == null) {
        tx.delete(reactionRef);
      } else {
        tx.set(reactionRef, {
          'postId': postId,
          'userId': user.uid,
          'value': next.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      // A removal with no stats document has nothing to decrement
      // (and the create rule requires a total of exactly 1), so the
      // stats write is skipped in that case only.
      if (statsSnap.exists || likes + dislikes + comments > 0) {
        tx.set(statsRef, {
          'likeCount': likes,
          'dislikeCount': dislikes,
          'commentCount': comments,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  @override
  Future<void> addComment({
    required String postId,
    required AuthUser user,
    required String text,
  }) async {
    final validation = commentValidationError(text);
    if (validation != null) {
      throw PostInteractionException(validation);
    }
    final now = DateTime.now();
    if (!_rateGuard.canSubmit(postId: postId, uid: user.uid, now: now)) {
      throw const PostInteractionException(
        'You are commenting too quickly. Wait a few seconds and try again.',
      );
    }
    final trimmed = text.trim();
    final photoUrl = user.photoUrl?.trim();
    await _db.runTransaction((tx) async {
      final statsRef = _statsRef(postId);
      final statsSnap = await tx.get(statsRef);
      final stats = statsSnap.data();
      final likes = (stats?['likeCount'] as num?)?.toInt() ?? 0;
      final dislikes = (stats?['dislikeCount'] as num?)?.toInt() ?? 0;
      final comments = (stats?['commentCount'] as num?)?.toInt() ?? 0;
      final commentRef = _comments.doc();
      tx.set(commentRef, {
        'postId': postId,
        'userId': user.uid,
        'displayName': commentDisplayName(user),
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
        'text': trimmed,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(statsRef, {
        'likeCount': likes,
        'dislikeCount': dislikes,
        'commentCount': comments + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    _rateGuard.markSubmitted(postId: postId, uid: user.uid, now: now);
  }

  @override
  Future<void> deleteComment({
    required String postId,
    required AuthUser user,
    required String commentId,
  }) async {
    // The rules enforce authorship; the client does not need to read
    // the comment first. The stats update rides the same transaction.
    await _db.runTransaction((tx) async {
      final statsRef = _statsRef(postId);
      final statsSnap = await tx.get(statsRef);
      final stats = statsSnap.data();
      final likes = (stats?['likeCount'] as num?)?.toInt() ?? 0;
      final dislikes = (stats?['dislikeCount'] as num?)?.toInt() ?? 0;
      var comments = (stats?['commentCount'] as num?)?.toInt() ?? 0;
      tx.delete(_comments.doc(commentId));
      if (comments > 0) comments -= 1;
      if (statsSnap.exists || likes + dislikes + comments > 0) {
        tx.set(statsRef, {
          'likeCount': likes,
          'dislikeCount': dislikes,
          'commentCount': comments,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }
}

/// Device-only implementation of [PostInteractionRepository] for
/// local posts. Everything lives in SharedPreferences under two keys
/// and is keyed by [localPostKey]; nothing here ever touches the
/// network, so a local post stays local no matter how much it is
/// reacted to or commented on. Counts are computed from the stored
/// documents themselves, so they are exact by construction.
class LocalPostInteractionRepository implements PostInteractionRepository {
  LocalPostInteractionRepository({CommentRateGuard? rateGuard})
      : _rateGuard = rateGuard ?? CommentRateGuard();

  final CommentRateGuard _rateGuard;

  static const _reactionsKey = 'byahetayo_local_reactions';
  static const _commentsKey = 'byahetayo_local_comments';

  /// Local comment reactions, keyed postId -> commentId -> uid.
  /// A NEW key (never reused for post reactions): post reactions
  /// live under [_reactionsKey] keyed postId -> uid, and the two
  /// shapes must never be read as each other.
  static const _commentReactionsKey = 'byahetayo_local_comment_reactions';

  Future<Map<String, dynamic>> _readMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeMap(String key, Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  @override
  Future<PostInteractionState> loadState({
    required String postId,
    required String? uid,
  }) async {
    final reactions = await _readMap(_reactionsKey);
    final comments = await _readMap(_commentsKey);
    final postReactions = reactions[postId];
    var likes = 0;
    var dislikes = 0;
    PostReaction? mine;
    if (postReactions is Map) {
      for (final entry in postReactions.entries) {
        if (entry.value == 'like') likes += 1;
        if (entry.value == 'dislike') dislikes += 1;
        if (uid != null && entry.key == uid) {
          mine = entry.value == 'like'
              ? PostReaction.like
              : entry.value == 'dislike'
                  ? PostReaction.dislike
                  : null;
        }
      }
    }
    var commentCount = 0;
    final postComments = comments[postId];
    if (postComments is List) commentCount = postComments.length;
    return PostInteractionState(
      likeCount: likes,
      dislikeCount: dislikes,
      commentCount: commentCount,
      myReaction: mine,
    );
  }

  @override
  Future<List<PostComment>> loadComments(String postId) async {
    final comments = await _readMap(_commentsKey);
    final raw = comments[postId];
    if (raw is! List) return [];
    final parsed = raw
        .whereType<Map<String, dynamic>>()
        .map(PostComment.fromJson)
        .toList();
    parsed.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return parsed;
  }

  @override
  Future<Map<String, CommentReactionState>> loadCommentReactions({
    required String postId,
    required String? uid,
  }) async {
    final stored = await _readMap(_commentReactionsKey);
    final postMap = stored[postId];
    if (postMap is! Map) return {};
    final result = <String, CommentReactionState>{};
    for (final entry in postMap.entries) {
      final commentMap = entry.value;
      if (commentMap is! Map) continue;
      var likes = 0;
      var dislikes = 0;
      PostReaction? mine;
      for (final reaction in commentMap.entries) {
        if (reaction.value == 'like') likes += 1;
        if (reaction.value == 'dislike') dislikes += 1;
        if (uid != null && reaction.key == uid) {
          mine = reaction.value == 'like'
              ? PostReaction.like
              : reaction.value == 'dislike'
                  ? PostReaction.dislike
                  : null;
        }
      }
      result[entry.key.toString()] = CommentReactionState(
        likeCount: likes,
        dislikeCount: dislikes,
        myReaction: mine,
      );
    }
    return result;
  }

  @override
  Future<void> setCommentReaction({
    required String postId,
    required String commentId,
    required AuthUser user,
    required PostReaction tapped,
  }) async {
    final stored = await _readMap(_commentReactionsKey);
    final postMapRaw = stored[postId];
    final postMap = postMapRaw is Map<String, dynamic>
        ? Map<String, dynamic>.of(postMapRaw)
        : <String, dynamic>{};
    final commentMapRaw = postMap[commentId];
    final commentMap = commentMapRaw is Map<String, dynamic>
        ? Map<String, dynamic>.of(commentMapRaw)
        : <String, dynamic>{};
    final currentValue = commentMap[user.uid];
    final current = currentValue == 'like'
        ? PostReaction.like
        : currentValue == 'dislike'
            ? PostReaction.dislike
            : null;
    final next = resolveReaction(current, tapped);
    if (next == null) {
      commentMap.remove(user.uid);
    } else {
      commentMap[user.uid] = next.name;
    }
    postMap[commentId] = commentMap;
    stored[postId] = postMap;
    await _writeMap(_commentReactionsKey, stored);
  }

  @override
  Future<void> addReply({
    required String postId,
    required String parentCommentId,
    required AuthUser user,
    required String text,
  }) async {
    final validation = commentValidationError(text);
    if (validation != null) {
      throw PostInteractionException(validation);
    }
    final now = DateTime.now();
    if (!_rateGuard.canSubmit(postId: postId, uid: user.uid, now: now)) {
      throw const PostInteractionException(
        'You are commenting too quickly. Wait a few seconds and try again.',
      );
    }
    final comments = await _readMap(_commentsKey);
    final raw = comments[postId];
    final list = raw is List ? List<dynamic>.of(raw) : <dynamic>[];
    final all = list
        .whereType<Map<String, dynamic>>()
        .map(PostComment.fromJson)
        .toList();
    PostComment? parent;
    for (final c in all) {
      if (c.id == parentCommentId) parent = c;
    }
    if (parent == null) {
      throw const PostInteractionException(
        'That comment no longer exists.',
      );
    }
    if (!canReplyTo(all, parent)) {
      throw const PostInteractionException(
        'Replies cannot go deeper than 2 levels.',
      );
    }
    final photoUrl = user.photoUrl?.trim();
    final reply = PostComment(
      id: '${now.microsecondsSinceEpoch}_${user.uid}',
      postId: postId,
      userId: user.uid,
      displayName: commentDisplayName(user),
      photoUrl: photoUrl != null && photoUrl.isNotEmpty ? photoUrl : null,
      text: text.trim(),
      createdAt: now,
      parentCommentId: parentCommentId,
    );
    list.add(reply.toJson());
    comments[postId] = list;
    await _writeMap(_commentsKey, comments);
    _rateGuard.markSubmitted(postId: postId, uid: user.uid, now: now);
  }

  @override
  Future<void> setReaction({
    required String postId,
    required AuthUser user,
    required PostReaction tapped,
  }) async {
    final reactions = await _readMap(_reactionsKey);
    final postReactions = reactions[postId];
    final map = postReactions is Map<String, dynamic>
        ? Map<String, dynamic>.of(postReactions)
        : <String, dynamic>{};
    final currentValue = map[user.uid];
    final current = currentValue == 'like'
        ? PostReaction.like
        : currentValue == 'dislike'
            ? PostReaction.dislike
            : null;
    final next = resolveReaction(current, tapped);
    if (next == null) {
      map.remove(user.uid);
    } else {
      map[user.uid] = next.name;
    }
    reactions[postId] = map;
    await _writeMap(_reactionsKey, reactions);
  }

  @override
  Future<void> addComment({
    required String postId,
    required AuthUser user,
    required String text,
  }) async {
    final validation = commentValidationError(text);
    if (validation != null) {
      throw PostInteractionException(validation);
    }
    final now = DateTime.now();
    if (!_rateGuard.canSubmit(postId: postId, uid: user.uid, now: now)) {
      throw const PostInteractionException(
        'You are commenting too quickly. Wait a few seconds and try again.',
      );
    }
    final comments = await _readMap(_commentsKey);
    final raw = comments[postId];
    final list = raw is List ? List<dynamic>.of(raw) : <dynamic>[];
    final photoUrl = user.photoUrl?.trim();
    final comment = PostComment(
      id: '${now.microsecondsSinceEpoch}_${user.uid}',
      postId: postId,
      userId: user.uid,
      displayName: commentDisplayName(user),
      photoUrl: photoUrl != null && photoUrl.isNotEmpty ? photoUrl : null,
      text: text.trim(),
      createdAt: now,
    );
    list.add(comment.toJson());
    comments[postId] = list;
    await _writeMap(_commentsKey, comments);
    _rateGuard.markSubmitted(postId: postId, uid: user.uid, now: now);
  }

  @override
  Future<void> deleteComment({
    required String postId,
    required String commentId,
    required AuthUser user,
  }) async {
    final comments = await _readMap(_commentsKey);
    final raw = comments[postId];
    if (raw is! List) {
      throw const PostInteractionException('That comment no longer exists.');
    }
    final index = raw.indexWhere(
      (item) => item is Map<String, dynamic> && item['id'] == commentId,
    );
    if (index < 0) {
      throw const PostInteractionException('That comment no longer exists.');
    }
    final target = raw[index] as Map<String, dynamic>;
    if (target['userId'] != user.uid) {
      throw const PostInteractionException(
        'You can only delete your own comments.',
      );
    }
    raw.removeAt(index);
    comments[postId] = raw;
    await _writeMap(_commentsKey, comments);
  }
}

/// Like / Dislike / Comment row for one community post.
///
/// Shared posts must be approved for the row to appear at all
/// (pending and rejected shared posts render nothing — they are not
/// public). Local posts always show the row, backed by the local
/// repository the caller passes in. The caller picks the repository:
/// pass the Firestore implementation for shared posts and the local
/// implementation for local posts; the widget itself only knows the
/// post id ([CommunityPost.id] for shared posts, [localPostKey] for
/// local ones).
///
/// The row follows the ambient [ColorScheme] in both modes: emerald
/// ([ColorScheme.primary], #16A34A light / #34D399 dark) for a
/// selected Like, a restrained red for a selected Dislike, and
/// [ColorScheme.onSurfaceVariant] for unselected actions. No counts
/// are shown until the first load completes.
class CommunityPostInteractionWidget extends StatefulWidget {
  const CommunityPostInteractionWidget({
    super.key,
    required this.post,
    required this.currentUser,
    required this.repository,
  });

  final CommunityPost post;
  final AuthUser? currentUser;
  final PostInteractionRepository repository;

  @override
  State<CommunityPostInteractionWidget> createState() =>
      _CommunityPostInteractionWidgetState();
}

class _CommunityPostInteractionWidgetState
    extends State<CommunityPostInteractionWidget> {
  PostInteractionState? _state;
  var _loading = true;
  String? _error;
  PostReaction? _reacting;

  String get _postId =>
      widget.post.isShared ? widget.post.id! : localPostKey(widget.post);

  @override
  void initState() {
    super.initState();
    // Pending / rejected shared posts render nothing, so they never
    // load (and never touch the backend).
    if (!widget.post.isShared ||
        widget.post.status == PostStatus.approved) {
      _reload();
    } else {
      _loading = false;
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await widget.repository.loadState(
        postId: _postId,
        uid: widget.currentUser?.uid,
      );
      if (!mounted) return;
      setState(() {
        _state = state;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = interactionErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _onReactionTap(PostReaction tapped) async {
    final user = widget.currentUser;
    if (user == null || _reacting != null) return;
    setState(() => _reacting = tapped);
    try {
      await widget.repository.setReaction(
        postId: _postId,
        user: user,
        tapped: tapped,
      );
      await _reload();
      // Rating prompt (Nov 9): a successful Like/Dislike is a real
      // action — interacting with a Communities post.
      AppRatingTracker.instance
          .recordAction(AppRatingAction.interactedWithPost);
    } catch (e) {
      if (!mounted) return;
      TopPopup.show(context, message: interactionErrorMessage(e));
    } finally {
      if (mounted) setState(() => _reacting = null);
    }
  }

  Future<void> _openComments() async {
    final user = widget.currentUser;
    if (user == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _CommentSheet(
        postId: _postId,
        user: user,
        repository: widget.repository,
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    // Pending and rejected shared posts are not public: no
    // interactions, ever. (Local posts always show the row.)
    if (widget.post.isShared &&
        widget.post.status != PostStatus.approved) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_error != null || _state == null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              _error ?? 'Could not load reactions.',
              style: AppText.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(onPressed: _reload, child: const Text('Retry')),
        ],
      );
    }
    final state = _state!;
    final signedIn = widget.currentUser != null;
    return Column(
      children: [
        Divider(height: 1, color: scheme.outline),
        const SizedBox(height: AppSpacing.s4),
        Row(
          children: [
            Expanded(
              child: _ReactionButton(
                icon: state.myReaction == PostReaction.like
                    ? Icons.thumb_up
                    : Icons.thumb_up_outlined,
                label: 'Like',
                count: state.likeCount,
                selected: state.myReaction == PostReaction.like,
                selectedColor: scheme.primary,
                enabled: signedIn,
                busy: _reacting == PostReaction.like,
                onTap: () => _onReactionTap(PostReaction.like),
              ),
            ),
            Expanded(
              child: _ReactionButton(
                icon: state.myReaction == PostReaction.dislike
                    ? Icons.thumb_down
                    : Icons.thumb_down_outlined,
                label: 'Dislike',
                count: state.dislikeCount,
                selected: state.myReaction == PostReaction.dislike,
                selectedColor: const Color(0xFFEF4444),
                enabled: signedIn,
                busy: _reacting == PostReaction.dislike,
                onTap: () => _onReactionTap(PostReaction.dislike),
              ),
            ),
            Expanded(
              child: _ReactionButton(
                icon: Icons.comment_outlined,
                label: 'Comment',
                count: state.commentCount,
                selected: false,
                selectedColor: scheme.primary,
                enabled: signedIn,
                busy: false,
                onTap: _openComments,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One Like / Dislike / Comment action: icon + count, with a subtle
/// scale animation when the icon or count changes, and a spinner
/// while its own write is in flight.
class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.selectedColor,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final Color selectedColor;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
        : selected
            ? selectedColor
            : scheme.onSurfaceVariant;
    return TextButton(
      onPressed: enabled && !busy ? onTap : null,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: Tween<double>(begin: 0.8, end: 1).animate(animation),
                child: child,
              ),
              child: Icon(icon, key: ValueKey(icon), size: 20),
            ),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1).animate(animation),
              child: child,
            ),
            child: Text(
              '$count',
              key: ValueKey(count),
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Comment bottom sheet: the comment list for one post plus the
/// compose field. Counts refresh in the parent row when the sheet
/// closes. Own comments show a delete button; other users' comments
/// never do.
class _CommentSheet extends StatefulWidget {
  const _CommentSheet({
    required this.postId,
    required this.user,
    required this.repository,
  });

  final String postId;
  final AuthUser user;
  final PostInteractionRepository repository;

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final _controller = TextEditingController();
  List<PostComment> _comments = [];
  Map<String, CommentReactionState> _reactions = {};
  var _loading = true;
  String? _error;
  String? _fieldError;
  var _submitting = false;
  String? _deletingId;
  String? _reactingCommentId;

  /// Comment ids whose replies are currently expanded.
  final Set<String> _expanded = {};

  /// Comment being replied to, or null for a top-level comment.
  PostComment? _replyingTo;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final comments =
          await widget.repository.loadComments(widget.postId);
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loading = false;
      });
      // Reactions load separately and never block the comments:
      // on a shared post without published comment-reaction rules
      // this fails with a permission error, and the sheet still
      // shows every comment (reactions stay at zero and surface
      // the error only when tapped).
      try {
        final reactions =
            await widget.repository.loadCommentReactions(
          postId: widget.postId,
          uid: widget.user.uid,
        );
        if (!mounted) return;
        setState(() => _reactions = reactions);
      } catch (_) {
        if (!mounted) return;
        setState(() => _reactions = {});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = interactionErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final validation = commentValidationError(_controller.text);
    if (validation != null) {
      setState(() => _fieldError = validation);
      return;
    }
    setState(() {
      _submitting = true;
      _fieldError = null;
    });
    try {
      final replyingTo = _replyingTo;
      if (replyingTo != null) {
        await widget.repository.addReply(
          postId: widget.postId,
          parentCommentId: replyingTo.id,
          user: widget.user,
          text: _controller.text,
        );
        if (!mounted) return;
        setState(() {
          _replyingTo = null;
          _expanded.add(replyingTo.id);
        });
      } else {
        await widget.repository.addComment(
          postId: widget.postId,
          user: widget.user,
          text: _controller.text,
        );
      }
      _controller.clear();
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _fieldError = interactionErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _onCommentReaction(
    PostComment comment,
    PostReaction tapped,
  ) async {
    if (_reactingCommentId != null) return;
    setState(() => _reactingCommentId = comment.id);
    try {
      await widget.repository.setCommentReaction(
        postId: widget.postId,
        commentId: comment.id,
        user: widget.user,
        tapped: tapped,
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      TopPopup.show(context, message: interactionErrorMessage(e));
    } finally {
      if (mounted) setState(() => _reactingCommentId = null);
    }
  }

  Future<void> _delete(PostComment comment) async {
    setState(() => _deletingId = comment.id);
    try {
      await widget.repository.deleteComment(
        postId: widget.postId,
        commentId: comment.id,
        user: widget.user,
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      TopPopup.show(context, message: interactionErrorMessage(e));
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  /// One comment tile plus its action row and, when expanded, its
  /// replies. [node] carries the tree depth: depth-2 comments get
  /// no Reply button ([kMaxCommentDepth]).
  Widget _commentTile(CommentNode node) {
    final scheme = Theme.of(context).colorScheme;
    final comment = node.comment;
    final isOwn = comment.userId == widget.user.uid;
    final reaction = _reactions[comment.id];
    final likeCount = reaction?.likeCount ?? 0;
    final dislikeCount = reaction?.dislikeCount ?? 0;
    final myReaction = reaction?.myReaction;
    final expanded = _expanded.contains(comment.id);
    final children = node.children;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CommentAvatar(comment: comment),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          comment.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        formatCommentTime(comment.createdAt),
                        style: AppText.caption.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(comment.text),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: _ReactionButton(
                          icon: myReaction == PostReaction.like
                              ? Icons.thumb_up
                              : Icons.thumb_up_outlined,
                          label: 'Like',
                          count: likeCount,
                          selected: myReaction == PostReaction.like,
                          selectedColor: scheme.primary,
                          enabled: true,
                          busy: _reactingCommentId == comment.id,
                          onTap: () => _onCommentReaction(
                            comment,
                            PostReaction.like,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _ReactionButton(
                          icon: myReaction == PostReaction.dislike
                              ? Icons.thumb_down
                              : Icons.thumb_down_outlined,
                          label: 'Dislike',
                          count: dislikeCount,
                          selected:
                              myReaction == PostReaction.dislike,
                          selectedColor: const Color(0xFFEF4444),
                          enabled: true,
                          busy: _reactingCommentId == comment.id,
                          onTap: () => _onCommentReaction(
                            comment,
                            PostReaction.dislike,
                          ),
                        ),
                      ),
                      if (node.depth < kMaxCommentDepth)
                        TextButton.icon(
                          onPressed: () => setState(
                            () => _replyingTo = comment,
                          ),
                          icon: const Icon(Icons.reply, size: 18),
                          label: const Text('Reply'),
                        ),
                    ],
                  ),
                  if (children.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() {
                        if (expanded) {
                          _expanded.remove(comment.id);
                        } else {
                          _expanded.add(comment.id);
                        }
                      }),
                      child: Text(
                        expanded
                            ? 'Hide replies'
                            : 'View replies (${children.length})',
                      ),
                    ),
                ],
              ),
            ),
            if (isOwn)
              _deletingId == comment.id
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                      ),
                      tooltip: 'Delete comment',
                      onPressed: () => _delete(comment),
                    ),
          ],
        ),
        if (expanded && children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 8),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _commentTile(children[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roots = buildCommentTree(_comments);
    final replyingTo = _replyingTo;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Comments (${_comments.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: AppText.caption.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _reload,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : _comments.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'No comments yet. '
                                  'Be the first to comment.',
                                  textAlign: TextAlign.center,
                                  style: AppText.caption.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: roots.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, index) =>
                                  _commentTile(roots[index]),
                            ),
            ),
            const Divider(height: 1),
            if (replyingTo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Replying to @${replyingTo.displayName}',
                        style: AppText.caption.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Cancel reply',
                      onPressed: () =>
                          setState(() => _replyingTo = null),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      // No maxLength: overlong input must reach submit
                      // validation so the user sees why it is rejected
                      // (a capped field would silently truncate it).
                      // The 500-character cap is enforced on submit
                      // and again by the repository and the rules.
                      maxLines: 3,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: replyingTo != null
                            ? 'Write a reply…'
                            : 'Write a comment…',
                        errorText: _fieldError,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (_fieldError != null) {
                          setState(() => _fieldError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    tooltip: 'Send comment',
                    onPressed: _submitting ? null : _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Commenter avatar: the Google profile photo when the comment
/// carries one, otherwise an emerald initials circle. A photo that
/// fails to load falls back to initials (the child would otherwise
/// paint on top of the photo).
class _CommentAvatar extends StatefulWidget {
  const _CommentAvatar({required this.comment});

  final PostComment comment;

  @override
  State<_CommentAvatar> createState() => _CommentAvatarState();
}

class _CommentAvatarState extends State<_CommentAvatar> {
  var _photoFailed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photoUrl = widget.comment.photoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty && !_photoFailed) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: NetworkImage(photoUrl),
        onBackgroundImageError: (_, _) {
          if (mounted) setState(() => _photoFailed = true);
        },
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      child: Text(
        commentInitials(widget.comment.displayName),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
