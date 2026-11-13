// Tests for the Grades semester fix (Nov 13, 2026): Subject
// gains a semester field (old stored subjects read as 1st
// Semester), and migrateStoredSubjects repairs the bad
// schedule-scan output from Steven's screenshots — room numbers
// as subject codes ("CC105"), fragments ("Coding", "Vigan")
// as subject names — into the verified 1st-term 2026–2027
// DCT-1 meetings from his Certificate of Registration, and
// drops entries that name no real class. Grades are preserved:
// a grade on a repaired subject keeps its subject id, a grade
// on a duplicate meeting is remapped to the kept entry, and a
// grade on dropped junk is removed. No 2nd-semester subject
// is ever invented here.
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter_test/flutter_test.dart';

Subject _bad({
  required String id,
  required String name,
  required String code,
  required List<int> days,
  required int startMin,
  required int endMin,
  String room = '',
  String teacher = '',
}) =>
    Subject(
      id: id,
      name: name,
      code: code,
      teacher: teacher,
      room: room,
      days: days,
      startMin: startMin,
      endMin: endMin,
      color: 0xFF16A34A,
    );

/// The six rows from Steven's Nov 13 screenshots, with the six
/// meeting patterns from his Certificate of Registration.
List<Subject> _screenshotRows() => [
      _bad(
        id: 'm1',
        name: 'Introduction Of Computing',
        code: 'CC105',
        days: [1],
        startMin: 7 * 60 + 30,
        endMin: 9 * 60 + 30,
        room: 'CC105',
      ),
      _bad(
        id: 'm2',
        name: 'Introduction Of Computing',
        code: 'CC101',
        days: [2, 4],
        startMin: 14 * 60,
        endMin: 15 * 60 + 30,
        room: 'CC104',
      ),
      _bad(
        id: 'm3',
        name: 'Coding',
        code: 'Coding',
        days: [1],
        startMin: 10 * 60,
        endMin: 12 * 60,
        room: 'CC105',
      ),
      _bad(
        id: 'm4',
        name: 'Coding',
        code: '',
        days: [2, 4],
        startMin: 10 * 60 + 30,
        endMin: 12 * 60,
        room: 'CC104',
      ),
      _bad(
        id: 'm5',
        name: 'Installing Configuration',
        code: 'CC105',
        days: [1],
        startMin: 13 * 60,
        endMin: 15 * 60,
        room: 'CC105',
      ),
      _bad(
        id: 'm6',
        name: 'Computer and Configuration',
        code: 'CC203',
        days: [2, 4],
        startMin: 9 * 60,
        endMin: 10 * 60 + 30,
        room: 'CC203',
      ),
    ];

