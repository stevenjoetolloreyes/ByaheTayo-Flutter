// Local (on-device) notifications — EstudyanteGO Flutter app.
//
// LOCAL ONLY. No FCM, no Cloud Functions, no server, no inbox:
// every notification below is scheduled on the phone itself with
// [flutter_local_notifications] and fires from the device clock.
//
// What the system covers (Steven, Nov 8: "Local muna (reminders +
// daily login)"):
//
// * Class reminders — 15 minutes before each stored class starts,
//   from the Classes & Timetable data (weekly repeat per class day).
// * Assignment & exam reminders — 8:00 AM the day before an
//   assignment or exam is due.
// * School reminders — 8:00 AM the day before a school event or a
//   Philippine holiday (no-classes days included).
// * Daily login reminder — once a day at a time the user picks
//   (default 8:00 AM), for the sign-in points streak.
//
// The four toggles are REAL preferences (SharedPreferences) with
// these keys — see [NotificationPreferencesStore]. They default to
// ON, matching the pre-checked look of the old settings page.
//
// NOTE on the old settings page: the Nov 5 Account redesign showed
// four pre-checked toggles (Push Notifications, Email Notifications,
// Account Alerts, Student Announcements) — but those exist only in
// the Gemini preview HTML; the real app's Account tab only ever had
// a Notification Settings row showing the OS permission status and
// opening a permission dialog. None of the four preview toggles can
// be wired to anything local (all four are server-side: push, email,
// announcements), so this build CREATES the settings screen with
// four real local toggles instead: class, assignment, school, and
// daily login reminders. Friend requests, community likes/comments
// and announcements still need the Full push system (FCM + Cloud
// Functions) — NOT approved, NOT built here.
//
// Scheduling model: [buildNotificationPlan] is pure — it turns the
// stored data + preferences into a [PlannedNotification] list.
// [LocalNotificationService.refreshAll] loads the data, builds the
// plan, cancels everything previously scheduled, and re-schedules
// the plan. It runs at app start and whenever class/assignment
// data or the preferences change (see
// [localNotificationRefreshRequest]).
//
// Exact alarms: on Android 12+ the scheduler asks for
// SCHEDULE_EXACT_ALARM so reminders fire on time; when the user
// has not allowed exact alarms, the plugin falls back to inexact
// scheduling (reminders may arrive a few minutes late) and the
// settings screen says so. Nothing here ever throws: a failed
// refresh leaves the previously scheduled notifications in place.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'ph_holidays.dart';
import 'school_events.dart';
import 'student/student_data.dart';

/// Notification id for the daily login reminder.
const int kDailyLoginNotificationId = 1;

/// Notification id base for class reminders (one id per class day).
const int kClassNotificationIdBase = 1000;

/// Notification id base for assignment / exam reminders.
const int kAssignmentNotificationIdBase = 2000;

/// Notification id base for school-event / holiday reminders.
const int kSchoolNotificationIdBase = 3000;

/// Notification id for the test notification from the settings screen.
const int kTestNotificationId = 9999;

/// How many minutes before a class starts its reminder fires.
const int kClassReminderLeadMinutes = 15;

/// How far ahead school reminders are planned (days).
const int kSchoolReminderWindowDays = 60;

/// Hour of the day-before reminder for assignments, exams, school
/// events and holidays (8:00 AM).
const int kSchoolReminderHour = 8;

/// Android notification channel for all local reminders.
const String kNotificationChannelId = 'estudyantego_reminders';
const String kNotificationChannelName = 'Reminders';

/// Small white icon shown on the notification (vector drawable).
const String kNotificationIcon = '@drawable/ic_notification';

/// Bumped whenever class/assignment data or notification
/// preferences change, so the app shell can re-run the schedule
/// refresh. Same [ValueNotifier] pattern as `busStopsChanged` and
/// `customRoutesChanged`.
final ValueNotifier<int> localNotificationRefreshRequest =
    ValueNotifier<int>(0);

