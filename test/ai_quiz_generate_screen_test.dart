// Widget tests for the AI quiz generate screen + its entry point
// in the Notes screen. Uses a fake generator: no network, no model.
import 'dart:typed_data';

import 'package:estudyantego/features/ai_quiz_generate_screen.dart';
import 'package:estudyantego/features/ai_quiz_input.dart';
import 'package:estudyantego/features/ai_quiz_service.dart';
import 'package:estudyantego/features/student/notes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_quiz_service_test.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('generate shows questions, save confirms', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiQuizGenerateScreen(generator: FakeAiQuizGenerator()),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'Addition basics: 2 + 2 is 4.',
    );
    await tester.ensureVisible(find.text('Generate quiz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate quiz'));
    await tester.pumpAndSettle();
    expect(find.textContaining('What is 2 + 2?'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    // The new input-options row makes the screen taller than the
    // test viewport, so scroll Save into view first (on-device the
    // user scrolls the same way; the button itself is unchanged).
    await tester.ensureVisible(find.text('Save as quiz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as quiz'));
    await tester.pumpAndSettle();
    expect(
      find.text('Saved! Find it in your Quizzes list.'),
      findsOneWidget,
    );
  });

  testWidgets('quizzes tab shows the AI generate entry', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NotesScreen(initialTab: 'quizzes')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Generate quiz from text (AI)'), findsOneWidget);
  });

  testWidgets('input options render', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiQuizGenerateScreen(generator: FakeAiQuizGenerator()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Picture'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
  });

  testWidgets('camera pick generates from media', (tester) async {
    final fake = FakeAiQuizGenerator();
    await tester.pumpWidget(
      MaterialApp(
        home: AiQuizGenerateScreen(
          generator: fake,
          pickInput: (_) async => AiQuizPickedInput(
            label: 'notes.jpg',
            attachments: [
              AiQuizAttachment(
                mimeType: 'image/jpeg',
                bytes: Uint8List.fromList([1, 2, 3]),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    expect(find.text('notes.jpg'), findsOneWidget);
    await tester.ensureVisible(find.text('Generate quiz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate quiz'));
    await tester.pumpAndSettle();
    expect(find.textContaining('What is 2 + 2?'), findsOneWidget);
    expect(fake.lastMedia, isNotNull);
    expect(fake.lastMedia!.single.mimeType, 'image/jpeg');
    expect(fake.lastMedia!.single.bytes, [1, 2, 3]);
    expect(fake.lastText, isNull);
  });

  testWidgets('documents text file reuses the text path', (tester) async {
    final fake = FakeAiQuizGenerator();
    await tester.pumpWidget(
      MaterialApp(
        home: AiQuizGenerateScreen(
          generator: fake,
          pickInput: (_) async => const AiQuizPickedInput(
            label: 'lesson.txt',
            text: 'Addition basics: 2 + 2 is 4.',
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
    expect(find.textContaining('What is 2 + 2?'), findsOneWidget);
    expect(fake.lastText, 'Addition basics: 2 + 2 is 4.');
    expect(fake.lastMedia, isNull);
  });

  testWidgets('pick cancelled does nothing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiQuizGenerateScreen(
          generator: FakeAiQuizGenerator(),
          pickInput: (_) async => null,
        ),
      ),
    );
    await tester.tap(find.text('Picture'));
    await tester.pumpAndSettle();
    expect(find.byType(Chip), findsNothing);
    expect(find.textContaining('What is 2 + 2?'), findsNothing);
  });

  testWidgets('pick denied shows a message without crashing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiQuizGenerateScreen(
          generator: FakeAiQuizGenerator(),
          pickInput: (_) async => throw const FormatException(
            'Permission denied — allow camera and photo access to '
            'use this, then try again.',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Permission denied'), findsOneWidget);
    expect(find.textContaining('What is 2 + 2?'), findsNothing);
  });

  testWidgets('generator failure shows an error, never fake questions',
      (tester) async {
    final fake = FakeAiQuizGenerator(
      result: const AiQuizGeneration(
        questions: [],
        error: 'AI generation failed.',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AiQuizGenerateScreen(
          generator: fake,
          pickInput: (_) async => AiQuizPickedInput(
            label: 'notes.jpg',
            attachments: [
              AiQuizAttachment(
                mimeType: 'image/jpeg',
                bytes: Uint8List.fromList([9]),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Generate quiz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate quiz'));
    await tester.pumpAndSettle();
    expect(find.text('AI generation failed.'), findsOneWidget);
    expect(find.textContaining('What is 2 + 2?'), findsNothing);
  });
}
