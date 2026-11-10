// Unit tests for Feature 3 of the Classes + menu build (Nov 10,
// 2026): the schedule-text parser behind the Files scan
// (lib/features/student/schedule_scan.dart). Covers the pipe,
// comma, and free-form line formats, day and time variants, code
// / room / teacher extraction, and the honesty rule — lines
// without both a weekday and a time range never yield a class.
import 'dart:io';

import 'package:estudyantego/features/student/schedule_scan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pipe format', () {
    test('parses a full pipe line', () {
      final result = parseScheduleText(
        'Discrete Math | Mon, Wed, Fri | 8:00 AM - 9:30 AM | Room 101 | Prof. Santos',
      );
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.name, 'Discrete Math');
      expect(c.days, [1, 3, 5]);
      expect(c.startMin, 8 * 60);
      expect(c.endMin, 9 * 60 + 30);
      expect(c.room, 'Room 101');
      expect(c.teacher, 'Prof. Santos');
    });

    test('parses a code in parentheses and a day range', () {
      final result = parseScheduleText(
        'Calculus (MATH 101) | Mon-Fri | 1:00 PM - 2:30 PM | Lab 2',
      );
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.name, 'Calculus');
      expect(c.code, 'MATH 101');
      expect(c.days, [1, 2, 3, 4, 5]);
      expect(c.startMin, 13 * 60);
      expect(c.endMin, 14 * 60 + 30);
      expect(c.room, 'Lab 2');
    });

    test('parses a leading code and 24-hour times', () {
      final result = parseScheduleText(
        'CS101 - Discrete Math | Tue, Thu | 13:00-14:30',
      );
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.name, 'Discrete Math');
      expect(c.code, 'CS101');
      expect(c.days, [2, 4]);
      expect(c.startMin, 13 * 60);
      expect(c.endMin, 14 * 60 + 30);
    });
  });

  group('comma and free-form lines', () {
    test('parses a comma line with days spread across segments', () {
      final result = parseScheduleText(
        'Biology, Mon, Wed, Fri, 10:00 AM - 11:00 AM, Room 5',
      );
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.name, 'Biology');
      expect(c.days, [1, 3, 5]);
      expect(c.startMin, 10 * 60);
      expect(c.endMin, 11 * 60);
      expect(c.room, 'Room 5');
    });

    test('parses a free-form line', () {
      final result = parseScheduleText(
        'Physics Mon Wed Fri 8:00 AM - 9:30 AM Room 201',
      );
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.name, 'Physics');
      expect(c.days, [1, 3, 5]);
      expect(c.startMin, 8 * 60);
      expect(c.endMin, 9 * 60 + 30);
      expect(c.room, 'Room 201');
    });

    test('parses compact days and a bare-hour range', () {
      final result = parseScheduleText(
        'Chemistry MWF 8-9:30am',
      );
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.name, 'Chemistry');
      expect(c.days, [1, 3, 5]);
      expect(c.startMin, 8 * 60);
      expect(c.endMin, 9 * 60 + 30);
    });

    test('parses TTh and an afternoon bare range', () {
      final result = parseScheduleText(
        'History TTh 2:00-3:30',
      );
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.name, 'History');
      expect(c.days, [2, 4]);
      expect(c.startMin, 14 * 60);
      expect(c.endMin, 15 * 60 + 30);
    });

    test('an end marker applies to a bare start, and vice versa', () {
      final pm = parseScheduleText('Art Mon 1:00 PM - 2:30');
      expect(pm.classes.single.startMin, 13 * 60);
      expect(pm.classes.single.endMin, 14 * 60 + 30);
      final am = parseScheduleText('Music Mon 8:00 - 9:30 AM');
      expect(am.classes.single.startMin, 8 * 60);
      expect(am.classes.single.endMin, 9 * 60 + 30);
    });

    test('parses an en-dash separator and full day names', () {
      final result = parseScheduleText(
        'English Monday Wednesday Friday 8:00 AM – 9:00 AM',
      );
      expect(result.classes, hasLength(1));
      final c = result.classes.single;
      expect(c.name, 'English');
      expect(c.days, [1, 3, 5]);
    });
  });

  group('honesty: nothing is invented', () {
    test('a file with no parseable entries yields no classes', () {
      const text = '''
Class Schedule

Welcome to the new semester!
Please check the bulletin board for updates.
Monday
8:00 AM
''';
      expect(parseScheduleText(text).classes, isEmpty);
    });

    test('lines missing days, time, or a name are skipped', () {
      const text = '''
Biology Mon Wed Fri
Chemistry 8:00 AM - 9:00 AM
8:00 AM - 9:00 AM Mon Wed Fri
''';
      expect(parseScheduleText(text).classes, isEmpty);
    });

    test('an end time at or before the start is skipped', () {
      expect(parseScheduleText('Art Mon 9:00 AM - 8:00 AM').classes,
          isEmpty);
      expect(parseScheduleText('Art Mon 8:00 AM - 8:00 AM').classes,
          isEmpty);
    });

    test('a date is never mistaken for a time range', () {
      expect(parseScheduleText('Math Mon 2026-11-10').classes, isEmpty);
    });

    test('duplicate entries in the file are kept once', () {
      const text = '''
Biology | Mon, Wed, Fri | 8:00 AM - 9:00 AM
Biology | Mon, Wed, Fri | 8:00 AM - 9:00 AM
Biology | Tue, Thu | 8:00 AM - 9:00 AM
''';
      final result = parseScheduleText(text);
      expect(result.classes, hasLength(2));
    });

    test('headers and notes around real entries are ignored', () {
      const text = '''
Class Schedule - 1st Semester
Subject | Days | Time | Room
Biology | Mon, Wed, Fri | 8:00 AM - 9:00 AM | Room 5
Good luck this semester!
''';
      final result = parseScheduleText(text);
      expect(result.classes, hasLength(1));
      expect(result.classes.single.name, 'Biology');
    });
  });

  group('toSubject', () {
    test('maps a scanned class onto a Subject', () {
      const scanned = ScannedClass(
        name: 'Biology',
        code: 'BIO101',
        teacher: 'Ms. Cruz',
        room: 'Room 5',
        days: [1, 3, 5],
        startMin: 480,
        endMin: 540,
      );
      final subject = scanned.toSubject(id: 'x', color: 0xFF16A34A);
      expect(subject.id, 'x');
      expect(subject.name, 'Biology');
      expect(subject.code, 'BIO101');
      expect(subject.teacher, 'Ms. Cruz');
      expect(subject.room, 'Room 5');
      expect(subject.days, [1, 3, 5]);
      expect(subject.startMin, 480);
      expect(subject.endMin, 540);
    });
  });

  // Plain tests (real async): the real file-read path — a real
  // temp .txt file through the real NoteExtractService. Widget
  // tests cannot do this (real file I/O deadlocks in the fake-
  // async zone), so it lives here, next to the Notes tests' own
  // file-read test.
  group('ScheduleFileScanner with real files', () {
    test('a real text file with entries scans to found classes',
        () async {
      final dir = await Directory.systemTemp.createTemp('schedule_scan');
      try {
        final file = File('${dir.path}/schedule.txt');
        await file.writeAsString(
          'Biology | Mon, Wed, Fri | 8:00 AM - 9:00 AM | Room 5\n'
          'Chemistry | Tue, Thu | 10:00 AM - 11:00 AM\n',
        );
        final result =
            await ScheduleFileScanner().extractAndParse(file);
        expect(result.status, ScheduleScanStatus.found);
        expect(result.fileName, 'schedule.txt');
        expect(
          result.classes.map((c) => c.name),
          ['Biology', 'Chemistry'],
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('a real text file with no entries scans to noClasses',
        () async {
      final dir = await Directory.systemTemp.createTemp('schedule_scan');
      try {
        final file = File('${dir.path}/notes.txt');
        await file.writeAsString('Welcome to the new semester!\n');
        final result =
            await ScheduleFileScanner().extractAndParse(file);
        expect(result.status, ScheduleScanStatus.noClasses);
        expect(result.classes, isEmpty);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('an empty real text file scans to noText', () async {
      final dir = await Directory.systemTemp.createTemp('schedule_scan');
      try {
        final file = File('${dir.path}/empty.txt');
        await file.writeAsString('');
        final result =
            await ScheduleFileScanner().extractAndParse(file);
        expect(result.status, ScheduleScanStatus.noText);
        expect(result.classes, isEmpty);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('cancelling the picker scans to cancelled', () async {
      final result = await ScheduleFileScanner(
        pickFile: () async => null,
      ).scan();
      expect(result.status, ScheduleScanStatus.cancelled);
    });
  });
}
