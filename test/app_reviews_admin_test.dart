// App Reviews (admin side) + reply notifications tests (Nov 9, 2026).
//
// Covers: summary math, star/topic/satisfied filters, review detail
// + admin reply thread, the Notifications sheet (entry + empty
// state + privacy), the bell badge, the Student Hub wiring (badge +
// section card + sheet + mark-as-read on close), and the top reply
// popup (appears only for replies that arrive while the app is
// open, auto-dismisses after 5 seconds, tapping opens the sheet).
// The Firestore repositories are replaced by in-memory fakes; the
// real Firestore batch (reply + notification) is not covered here —
// there is no Firestore emulator in the sandbox.

import 'dart:async';

import 'package:estudyantego/features/app_reply_popup.dart';
import 'package:estudyantego/features/app_review_detail_screen.dart';
import 'package:estudyantego/features/app_review_notifications.dart';
import 'package:estudyantego/features/app_reviews.dart';
import 'package:estudyantego/features/app_reviews_admin_screen.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/student/student_theme.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tall viewport so a full StudentTab list builds.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

AppRating _rating({
  required String id,
  required bool satisfied,
  int? stars,
  List<String> topics = const [],
  String comment = '',
  String? userId = 'student-1',
  List<AdminReply> adminReplies = const [],
}) {
  return AppRating(
    id: id,
    satisfied: satisfied,
    stars: stars,
    topics: topics,
    comment: comment,
    userId: userId,
    appVersion: '1.0.0+1',
    submittedAt: DateTime(2026, 11, 9),
    adminReplies: adminReplies,
  );
}

AppReviewNotification _notification({
  required String id,
  required String userId,
  required String replyText,
  int? stars,
  List<String> topics = const [],
  bool read = false,
}) {
  return AppReviewNotification(
    id: id,
    userId: userId,
    reviewId: 'r1',
    replyText: replyText,
    stars: stars,
    topics: topics,
    createdAt: DateTime(2026, 11, 9, 10, 30),
    read: read,
  );
}

/// In-memory stand-in for the Firestore admin repository. The
/// reply is appended to the rating in the list and re-emitted, so
/// the detail thread updates live — the same shape as the real
/// Firestore stream. Each stream call gets its own controller that
/// replays the current list immediately, so an update is never
/// lost to broadcast timing (the failure mode of an async*
/// generator yielding into a broadcast controller).
class _FakeAppReviewsRepository implements AppReviewsRepository {
  _FakeAppReviewsRepository(this.ratings);

  final List<AppRating> ratings;
  final List<({String text, String adminEmail})> replies = [];
  final _updates = StreamController<List<AppRating>>.broadcast();

  AppRating? _find(String id) {
    for (final rating in ratings) {
      if (rating.id == id) return rating;
    }
    return null;
  }

