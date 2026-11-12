package com.estudyantego.app

import java.time.LocalDate
import java.time.LocalDateTime
import org.json.JSONObject

/**
 * Schedule home screen widgets — shared data + derivation, used
 * by BOTH providers (ScheduleWidgetProvider 4x2 "Next Class" and
 * ScheduleWeekWidgetProvider 4x3 "This Week").
 *
 * DESIGN (mirrors the Bible Verse widget): the Dart side
 * (ScheduleWidgetService) pushes the FULL schedule as ONE JSON
 * blob under "schedule_widget_data" — the student's classes plus
 * the synced Google Calendar events — and these providers derive
 * today / next class / week rows from that stored list on every
 * update (updatePeriodMillis 30 min), so the widget stays right
 * across days even when the app was never opened. The Dart side
 * carries the SAME derivation (student_data.nextClass /
 * classesOnDay, ScheduleWidgetService.comingUpLabel /
 * nextUpLine); the two must agree, or the widget and the Classes
 * screen disagree about the next class.
 *
 * NO INSTRUCTOR NAMES (privacy rule, same as the landing page):
 * the pushed JSON carries code + name + days + times + room only
 * — Subject.teacher / GoogleCalendarEvent.teacher are stripped
 * by the Dart side at encode time, and nothing here reads a
 * teacher field even if an older payload carried one.
 *
 * GOOGLE CALENDAR (approved preview v2, Nov 11, 2026): the widget
 * shows each synced Google Calendar event with its white G badge
 * and its NAME only. The stored events carry a weekday, a time
 * range and a place, but the approved preview shows the name
 * only, so the widget follows the preview. HONEST NOTE: the four
 * events currently in the app (NSTP 1, Life and Works of Rizal,
 * Discrete Mathematics, Vigan) are the sample set seeded by
 * loadGoogleEvents; the first real Google Calendar sync replaces
 * them with the student's real Google Calendar events. Nothing
 * here invents an event, a time, a day or a place.
 *
 * Malformed or missing data is never a crash: parse() returns
 * null and the providers show the empty state ("No subjects
 * yet.") instead.
 */
object ScheduleWidgetData {

    /** SharedPreferences key (inside the home_widget store). */
    const val DATA_KEY = "schedule_widget_data"

    /** URI the providers launch with on tap; the app root opens
     * the Classes screen for it (see main.dart). */
    const val CLASSES_URI = "homewidget://classes"

    /** Empty state, same wording as the Dart side. */
    const val EMPTY_TITLE = "No subjects yet."
    const val EMPTY_SUBTITLE = "Add a subject to build your timetable."

    /** How many Google events the widget lists at most. */
    const val MAX_GOOGLE_EVENTS = 4

    /** How many entries a week day row shows at most. */
    const val MAX_ENTRIES_PER_DAY = 3

    /** One class as the widget understands it (no teacher). */
    data class WidgetSubject(
        val id: String,
        val code: String,
        val name: String,
        val days: List<Int>,
        val startMin: Int,
        val endMin: Int,
        val room: String,
        val color: Int,
    ) {
        /** "9:00–10:30 AM" — built from the stored minutes. The
         *  AM/PM suffix is shown once when both ends share it
         *  ("2:00–3:30 PM"); when the range crosses noon both
         *  suffixes stay ("11:00 AM–12:30 PM"). Must stay in sync
         *  with ScheduleWidgetSubject.timeRange in
         *  schedule_widget_service.dart. */
        fun timeRange(): String {
            val start = formatMinutes(startMin)
            val end = formatMinutes(endMin)
            val startSuffix = start.takeLast(2)
            val endSuffix = end.takeLast(2)
            if (startSuffix == endSuffix) {
                return "${start.dropLast(3)}–$end"
            }
            return "$start–$end"
        }

        /** "CT101" when the subject has a code, else its name. */
        fun displayCode(): String = code.ifEmpty { name }
    }

    /** One Google Calendar event as the widget understands it:
     * id + title only (see the file header). */
    data class WidgetGoogleEvent(
        val id: String,
        val title: String,
    )

    /** The whole schedule payload. */
    data class ScheduleData(
        val subjects: List<WidgetSubject>,
        val googleEvents: List<WidgetGoogleEvent>,
    )

