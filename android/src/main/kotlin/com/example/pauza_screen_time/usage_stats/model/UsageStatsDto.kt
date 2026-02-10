package com.example.pauza_screen_time.usage_stats.model

data class UsageStatsDto(
    val packageId: String,
    val appName: String,
    val appIcon: ByteArray?,
    val category: String?,
    val isSystemApp: Boolean,
    val totalDurationMs: Long,
    val totalLaunchCount: Int,
    val bucketStartMs: Long?,
    val bucketEndMs: Long?,
    val lastTimeUsedMs: Long?,
    val lastTimeVisibleMs: Long?,
) {
    fun toChannelMap(): Map<String, Any?> {
        return mapOf(
            "packageId" to packageId,
            "appName" to appName,
            "appIcon" to appIcon,
            "category" to category,
            "isSystemApp" to isSystemApp,
            "totalDurationMs" to totalDurationMs,
            "totalLaunchCount" to totalLaunchCount,
            "bucketStartMs" to bucketStartMs,
            "bucketEndMs" to bucketEndMs,
            "lastTimeUsedMs" to lastTimeUsedMs,
            "lastTimeVisibleMs" to lastTimeVisibleMs,
        )
    }
}
