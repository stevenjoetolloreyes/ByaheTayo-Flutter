// Local (on-device) notifications — EstudyanteGO Flutter app.
//
// LOCAL ONLY. No FCM, no Cloud Functions, no server, no inbox:
// every notification below is scheduled on the phone itself with
// [flutter_local_notifications] and fires from the device clock.
//
// What the system covers (Smart Notifications v1, approved preview
// Nov 11, 2026 — the Nov 8 local build, extended):
//
// * Class reminders — 30 minutes before each stored class starts,
//   from the Classes & Timetable data (weekly repeat per class day).
//   The body carries the student's real commute: "Umalis ka na —
//   30 mins pa bago yung CT102 mo, 10:00 AM sa CC105. Bus fare
//   ₱60, biyahe 1 hr 10 mins." The fare comes from the verified
//   [knownBusFares] table and the trip time from the app's own
//   estimateTripMinutes model, for the student's saved commute
//   destination (Cabugao → destination, default Vigan City — the
//   Commute screen's own default). When no fare or trip is known
//   for that pair, the body falls back to schedule only.
// * Quiz / exam reminders — 8:00 PM the night before an exam
//   (Classes data, kind 'exam'). Saved quizzes carry no date, so
//   there is nothing date-based to remind from Flashcards state.
// * Assignment reminders — 8:00 AM the day before an assignment
//   is due (kind 'assignment' only; exams moved to the quiz/exam
//   reminder above).
// * School reminders — 8:00 AM the day before a school event or a
//   Philippine holiday (no-classes days included).
// * Daily login reminder — once a day at a time the user picks
//   (default 8:00 AM), for the sign-in points streak.
// * 7-day sign-in streak — 7:15 AM when the streak would break
//   today (a real streak exists and today is not checked in yet).
// * Bible Verse / Daily Quote morning — 7:00 AM with the next
//   morning's verse or quote, alternating by day of year, from the
//   bundled verse/quote lists ([verseOfDay] / [quoteOfDay]). It is
//   a one-off for the next morning (not a daily repeat), because a
//   repeating notification would keep showing the same verse.
// * Allowance / budget alerts — 8:00 AM while the allowance is
//   used up (balance <= 0) or a monthly category budget is over,
//   from the real Money / Allowance transactions and limits. Only
//   when allowance data exists at all.
// * Chat Support replies + App Reviews replies — checked when the
//   app opens ([checkReplyNotifications]): an unread admin reply
//   in Firestore fires one immediate local notification. There is
//   NO push server, so a reply that arrives while the app has been
//   closed for days only notifies on the next app open. The bell
//   badge + Notifications sheet still show them in-app.
//
// The toggles are REAL preferences (SharedPreferences) with
// these keys — see [NotificationPreferencesStore]. They default to
// ON, matching the pre-checked look of the old settings page.
//
// The toggles are REAL preferences (SharedPreferences) with
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
// real local toggles instead: class, quiz/exam, assignment, school,
// daily login, streak, allowance, verse/quote, chat replies and
// review replies. Friend requests, community likes/comments
// and announcements still need the Full push system (FCM + Cloud
// Functions) — NOT approved, NOT built here.
//
// Tapping a notification opens the app straight to the right
// place ([notificationTargetForPayload]): a class / assignment /
// quiz notification opens Schedule (Classes), allowance opens the
// Allowance screen, the morning verse opens the Bible screen,
// Chat Support opens the Account tab. The shell wires the tap
// through [LocalNotificationService.initialize]'s [onTap].
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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'fares_tab.dart' as fares;
import 'map_tab.dart' as maps;
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

/// Notification id base for quiz / exam reminders.
const int kQuizNotificationIdBase = 4000;

/// Notification id for the 7-day streak reminder.
const int kStreakNotificationId = 7000;

/// Notification id for the Bible Verse / Daily Quote morning reminder.
const int kVerseNotificationId = 7100;

/// Notification id for the allowance / budget alert.
const int kAllowanceNotificationId = 7200;

/// Notification id base for immediate App Reviews reply notifications.
const int kReviewReplyNotificationIdBase = 8000;

