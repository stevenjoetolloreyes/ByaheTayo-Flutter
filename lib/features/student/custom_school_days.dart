// Custom marked days + overrides for the School Calendar.
//
// The calendar has three sources of truth, in priority order:
//   1. nationwide PH holidays (static table, 2026 only —
//      lib/features/ph_holidays.dart),
//   2. built-in school events for the student's school
//      (lib/features/school_events.dart, e.g. UNP intramurals),
//   3. days the student adds themselves.
//
// The Edit School Calendar page edits the EFFECTIVE marked days:
// a rename of a PH holiday or built-in event is stored as a name
// override, a removal as a hidden override, and anything added (or
// moved to another date) as a custom day. Nothing here edits the
// static tables — they stay the verified source, and the overrides
// are what the calendar actually renders. All persistence goes
// through SharedPreferences (StudentStorage list helpers), so the
// edits survive reinstalls exactly like the rest of the profile.
//
// The file also holds the Files-scan parser: it reads real extracted
// text (ML Kit OCR for photos, pdfrx text layer for PDFs — see
// NoteExtractService, same as the Allowance invoice scan) and pulls
// out dated school days. Nothing is invented: a line only becomes a
// day when it carries a recognizable date, and the name is the
// line's own text with the date stripped out.

import '../ph_holidays.dart';
import '../school_events.dart';
import 'student_data.dart';

/// What kind of marked day this is (the Add/Edit day sheet's
/// segment, and the badge on the calendar + Coming up list).
enum MarkedDayType {
  holiday,
  noClasses,
  event;

  String get label => switch (this) {
        MarkedDayType.holiday => 'Holiday',
        MarkedDayType.noClasses => 'No classes',
        MarkedDayType.event => 'Event',
      };

  /// True when classes are suspended on this day (wala pasok).
  bool get suspendsClasses =>
      this == MarkedDayType.holiday || this == MarkedDayType.noClasses;

  static MarkedDayType fromLabel(String value) => switch (value) {
        'holiday' => MarkedDayType.holiday,
        'noclass' => MarkedDayType.noClasses,
        'event' => MarkedDayType.event,
        _ => MarkedDayType.event,
      };

  String get storage => switch (this) {
        MarkedDayType.holiday => 'holiday',
        MarkedDayType.noClasses => 'noclass',
        MarkedDayType.event => 'event',
      };
}

/// Where an effective marked day came from.
enum MarkedDaySource { holiday, schoolEvent, custom }

/// One day on the calendar, as the Edit page and the hub card see
/// it: the effective value after overrides. [end] is the last day
/// of a multi-day built-in event; for one-day entries it equals
/// [date]. [systemKey] identifies the underlying system entry
/// ('hol:yyyy-MM-dd' for a PH holiday, 'evt:yyyy-MM-dd:name' for
/// a built-in event) so the draft can be written back as
/// overrides; custom days carry their own id instead.
class MarkedDayEntry {
  const MarkedDayEntry({
    required this.id,
    required this.date,
    required this.end,
    required this.name,
    required this.type,
    required this.source,
    this.systemKey,
  });

  final String id;
  final DateTime date;
  final DateTime end;
  final String name;
  final MarkedDayType type;
  final MarkedDaySource source;
  final String? systemKey;

  MarkedDayEntry copyWith({
    String? name,
    DateTime? date,
    DateTime? end,
    MarkedDayType? type,
  }) =>
      MarkedDayEntry(
        id: id,
        date: date ?? this.date,
        end: end ?? this.end,
        name: name ?? this.name,
        type: type ?? this.type,
        source: source,
        systemKey: systemKey,
      );

  bool get isSingleDay =>
      date.year == end.year && date.month == end.month && date.day == end.day;
}

/// A day the student added (or a system day moved to a new date).
class CustomSchoolDay {
  const CustomSchoolDay({
    required this.id,
    required this.name,
    required this.date,
    required this.type,
  });