/// Asks the app shell to re-run the notification schedule refresh.
void requestLocalNotificationRefresh() {
  localNotificationRefreshRequest.value++;
}

// ---------------------------------------------------------------------------
// Preferences
// ---------------------------------------------------------------------------

const String _kClassKey = 'byahetayo_notif_class_reminders';
const String _kAssignmentKey = 'byahetayo_notif_assignment_reminders';
const String _kSchoolKey = 'byahetayo_notif_school_reminders';
const String _kDailyKey = 'byahetayo_notif_daily_login';
const String _kDailyHourKey = 'byahetayo_notif_daily_login_hour';
const String _kDailyMinuteKey = 'byahetayo_notif_daily_login_minute';

/// The four real local-notification preferences, plus the daily
/// login reminder time. All four toggles default to ON.
class NotificationPreferences {
  const NotificationPreferences({
    this.classReminders = true,
    this.assignmentReminders = true,
    this.schoolReminders = true,
    this.dailyLoginReminder = true,
    this.dailyLoginTime = const TimeOfDay(hour: 8, minute: 0),
  });

  /// 15 minutes before each class starts.
  final bool classReminders;

  /// 8:00 AM the day before an assignment or exam is due.
  final bool assignmentReminders;

  /// 8:00 AM the day before a school event or a holiday.
  final bool schoolReminders;

  /// Once a day, at [dailyLoginTime].
  final bool dailyLoginReminder;

  /// Time of the daily login reminder. Default 8:00 AM.
  final TimeOfDay dailyLoginTime;

  NotificationPreferences copyWith({
    bool? classReminders,
    bool? assignmentReminders,
    bool? schoolReminders,
    bool? dailyLoginReminder,
    TimeOfDay? dailyLoginTime,
  }) {
    return NotificationPreferences(
      classReminders: classReminders ?? this.classReminders,
      assignmentReminders: assignmentReminders ?? this.assignmentReminders,
      schoolReminders: schoolReminders ?? this.schoolReminders,
      dailyLoginReminder: dailyLoginReminder ?? this.dailyLoginReminder,
      dailyLoginTime: dailyLoginTime ?? this.dailyLoginTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationPreferences &&
      classReminders == other.classReminders &&
      assignmentReminders == other.assignmentReminders &&
      schoolReminders == other.schoolReminders &&
      dailyLoginReminder == other.dailyLoginReminder &&
      dailyLoginTime == other.dailyLoginTime;

  @override
  int get hashCode => Object.hash(
        classReminders,
        assignmentReminders,
        schoolReminders,
        dailyLoginReminder,
        dailyLoginTime,
      );
}

/// Loads and saves [NotificationPreferences] in SharedPreferences.
/// Never throws: a failed load returns the defaults, a failed save
/// is swallowed.
class NotificationPreferencesStore {
  Future<NotificationPreferences> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return NotificationPreferences(
        classReminders: prefs.getBool(_kClassKey) ?? true,
        assignmentReminders: prefs.getBool(_kAssignmentKey) ?? true,
        schoolReminders: prefs.getBool(_kSchoolKey) ?? true,
        dailyLoginReminder: prefs.getBool(_kDailyKey) ?? true,
        dailyLoginTime: TimeOfDay(
          hour: (prefs.getInt(_kDailyHourKey) ?? 8).clamp(0, 23),
          minute: (prefs.getInt(_kDailyMinuteKey) ?? 0).clamp(0, 59),
        ),
      );
    } catch (_) {
      return const NotificationPreferences();
    }
  }

  Future<void> save(NotificationPreferences prefs) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kClassKey, prefs.classReminders);
      await sp.setBool(_kAssignmentKey, prefs.assignmentReminders);
      await sp.setBool(_kSchoolKey, prefs.schoolReminders);
      await sp.setBool(_kDailyKey, prefs.dailyLoginReminder);
      await sp.setInt(_kDailyHourKey, prefs.dailyLoginTime.hour);
      await sp.setInt(_kDailyMinuteKey, prefs.dailyLoginTime.minute);
    } catch (_) {
      // A failed save just leaves the previous preferences in place.
    }
  }
}

