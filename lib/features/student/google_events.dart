// Google Calendar events synced into Classes & Timetable.
//
// MOCK SYNC (Nov 9, 2026): there is no real Google Calendar API /
// OAuth integration yet. The sample set below is the synced set
// from the approved hub-card preview — Discrete Mathematics, Life
// and Works of Rizal, NSTP 1, Vigan — stored locally in
// SharedPreferences the first time the Hub loads, so edits and
// removals persist. The sync reads ONLY the signed-in student's
// own calendar (when the real sync lands); it never touches
// anyone else's calendar.
//
// ONE DATA SOURCE: [mergedEntries] / [todayListEntries] /
// [entriesForDay] build the single merged (classes + Google)
// list that the hub timelines, the hub lists, and the full-screen
// lists all render from, so they can never diverge. A Google
// event whose title matches a real class is skipped (the class
// already represents it) — the full-screen list deduplicates the
// same way.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../top_popup.dart';
import 'student_data.dart';

/// One Google Calendar event synced into the timetable.
class GoogleCalendarEvent {
  GoogleCalendarEvent({
    required this.id,
    required this.title,
    required this.weekday, // 1 = Monday .. 7 = Sunday (DateTime.weekday)
    required this.startMin,
    required this.endMin,
    required this.place,
    this.teacher = '',
    required this.color,
    this.single = false, // single-point event (e.g. Vigan 4:47 PM)
  });

  final String id;
  final String title;
  final int weekday;
  final int startMin;
  final int endMin;
  final String place;
  final String teacher;
  final int color;

  /// True for a point-in-time event: the block renders one hour
  /// from [startMin] and the time shows as a single time, not a
  /// range.
  final bool single;