/// Notification id base for immediate Chat Support reply notifications.
const int kChatReplyNotificationIdBase = 9000;

/// Notification id for the test notification from the settings screen.
const int kTestNotificationId = 9999;

/// How many minutes before a class starts its reminder fires.
/// Preview v1: 30 minutes ("Umalis ka na — 30 mins pa…").
const int kClassReminderLeadMinutes = 30;

/// Hour of the evening-before reminder for exams (8:00 PM).
const int kQuizReminderHour = 20;

/// Time of the streak reminder: 7:15 AM, when the streak is at risk.
const int kStreakReminderHour = 7;
const int kStreakReminderMinute = 15;

/// Time of the morning verse / quote: 7:00 AM.
const int kVerseReminderHour = 7;
const int kVerseReminderMinute = 0;

/// Hour of the allowance / budget alert (8:00 AM).
const int kAllowanceAlertHour = 8;

/// The student's home hub for the commute in class reminders.
/// The Commute screen models every saved route as "Cabugao → `<fav>`".
const String kCommuteOrigin = 'Cabugao';

/// Default commute destination when the student saved no favorite
/// destination — the Commute screen's own default pick.
const String kCommuteDefaultDestination = 'Vigan City';

/// How far ahead school reminders are planned (days).
const int kSchoolReminderWindowDays = 60;

/// Hour of the day-before reminder for assignments, exams, school
/// events and holidays (8:00 AM).
const int kSchoolReminderHour = 8;

/// Android notification channel for all local reminders.
const String kNotificationChannelId = 'estudyantego_reminders';
const String kNotificationChannelName = 'Reminders';

/// Fixed notification id for the login alert (a new sign-in from
/// another device). Reusing one id replaces the previous alert
/// instead of stacking one per sign-in.
const int kLoginAlertNotificationId = 9001;

/// Payload carried by the login-alert notification tap.
const String kLoginAlertPayload = 'security';

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
const String _kQuizKey = 'byahetayo_notif_quiz_reminders';
const String _kAssignmentKey = 'byahetayo_notif_assignment_reminders';
const String _kSchoolKey = 'byahetayo_notif_school_reminders';
const String _kDailyKey = 'byahetayo_notif_daily_login';
const String _kDailyHourKey = 'byahetayo_notif_daily_login_hour';
const String _kDailyMinuteKey = 'byahetayo_notif_daily_login_minute';
const String _kAllowanceKey = 'byahetayo_notif_allowance_alerts';
const String _kStreakKey = 'byahetayo_notif_streak_reminder';
const String _kVerseKey = 'byahetayo_notif_verse_morning';
const String _kChatRepliesKey = 'byahetayo_notif_chat_replies';
const String _kReviewRepliesKey = 'byahetayo_notif_review_replies';

/// SharedPreferences keys for the reply notifications already
/// delivered as local notifications (one entry per Firestore doc /
/// conversation, so a reply is never announced twice).
const String _kNotifiedReviewRepliesKey =
    'byahetayo_notified_review_replies';
const String _kNotifiedChatRepliesKey = 'byahetayo_notified_chat_replies';

/// The real local-notification preferences, plus the daily
/// login reminder time. All toggles default to ON.
class NotificationPreferences {
  const NotificationPreferences({
    this.classReminders = true,
    this.quizReminders = true,
    this.assignmentReminders = true,
    this.schoolReminders = true,
    this.dailyLoginReminder = true,
    this.dailyLoginTime = const TimeOfDay(hour: 8, minute: 0),
    this.allowanceAlerts = true,
    this.streakReminder = true,
    this.verseMorning = true,
    this.chatReplies = true,
    this.reviewReplies = true,
  });

  /// 30 minutes before each class starts, with fare + trip time.
  final bool classReminders;

  /// 8:00 PM the night before an exam.
  final bool quizReminders;

  /// 8:00 AM the day before an assignment is due.
  final bool assignmentReminders;

  /// 8:00 AM the day before a school event or a holiday.
  final bool schoolReminders;

