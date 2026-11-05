// Widget tests for the AI Quiz tipid guards: same-input reuse,
// large-request confirm, and the double-call guard. Uses a
// counting fake generator: no network, no model, no quota spent.
import 'package:estudyantego/features/ai_quiz_generate_screen.dart';
import 'package:estudyantego/features/ai_quiz_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counting fake mirroring the FakeAiQuizGenerator pattern from
/// test/ai_quiz_generate_screen_test.dart, plus a call counter and
/// an optional delay (for the double-call guard test).
class CountingFakeAiQuizGenerator implements AiQuizGenerator {
  CountingFakeAiQuizGenerator({this.delay = Duration.zero});

  final Duration delay;
  int callCount = 0;

  static const canned = AiQuizGeneration(questions: [
    AiQuizQuestion(
      question: 'What is 2 + 2?',
      options: ['3', '4', '5', '6'],
      correctIndex: 1,
      explanation: 'Basic addition.',
    ),
  ]);

  @override
  Future<AiQuizGeneration> generateFromText(
    String contextText, {
    int questionCount = 5,
    String difficulty = 'medium',
    List<String> questionTypes = const ['mcq'],
  }) async {
    callCount++;
    if (delay > Duration.zero) await Future.delayed(delay);
    return canned;
  }

  @override
  Future<AiQuizGeneration> generateFromMedia(
    List<AiQuizAttachment> attachments, {
    int questionCount = 5,
    String difficulty = 'medium',
    List<String> questionTypes = const ['mcq'],
  }) async {
    callCount++;
    if (delay > Duration.zero) await Future.delayed(delay);
    return canned;
  }

  @override
  Future<String> explainMore({
    required String question,
    required String correctAnswer,
    String explanation = '',
  }) async =>
      'Canned AI explanation.';
}

Future<void> _pumpScreen(
    WidgetTester tester, CountingFakeAiQuizGenerator fake) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: AiQuizGenerateScreen(generator: fake)),
  );
}

Future<void> _generate(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Generate quiz'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Generate quiz'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'same input again shows reuse dialog; Gamitin yung dati keeps calls at 1',
      (tester) async {
    final fake = CountingFakeAiQuizGenerator();
    await _pumpScreen(tester, fake);
    await tester.enterText(
      find.byType(TextField).at(0),
      'Addition basics: 2 + 2 is 4.',
    );
    await _generate(tester);
    expect(fake.callCount, 1);
    expect(find.textContaining('What is 2 + 2?'), findsOneWidget);

    // Same input, same settings: no new call, reuse dialog instead.
    await _generate(tester);
    expect(
      find.text('Walang bagong AI call — ginamit ulit yung huling quiz'),
      findsOneWidget,
    );
    await tester.tap(find.text('Gamitin yung dati'));
    await tester.pumpAndSettle();
    expect(fake.callCount, 1);
    expect(find.textContaining('What is 2 + 2?'), findsOneWidget);
    expect(
      find.text('Tip: i-save mo para magamit ulit nang walang bagong AI call.'),
      findsOneWidget,
    );
  });

  testWidgets('reuse dialog Generate ulit raises calls to 2', (tester) async {
    final fake = CountingFakeAiQuizGenerator();
    await _pumpScreen(tester, fake);
    await tester.enterText(
      find.byType(TextField).at(0),
      'Addition basics: 2 + 2 is 4.',
    );
    await _generate(tester);
    expect(fake.callCount, 1);

    await _generate(tester);
    expect(
      find.text('Walang bagong AI call — ginamit ulit yung huling quiz'),
      findsOneWidget,
    );
    await tester.tap(find.text('Generate ulit (gagamit ng quota)'));
    await tester.pumpAndSettle();
    expect(fake.callCount, 2);
    expect(find.textContaining('What is 2 + 2?'), findsOneWidget);
  });

  testWidgets(
      '50 questions shows confirm dialog; Cancel keeps calls at 0, Confirm makes 1',
      (tester) async {
    final fake = CountingFakeAiQuizGenerator();
    await _pumpScreen(tester, fake);
    await tester.enterText(
      find.byType(TextField).at(0),
      'Addition basics: 2 + 2 is 4.',
    );
    await tester.ensureVisible(find.text('50'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('50'));
    await tester.pumpAndSettle();

    // Cancel: zero model calls, no questions.
    await _generate(tester);
    expect(find.text('Malaking request ito'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.callCount, 0);
    expect(find.textContaining('What is 2 + 2?'), findsNothing);

    // Confirm: exactly one call.
    await _generate(tester);
    expect(find.text('Malaking request ito'), findsOneWidget);
    await tester.tap(find.text('Generate pa rin'));
    await tester.pumpAndSettle();
    expect(fake.callCount, 1);
    expect(find.textContaining('What is 2 + 2?'), findsOneWidget);
  });

  testWidgets('rapid Generate taps while loading make only one call',
      (tester) async {
    final fake = CountingFakeAiQuizGenerator(
      delay: const Duration(milliseconds: 300),
    );
    await _pumpScreen(tester, fake);
    await tester.enterText(
      find.byType(TextField).at(0),
      'Addition basics: 2 + 2 is 4.',
    );
    await tester.ensureVisible(find.text('Generate quiz'));
    await tester.pumpAndSettle();
    // First tap starts the call; the button is disabled while
    // loading, so a second tap cannot start another call.
    await tester.tap(find.text('Generate quiz'));
    await tester.pump();
    await tester.tap(find.text('Generate quiz'));
    await tester.pumpAndSettle();
    expect(fake.callCount, 1);
    expect(find.textContaining('What is 2 + 2?'), findsOneWidget);
  });

  testWidgets('pasted-text character count is shown', (tester) async {
    final fake = CountingFakeAiQuizGenerator();
    await _pumpScreen(tester, fake);
    const text = 'Addition basics: 2 + 2 is 4.';
    await tester.enterText(find.byType(TextField).at(0), text);
    await tester.pump();
    expect(find.text('${text.length} characters'), findsOneWidget);
  });
}
