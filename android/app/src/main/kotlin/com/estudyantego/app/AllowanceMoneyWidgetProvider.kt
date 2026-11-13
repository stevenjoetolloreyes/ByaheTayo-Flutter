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
 * Allowance home screen widget — big 4x3 "Money" (Android only).
 * Approved preview v1 (Nov 11, 2026).
 *
 * Shows the full money picture: the REAL available balance, this
 * month's in/out, the 6-month spending chart (segmented bars —
 * the biggest month is the tallest deep-leaves bar, months with
 * no spending are short faint gray bars, exactly like the
 * Allowance screen's chart), budget utilization bars, savings
 * progress bars, and recent transactions. Tapping the widget
 * opens the app's Allowance screen (the `homewidget://allowance`
 * URI; the app root listens for it and pushes AllowanceScreen
 * when the dashboard is showing).
 *
 * DATA: same `allowance_widget_data` JSON as the 4x2 widget (the
 * student's REAL stored allowance) — the two sizes can never
 * disagree. With no budgets set the widget says "No budget
 * limits set."; with no savings goals, "No savings goals yet."
 * — never the preview's sample figures.
 *
 * RemoteViews rules (Nov 11 Bible widget fix): the layout uses
 * only RemoteViews-allowed views (LinearLayout, TextView,
 * ImageView, ProgressBar), no plain View, no clipToOutline, no
 * full-size photo src — the only src is the E logo
 * (@drawable/launch_image). Chart bars are five pre-sized
 * segments per month with visibility toggling (RemoteViews has
 * no runtime height API below API 31, and the app floor is 26).
 */
class AllowanceMoneyWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val data = AllowanceWidgetData.parse(
            widgetData.getString(AllowanceWidgetData.DATA_KEY, null),
        )
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.allowance_widget_money).apply {
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse(AllowanceWidgetData.ALLOWANCE_URI),
                    ),
                )

                if (data == null) {
                    setViewVisibility(R.id.widget_content, View.GONE)
                    setViewVisibility(R.id.widget_empty, View.VISIBLE)
                    setTextViewText(R.id.widget_empty_title, AllowanceWidgetData.EMPTY_TITLE)
                    setTextViewText(R.id.widget_empty_sub, AllowanceWidgetData.EMPTY_SUBTITLE)
                } else {
                    setViewVisibility(R.id.widget_content, View.VISIBLE)
                    setViewVisibility(R.id.widget_empty, View.GONE)
                    setTextViewText(
                        R.id.widget_balance,
                        AllowanceWidgetData.formatPeso(data.balance),
                    )
                    if (data.hasNoTransactions()) {
                        setViewVisibility(R.id.widget_month_row, View.GONE)
                        setViewVisibility(R.id.widget_note, View.VISIBLE)
                        setTextViewText(
                            R.id.widget_note,
                            AllowanceWidgetData.EMPTY_TITLE,
                        )
                    } else if (!data.isCurrentMonth()) {
                        setViewVisibility(R.id.widget_month_row, View.GONE)
                        setViewVisibility(R.id.widget_note, View.VISIBLE)
                        setTextViewText(
                            R.id.widget_note,
                            "Open EstudyanteGO to refresh this month.",
                        )
                    } else {
                        setViewVisibility(R.id.widget_month_row, View.VISIBLE)
                        setViewVisibility(R.id.widget_note, View.GONE)
                        setTextViewText(
                            R.id.widget_month_in,
                            "In: ${AllowanceWidgetData.formatPeso(data.monthIncome)}",
                        )
                        setTextViewText(
                            R.id.widget_month_out,
                            "Out: ${AllowanceWidgetData.formatPeso(data.monthExpense)}",
                        )
                    }

                    // Spending chart: 6 months, oldest first.
                    val totalSpent = data.months.sumOf { it.amount }
                    for (i in data.months.indices) {
                        val month = data.months[i]
                        val barId = id(context, "widget_bar_$i")
                        if (barId != 0) {
                            setViewVisibility(barId, View.VISIBLE)
                            setBar(
                                context,
                                "widget_bar_$i",
                                data.barLevel(month),
                                data.isMaxMonth(month),
                            )
                        }
                        val labelId = id(context, "widget_bar_${i}_label")
                        if (labelId != 0) setTextViewText(labelId, month.label)
                        val valueId = id(context, "widget_bar_${i}_value")
                        if (valueId != 0) setTextViewText(
                            valueId,
                            AllowanceWidgetData.formatPeso(month.amount),
                        )
                    }
                    setTextViewText(
                        R.id.widget_chart_total,
                        if (totalSpent == 0.0) {
                            "No spending recorded in the last 6 months."
                        } else {
                            "${AllowanceWidgetData.formatPeso(totalSpent)} Total spent"
                        },
                    )

                    // Budget utilization.
                    if (data.budgets.isEmpty()) {
                        setViewVisibility(R.id.widget_budgets_empty, View.VISIBLE)
                        setTextViewText(
                            R.id.widget_budgets_empty,
                            AllowanceWidgetData.NO_BUDGETS,
                        )
                    } else {
                        setViewVisibility(R.id.widget_budgets_empty, View.GONE)
                    }
                    for (i in 0 until AllowanceWidgetData.MAX_BUDGETS) {
                        val rowId = id(context, "widget_budget_$i")
                        val nameId = id(context, "widget_budget_${i}_name")
                        val amountId = id(context, "widget_budget_${i}_amount")
                        val barId = id(context, "widget_budget_${i}_bar")
                        if (rowId == 0) continue
                        if (i < data.budgets.size) {
                            val budget = data.budgets[i]
                            setViewVisibility(rowId, View.VISIBLE)
                            if (nameId != 0) setTextViewText(nameId, budget.category)
                            if (amountId != 0) {
                                val over = if (budget.isOverBudget()) " — over budget" else ""
                                setTextViewText(
                                    amountId,
                                    "Spent ${AllowanceWidgetData.formatPeso(budget.spent)} " +
                                        "of ${AllowanceWidgetData.formatPeso(budget.limit)}$over",
                                )
                            }
                            if (barId != 0) {
                                setProgressBar(barId, 100, budget.utilizationPct(), false)
                            }
                        } else {
                            setViewVisibility(rowId, View.GONE)
                        }
                    }
                    if (data.budgets.size > AllowanceWidgetData.MAX_BUDGETS) {
                        setViewVisibility(R.id.widget_budgets_more, View.VISIBLE)
                        setTextViewText(
                            R.id.widget_budgets_more,
                            "+${data.budgets.size - AllowanceWidgetData.MAX_BUDGETS} more",
                        )
                    } else {
                        setViewVisibility(R.id.widget_budgets_more, View.GONE)
                    }

                    // Savings progress.
                    if (data.goals.isEmpty()) {
                        setViewVisibility(R.id.widget_goals_empty, View.VISIBLE)
                        setTextViewText(
                            R.id.widget_goals_empty,
                            AllowanceWidgetData.NO_GOALS,
                        )
                    } else {
                        setViewVisibility(R.id.widget_goals_empty, View.GONE)
                    }
                    for (i in 0 until AllowanceWidgetData.MAX_GOALS) {
                        val rowId = id(context, "widget_goal_$i")
                        val nameId = id(context, "widget_goal_${i}_name")
                        val amountId = id(context, "widget_goal_${i}_amount")
                        val barId = id(context, "widget_goal_${i}_bar")
                        if (rowId == 0) continue
                        if (i < data.goals.size) {
                            val goal = data.goals[i]
                            setViewVisibility(rowId, View.VISIBLE)
                            if (nameId != 0) setTextViewText(nameId, goal.name)
                            if (amountId != 0) {
                                setTextViewText(
                                    amountId,
                                    "${AllowanceWidgetData.formatPeso(goal.saved)} " +
                                        "of ${AllowanceWidgetData.formatPeso(goal.target)}",
                                )
                            }
                            if (barId != 0) {
                                setProgressBar(barId, 100, goal.progressPct(), false)
                            }
                        } else {
                            setViewVisibility(rowId, View.GONE)
                        }
                    }
                    if (data.goals.size > AllowanceWidgetData.MAX_GOALS) {
                        setViewVisibility(R.id.widget_goals_more, View.VISIBLE)
                        setTextViewText(
                            R.id.widget_goals_more,
                            "+${data.goals.size - AllowanceWidgetData.MAX_GOALS} more",
                        )
                    } else {
                        setViewVisibility(R.id.widget_goals_more, View.GONE)
                    }

                    // Recent transactions.
                    if (data.recent.isEmpty()) {
                        setViewVisibility(R.id.widget_recent_empty, View.VISIBLE)
                        setTextViewText(
                            R.id.widget_recent_empty,
                            AllowanceWidgetData.EMPTY_TITLE,
                        )
                    } else {
                        setViewVisibility(R.id.widget_recent_empty, View.GONE)
                    }
                    for (i in 0 until AllowanceWidgetData.MAX_RECENT) {
                        val rowId = id(context, "widget_txn_$i")
                        val titleId = id(context, "widget_txn_${i}_title")
                        val subId = id(context, "widget_txn_${i}_sub")
                        val amountId = id(context, "widget_txn_${i}_amount")
                        if (rowId == 0) continue
                        if (i < data.recent.size) {
                            val txn = data.recent[i]
                            setViewVisibility(rowId, View.VISIBLE)
                            if (titleId != 0) setTextViewText(titleId, txn.title())
                            if (subId != 0) {
                                setTextViewText(
                                    subId,
                                    "${txn.category} · ${txn.shortDate()}",
                                )
                            }
                            if (amountId != 0) {
                                val sign = if (txn.kind == "income") "+" else "−"
                                setTextViewText(
                                    amountId,
                                    "$sign${AllowanceWidgetData.formatPeso(txn.amount)}",
                                )
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

    /**
     * Shows one chart bar at [level] (0..4) by toggling its five
     * pre-sized segments. Level 0 renders the short faint gray
     * bar; the biggest month renders deep leaves; the rest render
     * grass green. RemoteViews has no runtime height API below
     * API 31, so the heights live in the layout.
     */
    private fun RemoteViews.setBar(
        context: Context,
        base: String,
        level: Int,
        isMax: Boolean,
    ) {
        for (l in 0 until AllowanceWidgetData.BAR_LEVELS) {
            val segmentId = context.resources.getIdentifier(
                "${base}_level_$l",
                "id",
                context.packageName,
            )
            if (segmentId == 0) continue
            setViewVisibility(
                segmentId,
                if (l == level) View.VISIBLE else View.GONE,
            )
            if (l == level) {
                val bg = when {
                    level == 0 -> R.drawable.widget_bar_track
                    isMax -> R.drawable.widget_bar_fill_max
                    else -> R.drawable.widget_bar_fill
                }
                setInt(segmentId, "setBackgroundResource", bg)
            }
        }
    }

    /** Resolves a generated view id by name (0 when missing). */
    private fun id(context: Context, name: String): Int =
        context.resources.getIdentifier(name, "id", context.packageName)
}
