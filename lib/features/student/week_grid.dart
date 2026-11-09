// Google Calendar-style week/day grid for Classes & Timetable.
//
// Phone-width grid: hour axis 12 AM–11 PM, day headers with weekday
// + date, today in a filled emerald circle with a tinted column, a
// red now-line at the current time, and the grid opens scrolled to
// the current hour. Monday-first; dates come from the device clock.
//
// Event blocks come from real [Subject] data (days + start/end
// minutes) AND the synced Google Calendar events — the same merged
// set the hub lists render, so grid and list can never diverge.
// Google blocks carry the small white G badge and are tappable
// (edit / remove via the action sheet). Blocks that overlap in
// time share the day column side by side (lane split); with no
// overlaps every block is full width. With no subjects and no
// Google events the grid is empty by design — nothing is invented.
// Event-block styling (color bar, title, time range) is ready for
// real classes.

import 'package:flutter/material.dart';

import 'google_events.dart';
import 'student_data.dart';

/// One positioned block on the grid: a class or a Google event.
class _GridBlock {
  _GridBlock({
    required this.entry,
    required this.lane,
    required this.laneCount,
  });

  final TimetableEntry entry;

  /// 0-based lane within its day column (0 when nothing overlaps).
  final int lane;

  /// Lanes in this day column (1 when nothing overlaps).
  final int laneCount;
}

/// Google Calendar-style grid over [days] (1 day = Today view,
/// 7 days starting Monday = This Week view).
class ClassWeekGrid extends StatefulWidget {
  const ClassWeekGrid({
    super.key,
    required this.subjects,
    required this.days,
    required this.now,
    this.googleEvents = const [],
    this.viewportHeight = 420,
    this.onGoogleEventTap,
  });

  final List<Subject> subjects;
  final List<DateTime> days;
  final DateTime now;

  /// Synced Google Calendar events, drawn on the grid with G
  /// badges (same merged set as the hub lists).
  final List<GoogleCalendarEvent> googleEvents;

  /// Visible viewport height. Today is the compact 4x5
  /// widget-size box (5 hour-rows); This Week is the full-size
  /// grid (14 hour-rows). The whole 24-hour day is inside the
  /// scroll in both cases.
  final double viewportHeight;

  /// Tapped Google block (edit / remove sheet). Null when the
  /// grid is read-only.
  final ValueChanged<GoogleCalendarEvent>? onGoogleEventTap;

  @override
  State<ClassWeekGrid> createState() => _ClassWeekGridState();
}

class _ClassWeekGridState extends State<ClassWeekGrid> {
  static const double _hourHeight = 48;
  static const double _gutterWidth = 44;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    // Open scrolled to the current time (~1.5 hours of context
    // above the now-line), clamped to the grid bounds. The scroll
    // position is set once here — the 30s now-line refresh only
    // rebuilds, it never re-scrolls under the reader.
    final offset = ((widget.now.hour - 1.5) * _hourHeight).clamp(
      0.0,
      24 * _hourHeight - widget.viewportHeight,
    );
    _scrollController = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _hourLabel(int hour24) {
    if (hour24 == 0) return '12 AM';
    if (hour24 < 12) return '$hour24 AM';
    if (hour24 == 12) return '12 PM';
    return '${hour24 - 12} PM';
  }

