package com.example.pauza_screen_time.usage_stats.repository

import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.app.usage.UsageEvents
import android.os.Build
import com.example.pauza_screen_time.permissions.PermissionHandler
import com.example.pauza_screen_time.usage_stats.model.UsageStatsDto
import com.example.pauza_screen_time.utils.AppIconExtractor
import com.example.pauza_screen_time.utils.AppInfoUtils

private data class AggregatedStats(
    val packageName: String,
    val totalTimeInForeground: Long,
    val firstTimeStamp: Long,
    val lastTimeStamp: Long,
    val lastTimeUsed: Long,
    val lastTimeVisible: Long,
)

/**
 * Repository for per-app and all-app usage statistics.
 *
 * Wraps [UsageStatsManager.queryUsageStats] and enriches results with app
 * metadata (name, icon, category) from [PackageManager].
 *
 * Requires [android.Manifest.permission.PACKAGE_USAGE_STATS].
 * Throws [SecurityException] when the permission is not granted.
 */
class UsageStatsRepository(private val context: Context) {

    private val usageStatsManager: UsageStatsManager =
        context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    private val packageManager: PackageManager = context.packageManager
    private val permissionHandler = PermissionHandler(context)

    // ============================================================
    // Public API
    // ============================================================

    /**
     * Queries usage statistics for all apps within the specified time range.
     *
     * Apps with zero foreground time are excluded from results.
     *
     * @param startTimeMs Start time in milliseconds since epoch
     * @param endTimeMs   End time in milliseconds since epoch
     * @param includeIcons Whether to include app icons in results (expensive)
     * @return List of enriched usage stats, one per app that had foreground use
     * @throws SecurityException if Usage Access permission is not granted
     */
    fun queryUsageStats(
        startTimeMs: Long,
        endTimeMs: Long,
        includeIcons: Boolean = true,
    ): List<UsageStatsDto> {
        ensurePermission()

        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_BEST,
            startTimeMs,
            endTimeMs,
        )

        if (stats.isNullOrEmpty()) {
            android.util.Log.w(TAG, "No usage stats found for the given time range")
            return emptyList()
        }

        // Single events scan to count launches — avoids O(N_apps × N_events).
        val launchCountsByPackage = calculateLaunchCounts(startTimeMs, endTimeMs)

        val aggregated = aggregateStats(stats)

        val result = mutableListOf<UsageStatsDto>()
        for (agg in aggregated) {
            if (agg.totalTimeInForeground <= 0) continue
            val dto = extractUsageStatsData(
                aggregated = agg,
                launchCount = launchCountsByPackage[agg.packageName] ?: 0,
                includeIcons = includeIcons,
            )
            if (dto != null) result.add(dto)
        }

