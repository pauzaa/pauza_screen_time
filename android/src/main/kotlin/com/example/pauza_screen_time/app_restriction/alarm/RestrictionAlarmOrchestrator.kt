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
                trigger = "pause_end_alarm",
                previousLifecycleSnapshot = previousSnapshot,
            )
            rescheduleScheduleBoundary()
            return
        }

        sessionController.applyCurrentEnforcementState(trigger = "pause_end_alarm")
        rescheduleScheduleBoundary()
    }

    fun onScheduleBoundaryFired(alarmType: RestrictionAlarmType) {
        Log.d(TAG, "Schedule boundary fired: ${alarmType.value}")
        when (alarmType) {
            RestrictionAlarmType.SCHEDULE_SESSION_START -> applyScheduleStart()
            RestrictionAlarmType.SCHEDULE_SESSION_END -> applyScheduleEnd()
            RestrictionAlarmType.PAUSE_END -> Unit
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
            sessionController.applyCurrentEnforcementState(trigger = "schedule_boundary_start_noop")
            return
        }

        sessionController.startSession(
            modeId = resolution.activeModeId,
            blockedAppIds = resolution.blockedAppIds,
            source = RestrictionModeSource.SCHEDULE,
            trigger = "schedule_boundary_start",
            rescheduleAlarms = false,
        )
    }

    private fun applyScheduleEnd() {
        sessionController.endSession(
            source = RestrictionModeSource.SCHEDULE,
            trigger = "schedule_boundary_end",
            rescheduleAlarms = false,
        )
    }
}
