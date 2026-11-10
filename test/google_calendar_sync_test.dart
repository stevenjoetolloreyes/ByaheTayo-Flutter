// Plain tests for Feature 4 of the Classes + menu build (Nov 10,
// 2026): the Google Calendar sync's pure parser and the sync
// service's status mapping.
//
// The parser turns a Calendar v3 events.list response into
// timetable events. Only events actually returned by the API are
// ever produced — the 4 placeholder sample events
// (Discrete Mathematics, Life and Works of Rizal, NSTP 1, Vigan)
// are never emitted, and no event is invented from an all-day,
// cancelled, or untitled entry.
//
// The real connect/fetch paths (Google Sign-In, HttpClient) cannot
// run in `flutter test`'s fake-async zone — the Files scan fakes
// its picker/extractor for the same reason — so the service is
// exercised here through its injectable connect/fetch seams, and
// the widget flow is covered in test/classes_google_schedule_test.dart.
import 'package:estudyantego/features/student/google_calendar_sync.dart';
import 'package:estudyantego/features/student/google_events.dart';
import 'package:flutter_test/flutter_test.dart';

/// One Calendar v3 event item, Manila time (+08:00).
Map<String, dynamic> _item({
  required String id,
  required String summary,
  required String start,
  String? end,
  String? location,
  String? status,
}) {
  final map = <String, dynamic>{
    'id': id,
    'summary': summary,
    'status': status ?? 'confirmed',
    'start': {'dateTime': start},
  };
  if (end != null) map['end'] = {'dateTime': end};
  if (location != null) map['location'] = location;
  return map;
}

