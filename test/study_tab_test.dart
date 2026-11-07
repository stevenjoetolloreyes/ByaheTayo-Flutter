// Tests for the Study tab (preview parity, Nov 6, 2026): pill
// sub-navigation Grades / Files / Notes / Review over the app's
// REAL data — no sample GWA, no sample subjects, no sample files.
//
// Rules pinned here: a fresh install shows GWA "—" and honest
// empty states; a recorded grade computes a real weighted GWA;
// files start at 0 files / 0 B of 5 GB; notes and quizzes come
// from the same StudentStorage the Student tab already uses.
import 'dart:convert';

import 'package:estudyantego/features/study_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _subjectJson =
    '[{"id":"s1","name":"Math 101","code":"MATH101","teacher":"","room":"","days":[1,3],"startMin":480,"endMin":540,"color":4278190080}]';
const _gradeJson =
    '[{"subjectId":"s1","grade":1.5,"units":3,"semester":1}]';
const _noteJson =
    '[{"id":"n1","title":"My note","subject":"Math","body":"hello","favorite":false,"updated":"2026-11-06T00:00:00.000"}]';

Future<void> _pumpTab(
  WidgetTester tester, {
  Map<String, Object>? prefs,
}) async {
  SharedPreferences.setMockInitialValues(prefs ?? {});
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: StudyTab())),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Grades is the default panel with honest empty states',
      (tester) async {
    await _pumpTab(tester);
    expect(find.text('Study'), findsOneWidget);
    for (final label in ['Grades', 'Files', 'Notes', 'Review']) {
      expect(find.text(label), findsWidgets);
    }
    // No sample GWA: fresh install shows "—", never the preview's
    // sample 1.58.
    expect(find.text('—'), findsWidgets);
    expect(find.text('1.58'), findsNothing);
    expect(find.text('No subjects yet.'), findsOneWidget);
    expect(find.text('GENERAL WEIGHTED AVERAGE'), findsOneWidget);
    expect(find.text('1.00 – 1.50 Excellent'), findsOneWidget);
    expect(find.text('5.00 Failed'), findsOneWidget);
  });

  testWidgets('a recorded grade computes a real weighted GWA',
      (tester) async {
    await _pumpTab(tester, prefs: {
      'byahetayo_student_subjects': _subjectJson,
      'byahetayo_student_grades': _gradeJson,
    });
    expect(find.text('Math 101'), findsOneWidget);
    expect(find.text('1.50'), findsWidgets);
    expect(find.text('Excellent'), findsOneWidget);
    expect(find.text('3 units · 1 graded'), findsOneWidget);
    // 2nd Semester has no grade for this subject: GWA back to "—".
    await tester.tap(find.text('2nd Semester'));
    await tester.pumpAndSettle();
    expect(find.text('No grade yet'), findsOneWidget);
  });

  testWidgets('Files panel starts empty: 0 files, 0 B of 5 GB',
      (tester) async {
    await _pumpTab(tester);
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('Study files'), findsOneWidget);
    expect(find.text('0 B of 5 GB used'), findsOneWidget);
    for (final folder in ['Lectures', 'Activities', 'Reviewers']) {
      expect(find.text(folder), findsOneWidget);
    }
    expect(find.text('0 files'), findsNWidgets(3));
    expect(find.text('No files yet.'), findsOneWidget);
    for (final filter in ['All', 'PDF', 'Docs', 'Slides', 'Images']) {
      expect(find.text(filter), findsOneWidget);
    }
  });

  testWidgets('Notes panel lists real notes, searchable',
      (tester) async {
    await _pumpTab(tester, prefs: {
      'byahetayo_student_notes': _noteJson,
    });
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Search notes'), findsOneWidget);
    expect(find.text('My note'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Search notes'),
      'zzz-no-match',
    );
    await tester.pumpAndSettle();
    expect(find.text('My note'), findsNothing);
    expect(find.text('No notes yet.'), findsOneWidget);
  });

  testWidgets('Review panel shows real study entry points, empty states',
      (tester) async {
    await _pumpTab(tester);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Pick how to study'), findsOneWidget);
    expect(find.text('Flashcards'), findsOneWidget);
    expect(find.text('Quiz'), findsWidgets);
    expect(find.text('AI Quiz'), findsOneWidget);
    expect(find.text('No quizzes yet.'), findsOneWidget);
    // The preview's Drag & Drop mode has no app equivalent and is
    // not faked with a substitute.
    expect(find.text('Drag & Drop'), findsNothing);
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    expect(find.text('Quizzes completed'), findsOneWidget);
    expect(find.text('Average score'), findsOneWidget);
    expect(find.text('No quiz attempts yet.'), findsOneWidget);
  });

  testWidgets('grade form validates the 1.00–5.00 range', (tester) async {
    await _pumpTab(tester, prefs: {
      'byahetayo_student_subjects': _subjectJson,
    });
    expect(find.text('No grade yet'), findsOneWidget);
    await tester.tap(find.text('Add grade'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Grade (1.00 – 5.00)'),
      '6.00',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a grade from 1.00 to 5.00.'),
      findsOneWidget,
    );
    // Dialog stays open; a valid grade saves.
    await tester.enterText(
      find.widgetWithText(TextField, 'Grade (1.00 – 5.00)'),
      '2.00',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('2.00'), findsWidgets);
    expect(jsonDecode(
      (await SharedPreferences.getInstance())
              .getString('byahetayo_student_grades') ??
          '[]',
    ), isNotEmpty);
  });
}