  Stream<List<AppRating>> _stream() {
    final controller = StreamController<List<AppRating>>();
    controller.add(List.of(ratings));
    final sub = _updates.stream.listen((list) {
      controller.add(List.of(list));
    });
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  @override
  Stream<List<AppRating>> watchAll() => _stream();

  @override
  Stream<AppRating?> watchOne(String ratingId) =>
      _stream().map((_) => _find(ratingId));

  @override
  Future<void> addReply({
    required AppRating rating,
    required String text,
    required String adminEmail,
  }) async {
    replies.add((text: text, adminEmail: adminEmail));
    final index = ratings.indexWhere((r) => r.id == rating.id);
    if (index >= 0) {
      final old = ratings[index];
      ratings[index] = AppRating(
        id: old.id,
        satisfied: old.satisfied,
        stars: old.stars,
        topics: old.topics,
        comment: old.comment,
        userId: old.userId,
        appVersion: old.appVersion,
        submittedAt: old.submittedAt,
        adminReplies: [
          ...old.adminReplies,
          AdminReply(
            text: text,
            adminEmail: adminEmail,
            createdAt: DateTime(2026, 11, 9, 11, 0),
          ),
        ],
      );
      _updates.add(List.of(ratings));
    }
  }
}

/// In-memory stand-in for the Firestore notification repository.
/// [addNotification] simulates a reply arriving while the app is
/// open (the admin replied): it pushes an update through the
/// stream, exactly as Firestore would. Each stream call gets its
/// own controller that replays the current list immediately, so
/// an update is never lost to broadcast timing.
class _FakeNotificationRepository
    implements AppReviewNotificationRepository {
  _FakeNotificationRepository(this.notifications);

  final List<AppReviewNotification> notifications;
  bool markAllReadCalled = false;
  final _updates =
      StreamController<List<AppReviewNotification>>.broadcast();

  Stream<List<AppReviewNotification>> _stream(String uid) {
    final controller = StreamController<List<AppReviewNotification>>();
    controller.add(
      notifications.where((n) => n.userId == uid).toList(),
    );
    final sub = _updates.stream.listen((list) {
      controller.add(list.where((n) => n.userId == uid).toList());
    });
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  @override
  Stream<List<AppReviewNotification>> watchForUser(String uid) =>
      _stream(uid);

  void addNotification(AppReviewNotification notification) {
    notifications.add(notification);
    _updates.add(List.of(notifications));
  }

  @override
  Future<void> markAllRead(String uid) async {
    markAllReadCalled = true;
    for (var i = 0; i < notifications.length; i++) {
      if (notifications[i].userId == uid && !notifications[i].read) {
        final old = notifications[i];
        notifications[i] = AppReviewNotification(
          id: old.id,
          userId: old.userId,
          reviewId: old.reviewId,
          replyText: old.replyText,
          stars: old.stars,
          topics: old.topics,
          createdAt: old.createdAt,
          read: true,
        );
      }
    }
    _updates.add(List.of(notifications));
  }
}

List<AppRating> _sampleRatings() {
  return [
    _rating(
      id: 'r1',
      satisfied: true,
      stars: 5,
      topics: const ['Fares'],
      comment: 'Great fares view',
      userId: 'student-1',
    ),
    _rating(
      id: 'r2',
      satisfied: true,
      stars: 3,
      topics: const ['Map & Routes'],
      comment: 'Map is okay',
      userId: 'student-2',
    ),
    _rating(
      id: 'r3',
      satisfied: false,
      stars: 1,
      topics: const ['Bugs & Crashes', 'Fares'],
      comment: 'App crashed',
      userId: 'student-1',
    ),
  ];
}

Future<void> _pumpAdminScreen(
  WidgetTester tester,
  AppReviewsRepository repository,
) async {
  // Tall viewport: the admin screen's summary + filters are fixed
  // height and the review list fills the rest — the default
  // 800x600 test viewport is shorter than a phone, so the list
  // collapses to zero height and no review is visible.
  _tallScreen(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppReviewsScreen(
          repository: repository,
          adminEmail: 'stevenjoereyes0625@gmail.com',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('App Reviews summary', () {
    testWidgets('shows average, total and Satisfied %',
        (WidgetTester tester) async {
      final repository = _FakeAppReviewsRepository(_sampleRatings());
      await _pumpAdminScreen(tester, repository);
      // Average (5 + 3 + 1) / 3 = 3.0; satisfied 2 of 3 = 67%.
      expect(find.text('3.0'), findsOneWidget);
      expect(find.text('67%'), findsOneWidget);
      expect(find.text('3 reviews'), findsOneWidget);
      // Distribution: one 5★, one 3★, one 1★ — each appears twice
      // (once in the star filter chip, once in the summary row).
      expect(find.text('5★'), findsNWidgets(2));
      expect(find.text('3★'), findsNWidgets(2));
      expect(find.text('1★'), findsNWidgets(2));
    });

    testWidgets('shows the empty state when there are no reviews',
        (WidgetTester tester) async {
      final repository = _FakeAppReviewsRepository([]);
      await _pumpAdminScreen(tester, repository);
      expect(find.textContaining('No reviews yet'), findsOneWidget);
    });
  });

  group('App Reviews filters', () {
    testWidgets('star filter shows only matching reviews',
        (WidgetTester tester) async {
      final repository = _FakeAppReviewsRepository(_sampleRatings());
      await _pumpAdminScreen(tester, repository);
      await tester.tap(find.widgetWithText(ChoiceChip, '5★'));
      await tester.pumpAndSettle();
      expect(find.text('Great fares view'), findsOneWidget);
      expect(find.text('Map is okay'), findsNothing);
      expect(find.text('App crashed'), findsNothing);
      expect(find.text('1 review'), findsOneWidget);
      // Back to All.
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      expect(find.text('3 reviews'), findsOneWidget);
    });

    testWidgets('topic filter shows only reviews with that topic',
        (WidgetTester tester) async {
      final repository = _FakeAppReviewsRepository(_sampleRatings());
      await _pumpAdminScreen(tester, repository);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      // The menu item is the last "Fares" — the review cards also
      // carry a "Fares" topic chip.
      await tester.tap(find.text('Fares').last);
      await tester.pumpAndSettle();
      expect(find.text('Great fares view'), findsOneWidget);
      expect(find.text('App crashed'), findsOneWidget);
      expect(find.text('Map is okay'), findsNothing);
    });

    testWidgets('satisfied filter shows only Not yet reviews',
        (WidgetTester tester) async {
      final repository = _FakeAppReviewsRepository(_sampleRatings());
      await _pumpAdminScreen(tester, repository);
      // Tap the "Not yet" segment label inside the SegmentedButton
      // (find.text alone is ambiguous — the review cards also carry
      // a "Not yet" badge).
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<bool?>),
          matching: find.text('Not yet'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('App crashed'), findsOneWidget);
      expect(find.text('Great fares view'), findsNothing);
      expect(find.text('Map is okay'), findsNothing);
    });
  });

  group('Review detail and admin reply', () {
    testWidgets('a sent reply appears in the thread',
        (WidgetTester tester) async {
      final repository = _FakeAppReviewsRepository(_sampleRatings());
      await _pumpAdminScreen(tester, repository);
      await tester.ensureVisible(find.text('Great fares view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Great fares view'));
      await tester.pumpAndSettle();
      expect(find.text('Admin replies'), findsOneWidget);
      expect(
        find.text(
          "No replies yet. Your reply will appear in the student's Notifications.",
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(TextField),
        'Thanks for the feedback!',
      );
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(find.text('Thanks for the feedback!'), findsOneWidget);
      expect(
        find.text(
          "No replies yet. Your reply will appear in the student's Notifications.",
        ),
        findsNothing,
      );
      expect(repository.replies, hasLength(1));
      expect(repository.replies.first.text, 'Thanks for the feedback!');
      expect(
        repository.replies.first.adminEmail,
        'stevenjoereyes0625@gmail.com',
      );
    });

    testWidgets('composer is disabled without an admin email',
        (WidgetTester tester) async {
      final repository = _FakeAppReviewsRepository(_sampleRatings());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppReviewDetailScreen(
              repository: repository,
              ratingId: 'r1',
              adminEmail: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sendButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.send),
      );
      expect(sendButton.onPressed, isNull);
    });
  });

  group('Notifications sheet', () {
    testWidgets('shows the reply entry with stars, topics and date',
        (WidgetTester tester) async {
      final repository = _FakeNotificationRepository([
        _notification(
          id: 'n1',
          userId: 'student-1',
          replyText: 'We fixed the crash — thanks!',
          stars: 1,
          topics: const ['Bugs & Crashes'],
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppReviewNotificationsSheet(
              repository: repository,
              userId: 'student-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('EstudyanteGO replied to your review.'),
        findsOneWidget,
      );
      expect(find.text('We fixed the crash — thanks!'), findsOneWidget);
      expect(find.text('Bugs & Crashes'), findsOneWidget);
      expect(find.text('Nov 9, 2026'), findsOneWidget);
      expect(find.text('No notifications yet.'), findsNothing);
    });

    testWidgets('shows the empty state when there are none',
        (WidgetTester tester) async {
      final repository = _FakeNotificationRepository([]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppReviewNotificationsSheet(
              repository: repository,
              userId: 'student-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No notifications yet.'), findsOneWidget);
      expect(
        find.text(
          'When EstudyanteGO replies to one of your reviews, it will appear here.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a student sees only their own notifications',
        (WidgetTester tester) async {
      final repository = _FakeNotificationRepository([
        _notification(
          id: 'n1',
          userId: 'student-1',
          replyText: 'We fixed the crash — thanks!',
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppReviewNotificationsSheet(
              repository: repository,
              userId: 'student-2',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('We fixed the crash — thanks!'), findsNothing);
      expect(find.text('No notifications yet.'), findsOneWidget);
    });
  });

  group('Bell badge', () {
    testWidgets('shows the unread count, hides at zero, caps at 9+',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: studentHeader(
              greetingName: 'Good Morning',
              onBell: () {},
              unreadNotifications: 2,
            ),
          ),
        ),
      );
      expect(find.text('2'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: studentHeader(
              greetingName: 'Good Morning',
              onBell: () {},
              unreadNotifications: 12,
            ),
          ),
        ),
      );
      expect(find.text('9+'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: studentHeader(
              greetingName: 'Good Morning',
              onBell: () {},
            ),
          ),
        ),
      );
      expect(find.text('2'), findsNothing);
      expect(find.text('9+'), findsNothing);
    });
  });

  group('Student Hub notifications wiring', () {
    testWidgets(
        'badge shows the reply; opening the sheet marks it read',
        (WidgetTester tester) async {
      // Very tall viewport: the Hub ListView only builds what is
      // in view — 6000px is not enough to reach the deep cards.
      tester.view.physicalSize = const Size(390, 15000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final repository = _FakeNotificationRepository([
        _notification(
          id: 'n1',
          userId: 'student-1',
          replyText: 'We fixed the crash — thanks!',
          stars: 1,
          topics: const ['Bugs & Crashes'],
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudentHubTheme(
              child: StudentTab(
                user: const AuthUser(
                  uid: 'student-1',
                  email: 'student@example.com',
                ),
                reviewNotificationRepository: repository,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Unread badge on the header bell.
      expect(
        find.byKey(const ValueKey('notification-badge')),
        findsOneWidget,
      );
      // The Notifications section card was removed Nov 9 at
      // Steven's request — the reply is no longer previewed on
      // the Hub itself; it reaches the student through the bell
      // badge, the top popup, and the Notifications sheet.
      expect(find.text('We fixed the crash — thanks!'), findsNothing);
      expect(find.text('1 unread'), findsNothing);
      expect(find.text('EstudyanteGO replied to your review.'),
          findsNothing);
      expect(find.text('Notifications'), findsNothing);
      // Tapping the bell opens the sheet with the full reply.
      // Scroll the header bell into view first, then tap the bell
      // icon itself.
      await tester.ensureVisible(
        find.byIcon(Icons.notifications_outlined).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.notifications_outlined).first);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      // The sheet entry shows the review's topics and date — this
      // proves the sheet (not a Hub card) is showing the reply.
      expect(find.text('We fixed the crash — thanks!'), findsOneWidget);
      expect(find.text('Bugs & Crashes'), findsOneWidget);
      expect(find.text('Nov 9, 2026'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      // Closing the sheet marks it read — the badge clears. The
      // sheet is a modal: tapping the scrim above it dismisses it
      // (pageBack needs an AppBar back button, which this screen
      // does not have).
      await tester.tapAt(const Offset(200, 100));
      await tester.pumpAndSettle();
      expect(repository.markAllReadCalled, isTrue);
      expect(
        find.byKey(const ValueKey('notification-badge')),
        findsNothing,
      );
    });
  });

  group('Reply top popup', () {
    Future<void> pumpOverlay(
      WidgetTester tester,
      _FakeNotificationRepository repository,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppReplyPopupOverlay(
            repository: repository,
            userId: 'student-1',
            child: const Scaffold(
              body: Center(child: Text('Home')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('appears when a new reply arrives while the app is open',
        (WidgetTester tester) async {
      final repository = _FakeNotificationRepository([]);
      await pumpOverlay(tester, repository);
      expect(
        find.text('EstudyanteGO replied to your review.'),
        findsNothing,
      );
      repository.addNotification(
        _notification(
          id: 'n1',
          userId: 'student-1',
          replyText: 'We fixed the crash — thanks!',
        ),
      );
      // Pump a short frame only — pumpAndSettle would fast-forward
      // past the 5-second popup (the drain animation completes and
      // the popup auto-dismisses), the same as the rating
      // "Thank you!" popup test.
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('EstudyanteGO replied to your review.'),
        findsOneWidget,
      );
      expect(find.text('We fixed the crash — thanks!'), findsOneWidget);
    });

    testWidgets(
        'does not appear for replies already waiting when the app opens',
        (WidgetTester tester) async {
      final repository = _FakeNotificationRepository([
        _notification(
          id: 'n1',
          userId: 'student-1',
          replyText: 'We fixed the crash — thanks!',
        ),
      ]);
      await pumpOverlay(tester, repository);
      expect(
        find.text('EstudyanteGO replied to your review.'),
        findsNothing,
      );
    });

    testWidgets('auto-dismisses after 5 seconds',
        (WidgetTester tester) async {
      final repository = _FakeNotificationRepository([]);
      await pumpOverlay(tester, repository);
      repository.addNotification(
        _notification(
          id: 'n1',
          userId: 'student-1',
          replyText: 'We fixed the crash — thanks!',
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('EstudyanteGO replied to your review.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(
        find.text('EstudyanteGO replied to your review.'),
        findsNothing,
      );
    });

    testWidgets(
        'tapping the popup opens the sheet and marks the reply read on close',
        (WidgetTester tester) async {
      final repository = _FakeNotificationRepository([]);
      await pumpOverlay(tester, repository);
      repository.addNotification(
        _notification(
          id: 'n1',
          userId: 'student-1',
          replyText: 'We fixed the crash — thanks!',
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.text('EstudyanteGO replied to your review.'),
      );
      await tester.pumpAndSettle();
      // The popup dismisses and the sheet opens with the full reply.
      expect(find.text('We fixed the crash — thanks!'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      // Tapping the scrim dismisses the sheet (pageBack needs an
      // AppBar back button, which this screen does not have).
      await tester.tapAt(const Offset(200, 100));
      await tester.pumpAndSettle();
      expect(repository.markAllReadCalled, isTrue);
      // The popup does not reappear after the reply is read.
      expect(
        find.text('EstudyanteGO replied to your review.'),
        findsNothing,
      );
    });
  });
}
