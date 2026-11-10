// Schedule scan (Feature 3 of the Classes + menu build, Nov 10,
// 2026): read a picked file's real text and pull class schedule
// entries out of it.
//
// Extraction reuses the app's existing path — [NoteExtractService]:
// on-device ML Kit OCR for photos, pdfrx text layer for PDFs,
// direct read for plain text (.txt / .md / .csv). No new
// dependency, no new ML Kit piece.
//
// Honesty rule: only classes actually found in the file are ever
// added. A line counts as a class only when it carries BOTH a
// weekday and a time range; anything else is skipped, never
// guessed. When nothing parses, the result is empty and the UI
// says so plainly — no sample classes are ever shown as results.
//
// Supported line formats (one class per line):
//   Discrete Math | Mon, Wed, Fri | 8:00 AM - 9:30 AM | Room 101 | Prof. Santos
//   CS101 - Discrete Math, Mon Wed Fri, 8:00-9:30am, Room 101
//   Discrete Math Mon Wed Fri 8:00 AM - 9:30 AM Room 101
// Days: Mon..Sun / Monday..Sunday, compact MWF / TTh / TR, ranges
// Mon-Fri. Times: 8:00 AM - 9:30 AM, 8-9:30am, 13:00-14:30. A bare
// hour with no AM/PM reads 7-11 as morning, 12 as noon, 1-6 as
// afternoon (the usual school-schedule reading).
//
// Table-style OCR (added Nov 10, 2026; day-after-time fixed
// Nov 11, 2026): a Certificate of Registration is a table, so
// ML Kit reads it fragmented — the subject code/name, the day
// code, the time range, the room, and the instructor may each
// land on their own line, or a subject may carry two schedule
// lines. [parseScheduleText] therefore runs a second pass that
// groups nearby fragments into class entries: a schedule
// fragment (a time range, with its day code on the same line
// before the time, right after the time — "7:30-9:30 am M
// CC105", the real certificate's format — on the line just
// above it, or on the line just below it) attaches to the
// nearest preceding subject (code + name), and room /
// instructor are read from the fragment's own line or the next
// line(s).
// Day codes in schedule fragments: M = Monday, T = Tuesday,
// W = Wednesday, Th = Thursday, Sat = Saturday, TTh = Tue + Thu
// (plus MWF / MW / TR and the named days above). A bare
// single-letter day (M, T, W, ...) counts ONLY in schedule
// context — next to a time range, or on a day-only line between
// a subject and its time line — never in free prose or a header.
// A fragment with no subject, or with days but no time (or vice
// versa), is skipped, never guessed.
//
// What it cannot do (yet): a scanned / image-only PDF has no text
// layer, so it reads as empty — a photo of the page works instead
// (on-device OCR). A table whose days live only in a header row
// and whose times live only in a column, with nothing tying a
// day/time to a subject row, does not parse.
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'note_extract_service.dart';
import 'student_data.dart';

/// One class entry pulled out of a scanned file. Maps straight
/// onto [Subject] via [toSubject]; [days] are 1 = Monday ..
/// 7 = Sunday, like [Subject.days].
class ScannedClass {
  const ScannedClass({
    required this.name,
    this.code = '',
    this.teacher = '',
    this.room = '',
    required this.days,
    required this.startMin,
    required this.endMin,
  });

  final String name;
  final String code;
  final String teacher;
  final String room;
  final List<int> days;
  final int startMin;
  final int endMin;

  Subject toSubject({required String id, required int color}) => Subject(
        id: id,
        name: name,
        code: code,
        teacher: teacher,
        room: room,
        days: days,
        startMin: startMin,
        endMin: endMin,
        color: color,
      );
}

/// What [parseScheduleText] found in one file's text.
class ScheduleParseResult {
  const ScheduleParseResult({required this.classes});

  /// Classes actually extracted (empty when nothing parseable).
  final List<ScannedClass> classes;
}

const _dayNames = <String, int>{
  'monday': 1,
  'mon': 1,
  'tuesday': 2,
  'tue': 2,
  'tues': 2,
  'wednesday': 3,
  'wed': 3,
  'thursday': 4,
  'thu': 4,
  'thur': 4,
  'thurs': 4,
  'friday': 5,
  'fri': 5,
  'saturday': 6,
  'sat': 6,
  'sunday': 7,
  'sun': 7,
};

const _dayAlternation =
    r'Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Tues|Wed|Thu|Thur|Thurs|Fri|Sat|Sun';

/// Compact academic day tokens: M = Monday, T = Tuesday,
/// W = Wednesday, R = Thursday, F = Friday, S = Saturday,
/// U = Sunday. "TR" = Tue + Thu.
const _compactDayMap = <String, int>{
  'M': 1,
  'T': 2,
  'W': 3,
  'R': 4,
  'F': 5,
  'S': 6,
  'U': 7,
};

