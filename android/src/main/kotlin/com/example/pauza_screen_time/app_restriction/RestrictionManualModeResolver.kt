package com.example.pauza_screen_time.app_restriction

import com.example.pauza_screen_time.app_restriction.model.ActiveSession
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource

internal object RestrictionManualModeResolver {
    fun resolveActiveSession(
        restrictionManager: RestrictionManager,
    ): ActiveSession? {
        return restrictionManager.getActiveSession()
    }

    fun resolveActiveManualMode(
        restrictionManager: RestrictionManager,
    ): ActiveSession? {
        val activeSession = resolveActiveSession(restrictionManager) ?: return null
        if (activeSession.source != RestrictionModeSource.MANUAL) {
            return null
        }
        return activeSession
    }
}
