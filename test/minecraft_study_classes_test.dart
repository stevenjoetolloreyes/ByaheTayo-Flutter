// Widget tests for the Feature 3 Minecraft restyle of Classes &
// Timetable and the Study tab (Nov 10, 2026): the quest board,
// the blocky 58px + button, the restyled Add Subject sheet (with
// NO Repeat option), the Flashcard Chests with LIVE counts and
// mastery, the AI Quiz Forge with the REAL max XP, and the blocky
// bottom pill nav — all over the app's real data, never the
// preview's sample numbers.
//
// What is NOT asserted here: the preview's sample numbers (24
// cards / 18 mastered 75%, the +20 XP quest rewards, 'Coding' at
// 12:30 AM, the Repeat chips) — none of those exist in the real
// app. Classes carry no per-class XP, so no XP number is shown
// on a quest row; the '+50 XP' forge chip is derived from the
// app's own constants (up to 5 forged questions × 10 pts per
// correct answer), and a different constant would render a
// different chip.
import 'dart:convert';

import 'package:estudyantego/features/minecraft_theme.dart';
import 'package:estudyantego/features/student/classes_screen.dart';
import 'package:estudyantego/features/student/flashcards_page.dart';
import 'package:estudyantego/features/student/google_events.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:estudyantego/features/study_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Subject _subject({
  String id = 's1',
  String name = 'Coding',
  int startMin = 6 * 60,
  int endMin = 7 * 60,
  int color = 0xFF16A34A,
}) => Subject(
  id: id,
  name: name,
  code: 'CS101',
  teacher: 'Ms. Cruz',
  room: 'Room 5',
  days: const [1, 2, 3, 4, 5, 6, 7],
  startMin: startMin,
  endMin: endMin,
  color: color,
);

Map<String, Object> _cardJson({
  required String id,
  required String front,
  required String back,
  required String subject,
  String studyStatus = '',
}) => {
  'id': id,
  'front': front,
  'back': back,
  'subject': subject,
  'studyStatus': studyStatus,
};

Finder get _fab => find.byKey(const Key('classes-plus-fab'));
Finder get _menu => find.byKey(const Key('classes-plus-menu'));

Future<void> _pumpClasses(WidgetTester tester, {Subject? seed}) async {
  SharedPreferences.setMockInitialValues({
    StudentStorage.subjectsKey: jsonEncode([(seed ?? _subject()).toJson()]),
    StudentStorage.assignmentsKey: jsonEncode([]),
    googleEventsKey: jsonEncode([]),
  });
  await tester.pumpWidget(const MaterialApp(home: ClassesScreen()));
  await tester.pumpAndSettle();
}

Future<void> _pumpStudy(
  WidgetTester tester, {
  Map<String, Object>? prefs,
}) async {
  SharedPreferences.setMockInitialValues(prefs ?? {});
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StudyTab())));
  await tester.pumpAndSettle();
}

Future<void> _tapNav(WidgetTester tester, String panel) async {
  await tester.tap(find.byKey(ValueKey('study-nav-$panel')));
  await tester.pumpAndSettle();
}

/// The blocky border width on a container's decoration (light
/// theme in these tests: 3px ink).
double? _borderWidth(BoxDecoration decoration) {
  final border = decoration.border;
  if (border is Border) return border.top.width;
  return null;
}