final _dayWordRe =
    RegExp('\\b($_dayAlternation)\\b\\.?', caseSensitive: false);
final _dayRangeRe = RegExp(
    '\\b($_dayAlternation)\\b\\.?\\s*[-–—]\\s*\\b($_dayAlternation)\\b\\.?',
    caseSensitive: false);
final _compactDaysRe = RegExp(r'\b([MTWRFSU]{2,5})\b');
final _tthRe = RegExp(r'\bTTh\b');

/// Bare day codes, schedule context ONLY (see [_parseScheduleDays]):
/// a lone "Th" is Thursday, and a lone letter is its compact day
/// (M = Monday, T = Tuesday, W = Wednesday, R = Thursday,
/// F = Friday, S = Saturday, U = Sunday). These are never read
/// through [_parseDays] — that would misread initials in a
/// teacher name ("W.E. Que") as Wednesday.
final _bareThRe = RegExp(r'\bTh\b');
final _bareSingleDayRe = RegExp(r'\b[MTWRFSU]\b');

/// A person's name as printed on a certificate: initials plus a
/// surname ("A. Supnet", "W.E. Que", "L. Baja") or a titled name
/// ("Prof. Santos", "Dr. Cruz").
final _personNameRe = RegExp(
  r'\b(?:[A-Z](?:\.[A-Z])+\.?|[A-Z]\.)\s+[A-Z][a-z]+\b'
  r'|\b(?:Prof\.?|Dr\.?|Mr\.?|Ms\.?|Mrs\.?)\s+[A-Z][A-Za-z]+'
  r'(?:\s+[A-Z][A-Za-z]+)?',
);

/// A bare room code as printed on a certificate ("CC105",
/// "CC 104"). Only ever read from text after a time range (or a
/// room/teacher lookahead line), never from a subject line.
final _roomCodeRe = RegExp(r'\b[A-Z]{1,4}\s?\d{2,4}[A-Z]?\b');

/// Weekdays in a schedule fragment: everything [_parseDays]
/// finds, plus bare "Th" and bare single-letter codes. Callers
/// must only pass text that is in schedule context — the part of
/// a line before its time range, or a day-only line sitting
/// between a subject and its time line. Never call this on free
/// prose, a header, or text after a time range (an instructor
/// like "W.E. Que" would otherwise donate a Wednesday).
Set<int> _parseScheduleDays(String segment) {
  final days = _parseDays(segment);
  if (_bareThRe.hasMatch(segment)) days.add(4);
  for (final m in _bareSingleDayRe.allMatches(segment)) {
    final day = _compactDayMap[m.group(0)!];
    if (day != null) days.add(day);
  }
  return days;
}

/// Leading day tokens at the start of [text], and the text after
/// them. Only ever called on text in schedule position — right
/// after a time range, or a line following a time line — never on
/// free prose, headers, or subject names. Tokens are read left to
/// right and stop at the first token that is not a day token, so
/// "M CC105 A. Supnet" reads Monday and stops at the room code,
/// and "W.E. Que" can never donate a Wednesday: "W.E." is one
/// token with periods, not a bare "W", and it sits after the room
/// code anyway. Per token, in order: (a) a named day (Mon / Tue /
/// Monday ..., case-insensitive, optional trailing period);
/// (b) "TTh" (Tue + Thu); (c) "Th" (Thursday); (d) a compact
/// token of 2-5 letters all in [_compactDayMap] (MWF, MW, TR);
/// (e) a bare single letter in [_compactDayMap] (M, T, W, R, F,
/// S, U) — exactly the letter, no trailing period, so an initial
/// like "M." is never a day. "T Th" as two tokens reads Tue +
/// Thu, and extra spaces are harmless (whitespace tokenizing).
({Set<int> days, String rest}) _leadingScheduleDays(String text) {
  final days = <int>{};
  var consumedEnd = 0;
  for (final m in RegExp(r'\S+').allMatches(text)) {
    final token = m.group(0)!;
    final lower = token.toLowerCase();
    final unperioded =
        lower.endsWith('.') ? lower.substring(0, lower.length - 1) : lower;
    final named = _dayNames[unperioded];
    if (named != null) {
      days.add(named);
    } else if (lower == 'tth') {
      days.add(2);
      days.add(4);
    } else if (lower == 'th') {
      days.add(4);
    } else {
      final upper = token.toUpperCase();
      if (upper.length >= 2 &&
          upper.length <= 5 &&
          upper.split('').every(_compactDayMap.containsKey)) {
        for (var i = 0; i < upper.length; i++) {
          days.add(_compactDayMap[upper[i]]!);
        }
      } else if (token.length == 1 &&
          _compactDayMap.containsKey(upper)) {
        days.add(_compactDayMap[upper]!);
      } else {
        break;
      }
    }
    consumedEnd = m.end;
  }
  return (days: days, rest: text.substring(consumedEnd).trim());
}

