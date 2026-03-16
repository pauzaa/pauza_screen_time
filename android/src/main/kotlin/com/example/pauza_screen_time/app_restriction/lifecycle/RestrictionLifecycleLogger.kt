package com.example.pauza_screen_time.app_restriction.lifecycle

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.example.pauza_screen_time.app_restriction.schedule.StorageDecodeException
import com.example.pauza_screen_time.app_restriction.storage.RestrictionStorageKeys
import com.example.pauza_screen_time.core.PlatformConstants
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class RestrictionLifecycleLogger private constructor(context: Context) {

    companion object {
        private const val TAG = "RestrictionLifecycleLog"

        @Volatile
        private var instance: RestrictionLifecycleLogger? = null

        fun getInstance(context: Context): RestrictionLifecycleLogger {
            return instance ?: synchronized(this) {
                instance ?: RestrictionLifecycleLogger(context.applicationContext).also {
                    instance = it
                }
            }
        }
    }

    private val preferences: SharedPreferences =
        context.getSharedPreferences(RestrictionStorageKeys.RESTRICTION_PREFS_NAME, Context.MODE_PRIVATE)

    private val json = Json { ignoreUnknownKeys = true }

    @Synchronized
    fun clearActiveSessionLifecycleEvents() {
        preferences.edit()
            .remove(RestrictionStorageKeys.KEY_ACTIVE_SESSION_LIFECYCLE_EVENTS)
            .apply()
    }

    @Synchronized
    internal fun appendLifecycleTransition(
        previous: RestrictionLifecycleSnapshot,
        next: RestrictionLifecycleSnapshot,
        reason: String,
        activeSessionId: String,
        occurredAtEpochMs: Long = System.currentTimeMillis(),
    ): Boolean {
        val drafts = RestrictionLifecycleTransitionMapper.map(
            previous = previous,
            next = next,
            reason = reason,
            occurredAtEpochMs = occurredAtEpochMs,
        )
        return appendLifecycleEvents(drafts, activeSessionId)
    }

    @Synchronized
    internal fun appendLifecycleEvents(events: List<RestrictionLifecycleEventDraft>, activeSessionId: String): Boolean {
        if (events.isEmpty()) return true

        return try {
            val persisted = loadLifecycleEvents().toMutableList()
            val activeSessionPersisted = loadActiveSessionLifecycleEvents().toMutableList()
            var nextSeq = preferences.getLong(RestrictionStorageKeys.KEY_LIFECYCLE_EVENT_SEQ, 0L)

            events.forEach { draft ->
                val normalized = normalizeLifecycleDraft(draft) ?: return@forEach
                nextSeq += 1
                val generated = RestrictionLifecycleEvent(
                    id = nextLifecycleEventId(nextSeq, normalized.occurredAtEpochMs),
                    sessionId = normalized.sessionId,
                    modeId = normalized.modeId,
                    action = normalized.action,
                    source = normalized.source,
                    reason = normalized.reason,
                    occurredAtEpochMs = normalized.occurredAtEpochMs,
                )
                persisted += generated
                if (activeSessionId.isNotEmpty() && generated.sessionId == activeSessionId) {
                    activeSessionPersisted += generated
                }
            }

            // O(N^2) issue fixed by dropping efficiently rather than repeating removeAt(0)
            val trimmedPersisted = if (persisted.size > PlatformConstants.MAX_LIFECYCLE_EVENTS) {
                persisted.drop(persisted.size - PlatformConstants.MAX_LIFECYCLE_EVENTS)
            } else {
                persisted
            }

            val trimmedActiveSessionPersisted = if (activeSessionPersisted.size > PlatformConstants.MAX_LIFECYCLE_EVENTS) {
                activeSessionPersisted.drop(activeSessionPersisted.size - PlatformConstants.MAX_LIFECYCLE_EVENTS)
            } else {
                activeSessionPersisted
            }

            persistLifecycleEvents(trimmedPersisted, nextSeq)
            persistActiveSessionLifecycleEvents(trimmedActiveSessionPersisted)
            true
        } catch (e: StorageDecodeException) {
            Log.w(TAG, "Corrupt lifecycle events storage; resetting before append", e)
            preferences.edit()
                .remove(RestrictionStorageKeys.KEY_LIFECYCLE_EVENTS)
                .remove(RestrictionStorageKeys.KEY_ACTIVE_SESSION_LIFECYCLE_EVENTS)
                .apply()
            false
        }
    }

    @Synchronized
    internal fun getPendingLifecycleEvents(limit: Int): List<RestrictionLifecycleEvent> {
        val normalizedLimit = limit.coerceIn(1, PlatformConstants.MAX_LIFECYCLE_EVENTS)
        return try {
            loadLifecycleEvents().take(normalizedLimit)
        } catch (e: StorageDecodeException) {
            Log.w(TAG, "Corrupt lifecycle events storage; resetting", e)
            preferences.edit().remove(RestrictionStorageKeys.KEY_LIFECYCLE_EVENTS).apply()
            emptyList()
        }
    }

    @Synchronized
    internal fun loadActiveSessionLifecycleEvents(): List<RestrictionLifecycleEvent> {
        val serialized = preferences.getString(RestrictionStorageKeys.KEY_ACTIVE_SESSION_LIFECYCLE_EVENTS, null)?.trim().orEmpty()
        if (serialized.isEmpty()) return emptyList()

        // ignoreUnknownKeys = true handles old JSON fields; a real parse failure is propagated.
        return try {
            json.decodeFromString(serialized)
        } catch (e: Exception) {
            throw StorageDecodeException("Active-session lifecycle events JSON is corrupt", e)
        }
    }

    @Synchronized
    fun ackLifecycleEventsThrough(throughEventId: String): Boolean {
        val normalizedId = throughEventId.trim()
        if (normalizedId.isEmpty()) return false

        return try {
            val events = loadLifecycleEvents()
            val next = events.filter { it.id > normalizedId }
            if (events.size != next.size) {
                persistLifecycleEvents(next, preferences.getLong(RestrictionStorageKeys.KEY_LIFECYCLE_EVENT_SEQ, 0L))
            }
            true
        } catch (e: StorageDecodeException) {
            Log.w(TAG, "Corrupt lifecycle events storage during ack; resetting. id=$normalizedId", e)
            preferences.edit().remove(RestrictionStorageKeys.KEY_LIFECYCLE_EVENTS).apply()
            false
        }
    }

    private fun loadLifecycleEvents(): List<RestrictionLifecycleEvent> {
        val serialized = preferences.getString(RestrictionStorageKeys.KEY_LIFECYCLE_EVENTS, null)?.trim().orEmpty()
        if (serialized.isEmpty()) return emptyList()

        return try {
            json.decodeFromString(serialized)
        } catch (e: Exception) {
            throw StorageDecodeException("Lifecycle events JSON is corrupt", e)
        }
    }

    private fun persistLifecycleEvents(events: List<RestrictionLifecycleEvent>, seq: Long) {
        val serialized = json.encodeToString(events)
        preferences.edit()
            .putString(RestrictionStorageKeys.KEY_LIFECYCLE_EVENTS, serialized)
            .putLong(RestrictionStorageKeys.KEY_LIFECYCLE_EVENT_SEQ, seq.coerceAtLeast(0L))
            .apply()
    }

    private fun persistActiveSessionLifecycleEvents(events: List<RestrictionLifecycleEvent>) {
        val serialized = json.encodeToString(events)
        preferences.edit()
            .putString(RestrictionStorageKeys.KEY_ACTIVE_SESSION_LIFECYCLE_EVENTS, serialized)
            .apply()
    }

    private fun normalizeLifecycleDraft(draft: RestrictionLifecycleEventDraft): RestrictionLifecycleEventDraft? {
        val sessionId = draft.sessionId.trim()
        val modeId = draft.modeId.trim()
        val reason = draft.reason.trim()
        if (sessionId.isEmpty() || modeId.isEmpty() || reason.isEmpty() || draft.occurredAtEpochMs <= 0L) {
            return null
        }
        return draft.copy(sessionId = sessionId, modeId = modeId, reason = reason)
    }

    private fun nextLifecycleEventId(seq: Long, occurredAtEpochMs: Long): String {
        return "${formatCounter(seq, 20)}-${formatEpochMs(occurredAtEpochMs)}"
    }

    private fun formatCounter(value: Long, width: Int): String {
        return value.coerceAtLeast(0L).toString().padStart(width, '0')
    }

    private fun formatEpochMs(value: Long): String {
        return value.coerceAtLeast(0L).toString().padStart(13, '0')
    }
}
