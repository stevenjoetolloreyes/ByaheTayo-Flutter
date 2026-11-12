package com.estudyantego.app

import java.time.LocalDate
import org.json.JSONObject

/**
 * Tasks / To-do home screen widgets — shared data + formatting,
 * used by all THREE providers (TasksWidgetProvider 4x2,
 * TasksSquareWidgetProvider 3x3, TasksLargeWidgetProvider 4x3).
 *
 * DESIGN (mirrors the Schedule widget): the Dart side
 * (TasksWidgetService) pushes the student's tasks as ONE JSON
 * blob under "tasks_widget_data" — pending first, due-date order,
 * then done — and these providers render from it on every update
 * (updatePeriodMillis 30 min). The single source of truth stays
 * the app's stored assignments (StudentStorage.assignmentsKey);
 * nothing here re-lists tasks.
 *
 * REAL TASKS ONLY: the approved preview v1 showed SAMPLE tasks
 * on the 3x3 and 4x3 sizes ("2 of 5 done"). The pushed list is
 * the REAL stored assignments, and an empty store renders the
 * honest empty state ("0 pending", "No pending tasks."). No
 * assignment, due date, or subject is ever invented. Done tasks
 * are counted ("N of M done") and listed after the pending ones,
 * muted; the preview's collapsible Completed section has no
 * widget equivalent, so the big size shows the done count as a
 * footer line instead.
 *
 * Malformed or missing data is never a crash: parse() returns
 * null and the providers show the empty state instead.
 */
object TasksWidgetData {

    /** SharedPreferences key (inside the home_widget store). */
    const val DATA_KEY = "tasks_widget_data"

    /** URI the providers launch with on tap; the app root opens
     * the Classes screen for it (see main.dart). */
    const val TASKS_URI = "homewidget://tasks"

    /** Empty state, same wording as the Dart side. */
    const val EMPTY_TITLE = "No pending tasks."
    const val EMPTY_SUBTITLE = "Add a task to get started."

    /** How many pending tasks each size lists at most. */
    const val SMALL_LIST_COUNT = 2
    const val SQUARE_LIST_COUNT = 4
    const val LARGE_LIST_COUNT = 5

    /** One task: title + kind + due date + done + subject name. */
    data class WidgetTask(
        val id: String,
        val title: String,
        val kind: String,
        val due: String,
        val done: Boolean,
        val subjectName: String,
    ) {
        /** "Assignment" / "Exam" — the row label, same words as
         * the Classes screen's rows. */
        fun kindLabel(): String = if (kind == "exam") "Exam" else "Assignment"

        /** "Nov 12, 2026" — the due date as the Classes screen
         * shows it. */
        fun dueLabel(): String {
            val parsed = runCatching { LocalDate.parse(due.substring(0, 10)) }.getOrNull()
                ?: return ""
            val months = listOf(
                "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
            )
            return "${months[parsed.monthValue - 1]} ${parsed.dayOfMonth}, ${parsed.year}"
        }

        /** "Computer Programming 1 · Exam · due Nov 12, 2026" —
         * the row subtitle, same shape as the Classes screen's
         * rows (subject omitted when unknown). */
        fun subtitle(): String {
            val subject = if (subjectName.isEmpty()) null else subjectName
            return listOfNotNull(subject, kindLabel(), "due ${dueLabel()}")
                .joinToString(" · ")
        }
    }

    /** The whole tasks payload. */
    data class TasksData(
        val tasks: List<WidgetTask>,
    ) {
        /** Not-done tasks, due-date order. */
        fun pending(): List<WidgetTask> = tasks.filter { !it.done }

        /** Done tasks, due-date order. */
        fun completed(): List<WidgetTask> = tasks.filter { it.done }

        /** "2 of 5 done" — the big widget's footer line. */
        fun doneLine(): String = "${completed().size} of ${tasks.size} done"
    }

    /**
     * Parses the pushed payload, or null when it is missing,
     * malformed, or not the expected shape. A single malformed
     * task poisons the whole payload (like the Bible widget's
     * decodeVerses): the provider then shows the empty state
     * instead of half a task list.
     */
    fun parse(raw: String?): TasksData? {
        if (raw.isNullOrBlank()) return null
        return try {
            val obj = JSONObject(raw)
            val tasksJson = obj.getJSONArray("tasks")
            val tasks = ArrayList<WidgetTask>()
            for (i in 0 until tasksJson.length()) {
                val t = tasksJson.getJSONObject(i)
                tasks.add(
                    WidgetTask(
                        id = t.getString("id"),
                        title = t.getString("title"),
                        kind = t.getString("kind"),
                        due = t.getString("due"),
                        done = t.getBoolean("done"),
                        subjectName = t.getString("subjectName"),
                    ),
                )
            }
            TasksData(tasks = tasks)
        } catch (_: Exception) {
            null
        }
    }
}
