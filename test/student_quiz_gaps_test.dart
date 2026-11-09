// Tests for the Review pages: flashcard study marks, question
// count clamping, the on-device AI's 5-question cap, results
// summary, weekly chart data, and quiz runner progress. No
// network, no model: the AI generator is the on-device one
// (rule-based) where it is exercised at all.
//
// The old groups that tested the deleted "Review Notes & Quizzes"
// screen (NotesScreen), the deleted AI Quiz generate screen, and
// docx extraction (ai_quiz_input.dart) are gone with those files:
// the new file scope is PDF, photo (OCR), and .txt/.md/.csv.
import 'dart:convert';

import 'package:estudyantego/features/estudyantego_ai.dart';
import 'package:estudyantego/features/student/quiz_page.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('flashcard study status', () {
    test('old cards load unmarked and round-trip', () {
      final old = Flashcard.fromJson({
        'id': '1',
        'front': 'Q',
        'back': 'A',
        'subject': 'Math',
      });
      expect(old.studyStatus, '');
      expect(old.toJson()['studyStatus'], '');
      final marked = Flashcard(
        id: '1',
        front: 'Q',
        back: 'A',
        subject: 'Math',
        studyStatus: 'remembered',
      );
      expect(
        Flashcard.fromJson(marked.toJson()).studyStatus,
        'remembered',
      );
    });
  });

  group('question count clamping', () {
    test('clamps to 1–50', () {
      expect(clampQuizQuestionCount(0), 1);
      expect(clampQuizQuestionCount(5), 5);
      expect(clampQuizQuestionCount(50), 50);
      expect(clampQuizQuestionCount(51), 50);
      expect(clampQuizQuestionCount(100), 50);
    });

    test('on-device generation caps at 5 questions per set', () async {
      final generator = OnDeviceAiQuizGenerator();
      final result = await generator.generateFromText(
        'CPU is the Central Processing Unit. RAM is temporary memory. '
        'ROM is read-only memory. SSD is fast storage. The keyboard '
        'is an input device. The monitor is an output device. The '
        'mouse is a pointing device. The printer is an output device.',
        questionCount: 50,
      );
      expect(result.succeeded, isTrue);
      expect(result.questions.length, lessThanOrEqualTo(5));
    });
  });

  group('results summary and weekly chart data', () {
    test('performance bands', () {
      expect(performanceSummaryForPct(95), 'Excellent');
      expect(performanceSummaryForPct(90), 'Excellent');
      expect(performanceSummaryForPct(75), 'Good');
      expect(performanceSummaryForPct(50), 'Fair');
      expect(performanceSummaryForPct(49), 'Needs review');
    });

    test('weekly chart data comes only from real attempts', () {
      final now = DateTime(2026, 11, 4);
      final attempts = [
        QuizAttempt(
          id: 'a',
          quizTitle: 'Q1',
          score: 8,
          total: 10,
          date: DateTime(2026, 11, 4),
        ),
        QuizAttempt(
          id: 'b',
          quizTitle: 'Q1',
          score: 5,
          total: 10,
          date: DateTime(2026, 11, 2),
        ),
      ];
      final analytics = computeQuizAnalytics(attempts, now: now);
      expect(analytics.weekly.length, 7);
      expect(analytics.weekly.last.attempts, 1);
      expect(analytics.weekly[4].attempts, 1);
      expect(analytics.weekly[0].attempts, 0);
      expect(analytics.weekly[0].averagePct, 0);
      expect(analytics.totalAttempts, 2);
    });
  });

  group('quiz runner progress', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('runner shows a progress bar on question 1 of 2',
        (tester) async {
      final quiz = {
        'id': 'q1',
        'title': 'Sample',
        'subject': 'Math',
        'timeLimitSec': 0,
        'difficulty': 'medium',
        'randomize': false,
        'questions': [
          {
            'type': 'mcq',
            'question': 'What is 2 + 2?',
            'options': ['3', '4', '5', '6'],
            'correctIndex': 1,
            'answer': '4',
            'explanation': '',
            'learningTip': '',
          },
          {
            'type': 'mcq',
            'question': 'What is 3 + 3?',
            'options': ['5', '6', '7', '8'],
            'correctIndex': 1,
            'answer': '6',
            'explanation': '',
            'learningTip': '',
          },
        ],
      };
      SharedPreferences.setMockInitialValues({
        'byahetayo_student_quizzes': jsonEncode([quiz]),
      });
      await tester.pumpWidget(
        const MaterialApp(home: QuizPage()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start quiz'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sample · 1/2'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsWidgets);
    });
  });
}
