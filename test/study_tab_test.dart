// Tests for the Study tab (preview parity, Nov 6, 2026; color +
// design port from the preview's Study tab, Nov 7, 2026): bottom
// pill nav Grades / Files / Notes / Review, per-panel title +
// heart/star chips, Quiz | Summary pills, blue/green/amber quiz
// deck cards, gradient GWA card — over the app's REAL data. No
// sample GWA, no sample subjects, no sample files, no sample
// quizzes, no sample heart count.
//
// Rules pinned here: a fresh install shows GWA "—" and honest
// empty states; a recorded grade computes a real weighted GWA;
// files start at 0 files / 0 B of 5 GB; notes and quizzes come
// from the same StudentStorage the Student tab already uses;
// the ❤️ chip is the favorited-notes count (0 with none) and the
// ⭐ chip is the real points balance (0 pts with no wallet
// controller wired, as in widget tests).
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
const _favNoteJson =
    '[{"id":"n1","title":"Fav note","subject":"Math","body":"hello","favorite":true,"updated":"2026-11-06T00:00:00.000"}]';
const _quizJson =
    '[{"id":"q1","title":"My first quiz","subject":"Math","timeLimitSec":0,"questions":['
    '{"type":"mcq","question":"What is 2+2?","options":["3","4"],"correctIndex":1,"answer":"4","explanation":""},'
    '{"type":"mcq","question":"What is 3+3?","options":["5","6"],"correctIndex":1,"answer":"6","explanation":""}'
    '],"difficulty":"medium","randomize":false}]';

const _filesJson =
    '[{"id":"f1","name":"Lecture 1.pdf","sizeBytes":2048,"kind":"pdf","folder":"Lectures","added":"2026-11-05T00:00:00.000"},'
    '{"id":"f2","name":"Activity 1.docx","sizeBytes":512,"kind":"doc","folder":"Activities","added":"2026-11-06T00:00:00.000"}]';

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

