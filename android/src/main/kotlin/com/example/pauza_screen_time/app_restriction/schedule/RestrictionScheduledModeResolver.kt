package com.example.pauza_screen_time.app_restriction.schedule

internal object RestrictionScheduledModeResolver {
    data class Resolution(
        val isInScheduleNow: Boolean,
        val activeModeId: String?,
        val blockedAppIds: List<String>,
        val activeIntervalEndEpochMs: Long?,
    )

    fun resolveNow(
        config: RestrictionScheduledModesConfig,
        scheduleCalculator: RestrictionScheduleCalculator = RestrictionScheduleCalculator(),
    ): Resolution {
        if (!config.scheduleEnforcementEnabled) {
            return Resolution(
                isInScheduleNow = false,
                activeModeId = null,
                blockedAppIds = emptyList(),
                activeIntervalEndEpochMs = null,
            )
        }
        val scheduledModes = config.modes.filter { it.schedule != null }
        if (scheduledModes.isEmpty()) {
            return Resolution(
                isInScheduleNow = false,
                activeModeId = null,
                blockedAppIds = emptyList(),
                activeIntervalEndEpochMs = null,
            )
        }

        var matchedMode: RestrictionScheduledModeEntry? = null
        var matchedEndEpochMs: Long? = null
        for (mode in scheduledModes) {
            val schedule = mode.schedule ?: continue
            val isActive = scheduleCalculator.isInSessionNow(
                RestrictionScheduleConfig(enabled = true, schedules = listOf(schedule)),
            )
            if (!isActive) {
                continue
            }
            if (matchedMode != null) {
                return Resolution(
                    isInScheduleNow = false,
                    activeModeId = null,
                    blockedAppIds = emptyList(),
                    activeIntervalEndEpochMs = null,
                )
            }
            matchedMode = mode
            val boundary = scheduleCalculator.nextBoundary(
                RestrictionScheduleConfig(enabled = true, schedules = listOf(schedule)),
            )
            matchedEndEpochMs = if (boundary?.type == RestrictionScheduleBoundaryType.END) {
                boundary.at.toInstant().toEpochMilli()
            } else {
                null
            }
        }
        if (matchedMode == null) {
            return Resolution(
                isInScheduleNow = false,
                activeModeId = null,
                blockedAppIds = emptyList(),
                activeIntervalEndEpochMs = null,
            )
        }
        return Resolution(
            isInScheduleNow = true,
            activeModeId = matchedMode.modeId,
            blockedAppIds = matchedMode.blockedAppIds,
            activeIntervalEndEpochMs = matchedEndEpochMs,
        )
    }
}