  final String id;
  final String name;
  final DateTime date;
  final MarkedDayType type;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'date': dateKey(date),
        'type': type.storage,
      };

  static CustomSchoolDay? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final dateRaw = json['date'];
    if (id is! String || name is! String || dateRaw is! String) {
      return null;
    }
    final date = parseDateKey(dateRaw);
    if (date == null) return null;
    return CustomSchoolDay(
      id: id,
      name: name,
      date: date,
      type: MarkedDayType.fromLabel('${json['type'] ?? 'event'}'),
    );
  }
}

/// A rename or removal of one system day (a PH holiday or a
/// built-in school event), keyed by its calendar date.
class HolidayOverride {
  const HolidayOverride({
    required this.dateKey,
    this.name,
    this.hidden = false,
  });

  /// 'yyyy-MM-dd' of the system day this override applies to.
  final String dateKey;

  /// Renamed title, or null to keep the system name.
  final String? name;

  /// True when the day is removed from the calendar entirely.
  final bool hidden;

  Map<String, dynamic> toJson() => {
        'date': dateKey,
        if (name != null) 'name': name,
        if (hidden) 'hidden': true,
      };

  static HolidayOverride? fromJson(Map<String, dynamic> json) {
    final dateRaw = json['date'];
    if (dateRaw is! String || parseDateKey(dateRaw) == null) return null;
    return HolidayOverride(
      dateKey: dateRaw,
      name: json['name'] is String ? json['name'] as String : null,
      hidden: json['hidden'] == true,
    );
  }
}

/// Parses a 'yyyy-MM-dd' key, or null when it is not one.
/// ([dateKey] itself lives in student_data.dart — the same
/// zero-padded format the check-in streak math uses — and is
/// imported from there, not duplicated here.)
DateTime? parseDateKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

/// SharedPreferences persistence for the calendar edits. The hub
/// card builder added StudentStorage.loadRaw for the Google-events
/// seed; these two lists reuse the existing loadList/saveList.
abstract class SchoolCalendarStore {
  static const customDaysKey = 'byahetayo_custom_school_days';
  static const overridesKey = 'byahetayo_holiday_overrides';

  static Future<List<CustomSchoolDay>> loadCustomDays() async {
    final raw = await StudentStorage.loadList(customDaysKey);
    return raw
        .map(CustomSchoolDay.fromJson)
        .whereType<CustomSchoolDay>()
        .toList();
  }

  static Future<void> saveCustomDays(List<CustomSchoolDay> days) =>
      StudentStorage.saveList(
          customDaysKey, days.map((d) => d.toJson()).toList());

  static Future<List<HolidayOverride>> loadOverrides() async {
    final raw = await StudentStorage.loadList(overridesKey);
    return raw
        .map(HolidayOverride.fromJson)
        .whereType<HolidayOverride>()
        .toList();
  }

  static Future<void> saveOverrides(List<HolidayOverride> overrides) =>
      StudentStorage.saveList(
          overridesKey, overrides.map((o) => o.toJson()).toList());
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// All effective marked days: PH holidays (2026 table) + built-in
/// school events for [school] + custom days, with overrides
/// applied. Sorted by date. A custom day on the same date as a
/// system day wins (the UI's duplicate guard prevents that from
/// happening, so this is only a deterministic tiebreak).
List<MarkedDayEntry> effectiveMarkedDays({
  required String? school,
  required List<CustomSchoolDay> custom,
  required List<HolidayOverride> overrides,
}) {
  final byKey = <String, HolidayOverride>{
    for (final o in overrides) o.dateKey: o,
  };
  final entries = <MarkedDayEntry>[];

  // Nationwide holidays (the 2026 table only — other years have
  // none rather than guessed dates).
  for (var month = 1; month <= 12; month++) {
    for (final h in philippineHolidaysInMonth(2026, month)) {
      final date = DateTime(2026, month, h.day);
      final override = byKey[dateKey(date)];
      if (override?.hidden == true) continue;
      entries.add(MarkedDayEntry(
        id: 'sys:${dateKey(date)}',
        date: date,
        end: date,
        name: override?.name ?? h.name,
        type: MarkedDayType.holiday,
        source: MarkedDaySource.holiday,
        systemKey: 'hol:${dateKey(date)}',
      ));
    }
  }

  // Built-in school events for this school.
  for (final event in _builtInEventsFor(school)) {
    final key = 'evt:${dateKey(event.start)}:${event.name}';
    final override = byKey[dateKey(event.start)];
    if (override?.hidden == true) continue;
    entries.add(MarkedDayEntry(
      id: 'sys:$key',
      date: event.start,
      end: event.end,
      name: override?.name ?? event.name,
      type: event.noClasses ? MarkedDayType.noClasses : MarkedDayType.event,
      source: MarkedDaySource.schoolEvent,
      systemKey: key,
    ));
  }

  // Custom days.
  for (final day in custom) {
    entries.add(MarkedDayEntry(
      id: day.id,
      date: _day(day.date),
      end: _day(day.date),
      name: day.name,
      type: day.type,
      source: MarkedDaySource.custom,
    ));
  }

  entries.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    return a.source.index.compareTo(b.source.index);
  });
  return entries;
}

