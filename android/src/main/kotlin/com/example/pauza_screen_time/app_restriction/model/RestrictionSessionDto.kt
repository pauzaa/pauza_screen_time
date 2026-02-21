package com.example.pauza_screen_time.app_restriction.model

enum class RestrictionModeSource(val wireValue: String) {
    NONE("none"),
    MANUAL("manual"),
    SCHEDULE("schedule");

    companion object {
        /**
         * Parses the wire value for [RestrictionModeSource].
         * @throws IllegalArgumentException if [raw] is not a known wire value.
         */
        fun fromWireValue(raw: String): RestrictionModeSource =
            entries.firstOrNull { it.wireValue == raw }
                ?: throw IllegalArgumentException("Unknown RestrictionModeSource wire value: '$raw'")
    }
}

data class RestrictionSessionDto(
    val isScheduleEnabled: Boolean,
    val isInScheduleNow: Boolean,
    val pausedUntilEpochMs: Long?,
    val activeMode: RestrictionModeDto?,
    val activeModeSource: RestrictionModeSource,
    val currentSessionEvents: List<Map<String, Any?>>,
) {
    fun toChannelMap(): Map<String, Any?> {
        return mapOf(
            "isScheduleEnabled" to isScheduleEnabled,
            "isInScheduleNow" to isInScheduleNow,
            "pausedUntilEpochMs" to pausedUntilEpochMs,
            "activeMode" to activeMode?.toChannelMap(),
            "activeModeSource" to activeModeSource.wireValue,
            "currentSessionEvents" to currentSessionEvents,
        )
    }
}

data class RestrictionModeDto(
    val modeId: String,
    val blockedAppIds: List<String>,
    val schedule: RestrictionScheduleDto? = null,
) {
    fun toChannelMap(): Map<String, Any?> {
        return mapOf(
            "modeId" to modeId,
            "blockedAppIds" to blockedAppIds,
            "schedule" to schedule?.toChannelMap(),
        )
    }
}
