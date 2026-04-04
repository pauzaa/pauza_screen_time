package com.example.pauza_screen_time.app_restriction.usecase

import android.content.Context
import com.example.pauza_screen_time.app_restriction.RestrictionManager
import com.example.pauza_screen_time.app_restriction.RestrictionSessionController
import com.example.pauza_screen_time.app_restriction.alarm.RestrictionAlarmOrchestrator
import com.example.pauza_screen_time.app_restriction.lifecycle.LifecycleReasonConstants
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleCalculator
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleConfig
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleEntry
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModeEntry
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModesConfig
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModesStore

internal class ManageModesUseCase(private val context: Context) {

    fun upsertMode(
        modeId: String,
        blockedAppIds: List<String>,
        schedule: RestrictionScheduleEntry?
    ) {
        val scheduleCalculator = RestrictionScheduleCalculator()
        if (schedule != null) {
            if (!scheduleCalculator.isScheduleShapeValid(RestrictionScheduleConfig(enabled = true, schedules = listOf(schedule)))) {
                throw IllegalArgumentException("Mode schedule payload is invalid")
            }
        }

        val store = RestrictionScheduledModesStore(context)
        val mode = RestrictionScheduledModeEntry(
            modeId = modeId,
            schedule = schedule,
            blockedAppIds = blockedAppIds,
        )

        val nextModes = store.getConfig().modes.toMutableList()
        nextModes.removeAll { it.modeId == mode.modeId }
        if (mode.schedule != null && mode.blockedAppIds.isNotEmpty()) {
            nextModes += mode
        }
        val shapeIsValid = scheduleCalculator.isScheduleShapeValid(
            RestrictionScheduleConfig(
                enabled = true,
                schedules = nextModes.mapNotNull { it.schedule },
            ),
        )
        if (!shapeIsValid) {
            throw IllegalArgumentException("Mode schedule overlaps with an existing schedule")
        }

        if (mode.schedule != null && mode.blockedAppIds.isNotEmpty()) {
            store.upsertMode(mode)
        } else {
            store.removeMode(mode.modeId)
        }

        val restrictionManager = RestrictionManager.getInstance(context)
        val activeSession = restrictionManager.getActiveSession()
        if (activeSession?.modeId == mode.modeId) {
            if (mode.blockedAppIds.isNotEmpty()) {
                restrictionManager.setActiveSession(mode.modeId, mode.blockedAppIds, activeSession.source)
            } else {
                restrictionManager.clearActiveSession()
            }
        }

        rescheduleAndApply()
    }

    fun replaceAllModes(modes: List<RestrictionScheduledModeEntry>) {
        val scheduleCalculator = RestrictionScheduleCalculator()
        val enforceable = modes.filter { it.schedule != null && it.blockedAppIds.isNotEmpty() }

        val shapeIsValid = scheduleCalculator.isScheduleShapeValid(
            RestrictionScheduleConfig(
                enabled = true,
                schedules = enforceable.mapNotNull { it.schedule },
            ),
        )
        if (!shapeIsValid) {
            throw IllegalArgumentException("Replacement modes contain overlapping schedules")
        }

        val store = RestrictionScheduledModesStore(context)
        store.replaceAllModes(enforceable)

        val restrictionManager = RestrictionManager.getInstance(context)
        val activeSession = restrictionManager.getActiveSession()
        if (activeSession != null) {
            val matchingMode = enforceable.firstOrNull { it.modeId == activeSession.modeId }
            if (matchingMode != null) {
                restrictionManager.setActiveSession(matchingMode.modeId, matchingMode.blockedAppIds, activeSession.source)
            } else {
                restrictionManager.clearActiveSession()
            }
        }

        rescheduleAndApply()
    }

    fun removeMode(modeId: String) {
        val modesStore = RestrictionScheduledModesStore(context)
        modesStore.removeMode(modeId)
        val restrictionManager = RestrictionManager.getInstance(context)
        if (restrictionManager.getActiveSession()?.modeId == modeId) {
            restrictionManager.clearActiveSession()
        }
        rescheduleAndApply()
    }

    fun setScheduleEnforcementEnabled(enabled: Boolean) {
        val store = RestrictionScheduledModesStore(context)
        if (store.isEnabled() == enabled) return
        store.setEnabled(enabled)
        rescheduleAndApply()
    }

    private fun rescheduleAndApply() {
        RestrictionAlarmOrchestrator(context).rescheduleAll()
        RestrictionSessionController(context).applyCurrentEnforcementState(trigger = LifecycleReasonConstants.MANUAL)
    }

    fun getModesConfig(): RestrictionScheduledModesConfig {
        return RestrictionScheduledModesStore(context).getConfig()
    }
}
