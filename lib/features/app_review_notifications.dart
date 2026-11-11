// App-review reply notifications — student side (Nov 9, 2026).
//
// When an admin replies to a student's review, a notification doc
// lands in Firestore `app_review_notifications` for that student
// (written by the admin reply flow in app_reviews.dart). The student
// sees it ONLY in the existing Notifications bottom sheet (bell in
// the Student Hub header) — there is no top banner, no white bar,
// no floating notification, and no push (in-app only, no FCM).
// The bell shows an unread badge count; tapping the bell opens the
// sheet. The sheet's empty state shows only when the student has
// no notifications.
//
// Privacy: a student reads ONLY their own notifications
// (userId == uid); the rules enforce it server-side. The query is
// a single `where('userId')` with client-side newest-first sort,
// so no composite Firestore index is needed.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_layout.dart';
import 'minecraft_theme.dart';
import 'student/student_data.dart';

/// One admin-reply notification for a student.
class AppReviewNotification {
  const AppReviewNotification({
    required this.id,
    required this.userId,
    required this.reviewId,
    required this.replyText,
    this.stars,
    required this.topics,
    this.createdAt,
    required this.read,
  });

  /// Firestore document id.
  final String id;

  /// Firebase UID of the student this notification is for.
  final String userId;

  /// The `app_ratings` doc the reply belongs to.
  final String reviewId;

  /// The admin's reply text.
  final String replyText;

  /// The review's stars (1–5), if the student gave any.
  final int? stars;

  /// The review's improve topics.
  final List<String> topics;

  /// Server timestamp of the reply (null while pending).
  final DateTime? createdAt;

  /// True once the student has seen the sheet.
  final bool read;

  factory AppReviewNotification.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final starsValue = data['stars'];
    final createdAt = data['createdAt'];
    return AppReviewNotification(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      reviewId: data['reviewId'] as String? ?? '',
      replyText: data['replyText'] as String? ?? '',
      stars: starsValue is num ? starsValue.toInt() : null,
      topics: (data['topics'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
      read: data['read'] as bool? ?? false,
    );
  }
}

/// Reads a student's reply notifications and marks them read.
/// Swappable so widget tests can use a fake.
abstract class AppReviewNotificationRepository {
  /// The student's notifications, newest first, live.
  Stream<List<AppReviewNotification>> watchForUser(String uid);

  /// Marks all of the student's notifications read.
  Future<void> markAllRead(String uid);
}

/// Firestore `app_review_notifications` implementation.
///
/// Lazy on purpose (same pattern as FirestorePointsWalletRepository):
/// constructing the repo never touches Firebase — the instance is
/// resolved only when a read/write actually runs. The shell builds
/// this repo on every launch, and widget tests don't initialize
/// Firebase, so an eager `FirebaseFirestore.instance` in the
/// constructor throws [core/no-app] and breaks the whole shell.
/// Reads also degrade to an empty stream when Firebase isn't
/// initialized, so the bell/sheet just show the honest empty state.
class FirestoreAppReviewNotificationRepository
    implements AppReviewNotificationRepository {
  /// Lazy — resolved only when a read/write actually runs, so
  /// constructing the repo in the shell build never touches
  /// Firebase (widget tests don't initialize it).
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  Stream<List<AppReviewNotification>> watchForUser(String uid) {
    try {
      // Single where only (no orderBy) — no composite index needed;
      // newest first is done client-side below.
      return _db
          .collection('app_review_notifications')
          .where('userId', isEqualTo: uid)
          .snapshots()
          .map((snap) {
        final list =
            snap.docs.map(AppReviewNotification.fromDoc).toList();
        list.sort((a, b) {
          final aTime = a.createdAt;
          final bTime = b.createdAt;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });
        return list;
      });
    } on FirebaseException {
      // Firebase not initialized (widget tests): no data to watch.
      return Stream.value(const <AppReviewNotification>[]);
    }
  }

  @override
  Future<void> markAllRead(String uid) async {
    try {
      final snap = await _db
          .collection('app_review_notifications')
          .where('userId', isEqualTo: uid)
          .get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        if (doc.data()['read'] != true) {
          batch.update(doc.reference, <String, dynamic>{'read': true});
        }
      }
      await batch.commit();
    } on FirebaseException {
      // Firebase not initialized (widget tests): nothing to mark.
      return;
    }
  }
}

