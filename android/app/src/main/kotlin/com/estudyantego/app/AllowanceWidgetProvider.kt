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
 * Allowance home screen widget — small 4x2 "Allowance" (Android
 * only). Approved preview v1 (Nov 11, 2026).
 *
 * Shows the quick glance: the REAL available balance (income
 * minus expenses from the student's stored transactions — the
 * preview's ₱10,000 was a SAMPLE and is never shown) and this
 * month's in/out. Tapping the widget opens the app's Allowance
 * screen (the `homewidget://allowance` URI; the app root listens
 * for it and pushes AllowanceScreen when the dashboard is
 * showing).
 *
 * DATA: reads the `allowance_widget_data` JSON the Dart side
 * (AllowanceWidgetService) pushes — the student's REAL stored
 * allowance — and renders from it on every update. The "This
 * month" row renders only when the payload's month is the
 * current month (see AllowanceWidgetData); the balance always
 * renders. The mini spending chart renders the payload's 6
 * months (same segmented bars as the Money widget, half scale)
 * whenever there are transactions at all; with none, the honest
 * empty state covers the whole widget instead.
 *
 * RemoteViews rules (Nov 11 Bible widget fix): the layout uses
 * only RemoteViews-allowed views (LinearLayout, TextView,
 * ImageView, FrameLayout for the chart bars), no plain View, no
 * clipToOutline, no full-size photo src — the only src is the E
 * logo (@drawable/launch_image).
 */
class AllowanceWidgetProvider : HomeWidgetProvider() {

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
            val views = RemoteViews(context.packageName, R.layout.allowance_widget).apply {
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
                    when {
                        data.hasNoTransactions() -> {
                            setViewVisibility(R.id.widget_month_row, View.GONE)
                            setViewVisibility(R.id.widget_note, View.VISIBLE)
                            setTextViewText(
                                R.id.widget_note,
                                AllowanceWidgetData.EMPTY_TITLE,
                            )
                        }
                        !data.isCurrentMonth() -> {
                            setViewVisibility(R.id.widget_month_row, View.GONE)
                            setViewVisibility(R.id.widget_note, View.VISIBLE)
                            setTextViewText(
                                R.id.widget_note,
                                "Open EstudyanteGO to refresh this month.",
                            )
                        }
                        else -> {
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
                    }

                    // Mini spending chart: 6 months, oldest first —
                    // same segmented-bar approach as the Money widget,
                    // half scale. Hidden with no transactions (the
                    // honest empty state covers that); shown otherwise,
                    // even when nothing was spent — all-zero months
                    // render short gray bars, like the Money widget.
                    if (data.hasNoTransactions()) {
                        setViewVisibility(R.id.widget_chart, View.GONE)
                    } else {
                        setViewVisibility(R.id.widget_chart, View.VISIBLE)
                        for (i in data.months.indices) {
                            val month = data.months[i]
                            setBar(
                                context,
                                "widget_mini_bar_$i",
                                data.barLevel(month),
                                data.isMaxMonth(month),
                            )
                            val labelId = id(context, "widget_mini_bar_${i}_label")
                            if (labelId != 0) setTextViewText(labelId, month.label)
                        }
                    }
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /**
     * Shows one mini chart bar at [level] (0..4) by toggling its
     * five pre-sized segments. Level 0 renders the short faint
     * gray bar; the biggest month renders deep leaves; the rest
     * render grass green. Mirrors AllowanceMoneyWidgetProvider
     * (RemoteViews has no runtime height API below API 31, and
     * the app floor is 26, so the heights live in the layout).
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
