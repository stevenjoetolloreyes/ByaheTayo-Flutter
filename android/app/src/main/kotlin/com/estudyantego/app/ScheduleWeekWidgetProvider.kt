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
 * Schedule home screen widget — big 4x3 "This Week" (Android
 * only). Approved preview v2 (Nov 11, 2026).
 *
 * Shows every class day at a glance: one row per day that has
 * classes (or is today), each with up to 3 classes (code, time
 * range, room), today marked "TODAY", the next class day marked
 * "NEXT CLASS DAY", days with no classes marked "No classes
 * today", plus the "Next up:" footer and the Google Calendar
 * section — each synced Google Calendar event with its white G
 * badge and its name only (see ScheduleWidgetData for why the
 * name only). Tapping the widget opens the app's Classes screen
 * (the `homewidget://classes` URI; the app root listens for it
 * and pushes ClassesScreen when the dashboard is showing).
 *
 * DATA: same `schedule_widget_data` JSON as the 4x2 widget (the
 * student's REAL stored schedule, never hardcoded) — the two
 * sizes can never disagree. A day row is shown only when that
 * day has classes or is today (the same rule as the in-app
 * Classes week tab); the other days are GONE.
 *
 * RemoteViews rules (Nov 11 Bible widget fix): the layout uses
 * only RemoteViews-allowed views (LinearLayout, TextView,
 * ImageView), no plain View, no clipToOutline, no full-size
 * photo src — the only src is the E logo (@drawable/launch_image).
 */
class ScheduleWeekWidgetProvider : HomeWidgetProvider() {

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
            val views = RemoteViews(context.packageName, R.layout.schedule_widget_week).apply {
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
                val next = ScheduleWidgetData.nextClass(subjects, now)
                val nextDay = next?.second?.dayOfWeek?.value

                for (weekday in 1..7) {
                    val rowId = id(context, "widget_day_$weekday")
                    if (rowId == 0) continue
                    val classes = ScheduleWidgetData.classesOnDay(subjects, weekday)
                    val isToday = weekday == today.dayOfWeek.value
                    if (classes.isEmpty() && !isToday) {
                        setViewVisibility(rowId, View.GONE)
                        continue
                    }
                    setViewVisibility(rowId, View.VISIBLE)
                    // Badge: TODAY wins over NEXT CLASS DAY.
                    val badgeId = id(context, "widget_day_${weekday}_badge")
                    if (badgeId != 0) {
                        when {
                            isToday -> {
                                setViewVisibility(badgeId, View.VISIBLE)
                                setTextViewText(badgeId, "TODAY")
                            }
                            weekday == nextDay -> {
                                setViewVisibility(badgeId, View.VISIBLE)
                                setTextViewText(badgeId, "NEXT CLASS DAY")
                            }
                            else -> setViewVisibility(badgeId, View.GONE)
                        }
                    }
                    if (classes.isEmpty()) {
                        // Today with no classes (the preview's
                        // Wednesday): the "No classes today" line.
                        setViewVisibility(
                            id(context, "widget_day_${weekday}_empty"),
                            View.VISIBLE,
                        )
                        for (i in 0 until ScheduleWidgetData.MAX_ENTRIES_PER_DAY) {
                            setViewVisibility(
                                id(context, "widget_day_${weekday}_class_$i"),
                                View.GONE,
                            )
                        }
                        setViewVisibility(
                            id(context, "widget_day_${weekday}_more"),
                            View.GONE,
                        )
                    } else {
                        setViewVisibility(
                            id(context, "widget_day_${weekday}_empty"),
                            View.GONE,
                        )
                        for (i in 0 until ScheduleWidgetData.MAX_ENTRIES_PER_DAY) {
                            val lineId =
                                id(context, "widget_day_${weekday}_class_$i")
                            if (lineId == 0) continue
                            if (i < classes.size) {
                                val subject = classes[i]
                                setViewVisibility(lineId, View.VISIBLE)
                                setTextViewText(
                                    id(context, "widget_day_${weekday}_class_${i}_code"),
                                    subject.displayCode(),
                                )
                                setTextViewText(
                                    id(context, "widget_day_${weekday}_class_${i}_time"),
                                    subject.timeRange(),
                                )
                                setTextViewText(
                                    id(context, "widget_day_${weekday}_class_${i}_room"),
                                    subject.room,
                                )
                            } else {
                                setViewVisibility(lineId, View.GONE)
                            }
                        }
                        val moreId = id(context, "widget_day_${weekday}_more")
                        if (moreId != 0) {
                            if (classes.size > ScheduleWidgetData.MAX_ENTRIES_PER_DAY) {
                                setViewVisibility(moreId, View.VISIBLE)
                                setTextViewText(
                                    moreId,
                                    "+${classes.size - ScheduleWidgetData.MAX_ENTRIES_PER_DAY} more",
                                )
                            } else {
                                setViewVisibility(moreId, View.GONE)
                            }
                        }
                    }
                }

                // Footer: the next class, or the empty state when
                // there is no schedule at all.
                val nextUp = ScheduleWidgetData.nextUpLine(subjects, now)
                setTextViewText(
                    R.id.widget_next_up,
                    nextUp ?: if (subjects.isEmpty()) {
                        ScheduleWidgetData.EMPTY_TITLE
                    } else {
                        "No upcoming classes."
                    },
                )

                // Google Calendar section: name + white G badge
                // only (approved preview v2). Hidden when there
                // are no synced events.
                val googleEvents = data?.googleEvents.orEmpty()
                if (googleEvents.isEmpty()) {
                    setViewVisibility(R.id.widget_google_section, View.GONE)
                } else {
                    setViewVisibility(R.id.widget_google_section, View.VISIBLE)
                    for (i in 0 until ScheduleWidgetData.MAX_GOOGLE_EVENTS) {
                        val rowId = id(context, "widget_google_$i")
                        val titleId = id(context, "widget_google_title_$i")
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

    /** Resolves a generated view id by name (0 when missing). */
    private fun id(context: Context, name: String): Int =
        context.resources.getIdentifier(name, "id", context.packageName)
}
