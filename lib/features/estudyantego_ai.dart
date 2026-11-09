// EstudyanteGO AI — the app's OWN built-in assistant.
//
// NO Gemini. NO external API. NO network, NO API key, NO quota.
// Everything here runs on the device: it reads the user's own
// notes/files, extracts key terms, and builds quiz questions,
// flashcards, and summaries from that text only. It never invents
// facts that are not in the material — a question is skipped when
// its answer is not in the text.
//
// What it does:
// * generateFromText — up to 5 questions from pasted/extracted
//   study text (multiple-choice with distractors drawn from the
//   SAME text, and fill-in-the-blank). The whole file is the
//   scope; nothing outside it is used.
// * generateFromMedia — images/PDF bytes are written to a temp
//   file, read on-device (ML Kit OCR for photos, pdfrx text layer
//   for PDFs) via NoteExtractService, then generated from text.
// * explainMore — returns the stored explanation, or says the
//   material does not explain further. Never invents.
// * answerChat — rule-based chat answers about quizzes,
//   flashcards, summaries, schedule, and fares. It states plainly
//   that it is built into the app and NOT an online AI.
// * keyPoints / flashcardsFromText — a key-points summary and
//   flip flashcards from the same extracted terms.
// * sampleComputerBasicsDeck — the "Computer Basics" sample deck
//   the preview shows, clearly marked as a sample. It is built-in
//   and never written to the user's storage; the pages show it
//   only while the user has no saved cards/quizzes of their own.
import 'dart:io';
import 'dart:math' as math;

import 'ai_quiz_service.dart';
import 'student/note_extract_service.dart';
import 'student/student_data.dart';

/// The one verified fare the AI answers from. No other fare is
/// ever stated by the AI — anything else must come from the app's
/// real route data, never from this file.
const String kAiCabugaoViganFareLine =
    'Cabugao → Vigan is ₱60 regular / ₱48 student.';

/// How many questions one generation produces at most.
const int kAiMaxQuestionsPerSet = 5;

/// One extracted key term: the term, its definition sentence, and
/// the source sentence it came from (used as the explanation).
class AiKeyTerm {
  const AiKeyTerm({
    required this.term,
    required this.definition,
    required this.sourceSentence,
  });

  final String term;
  final String definition;
  final String sourceSentence;
}

/// Split text into sentences. Splits on . ! ? and on line breaks,
/// trims, and drops empties and fragments shorter than 3 chars.
List<String> splitSentences(String text) {
  final out = <String>[];
  for (final chunk in text.split('\n')) {
    final line = chunk.trim();
    if (line.isEmpty) continue;
    // Split on sentence-ending punctuation followed by a space or
    // end of line, keeping the punctuation with the sentence.
    final parts = line.split(RegExp(r'(?<=[.!?])\s+'));
    for (final p in parts) {
      final s = p.trim();
      if (s.length >= 3) out.add(s);
    }
  }
  return out;
}

/// A small stopword set so single-word "terms" like "the" or
/// "this" never become flashcard fronts.
const Set<String> _stopwords = {
  'the', 'a', 'an', 'and', 'or', 'but', 'is', 'are', 'was', 'were', 'be',
  'been', 'it', 'its', 'this', 'that', 'these', 'those', 'in', 'on', 'at',
  'to', 'of', 'for', 'with', 'by', 'from', 'as', 'we', 'you', 'he',
  'she', 'they', 'i', 'my', 'your', 'his', 'her', 'their', 'our', 'not',
  'no', 'yes', 'if', 'then', 'so', 'do', 'does', 'did', 'can', 'could',
  'will', 'would', 'should', 'has', 'have', 'had', 'there', 'here',
  'when', 'where', 'which', 'who', 'whom', 'what', 'how', 'why', 'all',
  'any', 'some', 'more', 'most', 'other', 'into', 'over', 'under',
};