  /// Once a day, at [dailyLoginTime].
  final bool dailyLoginReminder;

  /// Time of the daily login reminder. Default 8:00 AM.
  final TimeOfDay dailyLoginTime;

  /// 8:00 AM while the allowance is used up or a monthly budget
  /// is over.
  final bool allowanceAlerts;

  /// 7:15 AM when the sign-in streak would break today.
  final bool streakReminder;

  /// 7:00 AM with the next morning's verse or quote.
  final bool verseMorning;

  /// Immediate local notification on an unread Chat Support reply.
  final bool chatReplies;

  /// Immediate local notification on an unread App Review reply.
  final bool reviewReplies;

  NotificationPreferences copyWith({
    bool? classReminders,
    bool? quizReminders,
    bool? assignmentReminders,
    bool? schoolReminders,
    bool? dailyLoginReminder,
    TimeOfDay? dailyLoginTime,
    bool? allowanceAlerts,
    bool? streakReminder,
    bool? verseMorning,
    bool? chatReplies,
    bool? reviewReplies,
  }) {
    return NotificationPreferences(
      classReminders: classReminders ?? this.classReminders,
      quizReminders: quizReminders ?? this.quizReminders,
      assignmentReminders: assignmentReminders ?? this.assignmentReminders,
      schoolReminders: schoolReminders ?? this.schoolReminders,
      dailyLoginReminder: dailyLoginReminder ?? this.dailyLoginReminder,
      dailyLoginTime: dailyLoginTime ?? this.dailyLoginTime,
      allowanceAlerts: allowanceAlerts ?? this.allowanceAlerts,
      streakReminder: streakReminder ?? this.streakReminder,
      verseMorning: verseMorning ?? this.verseMorning,
      chatReplies: chatReplies ?? this.chatReplies,
      reviewReplies: reviewReplies ?? this.reviewReplies,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationPreferences &&
      classReminders == other.classReminders &&
      quizReminders == other.quizReminders &&
      assignmentReminders == other.assignmentReminders &&
      schoolReminders == other.schoolReminders &&
      dailyLoginReminder == other.dailyLoginReminder &&
      dailyLoginTime == other.dailyLoginTime &&
      allowanceAlerts == other.allowanceAlerts &&
      streakReminder == other.streakReminder &&
      verseMorning == other.verseMorning &&
      chatReplies == other.chatReplies &&
      reviewReplies == other.reviewReplies;

  @override
  int get hashCode => Object.hash(
        classReminders,
        quizReminders,
        assignmentReminders,
        schoolReminders,
        dailyLoginReminder,
        dailyLoginTime,
        allowanceAlerts,
        streakReminder,
        verseMorning,
        chatReplies,
        reviewReplies,
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
        quizReminders: prefs.getBool(_kQuizKey) ?? true,
        assignmentReminders: prefs.getBool(_kAssignmentKey) ?? true,
        schoolReminders: prefs.getBool(_kSchoolKey) ?? true,
        dailyLoginReminder: prefs.getBool(_kDailyKey) ?? true,
        dailyLoginTime: TimeOfDay(
          hour: (prefs.getInt(_kDailyHourKey) ?? 8).clamp(0, 23),
          minute: (prefs.getInt(_kDailyMinuteKey) ?? 0).clamp(0, 59),
        ),
        allowanceAlerts: prefs.getBool(_kAllowanceKey) ?? true,
        streakReminder: prefs.getBool(_kStreakKey) ?? true,
        verseMorning: prefs.getBool(_kVerseKey) ?? true,
        chatReplies: prefs.getBool(_kChatRepliesKey) ?? true,
        reviewReplies: prefs.getBool(_kReviewRepliesKey) ?? true,
      );
    } catch (_) {
      return const NotificationPreferences();
    }
  }