List<SchoolEvent> _builtInEventsFor(String? school) {
  final out = <SchoolEvent>[];
  for (var month = 1; month <= 12; month++) {
    out.addAll(schoolEventsInMonth(school, 2026, month));
  }
  return out;
}

/// The effective marked day covering [date], or null when it is a
/// plain school day. A custom day on the date wins; otherwise a PH
/// holiday (unless hidden by an override); otherwise a built-in
/// school event covering the date.
MarkedDayEntry? markedDayOn(
  DateTime date, {
  required String? school,
  required List<CustomSchoolDay> custom,
  required List<HolidayOverride> overrides,
}) {
  final d = _day(date);
  final key = dateKey(d);
  final byKey = <String, HolidayOverride>{
    for (final o in overrides) o.dateKey: o,
  };

  for (final day in custom) {
    if (dateKey(day.date) == key) {
      return MarkedDayEntry(
        id: day.id,
        date: _day(day.date),
        end: _day(day.date),
        name: day.name,
        type: day.type,
        source: MarkedDaySource.custom,
      );
    }
  }

  final override = byKey[key];
  if (override?.hidden != true) {
    final holiday = philippineHolidayName(d);
    if (holiday != null) {
      return MarkedDayEntry(
        id: 'sys:$key',
        date: d,
        end: d,
        name: override?.name ?? holiday,
        type: MarkedDayType.holiday,
        source: MarkedDaySource.holiday,
        systemKey: 'hol:$key',
      );
    }
  }

  for (final event in schoolEventsOnDay(school, d)) {
    final eventOverride = byKey[dateKey(event.start)];
    if (eventOverride?.hidden == true) continue;
    return MarkedDayEntry(
      id: 'sys:evt:${dateKey(event.start)}:${event.name}',
      date: event.start,
      end: event.end,
      name: eventOverride?.name ?? event.name,
      type: event.noClasses ? MarkedDayType.noClasses : MarkedDayType.event,
      source: MarkedDaySource.schoolEvent,
      systemKey: 'evt:${dateKey(event.start)}:${event.name}',
    );
  }
  return null;
}

/// The effective days, with multi-day built-in school events
/// collapsed into ONE row each (date = first day, [MarkedDayEntry.end]
/// = last day). The Edit page's Marked Days list and the hub's
/// Coming up list show one row per event — "Intramural Games…,
/// Oct 19–25" — not seven identical rows. PH holidays and custom
/// days are single-day by construction, so they pass through
/// unchanged. Grouping is by system key + name, so two different
/// events that happen to share a start date never merge.
List<MarkedDayEntry> groupMarkedDays(List<MarkedDayEntry> days) {
  final grouped = <MarkedDayEntry>[];
  final seen = <String, int>{};
  for (final row in days) {
    final key = row.systemKey;
    if (key == null || row.source == MarkedDaySource.custom) {
      grouped.add(row);
      continue;
    }
    final gkey = '$key|${row.name}';
    final idx = seen[gkey];
    if (idx == null) {
      seen[gkey] = grouped.length;
      grouped.add(row);
    } else {
      final prev = grouped[idx];
      grouped[idx] = prev.copyWith(
        end: row.date.isAfter(prev.end) ? row.date : prev.end,
      );
    }
  }
  grouped.sort((a, b) => a.date.compareTo(b.date));
  return grouped;
}

