// Widget tests for Feature 3 of the Classes + menu build (Nov 10,
// 2026): the Files scan — tapping "Files" opens the file picker,
// the picked file's real text is scanned (same extraction path as
// Notes: ML Kit OCR / pdfrx / plain text), and the classes found
// spring into the timetable one by one with a green flash, a
// popping avatar, a "New" badge, and one placement chime each.
// A file with no parseable entries shows an honest empty state —
// no invented classes.
//
// The native picker and the file read are faked through
// ScheduleFileScanner's injectable seams: both deadlock in
// `flutter test`'s fake-async zone (the Notes tests fake their
// extractors for the same reason). The parser still runs for
// real on the canned text, and the real file-read path is covered
// by plain `test()`s in test/schedule_scan_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:estudyantego/features/student/classes_screen.dart';
import 'package:estudyantego/features/student/google_events.dart';
import 'package:estudyantego/features/student/schedule_scan.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Seeded at 6:00–7:00 on purpose, so scanned classes at 8:00+
// never conflict with it.
Subject _subject({int startMin = 6 * 60, int endMin = 7 * 60}) => Subject(
      id: 's1',
      name: 'Coding',
      code: 'CS101',
      teacher: '',
      room: '',
      days: const [1, 2, 3, 4, 5, 6, 7],
      startMin: startMin,
      endMin: endMin,
      color: 0xFF16A34A,
    );

Finder get _fab => find.byKey(const Key('classes-plus-fab'));
Finder get _menu => find.byKey(const Key('classes-plus-menu'));
Finder get _scanDialog => find.byKey(const Key('schedule-scan-progress'));
Finder get _emptyDialog => find.byKey(const Key('schedule-scan-empty'));
Finder get _scannedSpring =>
    find.byKey(const Key('scanned-subject-spring'));
Finder _tile(String name) => find.widgetWithText(ListTile, name);
Finder _newBadge(String name) => find.descendant(
      of: _tile(name),
      matching: find.text('New'),
    );

