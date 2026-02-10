package com.example.pauza_screen_time.app_restriction.model

enum class RestrictionModeSource(val wireValue: String) {
    NONE("none"),
    MANUAL("manual"),
    SCHEDULE("schedule"),
}

data class RestrictionSessionDto(
    val isActiveNow: Boolean,
    val isPausedNow: Boolean,
    val isScheduleEnabled: Boolean,
    val isInScheduleNow: Boolean,
    val pausedUntilEpochMs: Long?,
    val restrictedApps: List<String>,
    val activeModeId: String?,
    val activeModeSource: RestrictionModeSource,
) {
    fun toChannelMap(): Map<String, Any?> {
        return mapOf(
            "isActiveNow" to isActiveNow,
            "isPausedNow" to isPausedNow,
            "isScheduleEnabled" to isScheduleEnabled,
            "isInScheduleNow" to isInScheduleNow,
            "pausedUntilEpochMs" to pausedUntilEpochMs,
            "restrictedApps" to restrictedApps,
            "activeModeId" to activeModeId,
            "activeModeSource" to activeModeSource.wireValue,
        )
    }
}
