package com.example.pauza_screen_time.app_restriction.schedule

internal data class RestrictionScheduledModesConfig(
    val scheduleEnforcementEnabled: Boolean,
    val modes: List<RestrictionScheduledModeEntry>,
) {
    fun toChannelMap(): Map<String, Any?> {
        return mapOf(
            "scheduleEnforcementEnabled" to scheduleEnforcementEnabled,
            "modes" to modes.map { it.toChannelMap() },
        )
    }
}
