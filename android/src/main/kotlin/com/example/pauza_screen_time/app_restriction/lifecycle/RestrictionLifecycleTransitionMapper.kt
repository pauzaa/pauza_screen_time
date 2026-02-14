package com.example.pauza_screen_time.app_restriction.lifecycle

import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource

internal data class RestrictionLifecycleSnapshot(
    val isActive: Boolean,
    val isPaused: Boolean,
    val modeId: String?,
    val source: RestrictionModeSource,
    val sessionId: String?,
) {
    companion object {
        fun inactive(isPaused: Boolean): RestrictionLifecycleSnapshot {
            return RestrictionLifecycleSnapshot(
                isActive = false,
                isPaused = isPaused,
                modeId = null,
                source = RestrictionModeSource.NONE,
                sessionId = null,
            )
        }
    }
}

internal object RestrictionLifecycleTransitionMapper {
    fun map(
        previous: RestrictionLifecycleSnapshot,
        next: RestrictionLifecycleSnapshot,
        reason: String,
        occurredAtEpochMs: Long,
    ): List<RestrictionLifecycleEventDraft> {
        if (!previous.isActive && !next.isActive) {
            return emptyList()
        }

        if (previous.isActive && !next.isActive) {
            return endFrom(previous, reason, occurredAtEpochMs)
        }

        if (!previous.isActive && next.isActive) {
            return startFrom(next, reason, occurredAtEpochMs)
        }

        val modeOrSourceChanged =
            previous.modeId != next.modeId || previous.source != next.source || previous.sessionId != next.sessionId
        if (modeOrSourceChanged) {
            return endFrom(previous, reason, occurredAtEpochMs) + startFrom(next, reason, occurredAtEpochMs)
        }

        if (!previous.isPaused && next.isPaused) {
            return actionFrom(next, RestrictionLifecycleAction.PAUSE, reason, occurredAtEpochMs)
        }
        if (previous.isPaused && !next.isPaused) {
            return actionFrom(next, RestrictionLifecycleAction.RESUME, reason, occurredAtEpochMs)
        }

        return emptyList()
    }

    private fun startFrom(
        snapshot: RestrictionLifecycleSnapshot,
        reason: String,
        occurredAtEpochMs: Long,
    ): List<RestrictionLifecycleEventDraft> {
        return actionFrom(snapshot, RestrictionLifecycleAction.START, reason, occurredAtEpochMs)
    }

    private fun endFrom(
        snapshot: RestrictionLifecycleSnapshot,
        reason: String,
        occurredAtEpochMs: Long,
    ): List<RestrictionLifecycleEventDraft> {
        return actionFrom(snapshot, RestrictionLifecycleAction.END, reason, occurredAtEpochMs)
    }

    private fun actionFrom(
        snapshot: RestrictionLifecycleSnapshot,
        action: RestrictionLifecycleAction,
        reason: String,
        occurredAtEpochMs: Long,
    ): List<RestrictionLifecycleEventDraft> {
        val source = snapshot.source.toLifecycleSourceOrNull() ?: return emptyList()
        val sessionId = snapshot.sessionId?.trim().orEmpty()
        val modeId = snapshot.modeId?.trim().orEmpty()
        val normalizedReason = reason.trim()
        if (sessionId.isEmpty() || modeId.isEmpty() || normalizedReason.isEmpty()) {
            return emptyList()
        }
        return listOf(
            RestrictionLifecycleEventDraft(
                sessionId = sessionId,
                modeId = modeId,
                action = action,
                source = source,
                reason = normalizedReason,
                occurredAtEpochMs = occurredAtEpochMs,
            ),
        )
    }
}