  Future<void> save(NotificationPreferences prefs) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kClassKey, prefs.classReminders);
      await sp.setBool(_kQuizKey, prefs.quizReminders);
      await sp.setBool(_kAssignmentKey, prefs.assignmentReminders);
      await sp.setBool(_kSchoolKey, prefs.schoolReminders);
      await sp.setBool(_kDailyKey, prefs.dailyLoginReminder);
      await sp.setInt(_kDailyHourKey, prefs.dailyLoginTime.hour);
      await sp.setInt(_kDailyMinuteKey, prefs.dailyLoginTime.minute);
      await sp.setBool(_kAllowanceKey, prefs.allowanceAlerts);
      await sp.setBool(_kStreakKey, prefs.streakReminder);
      await sp.setBool(_kVerseKey, prefs.verseMorning);
      await sp.setBool(_kChatRepliesKey, prefs.chatReplies);
      await sp.setBool(_kReviewRepliesKey, prefs.reviewReplies);
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

/// The quiz / exam reminder for [item]: [kQuizReminderHour]:00 on
/// the night before an exam is due. Returns null when the item is
/// not an exam, is done, or the reminder time is not after [now].
DateTime? quizReminderTime(AssignmentItem item, DateTime now) {
  if (item.kind != 'exam' || item.done) return null;
  final reminder = DateTime(
    item.due.year,
    item.due.month,
    item.due.day - 1,
    kQuizReminderHour,
  );
  return reminder.isAfter(now) ? reminder : null;
}

/// The next streak reminder: today at 7:15 AM when it is still
/// ahead, otherwise tomorrow at 7:15 AM.
DateTime nextStreakReminderTime(DateTime now) {
  final today = DateTime(
    now.year,
    now.month,
    now.day,
    kStreakReminderHour,
    kStreakReminderMinute,
  );
  if (today.isAfter(now)) return today;
  return today.add(const Duration(days: 1));
}

/// "Day 6 ka na bukas…" — [streak] is the streak ending yesterday
/// (today not checked in yet); signing in today makes it day
/// [streak] + 1.
String streakReminderBody(int streak) =>
    'Day ${streak + 1} ka na bukas — mag-sign in ka para hindi maputol yung streak mo.';

/// The next morning verse / quote: today at 7:00 AM when it is
/// still ahead, otherwise tomorrow at 7:00 AM.
DateTime nextVerseReminderTime(DateTime now) {
  final today = DateTime(
    now.year,
    now.month,
    now.day,
    kVerseReminderHour,
    kVerseReminderMinute,
  );
  if (today.isAfter(now)) return today;
  return today.add(const Duration(days: 1));
}

/// The next allowance alert: today at 8:00 AM when it is still
/// ahead, otherwise tomorrow at 8:00 AM.
DateTime nextAllowanceAlertTime(DateTime now) {
  final today = DateTime(
    now.year,
    now.month,
    now.day,
    kAllowanceAlertHour,
  );
  if (today.isAfter(now)) return today;
  return today.add(const Duration(days: 1));
}

String _truncate(String value, int maxLength) {
  final trimmed = value.trim();
  if (trimmed.length <= maxLength) return trimmed;
  return '${trimmed.substring(0, maxLength).trimRight()}…';
}

/// The morning notification for [date]: the bundled verse on odd
/// days of the year, the bundled quote on even days — both real,
/// both from the same lists the Bible screen and the Daily Quotes
/// widget read.
({String title, String body}) morningVerseFor(DateTime date) {
  if (dayOfYear(date).isOdd) {
    final verse = verseOfDay(date);
    return (
      title: 'Verse of the day',
      body: '${verse.ref} — ${_truncate(verse.text, 180)}',
    );
  }
  final quote = quoteOfDay(date);
  return (
    title: 'Daily Quote',
    body: '"${_truncate(quote.text, 160)}" — ${quote.author}',
  );
}

/// True when the allowance state deserves an alert: real allowance
/// data exists ([hasData]) and the balance is used up or a monthly
/// category budget is over.
bool allowanceNeedsAlert({
  required bool hasData,
  required double balance,
  required List<({String category, double spent, double limit})>
      overBudgets,
}) =>
    hasData && (balance <= 0 || overBudgets.isNotEmpty);

