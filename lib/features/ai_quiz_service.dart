// AI quiz generation — Context to Quiz via Firebase AI Logic.
//
// HONEST SPLIT (binding):
// - This service DISPLAYS nothing and GRANTS nothing. It only turns
//   pasted study text — or attached photos/documents — into quiz
//   questions by calling Gemini through the Firebase AI Logic SDK
//   (Gemini Developer API backend).
// - No API key lives in the app: the Gemini Developer API backend
//   needs none when called through AI Logic. App Check (activated
//   in firebase_init.dart) is what protects these calls.
// - The service NEVER throws to the UI: every failure (no network,
//   App Check not registered, quota, malformed model output) is
//   returned as an [AiQuizGeneration] with an [AiQuizGeneration.error]
//   message the UI can show.
// - No credits, no points, no Firestore writes. Generated quizzes
//   are saved only to the existing LOCAL quiz store when the user
//   taps Save (same store the Notes screen already uses).
// - OCR HONESTY: there is NO dedicated OCR plugin or engine here.
//   Photos and PDFs are read by Gemini multimodal (image/PDF bytes
//   sent as inline data), which is the existing input path. Calling
//   that "OCR" would overstate it, so the UI must not claim a
//   separate OCR step.
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';

import 'student/student_data.dart';

/// One generated question. The original MCQ shape is preserved
/// (question/options/correctIndex) and the other types reuse the
/// local model's encoding: 'id' uses [answer]; 'enum' and 'fill'
/// use [answers] (one per line / blank, in order); 'match' uses
/// [lefts]/[rights] (paired, in order). [type] defaults to 'mcq'
/// so older callers keep working.
class AiQuizQuestion {
  const AiQuizQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    this.type = 'mcq',
    this.answer = '',
    this.answers = const [],
    this.lefts = const [],
    this.rights = const [],
    this.learningTip = '',
  });

  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String type;
  final String answer;
  final List<String> answers;
  final List<String> lefts;
  final List<String> rights;
  final String learningTip;

  /// Maps onto the app's existing local quiz model.
  QuizQuestion toQuizQuestion() {
    switch (type) {
      case 'tf':
        return QuizQuestion(
          type: 'tf',
          question: question,
          options: const ['True', 'False'],
          correctIndex: correctIndex,
          answer: correctIndex == 0 ? 'True' : 'False',
          explanation: explanation,
          learningTip: learningTip,
        );
      case 'id':
        return QuizQuestion(
          type: 'id',
          question: question,
          options: const [],
          correctIndex: 0,
          answer: answer,
          explanation: explanation,
          learningTip: learningTip,
        );
      case 'enum':
        return QuizQuestion(
          type: 'enum',
          question: question,
          options: const [],
          correctIndex: 0,
          answer: answers.join('\n'),
          explanation: explanation,
          learningTip: learningTip,
        );
      case 'match':
        return QuizQuestion(
          type: 'match',
          question: question,
          options: lefts,
          correctIndex: 0,
          answer: rights.join('\n'),
          explanation: explanation,
          learningTip: learningTip,
        );
      case 'fill':
        return QuizQuestion(
          type: 'fill',
          question: question,
          options: const [],
          correctIndex: 0,
          answer: answers.join('\n'),
          explanation: explanation,
          learningTip: learningTip,
        );
      default:
        return QuizQuestion(
          type: 'mcq',
          question: question,
          options: options,
          correctIndex: correctIndex,
          answer: options[correctIndex],
          explanation: explanation,
          learningTip: learningTip,
        );
    }
  }
}

/// Allowed AI question types, in the local model's encoding.
const aiQuizQuestionTypes = ['mcq', 'tf', 'id', 'enum', 'match', 'fill'];

String normalizeAiQuizType(String? value) =>
    aiQuizQuestionTypes.contains(value) ? value! : 'mcq';

String aiQuizTypeSchema() => 'Each object has "question" (string) and '
    '"type" (one of "mcq", "tf", "id", "enum", "match", "fill"), plus '
    'an "explanation" (one short sentence) and an optional '
    '"learningTip" (one short memory aid). Per type: mcq needs '
    '"options" (exactly 4 strings) and "correctIndex" (0-3); tf needs '
    '"correctIndex" (0 = True, 1 = False); id needs "answer" '
    '(string); enum needs "answers" (array of at least 2 strings); '
    'match needs "pairs" (array of at least 2 objects with "left" and '
    '"right" strings); fill needs the question to contain ____ blanks '
    'and "answers" (one string per blank, in order). Only use the '
    'requested types. Generate ONLY from the provided material: if '
    'an answer is not in the material, do not invent it — skip that '
    'question instead.';