/// A scanner whose picker returns a dummy path (never read) and
/// whose extract step runs the REAL parser on [text] — the same
/// status mapping the real extract path produces, minus the file
/// I/O that cannot run in the fake-async zone.
ScheduleFileScanner _fakeScanner(String fileName, String text) {
  return ScheduleFileScanner(
    pickFile: () async => File(fileName),
    extractAndParse: (_) async {
      if (text.trim().isEmpty) {
        return ScheduleScanResult(
          status: ScheduleScanStatus.noText,
          fileName: fileName,
        );
      }
      final parsed = parseScheduleText(text);
      if (parsed.classes.isEmpty) {
        return ScheduleScanResult(
          status: ScheduleScanStatus.noClasses,
          fileName: fileName,
        );
      }
      return ScheduleScanResult(
        status: ScheduleScanStatus.found,
        fileName: fileName,
        classes: parsed.classes,
      );
    },
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  VoidCallback? onPlacementChime,
  ScheduleFileScanner? filesScanner,
  Subject? seed,
}) async {
  SharedPreferences.setMockInitialValues({
    StudentStorage.subjectsKey: jsonEncode([(seed ?? _subject()).toJson()]),
    StudentStorage.assignmentsKey: jsonEncode([]),
    // Explicit empty list so the mock Google sample set is not
    // seeded into this test's lists.
    googleEventsKey: jsonEncode([]),
  });
  await tester.pumpWidget(
    MaterialApp(
      home: ClassesScreen(
        onPlacementChime: onPlacementChime,
        filesScanner: filesScanner,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pump until [finder] appears (up to ~2 s of fake time), then
/// return whether it did. Used for the scan dialog, which opens
/// after the picker future resolves.
Future<bool> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int steps = 40,
}) async {
  for (var i = 0; i < steps && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return finder.evaluate().isNotEmpty;
}

Future<void> _openMenuAndTapFiles(WidgetTester tester) async {
  await tester.tap(_fab);
  await tester.pumpAndSettle();
  expect(_menu, findsOneWidget);
  await tester.tap(find.text('Files'));
}

void main() {
  testWidgets('tapping Files opens the picker; cancelling adds nothing',
      (tester) async {
    var picks = 0;
    final scanner = ScheduleFileScanner(
      pickFile: () async {
        picks++;
        return null; // User cancelled the picker.
      },
    );
    var chimes = 0;
    await _pumpScreen(
      tester,
      onPlacementChime: () => chimes++,
      filesScanner: scanner,
    );

    await _openMenuAndTapFiles(tester);
    await tester.pumpAndSettle();

    expect(picks, 1);
    expect(_scanDialog, findsNothing);
    expect(_emptyDialog, findsNothing);
    expect(_tile('Coding'), findsOneWidget);
    expect(chimes, 0);
  });

  testWidgets(
      'a file with schedule entries adds those classes one by one, '
      'with New badges and a chime each', (tester) async {
    final scanner = _fakeScanner(
      'schedule.txt',
      'Biology | Mon, Tue, Wed, Thu, Fri, Sat, Sun | 8:00 AM - 9:00 AM | Room 5 | Prof. Cruz\n'
      'Chemistry | Mon, Tue, Wed, Thu, Fri, Sat, Sun | 10:00 AM - 11:00 AM | Lab 2\n',
    );
    var chimes = 0;
    await _pumpScreen(
      tester,
      onPlacementChime: () => chimes++,
      filesScanner: scanner,
    );

    await _openMenuAndTapFiles(tester);
    // The scan dialog shows the sweeping line while extracting.
    expect(await _pumpUntil(tester, _scanDialog), isTrue);
    // Extraction finishes and the dialog pops; the first class
    // springs in. Step forward until the spring is visible.
    for (var i = 0; i < 40 && _scannedSpring.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_scanDialog, findsNothing);
    expect(_tile('Biology'), findsOneWidget);
    expect(_scannedSpring, findsOneWidget);
    expect(_newBadge('Biology'), findsOneWidget);
    expect(chimes, 1);
    // The second class has not landed yet (one by one, ~0.5 s).
    expect(_tile('Chemistry'), findsNothing);
    // Step past the 500 ms gap: the second class lands, and the
    // toast reports both.
    await tester.pump(const Duration(milliseconds: 600));
    expect(_tile('Chemistry'), findsOneWidget);
    expect(_newBadge('Chemistry'), findsOneWidget);
    expect(chimes, 2);
    expect(find.text('2 classes added from schedule.txt.'), findsOneWidget);
    await tester.pumpAndSettle();

    // Settled: both classes in the list with their details and
    // badges, spring wrapper gone.
    expect(_tile('Biology'), findsOneWidget);
    expect(
      find.descendant(
        of: _tile('Biology'),
        matching: find.textContaining('Room 5'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Prof. Cruz'), findsOneWidget);
    expect(_tile('Chemistry'), findsOneWidget);
    expect(find.textContaining('Lab 2'), findsOneWidget);
    expect(_newBadge('Biology'), findsOneWidget);
    expect(_newBadge('Chemistry'), findsOneWidget);
    expect(chimes, 2);
    expect(_scannedSpring, findsNothing);
    // Persisted: same repo/model as the manual form — reload shows
    // both, plus the seed.
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(StudentStorage.subjectsKey);
    final decoded = (jsonDecode(saved!) as List)
        .map((e) => Subject.fromJson(e as Map<String, dynamic>))
        .toList();
    expect(decoded.any((s) => s.name == 'Biology'), isTrue);
    expect(decoded.any((s) => s.name == 'Chemistry'), isTrue);
    expect(decoded.any((s) => s.name == 'Coding'), isTrue);
  });

  testWidgets(
      'a file with no parseable entries shows an honest empty state '
      'and adds nothing', (tester) async {
    final scanner = _fakeScanner(
      'notes.txt',
      'Welcome to the new semester!\nPlease check the bulletin board.\n',
    );
    var chimes = 0;
    await _pumpScreen(
      tester,
      onPlacementChime: () => chimes++,
      filesScanner: scanner,
    );

    await _openMenuAndTapFiles(tester);
    expect(await _pumpUntil(tester, _emptyDialog), isTrue);
    expect(find.text('No classes found'), findsOneWidget);
    expect(find.textContaining('notes.txt'), findsOneWidget);
    // The dialog explains the format the scan understands.
    expect(find.textContaining('Discrete Math'), findsOneWidget);
    expect(_tile('Coding'), findsOneWidget);
    expect(chimes, 0);

    await tester.tap(find.byKey(const Key('scan-empty-ok')));
    await tester.pumpAndSettle();
    expect(_emptyDialog, findsNothing);
    expect(_tile('Coding'), findsOneWidget);
    expect(chimes, 0);
  });

  testWidgets('an empty file shows the no-text state', (tester) async {
    final scanner = _fakeScanner('empty.txt', '');
    await _pumpScreen(tester, filesScanner: scanner);

    await _openMenuAndTapFiles(tester);
    expect(await _pumpUntil(tester, _emptyDialog), isTrue);
    expect(find.text('No text found'), findsOneWidget);
    expect(find.textContaining('empty.txt'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scan-empty-ok')));
    await tester.pumpAndSettle();
    expect(_emptyDialog, findsNothing);
  });

  testWidgets('a conflicting scanned class is skipped and reported',
      (tester) async {
    final scanner = _fakeScanner(
      'schedule.txt',
      'Clash | Mon, Tue, Wed, Thu, Fri, Sat, Sun | 8:00 AM - 9:00 AM\n'
      'Biology | Mon, Tue, Wed, Thu, Fri, Sat, Sun | 10:00 AM - 11:00 AM\n',
    );
    var chimes = 0;
    await _pumpScreen(
      tester,
      onPlacementChime: () => chimes++,
      filesScanner: scanner,
      // Seed on the first scanned class's slot, so it conflicts.
      seed: _subject(startMin: 8 * 60, endMin: 9 * 60),
    );

    await _openMenuAndTapFiles(tester);
    expect(await _pumpUntil(tester, _scanDialog), isTrue);
    // Step past the scan + placement gap, then assert before the
    // 5 s popup auto-dismisses.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(_tile('Clash'), findsNothing);
    expect(_tile('Biology'), findsOneWidget);
    expect(chimes, 1);
    expect(
      find.text(
          '1 class added from schedule.txt. 1 skipped (time conflict).'),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(_tile('Biology'), findsOneWidget);
    expect(_newBadge('Biology'), findsOneWidget);
  });

  testWidgets('the Files scan does not alter the other lists',
      (tester) async {
    final scanner = _fakeScanner(
      'schedule.txt',
      'Biology | Mon, Tue, Wed, Thu, Fri, Sat, Sun | 8:00 AM - 9:00 AM\n',
    );
    await _pumpScreen(tester, filesScanner: scanner);

    expect(find.text('Assignments & Exams'), findsOneWidget);
    await _openMenuAndTapFiles(tester);
    expect(await _pumpUntil(tester, _scanDialog), isTrue);
    // The dialog stays open with its repeating sweep line while
    // extracting, so never pumpAndSettle here — step until the
    // class lands, then settle once the dialog is gone.
    expect(await _pumpUntil(tester, _tile('Biology')), isTrue);
    await tester.pumpAndSettle();

    expect(_tile('Biology'), findsOneWidget);
    expect(_tile('Coding'), findsOneWidget);
    expect(find.text('Assignments & Exams'), findsOneWidget);
  });
}
