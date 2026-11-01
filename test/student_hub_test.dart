// Unit tests for the Student Hub's pure helpers (no storage, no UI).
import 'package:byahetayo/features/student/student_data.dart';
import 'package:flutter_test/flutter_test.dart';

Subject _subject({
  String id = 's1',
  String name = 'Math',
  List<int> days = const [1],
  int startMin = 480,
  int endMin = 540,
}) =>
    Subject(
      id: id,
      name: name,
      code: '',
      teacher: '',
      room: '',
      days: days,
      startMin: startMin,
      endMin: endMin,
      color: 0xFF16A34A,
    );

void main() {
  test('allowanceBalance subtracts expenses from income', () {
    final txns = [
      AllowanceTxn(
          id: '1',
          kind: 'income',
          amount: 500,
          category: 'Allowance',
          note: '',
          date: DateTime(2026, 11, 1)),
      AllowanceTxn(
          id: '2',
          kind: 'expense',
          amount: 120,
          category: 'Food',
          note: '',
          date: DateTime(2026, 11, 1)),
    ];
    expect(allowanceBalance(txns), 380);
    expect(allowanceBalance([]), 0);
  });

  test('monthTotals only counts the requested month', () {
    final txns = [
      AllowanceTxn(
          id: '1',
          kind: 'income',
          amount: 500,
          category: 'Allowance',
          note: '',
          date: DateTime(2026, 10, 31)),
      AllowanceTxn(
          id: '2',
          kind: 'expense',
          amount: 50,
          category: 'Food',
          note: '',
          date: DateTime(2026, 11, 1)),
    ];
    final totals = monthTotals(txns, 2026, 11);
    expect(totals.income, 0);
    expect(totals.expense, 50);
  });

  test('findConflict flags same-day overlaps only', () {
    final existing = [_subject()];
    // Overlapping: 9:00–10:00 vs 8:00–9:00? No — adjacent is fine.
    expect(
        findConflict(existing,
            _subject(id: 's2', name: 'Eng', startMin: 540, endMin: 600)),
        isNull);
    // Overlapping: 8:30–9:30 vs 8:00–9:00.
    expect(
        findConflict(existing,
            _subject(id: 's2', name: 'Eng', startMin: 510, endMin: 570)),
        'Math');
    // Same time, different day: no conflict.
    expect(
        findConflict(existing,
            _subject(id: 's2', name: 'Eng', days: const [2])),
        isNull);
    // Editing the same subject does not conflict with itself.
    expect(
        findConflict(existing, _subject(), excludeId: 's1'), isNull);
  });

  test('nextClass picks later today, then the next day with classes', () {
    final subjects = [
      _subject(days: const [1], startMin: 480, endMin: 540),
      _subject(id: 's2', name: 'Eng', days: const [3], startMin: 600, endMin: 660),
    ];
    // Monday 7:00 — Math at 8:00 is next.
    final monday = nextClass(subjects, DateTime(2026, 11, 2, 7, 0));
    expect(monday?.subject.name, 'Math');
    // Monday 10:00 — Math passed, so Wednesday Eng is next.
    final later = nextClass(subjects, DateTime(2026, 11, 2, 10, 0));
    expect(later?.subject.name, 'Eng');
    expect(nextClass([], DateTime(2026, 11, 2)), isNull);
  });

  test('attendanceStats weights half-days and excludes excused', () {
    AttendanceRecord rec(String status) => AttendanceRecord(
        id: status,
        subject: 'Math',
        date: DateTime(2026, 11, 1),
        status: status,
        note: '',
        reason: '');
    final stats = attendanceStats([
      rec('present'),
      rec('present'),
      rec('late'),
      rec('half'),
      rec('absent'),
      rec('excused'),
    ]);
    expect(stats.total, 6);
    expect(stats.excused, 1);
    // (2 + 1 + 0.5) / (6 - 1) = 70%.
    expect(stats.percent, closeTo(70, 0.001));
    expect(attendanceStats([]).percent, 0);
    expect(attendanceStats([rec('excused')]).percent, 0);
  });

  test('scoreQuiz handles mcq, true/false, and identification', () {
    final quiz = Quiz(
      id: 'q',
      title: 'Sample',
      subject: '',
      timeLimitSec: 0,
      questions: [
        QuizQuestion(
            type: 'mcq',
            question: 'Q1',
            options: ['a', 'b', 'c', 'd'],
            correctIndex: 1,
            answer: '',
            explanation: ''),
        QuizQuestion(
            type: 'tf',
            question: 'Q2',
            options: ['True', 'False'],
            correctIndex: 0,
            answer: '',
            explanation: ''),
        QuizQuestion(
            type: 'id',
            question: 'Q3',
            options: [],
            correctIndex: 0,
            answer: 'Vigan',
            explanation: ''),
      ],
    );
    // typed is indexed by question position, like the runner's
    // List.filled(questions.length, '') list.
    expect(scoreQuiz(quiz, [1, 0], ['', '', 'vigan']), 3);
    expect(scoreQuiz(quiz, [2, 1], ['', '', '']), 0);
    expect(scoreQuiz(quiz, [1, 0], ['', '', '  VIGAN  ']), 3);
  });

  test('quote and verse of the day are deterministic per date', () {
    final date = DateTime(2026, 11, 1);
    expect(quoteOfDay(date).id, quoteOfDay(date).id);
    expect(verseOfDay(date).id, verseOfDay(date).id);
    expect(quoteOfDay(DateTime(2026, 1, 1)).id, bundledQuotes.first.id);
    expect(verseOfDay(DateTime(2026, 1, 1)).id, bundledVerses.first.id);
  });

  test('peso and time formatting', () {
    expect(peso(0), '₱0');
    expect(peso(90), '₱90');
    expect(peso(1234.5), '₱1,234.50');
    expect(formatMinutes(0), '12:00 AM');
    expect(formatMinutes(480), '8:00 AM');
    expect(formatMinutes(780), '1:00 PM');
  });

  test('csvEscape quotes fields with commas', () {
    expect(csvEscape('plain'), 'plain');
    expect(csvEscape('a,b'), '"a,b"');
    expect(toCsv([
      ['a', 'b'],
      ['x,y', 'z']
    ]), 'a,b\n"x,y",z');
  });

  CheckinRecord checkin(DateTime date, int day, int points) =>
      CheckinRecord(id: dateKey(date), date: date, dayIndex: day, points: points);

  test('dateKey pads month and day', () {
    expect(dateKey(DateTime(2026, 11, 1)), '2026-11-01');
    expect(dateKey(DateTime(2026, 1, 9)), '2026-01-09');
  });

  test('check-in streak counts consecutive days only', () {
    final today = DateTime(2026, 11, 1);
    final three = [
      checkin(today, 3, 10),
      checkin(today.subtract(const Duration(days: 1)), 2, 10),
      checkin(today.subtract(const Duration(days: 2)), 1, 10),
    ];
    expect(checkinStreak(three, today), 3);
    expect(checkinStreak([checkin(today, 1, 10)], today), 1);
    // Not checked today: streak runs through yesterday.
    expect(
        checkinStreak([
          checkin(today.subtract(const Duration(days: 1)), 2, 10),
          checkin(today.subtract(const Duration(days: 2)), 1, 10),
        ], today),
        2);
    // Gap breaks the streak; an old record alone counts for nothing.
    expect(
        checkinStreak(
            [checkin(today, 1, 10), checkin(today.subtract(const Duration(days: 3)), 1, 10)],
            today),
        1);
    expect(
        checkinStreak(
            [checkin(today.subtract(const Duration(days: 3)), 1, 10)],
            today),
        0);
  });

  test('hasCheckedInToday blocks duplicate check-ins', () {
    final today = DateTime(2026, 11, 1);
    expect(hasCheckedInToday([checkin(today, 1, 10)], today), isTrue);
    expect(
        hasCheckedInToday(
            [checkin(today.subtract(const Duration(days: 1)), 1, 10)],
            today),
        isFalse);
    expect(hasCheckedInToday([], today), isFalse);
  });

  test('cycle day, checked count, and rewards', () {
    expect(nextCycleDay(0), 1);
    expect(nextCycleDay(6), 7);
    expect(nextCycleDay(7), 1);
    expect(nextCycleDay(10), 4);
    expect(cycleCheckedCount(0), 0);
    expect(cycleCheckedCount(3), 3);
    expect(cycleCheckedCount(7), 7);
    expect(cycleCheckedCount(10), 3);
    expect(pointsForDay(1), 10);
    expect(pointsForDay(6), 10);
    expect(pointsForDay(7), 50);
    expect(totalCheckinPoints([checkin(DateTime(2026, 11, 1), 1, 10)]), 10);
    expect(
        totalCheckinPoints([
          checkin(DateTime(2026, 11, 1), 1, 10),
          checkin(DateTime(2026, 10, 31), 7, 50),
        ]),
        60);
  });

  test('current cycle resets after a completed cycle', () {
    final today = DateTime(2026, 11, 1);
    // Seven straight days ending today: cycle just completed, all 7 lit.
    final completed = List.generate(
        7,
        (i) => checkin(today.subtract(Duration(days: i)), 7 - i, 10));
    expect(currentCycleChecked(completed, today), 7);
    // Seven straight days ending yesterday: today starts a fresh cycle.
    final endedYesterday = List.generate(
        7,
        (i) => checkin(
            today.subtract(Duration(days: i + 1)), 7 - i, 10));
    expect(currentCycleChecked(endedYesterday, today), 0);
  });

  test('check-in record survives a JSON round-trip', () {
    final original = checkin(DateTime(2026, 11, 1), 7, 50);
    final restored = CheckinRecord.fromJson(original.toJson());
    expect(dateKey(restored.date), '2026-11-01');
    expect(restored.dayIndex, 7);
    expect(restored.points, 50);
  });
}
