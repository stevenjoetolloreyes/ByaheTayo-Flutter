// Widget tests for Feature 2 of the Classes + menu build (Nov 10,
// 2026): "Set Schedule Manual" — the + menu's Manual option opens
// the existing subject form (subject, code, day, start/end time,
// instructor, room); saving adds the class to the timetable with a
// spring-in and the placement pop-chime. Covers the form fields,
// the add flow, the spring-in, the chime trigger (via the
// onPlacementChime test hook — audio output itself is not tested),
// cancel, and that editing an existing subject stays silent.
//
// Note: find.text matches EditableText content too, so assertions
// about list tiles use find.widgetWithText(ListTile, ...) and the
// Save button is scrolled into view (the form is taller than the
// test viewport) before tapping.
import 'dart:convert';

import 'package:estudyantego/features/student/classes_screen.dart';
import 'package:estudyantego/features/student/google_events.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Seeded at 6:00–7:00 on purpose: the form defaults to 8:00–9:00,
// so a new class saved with the defaults never conflicts with the
// seed (the conflict test seeds 8:00–9:00 explicitly instead).
Subject _subject({int startMin = 6 * 60, int endMin = 7 * 60}) => Subject(
  id: 's1',
  name: 'Coding',
  code: 'CS101',
  teacher: '',
  room: '',
  days: const [1, 2, 3, 4, 5, 6, 7],
  startMin: startMin,
  endMin: endMin,
  color: 0xFF16A34A,
);

Finder get _fab => find.byKey(const Key('classes-plus-fab'));
Finder get _menu => find.byKey(const Key('classes-plus-menu'));
Finder get _spring => find.byKey(const Key('placed-subject-spring'));
Finder _tile(String name) => find.widgetWithText(ListTile, name);

Future<void> _pumpScreen(
  WidgetTester tester, {
  VoidCallback? onPlacementChime,
  Subject? seed,
}) async {
  SharedPreferences.setMockInitialValues({
    StudentStorage.subjectsKey: jsonEncode([(seed ?? _subject()).toJson()]),
    StudentStorage.assignmentsKey: jsonEncode([]),
    // Explicit empty list so the mock Google sample set is not
    // seeded into this test's lists.
    googleEventsKey: jsonEncode([]),
  });
  await tester.pumpWidget(
    MaterialApp(home: ClassesScreen(onPlacementChime: onPlacementChime)),
  );
  await tester.pumpAndSettle();
}

Future<void> _openManualForm(WidgetTester tester) async {
  await tester.tap(_fab);
  await tester.pumpAndSettle();
  expect(_menu, findsOneWidget);
  await tester.tap(find.text('Set Schedule Manual'));
  await tester.pumpAndSettle();
  // Menu closed, form open.
  expect(_menu, findsNothing);
  expect(find.text('Add subject'), findsOneWidget);
}

/// The form is taller than the 600px test viewport, so the Save
/// button sits below the fold until scrolled into view.
Future<void> _tapSave(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save'));
}

