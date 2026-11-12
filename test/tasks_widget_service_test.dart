import 'package:estudyantego/features/student/student_data.dart';
import 'package:estudyantego/features/student/tasks_widget_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Tasks / To-do home screen widgets (Nov 11, 2026): 4x2, 3x3, and
// 4x3, approved preview v1. The tasks below are TEST FIXTURES
// only — the widget itself reads the student's stored assignments
// and never hardcodes one. In particular the preview's SAMPLE
// tasks ("2 of 5 done") are NOT here: with no assignments the
// widget shows the honest empty state ("0 pending", "No pending
// tasks."), and with fixtures it shows the real pending list in
// due-date order.
void main() {
  List<Subject> fixtureSubjects() => [
        Subject(
          id: 's-ct101',
          name: 'Introduction to Computing',
          code: 'CT101',
          teacher: 'A. Supnet',
          room: 'CC105',
          days: const [1],
          startMin: 7 * 60 + 30,
          endMin: 9 * 60 + 30,
          color: 0xFF58CC02,
        ),
        Subject(
          id: 's-ct102',
          name: 'Computer Programming 1',
          code: 'CT102',
          teacher: 'W.E. Que',
          room: 'CC105',
          days: const [1],
          startMin: 10 * 60,
          endMin: 12 * 60,
          color: 0xFF1CB0F6,
        ),
      ];

  List<AssignmentItem> fixtureItems() => [
        AssignmentItem(
          id: 'a1',
          subjectId: 's-ct101',
          title: 'Chapter 3 exercises',
          kind: 'assignment',
          due: DateTime(2026, 11, 13, 23, 59),
          done: false,
        ),
        AssignmentItem(
          id: 'a2',
          subjectId: 's-ct102',
          title: 'Midterm exam',
          kind: 'exam',
          due: DateTime(2026, 11, 12, 10, 0),
          done: false,
        ),
        AssignmentItem(
          id: 'a3',
          subjectId: 's-ct101',
          title: 'Quiz 2',
          kind: 'assignment',
          due: DateTime(2026, 11, 10, 9, 0),
          done: true,
        ),
      ];

  TasksWidgetData decodeFixture() {
    final raw = TasksWidgetService.encodeData(
        fixtureItems(), fixtureSubjects());
    final data = TasksWidgetService.decodeData(raw);
    expect(data, isNotNull);
    return data!;
  }

  test('pending tasks come first, in due-date order', () {
    final data = decodeFixture();
    expect(data.pendingCount, 2);
    // The exam (due Nov 12) comes before the exercises (due Nov 13),
    // even though it was second in the stored list.
    expect(data.pending[0].title, 'Midterm exam');
    expect(data.pending[1].title, 'Chapter 3 exercises');
    // Done tasks sort after all pending ones.
    expect(data.tasks.last.title, 'Quiz 2');
    expect(data.tasks.last.done, isTrue);
  });

  test('done line counts real done tasks', () {
    expect(decodeFixture().doneLine, '1 of 3 done');
  });

  test('subject names resolve from the stored subjects', () {
    final data = decodeFixture();
    expect(data.pending[0].subjectName, 'Computer Programming 1');
    expect(data.pending[0].kindLabel, 'Exam');
    expect(data.pending[0].dueLabel, 'Nov 12, 2026');
    expect(data.pending[1].kindLabel, 'Assignment');
  });

  test('an unknown subject leaves the name blank, never invented', () {
    final raw = TasksWidgetService.encodeData(
      [
        AssignmentItem(
          id: 'a9',
          subjectId: 's-missing',
          title: 'Orphan task',
          kind: 'assignment',
          due: DateTime(2026, 11, 14),
          done: false,
        ),
      ],
      fixtureSubjects(),
    );
    final data = TasksWidgetService.decodeData(raw);
    expect(data!.pending.first.subjectName, '');
    expect(data.pending.first.title, 'Orphan task');
  });

  test('empty store: zero pending and the honest empty state', () {
    final raw = TasksWidgetService.encodeData([], fixtureSubjects());
    final data = TasksWidgetService.decodeData(raw);
    expect(data, isNotNull);
    expect(data!.pendingCount, 0);
    expect(data.tasks, isEmpty);
    expect(data.doneLine, '0 of 0 done');
  });

  test('payload caps at maxTasks, pending first', () {
    final many = [
      for (var i = 0; i < 10; i++)
        AssignmentItem(
          id: 'p$i',
          subjectId: 's-ct101',
          title: 'Pending $i',
          kind: 'assignment',
          due: DateTime(2026, 11, 13 + i),
          done: false,
        ),
      for (var i = 0; i < 3; i++)
        AssignmentItem(
          id: 'd$i',
          subjectId: 's-ct101',
          title: 'Done $i',
          kind: 'assignment',
          due: DateTime(2026, 11, 9),
          done: true,
        ),
    ];
    final raw = TasksWidgetService.encodeData(many, fixtureSubjects());
    final data = TasksWidgetService.decodeData(raw);
    expect(data!.tasks.length, TasksWidgetService.maxTasks);
    expect(data.pending.length, TasksWidgetService.maxTasks);
  });

  test('decodeData returns null for missing or malformed JSON', () {
    expect(TasksWidgetService.decodeData(null), isNull);
    expect(TasksWidgetService.decodeData(''), isNull);
    expect(TasksWidgetService.decodeData('not json'), isNull);
    expect(TasksWidgetService.decodeData('{"tasks": "x"}'), isNull);
    expect(TasksWidgetService.decodeData('[]'), isNull);
  });

  test('encode/decode round-trips the payload', () {
    final data = decodeFixture();
    final again = TasksWidgetService.decodeData(
        TasksWidgetService.encodeData(fixtureItems(), fixtureSubjects()));
    expect(again, data);
  });
}
