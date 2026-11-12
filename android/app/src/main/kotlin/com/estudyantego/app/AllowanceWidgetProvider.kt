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
 * renders.
 *
 * RemoteViews rules (Nov 11 Bible widget fix): the layout uses
 * only RemoteViews-allowed views (LinearLayout, TextView,
 * ImageView), no plain View, no clipToOutline, no full-size
 * photo src — the only src is the E logo (@drawable/launch_image).
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
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
