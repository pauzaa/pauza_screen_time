package com.example.pauza_screen_time.app_restriction.schedule

internal data class RestrictionScheduledModeEntry(
    val modeId: String,
    val isEnabled: Boolean,
    val schedule: RestrictionScheduleEntry,
    val blockedAppIds: List<String>,
)
