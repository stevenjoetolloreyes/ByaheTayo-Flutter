// App Reviews — admin side (Nov 9, 2026).
//
// Reads the student ratings in Firestore `app_ratings` (written by
// the student-side "Rate this EstudyanteGO App" flow) and lets an
// admin reply. Admin-only: the screen is gated by the allowlist
// (admin_access.dart) and Firestore rules enforce it server-side.
//
// A reply is appended to the rating doc's `adminReplies` array
// ({text, adminEmail, createdAt}) AND creates a notification doc
// in `app_review_notifications` for the review's author (when the
// review has a user id), so the student sees it in their
// Notifications sheet. Both writes go in one batch, so a reply
// never lands without its notification (and vice versa).
//
// Privacy: a student never reads `app_ratings` — only the author
// (via their own notification) and admins. The rules enforce that.

import 'package:cloud_firestore/cloud_firestore.dart';

/// One admin reply on a rating (part of the rating doc's
/// `adminReplies` array — the Admin comments thread).
class AdminReply {
  const AdminReply({
    required this.text,
    required this.adminEmail,
    this.createdAt,
  });

  final String text;
  final String adminEmail;
  final DateTime? createdAt;

  factory AdminReply.fromMap(Map<String, dynamic> map) {
    final createdAt = map['createdAt'];
    return AdminReply(
      text: map['text'] as String? ?? '',
      adminEmail: map['adminEmail'] as String? ?? '',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'text': text,
      'adminEmail': adminEmail,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

/// One student rating, as stored in Firestore `app_ratings`.
/// Defensive parsing: a missing or mistyped field falls back to a
/// safe default instead of crashing the admin list.
class AppRating {
  const AppRating({
    required this.id,
    required this.satisfied,
    this.stars,
    required this.topics,
    required this.comment,
    required this.userId,
    required this.appVersion,
    this.submittedAt,
    required this.adminReplies,
  });

  /// Firestore document id.
  final String id;

  /// True = "Yes, satisfied", false = "Not yet".
  final bool satisfied;

  /// 1–5 when the student picked stars; null when they sent from
  /// the "Not yet" path without rating.
  final int? stars;

  /// Improve topics the student picked (may be empty).
  final List<String> topics;

  /// Optional free-text comment (may be empty).
  final String comment;

  /// Firebase UID of the author, or null when the student was not
  /// signed in. Shown to the admin only as "Student" — never a
  /// name, for privacy.
  final String? userId;

  /// App version at submission time (e.g. "1.0.0+1").
  final String appVersion;

  /// Server timestamp of the submission (null while pending).
  final DateTime? submittedAt;

  /// Admin replies, oldest first as stored.
  final List<AdminReply> adminReplies;

  int get replyCount => adminReplies.length;

  factory AppRating.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final starsValue = data['stars'];
    final submittedAt = data['submittedAt'];
    final repliesValue = data['adminReplies'];
    return AppRating(
      id: doc.id,
      satisfied: data['satisfied'] as bool? ?? false,
      stars: starsValue is num ? starsValue.toInt() : null,
      topics: (data['topics'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(),
      comment: data['comment'] as String? ?? '',
      userId: data['userId'] as String?,
      appVersion: data['appVersion'] as String? ?? '',
      submittedAt: submittedAt is Timestamp ? submittedAt.toDate() : null,
      adminReplies: (repliesValue as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AdminReply.fromMap)
          .toList(),
    );
  }
}

/// Reads ratings and posts admin replies. Swappable so widget tests
/// can use a fake instead of the real backend.
abstract class AppReviewsRepository {
  /// All ratings, newest first, live.
  Stream<List<AppRating>> watchAll();

  /// One rating by id, live (null when the doc is gone).
  Stream<AppRating?> watchOne(String ratingId);

  /// Appends a reply to the rating's thread AND creates the
  /// student's notification (when the review has an author).
  Future<void> addReply({
    required AppRating rating,
    required String text,
    required String adminEmail,
  });
}

/// Firestore `app_ratings` + `app_review_notifications`
/// implementation.
///
/// Lazy on purpose (same pattern as FirestorePointsWalletRepository):
/// constructing the repo never touches Firebase — the instance is
/// resolved only when a read/write actually runs. The shell builds
/// a repo on every launch, and widget tests don't initialize
/// Firebase, so an eager `FirebaseFirestore.instance` in the
/// constructor throws [core/no-app]. Reads degrade to an empty
/// stream when Firebase isn't initialized; `addReply` lets the
/// write error surface so the composer shows its honest error.
class FirestoreAppReviewsRepository implements AppReviewsRepository {
  /// Lazy — resolved only when a read/write actually runs, so
  /// constructing the repo never touches Firebase (widget tests
  /// don't initialize it).
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  Stream<List<AppRating>> watchAll() {
    try {
      return _db
          .collection('app_ratings')
          .orderBy('submittedAt', descending: true)
          .snapshots()
          .map((snap) => snap.docs.map(AppRating.fromDoc).toList());
    } on FirebaseException {
      // Firebase not initialized (widget tests): no data to watch.
      return Stream.value(const <AppRating>[]);
    }
  }

  @override
  Stream<AppRating?> watchOne(String ratingId) {
    try {
      return _db
          .collection('app_ratings')
          .doc(ratingId)
          .snapshots()
          .map((doc) => doc.exists ? AppRating.fromDoc(doc) : null);
    } on FirebaseException {
      // Firebase not initialized (widget tests): no review to watch.
      return Stream.value(null);
    }
  }

  @override
  Future<void> addReply({
    required AppRating rating,
    required String text,
    required String adminEmail,
  }) async {
    final reply = AdminReply(text: text, adminEmail: adminEmail);
    final batch = _db.batch();
    batch.update(
      _db.collection('app_ratings').doc(rating.id),
      <String, dynamic>{
        'adminReplies': FieldValue.arrayUnion([reply.toMap()]),
      },
    );
    final userId = rating.userId;
    if (userId != null && userId.isNotEmpty) {
      batch.set(
        _db.collection('app_review_notifications').doc(),
        <String, dynamic>{
          'userId': userId,
          'reviewId': rating.id,
          'replyText': text,
          'stars': rating.stars,
          'topics': rating.topics,
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
        },
      );
    }
    await batch.commit();
  }
}