/// A bare year / date / number — not a real term or definition.
/// A question is never built around one of these, and one is never
/// a correct answer or a distractor. Matches: "2019", "2026", "42",
/// "1,000", "3.14", "2019-2020", "2019 - 2026", "Nov 2019",
/// "November 2019", "12/31/2019", "2019-12-31". A real term that
/// merely contains digits (e.g. "Windows 11", "COVID-19") does NOT
/// match — only a value that IS a date or number.
bool _isBareDateOrNumber(String value) {
  final v = value.trim();
  if (v.isEmpty) return true;
  // Pure number: digits with optional commas, decimal points, spaces.
  if (RegExp(r'^[\d.,\s]+$').hasMatch(v)) return true;
  // A 4-digit year, optionally a range ("2019", "2019-2020", "2019 - 26").
  if (RegExp(r'^(19|20)\d{2}(\s*[-–/]\s*(19|20)?\d{2})?$').hasMatch(v)) {
    return true;
  }
  // Month + year ("Nov 2019", "November 2019").
  if (RegExp(
    r'^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+(19|20)\d{2}$',
    caseSensitive: false,
  ).hasMatch(v)) {
    return true;
  }
  // A full date ("12/31/2019", "31-12-2019", "2019-12-31").
  if (RegExp(r'^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}$').hasMatch(v)) return true;
  if (RegExp(r'^(19|20)\d{2}[/-]\d{1,2}[/-]\d{1,2}$').hasMatch(v)) {
    return true;
  }
  return false;
}

/// A definition that is only a comma-separated list of proper-noun
/// items — an address, a list of names, a list of places — not an
/// explanation of the term. E.g. "Cabugao, Ilocos Sur, Philippines"
/// or "Places & Routes APIs, Meta / Facebook API". A real definition
/// either has no comma ("Central Processing Unit") or continues
/// with a descriptive clause ("..., which processes instructions").
/// A list of common nouns ("militarism, alliances, imperialism")
/// is kept — only a list of proper nouns is a fragment value.
/// A segment counts as a proper-noun phrase when every word in it
/// starts with an uppercase letter (Title Case / ALL-CAPS).
bool _isProperNounList(String value) {
  final segments = value.split(',');
  if (segments.length < 2) return false;
  for (final seg in segments) {
    final s = seg.trim();
    if (s.isEmpty) return false;
    // A proper-noun segment has no word starting with a
    // lowercase letter. (Title Case words like "Cabugao" DO
    // contain lowercase letters, so testing for any lowercase
    // letter would never match — the word's first letter is
    // what matters.)
    final words =
        RegExp(r'[A-Za-z]+').allMatches(s).map((m) => m.group(0)!);
    var sawWord = false;
    for (final w in words) {
      sawWord = true;
      if (RegExp(r'^[a-z]').hasMatch(w)) return false;
    }
    if (!sawWord) return false;
  }
  return true;
}

