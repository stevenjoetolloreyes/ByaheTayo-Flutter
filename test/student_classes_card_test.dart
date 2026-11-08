// Widget tests for the redesigned Classes & Timetable card (Nov 8,
// 2026): redesigned header/stat strip, Next-class banner, week-load
// graph from real Subject data, icon-headed Exams/Deadlines, filled
// View Timetable button — with the calendar region (segments + day
// grid) kept. Data is seeded through SharedPreferences exactly as
// the app stores it; nothing is invented.
import 'dart:convert';

import 'package:estudyantego/features/student/student_data.dart';
import 'package:estudyantego/features/student/student_theme.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tall viewport so the full StudentTab list builds.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpHub(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light(),
      themeMode: ThemeMode.light,
      home: Scaffold(
        body: StudentHubTheme(child: const StudentTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Subject _subject({
  String id = 's1',
  String name = 'Coding',
  List<int> days = const [1],
  int startMin = 30,
  int endMin = 360,
}) =>
    Subject(
      id: id,
      name: name,
      code: '',
      teacher: '',
      room: '',
      days: days,
      startMin: startMin,
      endMin: endMin,
      color: 0xFF16A34A,
    );

/// Text inside the Classes & Timetable card (scoped so a same-named
/// label in another Hub card cannot match).
Finder _inClassesCard(String text) => find.descendant(
      of: find
          .ancestor(
            of: find.text('Classes & Timetable'),
            matching: find.byType(Card),
          )
          .first,
      matching: find.text(text),
    );

void main() {
  testWidgets(
      'redesigned card renders with no subjects (honest empty states)',
      (WidgetTester tester) async {
    _tallScreen(tester);
    SharedPreferences.setMockInitialValues({});
    await _pumpHub(tester);

    expect(find.text('Classes & Timetable'), findsOneWidget);
    expect(find.text('Your schedule at a glance.'), findsOneWidget);
    expect(_inClassesCard('Total Subjects'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('total-subjects-count')),
          )
          .data,
      '0',
    );
    // Calendar region kept: the three segments + the day grid.
    expect(_inClassesCard('Today'), findsOneWidget);
    expect(_inClassesCard('This Week'), findsOneWidget);
    expect(_inClassesCard('All Classes'), findsOneWidget);
    // Empty day view keeps its exact honest strings.
    expect(_inClassesCard('No classes today.'), findsOneWidget);
    expect(
      _inClassesCard('Relax, study, or get ahead on your tasks!'),
      findsOneWidget,
    );
    // Graph: no fake chart, honest empty state.
    expect(find.text('Your week at a glance'), findsOneWidget);
    expect(find.byKey(const ValueKey('week-load-graph')), findsOneWidget);
    expect(
      find.text(
        'No subjects yet — add your classes to see your weekly load.',
      ),
      findsOneWidget,
    );
    // Icon-headed sections, honest empty states.
    expect(_inClassesCard('Upcoming Exams'), findsOneWidget);
    expect(_inClassesCard('No upcoming exams.'), findsOneWidget);
    expect(_inClassesCard('Assignment Deadlines'), findsOneWidget);
    expect(_inClassesCard('No upcoming assignments.'), findsOneWidget);
    // Filled View Timetable button.
    expect(
      find.widgetWithText(FilledButton, 'View Timetable'),
      findsOneWidget,
    );
    // No next-class banner with no subjects.
    expect(find.byKey(const ValueKey('next-class-banner')), findsNothing);
  });

  testWidgets('graph shows real hours and Next-class banner with subjects',
      (WidgetTester tester) async {
    _tallScreen(tester);
    final subjects = [
      _subject(days: const [1], startMin: 30, endMin: 360), // Mon 5.5h
      _subject(
        id: 's2',
        name: 'Coding Self',
        days: const [7],
        startMin: 840,
        endMin: 960,
      ), // Sun 2h
    ];
    SharedPreferences.setMockInitialValues({
      StudentStorage.subjectsKey:
          jsonEncode(subjects.map((s) => s.toJson()).toList()),
      StudentStorage.assignmentsKey: jsonEncode([]),
    });
    await _pumpHub(tester);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('total-subjects-count')),
          )
          .data,
      '2',
    );
    // Graph: real hours, real total.
    expect(find.text('5.5h'), findsOneWidget);
    expect(find.text('2h'), findsOneWidget);
    expect(
      find.text('7.5h total · 2 classes this week'),
      findsOneWidget,
    );
    // Next-class banner exists (which class is next depends on today).
    expect(find.byKey(const ValueKey('next-class-banner')), findsOneWidget);
    expect(find.text('NEXT CLASS'), findsOneWidget);
    // Calendar region kept.
    expect(_inClassesCard('Today'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'View Timetable'),
      findsOneWidget,
    );
  });

  testWidgets('All Classes lists the real subjects with their colors',
      (WidgetTester tester) async {
    _tallScreen(tester);
    final subjects = [
      _subject(days: const [1], startMin: 30, endMin: 360), // Mon 5.5h
      _subject(
        id: 's2',
        name: 'Coding Self',
        days: const [7],
        startMin: 840,
        endMin: 960,
      ), // Sun 2h
    ];
    SharedPreferences.setMockInitialValues({
      StudentStorage.subjectsKey:
          jsonEncode(subjects.map((s) => s.toJson()).toList()),
      StudentStorage.assignmentsKey: jsonEncode([]),
    });
    await _pumpHub(tester);

    await tester.tap(_inClassesCard('All Classes'));
    await tester.pumpAndSettle();

    // The subjects list (the grid and the banner are gone in this view).
    expect(_inClassesCard('Coding'), findsOneWidget);
    expect(_inClassesCard('Coding Self'), findsOneWidget);
    expect(find.byKey(const ValueKey('next-class-banner')), findsNothing);
  });
}
