package com.estudyantego.app

import org.json.JSONObject

/**
 * Allowance / Money home screen widgets — shared data + formatting,
 * used by BOTH providers (AllowanceWidgetProvider 4x2 "Allowance"
 * and AllowanceMoneyWidgetProvider 4x3 "Money").
 *
 * DESIGN (mirrors the Schedule widget): the Dart side
 * (AllowanceWidgetService) pushes the FULL allowance picture as
 * ONE JSON blob under "allowance_widget_data" — balance, this
 * month's in/out, the 6-month spending chart, budgets, savings
 * goals, recent transactions — and these providers render from
 * it on every update (updatePeriodMillis 30 min). The single
 * source of truth stays the app's stored allowance lists; nothing
 * here re-lists transactions.
 *
 * REAL BALANCE, NOT THE PREVIEW SAMPLE: the approved preview v1
 * showed a ₱10,000 SAMPLE balance. The pushed balance is the
 * REAL income-minus-expenses total (currently ₱0.00 when there
 * are no transactions) — never the sample. Likewise the preview's
 * sample budgets and goals are NOT carried over: with none set,
 * the widget says so plainly.
 *
 * MONTH STALENESS: the payload carries its month key
 * ("2026-11"); the providers render the "This month" row only
 * when the payload's month is the current month. The balance is
 * month-independent, so it always renders.
 *
 * Malformed or missing data is never a crash: parse() returns
 * null and the providers show the empty state ("No transactions
 * yet.") instead.
 */
object AllowanceWidgetData {

    /** SharedPreferences key (inside the home_widget store). */
    const val DATA_KEY = "allowance_widget_data"

    /** URI the providers launch with on tap; the app root opens
     * the Allowance screen for it (see main.dart). */
    const val ALLOWANCE_URI = "homewidget://allowance"

    /** Empty state, same wording as the Dart side. */
    const val EMPTY_TITLE = "No transactions yet."
    const val EMPTY_SUBTITLE = "Add a transaction to track your allowance."

    /** Empty budgets / goals lines, same wording as the Dart side. */
    const val NO_BUDGETS = "No budget limits set."
    const val NO_GOALS = "No savings goals yet."

    /** How many budgets / goals / recent transactions the big
     * widget lists at most. */
    const val MAX_BUDGETS = 3
    const val MAX_GOALS = 2
    const val MAX_RECENT = 4

    /** Chart bar levels: 0 (no spending) .. 4 (the biggest month).
     * Level 0 renders the short faint gray bar, like the Allowance
     * screen's chart. */
    const val BAR_LEVELS = 5

    /** One budget: category + monthly limit + this month's spend. */
    data class WidgetBudget(
        val category: String,
        val limit: Double,
        val spent: Double,
    ) {
        /** 0..100 share of the limit spent, for the progress bar. */
        fun utilizationPct(): Int =
            if (limit <= 0) 0 else ((spent / limit) * 100).toInt().coerceIn(0, 100)

        fun isOverBudget(): Boolean = limit > 0 && spent > limit
    }

    /** One savings goal: name + saved + target. */
    data class WidgetGoal(
        val name: String,
        val saved: Double,
        val target: Double,
    ) {
        /** 0..100 share of the target saved, for the progress bar. */
        fun progressPct(): Int =
            if (target <= 0) 0 else ((saved / target) * 100).toInt().coerceIn(0, 100)
    }

    /** One recent transaction. */
    data class WidgetTxn(
        val kind: String,
        val amount: Double,
        val category: String,
        val note: String,
        val date: String,
    ) {
        /** What the row shows: the note when there is one, else
         * the category (same rule as the Allowance screen). */
        fun title(): String = note.ifEmpty { category }

        /** "Nov 12" — the short date label for the row. */
        fun shortDate(): String {
            val parts = date.split("T").firstOrNull()?.split("-")
                ?: return ""
            if (parts.size != 3) return ""
            val month = parts[1].toIntOrNull() ?: return ""
            val day = parts[2].toIntOrNull() ?: return ""
            return "${monthShort(month)} $day"
        }
    }

    /** One month of the spending chart. */
    data class WidgetMonth(
        val label: String,
        val amount: Double,
    )

