// Widget tests for the Feature 2 Minecraft restyle of the Student
// tab (Nov 10, 2026): the approved preview's HUD layout, XP-bar
// treatment, quest-card styling, grass/dirt motifs, and Baloo 2
// headings — with the tab's LIVE data, never the preview's sample
// numbers. Every asserted value comes from a seeded controller or
// seeded storage; a different seed must (and does) render a
// different value.
//
// What is NOT asserted here: the preview's sample numbers (1,240
// emeralds, 12-day streak, 5/5 hearts, Level 7, 340/500 XP, the 4
// preview quest rows) — none of those exist in the real tab. There
// is no hearts data and no level system; the HUD keeps the real
// Points / Free scans / Classes today, and the real progress bars
// (sign-in cycle, Walking Goal, budgets, savings) get the XP-bar
// treatment instead.
import 'dart:convert';

import 'package:estudyantego/features/minecraft_theme.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/points_wallet_repository.dart';
import 'package:estudyantego/features/student/signin_components.dart';
import 'package:estudyantego/features/student/student_data.dart';
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

DateTime _daysAgo(int n) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: n));
}

/// Seeds the legacy local check-in log: [days] are dayIndexes for
/// consecutive days ending [endOffset] days ago (0 = today).
Future<void> _seedLocalCheckins(List<int> days, {int endOffset = 0}) async {
  final records = <Map<String, dynamic>>[];
  for (var i = 0; i < days.length; i++) {
    final date = _daysAgo(endOffset + days.length - 1 - i);
    records.add(CheckinRecord(
      id: 'seed-$i',
      date: date,
      dayIndex: days[i],
      points: pointsForDay(days[i]),
    ).toJson());
  }
  SharedPreferences.setMockInitialValues({
    StudentStorage.checkinsKey: jsonEncode(records),
  });
}

/// Seeds one subject that meets today, so the HUD's live
/// "Classes today" count is 1 and the Classes card's total is 1.
void _seedOneSubjectToday() {
  final subject = Subject(
    id: 's1',
    name: 'Math',
    code: '',
    teacher: '',
    room: '',
    days: [DateTime.now().weekday],
    startMin: 480,
    endMin: 540,
    color: 0xFF16A34A,
  );
  SharedPreferences.setMockInitialValues({
    StudentStorage.subjectsKey: jsonEncode([subject.toJson()]),
  });
}

/// Minimal points repository with a fixed live balance.
class _FixedBalanceRepo implements PointsWalletRepository {
  _FixedBalanceRepo(this.balance);

  final int balance;

  @override
  Future<PointsWallet> fetchWallet(String uid) async =>
      PointsWallet(balance: balance, totalEarned: balance);

  @override
  Future<List<PointsTransaction>> fetchTransactions(String uid) async =>
      const [];

  @override
  Future<bool> claimSignin({
    required String uid,
    required String manilaDate,
    required int dayIndex,
    required int points,
  }) async =>
      false;

  @override
  Future<int> migrateSignin({
    required String uid,
    required List<CheckinRecord> records,
  }) async =>
      0;
}

