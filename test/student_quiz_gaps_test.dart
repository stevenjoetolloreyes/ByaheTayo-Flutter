// Tests for the Review Notes & Quizzes gaps patch: flashcard study
// marks, AI count clamping, docx extraction, the inline neon
// loading bar, runner progress, results summary, and weekly chart
// data. No network, no model: the AI generator is faked.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:estudyantego/features/ai_quiz_generate_screen.dart';
import 'package:estudyantego/features/ai_quiz_input.dart';
import 'package:estudyantego/features/ai_quiz_service.dart';
import 'package:estudyantego/features/student/notes_screen.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal stored (method 0) zip containing one file, for docx tests.
Uint8List _storedZip(String filename, List<int> data) {
  final out = <int>[];
  void u16(int v) {
    out.add(v & 0xFF);
    out.add((v >> 8) & 0xFF);
  }

  void u32(int v) {
    out.add(v & 0xFF);
    out.add((v >> 8) & 0xFF);
    out.add((v >> 16) & 0xFF);
    out.add((v >> 24) & 0xFF);
  }

  // Local file header.
  u32(0x04034b50);
  u16(20);
  u16(0);
  u16(0);
  u16(0);
  u16(0);
  u32(0);
  u32(data.length);
  u32(data.length);
  u16(filename.length);
  u16(0);
  out.addAll(utf8.encode(filename));
  out.addAll(data);
  final cdOffset = out.length;
  // Central directory entry.
  u32(0x02014b50);
  u16(20);
  u16(20);
  u16(0);
  u16(0);
  u16(0);
  u16(0);
  u32(0);
  u32(data.length);
  u32(data.length);
  u16(filename.length);
  u16(0);
  u16(0);
  u16(0);
  u16(0);
  u32(0);
  u32(0);
  out.addAll(utf8.encode(filename));
  final cdSize = out.length - cdOffset;
  // End of central directory.
  u32(0x06054b50);
  u16(0);
  u16(0);
  u16(1);
  u16(1);
  u32(cdSize);
  u32(cdOffset);
  u16(0);
  return Uint8List.fromList(out);
}

class _GatedGenerator implements AiQuizGenerator {
  _GatedGenerator({required this.completer, required this.result});

  final Completer<AiQuizGeneration> completer;
  final AiQuizGeneration result;

  @override
  Future<AiQuizGeneration> generateFromText(
    String contextText, {
    int questionCount = 5,
    String difficulty = 'medium',
    List<String> questionTypes = const ['mcq'],
  }) =>
      completer.future;

  @override
  Future<AiQuizGeneration> generateFromMedia(
    List<AiQuizAttachment> attachments, {
    int questionCount = 5,
    String difficulty = 'medium',
    List<String> questionTypes = const ['mcq'],
  }) =>
      completer.future;

  @override
  Future<String> explainMore({
    required String question,
    required String correctAnswer,
    String explanation = '',
  }) async =>
      'Canned AI explanation.';
}

class _FailingGenerator implements AiQuizGenerator {
  @override
  Future<AiQuizGeneration> generateFromText(
    String contextText, {
    int questionCount = 5,
    String difficulty = 'medium',
    List<String> questionTypes = const ['mcq'],
  }) async =>
      const AiQuizGeneration(
        questions: [],
        error: 'AI generation failed. Try again.',
      );

  @override
  Future<AiQuizGeneration> generateFromMedia(
    List<AiQuizAttachment> attachments, {
    int questionCount = 5,
    String difficulty = 'medium',
    List<String> questionTypes = const ['mcq'],
  }) async =>
      const AiQuizGeneration(
        questions: [],
        error: 'AI generation failed. Try again.',
      );

  @override
  Future<String> explainMore({
    required String question,
    required String correctAnswer,
    String explanation = '',
  }) async =>
      'Canned AI explanation.';
}

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

    test('media prompt accepts a large count without capping to 10', () {
      final content = buildMediaContent(
        [AiQuizAttachment(mimeType: 'image/jpeg', bytes: Uint8List(0))],
        questionCount: 50,
      );
      final prompt = content.parts
          .whereType<TextPart>()
          .map((p) => p.text)
          .join(' ');
      expect(prompt, contains('50'));
      expect(prompt, contains('never invent'));
    });
  });

  group('docx extraction', () {
    test('extracts text from a valid stored docx', () {
      const xml =
          '<w:document><w:body><w:p><w:r><w:t>Hello</w:t></w:r>'
          '<w:r><w:t> World</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>Second</w:t></w:r></w:p>'
          '</w:body></w:document>';
      final docx = _storedZip('word/document.xml', utf8.encode(xml));
      expect(extractDocxText(docx), 'Hello World\nSecond');
    });

    test('corrupt bytes and missing document.xml error cleanly', () {
      expect(
        () => extractDocxText(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      final other = _storedZip('word/other.xml', utf8.encode('<x/>'));
      expect(() => extractDocxText(other), throwsFormatException);
    });

    test('docx mime is recognised, binary doc is not', () {
      expect(
        mimeTypeForExtension('docx'),
        'application/vnd.openxmlformats-officedocument.'
        'wordprocessingml.document',
      );
      expect(mimeTypeForExtension('doc'), isNull);
      expect(kAiQuizDocumentExtensions, contains('docx'));
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

  group('generate screen loading states', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('button disabled and neon bar shown while generating',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final completer = Completer<AiQuizGeneration>();
      await tester.pumpWidget(
        MaterialApp(
          home: AiQuizGenerateScreen(
            generator: _GatedGenerator(
              completer: completer,
              result: const AiQuizGeneration(questions: []),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextField).first,
        'Photosynthesis basics.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate quiz'));
      await tester.pump();
      expect(find.text('Generating...'), findsOneWidget);
      expect(
        find.text('Please wait while AI processes your file.'),
        findsOneWidget,
      );
      expect(find.text('Generating Questions...'), findsOneWidget);
      final button =
          tester.widget<FilledButton>(find.byType(FilledButton).first);
      expect(button.onPressed, isNull);
      completer.complete(
        const AiQuizGeneration(questions: [
          AiQuizQuestion(
            question: 'What is 2 + 2?',
            options: ['3', '4', '5', '6'],
            correctIndex: 1,
            explanation: 'Basic addition.',
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quiz Generated Successfully!'), findsOneWidget);
      expect(find.text('1 questions generated'), findsOneWidget);
      expect(find.text('Preview Quiz'), findsOneWidget);
      expect(find.text('Generating...'), findsNothing);
    });

    testWidgets('error shows Retry and preserves the picked file',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AiQuizGenerateScreen(
            generator: _FailingGenerator(),
            pickInput: (_) async => const AiQuizPickedInput(
              label: 'lesson.txt',
              text: 'Photosynthesis basics.',
            ),
          ),
        ),
      );
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();
      expect(find.text('lesson.txt'), findsOneWidget);
      await tester.ensureVisible(find.text('Generate quiz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate quiz'));
      await tester.pumpAndSettle();
      expect(find.text('AI generation failed. Try again.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('lesson.txt'), findsOneWidget);
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
        const MaterialApp(home: NotesScreen(initialTab: 'quizzes')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sample · 1/2'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsWidgets);
    });
  });
}
