// Tests for the table-fragment pass in
// lib/features/student/schedule_scan.dart (Nov 10, 2026): the
// Files scan of a Certificate of Registration photo, whose table
// OCR comes out fragmented — subject, day code, time range,
// room, and instructor on separate or interleaved lines.
//
// The certificate used here is Steven's real one (UNP, 1st Term
// 2026-2027, DCT 1), as a TEST CASE only: the parser is general
// and nothing about this schedule is hardcoded into it.
//   CT101 Introduction to Computing — Mon 7:30-9:30 AM CC105 +
//     Tue/Thu 2:00-3:30 PM CC104, A. Supnet
//   CT102 Computer Programming 1 — Mon 10:00 AM-12:00 PM CC105 +
//     Tue/Thu 10:30 AM-12:00 PM CC104, W.E. Que
//   CSS101 Installing and Configuring Computer Systems —
//     Mon 1:00-3:00 PM CC105 + Tue/Thu 9:00-10:30 AM CC203,
//     L. Baja
// Day codes confirmed by Steven: M = Monday, T = Tuesday,
// W = Wednesday, Th = Thursday, Sat = Saturday,
// TTh = Tuesday + Thursday.
import 'package:estudyantego/features/student/schedule_scan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('certificate: fragmented table OCR', () {
    test('produces all 6 entries from fragmented OCR text', () {
      const text = '''
Certificate of Registration
University of Northern Philippines
1st Term 2026-2027
Diploma in Computer Technology 1
CT101
Introduction to Computing
M
7:30-9:30 AM
CC105
A. Supnet
TTh
2:00-3:30 PM
CC104
A. Supnet
CT102
Computer Programming 1
M 10:00 AM-12:00 PM
CC105
W.E. Que
TTh 10:30 AM-12:00 PM CC104
W.E. Que
CSS101 Installing and Configuring
Computer Systems
M 1:00-3:00 PM CC105
L. Baja
TTh
9:00-10:30 AM
CC203 L. Baja
''';
      final result = parseScheduleText(text);
      expect(result.classes, hasLength(6));

      final ct101Mon = result.classes[0];
      expect(ct101Mon.name, 'Introduction to Computing');
      expect(ct101Mon.code, 'CT101');
      expect(ct101Mon.days, [1]);
      expect(ct101Mon.startMin, 7 * 60 + 30);
      expect(ct101Mon.endMin, 9 * 60 + 30);
      expect(ct101Mon.room, 'CC105');
      expect(ct101Mon.teacher, 'A. Supnet');

      final ct101Tth = result.classes[1];
      expect(ct101Tth.name, 'Introduction to Computing');
      expect(ct101Tth.code, 'CT101');
      expect(ct101Tth.days, [2, 4]);
      expect(ct101Tth.startMin, 14 * 60);
      expect(ct101Tth.endMin, 15 * 60 + 30);
      expect(ct101Tth.room, 'CC104');
      expect(ct101Tth.teacher, 'A. Supnet');

      final ct102Mon = result.classes[2];
      expect(ct102Mon.name, 'Computer Programming 1');
      expect(ct102Mon.code, 'CT102');
      expect(ct102Mon.days, [1]);
      expect(ct102Mon.startMin, 10 * 60);
      expect(ct102Mon.endMin, 12 * 60);
      expect(ct102Mon.room, 'CC105');
      expect(ct102Mon.teacher, 'W.E. Que');

      final ct102Tth = result.classes[3];
      expect(ct102Tth.name, 'Computer Programming 1');
      expect(ct102Tth.code, 'CT102');
      expect(ct102Tth.days, [2, 4]);
      expect(ct102Tth.startMin, 10 * 60 + 30);
      expect(ct102Tth.endMin, 12 * 60);
      expect(ct102Tth.room, 'CC104');
      expect(ct102Tth.teacher, 'W.E. Que');

      final css101Mon = result.classes[4];
      expect(css101Mon.name,
          'Installing and Configuring Computer Systems');
      expect(css101Mon.code, 'CSS101');
      expect(css101Mon.days, [1]);
      expect(css101Mon.startMin, 13 * 60);
      expect(css101Mon.endMin, 15 * 60);
      expect(css101Mon.room, 'CC105');
      expect(css101Mon.teacher, 'L. Baja');

      final css101Tth = result.classes[5];
      expect(css101Tth.name,
          'Installing and Configuring Computer Systems');
      expect(css101Tth.code, 'CSS101');
      expect(css101Tth.days, [2, 4]);
      expect(css101Tth.startMin, 9 * 60);
      expect(css101Tth.endMin, 10 * 60 + 30);
      expect(css101Tth.room, 'CC203');
      expect(css101Tth.teacher, 'L. Baja');
    });
  });

  group('certificate: cleaner OCR', () {
    test('produces all 6 entries, one line per schedule', () {
      const text = '''
Certificate of Registration
University of Northern Philippines
1st Term 2026-2027
CT101 Introduction to Computing M 7:30-9:30 AM CC105 A. Supnet
CT101 Introduction to Computing TTh 2:00-3:30 PM CC104 A. Supnet
CT102 Computer Programming 1 M 10:00 AM-12:00 PM CC105 W.E. Que
CT102 Computer Programming 1 TTh 10:30 AM-12:00 PM CC104 W.E. Que
CSS101 Installing and Configuring Computer Systems M 1:00-3:00 PM CC105 L. Baja
CSS101 Installing and Configuring Computer Systems TTh 9:00-10:30 AM CC203 L. Baja
''';
      final result = parseScheduleText(text);
      expect(result.classes, hasLength(6));
      // Order is not contractual: the one-line pass finds the
      // TTh lines first and the fragment pass adds the Mon lines,
      // so look each entry up by code + days.
      ScannedClass at(String code, List<int> days) =>
          result.classes.singleWhere(
            (c) => c.code == code && c.days.join(',') == days.join(','),
          );
      expect((at('CT101', [1]).startMin, at('CT101', [1]).room,
          at('CT101', [1]).teacher), (7 * 60 + 30, 'CC105', 'A. Supnet'));
      expect((at('CT101', [2, 4]).startMin, at('CT101', [2, 4]).room),
          (14 * 60, 'CC104'));
      expect((at('CT102', [1]).startMin, at('CT102', [1]).teacher),
          (10 * 60, 'W.E. Que'));
      expect(at('CT102', [2, 4]).startMin, 10 * 60 + 30);
      expect(at('CSS101', [1]).startMin, 13 * 60);
      expect((at('CSS101', [2, 4]).startMin, at('CSS101', [2, 4]).room,
          at('CSS101', [2, 4]).teacher), (9 * 60, 'CC203', 'L. Baja'));
      // The "W" in "W.E. Que" must never donate a Wednesday.
      expect(at('CT102', [1]).days, [1]);
      expect(at('CT102', [2, 4]).days, [2, 4]);
    });
  });

  group('bare day codes in schedule fragments', () {
    test('a bare W next to a time range is Wednesday', () {
      const text = '''
MATH101
College Algebra
W
1:00-2:30 PM
Room 12
''';
      final result = parseScheduleText(text);
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.name, 'College Algebra');
      expect(c.code, 'MATH101');
      expect(c.days, [3]);
      expect(c.startMin, 13 * 60);
      expect(c.endMin, 14 * 60 + 30);
      expect(c.room, 'Room 12');
    });

    test('a bare W on the same line as its time range is Wednesday',
        () {
      final result = parseScheduleText(
        'MATH101 College Algebra W 9-10:30 am Room 12',
      );
      expect(result.classes, hasLength(1));
      expect(result.classes.single.days, [3]);
      expect(result.classes.single.startMin, 9 * 60);
      expect(result.classes.single.endMin, 10 * 60 + 30);
    });

    test('a bare Th on its own line is Thursday', () {
      const text = '''
ENG101
English
Th
8:00-9:30 AM
Room 3
''';
      final result = parseScheduleText(text);
      expect(result.classes, hasLength(1));
      expect(result.classes.single.days, [4]);
      expect(result.classes.single.startMin, 8 * 60);
      expect(result.classes.single.endMin, 9 * 60 + 30);
    });

    test('a Sat fragment is Saturday', () {
      const text = '''
PE101
Physical Education
Sat
9:00-10:30 AM
Gym 1
''';
      final result = parseScheduleText(text);
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.name, 'Physical Education');
      expect(c.code, 'PE101');
      expect(c.days, [6]);
      expect(c.startMin, 9 * 60);
      expect(c.endMin, 10 * 60 + 30);
      expect(c.room, 'Gym 1');
    });

    test('a Sat class on one line with an en-dash range', () {
      final result = parseScheduleText(
        'PE101 Physical Education Sat 9:00–10:30 AM Gym 1',
      );
      expect(result.classes, hasLength(1));
      expect(result.classes.single.days, [6]);
      expect(result.classes.single.startMin, 9 * 60);
      expect(result.classes.single.endMin, 10 * 60 + 30);
    });

    test('a bare-hour start with the marker on the end only', () {
      const text = '''
MATH101
College Algebra
M
10 am-12 pm
Room 12
''';
      final result = parseScheduleText(text);
      expect(result.classes, hasLength(1));
      expect(result.classes.single.days, [1]);
      expect(result.classes.single.startMin, 10 * 60);
      expect(result.classes.single.endMin, 12 * 60);
    });
  });

  group('fragment honesty: nothing is invented', () {
    test('a bare M or W in prose, with no time, yields nothing',
        () {
      const text = '''
Welcome to the new semester!
M
Please bring your ID.
W
''';
      expect(parseScheduleText(text).classes, isEmpty);
    });

    test('a day and a time with no subject yields nothing', () {
      const text = '''
M
7:30-9:30 AM
CC105
''';
      expect(parseScheduleText(text).classes, isEmpty);
    });

    test('a day-only line before any subject is ignored', () {
      const text = '''
Monday
8:00 AM - 9:00 AM
''';
      expect(parseScheduleText(text).classes, isEmpty);
    });
  });

  group('regression: one-class-per-line still works', () {
    test('pipe line still parses', () {
      final result = parseScheduleText(
        'Biology | Mon, Wed, Fri | 8:00 AM - 9:00 AM | Room 5',
      );
      expect(result.classes, hasLength(1));
      expect(result.classes.single.name, 'Biology');
      expect(result.classes.single.days, [1, 3, 5]);
    });

    test('free-form line still parses', () {
      final result = parseScheduleText(
        'Physics Mon Wed Fri 8:00 AM - 9:30 AM Room 201',
      );
      expect(result.classes, hasLength(1));
      expect(result.classes.single.name, 'Physics');
      expect(result.classes.single.days, [1, 3, 5]);
    });

    test('fragment entries are not duplicated by the two passes',
        () {
      const text = '''
CT101 Introduction to Computing M 7:30-9:30 AM CC105 A. Supnet
CT101 Introduction to Computing M 7:30-9:30 AM CC105 A. Supnet
''';
      expect(parseScheduleText(text).classes, hasLength(1));
    });
  });

  group('certificate: day code AFTER the time range', () {
    // Steven's real certificate (UNP, 1st Term 2026-2027, DCT 1)
    // as a TEST CASE only: on the real certificate the day code
    // comes AFTER the time on the same line ("7:30-9:30 am M
    // CC105"), which the parser used to miss entirely — it only
    // read days from before a time range or from a day-only line
    // above it. This group must fail before that fix and pass
    // after it.
    test('all 6 entries with the day after the time', () {
      const text = '''
Certificate of Registration
University of Northern Philippines
1st Term 2026-2027
Diploma in Computer Technology 1
CT101 Introduction to Computing 7:30-9:30 am M CC105 A. Supnet
CT101 Introduction to Computing 2-3:30 pm TTh CC104 A. Supnet
CT102 Computer Programming 1 10 am-12 pm M CC105 W.E. Que
CT102 Computer Programming 1 10:30 am-12 pm TTh CC104 W.E. Que
CSS101 Installing and Configuring Computer Systems 1-3 pm M CC105 L. Baja
CSS101 Installing and Configuring Computer Systems 9-10:30 am TTh CC203 L. Baja
''';
      final result = parseScheduleText(text);
      expect(result.classes, hasLength(6));
      ScannedClass at(String code, List<int> days) =>
          result.classes.singleWhere(
            (c) => c.code == code && c.days.join(',') == days.join(','),
          );

      final ct101Mon = at('CT101', [1]);
      expect(ct101Mon.name, 'Introduction to Computing');
      expect(ct101Mon.startMin, 7 * 60 + 30);
      expect(ct101Mon.endMin, 9 * 60 + 30);
      expect(ct101Mon.room, 'CC105');
      expect(ct101Mon.teacher, 'A. Supnet');

      final ct101Tth = at('CT101', [2, 4]);
      expect(ct101Tth.startMin, 14 * 60);
      expect(ct101Tth.endMin, 15 * 60 + 30);
      expect(ct101Tth.room, 'CC104');
      expect(ct101Tth.teacher, 'A. Supnet');

      final ct102Mon = at('CT102', [1]);
      expect(ct102Mon.name, 'Computer Programming 1');
      expect(ct102Mon.startMin, 10 * 60);
      expect(ct102Mon.endMin, 12 * 60);
      expect(ct102Mon.room, 'CC105');
      expect(ct102Mon.teacher, 'W.E. Que');

      final ct102Tth = at('CT102', [2, 4]);
      expect(ct102Tth.startMin, 10 * 60 + 30);
      expect(ct102Tth.endMin, 12 * 60);
      expect(ct102Tth.room, 'CC104');
      expect(ct102Tth.teacher, 'W.E. Que');

      final css101Mon = at('CSS101', [1]);
      expect(css101Mon.name,
          'Installing and Configuring Computer Systems');
      expect(css101Mon.startMin, 13 * 60);
      expect(css101Mon.endMin, 15 * 60);
      expect(css101Mon.room, 'CC105');
      expect(css101Mon.teacher, 'L. Baja');

      final css101Tth = at('CSS101', [2, 4]);
      expect(css101Tth.startMin, 9 * 60);
      expect(css101Tth.endMin, 10 * 60 + 30);
      expect(css101Tth.room, 'CC203');
      expect(css101Tth.teacher, 'L. Baja');

      // Honesty: the "W" in "W.E. Que" after the room code must
      // never donate a Wednesday.
      expect(at('CT102', [1]).days, [1]);
      expect(at('CT102', [2, 4]).days, [2, 4]);
    });

    test('full certificate, all schedule lines day-after-time',
        () {
      const text = '''
Certificate of Registration
University of Northern Philippines
1st Term 2026-2027
Diploma in Computer Technology 1
CT101
Introduction to Computing
7:30-9:30 am M CC105 A. Supnet
2-3:30 pm TTh CC104 A. Supnet
CT102
Computer Programming 1
10 am-12 pm M CC105 W.E. Que
10:30 am-12 pm TTh CC104 W.E. Que
CSS101
Installing and Configuring Computer Systems
1-3 pm M CC105 L. Baja
9-10:30 am TTh CC203 L. Baja
''';
      final result = parseScheduleText(text);
      expect(result.classes, hasLength(6));
      ScannedClass at(String code, List<int> days) =>
          result.classes.singleWhere(
            (c) => c.code == code && c.days.join(',') == days.join(','),
          );
      expect(at('CT101', [1]).startMin, 7 * 60 + 30);
      expect(at('CT101', [2, 4]).startMin, 14 * 60);
      expect(at('CT102', [1]).startMin, 10 * 60);
      expect(at('CT102', [2, 4]).startMin, 10 * 60 + 30);
      expect(at('CSS101', [1]).startMin, 13 * 60);
      expect(at('CSS101', [2, 4]).startMin, 9 * 60);
      expect(at('CT102', [1]).days, [1]);
      expect(at('CT102', [2, 4]).days, [2, 4]);
    });

    test('"T Th" as two tokens after the time is Tue + Thu', () {
      final result = parseScheduleText(
        'CT101 Introduction to Computing 2-3:30 pm T Th CC104 A. Supnet',
      );
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.days, [2, 4]);
      expect(c.startMin, 14 * 60);
      expect(c.endMin, 15 * 60 + 30);
      expect(c.room, 'CC104');
      expect(c.teacher, 'A. Supnet');
    });

    test('extra spaces after the time still parse', () {
      final result = parseScheduleText(
        'CT101 Introduction to Computing 7:30-9:30  am   M   CC105 A. Supnet',
      );
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.days, [1]);
      expect(c.startMin, 7 * 60 + 30);
      expect(c.endMin, 9 * 60 + 30);
      expect(c.room, 'CC105');
      expect(c.teacher, 'A. Supnet');
    });

    test('time line then day line split creates the class', () {
      const text = '''
CT101
Introduction to Computing
7:30-9:30 AM CC105 A. Supnet
M
''';
      final result = parseScheduleText(text);
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.name, 'Introduction to Computing');
      expect(c.code, 'CT101');
      expect(c.days, [1]);
      expect(c.startMin, 7 * 60 + 30);
      expect(c.endMin, 9 * 60 + 30);
      expect(c.room, 'CC105');
      expect(c.teacher, 'A. Supnet');
    });

    test('time line then day-plus-room line split creates the class',
        () {
      const text = '''
CT101
Introduction to Computing
7:30-9:30 AM
M CC105
A. Supnet
''';
      final result = parseScheduleText(text);
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.days, [1]);
      expect(c.startMin, 7 * 60 + 30);
      expect(c.endMin, 9 * 60 + 30);
      expect(c.room, 'CC105');
      expect(c.teacher, 'A. Supnet');
    });

    test('day line then time line split still creates the class',
        () {
      const text = '''
CT101
Introduction to Computing
M
7:30-9:30 AM
CC105
A. Supnet
''';
      final result = parseScheduleText(text);
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.days, [1]);
      expect(c.startMin, 7 * 60 + 30);
      expect(c.endMin, 9 * 60 + 30);
      expect(c.room, 'CC105');
      expect(c.teacher, 'A. Supnet');
    });

    test('day after the time with no room, just a teacher', () {
      final result = parseScheduleText(
        'CT101 Introduction to Computing 7:30-9:30 am M A. Supnet',
      );
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.days, [1]);
      expect(c.startMin, 7 * 60 + 30);
      expect(c.endMin, 9 * 60 + 30);
      expect(c.teacher, 'A. Supnet');
      expect(c.room, isEmpty);
    });

    test('a day line further down does not attach to a dayless time',
        () {
      const text = '''
CT101
Introduction to Computing
7:30-9:30 AM CC105 A. Supnet
Some note with no days
M
''';
      // The time line has no days and the next non-empty line
      // ("Some note...") has no leading day tokens, so the
      // pending time is discarded and the lone "M" yields nothing.
      expect(parseScheduleText(text).classes, isEmpty);
    });
  });
}