/// Earliest index in [text] where a schedule day token (named,
/// compact, TTh, bare "Th", or a bare single-letter code) or the
/// time range starts, or null when neither appears. Like
/// [_firstDayOrTimeIndex] but schedule-aware, so a subject name
/// can be cut off before a bare "M" day code.
int? _firstScheduleDayOrTimeIndex(String text) {
  var earliest = _timeRangeRe.firstMatch(text)?.start;
  for (final re in [
    _dayRangeRe,
    _dayWordRe,
    _compactDaysRe,
    _tthRe,
    _bareThRe,
    _bareSingleDayRe,
  ]) {
    final at = re.firstMatch(text)?.start;
    if (at != null && (earliest == null || at < earliest)) {
      earliest = at;
    }
  }
  return earliest;
}

/// True when [line] holds nothing but day tokens and separators
/// ("M", "TTh", "MWF", "Mon Wed", "Sat"). Such a line is a
/// schedule fragment's day half, never a subject or prose.
bool _isDayOnlyLine(String line) {
  if (_parseScheduleDays(line).isEmpty) return false;
  var rest = line;
  for (final re in [
    _dayRangeRe,
    _dayWordRe,
    _tthRe,
    _compactDaysRe,
    _bareThRe,
    _bareSingleDayRe,
  ]) {
    rest = rest.replaceAll(re, '');
  }
  rest = rest.replaceAll(RegExp(r'[\s,;/|.\-]+'), '');
  return rest.isEmpty;
}

/// True when [line] is a subject code followed by a name
/// ("CT102 Computer Programming 1"). A bare code alone is not
/// one — that may be a room code on the line after a time range.
bool _isSubjectWithNameLine(String line) {
  final m =
      RegExp('^($_codeRe)\\s*[-–—:.]?\\s+(.+)\$').firstMatch(line);
  if (m == null) return false;
  final rest = m.group(2)!.trim();
  if (rest.isEmpty || _isDayOnlyLine(rest)) return false;
  if (_timeRangeRe.hasMatch(rest)) return false;
  return true;
}

/// True when [line] could continue a subject name split across
/// lines ("Computer Systems" after "CSS101 Installing and
/// Configuring", "Computer Programming 1" after "CT102"): mostly
/// words, not a bare code ("CC105"), a room label, or a date /
/// year line. A digit inside a name ("Programming 1") is fine.
bool _looksLikeNameContinuation(String line) {
  if (line.length > 80) return false;
  if (!RegExp(r'[A-Za-z]').hasMatch(line)) return false;
  if (RegExp(r'^$_codeRe\$').hasMatch(line)) return false;
  if (RegExp(r'^(room|rm\.?|lab|bldg\.?|building|hall|blk\.?|wing)\b',
          caseSensitive: false)
      .hasMatch(line)) {
    return false;
  }
  if (RegExp(r'\b(19|20)\d\d\b').hasMatch(line)) return false;
  if (line.contains('|') || line.contains(';')) return false;
  if (_personNameRe.hasMatch(line)) return false;
  if (_isDayOnlyLine(line)) return false;
  return true;
}

/// Pull room / teacher out of [raw] — text after a time range, or
/// a room/teacher lookahead line. Labelled chunks first (via
/// [_splitRoomTeacher]), then a bare room code ("CC105") and an
/// initials-style teacher name ("A. Supnet", "W.E. Que"). A bare
/// room code wins over [_splitRoomTeacher]'s unlabelled-digit
/// chunk, so "CC105 A. Supnet" reads as room CC105 + teacher
/// A. Supnet, not room "CC105 A. Supnet".
({String room, String teacher}) _roomTeacherFromText(String raw) {
  final labelled = _splitRoomTeacher(raw);
  var teacher = labelled.teacher;
  if (teacher.isEmpty) {
    final m = _personNameRe.firstMatch(raw);
    if (m != null) teacher = m.group(0)!;
  }
  var room = '';
  final hasLabel = RegExp(
    r'\b(room|rm\.?|bldg\.?|building|hall|lab|blk\.?|wing)\b',
    caseSensitive: false,
  ).hasMatch(raw);
  if (hasLabel && labelled.room.isNotEmpty) {
    room = labelled.room;
  } else {
    final code = _roomCodeRe.firstMatch(raw);
    if (code != null) {
      room = code.group(0)!;
    } else {
      room = labelled.room;
    }
  }
  if (teacher.isNotEmpty && room.contains(teacher)) {
    room = room
        .replaceAll(teacher, '')
        .replaceAll(RegExp(r'[,;|]+\s*$'), '')
        .trim();
  }
  return (room: room, teacher: teacher);
}

