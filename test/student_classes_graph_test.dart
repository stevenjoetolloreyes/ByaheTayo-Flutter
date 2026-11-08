// Unit tests for the Classes & Timetable week-load graph helpers
// (Nov 8, 2026 redesign): the graph shows REAL class hours per day
// from Subject data only — these tests pin the math, including
// Steven's real shape (a 5.5-hour Monday class).
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter_test/flutter_test.dart';

Subject _subject({
  String id = 's1',
  String name = 'Coding',
  List<int> days = const [1],
  int startMin = 30,
  int endMin = 360,
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
  test('classHoursByWeekday sums real hours per day, Mon-first', () {
    final subjects = [
      _subject(days: const [1], startMin: 30, endMin: 360), // Mon 5.5h
      _subject(
        id: 's2',
        name: 'Coding Self',
        days: const [7],
        startMin: 840,
        endMin: 960,
      ), // Sun 2h
    ];
    expect(classHoursByWeekday(subjects), [5.5, 0, 0, 0, 0, 0, 2.0]);
    expect(totalWeeklyClassHours(subjects), 7.5);
    expect(weeklyClassCount(subjects), 2);
  });

  test('classHoursByWeekday counts a multi-day subject on each day', () {
    final subjects = [
      _subject(days: const [1, 3, 5], startMin: 480, endMin: 540),
    ];
    expect(classHoursByWeekday(subjects), [1.0, 0, 1.0, 0, 1.0, 0, 0]);
    expect(weeklyClassCount(subjects), 3);
    expect(totalWeeklyClassHours(subjects), 3.0);
  });

  test('classHoursByWeekday is all zero with no subjects', () {
    expect(classHoursByWeekday([]), [0, 0, 0, 0, 0, 0, 0]);
    expect(weeklyClassCount([]), 0);
    expect(totalWeeklyClassHours([]), 0);
  });

  test('classHoursByWeekday ignores bad data, never invents hours', () {
    final subjects = [
      _subject(
        days: const [2],
        startMin: 600,
        endMin: 540,
      ), // ends before it starts
      _subject(
        id: 's2',
        name: 'Bad day',
        days: const [0, 8],
        startMin: 480,
        endMin: 540,
      ), // days outside 1..7
    ];
    expect(classHoursByWeekday(subjects), [0, 0, 0, 0, 0, 0, 0]);
    expect(weeklyClassCount(subjects), 0);
    expect(totalWeeklyClassHours(subjects), 0);
  });

  test('formatHours trims whole hours', () {
    expect(formatHours(2), '2h');
    expect(formatHours(5.5), '5.5h');
    expect(formatHours(0), '0h');
    expect(formatHours(7.5), '7.5h');
  });
}