/// The allowance alert body for the real state: the used-up balance
/// first, then the first over-budget category (same wording as the
/// Money screen's own over-budget banner).
String allowanceAlertBody({
  required double balance,
  required List<({String category, double spent, double limit})>
      overBudgets,
}) {
  final parts = <String>[];
  if (balance <= 0) {
    parts.add('Naubos na ang allowance mo — balance mo ${peso(balance)}.');
  }
  if (overBudgets.isNotEmpty) {
    final first = overBudgets.first;
    parts.add(
      '${first.category} over budget: spent ${peso(first.spent)} of ${peso(first.limit)} this month.',
    );
  }
  return parts.join(' ');
}

/// The student's commute for a class reminder: the verified bus
/// fare and the estimated trip time for Cabugao → [destination].
/// Either value is null when the app has no real data for the pair.
class CommuteInfo {
  const CommuteInfo({
    required this.destination,
    this.fare,
    this.tripMinutes,
  });

  final String destination;

  /// Verified fare in pesos, or null when unverified.
  final int? fare;

  /// Estimated trip minutes, or null when the hubs are unknown.
  final int? tripMinutes;
}

fares.Hub? _hubByName(String name) {
  for (final hub in fares.hubs) {
    if (hub.name == name) return hub;
  }
  return null;
}

/// Resolves the commute for [destination] from the app's real data:
/// the fare from the verified [knownBusFares] table and the trip
/// time from the app's estimateTripMinutes model (same mountain /
/// same-region rules as the Map preview). Never invents a fare or
/// a time: unknown pairs yield nulls.
CommuteInfo resolveCommuteInfo(String destination) {
  final fare = maps.knownBusFare(kCommuteOrigin, destination);
  final originHub = _hubByName(kCommuteOrigin);
  final destHub = _hubByName(destination);
  int? tripMinutes;
  if (originHub != null && destHub != null) {
    final mountain =
        maps.isMountainHub(destHub) || maps.isMountainHub(originHub);
    tripMinutes = maps.estimateTripMinutes(
      roadKm: maps.roadKmBetween(
        originHub.lat,
        originHub.lng,
        destHub.lat,
        destHub.lng,
      ),
      mountain: mountain,
      sameRegion: originHub.region == destHub.region,
      mode: maps.TravelMode.transit,
    );
  }
  return CommuteInfo(
    destination: destination,
    fare: fare,
    tripMinutes: tripMinutes,
  );
}

/// The class reminder body (preview v1): "30 mins pa bago yung
/// CT102 mo, 10:00 AM sa CC105. Bus fare ₱60, biyahe 1 hr 10 min."
/// The fare / trip parts appear only when the commute knows them.
String classReminderBody(Subject subject, CommuteInfo? commute) {
  final room = subject.room.trim();
  final time = formatMinutes(subject.startMin);
  final base = room.isEmpty
      ? '30 mins pa bago yung ${subject.name} mo, $time.'
      : '30 mins pa bago yung ${subject.name} mo, $time sa $room.';
  if (commute == null) return base;
  final fare = commute.fare;
  final trip = commute.tripMinutes;
  if (fare == null && trip == null) return base;
  final parts = <String>[];
  if (fare != null) parts.add('Bus fare ${peso(fare.toDouble())}');
  if (trip != null) parts.add('biyahe ${maps.formatTripTime(trip)}');
  return '$base ${parts.join(', ')}.';
}

/// Deep-link target for a notification [payload]: the tab index to
/// open and the Student-hub screen to push once there ('classes',
/// 'bible', 'allowance', or null for the tab alone).
({int tab, String? screen}) notificationTargetForPayload(String? payload) {
  switch (payload) {
    case 'class':
    case 'assignment':
    case 'quiz':
      return (tab: 0, screen: 'classes');
    case 'allowance':
      return (tab: 0, screen: 'allowance');
    case 'verse':
      return (tab: 0, screen: 'bible');
    case 'chat':
      // Chat Support lives on the Account tab.
      return (tab: 5, screen: null);
    default:
      // daily, streak, school, review, test and unknown payloads
      // land on the Student hub (sign-in card, verse card, bell).
      return (tab: 0, screen: null);
  }
}

