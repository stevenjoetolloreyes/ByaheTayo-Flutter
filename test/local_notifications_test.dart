// Tests for the local (on-device) notifications system (Nov 8).
//
// Pure planning helpers + the plan builder are tested directly with
// a fixed "now" (Monday Nov 9, 2026, 7:00 AM). The service is tested
// through a fake scheduler (no plugin, no platform channels). The
// settings screen is tested as a widget with the existing
// FakePermissionService and a fake scheduler.
//
// Nothing here touches FCM, Cloud Functions, or a server: the whole
// system is local by design.
import 'dart:convert';

import 'package:estudyantego/features/local_notifications.dart';
import 'package:estudyantego/features/notification_settings_screen.dart';
import 'package:estudyantego/features/onboarding/permission_service.dart';
import 'package:estudyantego/features/school_events.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

/// Monday Nov 9, 2026, 7:00 AM — the fixed "now" for the pure tests.
final DateTime _now = DateTime(2026, 11, 9, 7, 0);

Subject _subject({
  String id = 's1',
  String name = 'Math',
  String room = 'Room 101',
  List<int> days = const [2],
  int startMin = 600,
  int endMin = 660,
}) =>
    Subject(
      id: id,
      name: name,
      code: '',
      teacher: '',
      room: room,
      days: days,
      startMin: startMin,
      endMin: endMin,
      color: 0xFF16A34A,
    );

AssignmentItem _assignment({
  String id = 'a1',
  String subjectId = 's1',
  String title = 'Problem set 3',
  String kind = 'assignment',
  DateTime? due,
  bool done = false,
}) =>
    AssignmentItem(
      id: id,
      subjectId: subjectId,
      title: title,
      kind: kind,
      due: due ?? DateTime(2026, 11, 12),
      done: done,
    );

SchoolEvent _event({
  String name = 'Foundation Day',
  DateTime? start,
  DateTime? end,
  SchoolEventKind kind = SchoolEventKind.foundation,
  bool noClasses = false,
}) =>
    SchoolEvent(
      start: start ?? DateTime(2026, 11, 14),
      end: end ?? start ?? DateTime(2026, 11, 14),
      name: name,
      kind: kind,
      noClasses: noClasses,
    );

CheckinRecord _checkin(DateTime date, {int dayIndex = 1}) => CheckinRecord(
      id: 'c${date.millisecondsSinceEpoch}',
      date: date,
      dayIndex: dayIndex,
      points: 10,
    );

/// Fake scheduler: records every call, never touches the plugin.
class FakeNotificationScheduler implements NotificationScheduler {
  bool initializeResult = true;
  bool canScheduleExactValue = true;
  bool throwOnSchedule = false;

  int initializeCount = 0;
  int cancelAllCount = 0;
  int requestExactCount = 0;
  final List<({int id, String? title, String? body, String? payload})>
      shown = [];
  final List<
      ({
        int id,
        String? title,
        String? body,
        DateTime scheduledDate,
        String? payload,
        NotificationRepeat repeat,
        bool exact,
      })> scheduled = [];

  @override
  Future<bool> initialize({
    required String androidIcon,
    void Function(String? payload)? onTap,
  }) async {
    initializeCount++;
    return initializeResult;
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    String? payload,
  }) async {
    shown.add((id: id, title: title, body: body, payload: payload));
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required DateTime scheduledDate,
    String? payload,
    required NotificationRepeat repeat,
    required bool exact,
  }) async {
    if (throwOnSchedule) throw StateError('schedule failed');
    scheduled.add((
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      payload: payload,
      repeat: repeat,
      exact: exact,
    ));
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
  }

  @override
  Future<bool> get canScheduleExact async => canScheduleExactValue;

  @override
  Future<void> requestExactAlarms() async {
    requestExactCount++;
    canScheduleExactValue = true;
  }
}