void main() {
  group('Classes quest board', () {
    testWidgets('class row is a quest card with a letter block', (
      tester,
    ) async {
      await _pumpClasses(tester);
      // Letter-block badge: 46px, the subject's color, 3px border.
      final badge = find.byKey(const Key('quest-badge'));
      expect(badge, findsOneWidget);
      expect(tester.getSize(badge), const Size(46, 46));
      final badgeBox =
          tester.widget<Container>(badge).decoration as BoxDecoration;
      expect(badgeBox.color, const Color(0xFF16A34A));
      expect(_borderWidth(badgeBox), 3);
      // Baloo 2 title + real details (code · time · teacher ·
      // room), no invented XP chip on the row.
      final title = tester.widget<Text>(find.text('Coding'));
      expect(title.style?.fontFamily, startsWith('Baloo2'));
      expect(
        find.textContaining('CS101 · 6:00 AM–7:00 AM · Ms. Cruz · Room 5'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('quest-xp')), findsNothing);
    });

    testWidgets('upcoming card carries the Next up chip', (tester) async {
      await _pumpClasses(tester);
      // Any subject on all days has a next occurrence within the
      // week, so the Upcoming card always renders with its chip.
      expect(find.textContaining('Upcoming: Coding'), findsOneWidget);
      // The chip lives on the Upcoming card itself (scoped here
      // so the tile below never double-counts it).
      final card = find.ancestor(
        of: find.textContaining('Upcoming: Coding'),
        matching: find.byType(MinecraftCard),
      );
      expect(
        find.descendant(of: card, matching: find.text('Next up')),
        findsOneWidget,
      );
    });

    testWidgets('assignments empty state stays, blocky', (tester) async {
      await _pumpClasses(tester);
      expect(find.text('No assignments yet.'), findsOneWidget);
      expect(find.text('Assignments & Exams'), findsOneWidget);
    });

    testWidgets('FAB is a blocky 58px grass button', (tester) async {
      await _pumpClasses(tester);
      expect(_fab, findsOneWidget);
      expect(tester.getSize(_fab), const Size(58, 58));
      final container = find.descendant(
        of: _fab,
        matching: find.byType(Container),
      );
      final box =
          tester.widget<Container>(container).decoration as BoxDecoration;
      expect(box.color, MinecraftColors.grassGreen);
      expect(_borderWidth(box), 3.5);
    });

    testWidgets('+ menu is blocky', (tester) async {
      await _pumpClasses(tester);
      await tester.tap(_fab);
      await tester.pumpAndSettle();
      expect(_menu, findsOneWidget);
      final box = tester.widget<Container>(_menu).decoration as BoxDecoration;
      expect(_borderWidth(box), 3);
      expect(find.text('Set Schedule Manual'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Google Schedule'), findsOneWidget);
    });
  });

  group('Add Subject sheet (Feature 3)', () {
    Future<void> openForm(WidgetTester tester) async {
      await tester.tap(_fab);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set Schedule Manual'));
      await tester.pumpAndSettle();
    }

    testWidgets('restyled title, Place Block save, NO Repeat option', (
      tester,
    ) async {
      await _pumpClasses(tester);
      await openForm(tester);
      expect(find.text('Add Subject Block'), findsOneWidget);
      expect(find.text('Place Block (Save)'), findsOneWidget);
      // The preview's Repeat options are NOT in the real app.
      expect(find.text('Repeat'), findsNothing);
      expect(find.text('Does not repeat'), findsNothing);
      expect(find.text('Every week'), findsNothing);
      expect(find.text('Forever'), findsNothing);
      expect(find.text('Custom'), findsNothing);
      // The existing fields are all still there.
      expect(find.text('Subject name'), findsOneWidget);
      expect(find.text('Subject code'), findsOneWidget);
      expect(find.text('Teacher'), findsOneWidget);
      expect(find.text('Classroom / location'), findsOneWidget);
      expect(find.text('Days'), findsOneWidget);
      expect(find.textContaining('Start:'), findsOneWidget);
      expect(find.textContaining('End:'), findsOneWidget);
      expect(find.text('Color'), findsOneWidget);
    });

    testWidgets('saving with Place Block still adds the class', (tester) async {
      await _pumpClasses(tester);
      await openForm(tester);
      await tester.enterText(find.byType(TextField).at(0), 'Biology');
      await tester.tap(find.text(weekdayName(DateTime.now().weekday)));
      await tester.pump();
      await tester.ensureVisible(find.text('Place Block (Save)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Place Block (Save)'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Biology'), findsOneWidget);
    });
  });

  group('Study tab — Flashcard Chests', () {
    String cardsJson(List<Map<String, Object>> cards) => jsonEncode(cards);

    testWidgets('chests show live counts and mastery per subject', (
      tester,
    ) async {
      await _pumpStudy(
        tester,
        prefs: {
          StudentStorage.flashcardsKey: cardsJson([
            _cardJson(
              id: 'c1',
              front: 'Q1',
              back: 'A1',
              subject: 'Math',
              studyStatus: 'remembered',
            ),
            _cardJson(
              id: 'c2',
              front: 'Q2',
              back: 'A2',
              subject: 'Math',
              studyStatus: 'remembered',
            ),
            _cardJson(
              id: 'c3',
              front: 'Q3',
              back: 'A3',
              subject: 'Math',
              studyStatus: 'remembered',
            ),
            _cardJson(id: 'c4', front: 'Q4', back: 'A4', subject: 'Math'),
            _cardJson(id: 'c5', front: 'Q5', back: 'A5', subject: 'Science'),
            _cardJson(id: 'c6', front: 'Q6', back: 'A6', subject: 'Science'),
          ]),
        },
      );
      await _tapNav(tester, 'review');
      expect(find.text('Flashcard Chests'), findsOneWidget);
      // Math: 4 cards, 3 remembered = 75% — open chest.
      expect(find.text('Math'), findsOneWidget);
      expect(find.text('4 cards · 3 mastered'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.byIcon(Icons.inbox), findsOneWidget);
      // Science: 2 cards, 0 remembered = 0% — closed chest.
      expect(find.text('Science'), findsOneWidget);
      expect(find.text('2 cards · 0 mastered'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.byIcon(Icons.inventory_2), findsOneWidget);
      // Never the preview's sample numbers.
      expect(find.text('24 cards · 18 mastered'), findsNothing);
      expect(find.text('Discrete Math — Logic'), findsNothing);
    });

    testWidgets('empty chests keep the Flashcards entry point', (tester) async {
      await _pumpStudy(tester);
      await _tapNav(tester, 'review');
      expect(find.text('Flashcard Chests'), findsOneWidget);
      expect(find.text('Flashcards'), findsOneWidget);
      expect(
        find.text('No flashcards yet — add your first card.'),
        findsOneWidget,
      );
      expect(find.text('0%'), findsOneWidget);
    });
  });

  group('Study tab — AI Quiz Forge', () {
    testWidgets('forge card shows the real max XP, opens the AI panel', (
      tester,
    ) async {
      await _pumpStudy(tester);
      await _tapNav(tester, 'review');
      expect(find.text('AI Quiz Forge'), findsOneWidget);
      expect(find.text('Turn notes into a quiz'), findsOneWidget);
      expect(find.text('Forge a Quiz'), findsOneWidget);
      // 5 forged questions × 10 pts per correct answer = 50 XP.
      expect(find.text('+50 XP'), findsOneWidget);
      expect(find.text('AI Quiz'), findsNothing);
      await tester.ensureVisible(find.text('Forge a Quiz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forge a Quiz'));
      await tester.pumpAndSettle();
      expect(find.text('On-device · Offline · No Gemini'), findsOneWidget);
    });
  });

  group('Study tab — blocky chrome', () {
    testWidgets('header title and nav labels are Baloo 2', (tester) async {
      await _pumpStudy(tester);
      final titles = tester.widgetList<Text>(find.text('Grades'));
      expect(titles, isNotEmpty);
      for (final t in titles) {
        expect(t.style?.fontFamily, startsWith('Baloo2'));
      }
    });

    testWidgets('active nav button is a grass block', (tester) async {
      await _pumpStudy(tester);
      final button = find.byKey(const ValueKey('study-nav-grades'));
      expect(button, findsOneWidget);
      final container = find.descendant(
        of: button,
        matching: find.byType(Container),
      );
      final box =
          tester.widget<Container>(container).decoration as BoxDecoration;
      expect(box.color, MinecraftColors.grassGreen);
    });

    testWidgets('deck cards keep live question counts', (tester) async {
      await _pumpStudy(
        tester,
        prefs: {
          StudentStorage.quizzesKey: jsonEncode([
            {
              'id': 'q1',
              'title': 'My first quiz',
              'subject': 'Math',
              'timeLimitSec': 0,
              'questions': [
                {
                  'type': 'mcq',
                  'question': 'What is 2+2?',
                  'options': ['3', '4'],
                  'correctIndex': 1,
                  'answer': '4',
                  'explanation': '',
                },
                {
                  'type': 'mcq',
                  'question': 'What is 3+3?',
                  'options': ['5', '6'],
                  'correctIndex': 1,
                  'answer': '6',
                  'explanation': '',
                },
              ],
              'difficulty': 'medium',
              'randomize': false,
            },
          ]),
        },
      );
      await _tapNav(tester, 'review');
      expect(find.text('My first quiz'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('questions'), findsOneWidget);
    });
  });

  group('Flashcards page — chests', () {
    testWidgets('cards group into subject chests with live mastery', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        StudentStorage.flashcardsKey: jsonEncode([
          _cardJson(
            id: 'c1',
            front: 'What is CPU?',
            back: 'CPU',
            subject: 'Computer Basics',
            studyStatus: 'remembered',
          ),
          _cardJson(
            id: 'c2',
            front: 'What is RAM?',
            back: 'RAM',
            subject: 'Computer Basics',
          ),
          _cardJson(
            id: 'c3',
            front: 'What is 2+2?',
            back: '4',
            subject: 'Math',
            studyStatus: 'remembered',
          ),
        ]),
      });
      await tester.pumpWidget(const MaterialApp(home: FlashcardsPage()));
      await tester.pumpAndSettle();
      // Computer Basics: 2 cards, 1 remembered = 50% — open chest.
      expect(find.text('Computer Basics'), findsWidgets);
      expect(find.text('2 cards · 1 mastered'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      // Math: 1 card, 1 remembered = 100% — open chest.
      expect(find.text('Math'), findsOneWidget);
      expect(find.text('1 card · 1 mastered'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      // The rows themselves are unchanged: definition + answer.
      expect(find.text('What is CPU?'), findsOneWidget);
      expect(find.textContaining('Answer: CPU'), findsOneWidget);
      expect(find.text('Study all cards'), findsOneWidget);
    });

    testWidgets('sample deck shows one chest with real sample counts', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MaterialApp(home: FlashcardsPage()));
      await tester.pumpAndSettle();
      expect(find.text('Sample deck'), findsOneWidget);
      expect(find.text('Computer Basics'), findsWidgets);
      expect(find.text('5 cards · 0 mastered'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
    });
  });
}
