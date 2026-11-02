// Widget tests for the 7-Day Sign-in page and dashboard card.
import 'package:estudyantego/features/student/signin_screen.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:estudyantego/features/student/student_theme.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Sign-in page checks in once, then blocks duplicates',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SigninScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Check in today · Day 1'), findsOneWidget);
    // The redesigned page is taller, so the history section sits
    // below the fold until scrolled into view; scroll back up
    // before tapping the button.
    await tester.scrollUntilVisible(
        find.text('No check-in history yet.'), 200);
    await tester.pumpAndSettle();
    expect(find.text('No check-in history yet.'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Check in today · Day 1'), -200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check in today · Day 1'));
    await tester.pumpAndSettle();
    expect(find.text('Already checked in today'), findsOneWidget);
    expect(find.text('Check in today · Day 1'), findsNothing);
    await tester.scrollUntilVisible(
        find.text(formatDate(DateTime.now())), 200);
    await tester.pumpAndSettle();
    expect(find.text(formatDate(DateTime.now())), findsOneWidget);
  });

  testWidgets('Dashboard sign-in card shows live streak state',
      (tester) async {
    tester.view.physicalSize = const Size(390, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: StudentTab())));
    await tester.pumpAndSettle();
    expect(find.text('7-Day Sign-in'), findsOneWidget);
    expect(find.text('Current Streak'), findsOneWidget);
    expect(find.text('0 days'), findsOneWidget);
    expect(find.text('Day 1 of 7'), findsOneWidget);
    expect(find.text('0 / 7 Days'), findsOneWidget);
    await tester.tap(find.text('7-Day Sign-in'));
    await tester.pumpAndSettle();
    expect(find.text('Check in today · Day 1'), findsOneWidget);
  });

  testWidgets('Student Hub uses its own light emerald theme', (tester) async {
    tester.view.physicalSize = const Size(390, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: StudentTheme(child: StudentTab()))));
    await tester.pumpAndSettle();
    expect(find.text('Student Hub'), findsOneWidget);
    final context = tester.element(find.byType(StudentTab));
    final theme = Theme.of(context);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF8FAFC));
    expect(theme.colorScheme.surface, const Color(0xFFFFFFFF));
    expect(theme.colorScheme.primary, const Color(0xFF14532D));
  });
}
