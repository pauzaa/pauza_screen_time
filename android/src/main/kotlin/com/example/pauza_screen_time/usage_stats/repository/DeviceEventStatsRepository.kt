package com.example.pauza_screen_time.usage_stats.repository

import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import com.example.pauza_screen_time.permissions.PermissionHandler
import com.example.pauza_screen_time.usage_stats.model.EventStatsDto
import com.example.pauza_screen_time.usage_stats.model.UsageStatsInterval

/**
 * Repository for aggregated device-level event statistics.
 *
 * Wraps [UsageStatsManager.queryEventStats] (API 28+) and maps results to
 * [EventStatsDto]. Covers screen-on/off and keyguard-show/hide events.
 *
 * Requires [android.Manifest.permission.PACKAGE_USAGE_STATS].
 * Throws [SecurityException] when the permission is not granted.
 *
 * **Requires API 28+.** Throws [UnsupportedOperationException] on older devices
 * instead of silently returning an empty list, so callers can surface the error.
 */
class DeviceEventStatsRepository(private val context: Context) {

    private val usageStatsManager: UsageStatsManager =
        context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    private val permissionHandler = PermissionHandler(context)

    /**
     * Queries aggregated event statistics for the given interval and time range.
     *
     * @param interval    The aggregation interval (daily, weekly, monthly, yearly, or best-fit)
     * @param startTimeMs Start time in milliseconds since epoch
     * @param endTimeMs   End time in milliseconds since epoch
     * @return List of aggregated event stats for the queried period
     * @throws SecurityException if Usage Access permission is not granted
     * @throws UnsupportedOperationException if the device is running on API < 28
     */
    fun queryEventStats(
        interval: UsageStatsInterval,
        startTimeMs: Long,
        endTimeMs: Long,
    ): List<EventStatsDto> {
        requireApi28()
        ensurePermission()

        val statsList = usageStatsManager.queryEventStats(interval.rawValue, startTimeMs, endTimeMs)
            ?: return emptyList()

        return statsList.map { stats ->
            EventStatsDto(
                eventType = stats.eventType,
                count = stats.count,
                totalTimeMs = stats.totalTime,
                firstTimestampMs = stats.firstTimeStamp,
                lastTimestampMs = stats.lastTimeStamp,
                lastEventTimeMs = stats.lastEventTime,
            )
        }
    }

    private fun requireApi28() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            throw UnsupportedOperationException(
                "queryEventStats requires Android 9 (API 28). " +
                    "Current API level: ${Build.VERSION.SDK_INT}"
            )
        }
    }

    private fun ensurePermission() {
        val status = permissionHandler.checkPermission(PermissionHandler.USAGE_STATS_KEY)
        if (status != PermissionHandler.STATUS_GRANTED) {
            throw SecurityException("Usage Access is not granted for android.usageStats")
        }
    }

    companion object {
        private const val TAG = "DeviceEventStatsRepository"
    }
}
