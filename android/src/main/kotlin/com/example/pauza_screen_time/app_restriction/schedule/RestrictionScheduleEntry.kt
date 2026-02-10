package com.example.pauza_screen_time.app_restriction.schedule

internal data class RestrictionScheduleEntry(
    val daysOfWeekIso: Set<Int>,
    val startMinutes: Int,
    val endMinutes: Int,
) {
    fun toChannelMap(): Map<String, Any?> {
        return mapOf(
            "daysOfWeekIso" to daysOfWeekIso.sorted(),
            "startMinutes" to startMinutes,
            "endMinutes" to endMinutes,
        )
    }
}
