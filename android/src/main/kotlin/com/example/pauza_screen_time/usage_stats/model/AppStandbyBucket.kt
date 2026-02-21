package com.example.pauza_screen_time.usage_stats.model

import android.app.usage.UsageStatsManager
import android.os.Build

/**
 * Typed wrapper for Android's app standby bucket constants.
 *
 * Available on API 28+. Each bucket determines how aggressively the system
 * restricts the app's background work and alarms.
 *
 * @see UsageStatsManager.getAppStandbyBucket
 */
enum class AppStandbyBucket(val rawValue: Int) {
    /** App is actively in use. No restrictions. (API 28+) */
    ACTIVE(UsageStatsManager.STANDBY_BUCKET_ACTIVE),

    /** App has been used recently. Light restrictions. (API 28+) */
    WORKING_SET(UsageStatsManager.STANDBY_BUCKET_WORKING_SET),

    /** App is used regularly but not daily. Moderate restrictions. (API 28+) */
    FREQUENT(UsageStatsManager.STANDBY_BUCKET_FREQUENT),

    /** App was last used weeks ago. Heavy restrictions. (API 28+) */
    RARE(UsageStatsManager.STANDBY_BUCKET_RARE),

    /**
     * App was never used or only used briefly. Strictest restrictions. (API 30+)
     *
     * Falls back to [RARE] on API < 30.
     */
    RESTRICTED(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) 45 else UsageStatsManager.STANDBY_BUCKET_RARE),

    /** Unrecognised value — should not normally occur. */
    UNKNOWN(-1);

    companion object {
        /**
         * Returns the [AppStandbyBucket] matching [rawValue], or [UNKNOWN] if not recognised.
         */
        fun fromRawValue(raw: Int): AppStandbyBucket =
            entries.firstOrNull { it.rawValue == raw } ?: UNKNOWN
    }
}