/// The marked day covering [date], if any. Range-aware: a
/// multi-day event covers every day from its first to its last, so
/// a new day picked inside the Intramurals week clashes with it.
/// Returns the covering row (for the duplicate-guard message) or
/// null when the date is free.
MarkedDayEntry? findDay(List<MarkedDayEntry> days, DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  for (final row in days) {
    if (!d.isBefore(row.date) && !d.isAfter(row.end)) return row;
  }
  return null;
}

/// The effective entries from today onward, next [limit] first.
/// What the hub card's "Coming up" list renders. A multi-day
/// event appears once, and still shows while it is running (its
/// end has not passed yet).
List<MarkedDayEntry> comingUpMarkedDays({
  required String? school,
  required List<CustomSchoolDay> custom,
  required List<HolidayOverride> overrides,
  DateTime? from,
  int limit = 5,
}) {
  final start = _day(from ?? DateTime.now());
  return groupMarkedDays(effectiveMarkedDays(
          school: school, custom: custom, overrides: overrides))
      .where((e) => !_day(e.end).isBefore(start))
      .take(limit)
      .toList();
}

/// Writes an edited draft list back as (custom days, overrides).
///
/// The draft is the edit page's working copy of
/// [groupMarkedDays] over [effectiveMarkedDays] — rows edited,
/// removed, or added there. Grouping matters: a multi-day school
/// event is ONE draft row, so the original it is compared against
/// is the grouped row too (the ungrouped list has one entry per
/// day sharing the same id, which would misread an untouched
/// event as moved).
///   - a custom row stays a custom day (new rows get their id
///     from the page; rows missing from the draft are deleted);
///   - a system row whose name only changed becomes a name
///     override; a system row whose date or type changed becomes a
///     hidden override plus a custom day at the new values (a
///     move); a system row missing from the draft becomes a hidden
///     override; an untouched system row leaves no trace.
/// Overrides for system days the draft never saw are preserved.
({List<CustomSchoolDay> custom, List<HolidayOverride> overrides})
    persistDraft({
  required List<MarkedDayEntry> draft,
  required String? school,
  required List<CustomSchoolDay> existingCustom,
  required List<HolidayOverride> existingOverrides,
}) {
  final original = groupMarkedDays(effectiveMarkedDays(
    school: school,
    custom: existingCustom,
    overrides: existingOverrides,
  ));
  final originalById = <String, MarkedDayEntry>{
    for (final e in original) e.id: e,
  };
  final draftById = <String, MarkedDayEntry>{
    for (final e in draft) e.id: e,
  };

  final custom = <CustomSchoolDay>[];
  final overrides = <HolidayOverride>[];
  final keptOverrideKeys = <String>{};

  for (final row in draft) {
    if (row.source == MarkedDaySource.custom) {
      custom.add(CustomSchoolDay(
        id: row.id,
        name: row.name,
        date: row.date,
        type: row.type,
      ));
      continue;
    }
    final orig = originalById[row.id];
    if (orig == null) continue;
    final origKey = dateKey(orig.date);
    final moved = dateKey(row.date) != origKey || row.type != orig.type;
    if (moved) {
      // A move: hide the original system day, add the edited
      // values as a custom day at the new date.
      overrides.add(HolidayOverride(dateKey: origKey, hidden: true));
      keptOverrideKeys.add(origKey);
      custom.add(CustomSchoolDay(
        id: row.id,
        name: row.name,
        date: row.date,
        type: row.type,
      ));
    } else if (row.name != orig.name) {
      overrides.add(HolidayOverride(dateKey: origKey, name: row.name));
      keptOverrideKeys.add(origKey);
    }
  }

  // System days the draft dropped are removed (hidden).
  for (final orig in original) {
    if (orig.source == MarkedDaySource.custom) continue;
    if (draftById.containsKey(orig.id)) continue;
    final key = dateKey(orig.date);
    overrides.add(HolidayOverride(dateKey: key, hidden: true));
    keptOverrideKeys.add(key);
  }

  // Keep overrides the draft never saw (e.g. a hidden day from a
  // previous edit that this draft's list did not include).
  for (final o in existingOverrides) {
    if (!keptOverrideKeys.contains(o.dateKey)) overrides.add(o);
  }

  custom.sort((a, b) => a.date.compareTo(b.date));
  overrides.sort((a, b) => a.dateKey.compareTo(b.dateKey));
  return (custom: custom, overrides: overrides);
}