// ---------------------------------------------------------------------------
// Pure planning helpers
// ---------------------------------------------------------------------------

/// How a planned notification repeats.
enum NotificationRepeat {
  /// Fires once, at [PlannedNotification.when].
  once,

  /// Fires every day at the same time.
  daily,

  /// Fires every week on the same weekday at the same time.
  weekly,
}

/// One notification the plan wants scheduled.
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    required this.repeat,
    this.payload,
  });

  final int id;
  final String title;
  final String body;
  final DateTime when;
  final NotificationRepeat repeat;
  final String? payload;
}

/// Next occurrence of [weekday] (1 = Monday .. 7 = Sunday) at
/// [minutesOfDay] minutes after midnight, strictly after [now].
/// Returns null when the weekday is out of range.
DateTime? nextWeeklyOccurrence({
  required int weekday,
  required int minutesOfDay,
  required DateTime now,
}) {
  if (weekday < DateTime.monday || weekday > DateTime.sunday) return null;
  final clamped = minutesOfDay.clamp(0, 24 * 60 - 1);
  final hour = clamped ~/ 60;
  final minute = clamped % 60;
  for (var offset = 0; offset < 8; offset++) {
    final day = DateTime(now.year, now.month, now.day)
        .add(Duration(days: offset));
    if (day.weekday != weekday) continue;
    final candidate = DateTime(day.year, day.month, day.day, hour, minute);
    if (candidate.isAfter(now)) return candidate;
  }
  return null;
}

/// The next class reminder for [subject]: [kClassReminderLeadMinutes]
/// before its next scheduled start, strictly after [now].
/// Returns null when the subject has no days or no future class.
DateTime? nextClassReminderTime(Subject subject, DateTime now,
    {int leadMinutes = kClassReminderLeadMinutes}) {
  DateTime? earliest;
  for (final weekday in subject.days) {
    final when = nextWeeklyOccurrence(
      weekday: weekday,
      minutesOfDay: subject.startMin - leadMinutes,
      now: now,
    );
    if (when == null) continue;
    if (earliest == null || when.isBefore(earliest)) earliest = when;
  }
  return earliest;
}

/// The next daily login reminder at [time]: today at that time when
/// it is still ahead, otherwise tomorrow at that time.
DateTime nextDailyReminderTime(TimeOfDay time, DateTime now) {
  final today = DateTime(now.year, now.month, now.day, time.hour, time.minute);
  if (today.isAfter(now)) return today;
  return today.add(const Duration(days: 1));
}

/// The assignment / exam reminder for [item]: [kSchoolReminderHour]:00
/// on the day before it is due. Returns null when the item is done
/// or the reminder time is not after [now].
DateTime? assignmentReminderTime(AssignmentItem item, DateTime now) {
  if (item.done) return null;
  final reminder = DateTime(
    item.due.year,
    item.due.month,
    item.due.day - 1,
    kSchoolReminderHour,
  );
  return reminder.isAfter(now) ? reminder : null;
}

/// The school-event / holiday reminder for an event starting at
/// [eventStart]: [kSchoolReminderHour]:00 on the day before it
/// starts. Returns null when that time is not after [now].
DateTime? schoolReminderTime(DateTime eventStart, DateTime now) {
  final reminder = DateTime(
    eventStart.year,
    eventStart.month,
    eventStart.day - 1,
    kSchoolReminderHour,
  );
  return reminder.isAfter(now) ? reminder : null;
}

String _subjectNameFor(List<Subject> subjects, String subjectId) {
  for (final subject in subjects) {
    if (subject.id == subjectId) return subject.name;
  }
  return 'Subject';
}

