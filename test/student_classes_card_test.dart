// Widget tests for the redesigned Classes & Timetable card (Nov 9,
// 2026): Today / This Week tabs only (no All Classes), no week-load
// graph, no Upcoming Exams / Assignment Deadlines, no View Timetable
// button. Google Calendar events (mock sync) sit on both timelines
// with G badges and in both lists, from the same merged entries as
// the timelines. Google rows open the Edit / Remove sheet.
// Data is seeded through SharedPreferences exactly as the app stores
// it; the Google sample set seeds itself on first load, so a test
// that wants no Google events stores an explicit empty list.
import 'dart:convert';

import 'package:estudyantego/features/student/google_events.dart';
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

/// The four mock-synced Google events, as the Today list renders
/// them (day prefix + time range + title, time order).
const _todayGoogleLabels = [
  'Sat · 8:00 AM–11:00 AM · NSTP 1',
  'Fri · 10:00 AM–11:30 AM · Life and Works of Rizal',
  'Thu · 3:00 PM–4:30 PM · Discrete Mathematics',
  'Sun · 4:47 PM · Vigan',
];

void main() {
  testWidgets(
      'redesigned card: Today/This Week only, Google events listed, '
      'no graph, no exams, no View Timetable', (WidgetTester tester) async {
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
    // Tabs: Today / This Week only — the All Classes tab is gone.
    expect(_inClassesCard('Today'), findsOneWidget);
    expect(_inClassesCard('This Week'), findsOneWidget);
    expect(_inClassesCard('All Classes'), findsNothing);
    // The "Your week at a glance" chart is gone.
    expect(find.text('Your week at a glance'), findsNothing);
    expect(find.byKey(const ValueKey('week-load-graph')), findsNothing);
    // Upcoming Exams / Assignment Deadlines are gone.
    expect(_inClassesCard('Upcoming Exams'), findsNothing);
    expect(_inClassesCard('No upcoming exams.'), findsNothing);
    expect(_inClassesCard('Assignment Deadlines'), findsNothing);
    expect(_inClassesCard('No upcoming assignments.'), findsNothing);
    // The View Timetable button is gone (the header opens the
    // full screen instead).
    expect(
      find.widgetWithText(FilledButton, 'View Timetable'),
      findsNothing,
    );
    // The mock-synced Google events are in the Today list, in
    // time order, with their day prefixes — even with no subjects
    // (so the "No classes today." empty state does NOT show).
    for (final label in _todayGoogleLabels) {
      expect(_inClassesCard(label), findsOneWidget);
    }
    expect(_inClassesCard('No classes today.'), findsNothing);
    // G badges mark the synced rows.
    expect(find.byType(GBadge), findsWidgets);
    // No next-class banner with no subjects.
    expect(find.byKey(const ValueKey('next-class-banner')), findsNothing);
  });

  testWidgets('empty Today list when no subjects and no Google events',
      (WidgetTester tester) async {
    _tallScreen(tester);
    // An explicitly stored empty Google list stays empty (the
    // sample set is seeded only when nothing was ever stored).
    SharedPreferences.setMockInitialValues({
      googleEventsKey: jsonEncode([]),
    });
    await _pumpHub(tester);

    expect(_inClassesCard('No classes today.'), findsOneWidget);
    expect(
      _inClassesCard('Relax, study, or get ahead on your tasks!'),
      findsOneWidget,
    );
    for (final label in _todayGoogleLabels) {
      expect(_inClassesCard(label), findsNothing);
    }
  });

  testWidgets('Next-class banner with subjects; graph strings gone',
      (WidgetTester tester) async {
    _tallScreen(tester);
    final today = DateTime.now().weekday;
    final subjects = [
      _subject(days: [today], startMin: 30, endMin: 360),
      _subject(
        id: 's2',
        name: 'Coding Self',
        days: const [7],
        startMin: 840,
        endMin: 960,
      ),
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
    // No graph at all — none of its strings render.
    expect(find.text('Your week at a glance'), findsNothing);
    expect(find.text('5.5h'), findsNothing);
    expect(find.text('2h'), findsNothing);
    expect(find.text('7.5h total · 2 classes this week'), findsNothing);
    // Next-class banner exists (which class is next depends on today).
    expect(find.byKey(const ValueKey('next-class-banner')), findsOneWidget);
    expect(find.text('NEXT CLASS'), findsOneWidget);
    // Today's class is in the Today list; Google events too.
    expect(
      _inClassesCard('12:30 AM–6:00 AM · Coding'),
      findsOneWidget,
    );
    for (final label in _todayGoogleLabels) {
      expect(_inClassesCard(label), findsOneWidget);
    }
  });

  testWidgets('This Week shows the full grid and the day-grouped list',
      (WidgetTester tester) async {
    _tallScreen(tester);
    final subjects = [
      _subject(days: const [1], startMin: 30, endMin: 360),
      _subject(
        id: 's2',
        name: 'Coding Self',
        days: const [7],
        startMin: 840,
        endMin: 960,
      ),
    ];
    SharedPreferences.setMockInitialValues({
      StudentStorage.subjectsKey:
          jsonEncode(subjects.map((s) => s.toJson()).toList()),
      StudentStorage.assignmentsKey: jsonEncode([]),
    });
    await _pumpHub(tester);

    await tester.tap(_inClassesCard('This Week'));
    await tester.pumpAndSettle();

    // Week list: Google events under their day groups, no day
    // prefix on the rows (the group header says the day).
    expect(_inClassesCard('3:00 PM–4:30 PM · Discrete Mathematics'),
        findsOneWidget);
    expect(_inClassesCard('10:00 AM–11:30 AM · Life and Works of Rizal'),
        findsOneWidget);
    expect(_inClassesCard('8:00 AM–11:00 AM · NSTP 1'), findsOneWidget);
    expect(_inClassesCard('4:47 PM · Vigan'), findsOneWidget);
    // Day-group headers carry the weekday + date number.
    expect(find.textContaining('THU · '), findsOneWidget);
    expect(find.textContaining('SUN · '), findsOneWidget);
    // Still no All Classes tab, no graph, no View Timetable.
    expect(_inClassesCard('All Classes'), findsNothing);
    expect(find.text('Your week at a glance'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'View Timetable'),
      findsNothing,
    );
  });

  testWidgets('Google row opens the sheet; Remove unsyncs the event',
      (WidgetTester tester) async {
    _tallScreen(tester);
    SharedPreferences.setMockInitialValues({});
    await _pumpHub(tester);

    await tester.tap(_inClassesCard('Sun · 4:47 PM · Vigan'));
    await tester.pumpAndSettle();

    // Action sheet: title + meta + Edit / Remove / Cancel.
    expect(find.text('Vigan'), findsWidgets);
    expect(find.widgetWithText(ListTile, 'Edit'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    // Confirm step.
    expect(find.text('Remove "Vigan"?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    // Vigan is gone from the Today list (and the timeline).
    expect(_inClassesCard('Sun · 4:47 PM · Vigan'), findsNothing);
    expect(_inClassesCard('4:47 PM · Vigan'), findsNothing);
    // The other Google events stay.
    expect(
      _inClassesCard('Thu · 3:00 PM–4:30 PM · Discrete Mathematics'),
      findsOneWidget,
    );
  });

  testWidgets('Google row Edit renames the event in the list',
      (WidgetTester tester) async {
    _tallScreen(tester);
    SharedPreferences.setMockInitialValues({});
    await _pumpHub(tester);

    await tester.tap(
        _inClassesCard('Thu · 3:00 PM–4:30 PM · Discrete Mathematics'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Google event'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField).first, 'Discrete Math 2');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      _inClassesCard('Thu · 3:00 PM–4:30 PM · Discrete Math 2'),
      findsOneWidget,
    );
    expect(
      _inClassesCard('Thu · 3:00 PM–4:30 PM · Discrete Mathematics'),
      findsNothing,
    );
  });
}