/// Outcome of one generation attempt. Either [questions] is non-empty
/// or [error] explains why nothing could be generated — never both
/// empty, never a thrown exception.
class AiQuizGeneration {
  const AiQuizGeneration({required this.questions, this.error});

  final List<AiQuizQuestion> questions;
  final String? error;

  bool get succeeded => questions.isNotEmpty && error == null;
}

/// One file attached to a generation request: raw bytes plus the
/// MIME type Gemini needs to read them (image/jpeg, image/png,
/// application/pdf, ...). Plain-text files are NOT sent this way —
/// they are read as text and reuse [generateFromText].
class AiQuizAttachment {
  const AiQuizAttachment({required this.mimeType, required this.bytes});

  final String mimeType;
  final Uint8List bytes;
}

/// MIME types Gemini accepts as inline data for quiz generation.
/// Anything else (including docx — a zip of XML, not readable as
/// inline data) is rejected with a user-facing error, never faked.
const Set<String> kAiQuizMediaMimeTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
  'application/pdf',
};

/// Total inline-data budget per request. Gemini's inline limit is
/// 20 MB; 15 MB leaves headroom for the prompt and encoding.
const int kAiQuizMaxMediaBytes = 15 * 1024 * 1024;

/// Builds the multimodal request for attached study material.
/// Pure (no model call) so tests can assert on its parts: a text
/// prompt first, then one inline-data part per attachment.
Content buildMediaContent(
  List<AiQuizAttachment> attachments, {
  int questionCount = 5,
  String difficulty = 'medium',
  List<String> questionTypes = const ['mcq'],
}) {
  final count = clampQuizQuestionCount(questionCount);
  final types = questionTypes.isEmpty ? ['mcq'] : questionTypes;
  final largeCountNote = count > 10
      ? ' If you cannot produce that many distinct questions from the material, produce as many valid distinct questions as you can — never invent, repeat, or pad questions.'
      : '';
  final prompt = 'You are a study assistant. Read the attached study '
      'material (photos of notes and/or documents — read by the '
      'model itself; there is no separate OCR step) and create '
      'exactly $count quiz questions from it, at '
      '${normalizeDifficulty(difficulty)} difficulty, using only '
      'these question types: ${types.join(', ')}.$largeCountNote '
      'Reply with JSON ONLY — no explanation, no Markdown fences '
      'around anything except the JSON itself. The JSON must be an '
      'array of objects. ${aiQuizTypeSchema()}';
  return Content.multi([
    TextPart(prompt),
    for (final attachment in attachments)
      InlineDataPart(attachment.mimeType, attachment.bytes),
  ]);
}

/// Contract for quiz generation. Tests inject a fake; production uses
/// [FirebaseAiQuizGenerator].
abstract class AiQuizGenerator {
  Future<AiQuizGeneration> generateFromText(
    String contextText, {
    int questionCount = 5,
    String difficulty = 'medium',
    List<String> questionTypes = const ['mcq'],
  });

  Future<AiQuizGeneration> generateFromMedia(
    List<AiQuizAttachment> attachments, {
    int questionCount = 5,
    String difficulty = 'medium',
    List<String> questionTypes = const ['mcq'],
  });

  /// A grounded follow-up explanation for one answered question.
  /// Implementations must use ONLY the question, the correct
  /// answer, and the stored explanation as context, and must say
  /// the material does not explain further rather than inventing
  /// an explanation. Never throws: failures return a fallback
  /// string the UI can show.
  Future<String> explainMore({
    required String question,
    required String correctAnswer,
    String explanation = '',
  });
}

