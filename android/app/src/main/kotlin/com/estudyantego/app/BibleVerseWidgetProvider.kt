package com.estudyantego.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import java.util.Calendar
import org.json.JSONArray
import org.json.JSONObject

/**
 * Bible Verse home screen widget (Android only).
 *
 * Shows the Verse of the Day from the bundled KJV selection,
 * styled like the sample Steven approved (Nov 8): a photographic
 * background, the EstudyanteGO logo top-left, the verse in large
 * white sans-serif, centered, and a green reference pill. The
 * verse stays APP-DRIVEN (the Dart side picks today's verse from
 * the 30 bundled KJV verses); the BACKGROUND is chosen by the
 * CATHOLIC LITURGICAL SEASON / feast (Steven, Nov 8).
 *
 * VERSE + PHOTO SYNC (Steven, Nov 8: "Dapat nag Sync yung
 * verse, photo ah"): the Dart side writes today's verse AND its
 * background as ONE pair — a single JSON object under
 * "bible_widget_today" (see BibleWidgetService.todayPair) —
 * and this provider applies both in a single RemoteViews update
 * (one updateAppWidget per widget), so the widget never shows a
 * new verse with an old photo (or vice versa). When there is no
 * fresh pair (the app wasn't opened, or the pair is stale
 * across a day/season boundary), the provider derives BOTH from
 * today instead — the verse from the pushed list by day-of-year,
 * the background from the season table below (or the verse's
 * nature photo) — so they are still in sync.
 *
 * BACKGROUND PRECEDENCE (first match wins):
 *   1. Fixed feast — Nov 1 All Saints Day, Nov 2 All Souls Day,
 *      Dec 8 Immaculate Conception, Epiphany (the Sunday
 *      between Jan 2 and Jan 8). A fixed feast overrides the
 *      season it falls in (Dec 8 is inside Advent; Epiphany is
 *      inside Christmas).
 *   2. Season window — Advent, Christmas, Lent (see
 *      seasonWindows). Ordinary Time (no feast, no window) has
 *      its own photo (ordinary_time).
 *   3. A season with no photo yet (the Easter Triduum, Easter
 *      Time): the verse's nature photo — the Dart side
 *      (BibleWidgetService) tags every verse with one of the
 *      4 nature scenes, and the provider renders it.
 *   4. No verse data yet (empty state): the default sunset/cross
 *      photo with the placeholder, never a fabricated verse.
 *
 * WHY THE SEASON TABLE LIVES HERE TOO (not only in Dart): the
 * provider runs on every update (updatePeriodMillis is 30
 * minutes) and has the current date, so the background follows
 * the season even on days the app was never opened — that is
 * the fallback when the pair is stale. The Dart side carries
 * the SAME table (BibleWidgetService.seasonSceneForDate) to
 * pick the pair's background at refresh time. The two tables
 * MUST stay in sync (same dates, same scenes) or the pair and
 * the fallback disagree. The verse itself is picked by
 * day-of-year for the same reason (correct even when the app
 * wasn't opened).
 *
 * THE TABLE (explicit, editable — add a row per season/year):
 * Fixed feasts (same date every year):
 *   Nov 1  -> all_saints              (All Saints Day)
 *   Nov 2  -> all_souls               (All Souls Day)
 *   Dec 8  -> immaculate_conception   (Immaculate Conception)
 * Epiphany (the Sunday between Jan 2 and Jan 8):
 *   Jan 3, 2027  -> epiphany
 *   Jan 2, 2028  -> epiphany
 * Seasons (explicit dates; movable seasons start on different
 * dates each year, so add the new year's window when it turns):
 *   Advent 2026    Nov 29, 2026 – Dec 24, 2026 -> advent
 *   Christmas      Dec 25, 2026 – Jan 10, 2027 -> christmas
 *                  (Baptism of the Lord ends the season)
 *   Lent 2027      Feb 10, 2027 – Mar 25, 2027 -> lent
 *   Triduum 2027   Mar 26–27, 2027             -> (no photo yet)
 *   Easter 2027    Mar 28 – May 16, 2027       -> (no photo yet)
 *   Advent 2027    Nov 28, 2027 – Dec 24, 2027 -> advent
 *   Christmas      Dec 25, 2027 – Jan 9, 2028  -> christmas
 *   Lent 2028      Mar 1, 2028 – Apr 13, 2028  -> lent
 *   Triduum 2028   Apr 14–15, 2028             -> (no photo yet)
 *   Easter 2028    Apr 16 – Jun 4, 2028        -> (no photo yet)
 *   Ordinary Time  (no feast, no window)        -> ordinary_time
 * Dates verified Nov 8, 2026 against the USCCB Liturgical
 * Calendar for the Dioceses of the USA 2027 (usccb.org) and
 * diocesan calendars — do NOT guess movable feasts. Christ the
 * King (Nov 21, 2027) is an Ordinary Time Sunday until its
 * photo arrives, so it shows the Ordinary Time photo.
 *
 * TO ADD A SEASON (Triduum / Easter / Pentecost / Christ the
 * King — photos to be generated later on Steven's ask):
 * generate/upload a photo as res/drawable/verse_bg_<name>.webp,
 * add one row to seasonWindows below (replacing the null), add
 * the name to BOTH season tables (Dart + Kotlin), and add one
 * line to sceneDrawable(). The provider references each scene
 * by NAME, never by file, so swapping a photo is a file
 * replacement, not a code change.
 *
 * The backgrounds are PHOTOS (WebP in res/drawable, one per
 * scene). They are BINARY files: they cannot be pushed via the
 * GitHub App and must be web-uploaded into res/drawable (like
 * the fonts and launch_image) before the code push lands, or the
 * cloud build fails on the missing drawables.
 *
 * The Dart side pushes the FULL verse list once as JSON under
 * the "bible_widget_verses" key AND today's verse + background
 * pair under "bible_widget_today" whenever the Bible screen
 * loads; this provider prefers the fresh pair and falls back to
 * the list + its own season table when the pair is stale. The
 * single source of truth is the Dart bundled list — the verses
 * are never copied here, and the verse-to-nature-scene mapping
 * lives in BibleWidgetService.
 *
 * Tap anywhere on the widget to open the app. When no verse
 * data has been pushed yet (widget added before the app ever
 * synced), the placeholder is shown on the default sunset scene
 * instead of crashing or going blank — never a fabricated verse.
 *
 * The reference pill shows just the reference ("Philippians
 * 4:13"), as in the sample — the " (KJV)" suffix the old widget
 * appended is dropped here (the in-app Bible screen still
 * identifies the translation). The verse is wrapped in curly
 * quotes, as in the sample.
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

                val today = LocalDate.now()
                // Verse + photo SYNC (Steven, Nov 8): the app writes
                // today's verse AND its background as ONE pair
                // (bible_widget_today) and this update applies both
                // in this single RemoteViews update, so the two can
                // never drift apart. A fresh pair is used as written.
                val pairVerse =
                    pickTodayPair(widgetData.getString(TODAY_KEY, null), today)
                val verse: WidgetVerse?
                val scene: String
                if (pairVerse != null) {
                    verse = pairVerse
                    scene = pairVerse.scene
                } else {
                    // No fresh pair (the app wasn't opened, or the
                    // pair is stale across a day/season boundary):
                    // derive BOTH from today — the verse from the
                    // pushed list by day-of-year, the background
                    // from the season table (or the verse's nature
                    // photo) — so they are still in sync.
                    verse = pickVerseForToday(widgetData.getString(VERSES_KEY, null))
                    scene = seasonSceneForDate(today)
                        ?: verse?.scene
                        ?: DEFAULT_SCENE
                }
                // Downsampled photo (Nov 11 widget fix): the
                // verse_bg_* photos are 2240px wide (~10 MB decoded
                // ARGB_8888), over the RemoteViews per-widget bitmap
                // ceiling, so the provider decodes a ~800px-wide
                // RGB_565 copy instead of setImageViewResource.
                // On any failure the ImageView is left empty (the
                // dark card background shows) — never the full-size
                // drawable, and never a provider crash.
                decodeWidgetBackground(context, sceneDrawable(scene))?.let {
                    setImageViewBitmap(R.id.widget_background, it)
                }
                if (verse == null) {
                    setTextViewText(R.id.widget_verse, PLACEHOLDER_TEXT)
                    setViewVisibility(R.id.widget_ref, View.GONE)
                    setViewVisibility(R.id.widget_divider, View.GONE)
                } else {
                    setTextViewText(R.id.widget_verse, "\u201C${verse.text}\u201D")
                    setTextViewText(R.id.widget_ref, verse.ref)
                    setViewVisibility(R.id.widget_ref, View.VISIBLE)
                    setViewVisibility(R.id.widget_divider, View.VISIBLE)
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /**
     * The liturgical season/feast scene for [date], or null when
     * the date is in a season that has no photo yet (the Easter
     * Triduum / Easter Time — the caller then falls back to the
     * verse's nature photo). Fixed feasts are checked FIRST so
     * they override the season they fall in (Dec 8 is inside
     * Advent; Epiphany is inside Christmas). Ordinary Time — any
     * date in no feast and no window — returns "ordinary_time"
     * (the dedicated Ordinary Time photo). Mirrors
     * BibleWidgetService.seasonSceneForDate (Dart): the same date
     * must return the same scene on both sides. Pure function of
     * the date, so the background follows the season on every
     * provider update without the app being opened.
     */
    fun seasonSceneForDate(date: LocalDate): String? {
        // Fixed feasts — the same date every year.
        if (date.monthValue == 11 && date.dayOfMonth == 1) {
            return "all_saints" // All Saints Day
        }
        if (date.monthValue == 11 && date.dayOfMonth == 2) {
            return "all_souls" // All Souls Day
        }
        if (date.monthValue == 12 && date.dayOfMonth == 8) {
            return "immaculate_conception" // Immaculate Conception
        }
        // Season windows (explicit dates — see seasonWindows).
        // A matching window returns its scene, which may be null
        // (a season with no photo yet); no matching window is
        // Ordinary Time. Epiphany's single-day windows sit FIRST
        // in the list so they win over the Christmas window that
        // contains them.
        val window = seasonWindows.firstOrNull { it.contains(date) }
        if (window != null) return window.scene
        return "ordinary_time"
    }

    /**
     * Parses the today-pair the Dart side writes (see
     * BibleWidgetService.todayPair): one JSON object
     * {'date','id','ref','text','scene'} holding today's verse
     * AND its background together. Returns the verse only when
     * the pair's date is [today]; a stale pair (the app wasn't
     * opened across a day/season boundary) or a malformed one
     * returns null and the caller derives both from today
     * instead. The returned verse's `scene` is the RESOLVED
     * background from the pair (season/feast or the verse's
     * nature photo), not the verse's own nature scene — it is
     * used directly as the background.
     */
    fun pickTodayPair(raw: String?, today: LocalDate): WidgetVerse? {
        if (raw.isNullOrBlank()) return null
        return try {
            val obj = JSONObject(raw)
            val date = LocalDate.parse(obj.getString("date"))
            if (date != today) return null
            WidgetVerse(
                ref = obj.getString("ref"),
                text = obj.getString("text"),
                scene = obj.getString("scene"),
            )
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Parses the pushed verse list and returns today's verse, or
     * null when there is no usable data. Selection mirrors the
     * Dart side (BibleWidgetService.verseIndexForDate):
     * index = (dayOfYear - 1) % count, so Jan 1 is the first verse
     * and the rotation wraps — including leap years, where Dec 31
     * is day 366 instead of 365. The scene is read with optString
     * so a list pushed by an older app build (no scene field)
     * still works and falls back to the default scene.
     */
    fun pickVerseForToday(raw: String?): WidgetVerse? {
        if (raw.isNullOrBlank()) return null
        return try {
            val verses = JSONArray(raw)
            if (verses.length() == 0) return null
            val dayOfYear = Calendar.getInstance().get(Calendar.DAY_OF_YEAR)
            val index = (dayOfYear - 1) % verses.length()
            val item = verses.getJSONObject(index)
            WidgetVerse(
                ref = item.getString("ref"),
                text = item.getString("text"),
                scene = item.optString("scene", DEFAULT_SCENE),
            )
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Maps a scene name (a fixed feast / season from
     * seasonSceneForDate, or a verse scene from the Dart side)
     * to its photo drawable. Unknown names fall back to the
     * sunset/cross photo (the sample) instead of crashing.
     */
    fun sceneDrawable(scene: String): Int {
        return when (scene) {
            "sunset_cross" -> R.drawable.verse_bg_sunset_cross
            "mountain_sunrise" -> R.drawable.verse_bg_mountain_sunrise
            "calm_sea" -> R.drawable.verse_bg_calm_sea
            "forest_light" -> R.drawable.verse_bg_forest_light
            "all_saints" -> R.drawable.verse_bg_all_saints
            "all_souls" -> R.drawable.verse_bg_all_souls
            "immaculate_conception" -> R.drawable.verse_bg_immaculate_conception
            "epiphany" -> R.drawable.verse_bg_epiphany
            "advent" -> R.drawable.verse_bg_advent
            "christmas" -> R.drawable.verse_bg_christmas
            "lent" -> R.drawable.verse_bg_lent
            "ordinary_time" -> R.drawable.verse_bg_ordinary_time
            else -> R.drawable.verse_bg_sunset_cross
        }
    }

    /**
     * Decodes a scene photo downsampled to at most [MAX_PHOTO_WIDTH] px
     * wide (power-of-two inSampleSize, RGB_565), so the bitmap sent
     * to the launcher stays inside the RemoteViews per-widget memory
     * ceiling. The full-size verse_bg_* files are 2240px wide
     * (~10 MB decoded ARGB_8888) — loading one with
     * setImageViewResource can make the launcher reject the whole
     * widget ("An error occurred when loading widget"). Returns null
     * on any failure (bad resource, decode error): the caller then
     * leaves the ImageView empty on the dark card background instead
     * of crashing the provider or falling back to the full-size file.
     */
    private fun decodeWidgetBackground(context: Context, resId: Int): Bitmap? {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeResource(context.resources, resId, bounds)
            val width = bounds.outWidth
            if (width <= 0) return null
            var sampleSize = 1
            while (width / sampleSize > MAX_PHOTO_WIDTH) sampleSize *= 2
            val options = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.RGB_565
            }
            BitmapFactory.decodeResource(context.resources, resId, options)
        } catch (_: Exception) {
            null
        } catch (_: OutOfMemoryError) {
            null
        }
    }

    /** Today's verse as the widget renders it. */
    data class WidgetVerse(
        val ref: String,
        val text: String,
        val scene: String,
    )

    /** An inclusive liturgical season window mapped to a scene
     * (or null for a season with no photo yet — the caller then
     * falls back to the verse's nature photo). */
    private data class SeasonWindow(
        val start: LocalDate,
        val end: LocalDate,
        val scene: String?,
    ) {
        fun contains(date: LocalDate): Boolean =
            !date.isBefore(start) && !date.isAfter(end)
    }

    companion object {
        const val VERSES_KEY = "bible_widget_verses"

        /** Key holding today's verse + background as one pair. */
        const val TODAY_KEY = "bible_widget_today"

        /** Default scene: the sample's sunset/cross photo. */
        const val DEFAULT_SCENE = "sunset_cross"

        const val PLACEHOLDER_TEXT = "Open EstudyanteGO to load today's verse"

        /**
         * Widest decoded widget photo, in px. The 4x2 widget renders
         * at most ~1000px wide on a phone, so 800px keeps the bitmap
         * (~800x400 RGB_565 ≈ 0.6 MB) inside the RemoteViews
         * per-widget memory ceiling with headroom to spare.
         */
        const val MAX_PHOTO_WIDTH = 800

        /**
         * Liturgical season windows (inclusive). Movable seasons
         * start on different dates each year — add the new year's
         * window when the year turns. Dates verified against the
         * USCCB Liturgical Calendar 2027; see the class comment
         * for the full table. A null scene is a season with no
         * photo yet (Easter Time, the Triduum) — the caller then
         * shows the verse's nature photo. Epiphany's single-day
         * windows sit FIRST so they win over the Christmas window
         * that contains them (Jan 3, 2027 and Jan 2, 2028 are
         * inside Christmas). The Dart side carries the SAME
         * windows (BibleWidgetService._seasonWindows) — keep the
         * two in sync.
         */
        private val seasonWindows = listOf(
            // Epiphany 2027: Sunday Jan 3 (inside Christmas).
            SeasonWindow(
                LocalDate.of(2027, 1, 3),
                LocalDate.of(2027, 1, 3),
                "epiphany",
            ),
            // Epiphany 2028: Sunday Jan 2 (inside Christmas).
            SeasonWindow(
                LocalDate.of(2028, 1, 2),
                LocalDate.of(2028, 1, 2),
                "epiphany",
            ),
            // Advent 2026: First Sunday of Advent Nov 29 – Dec 24.
            SeasonWindow(
                LocalDate.of(2026, 11, 29),
                LocalDate.of(2026, 12, 24),
                "advent",
            ),
            // Christmas 2026–27: Dec 25 – Baptism of the Lord, Jan 10.
            SeasonWindow(
                LocalDate.of(2026, 12, 25),
                LocalDate.of(2027, 1, 10),
                "christmas",
            ),
            // Lent 2027: Ash Wednesday Feb 10 – Holy Thursday Mar 25.
            SeasonWindow(
                LocalDate.of(2027, 2, 10),
                LocalDate.of(2027, 3, 25),
                "lent",
            ),
            // Easter Triduum 2027: Mar 26–27 (no photo yet).
            SeasonWindow(
                LocalDate.of(2027, 3, 26),
                LocalDate.of(2027, 3, 27),
                null,
            ),
            // Easter Time 2027: Mar 28 – Pentecost, May 16
            // (no photo yet).
            SeasonWindow(
                LocalDate.of(2027, 3, 28),
                LocalDate.of(2027, 5, 16),
                null,
            ),
            // Advent 2027: First Sunday of Advent Nov 28 – Dec 24.
            SeasonWindow(
                LocalDate.of(2027, 11, 28),
                LocalDate.of(2027, 12, 24),
                "advent",
            ),
            // Christmas 2027–28: Dec 25 – Baptism of the Lord, Jan 9.
            SeasonWindow(
                LocalDate.of(2027, 12, 25),
                LocalDate.of(2028, 1, 9),
                "christmas",
            ),
            // Lent 2028: Ash Wednesday Mar 1 – Holy Thursday Apr 13.
            SeasonWindow(
                LocalDate.of(2028, 3, 1),
                LocalDate.of(2028, 4, 13),
                "lent",
            ),
            // Easter Triduum 2028: Apr 14–15 (no photo yet).
            SeasonWindow(
                LocalDate.of(2028, 4, 14),
                LocalDate.of(2028, 4, 15),
                null,
            ),
            // Easter Time 2028: Apr 16 – Pentecost, Jun 4
            // (no photo yet).
            SeasonWindow(
                LocalDate.of(2028, 4, 16),
                LocalDate.of(2028, 6, 4),
                null,
            ),
        )
    }
}
