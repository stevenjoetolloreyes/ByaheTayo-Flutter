// Widget tests for Feature 4 of the Classes + menu build (Nov 10,
// 2026): Google Schedule — tapping "Google Schedule" connects the
// student's REAL Google Calendar and places its events one by one
// with a spring-in, a green flash, a popping G badge, a "New"
// badge, and one placement chime each. A missing Console setup
// shows the exact steps instead of a fake "connected" state, and
// the 4 placeholder sample events are never presented as synced
// results — the first successful real sync replaces them.
//
// The native Google Sign-In and the Calendar API cannot run in
// `flutter test`'s fake-async zone (the Files scan fakes its
// picker/extractor for the same reason), so the connect/fetch
// steps are faked through GoogleCalendarSync's injectable seams.
// The real connect/fetch paths are covered by plain `test()`s over
// the pure parser in test/google_calendar_sync_test.dart.
import 'dart:convert';

import 'package:estudyantego/features/student/classes_screen.dart';
import 'package:estudyantego/features/student/google_calendar_sync.dart';
import 'package:estudyantego/features/student/google_events.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Seeded at 6:00–7:00 on purpose, so synced classes at 8:00+
// never match it by title or time.
Subject _subject({String name = 'Coding'}) => Subject(
      id: 's1',
      name: name,
      code: 'CS101',
      teacher: '',
      room: '',
      days: const [1, 2, 3, 4, 5, 6, 7],
      startMin: 6 * 60,
      endMin: 7 * 60,
      color: 0xFF16A34A,
    );

GoogleCalendarEvent _synced({
  required String id,
  required String title,
  int weekday = 1,
  int startMin = 8 * 60,
  int endMin = 9 * 60,
  String place = 'Room 5',
}) =>
    GoogleCalendarEvent(
      id: id,
      title: title,
      weekday: weekday,
      startMin: startMin,
      endMin: endMin,
      place: place,
      color: 0xFF16A34A,
    );

const _connection = GoogleCalendarConnection(
  accessToken: 'fake-token',
  email: 'student@gmail.com',
);

Finder get _fab => find.byKey(const Key('classes-plus-fab'));
Finder get _menu => find.byKey(const Key('classes-plus-menu'));
Finder get _syncDialog => find.byKey(const Key('google-sync-progress'));
Finder get _setupDialog =>
    find.byKey(const Key('google-sync-setup-missing'));
Finder get _emptyDialog => find.byKey(const Key('google-sync-empty'));
Finder get _syncedSpring => find.byKey(const Key('synced-google-spring'));
Finder _tile(String name) => find.widgetWithText(ListTile, name);
Finder _newBadge(String name) => find.descendant(
      of: _tile(name),
      matching: find.text('New'),
    );