    /** The whole allowance payload. */
    data class AllowanceData(
        val balance: Double,
        val monthKey: String,
        val monthIncome: Double,
        val monthExpense: Double,
        val months: List<WidgetMonth>,
        val budgets: List<WidgetBudget>,
        val goals: List<WidgetGoal>,
        val recent: List<WidgetTxn>,
    ) {
        /** True when there are no stored transactions at all. */
        fun hasNoTransactions(): Boolean = recent.isEmpty() && balance == 0.0

        /** "2026-11" for today — must match [monthKey] for the
         * month row to render. */
        fun isCurrentMonth(): Boolean {
            val now = java.time.LocalDate.now()
            val key = "${now.year}-${now.monthValue.toString().padStart(2, '0')}"
            return monthKey == key
        }

        /** Bar level (0..4) for a chart month: the biggest month
         * is level 4, the rest scale to it, zero is level 0. */
        fun barLevel(month: WidgetMonth): Int {
            val max = months.maxOfOrNull { it.amount } ?: 0.0
            if (max <= 0 || month.amount <= 0) return 0
            return ((month.amount / max) * 4).toInt().coerceIn(0, 4)
        }

        /** True when [month] is the biggest month (renders the
         * deep-leaves bar, like the Allowance screen's chart). */
        fun isMaxMonth(month: WidgetMonth): Boolean {
            val max = months.maxOfOrNull { it.amount } ?: 0.0
            return max > 0 && month.amount == max
        }
    }

    /**
     * Parses the pushed payload, or null when it is missing,
     * malformed, or not the expected shape. A single malformed
     * entry poisons the whole payload (like the Bible widget's
     * decodeVerses): the provider then shows the empty state
     * instead of half an allowance.
     */
    fun parse(raw: String?): AllowanceData? {
        if (raw.isNullOrBlank()) return null
        return try {
            val obj = JSONObject(raw)
            val monthsJson = obj.getJSONArray("months")
            val budgetsJson = obj.getJSONArray("budgets")
            val goalsJson = obj.getJSONArray("goals")
            val recentJson = obj.getJSONArray("recent")
            val months = ArrayList<WidgetMonth>()
            for (i in 0 until monthsJson.length()) {
                val m = monthsJson.getJSONObject(i)
                months.add(
                    WidgetMonth(
                        label = m.getString("label"),
                        amount = m.getDouble("amount"),
                    ),
                )
            }
            val budgets = ArrayList<WidgetBudget>()
            for (i in 0 until budgetsJson.length()) {
                val b = budgetsJson.getJSONObject(i)
                budgets.add(
                    WidgetBudget(
                        category = b.getString("category"),
                        limit = b.getDouble("limit"),
                        spent = b.getDouble("spent"),
                    ),
                )
            }
            val goals = ArrayList<WidgetGoal>()
            for (i in 0 until goalsJson.length()) {
                val g = goalsJson.getJSONObject(i)
                goals.add(
                    WidgetGoal(
                        name = g.getString("name"),
                        saved = g.getDouble("saved"),
                        target = g.getDouble("target"),
                    ),
                )
            }
            val recent = ArrayList<WidgetTxn>()
            for (i in 0 until recentJson.length()) {
                val t = recentJson.getJSONObject(i)
                recent.add(
                    WidgetTxn(
                        kind = t.getString("kind"),
                        amount = t.getDouble("amount"),
                        category = t.getString("category"),
                        note = t.getString("note"),
                        date = t.getString("date"),
                    ),
                )
            }
            AllowanceData(
                balance = obj.getDouble("balance"),
                monthKey = obj.getString("monthKey"),
                monthIncome = obj.getDouble("monthIncome"),
                monthExpense = obj.getDouble("monthExpense"),
                months = months,
                budgets = budgets,
                goals = goals,
                recent = recent,
            )
        } catch (_: Exception) {
            null
        }
    }

    /** "₱5,000" — mirrors peso() in student_data.dart (Dart):
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

    /** "Nov" for month 1..12. */
    fun monthShort(month: Int): String {
        val months = listOf(
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        )
        return months[(month - 1).coerceIn(0, 11)]
    }
}