/// Dismiss the bottom sheet via the system back button
/// ([pageBack] needs a Cupertino back button, which this screen
/// has none of).
Future<void> _dismissSheet(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tapping Manual opens the form with all required fields', (
    tester,
  ) async {
    await _pumpScreen(tester);
    await _openManualForm(tester);

    // Subject, code, instructor, room.
    expect(find.text('Subject name'), findsOneWidget);
    expect(find.text('Subject code'), findsOneWidget);
    expect(find.text('Teacher'), findsOneWidget);
    expect(find.text('Classroom / location'), findsOneWidget);
    // Day picker: one chip per weekday.
    expect(find.text('Days'), findsOneWidget);
    for (var day = 1; day <= 7; day++) {
      expect(find.text(weekdayName(day)), findsOneWidget);
    }
    // Start/end time pickers (defaults 8:00–9:00).
    expect(find.textContaining('Start:'), findsOneWidget);
    expect(find.textContaining('End:'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('saving a class adds it, springs it in, and chimes', (
    tester,
  ) async {
    var chimes = 0;
    await _pumpScreen(tester, onPlacementChime: () => chimes++);
    await _openManualForm(tester);

    await tester.enterText(find.byType(TextField).at(0), 'Biology');
    await tester.enterText(find.byType(TextField).at(1), 'BIO101');
    await tester.enterText(find.byType(TextField).at(2), 'Ms. Cruz');
    await tester.enterText(find.byType(TextField).at(3), 'Room 5');
    // Today, so the class lands in the Today list.
    await tester.tap(find.text(weekdayName(DateTime.now().weekday)));
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    // Step forward 50 ms at a time until the tile lands: the
    // spring starts the frame the sheet finishes popping, so
    // catching it here proves the spring-in runs.
    for (var i = 0; i < 20 && _spring.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_tile('Biology'), findsOneWidget);
    expect(_spring, findsOneWidget);
    // The top popup ('Subject added.') is up now; it auto-dismisses
    // after 5 s, so assert it before pumpAndSettle fast-forwards it.
    expect(find.text('Subject added.'), findsOneWidget);
    // Settled: class in the list with its details, chime fired
    // once, spring wrapper gone.
    await tester.pumpAndSettle();
    expect(_tile('Biology'), findsOneWidget);
    expect(find.textContaining('BIO101'), findsOneWidget);
    expect(find.textContaining('Ms. Cruz'), findsOneWidget);
    // Scoped to the tile: before 9 AM the Upcoming banner also
    // shows this class ("Tue · 8:00 AM–9:00 AM · Room 5"), so an
    // unscoped text search finds Room 5 twice and the test
    // depends on the time of day it runs.
    expect(
      find.descendant(
        of: _tile('Biology'),
        matching: find.textContaining('Room 5'),
      ),
      findsOneWidget,
    );
    expect(chimes, 1);
    expect(_spring, findsNothing);
    // Persisted: same repo/model as the old form — reload shows it.
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(StudentStorage.subjectsKey);
    final decoded = (jsonDecode(saved!) as List)
        .map((e) => Subject.fromJson(e as Map<String, dynamic>))
        .toList();
    expect(decoded.any((s) => s.name == 'Biology'), isTrue);
    expect(decoded.any((s) => s.name == 'Coding'), isTrue);
  });

  testWidgets('the new class also appears in the Week list', (tester) async {
    await _pumpScreen(tester);
    await _openManualForm(tester);

    await tester.enterText(find.byType(TextField).at(0), 'Physics');
    // A weekday that is not today, so it only shows in Week view.
    final otherDay = DateTime.now().weekday % 7 + 1;
    await tester.tap(find.text(weekdayName(otherDay)));
    await tester.pump();
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(_tile('Physics'), findsNothing); // Not in Today.
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(_tile('Physics'), findsOneWidget);
    expect(find.text(weekdayName(otherDay)), findsOneWidget);
  });

  testWidgets('dismissing the form adds nothing and chimes nothing', (
    tester,
  ) async {
    var chimes = 0;
    await _pumpScreen(tester, onPlacementChime: () => chimes++);
    await _openManualForm(tester);

    await tester.enterText(find.byType(TextField).at(0), 'Never Added');
    await _dismissSheet(tester);

    expect(find.text('Never Added'), findsNothing);
    expect(_tile('Coding'), findsOneWidget);
    expect(chimes, 0);
    expect(_spring, findsNothing);
  });

  testWidgets('editing an existing subject stays silent, no spring-in', (
    tester,
  ) async {
    var chimes = 0;
    await _pumpScreen(tester, onPlacementChime: () => chimes++);
    expect(_tile('Coding'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Edit subject'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Coding 2');
    await _tapSave(tester);
    // Popup up now (5 s auto-dismiss — assert before settling).
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Subject updated.'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(_tile('Coding 2'), findsOneWidget);
    expect(chimes, 0);
    expect(_spring, findsNothing);
  });

  testWidgets('the Manual form still blocks a conflicting time', (
    tester,
  ) async {
    var chimes = 0;
    await _pumpScreen(
      tester,
      onPlacementChime: () => chimes++,
      // Seed on the form's default 8:00–9:00 slot, so the new
      // class (same day, same defaults) conflicts with it.
      seed: _subject(startMin: 8 * 60, endMin: 9 * 60),
    );
    await _openManualForm(tester);

    // Same day and overlapping time as the seeded Coding class.
    await tester.enterText(find.byType(TextField).at(0), 'Clash');
    await tester.tap(find.text(weekdayName(DateTime.now().weekday)));
    await tester.pump();
    await _tapSave(tester);
    // Conflict popup shows immediately (validation is synchronous);
    // assert it before pumpAndSettle fast-forwards its 5 s life.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Add subject'), findsOneWidget);
    expect(find.textContaining('Schedule conflict'), findsOneWidget);
    expect(chimes, 0);
    // Dismiss the form: no Clash tile was ever added.
    await _dismissSheet(tester);
    expect(_tile('Clash'), findsNothing);
    expect(_tile('Coding'), findsOneWidget);
  });
}