// ------------------------------------------------------------ scan
// parsing (pure Dart, no plugins, so it is unit-testable — same
// pattern as the Allowance invoice parser).

/// One candidate day pulled from a scanned file. [type] is
/// 'event' unless the line clearly reads as a holiday or a
/// no-classes day.
class ScannedSchoolDay {
  const ScannedSchoolDay({
    required this.name,
    required this.date,
    required this.type,
  });

  final String name;
  final DateTime date;
  final MarkedDayType type;
}

const _scanMonthNames = <String, int>{
  'jan': 1,
  'january': 1,
  'feb': 2,
  'february': 2,
  'mar': 3,
  'march': 3,
  'apr': 4,
  'april': 4,
  'may': 5,
  'jun': 6,
  'june': 6,
  'jul': 7,
  'july': 7,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'oct': 10,
  'october': 10,
  'nov': 11,
  'november': 11,
  'dec': 12,
  'december': 12,
};

final _namedDateRe = RegExp(
    r'\b([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s*[-–—]\s*(\d{1,2})(?:st|nd|rd|th)?)?(?:,?\s+(\d{4}))?\b');
final _dayFirstDateRe = RegExp(
    r'\b(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,9})\.?(?:,?\s+(\d{4}))?\b');
final _isoDateRe = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b');
final _numericDateRe = RegExp(r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b');

/// The first date on [line], or null. A bare "Dec 19" (no year)
/// defaults to [fallbackYear] (the current year when omitted).
DateTime? _dateOnLine(String line, int fallbackYear) {
  final iso = _isoDateRe.firstMatch(line);
  if (iso != null) {
    final y = int.tryParse(iso.group(1)!);
    final m = int.tryParse(iso.group(2)!);
    final d = int.tryParse(iso.group(3)!);
    if (y != null && m != null && d != null && m >= 1 && m <= 12) {
      return DateTime(y, m, d);
    }
  }
  final named = _namedDateRe.firstMatch(line);
  if (named != null) {
    final month = _scanMonthNames[named.group(1)!.toLowerCase()];
    final day = int.tryParse(named.group(2)!);
    final year = named.group(4) != null
        ? int.tryParse(named.group(4)!)
        : fallbackYear;
    if (month != null && day != null && year != null) {
      return DateTime(year, month, day);
    }
  }
  final dayFirst = _dayFirstDateRe.firstMatch(line);
  if (dayFirst != null) {
    final month = _scanMonthNames[dayFirst.group(2)!.toLowerCase()];
    final day = int.tryParse(dayFirst.group(1)!);
    final year = dayFirst.group(3) != null
        ? int.tryParse(dayFirst.group(3)!)
        : fallbackYear;
    if (month != null && day != null && year != null) {
      return DateTime(year, month, day);
    }
  }
  final numeric = _numericDateRe.firstMatch(line);
  if (numeric != null) {
    var month = int.tryParse(numeric.group(1)!);
    var day = int.tryParse(numeric.group(2)!);
    var year = int.tryParse(numeric.group(3)!);
    if (month != null && day != null && year != null) {
      if (year < 100) year += 2000;
      // Day-first ("30/12/2026"): the first number cannot be a
      // month, so the two swap. Month-first stays as-is.
      if (month > 12 && day <= 12) {
        final tmp = month;
        month = day;
        day = tmp;
      }
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime(year, month, day);
      }
    }
  }
  return null;
}

