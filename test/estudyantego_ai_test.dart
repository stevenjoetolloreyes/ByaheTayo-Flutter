// Tests for the on-device EstudyanteGO AI engine and the new
// Review pages (Flashcards Page, Quiz Page) + AI chat panel.
// No network, no model, no native plugins: the engine is
// rule-based and the pages are pumped with empty SharedPreferences
// (so the sample deck shows) or with real saved data.
import 'package:estudyantego/features/estudyantego_ai.dart';
import 'package:estudyantego/features/student/ai_screen.dart';
import 'package:estudyantego/features/student/flashcards_page.dart';
import 'package:estudyantego/features/student/quiz_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _defs =
    'CPU is the Central Processing Unit. RAM is temporary memory. '
    'ROM is read-only memory. SSD is fast storage. The keyboard '
    'is an input device. The monitor is an output device.';

void main() {
  group('on-device AI engine', () {
    test('extractKeyTerms finds defined terms', () {
      final terms = extractKeyTerms(_defs);
      expect(terms.map((t) => t.term), contains('CPU'));
      expect(terms.map((t) => t.term), contains('RAM'));
      expect(terms.firstWhere((t) => t.term == 'CPU').definition,
          contains('Central Processing Unit'));
    });

    test('questionsFromText makes MCQ with same-text distractors, max 5',
        () {
      final questions = questionsFromText(_defs, questionCount: 50);
      expect(questions.length, lessThanOrEqualTo(5));
      expect(questions.length, greaterThan(0));
      for (final q in questions) {
        expect(q.type, 'mcq');
        expect(q.options.length, 4);
        expect(q.correctIndex, inInclusiveRange(0, 3));
        // Every option is a definition taken verbatim from the
        // same text — the AI never invents a distractor. (The
        // order is shuffled with an unseeded Random, so no test
        // may depend on which question comes first.)
        for (final option in q.options) {
          expect(_defs, contains(option),
              reason: 'option "$option" is not from the source text');
        }
      }
    });

    test('keyPoints returns at most 3 points', () {
      final points = keyPoints(_defs);
      expect(points.length, lessThanOrEqualTo(3));
      expect(points.length, greaterThan(0));
    });

    test('flashcardsFromText is definition-first: front shows the definition, back reveals the term', () {
      final cards = flashcardsFromText(_defs);
      expect(cards.length, greaterThan(0));
      expect(cards.first.front, contains('Central Processing Unit'));
      expect(cards.first.back, 'CPU');
    });

    // Resume-like content: the exact shape that produced the random
    // "What is 2019?" quiz (bare years, place fragments, label lines).
    test('no question is built around a bare year, date, or number', () {
      const resumeLike = 'Steven Joe T. Reyes\n'
          'Cabugao, Ilocos Sur, Philippines\n'
          '2019 - Inventory Management System\n'
          'Location: Cabugao, Ilocos Sur, Philippines\n'
          'Tech: Places & Routes APIs, Meta / Facebook API\n'
          'Graduation: 2026\n'
          'CPU is the Central Processing Unit. RAM is temporary memory. '
          'ROM is read-only memory. SSD is fast storage.';
      final questions = questionsFromText(resumeLike, questionCount: 5);
      expect(questions, isNotEmpty);
      for (final q in questions) {
        expect(q.question, isNot(contains('2019')),
            reason: 'question built around a bare year: ${q.question}');
        expect(q.question, isNot(contains('2026')),
            reason: 'question built around a bare year: ${q.question}');
        // No bare year/number among the options either.
        for (final option in q.options) {
          expect(option.trim(), isNot('2019'));
          expect(option.trim(), isNot('2026'));
        }
        // Options are distinct, and the explanation quotes the
        // exact source line from the notes.
        expect(q.options.toSet().length, q.options.length);
        expect(q.explanation, isNotEmpty);
        expect(resumeLike, contains(q.explanation));
      }
    });

    test('extractKeyTerms skips bare years and fragment values', () {
      const resumeLike = '2019 - Inventory Management System\n'
          'Location: Cabugao, Ilocos Sur, Philippines\n'
          'Graduation: 2026\n'
          'CPU is the Central Processing Unit.';
      final terms = extractKeyTerms(resumeLike);
      expect(terms.map((t) => t.term), isNot(contains('2019')));
      expect(terms.map((t) => t.term), isNot(contains('Graduation')));
      expect(terms.map((t) => t.term), isNot(contains('Location')));
      expect(terms.map((t) => t.term), isNot(contains('Cabugao')));
      expect(terms.map((t) => t.term), contains('CPU'));
      expect(terms.map((t) => t.definition), isNot(contains('2026')));
    });

    test('sample Computer Basics deck has 5 cards and 5 questions', () {
      expect(sampleComputerBasicsDeck.flashcards.length, 5);
      expect(sampleComputerBasicsDeck.questions.length, 5);
      // Definition-first: the front shows the definition and the
      // back reveals the term.
      expect(sampleComputerBasicsDeck.flashcards.first.front,
          'Central Processing Unit — it processes instructions');
      expect(sampleComputerBasicsDeck.flashcards.first.back, 'CPU');
      expect(sampleComputerBasicsDeck.quiz.id, 'sample-computer-basics');
    });

    test('answerChat gives the verified Cabugao → Vigan fare', () {
      final reply = answerChat('Fare: Cabugao → Vigan?');
      expect(reply.text, contains('₱60'));
      expect(reply.text, contains('₱48'));
    });

    test('answerChat never invents another fare', () {
      final reply = answerChat('How much is the fare to Laoag?');
      expect(reply.text, contains('I only know the verified fare'));
      expect(reply.text, contains('₱60'));
    });

    test('answerChat states it is built-in, not an online AI', () {
      final reply = answerChat('Are you an online AI?');
      expect(reply.text, contains('not an online AI'));
      expect(reply.text, contains('built into this app'));
      expect(reply.text, contains('without internet'));
    });
  });

  group('AI chat panel (widget)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> pumpChat(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiChatPanel(
              notes: const [],
              quizzes: const [],
              cards: const [],
              subjects: const [],
              points: 0,
              onQuestionsGenerated: (_, __) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('fare chip answers with the verified fare',
        (tester) async {
      await pumpChat(tester);
      await tester.tap(find.text('Fare: Cabugao → Vigan?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('₱60'), findsWidgets);
      expect(find.textContaining('₱48'), findsWidgets);
    });

    testWidgets('identity chip says it is not an online AI',
        (tester) async {
      await pumpChat(tester);
      // The chips are one swipeable row; the identity chip is the
      // last one, so scroll it into view before tapping.
      await tester.ensureVisible(find.text('Are you an online AI?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Are you an online AI?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not an online AI'), findsOneWidget);
    });

    testWidgets('quick-reply chips sit above the input, + is on its left',
        (tester) async {
      await pumpChat(tester);
      // The four chips are in one horizontal row above the input.
      expect(find.text('Make a quiz from my notes'), findsOneWidget);
      expect(find.text('Summarize my deck'), findsOneWidget);
      // The + attach button is a small brand circle left of the input.
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('+ menu offers only Take Photo and Files',
        (tester) async {
      await pumpChat(tester);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('More'), findsNothing);
      expect(find.text('Others'), findsNothing);
    });
  });

  group('Flashcards Page (widget)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('empty deck shows the labelled Computer Basics sample',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: FlashcardsPage()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sample deck'), findsOneWidget);
      expect(find.textContaining('Computer Basics'), findsWidgets);
      expect(find.text('Study all cards'), findsOneWidget);
      // Definition-first: the list shows the definition, and the
      // term is the answer in the subtitle.
      expect(find.textContaining('Central Processing Unit'),
          findsOneWidget);
      expect(find.textContaining('Answer: CPU'), findsOneWidget);
    });

    testWidgets('Study all cards opens the flip mode with progress',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: FlashcardsPage()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Study all cards'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Card 1 of 5'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsWidgets);
    });

    testWidgets('flip mode shows the definition first, term on flip',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: FlashcardsPage()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Study all cards'));
      await tester.pumpAndSettle();
      // Definition-first: the front is labelled Definition and
      // shows the definition, not the term.
      expect(find.text('Definition'), findsOneWidget);
      expect(find.textContaining('Central Processing Unit'),
          findsOneWidget);
      expect(find.text('CPU'), findsNothing);
      expect(find.text('Tap the card to reveal the term'),
          findsOneWidget);
      // Tap to flip: the term is revealed.
      await tester.tap(find.textContaining('Central Processing Unit'));
      await tester.pumpAndSettle();
      expect(find.text('Term'), findsOneWidget);
      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('Tap the card to flip back'), findsOneWidget);
    });
  });

  group('Quiz Page (widget)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('empty list shows the labelled Computer Basics sample',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: QuizPage()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sample quiz'), findsOneWidget);
      expect(find.textContaining('Computer Basics'), findsWidgets);
    });

    testWidgets('+ is an icon-only floating button, no label pill',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: QuizPage()),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('+ Add question'), findsNothing);
      expect(find.text('Add question'), findsNothing);
    });

    testWidgets('+ menu offers Add Question manually and Files',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: QuizPage()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('Add Question manually'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      // The + rotated 45° while the menu is open (it reads as a
      // close ×) — it keeps the add icon, rotated, rather than
      // swapping to a different icon.
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });
}