  /// Merged blocks for one day, with lanes: blocks overlapping in
  /// time split the column side by side. Greedy interval coloring
  /// by start time gives the minimum lane count (the max overlap
  /// depth), so non-overlapping blocks always stay full width.
  List<_GridBlock> _blocksForDay(int weekday) {
    final entries = entriesForDay(widget.subjects, widget.googleEvents, weekday)
      ..sort((a, b) => a.startMin.compareTo(b.startMin));
    final laneEnds = <int>[];
    final blocks = <_GridBlock>[];
    for (final entry in entries) {
      var lane = -1;
      for (var i = 0; i < laneEnds.length; i++) {
        if (laneEnds[i] <= entry.startMin) {
          lane = i;
          break;
        }
      }
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(entry.endMin);
      } else {
        laneEnds[lane] = entry.endMin;
      }
      blocks.add(_GridBlock(entry: entry, lane: lane, laneCount: 0));
    }
    final laneCount = laneEnds.length;
    return [
      for (final b in blocks)
        _GridBlock(entry: b.entry, lane: b.lane, laneCount: laneCount),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emerald = isDark ? const Color(0xFF34D399) : const Color(0xFF14532D);
    final days = widget.days;
    final now = widget.now;
    final todayIndex =
        days.indexWhere((d) => dateKey(d) == dateKey(now));
    final nowOffset =
        (now.hour + now.minute / 60) * _hourHeight;

    return Column(
      children: [
        // Day headers: weekday + date; today in a filled emerald circle.
        Row(
          children: [
            const SizedBox(width: _gutterWidth),
            for (var i = 0; i < days.length; i++)
              Expanded(
                child: Column(
                  children: [
                    Text(
                      weekdayName(days[i].weekday),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: i == todayIndex
                            ? emerald
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: i == todayIndex
                          ? BoxDecoration(
                              color: emerald,
                              shape: BoxShape.circle,
                            )
                          : null,
                      child: Text(
                        '${days[i].day}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: i == todayIndex
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: i == todayIndex
                              ? Colors.white
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: widget.viewportHeight,
          child: SingleChildScrollView(
            controller: _scrollController,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final colWidth =
                    (constraints.maxWidth - _gutterWidth) / days.length;
                return SizedBox(
                  height: 24 * _hourHeight,
                  child: Stack(
                    children: [
                      // Hour rows + tinted today column.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: _gutterWidth,
                            child: Column(
                              children: [
                                for (var h = 0; h < 24; h++)
                                  SizedBox(
                                    height: _hourHeight,
                                    child: Align(
                                      alignment: Alignment.topRight,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 6,
                                          top: 2,
                                        ),
                                        child: Text(
                                          _hourLabel(h),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          for (var i = 0; i < days.length; i++)
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: i == todayIndex
                                      ? emerald.withValues(alpha: 0.07)
                                      : null,
                                  border: Border(
                                    left: BorderSide(
                                      color: scheme.outline
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    for (var h = 0; h < 24; h++)
                                      Container(
                                        height: _hourHeight,
                                        decoration: BoxDecoration(
                                          border: Border(
                                            top: BorderSide(
                                              color: scheme.outline
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      // Real class + Google event blocks.
                      for (var i = 0; i < days.length; i++)
                        for (final block
                            in _blocksForDay(days[i].weekday))
                          Positioned(
                            left: _gutterWidth +
                                i * colWidth +
                                block.lane *
                                    (colWidth / block.laneCount) +
                                2,
                            width: colWidth / block.laneCount - 4,
                            top: block.entry.startMin / 60 * _hourHeight + 1,
                            height:
                                ((block.entry.endMin - block.entry.startMin) /
                                        60 *
                                        _hourHeight -
                                    2)
                                .clamp(18.0, double.infinity),
                            child: _BlockContent(
                              entry: block.entry,
                              isDark: isDark,
                              scheme: scheme,
                              onGoogleTap: widget.onGoogleEventTap,
                            ),
                          ),
                      // Red now-line at the current time.
                      if (todayIndex >= 0)
                        Positioned(
                          left: _gutterWidth - 6,
                          right: 0,
                          top: nowOffset,
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  height: 2,
                                  color: const Color(0xFFEF4444),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// One event block: color bar, title, time range, and the white G
/// badge on Google events (tappable — opens the edit/remove
/// sheet). Class blocks stay untappable, as before.
class _BlockContent extends StatelessWidget {
  const _BlockContent({
    required this.entry,
    required this.isDark,
    required this.scheme,
    required this.onGoogleTap,
  });

  final TimetableEntry entry;
  final bool isDark;
  final ColorScheme scheme;
  final ValueChanged<GoogleCalendarEvent>? onGoogleTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Color(entry.color).withValues(alpha: isDark ? 0.30 : 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            color: Color(entry.color),
            width: 3,
          ),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              Text(
                entry.isGoogle && entry.googleEvent != null
                    ? googleEventRange(entry.googleEvent!)
                    : '${formatMinutes(entry.startMin)}–${formatMinutes(entry.endMin)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (entry.isGoogle)
            const Positioned(
              top: 0,
              right: 0,
              child: GBadge(size: 14),
            ),
        ],
      ),
    );
    if (entry.isGoogle && entry.googleEvent != null && onGoogleTap != null) {
      final event = entry.googleEvent!;
      return GestureDetector(
        onTap: () => onGoogleTap!(event),
        child: content,
      );
    }
    return content;
  }
}

/// Monday of the week containing [day] (Monday-first weeks).
DateTime mondayOfWeek(DateTime day) {
  return DateTime(day.year, day.month, day.day - (day.weekday - 1));
}
