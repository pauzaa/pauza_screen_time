package com.example.pauza_screen_time.app_restriction

internal object RestrictionManualModeResolver {
    fun resolveActiveManualMode(
        restrictionManager: RestrictionManager,
    ): RestrictionManager.ManualActiveMode? {
        return restrictionManager.getManualActiveMode()
    }
}