void main() {
  group('nextClassReminderTime', () {
    test('same-day class still ahead fires today, 30 minutes early', () {
      final when = nextClassReminderTime(
        _subject(days: const [1], startMin: 600),
        _now,
      );
      // Monday 10:00 class -> Monday 9:30.
      expect(when, DateTime(2026, 11, 9, 9, 30));
    });

    test('class already started today fires on its next day', () {
      final when = nextClassReminderTime(
        _subject(days: const [1], startMin: 30),
        _now,
      );
      // Monday 12:30 AM class, now 7:00 AM -> next Monday 12:00 AM.
      expect(when, DateTime(2026, 11, 16, 0, 0));
    });

    test('picks the nearest day of a multi-day subject', () {
      final when = nextClassReminderTime(
        _subject(days: const [1, 3, 5], startMin: 600),
        _now,
      );
      expect(when, DateTime(2026, 11, 9, 9, 30));
    });

    test('no days means no reminder', () {
      expect(nextClassReminderTime(_subject(days: const []), _now), isNull);
    });

    test('lead time clamps at midnight for a just-past-midnight class', () {
      final when = nextWeeklyOccurrence(
        weekday: 1,
        minutesOfDay: 5 - kClassReminderLeadMinutes,
        now: DateTime(2026, 11, 8, 23, 0),
      );
      // 00:05 class - 30 minutes = before midnight -> 00:00 Monday.
      expect(when, DateTime(2026, 11, 9, 0, 0));
    });
  });

  group('nextDailyReminderTime', () {
    test('today when the time is still ahead', () {
      expect(
        nextDailyReminderTime(const TimeOfDay(hour: 8, minute: 0), _now),
        DateTime(2026, 11, 9, 8, 0),
      );
    });

    test('tomorrow when the time has passed', () {
      expect(
        nextDailyReminderTime(
          const TimeOfDay(hour: 8, minute: 0),
          DateTime(2026, 11, 9, 9, 0),
        ),
        DateTime(2026, 11, 10, 8, 0),
      );
    });
  });

  group('assignmentReminderTime', () {
    test('8:00 AM the day before the due date', () {
      expect(
        assignmentReminderTime(_assignment(due: DateTime(2026, 11, 12)), _now),
        DateTime(2026, 11, 11, 8, 0),
      );
    });

    test('done items get no reminder', () {
      expect(
        assignmentReminderTime(
          _assignment(due: DateTime(2026, 11, 12), done: true),
          _now,
        ),
        isNull,
      );
    });

    test('due today means the reminder already passed', () {
      expect(
        assignmentReminderTime(_assignment(due: DateTime(2026, 11, 9)), _now),
        isNull,
      );
    });
  });

  group('quizReminderTime', () {
    test('8:00 PM the night before the exam', () {
      expect(
        quizReminderTime(
          _assignment(kind: 'exam', due: DateTime(2026, 11, 12)),
          _now,
        ),
        DateTime(2026, 11, 11, 20, 0),
      );
    });

    test('assignments get no quiz reminder', () {
      expect(
        quizReminderTime(
          _assignment(kind: 'assignment', due: DateTime(2026, 11, 12)),
          _now,
        ),
        isNull,
      );
    });

    test('done exams get no reminder', () {
      expect(
        quizReminderTime(
          _assignment(
            kind: 'exam',
            due: DateTime(2026, 11, 12),
            done: true,
          ),
          _now,
        ),
        isNull,
      );
    });

    test('exam tomorrow night already passed means no reminder', () {
      expect(
        quizReminderTime(
          _assignment(kind: 'exam', due: DateTime(2026, 11, 10)),
          DateTime(2026, 11, 9, 21, 0),
        ),
        isNull,
      );
    });
  });

  group('schoolReminderTime', () {
    test('8:00 AM the day before the event', () {
      expect(
        schoolReminderTime(DateTime(2026, 11, 14), _now),
        DateTime(2026, 11, 13, 8, 0),
      );
    });

    test('tomorrow’s event, now past 8:00 AM, gets no reminder', () {
      expect(
        schoolReminderTime(
          DateTime(2026, 11, 10),
          DateTime(2026, 11, 9, 9, 0),
        ),
        isNull,
      );
    });
  });

  group('buildNotificationPlan', () {
    test('all toggles on: one entry per category, sorted, stable ids', () {
      final plan = buildNotificationPlan(
        subjects: [
          _subject(days: const [2], startMin: 600),
          _subject(
            id: 's2',
            name: 'Coding',
            room: '',
            days: const [1],
            startMin: 30,
            endMin: 360,
          ),
        ],
        assignments: [
          _assignment(due: DateTime(2026, 11, 12)),
          _assignment(
            id: 'a2',
            due: DateTime(2026, 11, 13),
            done: true,
          ),
        ],
        schoolEvents: [
          _event(start: DateTime(2026, 11, 14)),
          _event(
            name: 'Midterm Exam',
            start: DateTime(2026, 11, 16),
            kind: SchoolEventKind.exam,
          ),
        ],
        holidays: [
          (date: DateTime(2026, 11, 11), name: 'Test Holiday'),
        ],
        prefs: const NotificationPreferences(),
        now: _now,
      );

      // 2 class + 1 assignment + 3 school + 1 daily + 1 verse.
      expect(plan.length, 8);
      expect(plan.map((e) => e.id).toSet().length, 8);

      final classes =
          plan.where((e) => e.repeat == NotificationRepeat.weekly).toList();
      expect(classes.length, 2);
      expect(classes[0].id, kClassNotificationIdBase);
      expect(classes[0].title, 'Umalis ka na');
      expect(classes[0].body, '30 mins pa bago yung Math mo, 10:00 AM sa Room 101.');
      expect(classes[0].when, DateTime(2026, 11, 10, 9, 30));
      expect(classes[1].body, '30 mins pa bago yung Coding mo, 12:30 AM.');
      expect(classes[1].when, DateTime(2026, 11, 16, 0, 0));

      final assignments =
          plan.where((e) => e.payload == 'assignment').toList();
      expect(assignments.length, 1);
      expect(assignments[0].id, kAssignmentNotificationIdBase);
      expect(assignments[0].title, 'Assignment due tomorrow');
      expect(assignments[0].when, DateTime(2026, 11, 11, 8, 0));
      expect(assignments[0].repeat, NotificationRepeat.once);

      final school = plan.where((e) => e.payload == 'school').toList();
      expect(school.length, 3);
      // Sorted by time: holiday first, then foundation, then exam.
      expect(school[0].id, kSchoolNotificationIdBase);
      expect(school[0].title, 'No classes tomorrow');
      expect(school[0].when, DateTime(2026, 11, 10, 8, 0));
      expect(school[1].title, 'School event tomorrow');
      expect(school[1].when, DateTime(2026, 11, 13, 8, 0));
      expect(school[2].title, 'School event tomorrow');
      expect(school[2].when, DateTime(2026, 11, 15, 8, 0));

      final daily = plan.where((e) => e.payload == 'daily').toList();
      expect(daily.length, 1);
      expect(daily[0].id, kDailyLoginNotificationId);
      expect(daily[0].when, DateTime(2026, 11, 9, 8, 0));
      expect(daily[0].repeat, NotificationRepeat.daily);

      // The morning verse / quote: one-off for the next 7:00 AM.
      // Nov 10 is day 314 (even) -> the Daily Quote.
      final verse = plan.where((e) => e.payload == 'verse').toList();
      expect(verse.length, 1);
      expect(verse[0].id, kVerseNotificationId);
      expect(verse[0].title, 'Daily Quote');
      expect(verse[0].when, DateTime(2026, 11, 10, 7, 0));
      expect(verse[0].repeat, NotificationRepeat.once);
    });

    test('all toggles off: empty plan', () {
      final plan = buildNotificationPlan(
        subjects: [_subject()],
        assignments: [_assignment()],
        schoolEvents: [_event()],
        holidays: [(date: DateTime(2026, 11, 11), name: 'Test Holiday')],
        prefs: const NotificationPreferences(
          classReminders: false,
          quizReminders: false,
          assignmentReminders: false,
          schoolReminders: false,
          dailyLoginReminder: false,
          allowanceAlerts: false,
          streakReminder: false,
          verseMorning: false,
          chatReplies: false,
          reviewReplies: false,
        ),
        now: _now,
      );
      expect(plan, isEmpty);
    });

    test('multi-day subject gets one weekly entry per day', () {
      final plan = buildNotificationPlan(
        subjects: [_subject(days: const [1, 3, 5], startMin: 600)],
        assignments: const [],
        schoolEvents: const [],
        holidays: const [],
        prefs: const NotificationPreferences(
          assignmentReminders: false,
          schoolReminders: false,
          dailyLoginReminder: false,
          verseMorning: false,
        ),
        now: _now,
      );
      expect(plan.length, 3);
      expect(
        plan.map((e) => e.when).toList(),
        [
          DateTime(2026, 11, 9, 9, 30),
          DateTime(2026, 11, 11, 9, 30),
          DateTime(2026, 11, 13, 9, 30),
        ],
      );
      expect(
        plan.every((e) => e.repeat == NotificationRepeat.weekly),
        isTrue,
      );
    });

    test('no-classes school event is titled as no classes', () {
      final plan = buildNotificationPlan(
        subjects: const [],
        assignments: const [],
        schoolEvents: [
          _event(name: 'Intramurals', noClasses: true),
        ],
        holidays: const [],
        prefs: const NotificationPreferences(
          classReminders: false,
          assignmentReminders: false,
          dailyLoginReminder: false,
          verseMorning: false,
        ),
        now: _now,
      );
      expect(plan.length, 1);
      expect(plan[0].title, 'No classes tomorrow');
      expect(plan[0].body, contains('Intramurals'));
    });

    test('exam gets a quiz reminder the night before, not an assignment one',
        () {
      final plan = buildNotificationPlan(
        subjects: [_subject()],
        assignments: [_assignment(kind: 'exam', title: 'Midterm')],
        schoolEvents: const [],
        holidays: const [],
        prefs: const NotificationPreferences(
          classReminders: false,
          schoolReminders: false,
          dailyLoginReminder: false,
          verseMorning: false,
        ),
        now: _now,
      );
      expect(plan.length, 1);
      expect(plan[0].title, 'Exam bukas');
      expect(plan[0].payload, 'quiz');
      expect(plan[0].body, 'May exam ka bukas sa Math — mag-review ka na.');
      expect(plan[0].when, DateTime(2026, 11, 11, 20, 0));
      expect(plan[0].repeat, NotificationRepeat.once);
    });

    test('quiz reminder off means no exam entry', () {
      final plan = buildNotificationPlan(
        subjects: [_subject()],
        assignments: [_assignment(kind: 'exam', title: 'Midterm')],
        schoolEvents: const [],
        holidays: const [],
        prefs: const NotificationPreferences(
          classReminders: false,
          quizReminders: false,
          schoolReminders: false,
          dailyLoginReminder: false,
          verseMorning: false,
        ),
        now: _now,
      );
      expect(plan, isEmpty);
    });
  });

  group('class reminder body + commute', () {
    test('without commute data the body is schedule only', () {
      expect(
        classReminderBody(_subject(), null),
        '30 mins pa bago yung Math mo, 10:00 AM sa Room 101.',
      );
    });

    test('with commute data the body carries fare and trip time', () {
      expect(
        classReminderBody(
          _subject(),
          const CommuteInfo(
            destination: 'Vigan City',
            fare: 60,
            tripMinutes: 70,
          ),
        ),
        '30 mins pa bago yung Math mo, 10:00 AM sa Room 101. '
        'Bus fare ₱60, biyahe 1 hr 10 min.',
      );
    });

    test('real Cabugao to Vigan commute is ₱60, 70 minutes', () {
      final commute = resolveCommuteInfo('Vigan City');
      expect(commute.fare, 60);
      expect(commute.tripMinutes, 70);
    });

    test('unknown destination yields no fare or trip', () {
      final commute = resolveCommuteInfo('Nowhere');
      expect(commute.fare, isNull);
      expect(commute.tripMinutes, isNull);
      expect(
        classReminderBody(_subject(), commute),
        '30 mins pa bago yung Math mo, 10:00 AM sa Room 101.',
      );
    });
  });

  group('streak reminder', () {
    // Five-day streak ending Sunday Nov 8, 2026; today (Mon Nov 9)
    // is not checked in yet.
    List<CheckinRecord> fiveDayStreak() => [
          _checkin(DateTime(2026, 11, 4)),
          _checkin(DateTime(2026, 11, 5)),
          _checkin(DateTime(2026, 11, 6)),
          _checkin(DateTime(2026, 11, 7)),
          _checkin(DateTime(2026, 11, 8)),
        ];

    List<PlannedNotification> streakPlan(
      List<CheckinRecord> checkins, {
      NotificationPreferences prefs = const NotificationPreferences(
        classReminders: false,
        assignmentReminders: false,
        schoolReminders: false,
        dailyLoginReminder: false,
        verseMorning: false,
      ),
    }) =>
        buildNotificationPlan(
          subjects: const [],
          assignments: const [],
          schoolEvents: const [],
          holidays: const [],
          prefs: prefs,
          now: _now,
          checkins: checkins,
        ).where((e) => e.payload == 'streak').toList();

    test('fires at 7:15 AM with the next streak day', () {
      final entries = streakPlan(fiveDayStreak());
      expect(entries.length, 1);
      expect(entries[0].id, kStreakNotificationId);
      expect(entries[0].title, 'Streak mo, ingatan mo');
      expect(
        entries[0].body,
        'Day 6 ka na bukas — mag-sign in ka para hindi maputol yung streak mo.',
      );
      expect(entries[0].when, DateTime(2026, 11, 9, 7, 15));
      expect(entries[0].repeat, NotificationRepeat.once);
    });

    test('no entry once today is checked in', () {
      expect(
        streakPlan([...fiveDayStreak(), _checkin(DateTime(2026, 11, 9))]),
        isEmpty,
      );
    });

    test('no entry with no streak', () {
      expect(streakPlan(const []), isEmpty);
    });

    test('no entry when the toggle is off', () {
      expect(
        streakPlan(
          fiveDayStreak(),
          prefs: const NotificationPreferences(
            classReminders: false,
            assignmentReminders: false,
            schoolReminders: false,
            dailyLoginReminder: false,
            verseMorning: false,
            streakReminder: false,
          ),
        ),
        isEmpty,
      );
    });
  });

  group('morning verse / quote', () {
    test('odd day gives the verse, even day the quote', () {
      final verse = morningVerseFor(DateTime(2026, 11, 9));
      expect(verse.title, 'Verse of the day');
      expect(
        verse.body,
        contains(verseOfDay(DateTime(2026, 11, 9)).ref),
      );
      final quote = morningVerseFor(DateTime(2026, 11, 10));
      expect(quote.title, 'Daily Quote');
      expect(
        quote.body,
        contains(quoteOfDay(DateTime(2026, 11, 10)).author),
      );
    });

    test('next verse time is the next 7:00 AM', () {
      expect(nextVerseReminderTime(_now), DateTime(2026, 11, 10, 7, 0));
      expect(
        nextVerseReminderTime(DateTime(2026, 11, 9, 6, 0)),
        DateTime(2026, 11, 9, 7, 0),
      );
    });

    test('verse off means no verse entry', () {
      final plan = buildNotificationPlan(
        subjects: const [],
        assignments: const [],
        schoolEvents: const [],
        holidays: const [],
        prefs: const NotificationPreferences(
          classReminders: false,
          assignmentReminders: false,
          schoolReminders: false,
          dailyLoginReminder: false,
          verseMorning: false,
        ),
        now: _now,
      );
      expect(plan.where((e) => e.payload == 'verse'), isEmpty);
    });
  });

  group('allowance alert', () {
    test('no allowance data means no alert', () {
      expect(
        allowanceNeedsAlert(
          hasData: false,
          balance: -10,
          overBudgets: const [],
        ),
        isFalse,
      );
    });

    test('used-up balance alerts', () {
      expect(
        allowanceNeedsAlert(
          hasData: true,
          balance: 0,
          overBudgets: const [],
        ),
        isTrue,
      );
    });

    test('healthy balance with no over-budget category: no alert', () {
      expect(
        allowanceNeedsAlert(
          hasData: true,
          balance: 500,
          overBudgets: const [],
        ),
        isFalse,
      );
    });

    test('over-budget alerts even with a positive balance', () {
      expect(
        allowanceNeedsAlert(
          hasData: true,
          balance: 500,
          overBudgets: const [
            (category: 'Food', spent: 1200.0, limit: 1000.0),
          ],
        ),
        isTrue,
      );
      expect(
        allowanceAlertBody(
          balance: 500,
          overBudgets: const [
            (category: 'Food', spent: 1200.0, limit: 1000.0),
          ],
        ),
        contains('Food over budget: spent ₱1,200 of ₱1,000 this month.'),
      );
    });

    test('used-up balance schedules an 8:00 AM alert', () {
      final plan = buildNotificationPlan(
        subjects: const [],
        assignments: const [],
        schoolEvents: const [],
        holidays: const [],
        prefs: const NotificationPreferences(
          classReminders: false,
          assignmentReminders: false,
          schoolReminders: false,
          dailyLoginReminder: false,
          verseMorning: false,
        ),
        now: _now,
        allowanceBalance: -50,
      );
      final entries =
          plan.where((e) => e.payload == 'allowance').toList();
      expect(entries.length, 1);
      expect(entries[0].id, kAllowanceNotificationId);
      expect(entries[0].title, 'Allowance alert');
      expect(entries[0].body, contains('Naubos na ang allowance mo'));
      expect(entries[0].when, DateTime(2026, 11, 9, 8, 0));
      expect(entries[0].repeat, NotificationRepeat.once);
    });

    test('no balance passed means no alert entry', () {
      final plan = buildNotificationPlan(
        subjects: const [],
        assignments: const [],
        schoolEvents: const [],
        holidays: const [],
        prefs: const NotificationPreferences(),
        now: _now,
      );
      expect(plan.where((e) => e.payload == 'allowance'), isEmpty);
    });
  });

  group('notificationTargetForPayload', () {
    test('class, assignment and quiz open Schedule', () {
      expect(
        notificationTargetForPayload('class'),
        (tab: 0, screen: 'classes'),
      );
      expect(
        notificationTargetForPayload('assignment'),
        (tab: 0, screen: 'classes'),
      );
      expect(
        notificationTargetForPayload('quiz'),
        (tab: 0, screen: 'classes'),
      );
    });

    test('allowance opens Money, verse opens Bible', () {
      expect(
        notificationTargetForPayload('allowance'),
        (tab: 0, screen: 'allowance'),
      );
      expect(
        notificationTargetForPayload('verse'),
        (tab: 0, screen: 'bible'),
      );
    });

    test('chat opens the Account tab, the rest land on the hub', () {
      expect(
        notificationTargetForPayload('chat'),
        (tab: 5, screen: null),
      );
      expect(
        notificationTargetForPayload('daily'),
        (tab: 0, screen: null),
      );
      expect(
        notificationTargetForPayload('streak'),
        (tab: 0, screen: null),
      );
      expect(
        notificationTargetForPayload(null),
        (tab: 0, screen: null),
      );
      expect(
        notificationTargetForPayload('unknown'),
        (tab: 0, screen: null),
      );
    });
  });

  group('NotificationPreferencesStore', () {
    test('defaults are all on, 8:00 AM, and a save round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final store = NotificationPreferencesStore();
      expect(await store.load(), const NotificationPreferences());

      const saved = NotificationPreferences(
        classReminders: false,
        dailyLoginTime: TimeOfDay(hour: 7, minute: 30),
      );
      await store.save(saved);
      expect(await store.load(), saved);
    });
  });

  group('LocalNotificationService with a fake scheduler', () {
    test('refreshAll cancels, then schedules class + assignment + daily',
        () async {
      // Rebuild with the same seeded data so the fake is observable.
      SharedPreferences.setMockInitialValues({
        StudentStorage.subjectsKey: jsonEncode([
          _subject(days: const [2], startMin: 600).toJson(),
        ]),
        StudentStorage.assignmentsKey: jsonEncode([
          _assignment(due: DateTime(2026, 11, 12)).toJson(),
        ]),
      });
      final scheduler = FakeNotificationScheduler();
      final observable =
          LocalNotificationService(scheduler: scheduler);
      await observable.initialize();
      await observable.refreshAll(now: _now);

      expect(scheduler.cancelAllCount, 1);
      // The three seeded entries, plus the real built-in UNP school
      // events and Philippine holidays inside the 60-day window —
      // the exact count depends on the real calendar data, so only
      // the seeded entries are pinned here.
      expect(scheduler.scheduled.length, greaterThanOrEqualTo(3));
      final byId = {for (final s in scheduler.scheduled) s.id: s};
      expect(byId[kClassNotificationIdBase]!.repeat,
          NotificationRepeat.weekly);
      expect(byId[kClassNotificationIdBase]!.scheduledDate,
          DateTime(2026, 11, 10, 9, 30));
      expect(byId[kAssignmentNotificationIdBase]!.repeat,
          NotificationRepeat.once);
      expect(byId[kAssignmentNotificationIdBase]!.scheduledDate,
          DateTime(2026, 11, 11, 8, 0));
      expect(byId[kDailyLoginNotificationId]!.repeat,
          NotificationRepeat.daily);
      expect(byId[kDailyLoginNotificationId]!.scheduledDate,
          DateTime(2026, 11, 9, 8, 0));
      expect(scheduler.scheduled.every((s) => s.exact), isTrue);
    });

    test('refreshAll before initialize schedules nothing', () async {
      SharedPreferences.setMockInitialValues({});
      final scheduler = FakeNotificationScheduler();
      final service = LocalNotificationService(scheduler: scheduler);
      await service.refreshAll(now: _now);
      expect(scheduler.cancelAllCount, 0);
      expect(scheduler.scheduled, isEmpty);
    });

    test('inexact alarms when exact alarms are not allowed', () async {
      SharedPreferences.setMockInitialValues({
        StudentStorage.subjectsKey: jsonEncode([
          _subject(days: const [2], startMin: 600).toJson(),
        ]),
        StudentStorage.assignmentsKey: jsonEncode([]),
      });
      final scheduler = FakeNotificationScheduler()
        ..canScheduleExactValue = false;
      final service = LocalNotificationService(scheduler: scheduler);
      await service.initialize();
      await service.refreshAll(now: _now);
      expect(scheduler.scheduled, isNotEmpty);
      expect(scheduler.scheduled.every((s) => !s.exact), isTrue);
    });

    test('a failing schedule never throws', () async {
      SharedPreferences.setMockInitialValues({
        StudentStorage.subjectsKey: jsonEncode([
          _subject(days: const [2], startMin: 600).toJson(),
        ]),
        StudentStorage.assignmentsKey: jsonEncode([]),
      });
      final scheduler = FakeNotificationScheduler()..throwOnSchedule = true;
      final service = LocalNotificationService(scheduler: scheduler);
      await service.initialize();
      await service.refreshAll(now: _now);
      expect(scheduler.cancelAllCount, 1);
    });

    test('sendTestNotification shows id 9999; false before initialize',
        () async {
      SharedPreferences.setMockInitialValues({});
      final scheduler = FakeNotificationScheduler();
      final service = LocalNotificationService(scheduler: scheduler);
      expect(await service.sendTestNotification(), isFalse);
      expect(scheduler.shown, isEmpty);

      await service.initialize();
      expect(await service.sendTestNotification(), isTrue);
      expect(scheduler.shown.length, 1);
      expect(scheduler.shown[0].id, kTestNotificationId);
    });

    test('checkReplyNotifications without Firebase never throws', () async {
      SharedPreferences.setMockInitialValues({});
      final scheduler = FakeNotificationScheduler();
      final service = LocalNotificationService(scheduler: scheduler);
      await service.initialize();
      // No Firebase app in tests: the check degrades to nothing.
      await service.checkReplyNotifications(uid: 'uid-1');
      expect(scheduler.shown, isEmpty);
    });

    test('checkReplyNotifications before initialize does nothing', () async {
      SharedPreferences.setMockInitialValues({});
      final scheduler = FakeNotificationScheduler();
      final service = LocalNotificationService(scheduler: scheduler);
      await service.checkReplyNotifications(uid: 'uid-1');
      expect(scheduler.shown, isEmpty);
    });

    test('requestExactAlarms asks the scheduler', () async {
      SharedPreferences.setMockInitialValues({});
      final scheduler = FakeNotificationScheduler()
        ..canScheduleExactValue = false;
      final service = LocalNotificationService(scheduler: scheduler);
      await service.initialize();
      await service.requestExactAlarms();
      expect(scheduler.requestExactCount, 1);
    });
  });

  group('NotificationSettingsScreen', () {
    Future<FakeNotificationScheduler> pumpScreen(
      WidgetTester tester, {
      NotificationPermissionStatus permission =
          NotificationPermissionStatus.granted,
      bool exactAlarms = true,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final scheduler = FakeNotificationScheduler()
        ..canScheduleExactValue = exactAlarms;
      final service = LocalNotificationService(scheduler: scheduler);
      await service.initialize();
      // A phone-sized surface, so the whole settings screen fits
      // without scrolling (the account tests use the same size).
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          // The screen sits inside the shell's Scaffold in the real
          // app; the Scaffold here gives the snackbar a home.
          home: Scaffold(
            body: NotificationSettingsScreen(
              permissionService: FakePermissionService(initial: permission),
              notificationService: service,
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return scheduler;
    }

    testWidgets('shows the ten toggles on by default + the 8:00 AM time',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      expect(find.text('Notification Settings'), findsOneWidget);
      expect(find.byKey(const Key('class-reminders-toggle')), findsOneWidget);
      expect(
        find.byKey(const Key('quiz-exam-reminders-toggle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assignment-reminders-toggle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('allowance-alerts-toggle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('streak-reminder-toggle')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('verse-morning-toggle')), findsOneWidget);
      expect(
        find.byKey(const Key('school-reminders-toggle')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('daily-login-toggle')), findsOneWidget);
      expect(find.byKey(const Key('chat-replies-toggle')), findsOneWidget);
      expect(find.byKey(const Key('review-replies-toggle')), findsOneWidget);
      expect(find.byKey(const Key('daily-login-time-row')), findsOneWidget);
      expect(find.text('8:00 AM'), findsOneWidget);
      expect(find.text('Allowed'), findsWidgets);
    });

    testWidgets('turning a toggle off saves it and re-runs the schedule',
        (WidgetTester tester) async {
      final scheduler = await pumpScreen(tester);
      final before = scheduler.scheduled.length;
      await tester.tap(find.byKey(const Key('class-reminders-toggle')));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('byahetayo_notif_class_reminders'), isFalse);
      // The refresh ran again: cancel + a fresh schedule.
      expect(scheduler.cancelAllCount, greaterThan(0));
      expect(scheduler.scheduled.length, greaterThan(before));
      // With classes off, no weekly entry is scheduled.
      expect(
        scheduler.scheduled
            .where((s) => s.repeat == NotificationRepeat.weekly),
        isEmpty,
      );
    });

    testWidgets('daily login time row opens the time picker',
        (WidgetTester tester) async {
      final scheduler = await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('daily-login-time-row')));
      await tester.pumpAndSettle();
      expect(find.text('Select time'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // Confirming the (unchanged) time still re-runs the schedule.
      expect(scheduler.cancelAllCount, greaterThan(0));
    });

    testWidgets('exact-alarms card appears when exact alarms are off',
        (WidgetTester tester) async {
      final scheduler = await pumpScreen(tester, exactAlarms: false);
      expect(find.byKey(const Key('allow-exact-alarms-button')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('allow-exact-alarms-button')));
      await tester.pumpAndSettle();
      expect(scheduler.requestExactCount, 1);
    });

    testWidgets('test button sends a notification when allowed',
        (WidgetTester tester) async {
      final scheduler = await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('send-test-notification-button')));
      await tester.pumpAndSettle();
      expect(scheduler.shown.length, 1);
      expect(scheduler.shown[0].id, kTestNotificationId);
    });

    testWidgets('test button refuses when notifications are not allowed',
        (WidgetTester tester) async {
      final scheduler = await pumpScreen(
        tester,
        permission: NotificationPermissionStatus.denied,
      );
      await tester.tap(find.byKey(const Key('send-test-notification-button')));
      // Top popup (was a SnackBar): assert while it is still up —
      // pumpAndSettle would fast-forward past its 5 seconds.
      await tester.pump(const Duration(milliseconds: 500));
      expect(scheduler.shown, isEmpty);
      expect(find.text('Allow notifications first.'), findsOneWidget);
    });

    testWidgets('back button calls onBack', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final scheduler = FakeNotificationScheduler();
      final service = LocalNotificationService(scheduler: scheduler);
      await service.initialize();
      var backCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationSettingsScreen(
              permissionService: FakePermissionService(
                  initial: NotificationPermissionStatus.granted),
              notificationService: service,
              onBack: () => backCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back to Account'));
      expect(backCalled, isTrue);
    });
  });
}