/// Builds the full notification plan from the stored data.
///
/// * One weekly class reminder per (subject, weekday), 15 minutes
///   before the class starts. A subject meeting on several days
///   gets one entry per day — a single weekly repeat only covers
///   one weekday.
/// * One one-off assignment / exam reminder per open item, 8:00 AM
///   the day before it is due. Done items are skipped.
/// * One one-off school reminder per school event and per holiday
///   inside the [kSchoolReminderWindowDays] window, 8:00 AM the
///   day before it starts.
/// * One daily login reminder at the preferred time.
/// * A category whose toggle is off contributes nothing.
/// * Entries whose time is not after [now] are skipped.
///
/// Ids are assigned in sorted order (by time, then name) within
/// each category, so the same inputs always produce the same ids.
List<PlannedNotification> buildNotificationPlan({
  required List<Subject> subjects,
  required List<AssignmentItem> assignments,
  required List<SchoolEvent> schoolEvents,
  required List<({DateTime date, String name})> holidays,
  required NotificationPreferences prefs,
  required DateTime now,
}) {
  final plan = <PlannedNotification>[];

  if (prefs.classReminders) {
    final entries = <({Subject subject, int weekday, DateTime when})>[];
    for (final subject in subjects) {
      final days = subject.days.toSet().toList()..sort();
      for (final weekday in days) {
        final when = nextWeeklyOccurrence(
          weekday: weekday,
          minutesOfDay: subject.startMin - kClassReminderLeadMinutes,
          now: now,
        );
        if (when != null) {
          entries.add((subject: subject, weekday: weekday, when: when));
        }
      }
    }
    entries.sort((a, b) {
      final byTime = a.when.compareTo(b.when);
      if (byTime != 0) return byTime;
      final byName = a.subject.name.compareTo(b.subject.name);
      return byName != 0 ? byName : a.weekday.compareTo(b.weekday);
    });
    for (var i = 0; i < entries.length; i++) {
      final subject = entries[i].subject;
      final room = subject.room.trim();
      final time = formatMinutes(subject.startMin);
      plan.add(PlannedNotification(
        id: kClassNotificationIdBase + i,
        title: 'Class in 15 minutes',
        body: room.isEmpty
            ? '${subject.name} · $time'
            : '${subject.name} · $room · $time',
        when: entries[i].when,
        repeat: NotificationRepeat.weekly,
        payload: 'class',
      ));
    }
  }

  if (prefs.assignmentReminders) {
    final open = assignments.where((item) => !item.done).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    var index = 0;
    for (final item in open) {
      final when = assignmentReminderTime(item, now);
      if (when == null) continue;
      final subjectName = _subjectNameFor(subjects, item.subjectId);
      plan.add(PlannedNotification(
        id: kAssignmentNotificationIdBase + index++,
        title: item.kind == 'exam' ? 'Exam tomorrow' : 'Assignment due tomorrow',
        body: '$subjectName · ${item.title} — due ${formatDate(item.due)}',
        when: when,
        repeat: NotificationRepeat.once,
        payload: 'assignment',
      ));
    }
  }

  if (prefs.schoolReminders) {
    final entries = <({String title, String body, DateTime when})>[];
    for (final event in schoolEvents) {
      final when = schoolReminderTime(event.start, now);
      if (when == null) continue;
      entries.add((
        title: event.noClasses ? 'No classes tomorrow' : 'School event tomorrow',
        body: '${event.name} · ${formatEventRange(event)}',
        when: when,
      ));
    }
    for (final holiday in holidays) {
      final when = schoolReminderTime(holiday.date, now);
      if (when == null) continue;
      entries.add((
        title: 'No classes tomorrow',
        body: '${holiday.name} · ${formatDate(holiday.date)}',
        when: when,
      ));
    }
    entries.sort((a, b) => a.when.compareTo(b.when));
    for (var i = 0; i < entries.length; i++) {
      plan.add(PlannedNotification(
        id: kSchoolNotificationIdBase + i,
        title: entries[i].title,
        body: entries[i].body,
        when: entries[i].when,
        repeat: NotificationRepeat.once,
        payload: 'school',
      ));
    }
  }

  if (prefs.dailyLoginReminder) {
    plan.add(PlannedNotification(
      id: kDailyLoginNotificationId,
      title: 'Daily check-in reminder',
      body: "Open EstudyanteGO for today's sign-in.",
      when: nextDailyReminderTime(prefs.dailyLoginTime, now),
      repeat: NotificationRepeat.daily,
      payload: 'daily',
    ));
  }

  return plan;
}

