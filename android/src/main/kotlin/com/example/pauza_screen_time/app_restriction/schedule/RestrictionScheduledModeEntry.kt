package com.example.pauza_screen_time.app_restriction.schedule

internal data class RestrictionScheduledModeEntry(
    val modeId: String,
    val schedule: RestrictionScheduleEntry?,
    val blockedAppIds: List<String>,
) {
    fun toChannelMap(): Map<String, Any?> {
        return mapOf(
            "modeId" to modeId,
            "schedule" to schedule?.toChannelMap(),
            "blockedAppIds" to blockedAppIds,
        )
    }
}
