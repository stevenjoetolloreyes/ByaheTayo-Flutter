// School-specific calendar events (examinations, foundation days,
// school events such as intramurals).
//
// The calendar depends on the student's school: different schools have
// different calendars. The school comes from the Account's Student
// Information field (SharedPreferences key 'byahetayo_profile_school',
// free text). Only VERIFIED dates are seeded here. Anything unverified
// is left out rather than guessed.
//
// Seeded (verified from unp.edu.ph, October 2026):
// - UNP Intramural Games and Culture and Arts Festival 2026:
//   19-25 October 2026, no classes.

import 'ph_holidays.dart';

/// What kind of school event this is (shown in the event list).
enum SchoolEventKind { exam, foundation, event }

class SchoolEvent {
  const SchoolEvent({
    required this.start,
    required this.end,
    required this.name,
    required this.kind,
    required this.noClasses,
  });

  /// First day (inclusive).
  final DateTime start;

  /// Last day (inclusive). Same as [start] for a one-day event.
  final DateTime end;

  final String name;
  final SchoolEventKind kind;

  /// True when classes are suspended for this event (wala pasok).
  /// Exams have classes (may pasok), so they use false.
  final bool noClasses;

  bool covers(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }
}

/// Normalized built-in calendar key for a school name, or null when the
/// school has no built-in calendar (its calendar then shows only
/// nationwide holidays plus user-added events).
String? schoolCalendarKey(String? school) {
  if (school == null) return null;
  final v = school.trim().toLowerCase();
  if (v.isEmpty) return null;
  if (v.contains('unp') || v.contains('northern philippines')) {
    return 'unp';
  }
  return null;
}

/// Built-in events overlapping a month, in start order.
List<SchoolEvent> schoolEventsInMonth(String? school, int year, int month) {
  final key = schoolCalendarKey(school);
  if (key == null) return const [];
  final monthStart = DateTime(year, month, 1);
  final monthEnd = DateTime(year, month + 1, 0);
  final events = _builtIn[key]!
      .where((e) => !e.end.isBefore(monthStart) && !e.start.isAfter(monthEnd))
      .toList();
  events.sort((a, b) => a.start.compareTo(b.start));
  return events;
}

/// Built-in events covering a single day.
List<SchoolEvent> schoolEventsOnDay(String? school, DateTime date) {
  final key = schoolCalendarKey(school);
  if (key == null) return const [];
  return _builtIn[key]!.where((e) => e.covers(date)).toList();
}

/// Display range: 'Nov 5' for one day, 'Oct 19–25' for a same-month
/// range, 'Oct 30 – Nov 2' across months.
String formatEventRange(SchoolEvent event) {
  final s = event.start;
  final e = event.end;
  if (s.year == e.year && s.month == e.month && s.day == e.day) {
    return '${monthShortName(s.month)} ${s.day}';
  }
  if (s.year == e.year && s.month == e.month) {
    return '${monthShortName(s.month)} ${s.day}–${e.day}';
  }
  return '${monthShortName(s.month)} ${s.day} – '
      '${monthShortName(e.month)} ${e.day}';
}

final _builtIn = <String, List<SchoolEvent>>{
  'unp': [
    SchoolEvent(
      start: DateTime(2026, 10, 19),
      end: DateTime(2026, 10, 25),
      name: 'Intramural Games and Culture and Arts Festival',
      kind: SchoolEventKind.event,
      noClasses: true,
    ),
  ],
};