/// Extract (term, definition, source) triples from study text.
///
/// Definition patterns, in order:
/// * "Term: definition" / "Term - definition" (a labelled line).
/// * "Term is/are ..." / "Term refers to ..." (a definition
///   sentence). The term is the sentence's leading noun phrase
///   (up to 4 words, each starting with a letter).
/// * A sentence that repeats a term already found: the term is
///   reused with this sentence as an extra source, not a new term.
///
/// Terms are de-duplicated case-insensitively. Only terms with a
/// non-empty definition are kept, so every generated question has
/// a real answer in the text.
///
/// Only REAL term-and-definition pairs are kept (the improved
/// generation rules): a bare year / date / number is never a term
/// ("What is 2019?") and never a definition (a bare year as the
/// answer or a distractor), and a comma-separated list of proper
/// nouns (an address, a list of names) is a value, not a
/// definition. Pairs that fail these checks are skipped, never
/// turned into a question.
List<AiKeyTerm> extractKeyTerms(String text) {
  final terms = <AiKeyTerm>[];
  final seen = <String>{};
  final sentences = splitSentences(text);

  void add(String term, String definition, String source) {
    final t = term.trim();
    final d = definition.trim();
    if (t.isEmpty || d.isEmpty) return;
    // Never a bare year / date / number as the term ("What is
    // 2019?") or as the definition (a bare year as the answer or
    // a distractor, e.g. "2026").
    if (_isBareDateOrNumber(t) || _isBareDateOrNumber(d)) return;
    // A comma-separated list of proper nouns is a value (an
    // address, a list of names), not a definition of the term.
    if (_isProperNounList(d)) return;
    // Keep terms short (a term is a name, not a sentence).
    if (t.length > 48) return;
    final key = t.toLowerCase();
    if (seen.contains(key)) return;
    // A term must contain at least one real word (not a stopword
    // and not just a number).
    final words = t
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return;
    if (words.every((w) => _stopwords.contains(w.toLowerCase()))) return;
    seen.add(key);
    terms.add(AiKeyTerm(term: t, definition: d, sourceSentence: source));
  }

  for (final sentence in sentences) {
    // "Term: definition" or "Term - definition".
    final labelled = RegExp(r'^([A-Za-z0-9][A-Za-z0-9 .&/()-]{0,46})\s*[:\-–]\s+(.+)$')
        .firstMatch(sentence);
    if (labelled != null) {
      add(labelled.group(1)!, labelled.group(2)!, sentence);
      continue;
    }
    // "Term is/are ..." / "Term refers to ...".
    final isMatch = RegExp(
            r'^([A-Z][A-Za-z0-9 .&/()-]{0,46}?)\s+(is|are|refers to|means)\s+(.+)$')
        .firstMatch(sentence);
    if (isMatch != null) {
      final term = isMatch.group(1)!.trim();
      // The term is the leading noun phrase; drop a trailing
      // article/preposition the regex may have caught.
      final cleaned =
          term.replaceAll(RegExp(r'\s+(the|a|an|of|in|on|for)$'), '').trim();
      add(cleaned, isMatch.group(3)!, sentence);
      continue;
    }
    // "Term, ..." where the term is a short leading phrase followed
    // by a comma and a definition clause.
    final comma = RegExp(r'^([A-Z][A-Za-z0-9 .&/()-]{1,30}),\s+(.+)$')
        .firstMatch(sentence);
    if (comma != null) {
      add(comma.group(1)!, comma.group(2)!, sentence);
    }
  }

  // Fallback: if no definition pattern matched at all, use the
  // most frequent meaningful words as terms, with the sentence
  // they appear in as the definition. This keeps short note
  // fragments (a bare list of terms) usable instead of returning
  // nothing.
  if (terms.isEmpty) {
    final counts = <String, int>{};
    final firstSentence = <String, String>{};
    for (final sentence in sentences) {
      for (final word in sentence.split(RegExp(r'[^A-Za-z0-9]+'))) {
        final w = word.trim();
        if (w.length < 3) continue;
        if (_stopwords.contains(w.toLowerCase())) continue;
        final key = w.toLowerCase();
        counts[key] = (counts[key] ?? 0) + 1;
        firstSentence.putIfAbsent(key, () => sentence);
      }
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in ranked.take(8)) {
      final sentence = firstSentence[e.key]!;
      add(e.key, sentence, sentence);
    }
  }
  return terms;
}

