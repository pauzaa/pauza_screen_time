package com.example.pauza_screen_time.app_restriction.usecase

import android.content.Context
import com.example.pauza_screen_time.app_restriction.RestrictionManager
import com.example.pauza_screen_time.app_restriction.RestrictionSessionController
import com.example.pauza_screen_time.app_restriction.alarm.RestrictionAlarmOrchestrator
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeDto
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import com.example.pauza_screen_time.app_restriction.model.RestrictionSessionDto

internal class SessionEnforcementUseCase(private val context: Context) {

    fun isRestrictionSessionActiveNow(isPrerequisitesMet: Boolean): Boolean {
        val sessionState = RestrictionSessionController(context).resolveSessionState()
        val isPausedNow = RestrictionManager.getInstance(context).isPausedNow()
        val shouldEnforceSession = sessionState.activeModeSource != RestrictionModeSource.NONE
        return sessionState.blockedAppIds.isNotEmpty() && !isPausedNow && isPrerequisitesMet && shouldEnforceSession
    }

    fun pauseEnforcement(durationMs: Long) {
        val restrictionManager = RestrictionManager.getInstance(context)
        val sessionController = RestrictionSessionController(context)
        val previousSnapshot = sessionController.captureLifecycleSnapshot()
        
        if (restrictionManager.isPausedNow()) {
            throw IllegalStateException("Restriction enforcement is already paused")
        }

        restrictionManager.pauseFor(durationMs)
        RestrictionAlarmOrchestrator(context).rescheduleAll()
        com.example.pauza_screen_time.app_restriction.ShieldOverlayManager.getInstanceOrNull()?.hideShield()
        sessionController.applyCurrentEnforcementState(
            trigger = "pause_enforcement",
            previousLifecycleSnapshot = previousSnapshot,
        )
    }

    fun resumeEnforcement() {
        val sessionController = RestrictionSessionController(context)
        val previousSnapshot = sessionController.captureLifecycleSnapshot()
        RestrictionManager.getInstance(context).clearPause()
        RestrictionAlarmOrchestrator(context).rescheduleAll()
        sessionController.applyCurrentEnforcementState(
            trigger = "resume_enforcement",
            previousLifecycleSnapshot = previousSnapshot,
        )
    }

    fun hasActiveSession(): Boolean {
        return RestrictionSessionController(context).resolveSessionState().activeModeSource != RestrictionModeSource.NONE
    }

    fun startSession(modeId: String, blockedAppIds: List<String>, durationMs: Long? = null) {
        val restrictionManager = RestrictionManager.getInstance(context)
        if (durationMs != null) {
            restrictionManager.setManualSessionEndEpochMs(System.currentTimeMillis() + durationMs)
        } else {
            restrictionManager.clearManualSessionEndEpochMs()
        }
        RestrictionSessionController(context).startSession(
            modeId = modeId,
            blockedAppIds = blockedAppIds,
            source = RestrictionModeSource.MANUAL,
            trigger = "start_session_manual",
        )
    }

    fun endSession() {
        RestrictionManager.getInstance(context).clearManualSessionEndEpochMs()
        RestrictionSessionController(context).endSession(
            source = RestrictionModeSource.MANUAL,
            trigger = "end_session_manual",
        )
    }

    fun getRestrictionSession(): RestrictionSessionDto {
        val restrictionManager = RestrictionManager.getInstance(context)
        val pausedUntilEpochMs = restrictionManager.getPausedUntilEpochMs()
        val isPausedNow = pausedUntilEpochMs > 0L
        val state = RestrictionSessionController(context).resolveSessionState()
        val activeSession = restrictionManager.getActiveSession()
        val currentSessionEvents = if (activeSession == null) {
            emptyList()
        } else {
            restrictionManager
                .loadActiveSessionLifecycleEvents()
                .map { it.toChannelMap() }
        }
        return RestrictionSessionDto(
            isScheduleEnabled = state.isScheduleEnabled,
            isInScheduleNow = state.isInScheduleNow,
            pausedUntilEpochMs = if (isPausedNow) pausedUntilEpochMs else null,
            activeMode = state.activeModeId?.let { activeModeId ->
                RestrictionModeDto(
                    modeId = activeModeId,
                    blockedAppIds = state.blockedAppIds,
                )
            },
            activeModeSource = state.activeModeSource,
            currentSessionEvents = currentSessionEvents,
        )
    }
}