/// True when [line] is a room code followed by a teacher name
/// ("CC203 L. Baja"). It looks like a subject line (code + name)
/// but, right after a time range, it is room + teacher — the
/// lookahead must consume it, not stop at it.
bool _isRoomTeacherLine(String line) {
  final m = RegExp('^($_codeRe)\\s+(.+)\$').firstMatch(line);
  if (m == null) return false;
  final rest = m.group(2)!.trim();
  final pm = _personNameRe.firstMatch(rest);
  return pm != null && pm.start == 0 && pm.end == rest.length;
}

/// Room / teacher from up to two lines after [fromIndex] that
/// look like room / teacher. Stops at a time line, a day-only
/// line, or a subject line (a bare code after a time range is a
/// room code — "CC105" — but once the room is set, a bare code
/// is the next subject, so stop). Consumed lines are added to
/// [consumed] so the main walk skips them. [rt] is the room /
/// teacher already read from the time line itself; the lookahead
/// only fills fields still empty.
({String room, String teacher}) _roomTeacherLookahead(
  List<String> lines,
  int fromIndex,
  Set<int> consumed,
  ({String room, String teacher}) rt,
) {
  var looked = 0;
  for (var j = fromIndex; j < lines.length && looked < 2; j++) {
    final next = lines[j].trim();
    if (next.isEmpty) continue;
    if (_timeRangeRe.hasMatch(next)) break;
    if (_isDayOnlyLine(next)) break;
    if (_isSubjectWithNameLine(next) && !_isRoomTeacherLine(next)) {
      break;
    }
    if (RegExp('^$_codeRe\$').hasMatch(next)) {
      // A bare code after a time range is a room code
      // ("CC105"); once the room is set, a bare code is the
      // next subject, so stop.
      if (rt.room.isEmpty) {
        rt = (room: next, teacher: rt.teacher);
        consumed.add(j);
        looked++;
        continue;
      }
      break;
    }
    final nextRt = _roomTeacherFromText(next);
    if (nextRt.room.isEmpty && nextRt.teacher.isEmpty) break;
    rt = (
      room: rt.room.isEmpty ? nextRt.room : rt.room,
      teacher: rt.teacher.isEmpty ? nextRt.teacher : rt.teacher,
    );
    consumed.add(j);
    looked++;
    if (rt.room.isNotEmpty && rt.teacher.isNotEmpty) break;
  }
  return rt;
}

/// "8:00 AM - 9:30 AM", "8-9:30am", "13:00-14:30", "8:00 to 9:30".
/// Groups: 1 = start hour, 2 = start minutes, 3 = start AM/PM,
/// 4 = end hour, 5 = end minutes, 6 = end AM/PM.
final _timeRangeRe = RegExp(
  r'(\d{1,2})(?::(\d{2}))?\s*([AaPp][Mm])?\s*(?:[-–—~]|\bto\b)\s*(\d{1,2})(?::(\d{2}))?\s*([AaPp][Mm])?',
);

/// "CS101", "MATH 101", "CC 105" — a subject code, never a bare
/// word (so "ENGLISH 101" stays a name).
final _codeRe = r'[A-Z]{2,5}\s?\d{2,4}[A-Z]?';

/// Weekdays mentioned in [segment]: named days, "Mon-Fri" ranges,
/// compact "MWF" / "TR" tokens, and "TTh".
Set<int> _parseDays(String segment) {
  final days = <int>{};
  for (final m in _dayRangeRe.allMatches(segment)) {
    final start = _dayNames[m.group(1)!.toLowerCase()];
    final end = _dayNames[m.group(2)!.toLowerCase()];
    if (start != null && end != null && end >= start) {
      for (var d = start; d <= end; d++) {
        days.add(d);
      }
    }
  }
  for (final m in _dayWordRe.allMatches(segment)) {
    final day =
        _dayNames[m.group(0)!.toLowerCase().replaceAll('.', '')];
    if (day != null) days.add(day);
  }
  if (_tthRe.hasMatch(segment)) {
    days.add(2);
    days.add(4);
  }
  for (final m in _compactDaysRe.allMatches(segment)) {
    final token = m.group(0)!;
    if (token.split('').every(_compactDayMap.containsKey)) {
      for (var i = 0; i < token.length; i++) {
        days.add(_compactDayMap[token[i]]!);
      }
    }
  }
  return days;
}

/// One clock time to minutes since midnight. With an AM/PM marker
/// the hour must be 1-12; without one, 13-23 read as 24-hour,
/// 12 as noon, 7-11 as morning, 1-6 as afternoon. Null when the
/// hour/minute cannot be a real time.
int? _timeToMinutes(int hour, int? minute, String? marker) {
  final min = minute ?? 0;
  if (min > 59) return null;
  if (marker != null) {
    if (hour < 1 || hour > 12) return null;
    var h = hour % 12;
    if (marker.toLowerCase() == 'pm') h += 12;
    return h * 60 + min;
  }
  if (hour > 23) return null;
  if (hour == 0) return min;
  if (hour >= 12) return hour * 60 + min;
  if (hour >= 7) return hour * 60 + min;
  return (hour + 12) * 60 + min;
}

