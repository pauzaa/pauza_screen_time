package com.example.pauza_screen_time.app_restriction.schedule

internal data class RestrictionScheduledModesConfig(
    val enabled: Boolean,
    val modes: List<RestrictionScheduledModeEntry>,
) {
    fun toChannelMap(): Map<String, Any?> {
        return mapOf(
            "enabled" to enabled,
            "modes" to modes.map { it.toChannelMap() },
        )
    }
}