    /**
     * Parses the pushed payload, or null when it is missing,
     * malformed, or not the expected shape. A single malformed
     * subject or event poisons the whole payload (like the Bible
     * widget's decodeVerses): the provider then shows the empty
     * state instead of a half schedule.
     */
    fun parse(raw: String?): ScheduleData? {
        if (raw.isNullOrBlank()) return null
        return try {
            val obj = JSONObject(raw)
            val subjectsJson = obj.getJSONArray("subjects")
            val googleJson = obj.getJSONArray("google")
            val subjects = ArrayList<WidgetSubject>()
            for (i in 0 until subjectsJson.length()) {
                val s = subjectsJson.getJSONObject(i)
                val daysJson = s.getJSONArray("days")
                val days = ArrayList<Int>()
                for (j in 0 until daysJson.length()) {
                    days.add(daysJson.getInt(j))
                }
                subjects.add(
                    WidgetSubject(
                        id = s.getString("id"),
                        code = s.getString("code"),
                        name = s.getString("name"),
                        days = days,
                        startMin = s.getInt("startMin"),
                        endMin = s.getInt("endMin"),
                        room = s.getString("room"),
                        color = s.getInt("color"),
                    ),
                )
            }
            val googleEvents = ArrayList<WidgetGoogleEvent>()
            for (i in 0 until googleJson.length()) {
                val g = googleJson.getJSONObject(i)
                googleEvents.add(
                    WidgetGoogleEvent(
                        id = g.getString("id"),
                        title = g.getString("title"),
                    ),
                )
            }
            ScheduleData(subjects = subjects, googleEvents = googleEvents)
        } catch (_: Exception) {
            null
        }
    }

    /**
     * The day's classes, time order. Mirrors
     * student_data.classesOnDay (Dart): a subject meets on a day
     * when the day is in its days list.
     */
    fun classesOnDay(
        subjects: List<WidgetSubject>,
        weekday: Int,
    ): List<WidgetSubject> =
        subjects.filter { it.days.contains(weekday) }
            .sortedBy { it.startMin }

    /**
     * Next upcoming class: later today first, then the next day
     * that has classes. Returns the subject, its date, and the
     * day offset from [now] (0 = today), or null when there are
     * no subjects with meeting days. Mirrors
     * student_data.nextClass (Dart) exactly: a class whose start
     * time has already passed today is skipped.
     */
    fun nextClass(
        subjects: List<WidgetSubject>,
        now: LocalDateTime,
    ): Triple<WidgetSubject, LocalDate, Int>? {
        if (subjects.isEmpty()) return null
        val nowMin = now.hour * 60 + now.minute
        for (offset in 0 until 7) {
            val day = now.toLocalDate().plusDays(offset.toLong())
            // LocalDate.dayOfWeek: Monday = 1 .. Sunday = 7, the
            // same numbering as DateTime.weekday in Dart.
            val todays = classesOnDay(subjects, day.dayOfWeek.value)
            for (subject in todays) {
                if (offset == 0 && subject.startMin <= nowMin) continue
                return Triple(subject, day, offset)
            }
        }
        return null
    }

    /** "9:00 AM" — mirrors student_data.formatMinutes (Dart). */
    fun formatMinutes(minutes: Int): String {
        val h = minutes / 60
        val m = minutes % 60
        val suffix = if (h >= 12) "PM" else "AM"
        var h12 = h % 12
        if (h12 == 0) h12 = 12
        return "$h12:${m.toString().padStart(2, '0')} $suffix"
    }

    /** "Mon" .. "Sun" for weekday 1..7. */
    fun weekdayShort(weekday: Int): String {
        val names = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
        return names[(weekday - 1).coerceIn(0, 6)]
    }

    /** "Thu, Nov 12" — the next-class date line in the preview. */
    fun nextClassDateLine(date: LocalDate): String {
        val months = listOf(
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        )
        return "${weekdayShort(date.dayOfWeek.value)}, " +
            "${months[date.monthValue - 1]} ${date.dayOfMonth}"
    }

    /**
     * The "COMING UP" line for the next class: "Today at 2:00
     * PM", "Tomorrow at 9:00 AM", "Thu at 9:00 AM". Mirrors
     * ScheduleWidgetService.comingUpLabel (Dart).
     */
    fun comingUpLabel(
        nextDate: LocalDate,
        now: LocalDate,
        startMin: Int,
    ): String {
        val offset = nextDate.toEpochDay() - now.toEpochDay()
        val whenText = when (offset) {
            0L -> "Today"
            1L -> "Tomorrow"
            else -> weekdayShort(nextDate.dayOfWeek.value)
        }
        return "$whenText at ${formatMinutes(startMin)}"
    }

    /**
     * The week footer line: "Next up: Thu · CSS101 · 9:00 AM ·
     * CC203", or null when there is no upcoming class. Mirrors
     * ScheduleWidgetService.nextUpLine (Dart).
     */
    fun nextUpLine(
        subjects: List<WidgetSubject>,
        now: LocalDateTime,
    ): String? {
        val next = nextClass(subjects, now) ?: return null
        val (subject, date, _) = next
        val room = if (subject.room.isEmpty()) "" else " · ${subject.room}"
        return "Next up: ${weekdayShort(date.dayOfWeek.value)} · " +
            "${subject.displayCode()} · ${formatMinutes(subject.startMin)}$room"
    }
}
