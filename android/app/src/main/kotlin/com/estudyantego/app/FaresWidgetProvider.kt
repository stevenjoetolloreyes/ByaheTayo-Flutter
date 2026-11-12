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
 * Fares home screen widget — small 4x2 "Fares" (Android only).
 * Approved preview v1 (Nov 11, 2026).
 *
 * Shows the featured route — the first route in Fares-tab order
 * (Cabugao → Vigan Bus Terminal today): regular + student fare,
 * formula distance + ETA. A route with no fare shows "Fare not
 * set", never a sample. Tapping the widget opens the app's Fares
 * tab (the `homewidget://fares` URI; the app root listens for it
 * and switches to the Fares tab when the dashboard is showing).
 *
 * DATA: reads the `fares_widget_data` JSON the Dart side
 * (FaresWidgetService) pushes — the SAME merged Popular Routes
 * list the Fares tab reads — and renders from it on every update.
 *
 * RemoteViews rules (Nov 11 Bible widget fix): the layout uses
 * only RemoteViews-allowed views (LinearLayout, TextView,
 * ImageView), no plain View, no clipToOutline, no full-size
 * photo src — the only src is the E logo (@drawable/launch_image).
 */
class FaresWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val data = FaresWidgetData.parse(
            widgetData.getString(FaresWidgetData.DATA_KEY, null),
        )
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.fares_widget).apply {
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse(FaresWidgetData.FARES_URI),
                    ),
                )

                val featured = data?.featured()
                if (featured == null) {
                    setViewVisibility(R.id.widget_content, View.GONE)
                    setViewVisibility(R.id.widget_empty, View.VISIBLE)
                    setTextViewText(R.id.widget_empty_title, FaresWidgetData.EMPTY_TITLE)
                    setTextViewText(R.id.widget_empty_sub, FaresWidgetData.EMPTY_SUBTITLE)
                } else {
                    setViewVisibility(R.id.widget_content, View.VISIBLE)
                    setViewVisibility(R.id.widget_empty, View.GONE)
                    setTextViewText(R.id.widget_route, featured.title())
                    if (featured.operator != null) {
                        setViewVisibility(R.id.widget_operator, View.VISIBLE)
                        setTextViewText(
                            R.id.widget_operator,
                            "${featured.operator} · ${featured.vehicle}",
                        )
                    } else {
                        setViewVisibility(R.id.widget_operator, View.VISIBLE)
                        setTextViewText(R.id.widget_operator, featured.vehicle)
                    }
                    if (featured.fare == null) {
                        setViewVisibility(R.id.widget_fare_row, View.GONE)
                        setViewVisibility(R.id.widget_fare_not_set, View.VISIBLE)
                        setTextViewText(
                            R.id.widget_fare_not_set,
                            FaresWidgetData.FARE_NOT_SET,
                        )
                    } else {
                        setViewVisibility(R.id.widget_fare_row, View.VISIBLE)
                        setViewVisibility(R.id.widget_fare_not_set, View.GONE)
                        setTextViewText(
                            R.id.widget_fare,
                            FaresWidgetData.formatPeso(featured.fare),
                        )
                        if (featured.studentFare != null) {
                            setViewVisibility(R.id.widget_student_fare, View.VISIBLE)
                            setTextViewText(
                                R.id.widget_student_fare,
                                "${FaresWidgetData.formatPeso(featured.studentFare)} student",
                            )
                        } else {
                            setViewVisibility(R.id.widget_student_fare, View.GONE)
                        }
                    }
                    val distanceLine = featured.distanceLine()
                    if (distanceLine == null) {
                        setViewVisibility(R.id.widget_distance, View.GONE)
                    } else {
                        setViewVisibility(R.id.widget_distance, View.VISIBLE)
                        setTextViewText(R.id.widget_distance, distanceLine)
                    }
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