/// The first time range in [segment], or null when there is none
/// or it is not a real range (end at/before start, over 12 hours).
/// A missing AM/PM on one side inherits the other side's marker.
({int startMin, int endMin})? _parseTimeRange(String segment) {
  final m = _timeRangeRe.firstMatch(segment);
  if (m == null) return null;
  final startMarker = m.group(3) ?? m.group(6);
  final endMarker = m.group(6) ?? m.group(3);
  final start = _timeToMinutes(
      int.parse(m.group(1)!), int.tryParse(m.group(2) ?? ''), startMarker);
  final end = _timeToMinutes(
      int.parse(m.group(4)!), int.tryParse(m.group(5) ?? ''), endMarker);
  if (start == null || end == null) return null;
  if (end <= start) return null;
  if (end - start > 12 * 60) return null;
  return (startMin: start, endMin: end);
}

/// Split a subject name from its code: "CS101 - Discrete Math",
/// "Discrete Math (MATH 101)", "Discrete Math - CS101". When no
/// code pattern matches, the whole text is the name.
({String name, String code}) _splitNameCode(String raw) {
  final name = raw.trim();
  final paren =
      RegExp('^(.+?)\\s*\\(($_codeRe)\\)\\s*\$').firstMatch(name);
  if (paren != null) {
    return (name: paren.group(1)!.trim(), code: paren.group(2)!);
  }
  final leading =
      RegExp('^($_codeRe)\\s*[-–—:.]?\\s+(.+)\$').firstMatch(name);
  if (leading != null) {
    return (name: leading.group(2)!.trim(), code: leading.group(1)!);
  }
  final trailing =
      RegExp('^(.+?)\\s*[-–—:]\\s*($_codeRe)\\s*\$').firstMatch(name);
  if (trailing != null) {
    return (name: trailing.group(1)!.trim(), code: trailing.group(2)!);
  }
  return (name: name, code: '');
}

/// Pull room / teacher out of trailing text after the time range.
/// Only labelled chunks count ("Room 101", "Prof. Santos"); an
/// unlabelled chunk with a number reads as a room, anything else
/// is dropped rather than guessed into a field.
({String room, String teacher}) _splitRoomTeacher(String raw) {
  var room = '';
  var teacher = '';
  final chunks = raw
      .split(RegExp(r'\s*[|,;·]\s*'))
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty);
  for (final chunk in chunks) {
    final lower = chunk.toLowerCase();
    if (teacher.isEmpty &&
        RegExp(r'^(prof\.?|teacher|instructor|dr\.?|mr\.?|ms\.?|mrs\.?)\b')
            .hasMatch(lower)) {
      teacher = chunk;
    } else if (room.isEmpty &&
        RegExp(r'\b(room|rm\.?|bldg\.?|building|hall|lab|blk\.?|wing)\b')
            .hasMatch(lower)) {
      room = chunk;
    } else if (room.isEmpty && RegExp(r'\d').hasMatch(chunk)) {
      room = chunk;
    }
  }
  return (room: room, teacher: teacher);
}

/// Earliest index in [text] where a day token or the time range
/// starts, or null when neither appears.
int? _firstDayOrTimeIndex(String text) {
  var earliest = _timeRangeRe.firstMatch(text)?.start;
  for (final re in [_dayRangeRe, _dayWordRe, _compactDaysRe, _tthRe]) {
    final at = re.firstMatch(text)?.start;
    if (at != null && (earliest == null || at < earliest)) {
      earliest = at;
    }
  }
  return earliest;
}

