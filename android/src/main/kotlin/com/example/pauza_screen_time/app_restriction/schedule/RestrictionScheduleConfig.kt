package com.example.pauza_screen_time.app_restriction.schedule

internal data class RestrictionScheduleConfig(
    val enabled: Boolean,
    val schedules: List<RestrictionScheduleEntry>,
)
