package com.estudyantego.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar
import org.json.JSONArray

/**
 * Bible Verse home screen widget (Android only).
 *
 * Shows the Verse of the Day from the bundled KJV selection. The
 * Dart side (BibleWidgetService) pushes the FULL verse list once as
 * JSON under the "bible_widget_verses" key whenever the Bible
 * screen loads; this provider picks today's verse by day-of-year
 * itself on every update (updatePeriodMillis is 30 minutes), so
 * the verse stays correct even on days the app was never opened.
 * The single source of truth is the Dart bundled list — the verses
 * are never copied here.
 *
 * Tap anywhere on the widget to open the app. When no verse data
 * has been pushed yet (widget added before the app ever synced),
 * a placeholder is shown instead of crashing or going blank.
 */
class BibleVerseWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.bible_verse_widget).apply {
                val launchIntent = context.packageManager
                    .getLaunchIntentForPackage(context.packageName)
                    ?: return@forEach
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    0,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                val verse = pickVerseForToday(widgetData.getString(VERSES_KEY, null))
                if (verse == null) {
                    setTextViewText(R.id.widget_verse, PLACEHOLDER_TEXT)
                    setTextViewText(R.id.widget_ref, "")
                } else {
                    setTextViewText(R.id.widget_verse, verse.second)
                    setTextViewText(R.id.widget_ref, "${verse.first} (KJV)")
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /**
     * Parses the pushed verse list and returns today's (ref, text),
     * or null when there is no usable data. Selection mirrors the
     * Dart side (BibleWidgetService.verseIndexForDate):
     * index = (dayOfYear - 1) % count, so Jan 1 is the first verse
     * and the rotation wraps — including leap years, where Dec 31
     * is day 366 instead of 365.
     */
    fun pickVerseForToday(raw: String?): Pair<String, String>? {
        if (raw.isNullOrBlank()) return null
        return try {
            val verses = JSONArray(raw)
            if (verses.length() == 0) return null
            val dayOfYear = Calendar.getInstance().get(Calendar.DAY_OF_YEAR)
            val index = (dayOfYear - 1) % verses.length()
            val item = verses.getJSONObject(index)
            Pair(item.getString("ref"), item.getString("text"))
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        const val VERSES_KEY = "bible_widget_verses"
        const val PLACEHOLDER_TEXT = "Open EstudyanteGO to load today's verse"
    }
}