/// The outermost Container decoration of the sign-in hub card.
BoxDecoration _signinCardDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byKey(const ValueKey('signin-hub-card')),
          matching: find.byType(Container),
        )
        .first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('HUD shows the live wallet balance, not a sample number',
      (tester) async {
    _tallScreen(tester);
    final controller = PointsWalletController(
      repository: _FixedBalanceRepo(350),
    );
    await controller.loadForUser('u1');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudentTab(
            user: const AuthUser(uid: 'u1', email: 'u1@example.com'),
            walletController: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Live balance 350 — the preview's 1,240 never appears.
    final points = tester.widget<Text>(
      find.byKey(const ValueKey('at-a-glance-points')),
    );
    expect(points.data, '350');
    expect(find.text('1,240'), findsNothing);
    // The other HUD stats are live too: 3/3 free scans by default.
    expect(find.text('Free scans'), findsOneWidget);
    expect(find.text('3/3'), findsOneWidget);
    // HUD values are Baloo 2.
    expect(points.style?.fontFamily, startsWith('Baloo2'));
  });

  testWidgets('HUD shows 0 points with no wallet controller',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StudentTab())),
    );
    await tester.pumpAndSettle();
    final points = tester.widget<Text>(
      find.byKey(const ValueKey('at-a-glance-points')),
    );
    expect(points.data, '0');
  });

  testWidgets('HUD classes-today count follows the real subjects',
      (tester) async {
    _tallScreen(tester);
    _seedOneSubjectToday();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StudentTab())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Classes today'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('total-subjects-count')))
          .data,
      '1',
    );
  });

  testWidgets(
      'Sections stay present and in order with Baloo 2 headings',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StudentTab())),
    );
    await tester.pumpAndSettle();
    // Group headers, top to bottom.
    final groupTops = <String, double>{};
    for (final title in [
      'Rewards & Goals',
      'Study',
      'Money',
      'Inspiration & Calendar',
    ]) {
      expect(find.text(title), findsOneWidget);
      groupTops[title] = tester.getTopLeft(find.text(title)).dy;
      final style =
          tester.widget<Text>(find.text(title)).style;
      expect(style?.fontFamily, startsWith('Baloo2'));
    }
    expect(groupTops['Rewards & Goals']! < groupTops['Study']!, isTrue);
    expect(groupTops['Study']! < groupTops['Money']!, isTrue);
    expect(groupTops['Money']! < groupTops['Inspiration & Calendar']!,
        isTrue);
    // Every section's content, same order as before the restyle.
    for (final title in [
      '7-Day Sign-in',
      'Rewards Center',
      'Walking Goal',
      'Classes & Timetable',
      'Allowance & Budgeting',
      'Bible Verse',
      'Daily Quotes',
      'School Calendar',
    ]) {
      expect(find.text(title), findsOneWidget);
      final style = tester.widget<Text>(find.text(title)).style;
      expect(style?.fontFamily, startsWith('Baloo2'));
    }
  });

  testWidgets(
      'Sign-in card uses the XP bar and a 3px blocky border',
      (tester) async {
    _tallScreen(tester);
    await _seedLocalCheckins([1, 2, 3]);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StudentTab())),
    );
    await tester.pumpAndSettle();
    // Live progress: 3 of 7 days, real streak, real points.
    expect(find.text('3 / 7 Days'), findsOneWidget);
    expect(find.text('Day 3 of 7'), findsOneWidget);
    final xpBar = find.descendant(
      of: find.byKey(const ValueKey('signin-hub-card')),
      matching: find.byType(MinecraftXpBar),
    );
    expect(xpBar, findsOneWidget);
    expect(tester.widget<MinecraftXpBar>(xpBar).value,
        closeTo(3 / 7, 0.001));
    // Blocky card: 3px ink border, white surface, hard shadow.
    final decoration = _signinCardDecoration(tester);
    expect(decoration.color, Colors.white);
    expect(decoration.border?.top.width, 3);
    expect(decoration.border?.top.color, MinecraftColors.ink);
    expect(decoration.boxShadow, [MinecraftShapes.cardShadow]);
  });

  testWidgets('Sign-in day tiles keep their approved colors',
      (tester) async {
    _tallScreen(tester);
    // Days 1-2 checked, ending yesterday: today is Day 3, not yet
    // checked — D1 completed, D3 current.
    await _seedLocalCheckins([1, 2], endOffset: 1);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StudentTab())),
    );
    await tester.pumpAndSettle();
    // D1 completed: light green tile; D3 current: deep emerald.
    // The restyle changes geometry + label font only — the state
    // colors are the approved ones.
    Container tile(String label) {
      return tester.widget<Container>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byType(Container),
            )
            .first,
      );
    }

    expect(
      (tile('D1').decoration! as BoxDecoration).color,
      kSigninLightGreen,
    );
    expect(
      (tile('D3').decoration! as BoxDecoration).color,
      kStudentEmerald,
    );
  });

  testWidgets('Watch demo button is the block button, same key',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StudentTab())),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('watch-demo-button')),
        findsOneWidget);
    expect(find.text('Watch demo'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Watch demo'),
        matching: find.byType(MinecraftBlockButton),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'Rewards Center and Walking Goal cards keep honest states',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StudentTab())),
    );
    await tester.pumpAndSettle();
    // Signed out: the honest signed-out state, not invented values.
    expect(
      find.text(
        'Sign in to see your points, credits, and redemption history.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('rewards-center')), findsOneWidget);
    // No step sensor under test: the honest no-sensor state.
    expect(find.byKey(const ValueKey('walking-hub-card')),
        findsOneWidget);
    expect(
      find.text('Step counting isn\'t available on this device.'),
      findsOneWidget,
    );
  });

  testWidgets('Header greeting uses Baloo 2 on the grass banner',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StudentTab())),
    );
    await tester.pumpAndSettle();
    final greeting = tester.widget<Text>(find.textContaining(', Steven!'));
    expect(greeting.style?.fontFamily, startsWith('Baloo2'));
    expect(find.text('Student Hub'), findsOneWidget);
  });

  testWidgets('Sign-in card keeps the dark surface in dark mode',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.dark,
        home: const Scaffold(
          body: StudentHubTheme(child: StudentTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final decoration = _signinCardDecoration(tester);
    expect(decoration.color, kStudentDarkCard);
    expect(decoration.border?.top.width, 1);
    expect(decoration.border?.top.color, MinecraftColors.darkBorder);
    // Day tiles keep their dark approved colors too.
    Container tile(String label) {
      return tester.widget<Container>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byType(Container),
            )
            .first,
      );
    }

    expect(
      (tile('D1').decoration! as BoxDecoration).color,
      kStudentEmeraldAccent,
    );
  });

  testWidgets('MinecraftXpBar fills the live fraction of its track',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: MinecraftXpBar(value: 0.5, animate: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The grass-stripe fill is the only Container with the XP
    // gradient; its outer width is the 97px fill (half the inner
    // track: 200 - 6px border) plus its 3px left margin.
    final fill = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).gradient ==
              MinecraftDecorations.xpBarFill.gradient,
    );
    expect(fill, findsOneWidget);
    expect(tester.getSize(fill).width, closeTo(100, 0.5));
  });

  testWidgets('blockCardFor is blocky in light, flat dark in dark',
      (tester) async {
    final light =
        MinecraftDecorations.blockCardFor(Brightness.light);
    expect(light.color, Colors.white);
    expect(light.border?.top.width, 3);
    expect(light.border?.top.color, MinecraftColors.ink);
    expect(light.boxShadow, [MinecraftShapes.cardShadow]);

    final dark = MinecraftDecorations.blockCardFor(Brightness.dark);
    expect(dark.color, MinecraftColors.darkCard);
    expect(dark.border?.top.width, 1);
    expect(dark.border?.top.color, MinecraftColors.darkBorder);
    expect(dark.boxShadow, isNull);
  });
}