String _subjectNameFor(List<Subject> subjects, String subjectId) {
  for (final subject in subjects) {
    if (subject.id == subjectId) return subject.name;
  }
  return 'Subject';
}

/// Builds the full notification plan from the stored data.
///
/// * One weekly class reminder per (subject, weekday), 30 minutes
///   before the class starts. A subject meeting on several days
///   gets one entry per day — a single weekly repeat only covers
///   one weekday.
/// * One one-off quiz / exam reminder per open exam, 8:00 PM the
///   night before it is due.
/// * One one-off assignment reminder per open assignment, 8:00 AM
///   the day before it is due. Done items are skipped.
/// * One one-off school reminder per school event and per holiday
///   inside the [kSchoolReminderWindowDays] window, 8:00 AM the
///   day before it starts.
/// * One daily login reminder at the preferred time.
/// * One one-off streak reminder at 7:15 AM when a real streak
///   would break today (streak >= 1, today not checked in yet).
/// * One one-off morning verse / quote at 7:00 AM, for the next
///   morning's date.
/// * One one-off allowance alert at 8:00 AM while the allowance
///   is used up or a monthly budget is over (only when allowance
///   data exists).
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
  CommuteInfo? commute,
  List<CheckinRecord> checkins = const [],
  double? allowanceBalance,
  List<({String category, double spent, double limit})> overBudgets =
      const [],
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
      plan.add(PlannedNotification(
        id: kClassNotificationIdBase + i,
        title: 'Umalis ka na',
        body: classReminderBody(subject, commute),
        when: entries[i].when,
        repeat: NotificationRepeat.weekly,
        payload: 'class',
      ));
    }
  }

  if (prefs.quizReminders) {
    final exams = assignments
        .where((item) => item.kind == 'exam' && !item.done)
        .toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    var index = 0;
    for (final item in exams) {
      final when = quizReminderTime(item, now);
      if (when == null) continue;
      final subjectName = _subjectNameFor(subjects, item.subjectId);
      plan.add(PlannedNotification(
        id: kQuizNotificationIdBase + index++,
        title: 'Exam bukas',
        body: 'May exam ka bukas sa $subjectName — mag-review ka na.',
        when: when,
        repeat: NotificationRepeat.once,
        payload: 'quiz',
      ));
    }
  }

  if (prefs.assignmentReminders) {
    final open = assignments
        .where((item) => item.kind != 'exam' && !item.done)
        .toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    var index = 0;
    for (final item in open) {
      final when = assignmentReminderTime(item, now);
      if (when == null) continue;
      final subjectName = _subjectNameFor(subjects, item.subjectId);
      plan.add(PlannedNotification(
        id: kAssignmentNotificationIdBase + index++,
        title: 'Assignment due tomorrow',
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

  if (prefs.streakReminder && checkins.isNotEmpty) {
    final streak = checkinStreak(checkins, now);
    if (streak >= 1 && !hasCheckedInToday(checkins, now)) {
      plan.add(PlannedNotification(
        id: kStreakNotificationId,
        title: 'Streak mo, ingatan mo',
        body: streakReminderBody(streak),
        when: nextStreakReminderTime(now),
        repeat: NotificationRepeat.once,
        payload: 'streak',
      ));
    }
  }

  if (prefs.verseMorning) {
    final when = nextVerseReminderTime(now);
    final morning = morningVerseFor(when);
    plan.add(PlannedNotification(
      id: kVerseNotificationId,
      title: morning.title,
      body: morning.body,
      when: when,
      repeat: NotificationRepeat.once,
      payload: 'verse',
    ));
  }

  if (prefs.allowanceAlerts &&
      allowanceNeedsAlert(
        hasData: allowanceBalance != null,
        balance: allowanceBalance ?? 0,
        overBudgets: overBudgets,
      )) {
    plan.add(PlannedNotification(
      id: kAllowanceNotificationId,
      title: 'Allowance alert',
      body: allowanceAlertBody(
        balance: allowanceBalance ?? 0,
        overBudgets: overBudgets,
      ),
      when: nextAllowanceAlertTime(now),
      repeat: NotificationRepeat.once,
      payload: 'allowance',
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
  Future<bool> initialize({
    required String androidIcon,
    void Function(String? payload)? onTap,
  });

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
  Future<bool> initialize({
    required String androidIcon,
    void Function(String? payload)? onTap,
  }) async {
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
      final ok = await _plugin.initialize(
            settings: settings,
            onDidReceiveNotificationResponse: (response) =>
                onTap?.call(response.payload),
          ) ??
          false;
      if (ok && onTap != null) {
        // Cold start: the app was launched by tapping a
        // notification while it was closed.
        try {
          final launch = await _plugin.getNotificationAppLaunchDetails();
          if (launch?.didNotificationLaunchApp == true) {
            onTap(launch?.notificationResponse?.payload);
          }
        } catch (_) {}
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  NotificationDetails get _details => NotificationDetails(
        android: AndroidNotificationDetails(
          kNotificationChannelId,
          kNotificationChannelName,
          channelDescription:
              'Class, quiz, assignment, school, streak, verse and allowance reminders.',
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
  /// more than once; never throws. [onTap] fires with the tapped
  /// notification's payload (foreground tap and cold start).
  Future<void> initialize({void Function(String? payload)? onTap}) async {
    try {
      _initialized = await _scheduler.initialize(
        androidIcon: kNotificationIcon,
        onTap: onTap,
      );
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

  /// Shows the login-alert notification immediately ('New sign-in
  /// to your EstudyanteGO account'). Used by the Session Manager
  /// when another device signs in; tapping it opens the app (the
  /// in-app 'Was this you?' dialog is shown by the shell). No-op
  /// before [initialize] and never throws.
  Future<void> showLoginAlert({
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    try {
      await _scheduler.show(
        id: kLoginAlertNotificationId,
        title: title,
        body: body,
        payload: kLoginAlertPayload,
      );
    } catch (_) {}
  }

  /// Rebuilds the whole schedule from the stored data: loads the
  /// preferences, subjects, assignments, check-ins, allowance and
  /// commute, builds the plan for the next
  /// [kSchoolReminderWindowDays] days, cancels everything previously
  /// scheduled, and schedules the plan.
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

      final checkinRecords = <CheckinRecord>[];
      for (final map in await StudentStorage.loadList(
          StudentStorage.checkinsKey)) {
        try {
          checkinRecords.add(CheckinRecord.fromJson(map));
        } catch (_) {}
      }

      // Allowance state for the budget alert: the balance and the
      // monthly per-category spend vs the user's own limits. No
      // transactions at all means no allowance data — no alert.
      final txns = <AllowanceTxn>[];
      for (final map in await StudentStorage.loadList(
          StudentStorage.txnsKey)) {
        try {
          txns.add(AllowanceTxn.fromJson(map));
        } catch (_) {}
      }
      double? allowanceBalanceValue;
      final overBudgets =
          <({String category, double spent, double limit})>[];
      if (txns.isNotEmpty) {
        allowanceBalanceValue = allowanceBalance(txns);
        final budgets = <BudgetLimit>[];
        for (final map in await StudentStorage.loadList(
            StudentStorage.budgetsKey)) {
          try {
            budgets.add(BudgetLimit.fromJson(map));
          } catch (_) {}
        }
        for (final budget in budgets) {
          var spent = 0.0;
          for (final txn in txns) {
            if (txn.kind == 'expense' &&
                txn.category == budget.category &&
                txn.date.year == at.year &&
                txn.date.month == at.month) {
              spent += txn.amount;
            }
          }
          if (spent > budget.limit) {
            overBudgets.add((
              category: budget.category,
              spent: spent,
              limit: budget.limit,
            ));
          }
        }
      }

      // The student's commute for the class reminder fare + trip:
      // the first saved favorite destination, else the Commute
      // screen's own default (Vigan City).
      var destination = kCommuteDefaultDestination;
      try {
        final favs =
            await StudentStorage.loadStrings(StudentStorage.commuteFavsKey);
        final first = favs.firstWhere(
          (f) => f.trim().isNotEmpty,
          orElse: () => '',
        );
        if (first.trim().isNotEmpty) destination = first.trim();
      } catch (_) {}
      final commute = resolveCommuteInfo(destination);

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
        commute: commute,
        checkins: checkinRecords,
        allowanceBalance: allowanceBalanceValue,
        overBudgets: overBudgets,
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

  /// Checks Firestore for unread admin replies (Chat Support +
  /// App Reviews) and fires one immediate local notification per
  /// reply not yet announced. Runs when the app opens — there is
  /// no push server, so a reply that arrives while the app has
  /// been closed only notifies on the next app open. Each reply is
  /// announced once (tracked in SharedPreferences). Single-where
  /// queries only, so no composite Firestore index is needed.
  /// Never throws: a missing collection, missing rules, offline,
  /// or an uninitialized Firebase just means no reply
  /// notifications. No-ops when the matching toggle is off.
  Future<void> checkReplyNotifications({required String uid}) async {
    if (!_initialized || uid.isEmpty) return;
    try {
      final prefs = await _preferencesStore.load();
      final sp = await SharedPreferences.getInstance();
      if (prefs.reviewReplies) {
        final notified =
            sp.getStringList(_kNotifiedReviewRepliesKey) ?? const [];
        final fresh = <String>[];
        final snap = await FirebaseFirestore.instance
            .collection('app_review_notifications')
            .where('userId', isEqualTo: uid)
            .get();
        final docs = snap.docs.toList()
          ..sort((a, b) {
            final aTime =
                (a.data()['createdAt'] as Timestamp?)?.toDate();
            final bTime =
                (b.data()['createdAt'] as Timestamp?)?.toDate();
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });
        var index = 0;
        for (final doc in docs) {
          if (doc.data()['read'] == true) continue;
          if (notified.contains(doc.id)) continue;
          final reply =
              (doc.data()['replyText'] as String? ?? '').trim();
          await _scheduler.show(
            id: kReviewReplyNotificationIdBase + index++,
            title: 'EstudyanteGO replied to your review.',
            body: reply.isEmpty
                ? 'Tap to read the reply.'
                : _truncate(reply, 160),
            payload: 'review',
          );
          fresh.add(doc.id);
        }
        if (fresh.isNotEmpty) {
          await sp.setStringList(
            _kNotifiedReviewRepliesKey,
            [...notified, ...fresh],
          );
        }
      }
      if (prefs.chatReplies) {
        final notified =
            sp.getStringList(_kNotifiedChatRepliesKey) ?? const [];
        final fresh = <String>[];
        final snap = await FirebaseFirestore.instance
            .collection('support_conversations')
            .where('studentUid', isEqualTo: uid)
            .get();
        final docs = snap.docs.toList()
          ..sort((a, b) {
            final aTime =
                (a.data()['lastMessageAt'] as Timestamp?)?.toDate();
            final bTime =
                (b.data()['lastMessageAt'] as Timestamp?)?.toDate();
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });
        var index = 0;
        for (final doc in docs) {
          final data = doc.data();
          final unread = data['unreadForStudent'];
          if (unread is! num || unread <= 0) continue;
          if (data['lastSender'] != 'admin') continue;
          final at = (data['lastMessageAt'] as Timestamp?)?.toDate();
          final key =
              '${doc.id}|${at?.millisecondsSinceEpoch ?? 0}';
          if (notified.contains(key)) continue;
          final lastMessage =
              (data['lastMessage'] as String? ?? '').trim();
          await _scheduler.show(
            id: kChatReplyNotificationIdBase + index++,
            title: 'Reply from Steven',
            body: lastMessage.isEmpty
                ? 'Tap to read the reply.'
                : _truncate(lastMessage, 160),
            payload: 'chat',
          );
          fresh.add(key);
        }
        if (fresh.isNotEmpty) {
          await sp.setStringList(
            _kNotifiedChatRepliesKey,
            [...notified, ...fresh],
          );
        }
      }
    } catch (_) {
      // No Firebase / no rules / offline: no reply notifications.
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
