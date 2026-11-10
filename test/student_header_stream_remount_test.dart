// Regression test for the Student Hub header stream (Nov 10, 2026):
// the header bell's notification stream used to be ONE cached
// single-subscription stream in the tab's state. When the ListView
// scrolled the header out of view and back in, the StreamBuilder
// remounted and re-listened to the same stream, throwing "Bad state:
// Stream has already been listened to" and leaving the header
// broken. The Watch demo tour's programmatic scrolling trips it on
// every auto-start; plain manual scrolling reproduces it too. The
// header now owns a fresh stream per mount (see _NotificationHeader
// in student_tab.dart), so scroll-out + scroll-back must be safe.
import 'package:estudyantego/features/app_review_notifications.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/student/student_theme.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single-subscription degrade path, exactly like the real
/// no-Firebase `watchForUser` (`Stream.value(...)`).
class _SingleSubscriptionRepo implements AppReviewNotificationRepository {
  @override
  Stream<List<AppReviewNotification>> watchForUser(String uid) =>
      Stream.value(const <AppReviewNotification>[]);
  @override
  Future<void> markAllRead(String uid) async {}
}

const _user = AuthUser(
  uid: 'uid-1',
  email: 'steven@example.com',
  displayName: 'Steven Reyes',
  emailVerified: true,
);

void main() {
  testWidgets('header survives scroll-out and scroll-back (remount)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        themeMode: ThemeMode.light,
        home: Scaffold(
          body: StudentHubTheme(
            child: StudentTab(
              user: _user,
              reviewNotificationRepository: _SingleSubscriptionRepo(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Student Hub'), findsOneWidget);

    // Scroll the header far out of view.
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('Student Hub'), findsNothing);

    // Scroll back up: the header remounts and re-subscribes.
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(find.text('Student Hub'), findsOneWidget);
  });
}
