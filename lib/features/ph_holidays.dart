// Philippine nationwide holidays + school-calendar helpers.
//
// Source: Proclamation No. 1006 (3 September 2025) declaring the regular
// holidays and special (non-working) days for 2026, plus the later
// proclamations fixing Eid'l Fitr (20 March 2026) and Eid'l Adha
// (27 May 2026) as regular holidays.
//
// Only NATIONWIDE regular holidays and special (non-working) days are
// listed. Deliberately NOT included:
// - 25 February (EDSA People Power Revolution Anniversary) — a special
//   WORKING day, so classes still happen.
// - 16-18 November (ASEAN Summit) — special (non-working) days for the
//   National Capital Region only, not nationwide.
// - Eid dates for other years — proclaimed per year, so years other
//   than 2026 return no holidays rather than guessed dates.

/// Holiday name for [date], or null when it is not a nationwide holiday.
String? philippineHolidayName(DateTime date) {
  if (date.year != 2026) return null;
  return _holidays2026['${date.month}-${date.day}'];
}

/// All holidays in a month, sorted by day, as (day, name) pairs.
List<({int day, String name})> philippineHolidaysInMonth(
  int year,
  int month,
) {
  if (year != 2026) return const [];
  final out = <({int day, String name})>[];
  for (final entry in _holidays2026.entries) {
    final dash = entry.key.indexOf('-');
    final m = int.parse(entry.key.substring(0, dash));
    final d = int.parse(entry.key.substring(dash + 1));
    if (m == month) out.add((day: d, name: entry.value));
  }
  out.sort((a, b) => a.day.compareTo(b.day));
  return out;
}

/// True when [date] falls on a Saturday or Sunday.
bool isWeekend(DateTime date) =>
    date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

/// School-calendar kind for a day: holidays are 'wala pasok' even on
/// weekdays, weekends are 'wala pasok', anything else is 'meron pasok'.
enum SchoolDayKind { schoolDay, weekend, holiday }

SchoolDayKind schoolDayKind(DateTime date) {
  if (philippineHolidayName(date) != null) return SchoolDayKind.holiday;
  if (isWeekend(date)) return SchoolDayKind.weekend;
  return SchoolDayKind.schoolDay;
}

/// Full English month name (1 = January).
String monthName(int month) => _monthNames[month - 1];

/// Short English month name (1 = Jan).
String monthShortName(int month) => _monthShortNames[month - 1];

const _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _monthShortNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _holidays2026 = <String, String>{
  '1-1': "New Year's Day",
  '2-17': 'Chinese New Year',
  '3-20': "Eid'l Fitr",
  '4-2': 'Maundy Thursday',
  '4-3': 'Good Friday',
  '4-4': 'Black Saturday',
  '5-1': 'Labor Day',
  '5-27': "Eid'l Adha",
  '6-12': 'Independence Day',
  '8-21': 'Ninoy Aquino Day',
  '8-31': 'National Heroes Day',
  '11-1': "All Saints' Day",
  '11-2': "All Souls' Day",
  '11-30': 'Bonifacio Day',
  '12-8': 'Feast of the Immaculate Conception of Mary',
  '12-24': 'Christmas Eve',
  '12-25': 'Christmas Day',
  '12-30': 'Rizal Day',
  '12-31': 'Last Day of the Year',
};