Future<void> _tapNav(WidgetTester tester, String panel) async {
  await tester.tap(find.byKey(ValueKey('study-nav-$panel')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Grades is the default panel with honest empty states',
      (tester) async {
    await _pumpTab(tester);
    // Per-panel title (the preview's page title) + bottom nav.
    expect(find.text('Grades'), findsNWidgets(2)); // title + nav
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    // No sample GWA: fresh install shows "—", never the preview's
    // sample 1.58.
    expect(find.text('—'), findsWidgets);
    expect(find.text('1.58'), findsNothing);
    expect(find.text('No subjects yet.'), findsOneWidget);
    expect(find.text('GENERAL WEIGHTED AVERAGE'), findsOneWidget);
    expect(find.text('1.00 – 1.50 Excellent'), findsOneWidget);
    expect(find.text('5.00 Failed'), findsOneWidget);
    // Chips: no favorites, no wallet controller → honest zeros.
    expect(find.text('0 pts'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('study-hearts-chip')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    // The + FAB is present on the default panel.
    expect(find.byIcon(Icons.add), findsOneWidget);
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
    await _tapNav(tester, 'files');
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

  testWidgets('tapping a file row opens its details (metadata only)',
      (tester) async {
    await _pumpTab(tester, prefs: {
      'byahetayo_student_files': _filesJson,
    });
    await _tapNav(tester, 'files');
    expect(find.text('Lecture 1.pdf'), findsOneWidget);
    expect(find.text('Activity 1.docx'), findsOneWidget);
    await tester.tap(find.text('Lecture 1.pdf'));
    await tester.pumpAndSettle();
    // Name shows twice: row title + dialog title.
    expect(find.text('Lecture 1.pdf'), findsNWidgets(2));
    // Dialog rows: type / size / folder / added. 'PDF' also labels
    // a filter pill, so scope the dialog assertions to the dialog.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('PDF'),
      ),
      findsOneWidget,
    );
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Lectures'),
      ),
      findsOneWidget,
    );
    expect(find.text('Nov 5, 2026'), findsOneWidget);
    // Metadata only — no viewer, no content.
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Nov 5, 2026'), findsNothing);
    expect(find.text('Lecture 1.pdf'), findsOneWidget);
  });

  testWidgets('tapping a folder filters the file list to that folder',
      (tester) async {
    await _pumpTab(tester, prefs: {
      'byahetayo_student_files': _filesJson,
    });
    await _tapNav(tester, 'files');
    expect(find.text('Lecture 1.pdf'), findsOneWidget);
    expect(find.text('Activity 1.docx'), findsOneWidget);
    await tester.tap(find.text('Activities'));
    await tester.pumpAndSettle();
    expect(find.text('Lecture 1.pdf'), findsNothing);
    expect(find.text('Activity 1.docx'), findsOneWidget);
    // Tapping the active folder again clears the filter.
    await tester.tap(find.text('Activities'));
    await tester.pumpAndSettle();
    expect(find.text('Lecture 1.pdf'), findsOneWidget);
    expect(find.text('Activity 1.docx'), findsOneWidget);
    // A folder with no files shows its own honest empty state.
    await tester.tap(find.text('Reviewers'));
    await tester.pumpAndSettle();
    expect(find.text('No files in Reviewers yet.'), findsOneWidget);
    await tester.tap(find.text('Reviewers'));
    await tester.pumpAndSettle();
    expect(find.text('Lecture 1.pdf'), findsOneWidget);
  });

  testWidgets('tapping a file trash deletes it without opening details',
      (tester) async {
    await _pumpTab(tester, prefs: {
      'byahetayo_student_files': _filesJson,
    });
    await _tapNav(tester, 'files');
    // Rows sort most-recent-first, so target f1's own trash (not
    // the first trash on screen, which is f2's). The row sits low
    // in the list, so scroll it clear of the floating FAB first.
    final f1Row = find.ancestor(
      of: find.text('Lecture 1.pdf'),
      matching: find.byType(ListTile),
    );
    final f1Trash = find.descendant(
      of: f1Row,
      matching: find.byIcon(Icons.delete_outline),
    );
    await tester.ensureVisible(f1Trash);
    await tester.pumpAndSettle();
    await tester.tap(f1Trash);
    await tester.pumpAndSettle();
    expect(find.text('Lecture 1.pdf'), findsNothing);
    expect(find.text('Activity 1.docx'), findsOneWidget);
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('Notes panel lists real notes, searchable',
      (tester) async {
    await _pumpTab(tester, prefs: {
      'byahetayo_student_notes': _noteJson,
    });
    await _tapNav(tester, 'notes');
    expect(find.text('Search notes'), findsOneWidget);
    expect(find.text('My note'), findsOneWidget);
    // Preview note card: body excerpt, subject tag, "Nov 6" date.
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('Math'), findsOneWidget);
    expect(find.text('Nov 6'), findsOneWidget);
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
    await _tapNav(tester, 'review');
    // Per-panel title + nav both read "Review".
    expect(find.text('Review'), findsNWidgets(2));
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
    // Summary shows the same decks as summary cards, never the
    // stats view (no counterpart in the preview's Review tab).
    expect(find.text('Quizzes completed'), findsNothing);
    expect(find.text('Quizzes saved'), findsNothing);
    expect(find.text('Average score'), findsNothing);
    expect(find.text('Notes saved'), findsNothing);
    expect(find.text('Recent attempts'), findsNothing);
    expect(find.text('No quiz attempts yet.'), findsNothing);
    expect(find.text('No quizzes yet.'), findsOneWidget);
  });

  testWidgets('Summary shows deck summary cards from real quizzes',
      (tester) async {
    await _pumpTab(tester, prefs: {
      'byahetayo_student_quizzes': _quizJson,
    });
    await _tapNav(tester, 'review');
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    // The real quiz's summary card: title + factual teaser
    // (subject · question count · difficulty), list icon, chevron.
    expect(find.text('My first quiz'), findsOneWidget);
    expect(find.text('Math · 2 questions · Medium'), findsOneWidget);
    expect(find.byIcon(Icons.list_alt), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    // No stats view, no sample decks, no invented teaser.
    expect(find.text('Quizzes completed'), findsNothing);
    expect(find.text('Quizzes saved'), findsNothing);
    expect(find.text('Average score'), findsNothing);
    expect(find.text('Notes saved'), findsNothing);
    expect(find.text('Recent attempts'), findsNothing);
    expect(find.text('No quiz attempts yet.'), findsNothing);
    expect(find.text('11 Nursing Theorists and Their Theories'),
        findsNothing);
    expect(find.text('Audit Principles and Process'), findsNothing);
    expect(find.text('Computer Programming Fundamentals'), findsNothing);
    // Quiz pill still shows the question-count deck card.
    await tester.tap(find.text('Quiz'));
    await tester.pumpAndSettle();
    expect(find.text('MULTIPLE CHOICE'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('questions'), findsOneWidget);
    expect(find.text('Math'), findsOneWidget);
  });

  testWidgets('Review deck card shows a real quiz, never sample decks',
      (tester) async {
    await _pumpTab(tester, prefs: {
      'byahetayo_student_quizzes': _quizJson,
    });
    await _tapNav(tester, 'review');
    expect(find.text('My first quiz'), findsOneWidget);
    expect(find.text('MULTIPLE CHOICE'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('questions'), findsOneWidget);
    expect(find.text('Math'), findsOneWidget);
    expect(find.text('No quizzes yet.'), findsNothing);
    // The preview's sample decks are never hardcoded.
    expect(find.text('11 Nursing Theorists and Their Theories'),
        findsNothing);
    expect(find.text('Audit Principles and Process'), findsNothing);
    expect(find.text('Computer Programming Fundamentals'), findsNothing);
  });

  testWidgets('heart chip counts favorited notes, honestly',
      (tester) async {
    await _pumpTab(tester, prefs: {
      'byahetayo_student_notes': _favNoteJson,
    });
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('study-hearts-chip')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(find.text('15'), findsNothing);
  });

  testWidgets('Grades FAB points at the Student tab with no subjects',
      (tester) async {
    await _pumpTab(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(
      find.text(
        'Add subjects from the Student tab → Classes & Timetable first.',
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
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
