package com.example.pauza_screen_time.app_restriction

import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class RestrictionSessionControllerMonitoringPolicyTest {
    @Test
    fun noActiveMode_doesNotEnforceOrMonitor() {
        val state = sessionState(
            activeModeSource = RestrictionModeSource.NONE,
            blockedAppIds = listOf("com.example.app"),
        )

        assertFalse(RestrictionSessionController.shouldEnforceNow(state, isPausedNow = false))
        assertFalse(RestrictionSessionController.shouldMonitorForegroundEvents(state, isPausedNow = false))
    }

    @Test
    fun activeModeWithBlockedAppsAndNotPaused_enforcesAndMonitors() {
        val state = sessionState(
            activeModeSource = RestrictionModeSource.MANUAL,
            blockedAppIds = listOf("com.example.app"),
        )

        assertTrue(RestrictionSessionController.shouldEnforceNow(state, isPausedNow = false))
        assertTrue(RestrictionSessionController.shouldMonitorForegroundEvents(state, isPausedNow = false))
    }

    @Test
    fun activeModePaused_doesNotEnforceOrMonitor() {
        val state = sessionState(
            activeModeSource = RestrictionModeSource.SCHEDULE,
            blockedAppIds = listOf("com.example.app"),
        )

        assertFalse(RestrictionSessionController.shouldEnforceNow(state, isPausedNow = true))
        assertFalse(RestrictionSessionController.shouldMonitorForegroundEvents(state, isPausedNow = true))
    }

    @Test
    fun activeModeWithoutBlockedApps_doesNotEnforceOrMonitor() {
        val state = sessionState(
            activeModeSource = RestrictionModeSource.MANUAL,
            blockedAppIds = emptyList(),
        )

        assertFalse(RestrictionSessionController.shouldEnforceNow(state, isPausedNow = false))
        assertFalse(RestrictionSessionController.shouldMonitorForegroundEvents(state, isPausedNow = false))
    }

    @Test
    fun monitorPolicyMatchesEnforcePolicyAcrossInputs() {
        val states = listOf(
            sessionState(activeModeSource = RestrictionModeSource.NONE, blockedAppIds = emptyList()),
            sessionState(activeModeSource = RestrictionModeSource.NONE, blockedAppIds = listOf("a")),
            sessionState(activeModeSource = RestrictionModeSource.MANUAL, blockedAppIds = emptyList()),
            sessionState(activeModeSource = RestrictionModeSource.MANUAL, blockedAppIds = listOf("a")),
            sessionState(activeModeSource = RestrictionModeSource.SCHEDULE, blockedAppIds = emptyList()),
            sessionState(activeModeSource = RestrictionModeSource.SCHEDULE, blockedAppIds = listOf("a")),
        )

        val pausedStates = listOf(false, true)
        states.forEach { state ->
            pausedStates.forEach { paused ->
                assertEquals(
                    RestrictionSessionController.shouldEnforceNow(state, paused),
                    RestrictionSessionController.shouldMonitorForegroundEvents(state, paused),
                )
            }
        }
    }

    private fun sessionState(
        activeModeSource: RestrictionModeSource,
        blockedAppIds: List<String>,
    ): RestrictionSessionController.SessionState {
        return RestrictionSessionController.SessionState(
            isScheduleEnabled = true,
            isInScheduleNow = activeModeSource == RestrictionModeSource.SCHEDULE,
            blockedAppIds = blockedAppIds,
            activeModeId = if (activeModeSource == RestrictionModeSource.NONE) null else "focus",
            activeModeSource = activeModeSource,
            activeScheduleBoundaryEndEpochMs = null,
        )
    }
}
