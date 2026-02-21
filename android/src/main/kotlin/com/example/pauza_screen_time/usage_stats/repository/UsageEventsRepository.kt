package com.example.pauza_screen_time.usage_stats.repository

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import com.example.pauza_screen_time.permissions.PermissionHandler
import com.example.pauza_screen_time.usage_stats.model.UsageEventDto

/**
 * Repository for raw usage events.
 *
 * Wraps [UsageStatsManager.queryEvents] and maps results to [UsageEventDto].
 *
 * Requires [android.Manifest.permission.PACKAGE_USAGE_STATS].
 * Throws [SecurityException] when the permission is not granted.
 *
 * Note: Android only keeps events for a few days.
 */
class UsageEventsRepository(private val context: Context) {

    private val usageStatsManager: UsageStatsManager =
        context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    private val permissionHandler = PermissionHandler(context)

    /**
     * Queries raw usage events for the given time range.
     *
     * @param startTimeMs  Start time in milliseconds since epoch
     * @param endTimeMs    End time in milliseconds since epoch
     * @param eventTypes   Optional set of [UsageEvents.Event] type integers to include.
     *                     Null means all event types are returned.
     * @return List of raw events ordered by timestamp (ascending, as provided by the OS)
     * @throws SecurityException if Usage Access permission is not granted
     */
    fun queryUsageEvents(
        startTimeMs: Long,
        endTimeMs: Long,
        eventTypes: Set<Int>?,
    ): List<UsageEventDto> {
        ensurePermission()

        val events = usageStatsManager.queryEvents(startTimeMs, endTimeMs)
            ?: return emptyList()

        val result = mutableListOf<UsageEventDto>()
        val event = UsageEvents.Event()

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (eventTypes != null && event.eventType !in eventTypes) continue
            result.add(
                UsageEventDto(
                    timestampMs = event.timeStamp,
                    packageName = event.packageName ?: "",
                    className = event.className,
                    eventType = event.eventType,
                )
            )
        }

        android.util.Log.d(TAG, "Retrieved ${result.size} usage events")
        return result
    }

    private fun ensurePermission() {
        val status = permissionHandler.checkPermission(PermissionHandler.USAGE_STATS_KEY)
        if (status != PermissionHandler.STATUS_GRANTED) {
            throw SecurityException("Usage Access is not granted for android.usageStats")
        }
    }

    companion object {
        private const val TAG = "UsageEventsRepository"
    }
}
