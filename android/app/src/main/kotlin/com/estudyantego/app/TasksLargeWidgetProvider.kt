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
 * Tasks / To-do home screen widget — big 4x3 "Tasks" (Android
 * only). Approved preview v1 (Nov 11, 2026).
 *
 * Shows the pending count, the first five pending tasks (title +
 * subject · kind · due date), the done count ("N of M done" —
 * the preview's collapsible Completed section has no widget
 * equivalent, so the count renders as a footer line), and the
 * first done tasks muted below the pending ones. The preview's
 * sample tasks are NOT carried over — only the REAL stored
 * assignments render — and an empty store shows the honest empty
 * state ("0 pending", "No pending tasks."). Tapping the widget
 * opens the app's Classes screen, where tasks live (the
 * `homewidget://tasks` URI; the app root listens for it and
 * pushes ClassesScreen when the dashboard is showing).
 *
 * DATA: same `tasks_widget_data` JSON as the other two sizes —
 * the student's REAL stored assignments, pending first in
 * due-date order — so all three can never disagree.
 *
 * RemoteViews rules (Nov 11 Bible widget fix): the layout uses
 * only RemoteViews-allowed views (LinearLayout, TextView,
 * ImageView), no plain View, no clipToOutline, no full-size
 * photo src — the only src is the E logo (@drawable/launch_image).
 */
class TasksLargeWidgetProvider : HomeWidgetProvider() {

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
            val views = RemoteViews(
                context.packageName,
                R.layout.tasks_widget_large,
            ).apply {
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse(TasksWidgetData.TASKS_URI),
                    ),
                )

                val pending = data?.pending().orEmpty()
                val completed = data?.completed().orEmpty()
                setTextViewText(
                    R.id.widget_pending_count,
                    "${pending.size} pending",
                )
                if (pending.isEmpty()) {
                    setViewVisibility(R.id.widget_empty, View.VISIBLE)
                    setTextViewText(R.id.widget_empty_title, TasksWidgetData.EMPTY_TITLE)
                    setTextViewText(R.id.widget_empty_sub, TasksWidgetData.EMPTY_SUBTITLE)
                    for (i in 0 until TasksWidgetData.LARGE_LIST_COUNT) {
                        setViewVisibility(id(context, "widget_task_$i"), View.GONE)
                    }
                } else {
                    setViewVisibility(R.id.widget_empty, View.GONE)
                    for (i in 0 until TasksWidgetData.LARGE_LIST_COUNT) {
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
                if (pending.size > TasksWidgetData.LARGE_LIST_COUNT) {
                    setViewVisibility(R.id.widget_more, View.VISIBLE)
                    setTextViewText(
                        R.id.widget_more,
                        "+${pending.size - TasksWidgetData.LARGE_LIST_COUNT} more",
                    )
                } else {
                    setViewVisibility(R.id.widget_more, View.GONE)
                }
                // Progress bar: share of all tasks done. Shown
                // whenever there is at least one task.
                val totalTasks = data?.tasks?.size ?: 0
                if (totalTasks > 0) {
                    setViewVisibility(R.id.widget_progress_bar, View.VISIBLE)
                    setProgressBar(
                        R.id.widget_progress_bar,
                        100,
                        (data?.completed()?.size ?: 0) * 100 / totalTasks,
                        false,
                    )
                } else {
                    setViewVisibility(R.id.widget_progress_bar, View.GONE)
                }

                // Done tasks, muted, below the pending ones (the
                // preview's Completed section, flattened).
                if (completed.isEmpty()) {
                    setViewVisibility(R.id.widget_done_section, View.GONE)
                } else {
                    setViewVisibility(R.id.widget_done_section, View.VISIBLE)
                    setTextViewText(R.id.widget_done_line, data!!.doneLine())
                    for (i in 0 until 2) {
                        val rowId = id(context, "widget_done_$i")
                        val titleId = id(context, "widget_done_${i}_title")
                        if (rowId == 0) continue
                        if (i < completed.size) {
                            setViewVisibility(rowId, View.VISIBLE)
                            if (titleId != 0) {
                                setTextViewText(titleId, "✓ ${completed[i].title}")
                            }
                        } else {
                            setViewVisibility(rowId, View.GONE)
                        }
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
