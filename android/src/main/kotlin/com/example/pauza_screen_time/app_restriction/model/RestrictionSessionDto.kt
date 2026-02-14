package com.example.pauza_screen_time.app_restriction.model

enum class RestrictionModeSource(val wireValue: String) {
    NONE("none"),
    MANUAL("manual"),
    SCHEDULE("schedule"),
}

data class RestrictionSessionDto(
    val isScheduleEnabled: Boolean,
    val isInScheduleNow: Boolean,
    val pausedUntilEpochMs: Long?,
    val activeMode: RestrictionModeDto?,
    val activeModeSource: RestrictionModeSource,
) {
    fun toChannelMap(): Map<String, Any?> {
        return mapOf(
            "isScheduleEnabled" to isScheduleEnabled,
            "isInScheduleNow" to isInScheduleNow,
            "pausedUntilEpochMs" to pausedUntilEpochMs,
            "activeMode" to activeMode?.toChannelMap(),
            "activeModeSource" to activeModeSource.wireValue,
        )
    }
}

data class RestrictionModeDto(
    val modeId: String,
    val blockedAppIds: List<String>,
    val schedule: Any? = null,
) {
    fun toChannelMap(): Map<String, Any?> {
        return mapOf(
            "modeId" to modeId,
            "blockedAppIds" to blockedAppIds,
            "schedule" to schedule,
        )
    }
}
