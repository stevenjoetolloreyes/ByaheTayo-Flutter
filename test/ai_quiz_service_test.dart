// Unit tests for the AI quiz parser + the on-device generator contract.
// No network, no model calls: the parser is pure and the on-device
// generator is rule-based (no external API).
import 'dart:typed_data';

import 'package:estudyantego/features/ai_quiz_service.dart';
import 'package:estudyantego/features/estudyantego_ai.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAiQuizGenerator implements AiQuizGenerator {
  FakeAiQuizGenerator({this.result});

  final AiQuizGeneration? result;

  /// Last call received, for wiring assertions in screen tests.
  String? lastText;
  List<AiQuizAttachment>? lastMedia;
  String? lastDifficulty;
  List<String>? lastTypes;

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
    lastText = contextText;
    lastDifficulty = difficulty;
    lastTypes = questionTypes;
    return result ?? canned;
  }

  @override
  Future<AiQuizGeneration> generateFromMedia(
    List<AiQuizAttachment> attachments, {
    int questionCount = 5,
    String difficulty = 'medium',
    List<String> questionTypes = const ['mcq'],
  }) async {
    lastMedia = attachments;
    lastDifficulty = difficulty;
    lastTypes = questionTypes;
    return result ?? canned;
  }

  @override
  Future<String> explainMore({
    required String question,
    required String correctAnswer,
    String explanation = '',
  }) async =>
      'Canned AI explanation.';
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

    test('parses tf, id, enum, match, and fill items', () {
      const raw = '[{\"question\":\"True?\",\"type\":\"tf\",'
          '\"correctIndex\":1,\"explanation\":\"\"},'
          '{\"question\":\"Capital?\",\"type\":\"id\",'
          '\"answer\":\"Vigan\",\"explanation\":\"\"},'
          '{\"question\":\"Name two colors.\",\"type\":\"enum\",'
          '\"answers\":[\"red\",\"blue\"],\"explanation\":\"\"},'
          '{\"question\":\"Match.\",\"type\":\"match\",'
          '\"pairs\":[{\"left\":\"a\",\"right\":\"1\"},'
          '{\"left\":\"b\",\"right\":\"2\"}],\"explanation\":\"\"},'
          '{\"question\":\"The ____ is red.\",\"type\":\"fill\",'
          '\"answers\":[\"apple\"],\"explanation\":\"\"}]';
      final questions = parseAiQuizJson(raw);
      expect(questions.length, 5);
      expect(questions.map((q) => q.type),
          ['tf', 'id', 'enum', 'match', 'fill']);
      expect(questions[0].toQuizQuestion().options, ['True', 'False']);
      expect(questions[1].toQuizQuestion().answer, 'Vigan');
      expect(questions[2].toQuizQuestion().answer, 'red\nblue');
      expect(questions[3].toQuizQuestion().options, ['a', 'b']);
      expect(questions[3].toQuizQuestion().answer, '1\n2');
      expect(questions[4].toQuizQuestion().answer, 'apple');
    });

    test('skips fill items whose answer count mismatches blanks', () {
      const raw = '[{\"question\":\"____ and ____.\",\"type\":\"fill\",'
          '\"answers\":[\"only-one\"],\"explanation\":\"\"}]';
      expect(parseAiQuizJson(raw), isEmpty);
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

  group('OnDeviceAiQuizGenerator empty input', () {
    test('empty context returns an error, no external call', () async {
      final generator = OnDeviceAiQuizGenerator();
      final result = await generator.generateFromText('   ');
      expect(result.succeeded, isFalse);
      expect(result.error, contains('Paste some study text'));
    });

    test('generates questions from a definition, at most 5', () async {
      final generator = OnDeviceAiQuizGenerator();
      final result = await generator.generateFromText(
        'CPU is the Central Processing Unit. RAM is temporary memory. '
        'ROM is read-only memory. SSD is fast storage. The keyboard '
        'is an input device. The monitor is an output device.',
      );
      expect(result.succeeded, isTrue);
      expect(result.questions.length, lessThanOrEqualTo(5));
      expect(result.questions.length, greaterThan(0));
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

  group('OnDeviceAiQuizGenerator media guards', () {
    test('empty attachments return an error, no extraction', () async {
      final generator = OnDeviceAiQuizGenerator();
      final result = await generator.generateFromMedia([]);
      expect(result.succeeded, isFalse);
      expect(result.error, contains('Attach a photo'));
    });

    test('unsupported MIME type is rejected, never faked', () async {
      final generator = OnDeviceAiQuizGenerator();
      final result = await generator.generateFromMedia([
        AiQuizAttachment(
          mimeType: 'application/msword',
          bytes: Uint8List.fromList([1]),
        ),
      ]);
      expect(result.succeeded, isFalse);
      expect(result.error, contains('Only images, PDFs, and text files'));
    });

    test('oversized attachments are rejected before any extraction',
        () async {
      final generator = OnDeviceAiQuizGenerator();
      final result = await generator.generateFromMedia([
        AiQuizAttachment(
          mimeType: 'image/jpeg',
          bytes: Uint8List(kAiQuizMaxMediaBytes + 1),
        ),
      ]);
      expect(result.succeeded, isFalse);
      expect(result.error, contains('too large'));
    });
  });

}
