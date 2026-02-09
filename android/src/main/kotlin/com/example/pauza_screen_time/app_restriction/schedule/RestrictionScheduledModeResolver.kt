package com.example.pauza_screen_time.app_restriction.schedule

internal object RestrictionScheduledModeResolver {
    data class Resolution(
        val isInScheduleNow: Boolean,
        val blockedAppIds: List<String>,
    )

    fun resolveNow(
        config: RestrictionScheduledModesConfig,
        scheduleCalculator: RestrictionScheduleCalculator = RestrictionScheduleCalculator(),
    ): Resolution {
        if (!config.enabled) {
            return Resolution(isInScheduleNow = false, blockedAppIds = emptyList())
        }
        val enabledModes = config.scheduledModes.filter { it.isEnabled }
        if (enabledModes.isEmpty()) {
            return Resolution(isInScheduleNow = false, blockedAppIds = emptyList())
        }

        var matchedMode: RestrictionScheduledModeEntry? = null
        for (mode in enabledModes) {
            val isActive = scheduleCalculator.isInSessionNow(
                RestrictionScheduleConfig(enabled = true, schedules = listOf(mode.schedule)),
            )
            if (!isActive) {
                continue
            }
            if (matchedMode != null) {
                return Resolution(isInScheduleNow = false, blockedAppIds = emptyList())
            }
            matchedMode = mode
        }
        if (matchedMode == null) {
            return Resolution(isInScheduleNow = false, blockedAppIds = emptyList())
        }
        return Resolution(
            isInScheduleNow = true,
            blockedAppIds = matchedMode.blockedAppIds,
        )
    }
}
