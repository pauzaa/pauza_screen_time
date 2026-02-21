package com.example.pauza_screen_time.usage_stats.model

import android.app.usage.UsageStatsManager

/**
 * Typed wrapper for the Android UsageStatsManager interval constants.
 *
 * Use this enum instead of passing raw integers to avoid confusion between
 * arbitrary integers and the valid [UsageStatsManager.INTERVAL_*] constants.
 */
enum class UsageStatsInterval(val rawValue: Int) {
    /** Let the system choose the most appropriate interval. */
    BEST(UsageStatsManager.INTERVAL_BEST),

    /** Aggregate data by day. */
    DAILY(UsageStatsManager.INTERVAL_DAILY),

    /** Aggregate data by week. */
    WEEKLY(UsageStatsManager.INTERVAL_WEEKLY),

    /** Aggregate data by month. */
    MONTHLY(UsageStatsManager.INTERVAL_MONTHLY),

    /** Aggregate data by year. */
    YEARLY(UsageStatsManager.INTERVAL_YEARLY);

    companion object {
        /**
         * Returns the [UsageStatsInterval] matching [rawValue], or [BEST] if not recognised.
         */
        fun fromRawValue(raw: Int): UsageStatsInterval =
            entries.firstOrNull { it.rawValue == raw } ?: BEST
    }
}
