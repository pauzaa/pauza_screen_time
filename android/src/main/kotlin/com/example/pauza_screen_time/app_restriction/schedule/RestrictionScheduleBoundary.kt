package com.example.pauza_screen_time.app_restriction.schedule

import java.time.ZonedDateTime

internal enum class RestrictionScheduleBoundaryType {
    START,
    END,
}

internal data class RestrictionScheduleBoundary(
    val type: RestrictionScheduleBoundaryType,
    val at: ZonedDateTime,
)