/// One line of schedule text -> one class, or null when the line
/// does not carry both a weekday and a time range (headers,
/// dates, notes, and half-lines are skipped, never guessed).
ScannedClass? _parseLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;

  // Structured line: "Name | Days | Time | Room | Teacher" or the
  // same with commas / semicolons / tabs. The name is the first
  // segment; days and time are read from the rest (so a name like
  // "Sunday School" never donates its day word).
  List<String>? parts;
  if (trimmed.contains('|')) {
    parts = trimmed.split('|').map((p) => p.trim()).toList();
  } else {
    final split = trimmed
        .split(RegExp(r'[,;\t]'))
        .map((p) => p.trim())
        .toList();
    if (split.length >= 3) parts = split;
  }
  if (parts != null && parts.length >= 2) {
    final nameCode = _splitNameCode(parts[0]);
    if (nameCode.name.isEmpty) return null;
    final rest = parts.sublist(1).join(' | ');
    final days = _parseDays(rest);
    final time = _parseTimeRange(rest);
    if (days.isEmpty || time == null) return null;
    var room = '';
    var teacher = '';
    var timeSeen = false;
    for (final part in parts.sublist(1)) {
      if (!timeSeen) {
        if (_parseTimeRange(part) != null) timeSeen = true;
        continue;
      }
      final rt = _roomTeacherFromText(part);
      if (room.isEmpty) room = rt.room;
      if (teacher.isEmpty) teacher = rt.teacher;
    }
    return ScannedClass(
      name: nameCode.name,
      code: nameCode.code,
      teacher: teacher,
      room: room,
      days: days.toList()..sort(),
      startMin: time.startMin,
      endMin: time.endMin,
    );
  }

  // Free-form line: "Discrete Math Mon Wed Fri 8:00 AM - 9:30 AM
  // Room 101". The name is everything before the first day token
  // or the time range; room / teacher is what follows the time.
  final time = _parseTimeRange(trimmed);
  if (time == null) return null;
  final days = _parseDays(trimmed);
  if (days.isEmpty) return null;
  final nameEnd = _firstDayOrTimeIndex(trimmed);
  if (nameEnd == null || nameEnd == 0) return null;
  final rawName = trimmed
      .substring(0, nameEnd)
      .replaceAll(RegExp(r'[-–—•|:,;]+\s*$'), '')
      .trim();
  final nameCode = _splitNameCode(rawName);
  if (nameCode.name.isEmpty) return null;
  final timeEnd = _timeRangeRe.firstMatch(trimmed)!.end;
  final trailing = trimmed.substring(timeEnd).trim();
  final rt = _roomTeacherFromText(trailing);
  return ScannedClass(
    name: nameCode.name,
    code: nameCode.code,
    teacher: rt.teacher,
    room: rt.room,
    days: days.toList()..sort(),
    startMin: time.startMin,
    endMin: time.endMin,
  );
}

