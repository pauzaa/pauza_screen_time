package com.example.pauza_screen_time.app_restriction

import android.content.Context
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleEvent
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleEventDraft
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleLogger
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleSnapshot
import com.example.pauza_screen_time.app_restriction.model.ActiveSession
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import com.example.pauza_screen_time.app_restriction.storage.RestrictionStorageRepository

/**
 * A lightweight facade that coordinates between RestrictionStorageRepository and RestrictionLifecycleLogger.
 */
class RestrictionManager private constructor(context: Context) {

    private val storage = RestrictionStorageRepository.getInstance(context)
    private val logger = RestrictionLifecycleLogger.getInstance(context)

    companion object {
        @Volatile
        private var instance: RestrictionManager? = null

        fun getInstance(context: Context): RestrictionManager {
            return instance ?: synchronized(this) {
                instance ?: RestrictionManager(context.applicationContext).also {
                    instance = it
                }
            }
        }
    }

    @Synchronized
    fun setRestrictedApps(packageIds: List<String>) = storage.setRestrictedApps(packageIds)

    @Synchronized
    fun getRestrictedApps(): List<String> = storage.getRestrictedApps()

    @Synchronized
    fun isRestricted(packageId: String): Boolean = storage.isRestricted(packageId)

    @Synchronized
    fun getPausedUntilEpochMs(
        nowMs: Long = System.currentTimeMillis(),
        clearExpired: Boolean = true,
    ): Long = storage.getPausedUntilEpochMs(nowMs, clearExpired)

    @Synchronized
    fun isPausedNow(nowMs: Long = System.currentTimeMillis()): Boolean = storage.isPausedNow(nowMs)

    @Synchronized
    fun hasPauseMarker(): Boolean = storage.hasPauseMarker()

    @Synchronized
    fun pauseFor(durationMs: Long, nowMs: Long = System.currentTimeMillis()) = storage.pauseFor(durationMs, nowMs)

    @Synchronized
    fun clearPause() = storage.clearPause()

    @Synchronized
    fun getManualSessionEndEpochMs(
        nowMs: Long = System.currentTimeMillis(),
        clearExpired: Boolean = true,
    ): Long = storage.getManualSessionEndEpochMs(nowMs, clearExpired)

    @Synchronized
    fun setManualSessionEndEpochMs(manualSessionEndEpochMs: Long) =
        storage.setManualSessionEndEpochMs(manualSessionEndEpochMs)

    @Synchronized
    fun clearManualSessionEndEpochMs() = storage.clearManualSessionEndEpochMs()

    @Synchronized
    fun getActiveSession(): ActiveSession? = storage.getActiveSession()

    @Synchronized
    fun setActiveSession(
        modeId: String,
        blockedAppIds: List<String>,
        source: RestrictionModeSource,
        sessionId: String? = null,
    ) {
        val previousSession = getActiveSession()
        val nextSession = storage.setActiveSession(modeId, blockedAppIds, source, sessionId)
        
        if (nextSession != null && previousSession?.sessionId != nextSession.sessionId) {
            logger.clearActiveSessionLifecycleEvents()
        }
    }

    @Synchronized
    fun clearActiveSession() {
        storage.clearActiveSession()
        storage.clearManualSessionEndEpochMs()
    }

    @Synchronized
    internal fun snapshotLifecycleState(): RestrictionLifecycleSnapshot {
        val activeSession = getActiveSession()
        if (activeSession == null) {
            return RestrictionLifecycleSnapshot.inactive(isPaused = hasPauseMarker())
        }
        return RestrictionLifecycleSnapshot(
            isActive = true,
            isPaused = hasPauseMarker(),
            modeId = activeSession.modeId,
            source = activeSession.source,
            sessionId = activeSession.sessionId,
        )
    }

    @Synchronized
    internal fun appendLifecycleTransition(
        previous: RestrictionLifecycleSnapshot,
        next: RestrictionLifecycleSnapshot,
        reason: String,
        occurredAtEpochMs: Long = System.currentTimeMillis(),
    ): Boolean {
        val activeSessionId = getActiveSession()?.sessionId.orEmpty()
        return logger.appendLifecycleTransition(previous, next, reason, activeSessionId, occurredAtEpochMs)
    }

    @Synchronized
    internal fun appendLifecycleEvents(events: List<RestrictionLifecycleEventDraft>): Boolean {
        val activeSessionId = getActiveSession()?.sessionId.orEmpty()
        return logger.appendLifecycleEvents(events, activeSessionId)
    }

    @Synchronized
    internal fun getPendingLifecycleEvents(limit: Int): List<RestrictionLifecycleEvent> =
        logger.getPendingLifecycleEvents(limit)

    @Synchronized
    internal fun loadActiveSessionLifecycleEvents(): List<RestrictionLifecycleEvent> =
        logger.loadActiveSessionLifecycleEvents()

    @Synchronized
    fun ackLifecycleEventsThrough(throughEventId: String): Boolean =
        logger.ackLifecycleEventsThrough(throughEventId)
}