Future<void> _pumpScreen(
  WidgetTester tester, {
  VoidCallback? onPlacementChime,
  GoogleCalendarSync? googleSync,
  Subject? seed,
  List<GoogleCalendarEvent>? googleEvents,
  bool realSyncDone = false,
}) async {
  SharedPreferences.setMockInitialValues({
    StudentStorage.subjectsKey: jsonEncode([(seed ?? _subject()).toJson()]),
    StudentStorage.assignmentsKey: jsonEncode([]),
    // Explicit list so the mock Google sample set is not seeded
    // into this test's lists (except the test that seeds it on
    // purpose to prove the first real sync replaces it).
    googleEventsKey:
        jsonEncode((googleEvents ?? []).map((e) => e.toJson()).toList()),
    if (realSyncDone) googleCalendarRealSyncKey: 1,
  });
  await tester.pumpWidget(
    MaterialApp(
      home: ClassesScreen(
        onPlacementChime: onPlacementChime,
        googleSync: googleSync,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pump until [finder] appears (up to ~2 s of fake time), then
/// return whether it did. Used for the sync dialog, which opens
/// after the menu tap resolves.
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

Future<void> _openMenuAndTapGoogle(WidgetTester tester) async {
  await tester.tap(_fab);
  await tester.pumpAndSettle();
  expect(_menu, findsOneWidget);
  await tester.tap(find.text('Google Schedule'));
}

GoogleCalendarSync _fakeSync({
  required List<GoogleCalendarEvent> events,
  Object? connectError,
  Object? fetchError,
}) {
  return GoogleCalendarSync(
    connect: () async {
      if (connectError != null) throw connectError;
      return _connection;
    },
    fetchEvents: (_) async {
      if (fetchError != null) throw fetchError;
      return events;
    },
  );
}

void main() {
  testWidgets(
      'synced events land one by one with New badges and a chime each',
      (tester) async {
    final sync = _fakeSync(events: [
      _synced(id: 'gcal-bio-1', title: 'Biology'),
      _synced(
        id: 'gcal-chem-2',
        title: 'Chemistry',
        weekday: 2,
        startMin: 10 * 60,
        endMin: 11 * 60,
        place: 'Lab 2',
      ),
    ]);
    var chimes = 0;
    await _pumpScreen(
      tester,
      onPlacementChime: () => chimes++,
      googleSync: sync,
    );

    await _openMenuAndTapGoogle(tester);
    // The progress dialog shows while the (fake) connect + fetch
    // run. (The connecting → syncing phase order is covered by
    // the service test in test/google_calendar_sync_test.dart —
    // with instant fakes the dialog may already be on its second
    // phase before the first frame.)
    expect(await _pumpUntil(tester, _syncDialog), isTrue);
    // The fetch finishes and the dialog pops; the first event
    // springs in. Step forward until the spring is visible.
    for (var i = 0; i < 40 && _syncedSpring.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_syncDialog, findsNothing);
    expect(_tile('Biology'), findsOneWidget);
    expect(_syncedSpring, findsOneWidget);
    expect(_newBadge('Biology'), findsOneWidget);
    expect(chimes, 1);
    // The second event has not landed yet (one by one, ~0.5 s).
    expect(_tile('Chemistry'), findsNothing);
    // Step past the 500 ms gap: the second event lands, and the
    // toast reports both.
    await tester.pump(const Duration(milliseconds: 600));
    expect(_tile('Chemistry'), findsOneWidget);
    expect(_newBadge('Chemistry'), findsOneWidget);
    expect(chimes, 2);
    expect(find.text('2 classes synced from Google Calendar.'),
        findsOneWidget);
    await tester.pumpAndSettle();

    // Settled: both events in the list with their details and
    // badges, spring wrapper gone.
    expect(_tile('Biology'), findsOneWidget);
    expect(
      find.descendant(
        of: _tile('Biology'),
        matching: find.textContaining('Room 5'),
      ),
      findsOneWidget,
    );
    expect(_tile('Chemistry'), findsOneWidget);
    expect(find.textContaining('Lab 2'), findsOneWidget);
    expect(_newBadge('Biology'), findsOneWidget);
    expect(_newBadge('Chemistry'), findsOneWidget);
    expect(chimes, 2);
    expect(_syncedSpring, findsNothing);
    // Persisted: reload shows both, plus the seed subject.
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(googleEventsKey);
    final decoded = (jsonDecode(saved!) as List)
        .map((e) => GoogleCalendarEvent.fromJson(e as Map<String, dynamic>))
        .toList();
    expect(decoded.any((e) => e.title == 'Biology'), isTrue);
    expect(decoded.any((e) => e.title == 'Chemistry'), isTrue);
    expect(prefs.getInt(googleCalendarRealSyncKey), 1);
  });

  testWidgets(
      'a missing setup shows the exact Console steps and adds nothing',
      (tester) async {
    final sync = _fakeSync(
      events: [],
      connectError: const GoogleCalendarSetupMissing('no OAuth client'),
    );
    var chimes = 0;
    await _pumpScreen(
      tester,
      onPlacementChime: () => chimes++,
      googleSync: sync,
    );

    await _openMenuAndTapGoogle(tester);
    expect(await _pumpUntil(tester, _setupDialog), isTrue);
    expect(find.text('Google Calendar isn\'t connected yet'),
        findsOneWidget);
    expect(find.textContaining('Google Calendar API'), findsOneWidget);
    expect(find.textContaining('calendar.readonly'), findsOneWidget);
    expect(find.textContaining('com.estudyantego.app'), findsOneWidget);
    // No fake "connected" state, no events, no chime.
    expect(_tile('Biology'), findsNothing);
    expect(chimes, 0);

    await tester.tap(find.byKey(const Key('google-setup-ok')));
    await tester.pumpAndSettle();
    expect(_setupDialog, findsNothing);
    expect(chimes, 0);
  });

  testWidgets('cancelling the connect adds nothing and says nothing',
      (tester) async {
    final sync = _fakeSync(
      events: [],
      connectError: GoogleCalendarCancelled(),
    );
    var chimes = 0;
    await _pumpScreen(
      tester,
      onPlacementChime: () => chimes++,
      googleSync: sync,
    );

    await _openMenuAndTapGoogle(tester);
    await tester.pumpAndSettle();

    expect(_syncDialog, findsNothing);
    expect(_setupDialog, findsNothing);
    expect(_emptyDialog, findsNothing);
    expect(_tile('Coding'), findsOneWidget);
    expect(chimes, 0);
  });

  testWidgets(
      'a connected calendar with no class events shows an honest '
      'empty state', (tester) async {
    final sync = _fakeSync(events: []);
    var chimes = 0;
    await _pumpScreen(
      tester,
      onPlacementChime: () => chimes++,
      googleSync: sync,
    );

    await _openMenuAndTapGoogle(tester);
    expect(await _pumpUntil(tester, _emptyDialog), isTrue);
    expect(find.text('No classes found'), findsOneWidget);
    expect(find.textContaining('student@gmail.com'), findsOneWidget);
    expect(find.textContaining('next 4 weeks'), findsOneWidget);
    expect(chimes, 0);

    await tester.tap(find.byKey(const Key('google-sync-empty-ok')));
    await tester.pumpAndSettle();
    expect(_emptyDialog, findsNothing);
    expect(chimes, 0);
  });

  testWidgets(
      'the first real sync replaces the placeholder sample events '
      'and never presents them as synced', (tester) async {
    final sync = _fakeSync(events: [
      _synced(id: 'gcal-bio-1', title: 'Biology'),
    ]);
    var chimes = 0;
    await _pumpScreen(
      tester,
      onPlacementChime: () => chimes++,
      googleSync: sync,
      // The seeded placeholder set, as it exists before any sync.
      googleEvents: sampleGoogleEvents(),
    );

    // Before the sync, the placeholders are listed — but with no
    // "New" badge and no chime: they were never synced results.
    expect(_tile('Discrete Mathematics'), findsOneWidget);
    expect(_newBadge('Discrete Mathematics'), findsNothing);
    expect(_newBadge('NSTP 1'), findsNothing);
    expect(chimes, 0);

    await _openMenuAndTapGoogle(tester);
    expect(await _pumpUntil(tester, _tile('Biology')), isTrue);
    // Assert the toast before pumpAndSettle: the popup
    // auto-dismisses after ~5 s and settling would advance past it.
    expect(find.text('1 class synced from Google Calendar.'),
        findsOneWidget);
    await tester.pumpAndSettle();

    // After the sync, the placeholders are gone and only the real
    // event carries a "New" badge.
    expect(_tile('Discrete Mathematics'), findsNothing);
    expect(_tile('Life and Works of Rizal'), findsNothing);
    expect(_tile('NSTP 1'), findsNothing);
    expect(_tile('Vigan'), findsNothing);
    expect(_tile('Biology'), findsOneWidget);
    expect(_newBadge('Biology'), findsOneWidget);
    expect(chimes, 1);
  });

  testWidgets('a later sync skips events already synced', (tester) async {
    final already = _synced(id: 'gcal-bio-1', title: 'Biology');
    final sync = _fakeSync(events: [
      already,
      _synced(id: 'gcal-chem-2', title: 'Chemistry', weekday: 2),
    ]);
    var chimes = 0;
    await _pumpScreen(
      tester,
      onPlacementChime: () => chimes++,
      googleSync: sync,
      googleEvents: [already],
      realSyncDone: true,
    );

    await _openMenuAndTapGoogle(tester);
    expect(await _pumpUntil(tester, _tile('Chemistry')), isTrue);
    // Step past the placement gap, then assert before the 5 s
    // popup auto-dismisses.
    await tester.pump(const Duration(milliseconds: 600));
    expect(_tile('Biology'), findsOneWidget);
    expect(_tile('Chemistry'), findsOneWidget);
    expect(_newBadge('Chemistry'), findsOneWidget);
    // The already-synced event was not placed again: no second
    // chime, no second "New" badge on it.
    expect(_newBadge('Biology'), findsNothing);
    expect(chimes, 1);
    expect(
      find.text('1 class synced from Google Calendar. '
          '1 already on your timetable.'),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a synced event matching a class is skipped and reported',
      (tester) async {
    final sync = _fakeSync(events: [
      _synced(id: 'gcal-bio-1', title: 'Biology'),
    ]);
    var chimes = 0;
    await _pumpScreen(
      tester,
      onPlacementChime: () => chimes++,
      googleSync: sync,
      // A class with the same title already on the timetable.
      seed: _subject(name: 'Biology'),
    );

    await _openMenuAndTapGoogle(tester);
    // Pump until the toast appears (never pumpAndSettle first:
    // settling advances past the popup's ~5 s auto-dismiss).
    expect(
      await _pumpUntil(
        tester,
        find.text('No classes added — the synced event is already on '
            'your timetable.'),
      ),
      isTrue,
    );
    expect(_tile('Biology'), findsOneWidget);
    expect(_newBadge('Biology'), findsNothing);
    expect(chimes, 0);
  });

  testWidgets('a failed sync shows a plain retry message', (tester) async {
    final sync = _fakeSync(
      events: [],
      connectError: StateError('network down'),
    );
    var chimes = 0;
    await _pumpScreen(
      tester,
      onPlacementChime: () => chimes++,
      googleSync: sync,
    );

    await _openMenuAndTapGoogle(tester);
    // Pump until the retry toast appears (never pumpAndSettle
    // first: settling advances past the popup's auto-dismiss).
    expect(
      await _pumpUntil(
        tester,
        find.text('Couldn\'t sync Google Calendar. Check your connection '
            'and try again.'),
      ),
      isTrue,
    );
    expect(_setupDialog, findsNothing);
    expect(_emptyDialog, findsNothing);
    expect(chimes, 0);
  });

  testWidgets('the Google sync does not alter the other lists',
      (tester) async {
    final sync = _fakeSync(events: [
      _synced(id: 'gcal-bio-1', title: 'Biology'),
    ]);
    await _pumpScreen(tester, googleSync: sync);

    expect(find.text('Assignments & Exams'), findsOneWidget);
    await _openMenuAndTapGoogle(tester);
    expect(await _pumpUntil(tester, _tile('Biology')), isTrue);
    await tester.pumpAndSettle();

    expect(_tile('Biology'), findsOneWidget);
    expect(_tile('Coding'), findsOneWidget);
    expect(find.text('Assignments & Exams'), findsOneWidget);
  });
}
