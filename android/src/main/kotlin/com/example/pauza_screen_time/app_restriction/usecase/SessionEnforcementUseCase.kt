package com.example.pauza_screen_time.app_restriction.usecase

import android.content.Context
import com.example.pauza_screen_time.app_restriction.RestrictionManager
import com.example.pauza_screen_time.app_restriction.RestrictionSessionController
import com.example.pauza_screen_time.app_restriction.alarm.RestrictionAlarmOrchestrator
import com.example.pauza_screen_time.app_restriction.lifecycle.LifecycleReasonConstants
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
        val state = sessionController.resolveSessionState()
        val previousSnapshot = sessionController.captureLifecycleSnapshot()

        if (state.activeModeSource == RestrictionModeSource.NONE) {
            throw IllegalStateException("No active restriction session to pause.")
        }
        if (restrictionManager.isPausedNow()) {
            throw IllegalStateException("Restriction enforcement is already paused.")
        }

        restrictionManager.pauseFor(durationMs)
        RestrictionAlarmOrchestrator(context).rescheduleAll()
        // Note: dismiss is handled inside applyCurrentEnforcementState when
        // enforcement is no longer active, so no separate requestDismiss() needed.
        sessionController.applyCurrentEnforcementState(
            trigger = LifecycleReasonConstants.MANUAL,
            previousLifecycleSnapshot = previousSnapshot,
        )
    }

    fun resumeEnforcement() {
        val restrictionManager = RestrictionManager.getInstance(context)
        val sessionController = RestrictionSessionController(context)
        val state = sessionController.resolveSessionState()
        val previousSnapshot = sessionController.captureLifecycleSnapshot()

        if (state.activeModeSource == RestrictionModeSource.NONE) {
            throw IllegalStateException("No active restriction session to resume.")
        }
        if (!restrictionManager.isPausedNow()) {
            throw IllegalStateException("Restriction enforcement is not paused.")
        }

        restrictionManager.clearPause()
        RestrictionAlarmOrchestrator(context).rescheduleAll()
        sessionController.applyCurrentEnforcementState(
            trigger = LifecycleReasonConstants.MANUAL,
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
            trigger = LifecycleReasonConstants.MANUAL,
        )
    }

    fun endSession(durationMs: Long? = null, reason: String? = null) {
        if (durationMs != null) {
            scheduleEndSession(durationMs)
            return
        }
        endSessionNow(reason)
    }

    private fun scheduleEndSession(durationMs: Long) {
        val restrictionManager = RestrictionManager.getInstance(context)
        val state = RestrictionSessionController(context).resolveSessionState()
        if (state.activeModeSource == RestrictionModeSource.NONE || state.activeModeId == null) {
            throw IllegalStateException("No active restriction session to end")
        }
        restrictionManager.setPendingEndSessionEpochMs(System.currentTimeMillis() + durationMs)
        RestrictionAlarmOrchestrator(context).rescheduleAll()
    }

    fun endSessionNow(reason: String? = null) {
        val restrictionManager = RestrictionManager.getInstance(context)
        val sessionController = RestrictionSessionController(context)
        val state = sessionController.resolveSessionState()
        if (state.activeModeSource == RestrictionModeSource.NONE || state.activeModeId == null) {
            throw IllegalStateException("No active restriction session to end")
        }
        if (state.activeModeSource == RestrictionModeSource.SCHEDULE) {
            val suppressionUntilMs = state.activeScheduleBoundaryEndEpochMs
            if (suppressionUntilMs != null && suppressionUntilMs > System.currentTimeMillis()) {
                restrictionManager.setScheduleSuppression(
                    modeId = state.activeModeId,
                    untilEpochMs = suppressionUntilMs,
                )
            }
        }
        restrictionManager.clearManualSessionEndEpochMs()
        restrictionManager.clearPendingEndSessionEpochMs()
        sessionController.endSession(
            source = RestrictionModeSource.MANUAL,
            trigger = reason ?: LifecycleReasonConstants.MANUAL,
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
