// Widget tests for Feature 1 of the Classes + menu build (Nov 10,
// 2026): the round + button on the Classes & Timetable screen and
// its floating spring menu (Set Schedule Manual / Files / Google
// Schedule). Covers open/close, tap-outside, option taps with no
// callback wired yet (just close), reduced motion, and that the
// menu never alters the existing lists.
import 'dart:convert';

import 'package:estudyantego/features/student/classes_plus_menu.dart';
import 'package:estudyantego/features/student/classes_screen.dart';
import 'package:estudyantego/features/student/google_events.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Subject _subject() => Subject(
  id: 's1',
  name: 'Coding',
  code: 'CS101',
  teacher: '',
  room: '',
  days: const [1, 2, 3, 4, 5, 6, 7],
  startMin: 8 * 60,
  endMin: 9 * 60,
  color: 0xFF16A34A,
);

Future<void> _pumpScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    StudentStorage.subjectsKey: jsonEncode([_subject().toJson()]),
    StudentStorage.assignmentsKey: jsonEncode([
      AssignmentItem(
        id: 'a1',
        subjectId: 's1',
        title: 'Homework 1',
        kind: 'assignment',
        due: DateTime.now().add(const Duration(days: 1)),
        done: false,
      ).toJson(),
    ]),
    // Explicit empty list so the mock Google sample set is not
    // seeded into this test's lists.
    googleEventsKey: jsonEncode([]),
  });
  await tester.pumpWidget(const MaterialApp(home: ClassesScreen()));
  await tester.pumpAndSettle();
}

Finder get _fab => find.byKey(const Key('classes-plus-fab'));
Finder get _menu => find.byKey(const Key('classes-plus-menu'));

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(_fab);
  await tester.pumpAndSettle();
  expect(_menu, findsOneWidget);
}

void main() {
  testWidgets('tapping + opens the menu with all three options in order', (
    tester,
  ) async {
    await _pumpScreen(tester);

    expect(_menu, findsNothing);
    await tester.tap(_fab);
    await tester.pumpAndSettle();

    expect(_menu, findsOneWidget);
    expect(find.text('Set Schedule Manual'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Google Schedule'), findsOneWidget);
    // Menu order: manual, files, google (top to bottom).
    final manualY = tester.getTopLeft(find.text('Set Schedule Manual')).dy;
    final filesY = tester.getTopLeft(find.text('Files')).dy;
    final googleY = tester.getTopLeft(find.text('Google Schedule')).dy;
    expect(manualY < filesY, isTrue);
    expect(filesY < googleY, isTrue);
    // The old "+ Add subject" pill is gone.
    expect(find.text('Add subject'), findsNothing);
  });

  testWidgets('tapping the x closes the menu', (tester) async {
    await _pumpScreen(tester);
    await _openMenu(tester);

    await tester.tap(_fab);
    await tester.pumpAndSettle();
    expect(_menu, findsNothing);
  });

  testWidgets('tapping outside the menu closes it', (tester) async {
    await _pumpScreen(tester);
    await _openMenu(tester);

    // Tap the Upcoming banner area, well away from the menu.
    await tester.tapAt(const Offset(200, 100));
    await tester.pumpAndSettle();
    expect(_menu, findsNothing);
  });

  testWidgets('tapping an option with no callback just closes the menu', (
    tester,
  ) async {
    await _pumpScreen(tester);
    await _openMenu(tester);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(_menu, findsNothing);
    // No placeholder flow opened.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('the menu does not alter the existing lists', (tester) async {
    await _pumpScreen(tester);

    // Baseline: seeded subject + assignment render.
    expect(find.text('Coding'), findsOneWidget);
    expect(find.text('Homework 1'), findsOneWidget);
    expect(find.text('Assignments & Exams'), findsOneWidget);
    expect(find.text('Upcoming: Coding'), findsOneWidget);

    await _openMenu(tester);
    // Lists are still there underneath the open menu.
    expect(find.text('Coding'), findsOneWidget);
    expect(find.text('Homework 1'), findsOneWidget);

    await tester.tap(_fab);
    await tester.pumpAndSettle();
    expect(_menu, findsNothing);
    expect(find.text('Coding'), findsOneWidget);
    expect(find.text('Homework 1'), findsOneWidget);
    expect(find.text('Upcoming: Coding'), findsOneWidget);
  });

  testWidgets('reduced motion: menu shows and hides instantly', (tester) async {
    SharedPreferences.setMockInitialValues({
      StudentStorage.subjectsKey: jsonEncode([_subject().toJson()]),
      StudentStorage.assignmentsKey: jsonEncode([]),
      googleEventsKey: jsonEncode([]),
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const ClassesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_fab);
    await tester.pump(); // No settle: instant show, no spring.
    expect(_menu, findsOneWidget);
    expect(find.text('Set Schedule Manual'), findsOneWidget);

    await tester.tap(_fab);
    await tester.pump(); // Instant hide.
    expect(_menu, findsNothing);
  });

  testWidgets('menu widget: option tap fires its hook then dismisses', (
    tester,
  ) async {
    var filesCalled = false;
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClassesPlusMenu(
            animation: const AlwaysStoppedAnimation(1.0),
            onFiles: () => filesCalled = true,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Files'));
    expect(filesCalled, isTrue);
    expect(dismissed, isTrue);
  });

  testWidgets('menu widget: option tap with no hook still dismisses', (
    tester,
  ) async {
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClassesPlusMenu(
            animation: const AlwaysStoppedAnimation(1.0),
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Google Schedule'));
    expect(dismissed, isTrue);
  });
}