/// The key points of a text: up to [maxPoints] sentences, in
/// source order, preferring sentences that contain an extracted
/// key term. Purely extractive — no sentence is rewritten.
List<String> keyPoints(String text, {int maxPoints = 3}) {
  final sentences = splitSentences(text);
  if (sentences.isEmpty) return const [];
  final terms = extractKeyTerms(text);
  final termWords = terms
      .map((t) => t.term.toLowerCase())
      .toSet();
  final scored = <(String, int)>[];
  for (final s in sentences) {
    final lower = s.toLowerCase();
    var score = 0;
    for (final t in termWords) {
      if (lower.contains(t)) score++;
    }
    // Prefer mid-length sentences (a real point, not a heading).
    if (s.length > 140) score -= 1;
    if (s.length < 20) score -= 1;
    scored.add((s, score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  final picked = scored.take(maxPoints).map((e) => e.$1).toList();
  // Restore source order so the summary reads like the notes.
  picked.sort((a, b) => sentences.indexOf(a).compareTo(sentences.indexOf(b)));
  return picked;
}

/// Flashcards from text: one card per extracted key term.
/// Definition-first: the FRONT shows the definition (read it,
/// recall the term) and the BACK reveals the term. At most
/// [maxCards].
List<Flashcard> flashcardsFromText(String text, {int maxCards = 8}) {
  final terms = extractKeyTerms(text);
  final cards = <Flashcard>[];
  for (final t in terms.take(maxCards)) {
    cards.add(Flashcard(
      id: newId(),
      front: t.definition,
      back: t.term,
      subject: '',
    ));
  }
  return cards;
}

/// Build up to [questionCount] questions from study text.
///
/// Improved generation rules (approved Nov 9):
/// * Questions come ONLY from real term-and-definition pairs:
///   a term that has a definition in the notes. A bare year /
///   date / number or a standalone fragment is never a question
///   (enforced in [extractKeyTerms]).
/// * Multiple-choice definition questions: "What is <term>?" with
///   the term's definition as the answer and three OTHER
///   definitions from the SAME text as distractors — never random
///   unrelated fragments. Distractors are distinct from the
///   correct answer and from each other. Only built when at
///   least 4 terms exist, so distractors are real.
/// * Every question's [explanation] quotes the exact source
///   sentence from the notes (see [AiKeyTerm.sourceSentence]).
/// * Fill-in-the-blank: a source sentence with its key term
///   replaced by ____, the term as the answer.
/// * When fewer than 4 terms exist, fill-in-the-blank questions
///   carry the set instead, so the AI never pads with invented
///   options.
///
/// Returns an empty list when the text yields no usable term.
List<AiQuizQuestion> questionsFromText(
  String text, {
  int questionCount = kAiMaxQuestionsPerSet,
  math.Random? random,
}) {
  final rng = random ?? math.Random();
  final terms = extractKeyTerms(text);
  if (terms.isEmpty) return const [];
  final count = questionCount.clamp(1, kAiMaxQuestionsPerSet);
  final out = <AiQuizQuestion>[];
  final usedTerms = <String>{};

  // Multiple-choice definition questions first (they need 4 terms).
  if (terms.length >= 4) {
    final shuffled = List.of(terms)..shuffle(rng);
    for (final term in shuffled) {
      if (out.length >= count) break;
      if (usedTerms.contains(term.term.toLowerCase())) continue;
      // Distractors are other REAL definitions from the same text,
      // distinct from the correct answer and from each other — so
      // a duplicated definition can never appear twice as options.
      final others = terms
          .where((t) => t.term.toLowerCase() != term.term.toLowerCase())
          .map((t) => t.definition)
          .where((d) => d != term.definition)
          .toSet()
          .toList()
        ..shuffle(rng);
      final distractors = others.take(3).toList();
      if (distractors.length < 3) continue;
      final options = [...distractors, term.definition]..shuffle(rng);
      final correct = options.indexOf(term.definition);
      usedTerms.add(term.term.toLowerCase());
      out.add(AiQuizQuestion(
        question: 'What is ${term.term}?',
        options: options,
        correctIndex: correct,
        explanation: term.sourceSentence,
        learningTip: 'From your notes: ${term.sourceSentence}',
      ));
    }
  }

  // Fill-in-the-blank from the remaining terms' source sentences.
  if (out.length < count) {
    final shuffled = List.of(terms)..shuffle(rng);
    for (final term in shuffled) {
      if (out.length >= count) break;
      if (usedTerms.contains(term.term.toLowerCase())) continue;
      final sentence = term.sourceSentence;
      // Replace the term (case-insensitive, first occurrence) with
      // a blank. Skip when the term does not appear in its own
      // source sentence (should not happen, but never fake it).
      final idx = sentence.toLowerCase().indexOf(term.term.toLowerCase());
      if (idx < 0) continue;
      final blanked = sentence.replaceRange(
        idx,
        idx + term.term.length,
        '____',
      );
      usedTerms.add(term.term.toLowerCase());
      out.add(AiQuizQuestion(
        question: blanked,
        options: const [],
        correctIndex: 0,
        type: 'fill',
        answer: term.term,
        explanation: sentence,
        learningTip: 'From your notes: $sentence',
      ));
    }
  }
  return out;
}

/// The sample deck the preview shows, clearly marked as a sample.
/// Built-in only — never written to the user's storage. The pages
/// show it only while the user has no saved cards/quizzes of
/// their own, labelled "Sample".
class SampleDeck {
  const SampleDeck({
    required this.title,
    required this.subject,
    required this.terms,
  });

  final String title;
  final String subject;

  /// (term, definition) pairs. The same pairs back both the
  /// flashcards and the quiz, so the two pages share one deck.
  final List<(String, String)> terms;

  /// Definition-first, like [flashcardsFromText]: the front shows
  /// the definition and the back reveals the term.
  List<Flashcard> get flashcards => terms
      .map((t) => Flashcard(
            id: 'sample-${t.$1.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
            front: t.$2,
            back: t.$1,
            subject: subject,
          ))
      .toList();

  List<QuizQuestion> get questions {
    final defs = terms.map((t) => t.$2).toList();
    final out = <QuizQuestion>[];
    for (var i = 0; i < terms.length; i++) {
      final term = terms[i].$1;
      final definition = terms[i].$2;
      final distractors = <String>[];
      for (var j = 1; j <= 3; j++) {
        distractors.add(defs[(i + j) % defs.length]);
      }
      final options = [...distractors, definition];
      // Deterministic rotation so the correct answer is not always
      // last: rotate by the question index.
      final rotated = [
        for (var k = 0; k < options.length; k++)
          options[(k + i) % options.length],
      ];
      final correct = rotated.indexOf(definition);
      out.add(QuizQuestion(
        type: 'mcq',
        question: 'What is $term?',
        options: rotated,
        correctIndex: correct,
        answer: definition,
        explanation:
            '$term: $definition',
        learningTip: 'From the sample deck: $term — $definition',
      ));
    }
    return out;
  }

  Quiz get quiz => Quiz(
        id: 'sample-computer-basics',
        title: title,
        subject: subject,
        timeLimitSec: 0,
        questions: questions,
      );
}

const sampleComputerBasicsDeck = SampleDeck(
  title: 'Computer Basics',
  subject: 'Computer Basics',
  terms: [
    (
      'CPU',
      'Central Processing Unit — it processes instructions',
    ),
    (
      'RAM',
      'Random Access Memory — temporary memory that clears on shutdown',
    ),
    (
      'ROM',
      'Read-Only Memory — permanent memory that stores startup instructions',
    ),
    (
      'Hard Drive',
      'Storage that keeps your files permanently',
    ),
    (
      'Operating System',
      'Software that manages the computer hardware and programs',
    ),
  ],
);

/// The on-device AI. Implements the app's [AiQuizGenerator]
/// contract with rule-based generation only — no model call, no
/// network. Safe to construct and use in unit tests.
class OnDeviceAiQuizGenerator implements AiQuizGenerator {
  OnDeviceAiQuizGenerator({NoteExtractService? extractor})
      : _extractor = extractor ?? NoteExtractService();

  final NoteExtractService _extractor;

  @override
  Future<AiQuizGeneration> generateFromText(
    String contextText, {
    int questionCount = kAiMaxQuestionsPerSet,
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
    final questions = questionsFromText(
      context,
      questionCount: questionCount.clamp(1, kAiMaxQuestionsPerSet),
    );
    if (questions.isEmpty) {
      return const AiQuizGeneration(
        questions: [],
        error: 'I could not find clear terms in that text. '
            'Try notes with definitions, like "CPU is the Central '
            'Processing Unit".',
      );
    }
    return AiQuizGeneration(questions: questions);
  }

  @override
  Future<AiQuizGeneration> generateFromMedia(
    List<AiQuizAttachment> attachments, {
    int questionCount = kAiMaxQuestionsPerSet,
    String difficulty = 'medium',
    List<String> questionTypes = const ['mcq'],
  }) async {
    if (attachments.isEmpty) {
      return const AiQuizGeneration(
        questions: [],
        error: 'Attach a photo or document first.',
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
    // On-device read: write each attachment to a temp file with
    // its real extension, extract text with the same service the
    // Notes flow uses (ML Kit OCR for photos, pdfrx text layer
    // for PDFs, direct read for text), then generate from text.
    final buffer = StringBuffer();
    for (final attachment in attachments) {
      final ext = _extensionForMime(attachment.mimeType);
      if (ext == null) {
        return const AiQuizGeneration(
          questions: [],
          error: 'Only images, PDFs, and text files are supported.',
        );
      }
      final tmp = await _writeTemp(attachment.bytes, ext);
      try {
        final result = await _extractor.extract(tmp);
        if (result.outcome == NoteExtractOutcome.ok) {
          buffer.writeln(result.text);
        }
      } finally {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      return const AiQuizGeneration(
        questions: [],
        error: 'I could not read any text from that file. '
            'Try a clearer photo or a PDF with a text layer.',
      );
    }
    return generateFromText(
      text,
      questionCount: questionCount,
      difficulty: difficulty,
      questionTypes: questionTypes,
    );
  }

  String? _extensionForMime(String mime) {
    switch (mime.toLowerCase()) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/heic':
        return 'heic';
      case 'image/heif':
        return 'heif';
      case 'application/pdf':
        return 'pdf';
      case 'text/plain':
        return 'txt';
      case 'text/markdown':
        return 'md';
      case 'text/csv':
        return 'csv';
      default:
        return null;
    }
  }

  Future<File> _writeTemp(List<int> bytes, String ext) async {
    final dir = Directory.systemTemp;
    final file = File(
        '${dir.path}/estudyantego-ai-${DateTime.now().microsecondsSinceEpoch}.$ext');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  @override
  Future<String> explainMore({
    required String question,
    required String correctAnswer,
    String explanation = '',
  }) async {
    // Grounded by construction: the stored explanation is the
    // only source. There is no model to ask, so an empty stored
    // explanation honestly says the material does not explain
    // further — never an invented reason.
    if (explanation.trim().isNotEmpty) return explanation.trim();
    if (question.trim().isEmpty || correctAnswer.trim().isEmpty) {
      return 'No explanation available.';
    }
    return 'The provided material does not explain this further.';
  }
}

/// One chat reply, plus whether it carries a follow-up action the
/// UI can offer (e.g. opening the quiz). Pure and synchronous so
/// tests can assert on it without a widget tree.
class AiChatReply {
  const AiChatReply(this.text, {this.action});

  final String text;

  /// 'quiz' | 'flashcards' | 'summary' | null.
  final String? action;
}

/// Rule-based chat for EstudyanteGO AI. Answers only from what it
/// is given — the user's own notes, quizzes, flashcards, subjects,
/// and the one verified fare. It never invents a fare, a schedule,
/// or a fact, and it states that it is built into the app, not an
/// online AI.
AiChatReply answerChat(
  String message, {
  List<Note> notes = const [],
  List<Quiz> quizzes = const [],
  List<Flashcard> cards = const [],
  List<String> subjects = const [],
  int points = 0,
}) {
  final lower = message.toLowerCase().trim();

  bool hasAny(List<String> words) =>
      words.any((w) => lower.contains(w));

  // Identity: the assistant is on-device, not an online AI.
  if (hasAny(['online ai', 'are you an ai', 'are you ai', 'gemini',
      'chatgpt', 'internet', 'are you real'])) {
    return const AiChatReply(
      'I am EstudyanteGO AI, built into this app — I run right here '
      'on your phone, so I work even without internet. I am not an '
      'online AI and I do not use Gemini or any outside service. '
      'Everything I read stays on your phone.',
    );
  }

  // Fares — only the one verified fare is ever stated.
  if (hasAny(['fare', 'pamasahe', 'magkano', 'how much']) &&
      lower.contains('cabugao') &&
      lower.contains('vigan')) {
    return const AiChatReply(kAiCabugaoViganFareLine);
  }
  if (hasAny(['fare', 'pamasahe', 'magkano', 'how much'])) {
    return const AiChatReply(
      'I only know the verified fare: $kAiCabugaoViganFareLine '
      'For other routes, check the Fares tab — I will not guess a fare.',
    );
  }

  // Greeting.
  if (hasAny(['hello', 'hi', 'hey', 'kumusta', 'good morning',
      'good afternoon', 'good evening'])) {
    return AiChatReply(
      'Hello! I am EstudyanteGO AI — I run on your phone, no '
      'internet needed. Ask me about your quizzes, flashcards, '
      'schedule, or fares, or tap + to turn a file into questions.',
    );
  }

  // Quiz help.
  if (hasAny(['quiz', 'quizzes', 'question'])) {
    if (quizzes.isEmpty) {
      return const AiChatReply(
        'You have no saved quizzes yet. Tap + and pick a file, or '
        'use "Add Question manually" on the Quiz page, and I will '
        'build one from your notes.',
        action: 'quiz',
      );
    }
    final total = quizzes.fold<int>(
        0, (sum, q) => sum + q.questions.length);
    return AiChatReply(
      'You have ${quizzes.length} quiz(zes) with $total question(s). '
      'Open the Quiz page to take one — each correct answer earns '
      '10 pts.',
      action: 'quiz',
    );
  }

  // Flashcards.
  if (hasAny(['flashcard', 'flashcards', 'cards'])) {
    if (cards.isEmpty) {
      return const AiChatReply(
        'You have no flashcards yet. Add one from the Flashcards '
        'page, or let me make some from your notes with the + button.',
        action: 'flashcards',
      );
    }
    return AiChatReply(
      'You have ${cards.length} flashcard(s). Open the Flashcards '
      'page and tap "Study all cards" to flip through them.',
      action: 'flashcards',
    );
  }

  // Summary.
  if (hasAny(['summar', 'summary', 'buod'])) {
    if (notes.isEmpty) {
      return const AiChatReply(
        'You have no notes to summarize yet. Write a note first, '
        'or pick a file with + and I will summarize it.',
        action: 'summary',
      );
    }
    final points = keyPoints(
      notes.map((n) => '${n.title}. ${n.body}').join('\n'),
    );
    if (points.isEmpty) {
      return const AiChatReply(
        'Your notes are too short for a summary. Add more detail '
        'and I will pull out the key points.',
        action: 'summary',
      );
    }
    return AiChatReply(
      'Here is your deck in short:\n${points.map((p) => '• $p').join('\n')}',
      action: 'summary',
    );
  }

  // Schedule / classes.
  if (hasAny(['schedule', 'class', 'classes', 'timetable', 'subject'])) {
    if (subjects.isEmpty) {
      return const AiChatReply(
        'You have no subjects saved yet. Add them from the Student '
        'tab → Classes & Timetable, then ask me again.',
      );
    }
    return AiChatReply(
      'Your subjects: ${subjects.join(', ')}. Open the Student tab '
      '→ Classes & Timetable for the full schedule.',
    );
  }

  // Points.
  if (hasAny(['point', 'points', 'pts', 'score'])) {
    return AiChatReply(
      'You have $points pts. Each correct quiz answer earns 10 pts.',
    );
  }

  // Fallback — honest about what it can do, never a fake answer.
  return const AiChatReply(
    'I can help with your quizzes, flashcards, summaries, schedule, '
    'and fares — all from your own notes, on this phone. Try asking '
    'about a quiz, or tap + to turn a file into questions.',
  );
}