void main() {
  group('parseCalendarEvents', () {
    test('a timed event maps to its Manila weekday and minutes', () {
      // Thu 2026-11-12, 3:00–4:30 PM Manila.
      final events = parseCalendarEvents({
        'items': [
          _item(
            id: 'abc123',
            summary: 'Discrete Mathematics',
            start: '2026-11-12T15:00:00+08:00',
            end: '2026-11-12T16:30:00+08:00',
            location: 'Rm 204',
          ),
        ],
      });
      expect(events, hasLength(1));
      final event = events.single;
      expect(event.id, 'gcal-abc123-4');
      expect(event.title, 'Discrete Mathematics');
      expect(event.weekday, DateTime.thursday);
      expect(event.startMin, 15 * 60);
      expect(event.endMin, 16 * 60 + 30);
      expect(event.place, 'Rm 204');
    });

    test('an offset other than +08:00 still reads as Manila wall clock',
        () {
      // 07:00 UTC == 15:00 Manila.
      final events = parseCalendarEvents({
        'items': [
          _item(
            id: 'utc1',
            summary: 'Physics',
            start: '2026-11-12T07:00:00Z',
            end: '2026-11-12T08:30:00Z',
          ),
        ],
      });
      expect(events.single.weekday, DateTime.thursday);
      expect(events.single.startMin, 15 * 60);
      expect(events.single.endMin, 16 * 60 + 30);
    });

    test('a recurring event expands to one entry per weekday occurrence',
        () {
      final events = parseCalendarEvents({
        'items': [
          _item(
            id: 'mwf1',
            summary: 'Biology',
            start: '2026-11-09T08:00:00+08:00',
            end: '2026-11-09T09:00:00+08:00',
          ),
          _item(
            id: 'mwf1',
            summary: 'Biology',
            start: '2026-11-11T08:00:00+08:00',
            end: '2026-11-11T09:00:00+08:00',
          ),
          _item(
            id: 'mwf1',
            summary: 'Biology',
            start: '2026-11-13T08:00:00+08:00',
            end: '2026-11-13T09:00:00+08:00',
          ),
          // Same occurrence again (a second page / overlap):
          // dedupes to one entry.
          _item(
            id: 'mwf1',
            summary: 'Biology',
            start: '2026-11-09T08:00:00+08:00',
            end: '2026-11-09T09:00:00+08:00',
          ),
        ],
      });
      expect(events, hasLength(3));
      expect(
        events.map((e) => e.weekday).toList(),
        [DateTime.monday, DateTime.wednesday, DateTime.friday],
      );
      expect(events.map((e) => e.id).toSet(), hasLength(3));
    });

    test('all-day, cancelled, and untitled events are skipped', () {
      final events = parseCalendarEvents({
        'items': [
          {
            'id': 'allday',
            'summary': 'Foundation Day',
            'status': 'confirmed',
            'start': {'date': '2026-11-12'},
            'end': {'date': '2026-11-13'},
          },
          _item(
            id: 'gone',
            summary: 'Old Class',
            start: '2026-11-12T09:00:00+08:00',
            end: '2026-11-12T10:00:00+08:00',
            status: 'cancelled',
          ),
          _item(
            id: 'notitle',
            summary: '   ',
            start: '2026-11-12T09:00:00+08:00',
            end: '2026-11-12T10:00:00+08:00',
          ),
        ],
      });
      expect(events, isEmpty);
    });

    test('an end at or before the start, or over 12 hours, is skipped',
        () {
      final events = parseCalendarEvents({
        'items': [
          _item(
            id: 'backwards',
            summary: 'Backwards',
            start: '2026-11-12T10:00:00+08:00',
            end: '2026-11-12T09:00:00+08:00',
          ),
          _item(
            id: 'marathon',
            summary: 'Marathon',
            start: '2026-11-12T00:00:00+08:00',
            end: '2026-11-12T23:00:00+08:00',
          ),
        ],
      });
      expect(events, isEmpty);
    });

    test('a missing end defaults to one hour', () {
      final events = parseCalendarEvents({
        'items': [
          _item(
            id: 'noend',
            summary: 'Vigan',
            start: '2026-11-15T16:47:00+08:00',
          ),
        ],
      });
      expect(events.single.startMin, 16 * 60 + 47);
      expect(events.single.endMin, 17 * 60 + 47);
    });

    test('the placeholder sample events are never emitted as results',
        () {
      // Even if the API somehow returned an event with a
      // placeholder-looking id, the parser's ids are namespaced
      // gcal-… and can never equal a sample id.
      final events = parseCalendarEvents({
        'items': [
          _item(
            id: 'g-nstp',
            summary: 'NSTP 1',
            start: '2026-11-14T08:00:00+08:00',
            end: '2026-11-14T11:00:00+08:00',
          ),
        ],
      });
      expect(events.single.id, isNot('g-nstp'));
      expect(events.single.id, startsWith('gcal-'));
      final sampleIds =
          sampleGoogleEvents().map((e) => e.id).toSet();
      expect(
        events.map((e) => e.id).toSet().intersection(sampleIds),
        isEmpty,
      );
      // And an empty response yields no events at all — nothing
      // is ever invented to fill the list.
      expect(parseCalendarEvents({'items': []}), isEmpty);
      expect(parseCalendarEvents({}), isEmpty);
    });
  });

  group('GoogleCalendarSync status mapping', () {
    const connection = GoogleCalendarConnection(
      accessToken: 'token',
      email: 'student@gmail.com',
    );
    final phases = <GoogleCalendarSyncPhase>[];

    test('connect then fetch reports both phases and the synced events',
        () async {
      final fetched = [
        GoogleCalendarEvent(
          id: 'gcal-x-1',
          title: 'Biology',
          weekday: 1,
          startMin: 8 * 60,
          endMin: 9 * 60,
          place: 'Room 5',
          color: 0xFF16A34A,
        ),
      ];
      final sync = GoogleCalendarSync(
        connect: () async => connection,
        fetchEvents: (_) async => fetched,
      );
      final result = await sync.sync(onPhase: phases.add);
      expect(result.status, GoogleCalendarSyncStatus.synced);
      expect(result.events, fetched);
      expect(result.accountEmail, 'student@gmail.com');
      expect(
        phases,
        [
          GoogleCalendarSyncPhase.connecting,
          GoogleCalendarSyncPhase.syncing,
        ],
      );
    });

    test('an empty fetch is noEvents, not a fake sync', () async {
      final sync = GoogleCalendarSync(
        connect: () async => connection,
        fetchEvents: (_) async => [],
      );
      final result = await sync.sync(onPhase: (_) {});
      expect(result.status, GoogleCalendarSyncStatus.noEvents);
      expect(result.events, isEmpty);
      expect(result.accountEmail, 'student@gmail.com');
    });

    test('a cancelled connect is cancelled', () async {
      final sync = GoogleCalendarSync(
        connect: () async => throw GoogleCalendarCancelled(),
      );
      final result = await sync.sync(onPhase: (_) {});
      expect(result.status, GoogleCalendarSyncStatus.cancelled);
    });

    test('a missing setup is setupMissing', () async {
      final sync = GoogleCalendarSync(
        connect: () async =>
            throw const GoogleCalendarSetupMissing('no OAuth client'),
      );
      final result = await sync.sync(onPhase: (_) {});
      expect(result.status, GoogleCalendarSyncStatus.setupMissing);
    });

    test('a rejected token on fetch is setupMissing', () async {
      final sync = GoogleCalendarSync(
        connect: () async => connection,
        fetchEvents: (_) async =>
            throw const GoogleCalendarSetupMissing('403'),
      );
      final result = await sync.sync(onPhase: (_) {});
      expect(result.status, GoogleCalendarSyncStatus.setupMissing);
    });

    test('any other failure is failed', () async {
      final sync = GoogleCalendarSync(
        connect: () async => throw StateError('boom'),
      );
      final result = await sync.sync(onPhase: (_) {});
      expect(result.status, GoogleCalendarSyncStatus.failed);
    });
  });
}