        android.util.Log.d(TAG, "Retrieved ${result.size} usage stats")
        return result
    }

    /**
     * Queries usage statistics for a specific package.
     *
     * @param packageId   Package name of the app
     * @param startTimeMs Start time in milliseconds since epoch
     * @param endTimeMs   End time in milliseconds since epoch
     * @param includeIcons Whether to include the app icon (expensive)
     * @return Enriched usage stats for the app, or null if the app has no usage
     * @throws SecurityException if Usage Access permission is not granted
     */
    fun queryAppUsageStats(
        packageId: String,
        startTimeMs: Long,
        endTimeMs: Long,
        includeIcons: Boolean = true,
    ): UsageStatsDto? {
        ensurePermission()

        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_BEST,
            startTimeMs,
            endTimeMs,
        ) ?: return null

        val matching = stats.filter { it.packageName == packageId }
        if (matching.isEmpty()) return null

        val aggregated = AggregatedStats(
            packageName = packageId,
            totalTimeInForeground = matching.sumOf { it.totalTimeInForeground },
            firstTimeStamp = matching.minOf { it.firstTimeStamp },
            lastTimeStamp = matching.maxOf { it.lastTimeStamp },
            lastTimeUsed = matching.maxOf { it.lastTimeUsed },
            lastTimeVisible = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                matching.maxOf { it.lastTimeVisible } else 0L,
        )
        if (aggregated.totalTimeInForeground <= 0) return null

        val launchCount = calculateLaunchCountForPackage(packageId, startTimeMs, endTimeMs)
        return extractUsageStatsData(aggregated, launchCount, includeIcons)
    }

    // ============================================================
    // Private helpers
    // ============================================================

    private fun ensurePermission() {
        val status = permissionHandler.checkPermission(PermissionHandler.USAGE_STATS_KEY)
        if (status != PermissionHandler.STATUS_GRANTED) {
            throw SecurityException("Usage Access is not granted for android.usageStats")
        }
    }

    /**
     * Counts ACTIVITY_RESUMED events for all packages in a single events scan.
     */
    private fun calculateLaunchCounts(startTimeMs: Long, endTimeMs: Long): Map<String, Int> {
        val counts = mutableMapOf<String, Int>()
        val events = usageStatsManager.queryEvents(startTimeMs, endTimeMs) ?: return counts
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
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
     * Counts ACTIVITY_RESUMED events for a single package.
     *
     * Used for the single-app query to avoid building the full launch-count map.
     */
    private fun calculateLaunchCountForPackage(
        packageName: String,
        startTimeMs: Long,
        endTimeMs: Long,
    ): Int {
        var count = 0
        val events = usageStatsManager.queryEvents(startTimeMs, endTimeMs) ?: return 0
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED &&
                event.packageName == packageName
            ) {
                count++
            }
        }
        return count
    }

    /**
     * Groups raw [UsageStats] entries by package name, summing durations and
     * taking min/max timestamps.
     */
    private fun aggregateStats(stats: List<UsageStats>): List<AggregatedStats> {
        return stats.groupBy { it.packageName }.map { (packageName, entries) ->
            AggregatedStats(
                packageName = packageName,
                totalTimeInForeground = entries.sumOf { it.totalTimeInForeground },
                firstTimeStamp = entries.minOf { it.firstTimeStamp },
                lastTimeStamp = entries.maxOf { it.lastTimeStamp },
                lastTimeUsed = entries.maxOf { it.lastTimeUsed },
                lastTimeVisible = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    entries.maxOf { it.lastTimeVisible } else 0L,
            )
        }
    }

    /**
     * Builds a [UsageStatsDto] from [AggregatedStats] and enriches it with
     * app metadata. Returns null if the app is no longer installed.
     */
    private fun extractUsageStatsData(
        aggregated: AggregatedStats,
        launchCount: Int,
        includeIcons: Boolean,
    ): UsageStatsDto? {
        val packageId = aggregated.packageName
        val appInfo = try {
            packageManager.getApplicationInfo(packageId, 0)
        } catch (e: PackageManager.NameNotFoundException) {
            android.util.Log.w(TAG, "App not found: $packageId (likely uninstalled)")
            return null
        }

        return UsageStatsDto(
            packageId = packageId,
            appName = appInfo.loadLabel(packageManager).toString(),
            appIcon = if (includeIcons) AppIconExtractor.extractOrNull(appInfo, packageManager) else null,
            category = AppInfoUtils.getAppCategory(appInfo),
            isSystemApp = AppInfoUtils.isSystemApp(appInfo),
            totalDurationMs = aggregated.totalTimeInForeground,
            totalLaunchCount = launchCount,
            bucketStartMs = aggregated.firstTimeStamp.takeIf { it > 0 },
            bucketEndMs = aggregated.lastTimeStamp.takeIf { it > 0 },
            lastTimeUsedMs = aggregated.lastTimeUsed.takeIf { it > 0 },
            lastTimeVisibleMs = aggregated.lastTimeVisible.takeIf { it > 0 },
        )
    }

    companion object {
        private const val TAG = "UsageStatsRepository"
    }
}
