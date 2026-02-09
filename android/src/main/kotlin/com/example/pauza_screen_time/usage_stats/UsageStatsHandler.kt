package com.example.pauza_screen_time.usage_stats

import android.app.usage.UsageEvents
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import com.example.pauza_screen_time.permissions.PermissionHandler
import com.example.pauza_screen_time.utils.AppInfoUtils

/**
 * Handler for usage statistics queries.
 *
 * This class provides functionality to query app usage statistics using Android's
 * UsageStatsManager API. It retrieves usage data for a specified time range and
 * enriches it with app metadata (name and icon) from PackageManager.
 *
 * Note: This is Android-only functionality. iOS has a different sandboxed approach
 * for usage statistics via DeviceActivityReport platform view.
 */
class UsageStatsHandler(private val context: Context) {

    private val usageStatsManager: UsageStatsManager =
        context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    private val packageManager: PackageManager = context.packageManager
    private val permissionHandler = PermissionHandler(context)

    /**
     * Queries usage statistics for a given time range.
     *
     * @param startTimeMs Start time in milliseconds since epoch
     * @param endTimeMs End time in milliseconds since epoch
     * @param includeIcons Whether to include app icons (can be expensive)
     * @return List of maps containing enriched usage statistics
     */
    fun queryUsageStats(
        startTimeMs: Long,
        endTimeMs: Long,
        includeIcons: Boolean = true
    ): List<Map<String, Any?>> {
        ensureUsageStatsPermission()
        val usageStatsList = mutableListOf<Map<String, Any?>>()

        // Query usage stats for the specified time range
        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_BEST,
            startTimeMs,
            endTimeMs
        )

        if (stats == null || stats.isEmpty()) {
            android.util.Log.w("UsageStatsHandler", "No usage stats found for the given time range")
            return emptyList()
        }

        // Single pass over events to avoid O(N_apps × N_events)
        val launchCountsByPackage = calculateLaunchCounts(startTimeMs, endTimeMs)

        // Process each app's usage stats
        for (usageStats in stats) {
            // Skip apps with zero usage time
            if (usageStats.totalTimeInForeground <= 0) {
                continue
            }

            val launchCount = launchCountsByPackage[usageStats.packageName] ?: 0

            // Extract enriched usage stats data
            val statsData = extractUsageStatsData(usageStats, launchCount, includeIcons)
            if (statsData != null) {
                usageStatsList.add(statsData)
            }
        }

        android.util.Log.d("UsageStatsHandler", "Retrieved ${usageStatsList.size} usage stats")
        return usageStatsList
    }

    /**
     * Queries usage statistics for a specific package within the specified time range.
     *
     * @param packageId Package name of the app
     * @param startTimeMs Start time in milliseconds since epoch
     * @param endTimeMs End time in milliseconds since epoch
     * @param includeIcons Whether to include app icons (can be expensive)
     * @return Map containing enriched usage statistics, or null if no usage/app not found
     */
    fun queryAppUsageStats(
        packageId: String,
        startTimeMs: Long,
        endTimeMs: Long,
        includeIcons: Boolean = true
    ): Map<String, Any?>? {
        ensureUsageStatsPermission()

        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_BEST,
            startTimeMs,
            endTimeMs
        ) ?: return null

        val usageStats = stats.firstOrNull { it.packageName == packageId } ?: return null
        if (usageStats.totalTimeInForeground <= 0) return null

        val launchCount = calculateLaunchCountForPackage(packageId, startTimeMs, endTimeMs)
        return extractUsageStatsData(usageStats, launchCount, includeIcons)
    }

    private fun ensureUsageStatsPermission() {
        val usageStatsStatus = permissionHandler.checkPermission(PermissionHandler.USAGE_STATS_KEY)
        if (usageStatsStatus != PermissionHandler.STATUS_GRANTED) {
            throw SecurityException(
                "Usage Access is not granted for android.usageStats"
            )
        }
    }

    /**
     * Calculates launch counts for all packages in a single events scan.
     *
     * @param startTimeMs Start time in milliseconds since epoch
     * @param endTimeMs End time in milliseconds since epoch
     * @return Map of package name to launch count
     */
    private fun calculateLaunchCounts(startTimeMs: Long, endTimeMs: Long): Map<String, Int> {
        val counts = mutableMapOf<String, Int>()
        val events = usageStatsManager.queryEvents(startTimeMs, endTimeMs)
        val event = UsageEvents.Event()

        while (events.hasNextEvent()) {
            events.getNextEvent(event)

            // Count ACTIVITY_RESUMED events (app moved to foreground)
            if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED) {
                val pkg = event.packageName
                if (!pkg.isNullOrBlank()) {
                    counts[pkg] = (counts[pkg] ?: 0) + 1
                }
            }
        }

        return counts
    }

    /**
     * Calculates the launch count for a specific package within a time range.
     *
     * This is used for the single-app query to avoid building counts for all packages.
     */
    private fun calculateLaunchCountForPackage(
        packageName: String,
        startTimeMs: Long,
        endTimeMs: Long
    ): Int {
        var launchCount = 0
        val events = usageStatsManager.queryEvents(startTimeMs, endTimeMs)
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED && event.packageName == packageName) {
                launchCount++
            }
        }
        return launchCount
    }

    /**
     * Extracts usage statistics data and enriches it with app metadata.
     *
     * @param usageStats Android UsageStats object
     * @param launchCount Calculated launch count for the app
     * @param includeIcons Whether to include app icons (can be expensive)
     * @return Map containing all usage stats data, or null if extraction fails
     */
    private fun extractUsageStatsData(
        usageStats: UsageStats,
        launchCount: Int,
        includeIcons: Boolean
    ): Map<String, Any?>? {
        val packageId = usageStats.packageName

        // Retrieve app metadata from PackageManager
        val appInfo = try {
            packageManager.getApplicationInfo(packageId, 0)
        } catch (e: Exception) {
            if (e is PackageManager.NameNotFoundException) {
                android.util.Log.w("UsageStatsHandler", "App not found: $packageId (likely uninstalled)")
                return null
            }
            throw e
        }

        val appName = appInfo.loadLabel(packageManager).toString()
        val appIcon = if (includeIcons) {
            AppInfoUtils.extractAppIcon(appInfo, packageManager)
        } else {
            null
        }
        val category = AppInfoUtils.getAppCategory(appInfo)
        val isSystemApp = AppInfoUtils.isSystemApp(appInfo)

        // Build the usage stats map matching the Flutter model
        val statsMap = mutableMapOf<String, Any?>(
            "packageId" to packageId,
            "appName" to appName,
            "appIcon" to appIcon,
            "category" to category,
            "isSystemApp" to isSystemApp,
            "totalDurationMs" to usageStats.totalTimeInForeground,
            "totalLaunchCount" to launchCount,
            "bucketStartMs" to if (usageStats.firstTimeStamp > 0) usageStats.firstTimeStamp else null,
            "bucketEndMs" to if (usageStats.lastTimeStamp > 0) usageStats.lastTimeStamp else null,
            "lastTimeUsedMs" to if (usageStats.lastTimeUsed > 0) usageStats.lastTimeUsed else null
        )

        // Add Android Q+ specific field (lastTimeVisible)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val lastTimeVisible = usageStats.lastTimeVisible
            statsMap["lastTimeVisibleMs"] = if (lastTimeVisible > 0) lastTimeVisible else null
        }

        return statsMap
    }
}
