package com.estudyantego.app

import java.time.LocalDate

/**
 * Daily Quotes home screen widgets — shared data + derivation,
 * used by all THREE providers (DailyQuotesWidgetProvider 4x2,
 * DailyQuotesSquareWidgetProvider 3x3, DailyQuotesLargeWidgetProvider
 * 4x3).
 *
 * DESIGN (mirrors the Bible Verse widget): the Dart side
 * (DailyQuotesWidgetService) pushes the FULL bundled quote list
 * once as JSON under "daily_quotes_widget_quotes" and these
 * providers pick today's quote by day-of-year themselves on
 * every update (updatePeriodMillis 30 min). The single source of
 * truth stays the bundled list in student_data.dart — nothing
 * here re-lists the quotes. The rotation is the app's own
 * quoteOfDay (day-of-year over bundledQuotes), so the widget and
 * the Quotes screen can never disagree about today's quote.
 *
 * QUOTE ONLY, VERSE-STYLE: the quote renders large over a
 * Minecraft block background (sky / grass / dirt bands, NO
 * photo) with a small green "Daily Quote" pill — the same pill
 * shape as the Verse widget's "Psalm 37:4" pill. No attribution
 * is ever invented: the author comes from the bundled quote.
 *
 * Malformed or missing data is never a crash: parse() returns an
 * empty list and the providers show the placeholder ("Open
 * EstudyanteGO to load today's quote.") instead.
 */
object DailyQuotesWidgetData {

    /** SharedPreferences key (inside the home_widget store). */
    const val QUOTES_KEY = "daily_quotes_widget_quotes"

    /** URI the providers launch with on tap; the app root opens
     * the Daily Quotes screen for it (see main.dart). */
    const val QUOTES_URI = "homewidget://quotes"

    /** Shown by the providers when no quote data has been pushed
     * yet. Same wording as the Dart side. */
    const val PLACEHOLDER_TEXT = "Open EstudyanteGO to load today's quote"

    /** The green pill label on every size, as in the approved
     * preview. Same wording as the Dart side. */
    const val PILL_LABEL = "Daily Quote"

    /** One quote: id + text + author + category, straight from
     * the bundled list. */
    data class WidgetQuote(
        val id: String,
        val text: String,
        val author: String,
        val category: String,
    )

    /**
     * Decodes a pushed quote list. Returns [] for null, empty,
     * non-list, or malformed JSON — the provider treats that as
     * "no data yet" and shows the placeholder, never a crash.
     * The pushed value is a bare JSON array (not an object).
     */
    fun decodeQuotes(raw: String?): List<WidgetQuote> {
        if (raw.isNullOrBlank()) return emptyList()
        return decodeArray(raw)
    }

    private fun decodeArray(raw: String): List<WidgetQuote> {
        return try {
            val array = org.json.JSONArray(raw)
            val out = ArrayList<WidgetQuote>()
            for (i in 0 until array.length()) {
                val q = array.getJSONObject(i)
                out.add(
                    WidgetQuote(
                        id = q.getString("id"),
                        text = q.getString("text"),
                        author = q.getString("author"),
                        category = q.getString("category"),
                    ),
                )
            }
            out
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** Pure: index into a [count]-long day-of-year rotation for
     * [date]. Mirrors quoteOfDay in student_data.dart — Jan 1 is
     * index 0 and the rotation wraps. Returns 0 when [count] is
     * not positive. */
    fun quoteIndexForDate(date: LocalDate, count: Int): Int {
        if (count <= 0) return 0
        return (date.dayOfYear - 1) % count
    }

    /** Pure: today's quote from an already-decoded list, or null
     * when the list is empty (the widget shows the placeholder
     * then). */
    fun quoteForDate(quotes: List<WidgetQuote>, date: LocalDate): WidgetQuote? {
        if (quotes.isEmpty()) return null
        return quotes[quoteIndexForDate(date, quotes.size)]
    }
}
