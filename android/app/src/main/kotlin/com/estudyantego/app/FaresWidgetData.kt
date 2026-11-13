package com.estudyantego.app

import kotlin.math.roundToInt
import org.json.JSONObject

/**
 * Fares home screen widgets — shared data + formatting, used by
 * BOTH providers (FaresWidgetProvider 4x2 "Fares" and
 * FaresPopularWidgetProvider 4x3 "Popular Routes").
 *
 * DESIGN (mirrors the Schedule widget): the Dart side
 * (FaresWidgetService) pushes the merged Popular Routes list as
 * ONE JSON blob under "fares_widget_data" — the built-in routes
 * with the admin's Firestore overrides applied, plus the
 * admin-added custom routes, minus the hidden built-in routes —
 * and these providers render from it on every update
 * (updatePeriodMillis 30 min). The single source of truth stays
 * the SAME merged list the Fares tab reads; nothing here re-lists
 * routes.
 *
 * DISTANCE + ETA COME FROM THE APP'S OWN MODELS: the distance is
 * the formula road distance the Fares LIST card shows ("≈ 31.6
 * km", haversine × 1.22) — NOT the preview's 32.3 km, which was
 * the live OSRM road distance from the detail sheet and which
 * the widget cannot fetch. The ETA comes from the app's own
 * estimateTripMinutes model, which gives the same "1 hr 10 min"
 * for Cabugao → Vigan.
 *
 * NO INVENTED ROUTES OR FARES: a route with a null fare shows
 * "Fare not set" — never a sample. The "Minimum fare ₱20" footer
 * is Steven's Nov 11 fare rule, stated in the approved preview.
 *
 * Malformed or missing data is never a crash: parse() returns
 * null and the providers show the empty state ("Open EstudyanteGO
 * to load fares.") instead.
 */
object FaresWidgetData {

    /** SharedPreferences key (inside the home_widget store). */
    const val DATA_KEY = "fares_widget_data"

    /** URI the providers launch with on tap; the app root opens
     * the Fares tab for it (see main.dart). */
    const val FARES_URI = "homewidget://fares"

    /** Empty state, same wording as the Dart side. */
    const val EMPTY_TITLE = "Open EstudyanteGO to load fares."
    const val EMPTY_SUBTITLE = "Fares load from the Fares tab when the app opens."

    /** Shown for a route with no fare set. Same wording as the
     * Dart side and the Fares list card. */
    const val FARE_NOT_SET = "Fare not set"

    /** Steven's fare rule (Nov 11, 2026): the minimum fare is
     * ₱20. Shown as the big widget's footer, as in the approved
     * preview. Same wording as the Dart side. */
    const val MIN_FARE_LABEL = "Minimum fare ₱20"

    /** How many routes the big widget lists. */
    const val BIG_LIST_COUNT = 3

    /** Chart bar levels: 0 (smallest) .. 4 (the biggest fare). */
    const val BAR_LEVELS = 5

    /** One route: endpoints + vehicle + operator + fares +
     * formula distance + ETA. */
    data class WidgetRoute(
        val from: String,
        val to: String,
        val vehicle: String,
        val operator: String?,
        val fare: Double?,
        val studentFare: Double?,
        val distanceKm: Double?,
        val etaMin: Int?,
    ) {
        /** "Cabugao → Vigan Bus Terminal" — the route line the
         * Fares list card shows. */
        fun title(): String = "$from → $to"

        /** "≈ 31.6 km · 1 hr 10 min" — the formula distance with
         * the list card's "≈" marker, plus the ETA. Null when the
         * endpoints are not known hubs (no figure is guessed). */
        fun distanceLine(): String? {
            if (distanceKm == null) return null
            val km = "≈ ${formatKm(distanceKm)} km"
            return if (etaMin != null) "$km · ${formatTripTime(etaMin)}" else km
        }
    }

    /** The whole fares payload. */
    data class FaresData(
        val routes: List<WidgetRoute>,
    ) {
        /** The featured route for the small widget: the first
         * route in Fares-tab order. */
        fun featured(): WidgetRoute? = routes.firstOrNull()

        /** The routes the big widget lists, in Fares-tab order. */
        fun top(count: Int): List<WidgetRoute> = routes.take(count)
    }

    /**
     * Parses the pushed payload, or null when it is missing,
     * malformed, or not the expected shape. A single malformed
     * route poisons the whole payload (like the Bible widget's
     * decodeVerses): the provider then shows the empty state
     * instead of half a route list.
     */
    fun parse(raw: String?): FaresData? {
        if (raw.isNullOrBlank()) return null
        return try {
            val obj = JSONObject(raw)
            val routesJson = obj.getJSONArray("routes")
            val routes = ArrayList<WidgetRoute>()
            for (i in 0 until routesJson.length()) {
                val r = routesJson.getJSONObject(i)
                routes.add(
                    WidgetRoute(
                        from = r.getString("from"),
                        to = r.getString("to"),
                        vehicle = r.getString("vehicle"),
                        operator = if (r.isNull("operator")) null else r.getString("operator"),
                        fare = if (r.isNull("fare")) null else r.getDouble("fare"),
                        studentFare = if (r.isNull("studentFare")) null else r.getDouble("studentFare"),
                        distanceKm = if (r.isNull("distanceKm")) null else r.getDouble("distanceKm"),
                        etaMin = if (r.isNull("etaMin")) null else r.getInt("etaMin"),
                    ),
                )
            }
            FaresData(routes = routes)
        } catch (_: Exception) {
            null
        }
    }

    /** "₱60" — mirrors peso() in student_data.dart (Dart):
     * thousands separators, 2 decimals only when the value has a
     * fractional part. */
    fun formatPeso(amount: Double): String {
        val fixed = "%.2f".format(amount)
        val parts = fixed.split(".")
        val intPart = parts[0]
        val buf = StringBuilder()
        for (i in intPart.indices) {
            if (i > 0 && (intPart.length - i) % 3 == 0) buf.append(',')
            buf.append(intPart[i])
        }
        val frac = parts[1]
        return "₱${buf}${if (frac == "00") "" else ".$frac"}"
    }

    /** "31.6" — one decimal, like the Fares list card's formatKm. */
    fun formatKm(km: Double): String = "%.1f".format(km)

    /** "45 min" / "1 hr 10 min" — mirrors formatTripTimeShort in
     * fares_tab.dart (Dart). */
    fun formatTripTime(minutes: Int): String {
        val hours = minutes / 60
        val mins = minutes % 60
        return when {
            hours == 0 -> "$mins min"
            mins == 0 -> "$hours hr"
            else -> "$hours hr $mins min"
        }
    }

    /** Bar level (0..4) for a fare against the biggest fare in
     * its comparison: the biggest fare is level 4, the rest
     * scale to it, zero is level 0. Mirrors
     * AllowanceWidgetData.barLevel. */
    fun fareLevel(fare: Double, maxFare: Double): Int {
        if (maxFare <= 0 || fare <= 0) return 0
        return ((fare / maxFare) * 4).roundToInt().coerceIn(0, 4)
    }
}
