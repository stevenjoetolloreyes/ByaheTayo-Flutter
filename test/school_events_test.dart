// Tests for the school-dependent event layer (UNP built-in calendar).
import 'package:estudyantego/features/school_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('schoolCalendarKey', () {
    test('UNP spellings map to unp', () {
      expect(schoolCalendarKey('UNP'), 'unp');
      expect(schoolCalendarKey('unp'), 'unp');
      expect(
        schoolCalendarKey('University of Northern Philippines'),
        'unp',
      );
      expect(
        schoolCalendarKey('University of Northern Philippines - Vigan'),
        'unp',
      );
      expect(schoolCalendarKey('  unp  '), 'unp');
    });

    test('other schools and empty values have no built-in calendar', () {
      expect(schoolCalendarKey(null), isNull);
      expect(schoolCalendarKey(''), isNull);
      expect(schoolCalendarKey('   '), isNull);
      expect(schoolCalendarKey('ISPSC'), isNull);
    });
  });

  group('UNP built-in events', () {
    test('intramurals week in October 2026', () {
      final events = schoolEventsInMonth('UNP', 2026, 10);
      expect(events.length, 1);
      expect(
        events.first.name,
        'Intramural Games and Culture and Arts Festival',
      );
      expect(events.first.kind, SchoolEventKind.event);
      expect(events.first.noClasses, isTrue);
      expect(events.first.start, DateTime(2026, 10, 19));
      expect(events.first.end, DateTime(2026, 10, 25));
    });

    test('no built-in events in November 2026', () {
      expect(schoolEventsInMonth('UNP', 2026, 11), isEmpty);
    });

    test('events cover every day of the range', () {
      expect(schoolEventsOnDay('UNP', DateTime(2026, 10, 19)).length, 1);
      expect(schoolEventsOnDay('UNP', DateTime(2026, 10, 22)).length, 1);
      expect(schoolEventsOnDay('UNP', DateTime(2026, 10, 25)).length, 1);
      expect(schoolEventsOnDay('UNP', DateTime(2026, 10, 26)), isEmpty);
    });

    test('unknown school has no events', () {
      expect(schoolEventsInMonth('ISPSC', 2026, 10), isEmpty);
      expect(schoolEventsOnDay(null, DateTime(2026, 10, 20)), isEmpty);
    });
  });

  group('formatEventRange', () {
    test('one day', () {
      final e = SchoolEvent(
        start: DateTime(2026, 11, 5),
        end: DateTime(2026, 11, 5),
        name: 'Midterm Exams',
        kind: SchoolEventKind.exam,
        noClasses: false,
      );
      expect(formatEventRange(e), 'Nov 5');
    });

    test('same-month range', () {
      final e = SchoolEvent(
        start: DateTime(2026, 10, 19),
        end: DateTime(2026, 10, 25),
        name: 'Intramurals',
        kind: SchoolEventKind.event,
        noClasses: true,
      );
      expect(formatEventRange(e), 'Oct 19–25');
    });

    test('cross-month range', () {
      final e = SchoolEvent(
        start: DateTime(2026, 10, 30),
        end: DateTime(2026, 11, 2),
        name: 'Festival',
        kind: SchoolEventKind.event,
        noClasses: true,
      );
      expect(formatEventRange(e), 'Oct 30 – Nov 2');
    });
  });
}
