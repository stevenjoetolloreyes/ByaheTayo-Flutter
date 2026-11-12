// Schedule home screen widgets — Dart side (Android only).
//
// DESIGN (why this shape): the widget must show the NEXT class and
// the week even on days the app was never opened, so — like the
// Bible Verse widget (BibleWidgetService) — the Dart side pushes
// the FULL schedule as JSON once and the Kotlin providers derive
// today / next class / week rows from that stored list on every
// update (updatePeriodMillis 30 min). The single source of truth
// stays the app's stored schedule: the SAME SharedPreferences
// lists the Classes & Timetable screen reads
// (StudentStorage.subjectsKey for classes, the synced set from
// google_events.dart for Google Calendar events). Nothing here
// re-lists subjects or events, so a Manual add, a Files scan, or
// a Google sync flows to the widget with the next sync call —
// and the widget NEVER hardcodes Steven's (or any student's)
// schedule. The times in the tests are fixtures only.
//
// BOTH SIZES, ONE PAYLOAD: the small 4x2 "Next Class" widget and
// the big 4x3 "This Week" widget read the same
// `schedule_widget_data` JSON, so they can never disagree. The
// Kotlin providers render different layouts from the same data.
//
// NO INSTRUCTOR NAMES (privacy rule, same as the landing page):
// the widget JSON carries code + name + days + times + room only.
// Subject.teacher and GoogleCalendarEvent.teacher are stripped
// at encode time — a subject with a teacher still in the app
// renders identically on the widget, and the encoded JSON never
// contains a teacher name.
//
// GOOGLE CALENDAR (approved preview v2, Nov 11, 2026): the widget
// shows each synced Google Calendar event with its white G badge
// and its NAME only — NSTP 1, Life and Works of Rizal, Discrete
// Mathematics, Vigan. The stored events DO carry a weekday, a
// time range and a place, but the approved preview shows the name
// only, so the widget follows the preview; the stored set keeps
// the full fields and showing them later is a rendering change,
// not a data change. HONEST NOTE: these four are the events
// currently saved in the app (the sample set seeded by
// loadGoogleEvents); the first real Google Calendar sync replaces
// them with the student's real Google Calendar events
// (google_events.dart: the first sync clears the stored set).
// Nothing here invents an event, a time, a day or a place.
//
// TAP: tapping either widget opens the app's Classes screen. The
// Kotlin providers launch the app with the `homewidget://classes`
// URI (HomeWidgetLaunchIntent) and the app root listens for it
// (see _EstudyanteGOAppState in main.dart) — only when the
// dashboard is showing (signed in, profile done); on the sign-in
// or setup screens the tap just opens the app.
//
// The push is best-effort and never throws: widget tests run
// without the plugin, and the Classes screen must never break
// because the widget plugin is unavailable. The provider shows
// an empty state ("No subjects yet.") when no schedule data has
// been pushed yet.
import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import 'google_events.dart';
import 'student_data.dart';

/// One class as the widget understands it: code + name + days +
/// start/end minutes + room + color. The teacher is deliberately
/// NOT carried (privacy rule — see the file header).
class ScheduleWidgetSubject {
  const ScheduleWidgetSubject({
    required this.id,
    required this.code,
    required this.name,
    required this.days,
    required this.startMin,
    required this.endMin,
    required this.room,
    required this.color,
  });

  factory ScheduleWidgetSubject.fromSubject(Subject s) =>
      ScheduleWidgetSubject(
        id: s.id,
        code: s.code,
        name: s.name,
        days: List<int>.of(s.days),
        startMin: s.startMin,
        endMin: s.endMin,
        room: s.room,
        color: s.color,
      );