// ---------------------------------------------------------------------------
// Scheduler abstraction (the real plugin, and a seam for tests)
// ---------------------------------------------------------------------------

/// The small surface of the notification plugin the service uses.
/// The production implementation is [PluginNotificationScheduler];
/// tests inject a fake.
abstract class NotificationScheduler {
  Future<bool> initialize({required String androidIcon});

  Future<void> show({
    required int id,
    String? title,
    String? body,
    String? payload,
  });

  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required DateTime scheduledDate,
    String? payload,
    required NotificationRepeat repeat,
    required bool exact,
  });

  Future<void> cancelAll();

  /// True when exact alarms are allowed (Android 12+). On other
  /// platforms there is no exact-alarm permission, so true.
  Future<bool> get canScheduleExact;

  /// Opens the system exact-alarm settings (Android 12+). No-op
  /// elsewhere.
  Future<void> requestExactAlarms();
}

/// The real [NotificationScheduler], backed by
/// flutter_local_notifications.
class PluginNotificationScheduler implements NotificationScheduler {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  @override
  Future<bool> initialize({required String androidIcon}) async {
    tz.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      // tz.local stays at its default; scheduled times are still
      // computed from the device's local clock.
    }
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    final settings = InitializationSettings(
      android: AndroidInitializationSettings(androidIcon),
      iOS: darwin,
      macOS: darwin,
    );
    try {
      return await _plugin.initialize(settings: settings) ?? false;
    } catch (_) {
      return false;
    }
  }

  NotificationDetails get _details => NotificationDetails(
        android: AndroidNotificationDetails(
          kNotificationChannelId,
          kNotificationChannelName,
          channelDescription:
              'Class, assignment, school and daily login reminders.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: kNotificationIcon,
        ),
        iOS: const DarwinNotificationDetails(),
      );

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    String? payload,
  }) =>
      _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _details,
        payload: payload,
      );

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
    final DateTimeComponents? match;
    switch (repeat) {
      case NotificationRepeat.weekly:
        match = DateTimeComponents.dayOfWeekAndTime;
      case NotificationRepeat.daily:
        match = DateTimeComponents.time;
      case NotificationRepeat.once:
        match = null;
    }
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails: _details,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: match,
      payload: payload,
    );
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<bool> get canScheduleExact async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> requestExactAlarms() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestExactAlarmsPermission();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// The local notification service.
///
/// Wiring: the app shell creates one in `main.dart`, calls
/// [initialize] once, then [refreshAll] at startup and whenever
/// [localNotificationRefreshRequest] is bumped (class/assignment
/// data or preferences changed).
class LocalNotificationService {
  LocalNotificationService({
    NotificationScheduler? scheduler,
    NotificationPreferencesStore? preferencesStore,
  })  : _scheduler = scheduler ?? PluginNotificationScheduler(),
        _preferencesStore =
            preferencesStore ?? NotificationPreferencesStore();

  final NotificationScheduler _scheduler;
  final NotificationPreferencesStore _preferencesStore;

  bool _initialized = false;
  bool _exactAlarms = false;

  /// True once [initialize] has succeeded.
  bool get isInitialized => _initialized;

