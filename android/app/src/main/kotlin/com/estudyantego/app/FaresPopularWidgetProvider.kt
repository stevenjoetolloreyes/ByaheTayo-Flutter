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
 * Fares home screen widget — big 4x3 "Popular Routes" (Android
 * only). Approved preview v1 (Nov 11, 2026).
 *
 * Shows the first three routes in Fares-tab order (Cabugao →
 * Vigan, Cabugao → San Juan, Sinait → Cabugao today), each with
 * its regular + student fare (or "Fare not set" where unset) and
 * its formula distance, plus the "Minimum fare ₱20" footer
 * (Steven's Nov 11 fare rule). No route is invented to fill the
 * list. Tapping the widget opens the app's Fares tab (the
 * `homewidget://fares` URI; the app root listens for it and
 * switches to the Fares tab when the dashboard is showing).
 *
 * DATA: same `fares_widget_data` JSON as the 4x2 widget (the SAME
 * merged Popular Routes list the Fares tab reads) — the two sizes
 * can never disagree.
 *
 * RemoteViews rules (Nov 11 Bible widget fix): the layout uses
 * only RemoteViews-allowed views (LinearLayout, TextView,
 * ImageView), no plain View, no clipToOutline, no full-size
 * photo src — the only src is the E logo (@drawable/launch_image).
 */
class FaresPopularWidgetProvider : HomeWidgetProvider() {

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
            val views = RemoteViews(context.packageName, R.layout.fares_widget_popular).apply {
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse(FaresWidgetData.FARES_URI),
                    ),
                )

                val routes = data?.top(FaresWidgetData.BIG_LIST_COUNT).orEmpty()
                if (routes.isEmpty()) {
                    setViewVisibility(R.id.widget_content, View.GONE)
                    setViewVisibility(R.id.widget_empty, View.VISIBLE)
                    setTextViewText(R.id.widget_empty_title, FaresWidgetData.EMPTY_TITLE)
                    setTextViewText(R.id.widget_empty_sub, FaresWidgetData.EMPTY_SUBTITLE)
                } else {
                    setViewVisibility(R.id.widget_content, View.VISIBLE)
                    setViewVisibility(R.id.widget_empty, View.GONE)
                    for (i in 0 until FaresWidgetData.BIG_LIST_COUNT) {
                        val rowId = id(context, "widget_route_$i")
                        val titleId = id(context, "widget_route_${i}_title")
                        val fareId = id(context, "widget_route_${i}_fare")
                        val subId = id(context, "widget_route_${i}_sub")
                        if (rowId == 0) continue
                        if (i < routes.size) {
                            val route = routes[i]
                            setViewVisibility(rowId, View.VISIBLE)
                            if (titleId != 0) setTextViewText(titleId, route.title())
                            if (fareId != 0) {
                                setTextViewText(
                                    fareId,
                                    if (route.fare == null) {
                                        FaresWidgetData.FARE_NOT_SET
                                    } else {
                                        FaresWidgetData.formatPeso(route.fare)
                                    },
                                )
                            }
                            if (subId != 0) {
                                val student = if (route.studentFare != null) {
                                    "${FaresWidgetData.formatPeso(route.studentFare)} student"
                                } else {
                                    null
                                }
                                val distance = route.distanceLine()
                                val sub = listOfNotNull(student, distance).joinToString(" · ")
                                if (sub.isEmpty()) {
                                    setViewVisibility(subId, View.GONE)
                                } else {
                                    setViewVisibility(subId, View.VISIBLE)
                                    setTextViewText(subId, sub)
                                }
                            }
                        } else {
                            setViewVisibility(rowId, View.GONE)
                        }
                    }
                    setTextViewText(R.id.widget_min_fare, FaresWidgetData.MIN_FARE_LABEL)
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /** Resolves a generated view id by name (0 when missing). */
    private fun id(context: Context, name: String): Int =
        context.resources.getIdentifier(name, "id", context.packageName)
}