/// Strips every date-like fragment (including ranges such as
/// "Dec 19-20") from [line] so only the event name is left.
String _stripDates(String line) {
  var out = line;
  out = out.replaceAll(_isoDateRe, ' ');
  out = out.replaceAll(_numericDateRe, ' ');
  out = out.replaceAll(_namedDateRe, ' ');
  out = out.replaceAll(_dayFirstDateRe, ' ');
  return out;
}

bool _isHeaderLine(String lower) =>
    lower.contains('memorandum') ||
    lower.contains('announcement') ||
    lower.startsWith('to:') ||
    lower.startsWith('from:') ||
    lower.startsWith('subject:') ||
    lower.startsWith('re:') ||
    lower.contains('republic of the philippines') ||
    lower.contains('office of the') ||
    lower.contains('university of northern philippines') ||
    lower.contains('noted by') ||
    lower.contains('approved by') ||
    lower == 'memo' ||
    lower.startsWith('cc:');

/// The type is guessed from the line's own words. No-classes
/// keywords win over holiday keywords on purpose: "Christmas
/// Break" is a break (wala pasok), while "Christmas Day" is a
/// holiday — checking 'break' first keeps the two apart.
MarkedDayType _guessDayType(String lower) {
  if (lower.contains('no class') ||
      lower.contains('suspended') ||
      lower.contains('suspension') ||
      lower.contains('break') ||
      lower.contains('vacation') ||
      lower.contains('no school') ||
      lower.contains('wala pasok') ||
      lower.contains('class suspension') ||
      lower.contains('closed')) {
    return MarkedDayType.noClasses;
  }
  if (lower.contains('holiday') ||
      lower.contains('christmas') ||
      lower.contains('new year') ||
      lower.contains('independence') ||
      lower.contains('bonifacio') ||
      lower.contains('rizal') ||
      lower.contains('all saints') ||
      lower.contains('all souls') ||
      lower.contains('immaculate') ||
      lower.contains('conception') ||
      lower.contains('ninoy') ||
      lower.contains('heroes') ||
      lower.contains('labor day') ||
      lower.contains("eid'l") ||
      lower.contains('maundy') ||
      lower.contains('good friday') ||
      lower.contains('black saturday') ||
      lower.contains('chinese new year')) {
    return MarkedDayType.holiday;
  }
  return MarkedDayType.event;
}

/// Pulls dated school days out of OCR / PDF text: one candidate
/// per line that carries a date. The name is the line's own text
/// with the date stripped; lines that are headers, addresses, or
/// too short/long to be a name are skipped, and a date that
/// already appeared keeps only its first line. Nothing is
/// invented: a line with no recognizable date yields nothing.
List<ScannedSchoolDay> parseSchoolDaysText(String text) {
  final fallbackYear = DateTime.now().year;
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final found = <ScannedSchoolDay>[];
  final seenDates = <String>{};
  for (final line in lines) {
    final date = _dateOnLine(line, fallbackYear);
    if (date == null) continue;
    final key = dateKey(date);
    if (seenDates.contains(key)) continue;
    final lower = line.toLowerCase();
    if (_isHeaderLine(lower)) continue;
    var name = _stripDates(line)
        .replaceAll(RegExp(r'^[\s\-–—•·:]+'), '')
        .replaceAll(RegExp(r'[\s\-–—•·:]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (name.length < 2 || name.length > 80) continue;
    if (_isHeaderLine(name.toLowerCase())) continue;
    seenDates.add(key);
    found.add(ScannedSchoolDay(
      name: name,
      date: date,
      type: _guessDayType(lower),
    ));
  }
  found.sort((a, b) => a.date.compareTo(b.date));
  return found;
}
