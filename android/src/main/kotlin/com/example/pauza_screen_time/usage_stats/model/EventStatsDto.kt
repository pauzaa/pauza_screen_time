package com.example.pauza_screen_time.usage_stats.model

/**
 * DTO for aggregated device-level event statistics from Android's queryEventStats() API.
 *
 * @param eventType       One of the UsageEvents.Event integer constants aggregated here:
 *                        SCREEN_INTERACTIVE (15), SCREEN_NON_INTERACTIVE (16),
 *                        KEYGUARD_SHOWN (17), KEYGUARD_HIDDEN (18).
 * @param count           Number of times this event occurred in the interval.
 * @param totalTimeMs     Total time (ms) this state was active in the interval.
 * @param firstTimestampMs Start of the measurement interval (ms since epoch).
 * @param lastTimestampMs  End of the measurement interval (ms since epoch).
 * @param lastEventTimeMs  When this event last triggered (ms since epoch).
 */
data class EventStatsDto(
    val eventType: Int,
    val count: Int,
    val totalTimeMs: Long,
    val firstTimestampMs: Long,
    val lastTimestampMs: Long,
    val lastEventTimeMs: Long,
) {
    fun toChannelMap(): Map<String, Any?> = mapOf(
        "eventType" to eventType,
        "count" to count,
        "totalTimeMs" to totalTimeMs,
        "firstTimestampMs" to firstTimestampMs,
        "lastTimestampMs" to lastTimestampMs,
        "lastEventTimeMs" to lastEventTimeMs,
    )

    companion object {
        fun fromChannelMap(map: Map<String, Any?>): EventStatsDto = EventStatsDto(
            eventType = (map["eventType"] as Number).toInt(),
            count = (map["count"] as Number).toInt(),
            totalTimeMs = (map["totalTimeMs"] as Number).toLong(),
            firstTimestampMs = (map["firstTimestampMs"] as Number).toLong(),
            lastTimestampMs = (map["lastTimestampMs"] as Number).toLong(),
            lastEventTimeMs = (map["lastEventTimeMs"] as Number).toLong(),
        )
    }
}
