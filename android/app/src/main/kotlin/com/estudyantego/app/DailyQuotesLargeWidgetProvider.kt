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

/**
 * Daily Quotes home screen widget — big 4x3 (Android only).
 * Approved preview v2 (Nov 11, 2026).
 *
 * Same content as the 4x2 and 3x3 Daily Quotes widgets — the
 * quote large over a Minecraft block background (sky / grass /
 * dirt bands, NO photo) with a small green "Daily Quote" pill —
 * in the big size, with room for the quote's category line and
 * the largest quote text. Today's quote is picked by day-of-year
 * from the app's bundled list, exactly like the Quotes screen's
 * quoteOfDay. Tapping the widget opens the app's Daily Quotes
 * screen (the `homewidget://quotes` URI; the app root listens for
 * it and pushes QuotesScreen when the dashboard is showing).
 *
 * DATA: same `daily_quotes_widget_quotes` JSON as the other two
 * sizes — the FULL bundled quote list — so all three can never
 * disagree.
 *
 * RemoteViews rules (Nov 11 Bible widget fix): the layout uses
 * only RemoteViews-allowed views (LinearLayout, TextView,
 * ImageView, FrameLayout), no plain View, no clipToOutline, no
 * full-size photo src — the only src is the E logo
 * (@drawable/launch_image). The block background is three
 * weighted color bands, not an image.
 */
class DailyQuotesLargeWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val quotes = DailyQuotesWidgetData.decodeQuotes(
            widgetData.getString(DailyQuotesWidgetData.QUOTES_KEY, null),
        )
        val today = DailyQuotesWidgetData.quoteForDate(quotes, LocalDate.now())
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(
                context.packageName,
                R.layout.daily_quotes_widget_large,
            ).apply {
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse(DailyQuotesWidgetData.QUOTES_URI),
                    ),
                )

                setTextViewText(R.id.widget_pill, DailyQuotesWidgetData.PILL_LABEL)
                if (today == null) {
                    setViewVisibility(R.id.widget_content, View.GONE)
                    setViewVisibility(R.id.widget_empty, View.VISIBLE)
                    setTextViewText(
                        R.id.widget_empty_text,
                        DailyQuotesWidgetData.PLACEHOLDER_TEXT,
                    )
                } else {
                    setViewVisibility(R.id.widget_content, View.VISIBLE)
                    setViewVisibility(R.id.widget_empty, View.GONE)
                    setTextViewText(R.id.widget_quote, "“${today.text}”")
                    setTextViewText(R.id.widget_author, "— ${today.author}")
                    setTextViewText(R.id.widget_category, today.category)
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
