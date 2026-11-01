// Tests for the Student Hub dashboard and its data helpers.
//
// Dashboard rule: every summary line comes from real on-device data
// (a zero balance is shown as ₱0, never an invented amount); module
// cards open real screens.
import 'package:byahetayo/features/friends_tab.dart';
import 'package:byahetayo/features/student_tab.dart';
import 'package:byahetayo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  setUp(() {
    // The full-app test boots through the first-time gate, so
    // onboarding is already done here. Direct-tab tests ignore it.
    SharedPreferences.setMockInitialValues({
      'byahetayo_onboarding_done': true,
    });
  });

  testWidgets('Student Hub dashboard shows all 7 modules, honest data',
      (tester) async {
    tester.view.physicalSize = const Size(390, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(const StudentTab()));
    await tester.pumpAndSettle();
    expect(find.text('Student Hub'), findsOneWidget);
    expect(find.text('Allowance & Budgeting'), findsOneWidget);
    expect(find.text('Classes & Timetable'), findsOneWidget);
    expect(find.text('Review Notes & Quizzes'), findsOneWidget);
    expect(find.text('My Commute'), findsOneWidget);
    expect(find.text('Daily Quotes'), findsOneWidget);
    expect(find.text('Bible Verse'), findsOneWidget);
    // The dashboard attendance card was retitled 'School Calendar'
    // (landscape spec); its attendance content is preserved inside,
    // and the Attendance screen stays reachable via quick access.
    expect(find.text('School Calendar'), findsOneWidget);
    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('Church Directory'), findsOneWidget);
    expect(find.text('Tasks & Assignments'), findsOneWidget);
    expect(find.text('Student Profile'), findsOneWidget);
    expect(
        find.text(
            'Catholic churches across Northern Luzon, loaded live on the Map.'),
        findsOneWidget);
    expect(find.text('No pending tasks.'), findsOneWidget);
    // Real zero state, not an invented amount.
    expect(find.text('Available Balance'), findsOneWidget);
    expect(find.textContaining('₱0'), findsWidgets);
    expect(find.text('No classes today.'), findsOneWidget);
    expect(
        find.textContaining('Saved routes are shared with the Map tab.'),
        findsOneWidget);
    expect(find.text('No recent study activity.'), findsOneWidget);
  });

  testWidgets('Student profile card jumps to the Account tab',
      (tester) async {
    var called = false;
    tester.view.physicalSize = const Size(390, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        wrap(StudentTab(onViewAccount: () => called = true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View Account'));
    expect(called, isTrue);
  });

  testWidgets('Student Hub cards stack in one column even at 800px wide',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(const StudentTab()));
    await tester.pumpAndSettle();
    // Stacked, not side by side: the CARDS share a left edge and
    // the Bible card sits below the Sign-in card. (The title texts
    // themselves have different offsets from their leading icons.)
    final signinCard = find.ancestor(
      of: find.text('7-Day Sign-in'),
      matching: find.byType(Card),
    );
    final bibleCard = find.ancestor(
      of: find.text('Bible Verse'),
      matching: find.byType(Card),
    );
    final signinTopLeft = tester.getTopLeft(signinCard);
    final bibleTopLeft = tester.getTopLeft(bibleCard);
    expect(bibleTopLeft.dx, signinTopLeft.dx);
    expect(bibleTopLeft.dy, greaterThan(signinTopLeft.dy));
  });

  testWidgets('Student module card opens its screen', (tester) async {
    tester.view.physicalSize = const Size(390, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(const StudentTab()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allowance & Budgeting'));
    await tester.pumpAndSettle();
    expect(find.text('Available balance'), findsOneWidget);
  });

  testWidgets('Friends tab shows premium sections and honest empty states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(const FriendsTab()));
    await tester.pumpAndSettle();
    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('My Friends'), findsOneWidget);
    expect(find.text('No friends yet'), findsOneWidget);
    // The code is now real: generated on-device with a real QR.
    expect(find.text('My Friend Code'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Friend Requests'), findsOneWidget);
    expect(find.text('No incoming requests'), findsOneWidget);
    expect(find.text('No outgoing requests'), findsOneWidget);
    // Chats shows directly: the Posts/Chat toggle left with the
    // community content, which now lives in the Communities tab.
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('No conversations yet'), findsOneWidget);
    // No fake request actions, no fake presence.
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);
    expect(find.text('Community'), findsNothing);
    expect(find.text('Share info'), findsNothing);
    expect(
      find.text('Know something that can help commuters?'),
      findsNothing,
    );
    expect(find.text('No announcements or posts yet.'), findsNothing);
  });

  testWidgets('Add Friend shows the share path, creates no fake friend', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(const FriendsTab()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Friend'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('no code entry is offered here'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('No friends yet'), findsOneWidget);
  });

  testWidgets('Student Hub uses its own light emerald theme even when the app is dark',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ByaheTayoApp(initialThemeMode: ThemeMode.dark),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Student', skipOffstage: true));
    await tester.pumpAndSettle();
    expect(find.text('Student Hub', skipOffstage: true), findsOneWidget);
    final context = tester.element(find.byType(StudentTab));
    final theme = Theme.of(context);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF8FAFC));
    expect(theme.colorScheme.surface, const Color(0xFFFFFFFF));
    expect(theme.colorScheme.primary, const Color(0xFF14532D));
    expect(theme.colorScheme.outline, const Color(0xFFE2E8F0));
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
