// Unit tests for the AI quiz parser + generator contract.
// No network, no real model calls: the parser is pure and the
// generator is exercised through a fake.
import 'package:estudyantego/features/ai_quiz_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAiQuizGenerator implements AiQuizGenerator {
  const FakeAiQuizGenerator({this.result});

  final AiQuizGeneration? result;

  @override
  Future<AiQuizGeneration> generateFromText(
    String contextText, {
    int questionCount = 5,
  }) async {
    return result ??
        const AiQuizGeneration(questions: [
          AiQuizQuestion(
            question: 'What is 2 + 2?',
            options: ['3', '4', '5', '6'],
            correctIndex: 1,
            explanation: 'Basic addition.',
          ),
        ]);
  }
}

void main() {
  group('parseAiQuizJson', () {
    test('parses a bare JSON array', () {
      const raw = '[{"question":"Capital of France?",'
          '"options":["Berlin","Paris","Rome","Madrid"],'
          '"correctIndex":1,"explanation":"Paris is the capital."}]';
      final questions = parseAiQuizJson(raw);
      expect(questions.length, 1);
      expect(questions.first.question, 'Capital of France?');
      expect(questions.first.options[1], 'Paris');
      expect(questions.first.correctIndex, 1);
    });

    test('strips Markdown code fences', () {
      const raw = '```json\n[{"question":"Q?",'
          '"options":["a","b","c","d"],'
          '"correctIndex":0,"explanation":""}]\n```';
      expect(parseAiQuizJson(raw).length, 1);
    });

    test('accepts an object with a questions key', () {
      const raw = '{"questions":[{"question":"Q?",'
          '"options":["a","b","c","d"],'
          '"correctIndex":2,"explanation":""}]}';
      expect(parseAiQuizJson(raw).first.correctIndex, 2);
    });

    test('malformed JSON yields an empty list, never a throw', () {
      expect(parseAiQuizJson('not json at all'), isEmpty);
      expect(parseAiQuizJson(''), isEmpty);
      expect(parseAiQuizJson('{"nope": true}'), isEmpty);
    });

    test('skips invalid items but keeps valid ones', () {
      const raw = '[{"question":"Good?",'
          '"options":["a","b","c","d"],'
          '"correctIndex":0,"explanation":""},'
          '{"question":"Bad options",'
          '"options":["a","b"],'
          '"correctIndex":0,"explanation":""},'
          '{"question":"Bad index",'
          '"options":["a","b","c","d"],'
          '"correctIndex":9,"explanation":""},'
          '{"question":"",'
          '"options":["a","b","c","d"],'
          '"correctIndex":0,"explanation":""}]';
      final questions = parseAiQuizJson(raw);
      expect(questions.length, 1);
      expect(questions.first.question, 'Good?');
    });
  });

  group('FirebaseAiQuizGenerator empty input', () {
    test('empty context returns an error without touching Firebase', () async {
      // No model override: construction must not touch Firebase,
      // and the empty check must fire before any model access.
      final generator = FirebaseAiQuizGenerator();
      final result = await generator.generateFromText('   ');
      expect(result.succeeded, isFalse);
      expect(result.error, contains('Paste some study text'));
    });
  });

  group('AiQuizQuestion mapping', () {
    test('maps onto the local QuizQuestion model', () {
      const q = AiQuizQuestion(
        question: 'Q?',
        options: ['a', 'b', 'c', 'd'],
        correctIndex: 3,
        explanation: 'Because.',
      );
      final mapped = q.toQuizQuestion();
      expect(mapped.type, 'mcq');
      expect(mapped.answer, 'd');
      expect(mapped.correctIndex, 3);
    });
  });
}