/// Second pass for table-style OCR text (see the file header):
/// reconstruct class entries whose subject, day code, time range,
/// room, and instructor arrived on separate or interleaved lines.
///
/// The walk keeps the nearest preceding subject (code + name,
/// with name continuations joined) and a pending day code from a
/// day-only line. A line with a time range becomes a class when
/// it has days — on its own line before the time, pending from
/// the line above, or leading right after the time ("7:30-9:30
/// am M CC105", the real certificate's format) — and a subject;
/// room / teacher come from the same line after the time and from
/// up to two following lines that look like room / teacher (never
/// a day, time, or subject line). A subject with two schedule
/// lines yields two entries. A time line with no days at all is
/// kept as a pending time entry and completed only by the
/// immediately following non-empty line when that line starts
/// with day tokens ("7:30-9:30 AM" then "M"); any other next
/// line discards it. Anything missing a subject, days, or a time
/// range is skipped; nothing is ever invented from fragments
/// that do not belong together.
List<ScannedClass> _tableFragmentClasses(String text) {
  final lines = text.split('\n');
  final found = <ScannedClass>[];
  final consumed = <int>{};
  ({String name, String code})? currentSubject;
  var awaitingName = false;
  Set<int>? pendingDays;
  ({String name, String code, int startMin, int endMin, String room,
      String teacher})? pendingTime;

  for (var i = 0; i < lines.length; i++) {
    if (consumed.contains(i)) continue;
    final line = lines[i].trim();
    if (line.isEmpty) continue;

    final timeMatch = _timeRangeRe.firstMatch(line);
    final time =
        timeMatch == null ? null : _parseTimeRange(line);
    if (time != null && timeMatch != null) {
      // A new time line supersedes any pending time entry: only
      // the immediately following line may complete one.
      pendingTime = null;
      // Schedule line: days come from the part before the time,
      // from a pending day-only line just above, or from the
      // leading day tokens right after the time ("7:30-9:30 am
      // M CC105"). The after-time read uses only leading tokens
      // and stops at the room code, so a teacher like "W.E. Que"
      // can never donate a Wednesday.
      final prefix = line.substring(0, timeMatch.start);
      var days = _parseScheduleDays(prefix);
      if (days.isEmpty) days = pendingDays ?? <int>{};
      if (days.isEmpty) {
        days = _leadingScheduleDays(line.substring(timeMatch.end)).days;
      }
      pendingDays = null;
      awaitingName = false;

      // A subject printed on this same line, before the day/time.
      ({String name, String code})? subject = currentSubject;
      final nameEnd = _firstScheduleDayOrTimeIndex(line);
      if (nameEnd != null && nameEnd > 0) {
        final rawName = line
            .substring(0, nameEnd)
            .replaceAll(RegExp(r'[-–—•|:,;]+\s*$'), '')
            .trim();
        if (rawName.isNotEmpty) {
          final nameCode = _splitNameCode(rawName);
          if (nameCode.name.isNotEmpty) {
            subject = (name: nameCode.name, code: nameCode.code);
          } else if (RegExp('^$_codeRe\$').hasMatch(rawName)) {
            // Code only before the day/time ("CT101 | M | ..."):
            // keep the code, keep any name seen before it.
            subject = (
              name: currentSubject?.name ?? rawName,
              code: rawName,
            );
          }
        }
      }
      // Room / teacher from the rest of this line (after the
      // time), whatever the days turn out to be.
      final rtSameLine =
          _roomTeacherFromText(line.substring(timeMatch.end));
      if (days.isEmpty) {
        // No days from any source: keep the time as a pending
        // entry when a subject exists, to be completed only by
        // the immediately following non-empty line starting
        // with day tokens. Otherwise skip it, never guess.
        if (subject != null &&
            (subject.name.isNotEmpty || subject.code.isNotEmpty)) {
          pendingTime = (
            name:
                subject.name.isEmpty ? subject.code : subject.name,
            code: subject.code,
            startMin: time.startMin,
            endMin: time.endMin,
            room: rtSameLine.room,
            teacher: rtSameLine.teacher,
          );
        }
        continue;
      }
      if (subject == null) continue;
      final name =
          subject.name.isEmpty ? subject.code : subject.name;
      if (name.isEmpty) continue;

      // Room / teacher: the rest of this line, then up to two
      // following lines that look like room / teacher.
      final rt = _roomTeacherLookahead(lines, i + 1, consumed, rtSameLine);

      currentSubject = subject;
      found.add(ScannedClass(
        name: name,
        code: subject.code,
        teacher: rt.teacher,
        room: rt.room,
        days: days.toList()..sort(),
        startMin: time.startMin,
        endMin: time.endMin,
      ));
      continue;
    }

    // A pending time entry is completed only by the immediately
    // following non-empty line, when that line starts with day
    // tokens ("M", or "M CC105"). Any other line discards the
    // pending entry and is processed normally below.
    if (pendingTime != null) {
      final pending = pendingTime;
      pendingTime = null;
      pendingDays = null;
      awaitingName = false;
      final leading = _leadingScheduleDays(line);
      if (leading.days.isNotEmpty) {
        final restRt = _roomTeacherFromText(leading.rest);
        var rt = (
          room: pending.room.isEmpty ? restRt.room : pending.room,
          teacher: pending.teacher.isEmpty
              ? restRt.teacher
              : pending.teacher,
        );
        rt = _roomTeacherLookahead(lines, i + 1, consumed, rt);
        currentSubject = (name: pending.name, code: pending.code);
        found.add(ScannedClass(
          name: pending.name,
          code: pending.code,
          teacher: rt.teacher,
          room: rt.room,
          days: leading.days.toList()..sort(),
          startMin: pending.startMin,
          endMin: pending.endMin,
        ));
        continue;
      }
      // No leading day tokens: fall through and process this
      // line normally (the pending entry is already discarded).
    }

    // A day-only line: remember its days for the time line that
    // follows — but only after a subject, so a stray "Monday" in
    // prose never becomes a pending schedule.
    if (_isDayOnlyLine(line)) {
      awaitingName = false;
      if (currentSubject != null &&
          (currentSubject.name.isNotEmpty ||
              currentSubject.code.isNotEmpty)) {
        pendingDays = _parseScheduleDays(line);
      }
      continue;
    }

    // A subject line: a leading code with a name, or a bare code
    // whose name follows on the next line(s).
    final leading =
        RegExp('^($_codeRe)\\s*[-–—:.]?\\s*(.*)\$').firstMatch(line);
    if (leading != null) {
      final rest = leading.group(2)!.trim();
      if (rest.isEmpty) {
        currentSubject = (name: '', code: leading.group(1)!);
        awaitingName = true;
        pendingDays = null;
      } else if (_isDayOnlyLine(rest)) {
        // "CT101 M" — code plus a day code, no name yet.
        currentSubject = (name: '', code: leading.group(1)!);
        awaitingName = true;
        pendingDays = _parseScheduleDays(rest);
      } else {
        final nameCode = _splitNameCode(line);
        currentSubject = (name: nameCode.name, code: nameCode.code);
        // The name may continue on the next line ("Installing
        // and Configuring" / "Computer Systems").
        awaitingName = true;
        // A new subject starts fresh: any pending day code
        // belonged to the previous subject.
        pendingDays = null;
      }
      continue;
    }

    // A name continuation for a subject whose name was split
    // across lines.
    if (awaitingName && currentSubject != null) {
      if (_looksLikeNameContinuation(line)) {
        final base = currentSubject.name.isEmpty
            ? line
            : '${currentSubject.name} $line';
        currentSubject = (name: base, code: currentSubject.code);
      } else {
        awaitingName = false;
      }
      continue;
    }

    // Anything else (headers, term lines, prose, dates) is
    // ignored — it belongs to no class.
  }
  return found;
}