/// Pure parser: extracts validated questions from raw model text.
///
/// Tolerant by design: strips Markdown code fences, accepts either a
/// bare JSON array or an object with a `questions` key, skips invalid
/// items (empty question, wrong option count, out-of-range answer)
/// instead of failing the whole batch. Returns an empty list when
/// nothing valid can be recovered.
List<AiQuizQuestion> parseAiQuizJson(String raw) {
  var text = raw.trim();
  // Strip a surrounding Markdown code fence if the model added one.
  if (text.startsWith('```')) {
    final firstNewline = text.indexOf('\n');
    if (firstNewline >= 0) text = text.substring(firstNewline + 1);
    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }
    text = text.trim();
  }
  try {
    final decoded = jsonDecode(text);
    final List<dynamic> items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map && decoded['questions'] is List) {
      items = decoded['questions'] as List;
    } else {
      return [];
    }
    List<String> cleanStrings(Object? raw) {
      if (raw is! List) return [];
      return raw
          .whereType<String>()
          .map((o) => o.trim())
          .where((o) => o.isNotEmpty)
          .toList();
    }

    final questions = <AiQuizQuestion>[];
    for (final item in items) {
      if (item is! Map) continue;
      final question = (item['question'] as String?)?.trim() ?? '';
      if (question.isEmpty) continue;
      final type = normalizeAiQuizType(item['type'] as String?);
      final explanation = (item['explanation'] as String?)?.trim() ?? '';
      final learningTip = (item['learningTip'] as String?)?.trim() ?? '';
      switch (type) {
        case 'mcq':
          final options = cleanStrings(item['options']);
          final correctIndex = item['correctIndex'];
          if (options.length != 4) continue;
          if (correctIndex is! int ||
              correctIndex < 0 ||
              correctIndex >= options.length) {
            continue;
          }
          questions.add(AiQuizQuestion(
            question: question,
            options: options,
            correctIndex: correctIndex,
            explanation: explanation,
            learningTip: learningTip,
          ));
        case 'tf':
          final correctIndex = item['correctIndex'];
          if (correctIndex is! int ||
              correctIndex < 0 ||
              correctIndex > 1) {
            continue;
          }
          questions.add(AiQuizQuestion(
            question: question,
            options: const ['True', 'False'],
            correctIndex: correctIndex,
            type: 'tf',
            explanation: explanation,
            learningTip: learningTip,
          ));
        case 'id':
          final answer = (item['answer'] as String?)?.trim() ?? '';
          if (answer.isEmpty) continue;
          questions.add(AiQuizQuestion(
            question: question,
            options: const [],
            correctIndex: 0,
            type: 'id',
            answer: answer,
            explanation: explanation,
            learningTip: learningTip,
          ));
        case 'enum':
          final answers = cleanStrings(item['answers']);
          if (answers.length < 2) continue;
          questions.add(AiQuizQuestion(
            question: question,
            options: const [],
            correctIndex: 0,
            type: 'enum',
            answers: answers,
            explanation: explanation,
            learningTip: learningTip,
          ));
        case 'match':
          final pairsRaw = item['pairs'];
          if (pairsRaw is! List) continue;
          final lefts = <String>[];
          final rights = <String>[];
          var valid = true;
          for (final pair in pairsRaw) {
            if (pair is! Map) {
              valid = false;
              break;
            }
            final left = (pair['left'] as String?)?.trim() ?? '';
            final right = (pair['right'] as String?)?.trim() ?? '';
            if (left.isEmpty || right.isEmpty) {
              valid = false;
              break;
            }
            lefts.add(left);
            rights.add(right);
          }
          if (!valid || lefts.length < 2) continue;
          questions.add(AiQuizQuestion(
            question: question,
            options: const [],
            correctIndex: 0,
            type: 'match',
            lefts: lefts,
            rights: rights,
            explanation: explanation,
            learningTip: learningTip,
          ));
        case 'fill':
          final blanks = '____'.allMatches(question).length;
          final answers = cleanStrings(item['answers']);
          if (blanks == 0 || answers.length != blanks) continue;
          questions.add(AiQuizQuestion(
            question: question,
            options: const [],
            correctIndex: 0,
            type: 'fill',
            answers: answers,
            explanation: explanation,
            learningTip: learningTip,
          ));
      }
    }
    return questions;
  } catch (_) {
    return [];
  }
}

/// Production generator over the Firebase AI Logic SDK.
///
/// The model is built lazily on first generation (not in the
/// constructor) so constructing this class never touches Firebase —
/// safe before Firebase init and safe in unit tests that only
/// exercise the empty-input path.
class FirebaseAiQuizGenerator implements AiQuizGenerator {
  FirebaseAiQuizGenerator({GenerativeModel? model}) : _modelOverride = model;

  final GenerativeModel? _modelOverride;

  GenerativeModel get _model =>
      _modelOverride ??
      FirebaseAI.googleAI().generativeModel(model: 'gemini-3.8-flash');

