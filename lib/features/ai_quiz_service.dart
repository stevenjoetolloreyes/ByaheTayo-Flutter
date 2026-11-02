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
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';

import 'student/student_data.dart';

/// One generated multiple-choice question.
class AiQuizQuestion {
  const AiQuizQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  /// Maps onto the app's existing local quiz model (MCQ type).
  QuizQuestion toQuizQuestion() => QuizQuestion(
        type: 'mcq',
        question: question,
        options: options,
        correctIndex: correctIndex,
        answer: options[correctIndex],
        explanation: explanation,
      );
}

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
}) {
  final count = questionCount.clamp(1, 10);
  final prompt = 'You are a study assistant. Read the attached study '
      'material (photos of notes and/or documents) and create exactly '
      '$count multiple-choice quiz questions from it. '
      'Reply with JSON ONLY — no explanation, no Markdown fences '
      'around anything except the JSON itself. The JSON must be an '
      'array of objects with exactly these fields: "question" '
      '(string), "options" (array of exactly 4 strings), '
      '"correctIndex" (integer 0-3 pointing at the correct option), '
      'and "explanation" (one short sentence explaining the answer).';
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
  });

  Future<AiQuizGeneration> generateFromMedia(
    List<AiQuizAttachment> attachments, {
    int questionCount = 5,
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
    final questions = <AiQuizQuestion>[];
    for (final item in items) {
      if (item is! Map) continue;
      final question = (item['question'] as String?)?.trim() ?? '';
      final rawOptions = item['options'];
      if (question.isEmpty || rawOptions is! List) continue;
      final options = rawOptions
          .whereType<String>()
          .map((o) => o.trim())
          .where((o) => o.isNotEmpty)
          .toList();
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
        explanation: (item['explanation'] as String?)?.trim() ?? '',
      ));
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
  }) async {
    final context = contextText.trim();
    if (context.isEmpty) {
      return const AiQuizGeneration(
        questions: [],
        error: 'Paste some study text first.',
      );
    }
    final count = questionCount.clamp(1, 10);
    final prompt = 'You are a study assistant. Create exactly $count '
        'multiple-choice quiz questions from the study text below. '
        'Reply with JSON ONLY — no explanation, no Markdown fences '
        'around anything except the JSON itself. The JSON must be an '
        'array of objects with exactly these fields: "question" '
        '(string), "options" (array of exactly 4 strings), '
        '"correctIndex" (integer 0-3 pointing at the correct option), '
        'and "explanation" (one short sentence explaining the answer).\n\n'
        'Study text:\n$context';
    return _callModel([Content.text(prompt)]);
  }

  @override
  Future<AiQuizGeneration> generateFromMedia(
    List<AiQuizAttachment> attachments, {
    int questionCount = 5,
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
    return _callModel(
        [buildMediaContent(attachments, questionCount: questionCount)]);
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
