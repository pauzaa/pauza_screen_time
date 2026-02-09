package com.example.pauza_screen_time.app_restriction.schedule

internal object RestrictionScheduledModeResolver {
    data class Resolution(
        val isInScheduleNow: Boolean,
        val activeModeId: String?,
        val blockedAppIds: List<String>,
    )

    fun resolveNow(
        config: RestrictionScheduledModesConfig,
        scheduleCalculator: RestrictionScheduleCalculator = RestrictionScheduleCalculator(),
    ): Resolution {
        if (!config.enabled) {
            return Resolution(isInScheduleNow = false, activeModeId = null, blockedAppIds = emptyList())
        }
        val enabledModes = config.modes.filter { it.isEnabled && it.schedule != null }
        if (enabledModes.isEmpty()) {
            return Resolution(isInScheduleNow = false, activeModeId = null, blockedAppIds = emptyList())
        }

        var matchedMode: RestrictionScheduledModeEntry? = null
        for (mode in enabledModes) {
            val schedule = mode.schedule ?: continue
            val isActive = scheduleCalculator.isInSessionNow(
                RestrictionScheduleConfig(enabled = true, schedules = listOf(schedule)),
            )
            if (!isActive) {
                continue
            }
            if (matchedMode != null) {
                return Resolution(isInScheduleNow = false, activeModeId = null, blockedAppIds = emptyList())
            }
            matchedMode = mode
        }
        if (matchedMode == null) {
            return Resolution(isInScheduleNow = false, activeModeId = null, blockedAppIds = emptyList())
        }
        return Resolution(
            isInScheduleNow = true,
            activeModeId = matchedMode.modeId,
            blockedAppIds = matchedMode.blockedAppIds,
        )
    }
}
