package com.example.pauza_screen_time.app_restriction.lifecycle

import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import kotlin.test.Test
import kotlin.test.assertEquals

internal class RestrictionLifecycleTransitionMapperTest {
    @Test
    fun manualFlow_mapsStartPauseResumeEndInOrder() {
        val started = RestrictionLifecycleTransitionMapper.map(
            previous = RestrictionLifecycleSnapshot.inactive(isPaused = false),
            next = RestrictionLifecycleSnapshot(
                isActive = true,
                isPaused = false,
                modeId = "focus",
                source = RestrictionModeSource.MANUAL,
                sessionId = "s1",
            ),
            reason = "manual_start",
            occurredAtEpochMs = 1L,
        )
        assertEquals(listOf(RestrictionLifecycleAction.START), started.map { it.action })

        val paused = RestrictionLifecycleTransitionMapper.map(
            previous = RestrictionLifecycleSnapshot(
                isActive = true,
                isPaused = false,
                modeId = "focus",
                source = RestrictionModeSource.MANUAL,
                sessionId = "s1",
            ),
            next = RestrictionLifecycleSnapshot(
                isActive = true,
                isPaused = true,
                modeId = "focus",
                source = RestrictionModeSource.MANUAL,
                sessionId = "s1",
            ),
            reason = "manual_pause",
            occurredAtEpochMs = 2L,
        )
        assertEquals(listOf(RestrictionLifecycleAction.PAUSE), paused.map { it.action })

        val resumed = RestrictionLifecycleTransitionMapper.map(
            previous = RestrictionLifecycleSnapshot(
                isActive = true,
                isPaused = true,
                modeId = "focus",
                source = RestrictionModeSource.MANUAL,
                sessionId = "s1",
            ),
            next = RestrictionLifecycleSnapshot(
                isActive = true,
                isPaused = false,
                modeId = "focus",
                source = RestrictionModeSource.MANUAL,
                sessionId = "s1",
            ),
            reason = "manual_resume",
            occurredAtEpochMs = 3L,
        )
        assertEquals(listOf(RestrictionLifecycleAction.RESUME), resumed.map { it.action })

        val ended = RestrictionLifecycleTransitionMapper.map(
            previous = RestrictionLifecycleSnapshot(
                isActive = true,
                isPaused = false,
                modeId = "focus",
                source = RestrictionModeSource.MANUAL,
                sessionId = "s1",
            ),
            next = RestrictionLifecycleSnapshot.inactive(isPaused = false),
            reason = "manual_end",
            occurredAtEpochMs = 4L,
        )
        assertEquals(listOf(RestrictionLifecycleAction.END), ended.map { it.action })
    }

    @Test
    fun activeModeChange_emitsEndThenStart() {
        val mapped = RestrictionLifecycleTransitionMapper.map(
            previous = RestrictionLifecycleSnapshot(
                isActive = true,
                isPaused = false,
                modeId = "focus",
                source = RestrictionModeSource.MANUAL,
                sessionId = "s1",
            ),
            next = RestrictionLifecycleSnapshot(
                isActive = true,
                isPaused = false,
                modeId = "work",
                source = RestrictionModeSource.SCHEDULE,
                sessionId = "s2",
            ),
            reason = "source_switch",
            occurredAtEpochMs = 10L,
        )
        assertEquals(
            listOf(RestrictionLifecycleAction.END, RestrictionLifecycleAction.START),
            mapped.map { it.action },
        )
        assertEquals("s1", mapped.first().sessionId)
        assertEquals("s2", mapped.last().sessionId)
    }

    @Test
    fun pausedToInactive_emitsOnlyEnd() {
        val mapped = RestrictionLifecycleTransitionMapper.map(
            previous = RestrictionLifecycleSnapshot(
                isActive = true,
                isPaused = true,
                modeId = "focus",
                source = RestrictionModeSource.SCHEDULE,
                sessionId = "s1",
            ),
            next = RestrictionLifecycleSnapshot.inactive(isPaused = false),
            reason = "schedule_end_during_pause",
            occurredAtEpochMs = 20L,
        )
        assertEquals(listOf(RestrictionLifecycleAction.END), mapped.map { it.action })
    }
}
