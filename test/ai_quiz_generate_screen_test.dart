// Widget tests for the AI quiz generate screen + its entry point
// in the Notes screen. Uses a fake generator: no network, no model.
import 'package:estudyantego/features/ai_quiz_generate_screen.dart';
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
      const MaterialApp(
        home: AiQuizGenerateScreen(generator: FakeAiQuizGenerator()),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'Addition basics: 2 + 2 is 4.',
    );
    await tester.tap(find.text('Generate quiz'));
    await tester.pumpAndSettle();
    expect(find.textContaining('What is 2 + 2?'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
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
}
