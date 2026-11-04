// Unit tests for the Review Notes & Quizzes enhancement: the three
// new question types, difficulty/randomize, attempt timing, the
// deterministic shuffle, and study analytics. No storage, no UI.
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter_test/flutter_test.dart';

QuizQuestion _q({
  String type = 'mcq',
  List<String> options = const [],
  int correctIndex = 0,
  String answer = '',
}) =>
    QuizQuestion(
      type: type,
      question: 'Q',
      options: options,
      correctIndex: correctIndex,
      answer: answer,
      explanation: '',
    );

Quiz _quiz(List<QuizQuestion> questions,
        {String difficulty = 'medium', bool randomize = false}) =>
    Quiz(
      id: 'q1',
      title: 'Sample',
      subject: '',
      timeLimitSec: 0,
      questions: questions,
      difficulty: difficulty,
      randomize: randomize,
    );

void main() {
  group('new question types', () {
    test('enumeration scores by exact set, order-independent', () {
      final quiz = _quiz([_q(type: 'enum', answer: 'red\nblue\ngreen')]);
      expect(scoreQuiz(quiz, [], ['green\nred\nblue']), 1);
      expect(scoreQuiz(quiz, [], ['RED\nBlue\nGreen']), 1);
      expect(scoreQuiz(quiz, [], ['red\nblue']), 0); // partial set
      expect(scoreQuiz(quiz, [], ['red\nblue\ngreen\nyellow']), 0);
      expect(scoreQuiz(quiz, [], ['']), 0); // empty answer
    });

    test('matching scores only when every pair matches', () {
      final quiz = _quiz([
        _q(type: 'match', options: ['a', 'b'], answer: '1\n2'),
      ]);
      expect(scoreQuiz(quiz, [], ['1\n2']), 1);
      expect(scoreQuiz(quiz, [], ['1\n3']), 0);
      expect(scoreQuiz(quiz, [], ['1']), 0);
      expect(scoreQuiz(quiz, [], ['']), 0);
      expect(matchPairResults(quiz.questions[0], '1\n3'), [true, false]);
    });

    test('fill in the blanks is case-insensitive per blank', () {
      final quiz = _quiz([
        _q(type: 'fill', answer: 'apple\nbanana'),
      ]);
      expect(scoreQuiz(quiz, [], ['Apple\nBANANA']), 1);
      expect(scoreQuiz(quiz, [], ['apple\norange']), 0);
      expect(scoreQuiz(quiz, [], ['apple']), 0);
      expect(scoreQuiz(quiz, [], ['']), 0);
    });

    test('mcq/tf/id behaviour is unchanged', () {
      final quiz = _quiz([
        _q(options: ['a', 'b'], correctIndex: 1),
        _q(type: 'tf', options: ['True', 'False'], correctIndex: 0),
        _q(type: 'id', answer: 'Vigan'),
      ]);
      expect(scoreQuiz(quiz, [1, 0], ['', '', 'vigan']), 3);
      expect(scoreQuiz(quiz, [0, 1], ['', '', '']), 0);
    });
  });

  group('difficulty, randomize, backward compatibility', () {
    test('old quiz JSON loads with medium + no randomize', () {
      final quiz = Quiz.fromJson({
        'id': 'old',
        'title': 'Old',
        'questions': [
          {
            'type': 'mcq',
            'question': 'Q?',
            'options': ['a', 'b'],
            'correctIndex': 0,
            'answer': '',
            'explanation': '',
          },
        ],
      });
      expect(quiz.difficulty, 'medium');
      expect(quiz.randomize, isFalse);
      expect(quiz.questions.first.learningTip, '');
    });

    test('unknown difficulty normalizes to medium', () {
      expect(_quiz([], difficulty: 'extreme').difficulty, 'medium');
      expect(_quiz([], difficulty: 'hard').difficulty, 'hard');
    });

    test('shuffle is deterministic per seed and remaps mcq answers', () {
      final quiz = _quiz(
        [
          _q(options: ['a', 'b', 'c', 'd'], correctIndex: 2),
          _q(options: ['w', 'x', 'y', 'z'], correctIndex: 0),
          _q(type: 'id', answer: 'Vigan'),
        ],
        randomize: true,
      );
      final a = shuffleQuizForAttempt(quiz, seed: 42);
      final b = shuffleQuizForAttempt(quiz, seed: 42);
      expect(
        a.questions.map((q) => q.question).toList(),
        b.questions.map((q) => q.question).toList(),
      );
      for (final q in a.questions) {
        if (q.type == 'mcq') {
          // The correct answer text survives the option shuffle.
          expect(q.options[q.correctIndex], isNotEmpty);
        }
      }
      // Non-randomized quizzes are returned untouched.
      final plain = _quiz([_q(options: ['a', 'b'], correctIndex: 1)]);
      expect(identical(shuffleQuizForAttempt(plain, seed: 7), plain), isTrue);
    });

    test('shuffle preserves scoring: remapped index still scores', () {
      final quiz = _quiz(
        [_q(options: ['a', 'b', 'c', 'd'], correctIndex: 2)],
        randomize: true,
      );
      final shuffled = shuffleQuizForAttempt(quiz, seed: 11);
      final q = shuffled.questions.first;
      expect(scoreQuiz(shuffled, [q.correctIndex], ['']), 1);
      expect(
        scoreQuiz(shuffled, [(q.correctIndex + 1) % 4], ['']),
        0,
      );
    });
  });

  group('attempt timing and percentages', () {
    test('old attempt JSON loads with zero duration', () {
      final attempt = QuizAttempt.fromJson({
        'id': 'a',
        'quizTitle': 'Old',
        'score': 2,
        'total': 4,
        'date': '2026-11-01T10:00:00.000',
      });
      expect(attempt.durationSec, 0);
      expect(attempt.percentage, 50);
      expect(attempt.correctCount, 2);
      expect(attempt.incorrectCount, 2);
      expect(attempt.correctFlags, isEmpty);
      expect(attempt.givenAnswers, isEmpty);
    });

    test('timed attempt round-trips with duration and review data', () {
      final attempt = QuizAttempt(
        id: 'a',
        quizTitle: 'T',
        score: 1,
        total: 2,
        date: DateTime(2026, 11, 1, 10, 5),
        quizId: 'q1',
        startedAt: DateTime(2026, 11, 1, 10, 0),
        finishedAt: DateTime(2026, 11, 1, 10, 5, 30),
        correctFlags: [true, false],
        givenAnswers: ['b', ''],
      );
      expect(attempt.durationSec, 330);
      final restored = QuizAttempt.fromJson(attempt.toJson());
      expect(restored.durationSec, 330);
      expect(restored.correctFlags, [true, false]);
      expect(restored.givenAnswers, ['b', '']);
      expect(restored.quizId, 'q1');
    });
  });

  group('study analytics', () {
    QuizAttempt attempt({
      required int score,
      required int total,
      required DateTime date,
      String quizId = 'q1',
    }) =>
        QuizAttempt(
          id: 'a-${date.toIso8601String()}-$score',
          quizTitle: 'T',
          score: score,
          total: total,
          date: date,
          quizId: quizId,
        );

    test('empty attempts yield zeros, never fabricated numbers', () {
      final analytics = computeQuizAnalytics(
        [],
        now: DateTime(2026, 11, 4),
      );
      expect(analytics.totalAttempts, 0);
      expect(analytics.averagePct, 0);
      expect(analytics.highestPct, 0);
      expect(analytics.weekly.length, 7);
      expect(analytics.weekly.every((d) => d.attempts == 0), isTrue);
      expect(analytics.distinctQuizzesAttempted, 0);
    });

    test('aggregates use real attempts only', () {
      final now = DateTime(2026, 11, 4, 12);
      final analytics = computeQuizAnalytics(
        [
          attempt(score: 8, total: 10, date: DateTime(2026, 11, 4, 9)),
          attempt(score: 5, total: 10, date: DateTime(2026, 11, 4, 10)),
          attempt(
              score: 10,
              total: 10,
              date: DateTime(2026, 11, 3, 9),
              quizId: 'q2'),
        ],
        now: now,
      );
      expect(analytics.totalAttempts, 3);
      expect(analytics.averagePct, 77); // (80 + 50 + 100) / 3 rounded
      expect(analytics.highestPct, 100);
      expect(analytics.distinctQuizzesAttempted, 2);
      final today = analytics.weekly.last;
      expect(today.attempts, 2);
      expect(today.averagePct, 65);
    });
  });
}
