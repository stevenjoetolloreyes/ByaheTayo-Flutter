package com.estudyantego.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Tasks / To-do home screen widget — small 4x2 "My Tasks"
 * (Android only). Approved preview v1 (Nov 11, 2026).
 *
 * Shows the real state first: the pending count ("2 pending")
 * and the first two pending tasks (title + subject · kind · due
 * date), or the honest empty state ("0 pending", "No pending
 * tasks.") when there are none. The preview's sample tasks are
 * NOT carried over. Tapping the widget opens the app's Classes
 * screen, where tasks live (the `homewidget://tasks` URI; the app
 * root listens for it and pushes ClassesScreen when the dashboard
 * is showing).
 *
 * DATA: reads the `tasks_widget_data` JSON the Dart side
 * (TasksWidgetService) pushes — the student's REAL stored
 * assignments, pending first in due-date order — and renders
 * from it on every update.
 *
 * RemoteViews rules (Nov 11 Bible widget fix): the layout uses
 * only RemoteViews-allowed views (LinearLayout, TextView,
 * ImageView), no plain View, no clipToOutline, no full-size
 * photo src — the only src is the E logo (@drawable/launch_image).
 */
class TasksWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val data = TasksWidgetData.parse(
            widgetData.getString(TasksWidgetData.DATA_KEY, null),
        )
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.tasks_widget).apply {
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse(TasksWidgetData.TASKS_URI),
                    ),
                )

                val pending = data?.pending().orEmpty()
                setTextViewText(
                    R.id.widget_pending_count,
                    "${pending.size} pending",
                )
                if (pending.isEmpty()) {
                    setViewVisibility(R.id.widget_empty, View.VISIBLE)
                    setTextViewText(R.id.widget_empty_title, TasksWidgetData.EMPTY_TITLE)
                    setTextViewText(R.id.widget_empty_sub, TasksWidgetData.EMPTY_SUBTITLE)
                    for (i in 0 until TasksWidgetData.SMALL_LIST_COUNT) {
                        setViewVisibility(id(context, "widget_task_$i"), View.GONE)
                    }
                } else {
                    setViewVisibility(R.id.widget_empty, View.GONE)
                    for (i in 0 until TasksWidgetData.SMALL_LIST_COUNT) {
                        val rowId = id(context, "widget_task_$i")
                        val titleId = id(context, "widget_task_${i}_title")
                        val subId = id(context, "widget_task_${i}_sub")
                        if (rowId == 0) continue
                        if (i < pending.size) {
                            val task = pending[i]
                            setViewVisibility(rowId, View.VISIBLE)
                            if (titleId != 0) setTextViewText(titleId, task.title)
                            if (subId != 0) setTextViewText(subId, task.subtitle())
                        } else {
                            setViewVisibility(rowId, View.GONE)
                        }
                    }
                }
                if (data != null && data.completed().isNotEmpty()) {
                    setViewVisibility(R.id.widget_done_line, View.VISIBLE)
                    setTextViewText(R.id.widget_done_line, data.doneLine())
                } else {
                    setViewVisibility(R.id.widget_done_line, View.GONE)
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /** Resolves a generated view id by name (0 when missing). */
    private fun id(context: Context, name: String): Int =
        context.resources.getIdentifier(name, "id", context.packageName)
}