void main() {
  test('Subject without a semester reads as 1st Semester', () {
    final fromOldJson = Subject.fromJson({
      'id': 's1',
      'name': 'Math 101',
      'code': 'MATH101',
      'teacher': '',
      'room': '',
      'days': [1, 3],
      'startMin': 480,
      'endMin': 540,
      'color': 4278190080,
    });
    expect(fromOldJson.semester, 1);

    final second = Subject.fromJson({
      'id': 's2',
      'name': 'Math 102',
      'code': 'MATH102',
      'teacher': '',
      'room': '',
      'days': [1, 3],
      'startMin': 480,
      'endMin': 540,
      'color': 4278190080,
      'semester': 2,
    });
    expect(second.semester, 2);
    expect(Subject.fromJson(second.toJson()).semester, 2);
    expect(Subject.fromJson(fromOldJson.toJson()).semester, 1);
  });

  test('migration repairs the six screenshot rows into the '
      'verified 1st-term meetings', () {
    final result = migrateStoredSubjects(_screenshotRows(), []);
    expect(result.changed, isTrue);
    expect(result.subjects.length, 6);
    // Ids are kept, so any recorded grade stays attached.
    expect(result.subjects.map((s) => s.id).toList(),
        ['m1', 'm2', 'm3', 'm4', 'm5', 'm6']);
    expect(result.subjects.map((s) => s.code).toList(),
        ['CT101', 'CT101', 'CT102', 'CT102', 'CSS101', 'CSS101']);
    expect(result.subjects.map((s) => s.name).toList(), [
      'Introduction to Computing',
      'Introduction to Computing',
      'Computer Programming 1',
      'Computer Programming 1',
      'Installing and Configuring Computer Systems',
      'Installing and Configuring Computer Systems',
    ]);
    expect(result.subjects.map((s) => s.teacher).toList(), [
      'A. Supnet',
      'A. Supnet',
      'W.E. Que',
      'W.E. Que',
      'L. Baja',
      'L. Baja',
    ]);
    expect(result.subjects.map((s) => s.room).toList(),
        ['CC105', 'CC104', 'CC105', 'CC104', 'CC105', 'CC203']);
    expect(result.subjects.every((s) => s.semester == 1), isTrue);
    // No bad code or fragment name survives.
    expect(
      result.subjects
          .where((s) =>
              s.code == 'CC105' ||
              s.code == 'CC101' ||
              s.code == 'CC203' ||
              s.name == 'Coding' ||
              s.name == 'Vigan')
          .toList(),
      isEmpty,
    );
  });

  test('migration drops a Vigan row that matches no meeting', () {
    final rows = [
      ..._screenshotRows(),
      _bad(
        id: 'junk',
        name: 'Vigan',
        code: 'v',
        days: [5],
        startMin: 8 * 60,
        endMin: 9 * 60,
      ),
    ];
    final result = migrateStoredSubjects(rows, []);
    expect(result.subjects.length, 6);
    expect(result.subjects.any((s) => s.id == 'junk'), isFalse);
    expect(result.changed, isTrue);
  });

  test('migration repairs by name when the time matches no meeting',
      () {
    final rows = [
      _bad(
        id: 'n1',
        name: 'Installing Configuration',
        code: 'CC105',
        days: [5],
        startMin: 8 * 60,
        endMin: 9 * 60,
      ),
    ];
    final result = migrateStoredSubjects(rows, []);
    expect(result.subjects.length, 1);
    expect(result.subjects.single.code, 'CSS101');
    expect(result.subjects.single.name,
        'Installing and Configuring Computer Systems');
    expect(result.subjects.single.teacher, 'L. Baja');
    // Its own days/times are kept — only the identity is fixed.
    expect(result.subjects.single.days, [5]);
  });

  test('migration leaves correct and user-added subjects alone', () {
    final correct = Subject(
      id: 'ok',
      name: 'Introduction to Computing',
      code: 'CT101',
      teacher: 'A. Supnet',
      room: 'CC105',
      days: [1],
      startMin: 450,
      endMin: 570,
      color: 0xFF16A34A,
      semester: 1,
    );
    final userAdded = Subject(
      id: 'user',
      name: 'PE 1',
      code: 'PE101',
      teacher: '',
      room: '',
      days: [3],
      startMin: 480,
      endMin: 540,
      color: 0xFF16A34A,
    );
    final result = migrateStoredSubjects([correct, userAdded], []);
    expect(result.changed, isFalse);
    expect(result.subjects.length, 2);
    expect(result.subjects[0], same(correct));
    expect(result.subjects[1], same(userAdded));
  });

  test('grades stay attached to repaired subjects, remap off '
      'duplicates, and drop with junk', () {
    final rows = [
      ..._screenshotRows(),
      // Duplicate of the CT101 Monday meeting, different id.
      _bad(
        id: 'dup',
        name: 'Introduction Of Computing',
        code: 'CC105',
        days: [1],
        startMin: 7 * 60 + 30,
        endMin: 9 * 60 + 30,
        room: 'CC105',
      ),
      _bad(
        id: 'junk',
        name: 'Vigan',
        code: 'v',
        days: [5],
        startMin: 8 * 60,
        endMin: 9 * 60,
      ),
    ];
    final grades = [
      GradeRecord(subjectId: 'm1', grade: 1.5, units: 3, semester: 1),
      GradeRecord(subjectId: 'dup', grade: 2.0, units: 3, semester: 1),
      GradeRecord(subjectId: 'junk', grade: 1.0, units: 3, semester: 1),
    ];
    final result = migrateStoredSubjects(rows, grades);
    // The duplicate meeting is dropped; its grade moves to m1.
    expect(result.subjects.any((s) => s.id == 'dup'), isFalse);
    expect(
      result.grades
          .where((g) => g.subjectId == 'm1')
          .map((g) => g.grade)
          .toList(),
      [1.5, 2.0],
    );
    // The junk grade names no real subject, so it goes with it.
    expect(result.grades.any((g) => g.subjectId == 'junk'), isFalse);
    expect(result.grades.length, 2);
  });
}