  factory ScheduleWidgetSubject.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final code = json['code'];
    final name = json['name'];
    final days = json['days'];
    final startMin = json['startMin'];
    final endMin = json['endMin'];
    final room = json['room'];
    final color = json['color'];
    if (id is! String ||
        code is! String ||
        name is! String ||
        days is! List ||
        startMin is! num ||
        endMin is! num ||
        room is! String ||
        color is! num) {
      throw const FormatException('Schedule widget subject is malformed');
    }
    return ScheduleWidgetSubject(
      id: id,
      code: code,
      name: name,
      days: days.map((e) => (e as num).toInt()).toList(),
      startMin: startMin.toInt(),
      endMin: endMin.toInt(),
      room: room,
      color: color.toInt(),
    );
  }

  final String id;

  /// e.g. "CT101" — the week rows show the code; the next-class
  /// card shows "NEXT CLASS · CT101" plus the full name below.
  final String code;

  /// e.g. "Introduction to Computing".
  final String name;

  /// 1 = Monday .. 7 = Sunday (DateTime.weekday).
  final List<int> days;
  final int startMin;
  final int endMin;

  /// e.g. "CC105" — empty when the subject has no room.
  final String room;
  final int color;

  /// "9:00–10:30 AM" — the week rows and the next-class card
  /// both use this; the time range is built from the stored
  /// minutes, never typed by hand. The AM/PM suffix is shown once
  /// when both ends share it ("2:00–3:30 PM"); when the range
  /// crosses noon both suffixes stay ("11:00 AM–12:30 PM").
  String get timeRange {
    final start = formatMinutes(startMin);
    final end = formatMinutes(endMin);
    final startSuffix = start.substring(start.length - 2);
    final endSuffix = end.substring(end.length - 2);
    if (startSuffix == endSuffix) {
      return '${start.substring(0, start.length - 3)}–$end';
    }
    return '$start–$end';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'days': days,
        'startMin': startMin,
        'endMin': endMin,
        'room': room,
        'color': color,
      };

  @override
  bool operator ==(Object other) =>
      other is ScheduleWidgetSubject &&
      other.id == id &&
      other.code == code &&
      other.name == name &&
      _daysEqual(other.days, days) &&
      other.startMin == startMin &&
      other.endMin == endMin &&
      other.room == room &&
      other.color == color;

  @override
  int get hashCode => Object.hash(
        id,
        code,
        name,
        Object.hashAll(days),
        startMin,
        endMin,
        room,
        color,
      );
}

bool _daysEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One Google Calendar event as the widget understands it: id +
/// title ONLY. The preview (v2, approved Nov 11) shows the event
/// name with its white G badge and no time/day/place — the stored
/// event carries those fields, but the approved design shows the
/// name only (see the file header).
class ScheduleWidgetGoogleEvent {
  const ScheduleWidgetGoogleEvent({required this.id, required this.title});

  factory ScheduleWidgetGoogleEvent.fromEvent(GoogleCalendarEvent e) =>
      ScheduleWidgetGoogleEvent(id: e.id, title: e.title);

  factory ScheduleWidgetGoogleEvent.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) {
      throw const FormatException('Schedule widget Google event is malformed');
    }
    return ScheduleWidgetGoogleEvent(id: id, title: title);
  }

  final String id;
  final String title;

  Map<String, dynamic> toJson() => {'id': id, 'title': title};

  @override
  bool operator ==(Object other) =>
      other is ScheduleWidgetGoogleEvent &&
      other.id == id &&
      other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}

/// The whole schedule payload the providers read: the student's
/// classes plus the synced Google Calendar events. Empty lists
/// mean "no data pushed yet" — the provider shows the empty state.
class ScheduleWidgetData {
  const ScheduleWidgetData({
    this.subjects = const [],
    this.googleEvents = const [],
  });

