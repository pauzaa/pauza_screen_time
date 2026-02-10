package com.example.pauza_screen_time.app_restriction

import android.content.Context
import com.example.pauza_screen_time.app_restriction.alarm.RestrictionAlarmOrchestrator
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleCalculator
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModeResolver
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModesStore

internal class RestrictionSessionController(
    context: Context,
) {
    private val appContext = context.applicationContext
    private val restrictionManager = RestrictionManager.getInstance(appContext)
    private val modesStore = RestrictionScheduledModesStore(appContext)
    private val scheduleCalculator = RestrictionScheduleCalculator()

    fun startSession(
        modeId: String,
        blockedAppIds: List<String>,
        source: RestrictionModeSource,
        trigger: String,
        rescheduleAlarms: Boolean = true,
    ) {
        restrictionManager.setActiveSession(modeId, blockedAppIds, source)
        if (rescheduleAlarms) {
            RestrictionAlarmOrchestrator(appContext).rescheduleAll()
        }
        applyCurrentEnforcementState(trigger = trigger)
    }

    fun endSession(
        source: RestrictionModeSource,
        trigger: String,
        rescheduleAlarms: Boolean = true,
    ) {
        val activeSession = restrictionManager.getActiveSession()
        if (activeSession != null) {
            val shouldClear = when (source) {
                RestrictionModeSource.SCHEDULE -> activeSession.source == RestrictionModeSource.SCHEDULE
                RestrictionModeSource.MANUAL,
                RestrictionModeSource.NONE,
                -> true
            }
            if (shouldClear) {
                restrictionManager.clearActiveSession()
            }
        }

        if (rescheduleAlarms) {
            RestrictionAlarmOrchestrator(appContext).rescheduleAll()
        }
        applyCurrentEnforcementState(trigger = trigger)
    }

    fun applyCurrentEnforcementState(trigger: String): SessionState {
        val state = resolveSessionState()
        restrictionManager.setRestrictedApps(state.blockedAppIds)

        val shouldEnforce = state.activeModeSource != RestrictionModeSource.NONE
        if (shouldEnforce) {
            AppMonitoringService.getInstance()?.enforceCurrentForegroundNow(trigger = trigger)
        } else {
            ShieldOverlayManager.getInstanceOrNull()?.hideShield()
        }

        return state
    }

    fun resolveSessionState(): SessionState {
        val modesConfig = modesStore.getConfig()
        val scheduleResolution = RestrictionScheduledModeResolver.resolveNow(
            config = modesConfig,
            scheduleCalculator = scheduleCalculator,
        )

        val activeSession = restrictionManager.getActiveSession()
        if (activeSession != null) {
            if (activeSession.source == RestrictionModeSource.MANUAL) {
                return SessionState(
                    isScheduleEnabled = modesConfig.enabled,
                    isInScheduleNow = scheduleResolution.isInScheduleNow,
                    blockedAppIds = activeSession.blockedAppIds,
                    activeModeId = activeSession.modeId,
                    activeModeSource = RestrictionModeSource.MANUAL,
                )
            }
            if (scheduleResolution.isInScheduleNow && activeSession.modeId == scheduleResolution.activeModeId) {
                return SessionState(
                    isScheduleEnabled = modesConfig.enabled,
                    isInScheduleNow = true,
                    blockedAppIds = activeSession.blockedAppIds,
                    activeModeId = activeSession.modeId,
                    activeModeSource = RestrictionModeSource.SCHEDULE,
                )
            }
            restrictionManager.clearActiveSession()
        }

        if (scheduleResolution.isInScheduleNow) {
            val modeId = scheduleResolution.activeModeId
            if (modeId != null) {
                restrictionManager.setActiveSession(
                    modeId = modeId,
                    blockedAppIds = scheduleResolution.blockedAppIds,
                    source = RestrictionModeSource.SCHEDULE,
                )
            }
            return SessionState(
                isScheduleEnabled = modesConfig.enabled,
                isInScheduleNow = true,
                blockedAppIds = scheduleResolution.blockedAppIds,
                activeModeId = scheduleResolution.activeModeId,
                activeModeSource = RestrictionModeSource.SCHEDULE,
            )
        }

        return SessionState(
            isScheduleEnabled = modesConfig.enabled,
            isInScheduleNow = false,
            blockedAppIds = emptyList(),
            activeModeId = null,
            activeModeSource = RestrictionModeSource.NONE,
        )
    }

    data class SessionState(
        val isScheduleEnabled: Boolean,
        val isInScheduleNow: Boolean,
        val blockedAppIds: List<String>,
        val activeModeId: String?,
        val activeModeSource: RestrictionModeSource,
    )
}
