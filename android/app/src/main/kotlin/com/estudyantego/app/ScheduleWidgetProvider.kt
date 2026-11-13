package com.estudyantego.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import java.time.LocalDateTime

/**
 * Schedule home screen widget — small 4x2 "Next Class" (Android
 * only). Approved preview v2 (Nov 11, 2026).
 *
 * Shows the quick glance: whether there are classes today, and
 * the next class coming up (code + name, day/date, time range,
 * room, "COMING UP / Tomorrow at 9:00 AM"), plus the Google
 * Calendar section — each synced Google Calendar event with its
 * white G badge and its name only (see ScheduleWidgetData for
 * why the name only). Tapping the widget opens the app's Classes
 * screen (the `homewidget://classes` URI; the app root listens
 * for it and pushes ClassesScreen when the dashboard is showing).
 *
 * DATA: reads the `schedule_widget_data` JSON the Dart side
 * (ScheduleWidgetService) pushes — the student's REAL stored
 * schedule (Manual / Files scan / Google sync), never a hardcoded
 * schedule — and derives today / next class from it on every
 * update, so the widget stays right across days even when the
 * app was never opened. No instructor names anywhere (the pushed
 * JSON carries none).
 *
 * RemoteViews rules (Nov 11 Bible widget fix): the layout uses
 * only RemoteViews-allowed views (LinearLayout, TextView,
 * ImageView), no plain View, no clipToOutline, no full-size
 * photo src — the only src is the E logo (@drawable/launch_image).
 */
class ScheduleWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val data = ScheduleWidgetData.parse(
            widgetData.getString(ScheduleWidgetData.DATA_KEY, null),
        )
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.schedule_widget).apply {
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse(ScheduleWidgetData.CLASSES_URI),
                    ),
                )

                val today = LocalDate.now()
                val now = LocalDateTime.now()
                val subjects = data?.subjects.orEmpty()
                val todays = ScheduleWidgetData.classesOnDay(
                    subjects,
                    today.dayOfWeek.value,
                )
                val next = ScheduleWidgetData.nextClass(subjects, now)

                // Today line: "No classes today" on a free day
                // (the preview's Wednesday), "Classes today"
                // otherwise, with the weekday + class count below.
                if (todays.isEmpty()) {
                    setTextViewText(R.id.widget_today_title, "No classes today")
                    setTextViewText(
                        R.id.widget_today_sub,
                        "${ScheduleWidgetData.weekdayShort(today.dayOfWeek.value)} " +
                            "is a free day in your schedule.",
                    )
                } else {
                    setTextViewText(R.id.widget_today_title, "Classes today")
                    setTextViewText(
                        R.id.widget_today_sub,
                        "${ScheduleWidgetData.weekdayShort(today.dayOfWeek.value)} · " +
                            "${todays.size} " +
                            if (todays.size == 1) "class" else "classes",
                    )
                }

                // Day progress: classes finished so far today.
                val nowMin = now.hour * 60 + now.minute
                val doneToday = todays.count { it.endMin <= nowMin }
                if (todays.isEmpty()) {
                    setViewVisibility(R.id.widget_progress, View.GONE)
                } else {
                    setViewVisibility(R.id.widget_progress, View.VISIBLE)
                    setTextViewText(
                        R.id.widget_progress_label,
                        "$doneToday of ${todays.size} done",
                    )
                    setProgressBar(
                        R.id.widget_progress_bar,
                        100,
                        doneToday * 100 / todays.size,
                        false,
                    )
                }

                // Next class card (hidden when there is no next
                // class); the empty state takes its place instead.
                if (next != null) {
                    val (subject, date, _) = next
                    setViewVisibility(R.id.widget_next_card, View.VISIBLE)
                    setViewVisibility(R.id.widget_empty, View.GONE)
                    setTextViewText(
                        R.id.widget_next_label,
                        "NEXT CLASS · ${subject.displayCode()}",
                    )
                    setTextViewText(R.id.widget_next_name, subject.name)
                    setTextViewText(
                        R.id.widget_next_date,
                        ScheduleWidgetData.nextClassDateLine(date),
                    )
                    val time = subject.timeRange() +
                        if (subject.room.isEmpty()) "" else " · ${subject.room}"
                    setTextViewText(R.id.widget_next_time, time)
                    setTextViewText(
                        R.id.widget_next_when,
                        ScheduleWidgetData.comingUpLabel(
                            date,
                            today,
                            subject.startMin,
                        ),
                    )
                } else {
                    setViewVisibility(R.id.widget_next_card, View.GONE)
                    setViewVisibility(R.id.widget_empty, View.VISIBLE)
                    if (subjects.isEmpty()) {
                        setTextViewText(
                            R.id.widget_empty_title,
                            ScheduleWidgetData.EMPTY_TITLE,
                        )
                        setTextViewText(
                            R.id.widget_empty_sub,
                            ScheduleWidgetData.EMPTY_SUBTITLE,
                        )
                    } else {
                        setTextViewText(
                            R.id.widget_empty_title,
                            "No upcoming classes.",
                        )
                        setTextViewText(
                            R.id.widget_empty_sub,
                            "Your subjects have no meeting days.",
                        )
                    }
                }

                // Google Calendar section: name + white G badge
                // only (approved preview v2). Hidden when there
                // are no synced events.
                val googleEvents = data?.googleEvents.orEmpty()
                if (googleEvents.isEmpty()) {
                    setViewVisibility(R.id.widget_google_section, View.GONE)
                } else {
                    setViewVisibility(R.id.widget_google_section, View.VISIBLE)
                    for (i in 0 until ScheduleWidgetData.MAX_GOOGLE_EVENTS) {
                        val rowId = context.resources.getIdentifier(
                            "widget_google_$i",
                            "id",
                            context.packageName,
                        )
                        val titleId = context.resources.getIdentifier(
                            "widget_google_title_$i",
                            "id",
                            context.packageName,
                        )
                        if (rowId == 0 || titleId == 0) continue
                        if (i < googleEvents.size) {
                            setViewVisibility(rowId, View.VISIBLE)
                            setTextViewText(titleId, googleEvents[i].title)
                        } else {
                            setViewVisibility(rowId, View.GONE)
                        }
                    }
                    if (googleEvents.size > ScheduleWidgetData.MAX_GOOGLE_EVENTS) {
                        setViewVisibility(R.id.widget_google_more, View.VISIBLE)
                        setTextViewText(
                            R.id.widget_google_more,
                            "+${googleEvents.size - ScheduleWidgetData.MAX_GOOGLE_EVENTS} " +
                                "more in Google Calendar",
                        )
                    } else {
                        setViewVisibility(R.id.widget_google_more, View.GONE)
                    }
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