  /// True when exact alarms are allowed (Android 12+). False before
  /// [initialize] and on platforms without the permission.
  Future<bool> get canScheduleExact async {
    if (!_initialized) return false;
    try {
      return await _scheduler.canScheduleExact;
    } catch (_) {
      return false;
    }
  }

  /// Initializes the plugin and the timezone database. Safe to call
  /// more than once; never throws.
  Future<void> initialize() async {
    try {
      _initialized = await _scheduler.initialize(androidIcon: kNotificationIcon);
      if (_initialized) {
        try {
          _exactAlarms = await _scheduler.canScheduleExact;
        } catch (_) {
          _exactAlarms = false;
        }
      }
    } catch (_) {
      _initialized = false;
    }
  }

  /// Rebuilds the whole schedule from the stored data: loads the
  /// preferences, subjects, assignments and school, builds the plan
  /// for the next [kSchoolReminderWindowDays] days, cancels
  /// everything previously scheduled, and schedules the plan.
  /// [now] is injectable for tests; production passes nothing.
  /// Never throws: a failed refresh leaves the previously scheduled
  /// notifications in place.
  Future<void> refreshAll({DateTime? now}) async {
    if (!_initialized) return;
    try {
      final at = now ?? DateTime.now();
      final prefs = await _preferencesStore.load();

      final subjects = <Subject>[];
      for (final map in await StudentStorage.loadList(
          StudentStorage.subjectsKey)) {
        try {
          subjects.add(Subject.fromJson(map));
        } catch (_) {}
      }

      final items = <AssignmentItem>[];
      for (final map in await StudentStorage.loadList(
          StudentStorage.assignmentsKey)) {
        try {
          items.add(AssignmentItem.fromJson(map));
        } catch (_) {}
      }

      String? school;
      try {
        school = (await SharedPreferences.getInstance())
            .getString('byahetayo_profile_school');
      } catch (_) {
        school = null;
      }

      final events = <SchoolEvent>[];
      final holidays = <({DateTime date, String name})>[];
      final end = at.add(const Duration(days: kSchoolReminderWindowDays));
      var cursor = DateTime(at.year, at.month, 1);
      final lastMonth = DateTime(end.year, end.month, 1);
      while (!cursor.isAfter(lastMonth)) {
        events.addAll(
            schoolEventsInMonth(school, cursor.year, cursor.month));
        for (final holiday
            in philippineHolidaysInMonth(cursor.year, cursor.month)) {
          holidays.add((
            date: DateTime(cursor.year, cursor.month, holiday.day),
            name: holiday.name,
          ));
        }
        cursor = DateTime(cursor.year, cursor.month + 1, 1);
      }

      final plan = buildNotificationPlan(
        subjects: subjects,
        assignments: items,
        schoolEvents: events,
        holidays: holidays,
        prefs: prefs,
        now: at,
      );

      await _scheduler.cancelAll();
      for (final entry in plan) {
        await _scheduler.zonedSchedule(
          id: entry.id,
          title: entry.title,
          body: entry.body,
          scheduledDate: entry.when,
          payload: entry.payload,
          repeat: entry.repeat,
          exact: _exactAlarms,
        );
      }
    } catch (_) {
      // A failed refresh leaves the previously scheduled
      // notifications in place.
    }
  }

  /// Sends one immediate test notification. Returns false when the
  /// service is not initialized or the send fails.
  Future<bool> sendTestNotification() async {
    if (!_initialized) return false;
    try {
      await _scheduler.show(
        id: kTestNotificationId,
        title: 'EstudyanteGO test',
        body: 'Local notifications are working.',
        payload: 'test',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system exact-alarm settings (Android 12+) so the
  /// user can allow on-time reminders, then re-reads the permission.
  /// No-op on other platforms. Never throws.
  Future<void> requestExactAlarms() async {
    try {
      await _scheduler.requestExactAlarms();
    } catch (_) {}
    try {
      _exactAlarms = await _scheduler.canScheduleExact;
    } catch (_) {}
  }
}