  GoogleCalendarEvent copyWith({
    String? title,
    int? weekday,
    int? startMin,
    int? endMin,
    String? place,
    String? teacher,
    int? color,
  }) {
    return GoogleCalendarEvent(
      id: id,
      title: title ?? this.title,
      weekday: weekday ?? this.weekday,
      startMin: startMin ?? this.startMin,
      endMin: endMin ?? this.endMin,
      place: place ?? this.place,
      teacher: teacher ?? this.teacher,
      color: color ?? this.color,
      single: single,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'weekday': weekday,
        'startMin': startMin,
        'endMin': endMin,
        'place': place,
        'teacher': teacher,
        'color': color,
        'single': single,
      };

  static GoogleCalendarEvent fromJson(Map<String, dynamic> j) =>
      GoogleCalendarEvent(
        id: j['id'] as String,
        title: j['title'] as String,
        weekday: (j['weekday'] as num).toInt(),
        startMin: (j['startMin'] as num).toInt(),
        endMin: (j['endMin'] as num).toInt(),
        place: j['place'] as String? ?? '',
        teacher: j['teacher'] as String? ?? '',
        color: (j['color'] as num).toInt(),
        single: j['single'] as bool? ?? false,
      );
}

/// The mock-synced sample set (the approved hub-card preview):
/// Discrete Mathematics (Thu), Life and Works of Rizal (Fri),
/// NSTP 1 (Sat), Vigan (Sun 4:47 PM).
List<GoogleCalendarEvent> sampleGoogleEvents() => [
      GoogleCalendarEvent(
        id: 'g-nstp',
        title: 'NSTP 1',
        weekday: 6,
        startMin: 8 * 60,
        endMin: 11 * 60,
        place: 'Covered Court',
        color: 0xFF0D9488,
      ),
      GoogleCalendarEvent(
        id: 'g-rizal',
        title: 'Life and Works of Rizal',
        weekday: 5,
        startMin: 10 * 60,
        endMin: 11 * 60 + 30,
        place: 'Rm 112',
        teacher: "Ma'am Santos",
        color: 0xFFD97706,
      ),
      GoogleCalendarEvent(
        id: 'g-discrete',
        title: 'Discrete Mathematics',
        weekday: 4,
        startMin: 15 * 60,
        endMin: 16 * 60 + 30,
        place: 'Rm 204',
        teacher: 'Sir Dela Cruz',
        color: 0xFF7C4DBD,
      ),
      GoogleCalendarEvent(
        id: 'g-vigan',
        title: 'Vigan',
        weekday: 7,
        startMin: 16 * 60 + 47,
        endMin: 17 * 60 + 47,
        place: 'Vigan',
        color: 0xFF3B82F6,
        single: true,
      ),
    ];

/// Storage key for the locally stored synced set.
const googleEventsKey = 'byahetayo_student_google_events';

/// Set to 1 once the first REAL Google Calendar sync has replaced
/// the placeholder sample set (Feature 4). Until then the stored
/// set may still be the seeded samples; after the first real sync
/// the stored set is real events only, and later syncs merge into
/// it instead of replacing it.
const googleCalendarRealSyncKey = 'byahetayo_google_calendar_real_sync_done';

/// True once a real Calendar API sync has run (see
/// [googleCalendarRealSyncKey]).
Future<bool> isGoogleCalendarRealSyncDone() async {
  return await StudentStorage.loadInt(googleCalendarRealSyncKey) == 1;
}

/// Marks the first real sync as done, so later syncs merge.
Future<void> markGoogleCalendarRealSyncDone() async {
  await StudentStorage.saveInt(googleCalendarRealSyncKey, 1);
}

/// Loads the stored synced set; seeds (and stores) the sample set
/// on first run. An explicitly stored empty list stays empty — a
/// student who removed every event does not get them back.
Future<List<GoogleCalendarEvent>> loadGoogleEvents() async {
  final raw = await StudentStorage.loadRaw(googleEventsKey);
  if (raw == null) {
    final seeded = sampleGoogleEvents();
    await saveGoogleEvents(seeded);
    return seeded;
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .map((e) => GoogleCalendarEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  } catch (_) {}
  return [];
}

Future<void> saveGoogleEvents(List<GoogleCalendarEvent> events) async {
  await StudentStorage.saveList(
      googleEventsKey, events.map((e) => e.toJson()).toList());
}

/// Google events on [weekday], sorted by start time.
List<GoogleCalendarEvent> googleEventsOnDay(
    List<GoogleCalendarEvent> events, int weekday) {
  final list = events.where((e) => e.weekday == weekday).toList();
  list.sort((a, b) => a.startMin.compareTo(b.startMin));
  return list;
}

/// Time range text for a Google event: a single time for
/// point events ("4:47 PM"), a range otherwise.
String googleEventRange(GoogleCalendarEvent event) {
  if (event.single) return formatMinutes(event.startMin);
  return '${formatMinutes(event.startMin)}–${formatMinutes(event.endMin)}';
}

/// "Thu · 3:00 PM–4:30 PM · Rm 204" — the action-sheet meta line.
String googleEventMeta(GoogleCalendarEvent event) {
  final parts = <String>[
    weekdayName(event.weekday),
    googleEventRange(event),
    if (event.place.isNotEmpty) event.place,
  ];
  return parts.join(' · ');
}

// ---------------------------------------------------------------- merged
// entries — the single source for grids and lists.

/// One renderable timetable entry: a real class or a synced
/// Google Calendar event.
class TimetableEntry {
  TimetableEntry({
    required this.title,
    required this.weekday,
    required this.startMin,
    required this.endMin,
    required this.color,
    required this.isGoogle,
    this.subject,
    this.googleEvent,
    this.dayPrefix = '',
  });

  /// Display title.
  final String title;

  /// 1 = Monday .. 7 = Sunday.
  final int weekday;
  final int startMin;
  final int endMin;
  final int color;

  /// True for a synced Google Calendar event.
  final bool isGoogle;
  final Subject? subject;
  final GoogleCalendarEvent? googleEvent;

  /// Day prefix for Google rows in the Today list ("Thu").
  /// Empty for class rows and for week-list rows (the day-group
  /// header already says the day).
  final String dayPrefix;

  /// "Rm 204 · Sir Dela Cruz" / "UNP · Sir Supnet" — the row's
  /// right-hand value. Empty when there is nothing to show.
  String get detail {
    final parts = <String>[];
    final place = isGoogle ? googleEvent?.place ?? '' : subject?.room ?? '';
    final teacher =
        isGoogle ? googleEvent?.teacher ?? '' : subject?.teacher ?? '';
    if (place.isNotEmpty) parts.add(place);
    if (teacher.isNotEmpty) parts.add(teacher);
    return parts.join(' · ');
  }

  /// "3:00 PM–4:30 PM · Discrete Mathematics" (Google rows in the
  /// Today list carry their day: "Thu · 3:00 PM–4:30 PM ·
  /// Discrete Mathematics").
  String get label {
    final range = isGoogle && googleEvent != null
        ? googleEventRange(googleEvent!)
        : '${formatMinutes(startMin)}–${formatMinutes(endMin)}';
    final prefix = dayPrefix.isEmpty ? '' : '$dayPrefix · ';
    return '$prefix$range · $title';
  }
}

TimetableEntry _fromSubject(Subject s, int weekday) => TimetableEntry(
      title: s.name,
      weekday: weekday,
      startMin: s.startMin,
      endMin: s.endMin,
      color: s.color,
      isGoogle: false,
      subject: s,
    );

TimetableEntry _fromGoogle(GoogleCalendarEvent e, {String dayPrefix = ''}) =>
    TimetableEntry(
      title: e.title,
      weekday: e.weekday,
      startMin: e.startMin,
      endMin: e.endMin,
      color: e.color,
      isGoogle: true,
      googleEvent: e,
      dayPrefix: dayPrefix,
    );

/// Merged entries for one weekday: the day's classes plus the
/// day's Google events, time order. A Google event whose title
/// matches a class is skipped (the class already represents it).
List<TimetableEntry> entriesForDay(
  List<Subject> subjects,
  List<GoogleCalendarEvent> googleEvents,
  int weekday,
) {
  final classNames =
      classesOnDay(subjects, weekday).map((s) => s.name).toSet();
  final out = <TimetableEntry>[
    for (final s in classesOnDay(subjects, weekday)) _fromSubject(s, weekday),
    for (final e in googleEventsOnDay(googleEvents, weekday))
      if (!classNames.contains(e.title)) _fromGoogle(e),
  ];
  out.sort((a, b) => a.startMin.compareTo(b.startMin));
  return out;
}

/// Merged entries for the Today list: today's classes plus EVERY
/// synced Google event (any day of the week), time order — the
/// preview's Today list ("Coding, Introduction Of Computing,
/// NSTP 1, Life and Works of Rizal, Installing Configuration,
/// Discrete Mathematics, Vigan"). Google rows carry their day
/// prefix ("Thu · 3:00 PM–4:30 PM · Discrete Mathematics").
/// A Google event whose title matches a class is skipped.
List<TimetableEntry> todayListEntries(
  List<Subject> subjects,
  List<GoogleCalendarEvent> googleEvents,
  int weekday,
) {
  final classNames =
      classesOnDay(subjects, weekday).map((s) => s.name).toSet();
  final out = <TimetableEntry>[
    for (final s in classesOnDay(subjects, weekday)) _fromSubject(s, weekday),
    for (final e in googleEvents)
      if (!classNames.contains(e.title))
        _fromGoogle(e, dayPrefix: weekdayName(e.weekday)),
  ];
  out.sort((a, b) => a.startMin.compareTo(b.startMin));
  return out;
}

// ---------------------------------------------------------------- badge

/// Small white "G" badge marking a synced Google Calendar event
/// (the preview's white badge with the blue Google G).
class GBadge extends StatelessWidget {
  const GBadge({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFDFE7E1)),
      ),
      child: Text(
        'G',
        style: TextStyle(
          fontSize: size * 0.62,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF4285F4),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- action
// sheet: Edit / Remove for one synced Google event.

/// Opens the Google-event action sheet (Edit / Remove / Cancel).
/// Edit opens the edit form; Remove asks for confirmation first.
/// [onUpdated] fires with the edited event, [onRemoved] with the
/// removed event — the caller saves and re-renders.
Future<void> showGoogleEventActionSheet(
  BuildContext context, {
    required GoogleCalendarEvent event,
    required ValueChanged<GoogleCalendarEvent> onUpdated,
    required ValueChanged<GoogleCalendarEvent> onRemoved,
  }) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const GBadge(size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${googleEventMeta(event)} · Synced from Google Calendar',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: Theme.of(sheetContext)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              subtitle:
                  const Text('Title, day, start/end time, place'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                'Remove',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              subtitle: const Text('Unsyncs this Google Calendar event'),
              onTap: () => Navigator.pop(sheetContext, 'remove'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    ),
  );
  if (action == 'edit') {
    if (!context.mounted) return;
    final updated = await showModalBottomSheet<GoogleCalendarEvent>(
      context: context,
      isScrollControlled: true,
      builder: (_) => GoogleEventEditForm(event: event),
    );
    if (updated != null) onUpdated(updated);
  } else if (action == 'remove') {
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove "${event.title}"?'),
        content: Text(
          '${googleEventMeta(event)} — removing unsyncs this Google '
          'Calendar event from your schedule. It disappears from the '
          'Today timeline, the This Week grid, and the class list. '
          'You can sync it again later from Google Schedule.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) onRemoved(event);
  }
}

/// Edit form for a synced Google event: title, day, start/end
/// time, place. End must be after start (validated on save, with
/// the same TopPopup feedback as the subject form).
class GoogleEventEditForm extends StatefulWidget {
  const GoogleEventEditForm({super.key, required this.event});

  final GoogleCalendarEvent event;

  @override
  State<GoogleEventEditForm> createState() => _GoogleEventEditFormState();
}

class _GoogleEventEditFormState extends State<GoogleEventEditForm> {
  late final TextEditingController _title;
  late final TextEditingController _place;
  late int _weekday;
  late int _startMin;
  late int _endMin;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.event.title);
    _place = TextEditingController(text: widget.event.place);
    _weekday = widget.event.weekday;
    _startMin = widget.event.startMin;
    _endMin = widget.event.endMin;
  }

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (isStart ? _startMin : _endMin) ~/ 60,
        minute: (isStart ? _startMin : _endMin) % 60,
      ),
    );
    if (picked == null) return;
    setState(() {
      final minutes = picked.hour * 60 + picked.minute;
      if (isStart) {
        _startMin = minutes;
      } else {
        _endMin = minutes;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Edit Google event',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            const Text('Day', style: TextStyle(fontWeight: FontWeight.w700)),
            Wrap(
              spacing: 6,
              children: [
                for (var day = 1; day <= 7; day++)
                  FilterChip(
                    label: Text(weekdayName(day)),
                    selected: _weekday == day,
                    onSelected: (_) => setState(() => _weekday = day),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Start: ${formatMinutes(_startMin)}'),
                    trailing: const Icon(Icons.schedule),
                    onTap: () => _pickTime(true),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('End: ${formatMinutes(_endMin)}'),
                    trailing: const Icon(Icons.schedule),
                    onTap: () => _pickTime(false),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _place,
              decoration:
                  const InputDecoration(labelText: 'Place'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (_title.text.trim().isEmpty) {
                  TopPopup.show(context, message: 'Enter a title.');
                  return;
                }
                if (_endMin <= _startMin) {
                  TopPopup.show(
                    context,
                    message: 'End time must be after the start time.',
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  widget.event.copyWith(
                    title: _title.text.trim(),
                    weekday: _weekday,
                    startMin: _startMin,
                    endMin: _endMin,
                    place: _place.text.trim(),
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