/// The Notifications bottom-sheet content (the existing sheet the
/// Student Hub bell opens). Shows the student's reply
/// notifications, newest first; the honest empty state shows only
/// when there are none. When [repository] or [userId] is null
/// (Firebase not configured / signed out), the empty state shows.
class AppReviewNotificationsSheet extends StatefulWidget {
  const AppReviewNotificationsSheet({
    super.key,
    required this.repository,
    required this.userId,
  });

  final AppReviewNotificationRepository? repository;
  final String? userId;

  @override
  State<AppReviewNotificationsSheet> createState() =>
      _AppReviewNotificationsSheetState();
}

class _AppReviewNotificationsSheetState
    extends State<AppReviewNotificationsSheet> {
  /// The notifications stream, created once — never in build, or
  /// every rebuild would resubscribe and re-emit.
  Stream<List<AppReviewNotification>>? _notificationsStream;

  @override
  void initState() {
    super.initState();
    final repository = widget.repository;
    final userId = widget.userId;
    if (repository != null && userId != null) {
      _notificationsStream = repository.watchForUser(userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final userId = widget.userId;
    if (repository == null || userId == null) {
      return const _NotificationsEmptyState();
    }
    return StreamBuilder<List<AppReviewNotification>>(
      stream: _notificationsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: AppLayout.pagePaddingLarge,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notifications', style: AppText.headingStrong),
                SizedBox(height: AppSpacing.s8),
                Text("Couldn't load your notifications. Try again."),
              ],
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: AppLayout.pagePaddingLarge,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final notifications = snapshot.data ?? const <AppReviewNotification>[];
        if (notifications.isEmpty) {
          return const _NotificationsEmptyState();
        }
        return ListView(
          shrinkWrap: true,
          padding: AppLayout.pagePaddingLarge,
          children: [
            const Text('Notifications', style: AppText.headingStrong),
            const SizedBox(height: AppSpacing.s12),
            for (final notification in notifications)
              _NotificationEntry(notification: notification),
          ],
        );
      },
    );
  }
}

/// The honest empty state: "No notifications yet." — shown only
/// when the student has no reply notifications.
class _NotificationsEmptyState extends StatelessWidget {
  const _NotificationsEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: AppLayout.pagePaddingLarge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notifications', style: AppText.headingStrong),
          SizedBox(height: AppSpacing.s8),
          Text('No notifications yet.'),
          SizedBox(height: AppSpacing.s4),
          Text(
            'When EstudyanteGO replies to one of your reviews, it will appear here.',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

/// One reply notification: "EstudyanteGO replied to your review."
/// + the reply text + the review's stars/topics + date + an unread
/// dot (filled while unread, so the student can tell at a glance).
class _NotificationEntry extends StatelessWidget {
  const _NotificationEntry({required this.notification});

  final AppReviewNotification notification;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final createdAt = notification.createdAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: notification.read
                    ? Colors.transparent
                    : scheme.primary,
                border: notification.read
                    ? Border.all(color: scheme.outline)
                    : null,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EstudyanteGO replied to your review.',
                  style: AppText.labelStrong,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(notification.replyText, style: AppText.body),
                const SizedBox(height: AppSpacing.s8),
                if (notification.stars != null ||
                    notification.topics.isNotEmpty)
                  Wrap(
                    spacing: AppSpacing.s4,
                    runSpacing: AppSpacing.s4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (notification.stars != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 1; i <= 5; i++)
                              Icon(
                                i <= notification.stars!
                                    ? Icons.star
                                    : Icons.star_border,
                                color: MinecraftColors.gold,
                                size: 16,
                              ),
                          ],
                        ),
                      for (final topic in notification.topics)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(topic, style: AppText.small),
                        ),
                    ],
                  ),
                if (createdAt != null) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    formatDate(createdAt),
                    style: AppText.caption,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
