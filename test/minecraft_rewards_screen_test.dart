// Widget tests for the Minecraft theme extension of the 7-Day
// Sign-in Details Page (lib/features/student/signin_screen.dart).
//
// Asserts the Minecraft styling (blocky MinecraftCard sections,
// MinecraftIconBadge headers, MinecraftXpBar, Baloo 2 headings,
// Press Start 2P chip accent, grass AppBar) AND that the live
// data still renders from seeded records — streak, points, day
// states, progress, and history entries. Every asserted value
// comes from seeded records; nothing hardcodes the UI's numbers.
// Dates are relative to today so the streak math holds on any
// run day.
import 'dart:convert';

import 'package:estudyantego/features/minecraft_theme.dart';
import 'package:estudyantego/features/student/signin_components.dart';
import 'package:estudyantego/features/student/signin_screen.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:estudyantego/features/student/student_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime _daysAgo(int n) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).subtract(Duration(days: n));
}

/// Seeds the legacy local check-in log: [days] are dayIndexes for
/// consecutive days ending [endOffset] days ago (0 = today).
Future<void> _seedLocal(List<int> days, {int endOffset = 0}) async {
  final records = <Map<String, dynamic>>[];
  for (var i = 0; i < days.length; i++) {
    final date = _daysAgo(endOffset + days.length - 1 - i);
    records.add(
      CheckinRecord(
        id: 'seed-$i',
        date: date,
        dayIndex: days[i],
        points: pointsForDay(days[i]),
      ).toJson(),
    );
  }
  SharedPreferences.setMockInitialValues({
    StudentStorage.checkinsKey: jsonEncode(records),
  });
}

/// Tall viewport so the full SigninScreen list builds.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Details page renders with Minecraft styling',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SigninScreen())),
    );
    await tester.pumpAndSettle();

    // Blocky Minecraft sections + icon badges + XP bar.
    expect(find.byType(MinecraftCard), findsWidgets);
    expect(find.byType(MinecraftIconBadge), findsWidgets);
    expect(find.byType(MinecraftXpBar), findsOneWidget);
    // Grass AppBar.
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, MinecraftColors.grassGreen);
    // Baloo 2 headings (AppBar title + hero title).
    final titles = tester.widgetList<Text>(find.text('7-Day Sign-in'));
    expect(titles, isNotEmpty);
    for (final title in titles) {
      expect(title.style?.fontFamily, startsWith('Baloo2'));
    }
    // Press Start 2P pixel accent on the Study Rewards chip.
    final chip = tester.widget<Text>(find.text('Study Rewards'));
    expect(chip.style?.fontFamily, startsWith('PressStart2P'));
    // Blocky card geometry: 3px ink border + hard shadow.
    final card = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('This Cycle'),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.border?.top.width, 3);
    expect(decoration.border?.top.color, MinecraftColors.ink);
    expect(decoration.boxShadow, [MinecraftShapes.cardShadow]);
  });

  testWidgets('Details page renders live data from seeded records',
      (tester) async {
    _tallScreen(tester);
    // Days 1-2 checked ending today: streak 2, 20 points.
    await _seedLocal([1, 2]);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SigninScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 days'), findsOneWidget);
    expect(find.text('20 pts'), findsOneWidget);
    expect(find.text('2 / 7 Days'), findsOneWidget);
    expect(find.text('Already checked in today'), findsOneWidget);
    expect(find.text('Resets in 5 days'), findsOneWidget);
    // XP bar fills the live fraction.
    final xpBar = tester.widget<MinecraftXpBar>(
      find.byType(MinecraftXpBar),
    );
    expect(xpBar.value, closeTo(2 / 7, 0.001));
    // Day tiles show the live per-day rewards (Day 7 is the gift).
    final tiles = find.byType(SigninDayTiles);
    expect(
      find.descendant(of: tiles, matching: find.text('Day 7')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tiles, matching: find.text('+50 pts')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tiles, matching: find.text('+10 pts')),
      findsNWidgets(6),
    );
    // History rows come from the seeded log only.
    final history = find.byKey(const ValueKey('signin-history'));
    expect(
      find.descendant(of: history, matching: find.text('Day 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: history, matching: find.text('Day 1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: history, matching: find.text('+10 pts')),
      findsNWidgets(2),
    );
  });

  testWidgets(
      'Day tiles keep the approved state colors in blocky form',
      (tester) async {
    _tallScreen(tester);
    // Days 1-2 checked, ending yesterday: today is Day 3, not yet
    // checked — D1 completed, D3 current, D7 upcoming gift.
    await _seedLocal([1, 2], endOffset: 1);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SigninScreen())),
    );
    await tester.pumpAndSettle();

    Container tile(String label) {
      return tester.widget<Container>(
        find
            .ancestor(
              of: find.descendant(
                of: find.byType(SigninDayTiles),
                matching: find.text(label),
              ),
              matching: find.byType(Container),
            )
            .first,
      );
    }

    // Completed Day 1: the approved light-green tile, now with a
    // 2.5px ink border and 8px blocky corners + Baloo 2 label.
    final day1 = tile('Day 1');
    final day1Decoration = day1.decoration! as BoxDecoration;
    expect(day1Decoration.color, kSigninLightGreen);
    expect(day1Decoration.border?.top.width, 2.5);
    expect(day1Decoration.border?.top.color, MinecraftColors.ink);
    expect(
      (day1Decoration.borderRadius! as BorderRadius)
          .topLeft
          .x,
      8,
    );
    final day1Label = tester.widget<Text>(
      find.descendant(
        of: find.byType(SigninDayTiles),
        matching: find.text('Day 1'),
      ),
    );
    expect(day1Label.style?.fontFamily, startsWith('Baloo2'));
    // Current Day 3: deep emerald; upcoming Day 7: pale gold gift.
    expect(
      (tile('Day 3').decoration! as BoxDecoration).color,
      kStudentEmerald,
    );
    expect(
      (tile('Day 7').decoration! as BoxDecoration).color,
      kSigninPaleGold,
    );
  });

  testWidgets('Minecraft check-in button still claims and locks',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SigninScreen())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check in today · Day 1'));
    await tester.pumpAndSettle();
    expect(find.text('Already checked in today'), findsOneWidget);
    expect(find.text('Check in today · Day 1'), findsNothing);
    expect(find.text('1 / 7 Days'), findsOneWidget);
    final history = find.byKey(const ValueKey('signin-history'));
    expect(
      find.descendant(of: history, matching: find.text('+10 pts')),
      findsOneWidget,
    );
    // Tapping the locked block must not create a second record.
    await tester.tap(find.text('Already checked in today'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: history, matching: find.text('+10 pts')),
      findsOneWidget,
    );
    expect(find.text('1 / 7 Days'), findsOneWidget);
  });
}