  @override
  Future<AiQuizGeneration> generateFromText(
    String contextText, {
    int questionCount = 5,
    String difficulty = 'medium',
    List<String> questionTypes = const ['mcq'],
  }) async {
    final context = contextText.trim();
    if (context.isEmpty) {
      return const AiQuizGeneration(
        questions: [],
        error: 'Paste some study text first.',
      );
    }
    final count = clampQuizQuestionCount(questionCount);
    final types = questionTypes.isEmpty ? ['mcq'] : questionTypes;
    final largeCountNote = count > 10
        ? ' If you cannot produce that many distinct questions from the material, produce as many valid distinct questions as you can — never invent, repeat, or pad questions.'
        : '';
    final prompt = 'You are a study assistant. Create exactly $count '
        'quiz questions from the study text below, at '
        '${normalizeDifficulty(difficulty)} difficulty, using only '
        'these question types: ${types.join(', ')}.$largeCountNote '
        'Reply with JSON ONLY — no explanation, no Markdown fences '
        'around anything except the JSON itself. The JSON must be an '
        'array of objects. ${aiQuizTypeSchema()}\n\n'
        'Study text:\n$context';
    return _callModel([Content.text(prompt)]);
  }

  @override
  Future<AiQuizGeneration> generateFromMedia(
    List<AiQuizAttachment> attachments, {
    int questionCount = 5,
    String difficulty = 'medium',
    List<String> questionTypes = const ['mcq'],
  }) async {
    if (attachments.isEmpty) {
      return const AiQuizGeneration(
        questions: [],
        error: 'Attach a photo or document first.',
      );
    }
    if (attachments
        .any((a) => !kAiQuizMediaMimeTypes.contains(a.mimeType))) {
      return const AiQuizGeneration(
        questions: [],
        error: 'Only images and PDF documents are supported for quiz '
            'generation.',
      );
    }
    final totalBytes =
        attachments.fold<int>(0, (sum, a) => sum + a.bytes.length);
    if (totalBytes > kAiQuizMaxMediaBytes) {
      return const AiQuizGeneration(
        questions: [],
        error: 'The attached files are too large — pick files '
            'totalling under 15 MB.',
      );
    }
    return _callModel([
      buildMediaContent(
        attachments,
        questionCount: questionCount,
        difficulty: difficulty,
        questionTypes: questionTypes,
      ),
    ]);
  }

  @override
  Future<String> explainMore({
    required String question,
    required String correctAnswer,
    String explanation = '',
  }) async {
    const fallback = 'No explanation available.';
    if (question.trim().isEmpty || correctAnswer.trim().isEmpty) {
      return explanation.trim().isNotEmpty ? explanation.trim() : fallback;
    }
    // Grounded by construction: the model gets ONLY the question,
    // the correct answer, and the stored explanation. It is told
    // to say the material does not explain further rather than
    // invent anything — and any failure falls back to the stored
    // explanation, never to a fabricated one.
    final prompt = 'You are a study tutor. Explain the correct answer '
        'to this quiz question in 2-4 short, easy sentences, using '
        'ONLY the information below. Do not add facts that are not '
        'in it. If it does not explain why the answer is correct, '
        'reply exactly: "The provided material does not explain '
        'this further."\n\n'
        'Question: ${question.trim()}\n'
        'Correct answer: ${correctAnswer.trim()}\n'
        'Stored explanation: ${explanation.trim()}';
    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text?.trim() ?? '';
      if (text.isEmpty) {
        return explanation.trim().isNotEmpty ? explanation.trim() : fallback;
      }
      return text;
    } catch (_) {
      return explanation.trim().isNotEmpty ? explanation.trim() : fallback;
    }
  }

  /// One model call shared by the text and media paths: same JSON
  /// parsing, same never-throws contract.
  Future<AiQuizGeneration> _callModel(List<Content> content) async {
    try {
      final response = await _model.generateContent(content);
      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        return const AiQuizGeneration(
          questions: [],
          error: 'The AI returned an empty response. Try again.',
        );
      }
      final questions = parseAiQuizJson(text);
      if (questions.isEmpty) {
        return const AiQuizGeneration(
          questions: [],
          error: 'Could not read the AI response as quiz questions. '
              'Try again with shorter text.',
        );
      }
      return AiQuizGeneration(questions: questions);
    } catch (e) {
      return AiQuizGeneration(
        questions: [],
        error: 'AI generation failed. Check your connection and that '
            'App Check is registered, then try again. ($e)',
      );
    }
  }
}
