package com.example.pauza_screen_time.usage_stats.model

/**
 * DTO for a single raw usage event from Android's UsageEvents API.
 *
 * @param timestampMs  Time the event occurred (ms since epoch).
 * @param packageName  Package of the app or system that generated the event.
 * @param className    Activity/service class name; may be null for system-level events
 *                     (e.g. SCREEN_INTERACTIVE, KEYGUARD_SHOWN).
 * @param eventType    One of the UsageEvents.Event integer constants.
 */
data class UsageEventDto(
    val timestampMs: Long,
    val packageName: String,
    val className: String?,
    val eventType: Int,
) {
    fun toChannelMap(): Map<String, Any?> = mapOf(
        "timestampMs" to timestampMs,
        "packageName" to packageName,
        "className" to className,
        "eventType" to eventType,
    )

    companion object {
        fun fromChannelMap(map: Map<String, Any?>): UsageEventDto = UsageEventDto(
            timestampMs = (map["timestampMs"] as Number).toLong(),
            packageName = map["packageName"] as String,
            className = map["className"] as? String,
            eventType = (map["eventType"] as Number).toInt(),
        )
    }
}
