// Google Calendar-style week/day grid for Classes & Timetable.
//
// Phone-width grid: hour axis 12 AM–11 PM, day headers with weekday
// + date, today in a filled emerald circle with a tinted column, a
// red now-line at the current time, and the grid opens scrolled to
// the current hour. Monday-first; dates come from the device clock.
//
// Event blocks come ONLY from real [Subject] data (days + start/end
// minutes); with no subjects the grid is empty by design — nothing
// is invented. Event-block styling (color bar, title, time range)
// is ready for real classes.

import 'package:flutter/material.dart';

import 'student_data.dart';

/// Google Calendar-style grid over [days] (1 day = Today view,
/// 7 days starting Monday = This Week view).
class ClassWeekGrid extends StatefulWidget {
  const ClassWeekGrid({
    super.key,
    required this.subjects,
    required this.days,
    required this.now,
  });

  final List<Subject> subjects;
  final List<DateTime> days;
  final DateTime now;

  @override
  State<ClassWeekGrid> createState() => _ClassWeekGridState();
}

class _ClassWeekGridState extends State<ClassWeekGrid> {
  static const double _hourHeight = 48;
  static const double _gutterWidth = 44;
  static const double _gridHeight = 420;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    // Open scrolled to the current hour (one hour of context above
    // the now-line), clamped to the grid bounds.
    final offset = ((widget.now.hour - 1) * _hourHeight).clamp(
      0.0,
      24 * _hourHeight - _gridHeight,
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
          height: _gridHeight,
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
                      // Real class event blocks.
                      for (var i = 0; i < days.length; i++)
                        for (final subject
                            in classesOnDay(widget.subjects, days[i].weekday))
                          Positioned(
                            left: _gutterWidth +
                                i * colWidth +
                                2,
                            width: colWidth - 4,
                            top: subject.startMin / 60 * _hourHeight + 1,
                            height:
                                ((subject.endMin - subject.startMin) /
                                        60 *
                                        _hourHeight -
                                    2)
                                .clamp(18.0, double.infinity),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Color(
                                  subject.color,
                                ).withValues(alpha: isDark ? 0.30 : 0.18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border(
                                  left: BorderSide(
                                    color: Color(subject.color),
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    subject.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    '${formatMinutes(subject.startMin)}–${formatMinutes(subject.endMin)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
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

/// Monday of the week containing [day] (Monday-first weeks).
DateTime mondayOfWeek(DateTime day) {
  return DateTime(day.year, day.month, day.day - (day.weekday - 1));
}