  factory ScheduleWidgetData.fromJson(Map<String, dynamic> json) {
    final subjects = json['subjects'];
    final googleEvents = json['google'];
    if (subjects is! List || googleEvents is! List) {
      throw const FormatException('Schedule widget data is malformed');
    }
    return ScheduleWidgetData(
      subjects: subjects
          .map((e) => ScheduleWidgetSubject.fromJson(e as Map<String, dynamic>))
          .toList(),
      googleEvents: googleEvents
          .map((e) =>
              ScheduleWidgetGoogleEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final List<ScheduleWidgetSubject> subjects;
  final List<ScheduleWidgetGoogleEvent> googleEvents;

  Map<String, dynamic> toJson() => {
        'subjects': subjects.map((s) => s.toJson()).toList(),
        'google': googleEvents.map((e) => e.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      other is ScheduleWidgetData &&
      _subjectsEqual(other.subjects, subjects) &&
      _googleEqual(other.googleEvents, googleEvents);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(subjects), Object.hashAll(googleEvents));
}

bool _subjectsEqual(
    List<ScheduleWidgetSubject> a, List<ScheduleWidgetSubject> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _googleEqual(List<ScheduleWidgetGoogleEvent> a,
    List<ScheduleWidgetGoogleEvent> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class ScheduleWidgetService {
  ScheduleWidgetService._();

  /// SharedPreferences key (inside the home_widget store) holding
  /// the schedule JSON both providers read.
  static const String dataKey = 'schedule_widget_data';

  /// Small 4x2 "Next Class" provider.
  static const String providerName = 'ScheduleWidgetProvider';
  static const String providerQualifiedName =
      'com.estudyantego.app.ScheduleWidgetProvider';

  /// Big 4x3 "This Week" provider.
  static const String weekProviderName = 'ScheduleWeekWidgetProvider';
  static const String weekProviderQualifiedName =
      'com.estudyantego.app.ScheduleWeekWidgetProvider';

  /// URI the providers launch with on tap. The app root listens
  /// for it (HomeWidget.widgetClicked /
  /// initiallyLaunchedFromHomeWidget) and opens the Classes
  /// screen when the dashboard is showing.
  static const String classesUri = 'homewidget://classes';

  /// Shown by the providers when no schedule data has been pushed
  /// yet. (The Kotlin side carries the same wording; keep them in
  /// sync.)
  static const String emptyTitle = 'No subjects yet.';
  static const String emptySubtitle =
      'Add a subject to build your timetable.';

  /// How many Google events the widget lists at most (the preview
  /// shows four); more than that renders as "+N more".
  static const int maxGoogleEvents = 4;

  /// How many entries a week day row shows at most; more than that
  /// renders as "+N more".
  static const int maxEntriesPerDay = 3;

  /// Pure: the short date line for the next class, e.g.
  /// "Thu, Nov 12". Mirrors formatDate but short ("Nov 12", no
  /// year) and with the weekday, as in the preview.
  static String nextClassDateLine(DateTime date) =>
      '${weekdayName(date.weekday)}, ${_shortMonth(date.month)} ${date.day}';

  static String _shortMonth(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  /// Pure: the "COMING UP" line for the next class, e.g.
  /// "Today at 2:00 PM", "Tomorrow at 9:00 AM", "Thu at 9:00 AM".
  /// [nextDate] is the DATE of the next class (midnight, as
  /// returned by [nextClass]); [startMin] is the class start time
  /// in minutes after midnight.
  static String comingUpLabel(DateTime nextDate, DateTime now, int startMin) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(nextDate.year, nextDate.month, nextDate.day);
    final offset = day.difference(today).inDays;
    final when = offset == 0
        ? 'Today'
        : offset == 1
            ? 'Tomorrow'
            : weekdayName(day.weekday);
    return '$when at ${formatMinutes(startMin)}';
  }

  /// Pure: the week footer line, e.g.
  /// "Next up: Thu · CSS101 · 9:00 AM · CC203". Null when there is
  /// no upcoming class.
  static String? nextUpLine(
    List<Subject> subjects,
    DateTime now,
  ) {
    final next = nextClass(subjects, now);
    if (next == null) return null;
    final s = next.subject;
    final room = s.room.isEmpty ? '' : ' · ${s.room}';
    return 'Next up: ${weekdayName(next.date.weekday)} · '
        '${s.code.isEmpty ? s.name : s.code} · '
        '${formatMinutes(s.startMin)}$room';
  }

  /// Encodes the widget payload from the app's stored lists. The
  /// teacher is stripped here (see the file header) — the JSON
  /// never contains an instructor name.
  static String encodeData(
    List<Subject> subjects,
    List<GoogleCalendarEvent> googleEvents,
  ) {
    return jsonEncode(ScheduleWidgetData(
      subjects: subjects.map(ScheduleWidgetSubject.fromSubject).toList(),
      googleEvents: googleEvents
          .map(ScheduleWidgetGoogleEvent.fromEvent)
          .toList(),
    ).toJson());
  }

  /// Decodes a pushed payload. Returns empty data for null, empty,
  /// non-map, or malformed JSON — the provider treats that as "no
  /// data yet" and shows the empty state, never a crash.
  static ScheduleWidgetData decodeData(String? raw) {
    if (raw == null || raw.isEmpty) return const ScheduleWidgetData();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const ScheduleWidgetData();
      }
      return ScheduleWidgetData.fromJson(decoded);
    } catch (_) {
      return const ScheduleWidgetData();
    }
  }

  /// Pushes the student's current schedule to the widget store,
  /// then asks BOTH providers to refresh. The payload is written
  /// in ONE saveWidgetData call (subjects + Google events
  /// together), so a refresh can never leave one widget showing
  /// new classes with old Google events. Best-effort: never
  /// throws, so callers (Classes screen saves, app start) can
  /// fire-and-forget it.
  static Future<void> sync() async {
    try {
      final rawSubjects =
          await StudentStorage.loadList(StudentStorage.subjectsKey);
      final subjects = rawSubjects.map(Subject.fromJson).toList();
      final googleEvents = await loadGoogleEvents();
      await HomeWidget.saveWidgetData<String>(
          dataKey, encodeData(subjects, googleEvents));
      await HomeWidget.updateWidget(
        androidName: providerName,
        qualifiedAndroidName: providerQualifiedName,
      );
      await HomeWidget.updateWidget(
        androidName: weekProviderName,
        qualifiedAndroidName: weekProviderQualifiedName,
      );
    } catch (_) {
      // No widget plugin (tests, iOS) or a platform failure: the
      // Classes screen and app start must keep working either way.
    }
  }
}
