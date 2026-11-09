// Tests for the Student Hub dashboard and its data helpers.
//
// Dashboard rule: every summary line comes from real on-device data
// (a zero balance is shown as ₱0, never an invented amount); module
// cards open real screens.
import 'package:estudyantego/features/friends_tab.dart';
import 'package:estudyantego/features/student/student_theme.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:estudyantego/features/top_nav.dart';
import 'package:estudyantego/main.dart';
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
    SharedPreferences.setMockInitialValues({'byahetayo_onboarding_done': true});
  });

  testWidgets('Student Hub dashboard shows all 6 modules, honest data', (
    tester,
  ) async {
    // Tall viewport: the redesigned Hub (group headers, at-a-glance
    // card, week grid, Google Tasks card, allowance charts) is
    // taller than the old layout, and the ListView only builds
    // on-screen items.
    tester.view.physicalSize = const Size(390, 10000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(const StudentTab()));
    await tester.pumpAndSettle();
    expect(find.text('Student Hub'), findsOneWidget);
    expect(find.text('Allowance & Budgeting'), findsOneWidget);
    expect(find.text('Classes & Timetable'), findsOneWidget);
    // The Review Notes & Quizzes card was removed Nov 8 at Steven's
    // request — it must not render anymore (the Review screen itself
    // stays reachable via the Notes segmented control's Review segment).
    expect(find.text('Review Notes & Quizzes'), findsNothing);
    // The Commute section was removed Nov 9 at Steven's request
    // — it must not render anymore (the Commute screen itself
    // stays in the codebase).
    expect(find.text('My Commute'), findsNothing);
    expect(find.text('Daily Quotes'), findsOneWidget);
    expect(find.text('Bible Verse'), findsOneWidget);
    // The dashboard attendance card was retitled 'School Calendar'
    // (landscape spec); its attendance content is preserved inside.
    // The Quick Buttons section was removed Nov 5, so no 'Attendance'
    // tile remains on the Hub and the Attendance screen has no Hub
    // entry point anymore.
    expect(find.text('School Calendar'), findsOneWidget);
    expect(find.text('Attendance'), findsNothing);
    // The Tasks & Assignments and Upcoming cards were removed Nov 8
    // at Steven's request — they must not render anymore.
    expect(find.text('Tasks & Assignments'), findsNothing);
    expect(find.text('No pending tasks.'), findsNothing);
    expect(find.text('Upcoming'), findsNothing);
    // Real zero state, not an invented amount.
    expect(find.text('Available Balance'), findsOneWidget);
    expect(find.textContaining('₱0'), findsWidgets);
    // No subjects are seeded here, but the mock Google Calendar
    // sync seeds its sample events on first load, so the Today
    // list shows them instead of the "No classes today." empty
    // state (that state only appears when the Google list is
    // explicitly stored empty).
    expect(find.text('No classes today.'), findsNothing);
    expect(
      find.text('Thu · 3:00 PM–4:30 PM · Discrete Mathematics'),
      findsOneWidget,
    );
    // The "Saved routes are shared with the Map tab." note lived
    // in the removed Commute section — it no longer renders on
    // the Hub (the Commute screen itself still has it).
    expect(
      find.textContaining('Saved routes are shared with the Map tab.'),
      findsNothing,
    );
    // 'No recent study activity.' was the removed Review card's empty
    // state — gone with the card (Nov 8).
    expect(find.text('No recent study activity.'), findsNothing);
  });

  testWidgets('Student Hub cards stack in one column even at 800px wide', (
    tester,
  ) async {
    // Height 6000: the redesigned Hub is taller, and the ListView
    // only builds on-screen cards — the width assertion needs the
    // Bible card built too.
    tester.view.physicalSize = const Size(800, 6000);
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
    expect(find.text('Know something that can help commuters?'), findsNothing);
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

  testWidgets(
    'Student Hub follows Dark Mode with charcoal cards when the app is dark',
    (tester) async {
      // Nov 2 Dark Mode polish: the old rule ("Hub keeps its light
      // emerald theme even when the app is dark") is superseded — the
      // Hub tab now follows Dark Mode with the charcoal student
      // theme. Module screens opened from it still keep the light
      // StudentTheme wrapper (their approved light design).
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const EstudyanteGOApp(initialThemeMode: ThemeMode.dark),
      );
      // Anime splash (Nov 7): one master animation drives the whole
      // ~4.9 s intro, so a single settle carries it to the handoff.
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('top-nav-item-Student')));
      await tester.pumpAndSettle();
      expect(find.text('Student Hub', skipOffstage: true), findsOneWidget);
      final context = tester.element(find.byType(StudentTab));
      final theme = Theme.of(context);
      expect(theme.scaffoldBackgroundColor, kStudentDarkBg);
      expect(theme.colorScheme.surface, kStudentDarkCard);
      expect(theme.colorScheme.primary, kStudentEmeraldAccent);
      expect(theme.colorScheme.outline, kStudentDarkBorder);
      expect(find.byType(TopNavBar), findsOneWidget);
    },
  );

  testWidgets(
    'Student Hub removals (Nov 9): no Commute, no Add school, '
    'no Subject breakdown, no Monthly report',
    (tester) async {
      // Nov 9, 2026: Steven asked to remove the Commute section,
      // the Add school chip, and the Subject breakdown / Monthly
      // report donuts from the Hub. The School Calendar itself
      // stays. (Nov 10: the calendar card gained an Edit button,
      // a day-detail line, and a Coming up list below it whose
      // rows carry type pills — so the bare word "Holiday" now
      // appears more than once on the Hub, and the legend
      // assertion below is scoped to the card itself.) The
      // Review ring + gauge left with the Review Notes & Quizzes
      // card, removed Nov 8 at Steven's request.
      tester.view.physicalSize = const Size(390, 10000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(wrap(const StudentTab()));
      await tester.pumpAndSettle();
      // Review card: gone with the card (Nov 8).
      expect(find.text('Learning Progress'), findsNothing);
      expect(find.text('0%'), findsNothing);
      expect(find.text('Average score'), findsNothing);
      expect(find.text('No quizzes taken'), findsNothing);
      expect(find.text('Quizzes this week'), findsNothing);
      expect(find.text('0 of 0 completed'), findsNothing);
      // Commute section: gone (Nov 9).
      expect(find.text('My Commute'), findsNothing);
      expect(find.text('Routes'), findsNothing);
      expect(find.text('0 Trips this week'), findsNothing);
      // Calendar: legend stays, Add school chip is gone (Nov 9).
      expect(find.text('School Calendar'), findsOneWidget);
      expect(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('School Calendar'),
                matching: find.byType(Card),
              )
              .first,
          matching: find.text('Holiday'),
        ),
        findsOneWidget,
      );
      expect(find.text('Add school'), findsNothing);
      expect(find.text('Holidays this month'), findsNothing);
      expect(find.textContaining('No school saved'), findsNothing);
      // Subject breakdown + Monthly report donuts: gone (Nov 9).
      expect(find.text('Subject breakdown'), findsNothing);
      expect(find.text('0 Subjects'), findsNothing);
      expect(find.text('0 Records'), findsNothing);
      expect(find.text('Monthly report'), findsNothing);
      expect(find.text('0.0%'), findsNothing);
      expect(find.text('Present'), findsNothing);
      expect(find.text('Absent'), findsNothing);
    },
  );
}
