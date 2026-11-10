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
// What it cannot do (yet): a scanned / image-only PDF has no text
// layer, so it reads as empty — a photo of the page works instead
// (on-device OCR). A class split across several lines, or a table
// whose days live in a header row and whose times live in a
// column, does not parse — one class per line is required.
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
      final rt = _splitRoomTeacher(part);
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
  final rt = _splitRoomTeacher(trailing);
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

/// Pull every class entry out of [text], one per line. Lines
/// without both a weekday and a time range are skipped; identical
/// entries in the file are kept once.
ScheduleParseResult parseScheduleText(String text) {
  final classes = <ScannedClass>[];
  final seen = <String>{};
  for (final rawLine in text.split('\n')) {
    final parsed = _parseLine(rawLine);
    if (parsed == null) continue;
    final key =
        '${parsed.name.toLowerCase()}|${parsed.days.join(',')}|${parsed.startMin}|${parsed.endMin}';
    if (!seen.add(key)) continue;
    classes.add(parsed);
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