/// Pull every class entry out of [text]. First the existing
/// one-class-per-line pass, then the table-fragment pass for
/// OCR text split across lines; identical entries are kept once.
ScheduleParseResult parseScheduleText(String text) {
  final classes = <ScannedClass>[];
  final seen = <String>{};
  void add(ScannedClass parsed) {
    final key =
        '${parsed.name.toLowerCase()}|${parsed.days.join(',')}|${parsed.startMin}|${parsed.endMin}';
    if (!seen.add(key)) return;
    classes.add(parsed);
  }

  for (final rawLine in text.split('\n')) {
    final parsed = _parseLine(rawLine);
    if (parsed == null) continue;
    add(parsed);
  }
  for (final parsed in _tableFragmentClasses(text)) {
    add(parsed);
  }
  return ScheduleParseResult(classes: classes);
}

/// What happened when a file was picked for the Files scan.
enum ScheduleScanStatus {
  /// The user dismissed the picker; nothing to do.
  cancelled,

  /// Text was extracted and at least one class was found.
  found,

  /// Text was extracted but no line parsed as a class.
  noClasses,

  /// The file opened but no text was found in it (empty text
  /// file, image with no words, scanned PDF with no text layer).
  noText,

  /// The file type has no extractor.
  unsupported,
}

class ScheduleScanResult {
  const ScheduleScanResult({
    required this.status,
    required this.fileName,
    this.classes = const [],
  });

  final ScheduleScanStatus status;
  final String fileName;

  /// Classes actually extracted (non-empty only when [status] is
  /// [ScheduleScanStatus.found]).
  final List<ScannedClass> classes;
}

/// Pick a file and scan it for class schedule entries.
///
/// - Picking uses the same [FilePicker] call as Notes / AI Files:
///   photos, PDFs, and plain text (.txt / .md / .csv).
/// - Text extraction is [NoteExtractService] (ML Kit OCR, pdfrx,
///   direct text read) — no new dependency.
/// - Parsing is [parseScheduleText] (pure Dart).
///
/// The picker, the extractor, and the whole extract-and-parse step
/// are injectable so widget tests can run without native plugins
/// or real file I/O (both deadlock in `flutter test`'s fake-async
/// zone — the Notes tests hit the same wall and fake the
/// extractors there too; the real file-read path is covered by
/// plain `test()`s in test/schedule_scan_test.dart instead).
class ScheduleFileScanner {
  ScheduleFileScanner({
    Future<File?> Function()? pickFile,
    NoteExtractService? extractService,
    Future<ScheduleScanResult> Function(File file)? extractAndParse,
  })  : _pickFile = pickFile ?? _defaultPickFile,
        _extractService = extractService ?? NoteExtractService(),
        _extractAndParseOverride = extractAndParse;

  final Future<File?> Function() _pickFile;
  final NoteExtractService _extractService;
  final Future<ScheduleScanResult> Function(File file)?
      _extractAndParseOverride;

  static const _extensions = [
    'pdf',
    'png',
    'jpg',
    'jpeg',
    'webp',
    'heic',
    'heif',
    'bmp',
    'gif',
    'txt',
    'md',
    'csv',
  ];

  static Future<File?> _defaultPickFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _extensions,
    );
    if (picked == null || picked.path == null) return null;
    return File(picked.path!);
  }

  /// Open the file picker. Null when the user cancels.
  Future<File?> pickFile() => _pickFile();

  /// Extract text from [file] and parse it for classes.
  Future<ScheduleScanResult> extractAndParse(File file) async {
    final override = _extractAndParseOverride;
    if (override != null) return override(file);
    final fileName = file.path.split('/').last;
    final extracted = await _extractService.extract(file);
    switch (extracted.outcome) {
      case NoteExtractOutcome.ok:
        final parsed = parseScheduleText(extracted.text);
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
      case NoteExtractOutcome.empty:
        return ScheduleScanResult(
          status: ScheduleScanStatus.noText,
          fileName: fileName,
        );
      case NoteExtractOutcome.videoUnsupported:
      case NoteExtractOutcome.typeUnsupported:
        return ScheduleScanResult(
          status: ScheduleScanStatus.unsupported,
          fileName: fileName,
        );
    }
  }

  /// Pick a file and scan it in one step. Convenience for call
  /// sites that do not need to show progress while extracting.
  Future<ScheduleScanResult> scan() async {
    final file = await pickFile();
    if (file == null) {
      return const ScheduleScanResult(
        status: ScheduleScanStatus.cancelled,
        fileName: '',
      );
    }
    return extractAndParse(file);
  }
}
