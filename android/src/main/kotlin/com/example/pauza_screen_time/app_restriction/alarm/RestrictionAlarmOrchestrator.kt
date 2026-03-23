package com.example.pauza_screen_time.app_restriction.alarm

import android.content.Context
import android.os.SystemClock
import android.util.Log
import com.example.pauza_screen_time.app_restriction.RestrictionManager
import com.example.pauza_screen_time.app_restriction.RestrictionSessionController
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleBoundaryType
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleCalculator
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleConfig
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModesStore
import com.example.pauza_screen_time.app_restriction.lifecycle.LifecycleReasonConstants
import com.example.pauza_screen_time.app_restriction.usecase.SessionEnforcementUseCase

internal class RestrictionAlarmOrchestrator(
    context: Context,
) {
    companion object {
        private const val TAG = "RestrictionAlarmOrchestrator"
    }

    private val appContext = context.applicationContext
    private val scheduler = RestrictionAlarmScheduler(appContext)
    private val restrictionManager = RestrictionManager.getInstance(appContext)
    private val modesStore = RestrictionScheduledModesStore(appContext)
    private val scheduleCalculator = RestrictionScheduleCalculator()
    private val sessionController = RestrictionSessionController(appContext)

    fun onAlarmFired(alarmType: RestrictionAlarmType) {
        when (alarmType) {
            RestrictionAlarmType.PAUSE_END -> onPauseEndFired()
            RestrictionAlarmType.MANUAL_SESSION_END -> onManualSessionEndFired()
            RestrictionAlarmType.DELAYED_END_SESSION -> onDelayedEndSessionFired()
            RestrictionAlarmType.SCHEDULE_SESSION_START,
            RestrictionAlarmType.SCHEDULE_SESSION_END,
            -> onScheduleBoundaryFired(alarmType)
        }
    }

    fun onPauseEndFired() {
        val nowMs = System.currentTimeMillis()
        val pausedUntilMs = restrictionManager.getPausedUntilEpochMs(nowMs, clearExpired = false)
        if (pausedUntilMs > 0L) {
            if (pausedUntilMs > nowMs) {
                schedulePauseEnd(pausedUntilMs, nowMs)
                return
            }
            val previousSnapshot = sessionController.captureLifecycleSnapshot()
            restrictionManager.clearPause()
            sessionController.applyCurrentEnforcementState(
                trigger = LifecycleReasonConstants.TIMER,
                previousLifecycleSnapshot = previousSnapshot,
            )
            rescheduleScheduleBoundary()
            return
        }

        sessionController.applyCurrentEnforcementState(trigger = LifecycleReasonConstants.TIMER)
        rescheduleScheduleBoundary()
    }

    fun onScheduleBoundaryFired(alarmType: RestrictionAlarmType) {
        Log.d(TAG, "Schedule boundary fired: ${alarmType.value}")
        when (alarmType) {
            RestrictionAlarmType.SCHEDULE_SESSION_START -> applyScheduleStart()
            RestrictionAlarmType.SCHEDULE_SESSION_END -> applyScheduleEnd()
            RestrictionAlarmType.MANUAL_SESSION_END -> Unit
            RestrictionAlarmType.PAUSE_END -> Unit
            RestrictionAlarmType.DELAYED_END_SESSION -> Unit
        }
        rescheduleScheduleBoundary()
    }

    fun rescheduleAll() {
        val nowMs = System.currentTimeMillis()
        val pausedUntilMs = restrictionManager.getPausedUntilEpochMs(nowMs)
        if (pausedUntilMs > 0L) {
            schedulePauseEnd(pausedUntilMs, nowMs)
        } else {
            scheduler.cancel(RestrictionAlarmType.PAUSE_END)
        }
        val manualSessionEndMs = restrictionManager.getManualSessionEndEpochMs(nowMs)
        if (manualSessionEndMs > 0L) {
            scheduleManualSessionEnd(manualSessionEndMs, nowMs)
        } else {
            scheduler.cancel(RestrictionAlarmType.MANUAL_SESSION_END)
        }
        val delayedEndSessionMs = restrictionManager.getPendingEndSessionEpochMs(nowMs)
        if (delayedEndSessionMs > 0L) {
            scheduleDelayedEndSession(delayedEndSessionMs, nowMs)
        } else {
            scheduler.cancel(RestrictionAlarmType.DELAYED_END_SESSION)
        }

        rescheduleScheduleBoundary()
    }

    fun onManualSessionEndFired() {
        val nowMs = System.currentTimeMillis()
        val manualSessionEndMs = restrictionManager.getManualSessionEndEpochMs(nowMs, clearExpired = false)
        if (manualSessionEndMs > nowMs) {
            scheduleManualSessionEnd(manualSessionEndMs, nowMs)
            return
        }

        val activeSession = restrictionManager.getActiveSession()
        restrictionManager.clearManualSessionEndEpochMs()
        if (activeSession?.source == RestrictionModeSource.MANUAL) {
            sessionController.endSession(
                source = RestrictionModeSource.MANUAL,
                trigger = LifecycleReasonConstants.TIMER,
                rescheduleAlarms = false,
            )
        } else {
            sessionController.applyCurrentEnforcementState(trigger = LifecycleReasonConstants.TIMER)
        }
        rescheduleScheduleBoundary()
    }

    fun onDelayedEndSessionFired() {
        val nowMs = System.currentTimeMillis()
        val pendingEndMs = restrictionManager.getPendingEndSessionEpochMs(nowMs, clearExpired = false)
        if (pendingEndMs > nowMs) {
            scheduleDelayedEndSession(pendingEndMs, nowMs)
            return
        }
        restrictionManager.clearPendingEndSessionEpochMs()
        val activeSession = restrictionManager.getActiveSession()
        if (activeSession != null) {
            try {
                SessionEnforcementUseCase(appContext).endSessionNow()
            } catch (_: IllegalStateException) {
                sessionController.applyCurrentEnforcementState(trigger = LifecycleReasonConstants.MANUAL)
            }
        } else {
            sessionController.applyCurrentEnforcementState(trigger = LifecycleReasonConstants.MANUAL)
        }
        rescheduleScheduleBoundary()
    }

    private fun schedulePauseEnd(pausedUntilMs: Long, nowMs: Long) {
        val remainingMs = (pausedUntilMs - nowMs).coerceAtLeast(0L)
        val triggerElapsedMs = SystemClock.elapsedRealtime() + remainingMs
        scheduler.schedule(
            type = RestrictionAlarmType.PAUSE_END,
            timebase = RestrictionAlarmTimebase.ElapsedRealtime(triggerElapsedMs),
        )
    }

    private fun scheduleManualSessionEnd(manualSessionEndMs: Long, nowMs: Long) {
        val remainingMs = (manualSessionEndMs - nowMs).coerceAtLeast(0L)
        val triggerElapsedMs = SystemClock.elapsedRealtime() + remainingMs
        scheduler.schedule(
            type = RestrictionAlarmType.MANUAL_SESSION_END,
            timebase = RestrictionAlarmTimebase.ElapsedRealtime(triggerElapsedMs),
        )
    }

    private fun scheduleDelayedEndSession(delayedEndSessionMs: Long, nowMs: Long) {
        val remainingMs = (delayedEndSessionMs - nowMs).coerceAtLeast(0L)
        val triggerElapsedMs = SystemClock.elapsedRealtime() + remainingMs
        scheduler.schedule(
            type = RestrictionAlarmType.DELAYED_END_SESSION,
            timebase = RestrictionAlarmTimebase.ElapsedRealtime(triggerElapsedMs),
        )
    }

    private fun rescheduleScheduleBoundary() {
        scheduler.cancel(RestrictionAlarmType.SCHEDULE_SESSION_START)
        scheduler.cancel(RestrictionAlarmType.SCHEDULE_SESSION_END)

        val modesConfig = modesStore.getConfig()
        val config = RestrictionScheduleConfig(
            enabled = modesConfig.enabled,
            schedules = modesConfig
                .modes
                .filter { it.schedule != null }
                .mapNotNull { it.schedule },
        )
        val boundary = scheduleCalculator.nextBoundary(config) ?: return
        val alarmType = when (boundary.type) {
            RestrictionScheduleBoundaryType.START -> RestrictionAlarmType.SCHEDULE_SESSION_START
            RestrictionScheduleBoundaryType.END -> RestrictionAlarmType.SCHEDULE_SESSION_END
        }

        scheduler.schedule(
            type = alarmType,
            timebase = RestrictionAlarmTimebase.Rtc(boundary.at.toInstant().toEpochMilli()),
        )
    }

    private fun applyScheduleStart() {
        val modesConfig = modesStore.getConfig()
        val resolution = com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModeResolver.resolveNow(
            config = modesConfig,
            scheduleCalculator = scheduleCalculator,
        )
        if (!resolution.isInScheduleNow || resolution.activeModeId == null || resolution.blockedAppIds.isEmpty()) {
            sessionController.applyCurrentEnforcementState(trigger = LifecycleReasonConstants.SCHEDULE)
            return
        }

        sessionController.startSession(
            modeId = resolution.activeModeId,
            blockedAppIds = resolution.blockedAppIds,
            source = RestrictionModeSource.SCHEDULE,
            trigger = LifecycleReasonConstants.SCHEDULE,
            rescheduleAlarms = false,
        )
    }

    private fun applyScheduleEnd() {
        sessionController.endSession(
            source = RestrictionModeSource.SCHEDULE,
            trigger = LifecycleReasonConstants.SCHEDULE,
            rescheduleAlarms = false,
        )
    }
}
