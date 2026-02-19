package com.example.pauza_screen_time.app_restriction

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleEvent
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleEventDraft
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleTransitionMapper
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleSnapshot
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import org.json.JSONArray
import org.json.JSONObject

class RestrictionManager private constructor(context: Context) {

    companion object {
        private const val TAG = "RestrictionManager"
        private const val PREFS_NAME = "app_restriction_prefs"
        private const val KEY_BLOCKED_APPS = "blocked_apps"
        private const val KEY_BLOCKED_APPS_LIST = "blockedApps"
        private const val KEY_PAUSED_UNTIL_EPOCH_MS = "paused_until_epoch_ms"
        private const val KEY_ACTIVE_SESSION = "active_session"
        private const val KEY_ACTIVE_SESSION_MODE_ID = "modeId"
        private const val KEY_ACTIVE_SESSION_BLOCKED_APPS = "blockedAppIds"
        private const val KEY_ACTIVE_SESSION_SOURCE = "source"
        private const val KEY_ACTIVE_SESSION_ID = "sessionId"
        private const val KEY_LIFECYCLE_EVENTS = "lifecycle_events"
        private const val KEY_ACTIVE_SESSION_LIFECYCLE_EVENTS = "active_session_lifecycle_events"
        private const val KEY_LIFECYCLE_EVENT_SEQ = "lifecycle_event_seq"
        private const val KEY_SESSION_ID_SEQ = "session_id_seq"
        private const val MAX_LIFECYCLE_EVENTS = 10_000

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

    private val preferences: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val blockedApps: MutableSet<String> = mutableSetOf()

    init {
        loadBlockedApps()
    }

    data class ActiveSession(
        val sessionId: String,
        val modeId: String,
        val blockedAppIds: List<String>,
        val source: RestrictionModeSource,
    )

    @Synchronized
    fun setRestrictedApps(packageIds: List<String>) {
        blockedApps.clear()
        blockedApps.addAll(packageIds.filter { it.isNotBlank() })
        persistBlockedApps()
        Log.d(TAG, "Set restricted apps: $blockedApps")
    }

    @Synchronized
    fun getRestrictedApps(): List<String> {
        return blockedApps.toList()
    }

    @Synchronized
    fun isRestricted(packageId: String): Boolean {
        return blockedApps.contains(packageId)
    }

    @Synchronized
    fun getPausedUntilEpochMs(
        nowMs: Long = System.currentTimeMillis(),
        clearExpired: Boolean = true,
    ): Long {
        val pausedUntil = preferences.getLong(KEY_PAUSED_UNTIL_EPOCH_MS, 0L)
        if (pausedUntil <= nowMs) {
            if (clearExpired && pausedUntil != 0L) {
                preferences.edit()
                    .putLong(KEY_PAUSED_UNTIL_EPOCH_MS, 0L)
                    .apply()
            }
            return 0L
        }
        return pausedUntil
    }

    @Synchronized
    fun isPausedNow(nowMs: Long = System.currentTimeMillis()): Boolean {
        return getPausedUntilEpochMs(nowMs) > nowMs
    }

    @Synchronized
    fun hasPauseMarker(): Boolean {
        return preferences.getLong(KEY_PAUSED_UNTIL_EPOCH_MS, 0L) > 0L
    }

    @Synchronized
    fun pauseFor(durationMs: Long, nowMs: Long = System.currentTimeMillis()) {
        val pausedUntil = nowMs + durationMs
        preferences.edit()
            .putLong(KEY_PAUSED_UNTIL_EPOCH_MS, pausedUntil)
            .apply()
        Log.d(TAG, "Restriction enforcement paused until: $pausedUntil")
    }

    @Synchronized
    fun clearPause() {
        preferences.edit()
            .putLong(KEY_PAUSED_UNTIL_EPOCH_MS, 0L)
            .apply()
        Log.d(TAG, "Restriction pause cleared")
    }

    @Synchronized
    fun getActiveSession(): ActiveSession? {
        val serialized = preferences.getString(KEY_ACTIVE_SESSION, null)?.trim().orEmpty()
        if (serialized.isEmpty()) {
            return null
        }
        return try {
            val payload = JSONObject(serialized)
            val modeId = payload.optString(KEY_ACTIVE_SESSION_MODE_ID, "").trim()
            if (modeId.isEmpty()) {
                clearActiveSession()
                return null
            }
            val blocked = payload.optJSONArray(KEY_ACTIVE_SESSION_BLOCKED_APPS)
            val blockedAppIds = mutableListOf<String>()
            if (blocked != null) {
                for (index in 0 until blocked.length()) {
                    val appId = blocked.optString(index, "").trim()
                    if (appId.isNotEmpty()) {
                        blockedAppIds += appId
                    }
                }
            }
            if (blockedAppIds.isEmpty()) {
                clearActiveSession()
                return null
            }
            val sourceRaw = payload.optString(KEY_ACTIVE_SESSION_SOURCE, RestrictionModeSource.MANUAL.wireValue)
            val source = RestrictionModeSource.entries.firstOrNull { it.wireValue == sourceRaw }
                ?: RestrictionModeSource.MANUAL
            val sessionIdRaw = payload.optString(KEY_ACTIVE_SESSION_ID, "").trim()
            val sessionId = if (sessionIdRaw.isNotEmpty()) {
                sessionIdRaw
            } else {
                nextSessionId()
            }
            val activeSession = ActiveSession(
                sessionId = sessionId,
                modeId = modeId,
                blockedAppIds = blockedAppIds.distinct(),
                source = source,
            )
            if (sessionIdRaw.isEmpty()) {
                persistActiveSession(activeSession)
            }
            activeSession
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse active session payload", e)
            clearActiveSession()
            null
        }
    }

    @Synchronized
    fun setActiveSession(
        modeId: String,
        blockedAppIds: List<String>,
        source: RestrictionModeSource,
        sessionId: String? = null,
    ) {
        val normalizedModeId = modeId.trim()
        val normalizedBlockedIds = blockedAppIds.map(String::trim).filter { it.isNotEmpty() }.distinct()
        if (normalizedModeId.isEmpty() || normalizedBlockedIds.isEmpty()) {
            clearActiveSession()
            return
        }

        val persisted = getActiveSession()
        val previousSessionId = persisted?.sessionId
        val resolvedSessionId = sessionId?.trim().takeUnless { it.isNullOrEmpty() }
            ?: if (
                persisted != null &&
                persisted.modeId == normalizedModeId &&
                persisted.source == source
            ) {
                persisted.sessionId
            } else {
                nextSessionId()
            }
        val nextSession = ActiveSession(
            sessionId = resolvedSessionId,
            modeId = normalizedModeId,
            blockedAppIds = normalizedBlockedIds,
            source = source,
        )
        if (previousSessionId != nextSession.sessionId) {
            clearActiveSessionLifecycleEvents()
        }
        persistActiveSession(nextSession)
        Log.d(
            TAG,
            "Active session set to: $normalizedModeId [${source.wireValue}] sessionId=${nextSession.sessionId}",
        )
    }

    @Synchronized
    fun clearActiveSession() {
        preferences.edit()
            .remove(KEY_ACTIVE_SESSION)
            .remove(KEY_ACTIVE_SESSION_LIFECYCLE_EVENTS)
            .apply()
        Log.d(TAG, "Active session cleared")
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
        val drafts = RestrictionLifecycleTransitionMapper.map(
            previous = previous,
            next = next,
            reason = reason,
            occurredAtEpochMs = occurredAtEpochMs,
        )
        return appendLifecycleEvents(drafts)
    }

    @Synchronized
    internal fun appendLifecycleEvents(events: List<RestrictionLifecycleEventDraft>): Boolean {
        if (events.isEmpty()) {
            return true
        }

        return try {
            val persisted = loadLifecycleEvents().toMutableList()
            val activeSessionPersisted = loadActiveSessionLifecycleEvents().toMutableList()
            val activeSessionId = getActiveSession()?.sessionId?.trim().orEmpty()
            var nextSeq = preferences.getLong(KEY_LIFECYCLE_EVENT_SEQ, 0L)
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
            if (persisted.size > MAX_LIFECYCLE_EVENTS) {
                val overflow = persisted.size - MAX_LIFECYCLE_EVENTS
                repeat(overflow) { persisted.removeAt(0) }
            }
            if (activeSessionPersisted.size > MAX_LIFECYCLE_EVENTS) {
                val overflow = activeSessionPersisted.size - MAX_LIFECYCLE_EVENTS
                repeat(overflow) { activeSessionPersisted.removeAt(0) }
            }
            persistLifecycleEvents(persisted, nextSeq)
            persistActiveSessionLifecycleEvents(activeSessionPersisted)
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to append lifecycle events", e)
            false
        }
    }

    @Synchronized
    internal fun getPendingLifecycleEvents(limit: Int): List<RestrictionLifecycleEvent> {
        val normalizedLimit = limit.coerceIn(1, MAX_LIFECYCLE_EVENTS)
        return loadLifecycleEvents().take(normalizedLimit)
    }

    @Synchronized
    internal fun loadActiveSessionLifecycleEvents(): List<RestrictionLifecycleEvent> {
        val serialized = preferences.getString(KEY_ACTIVE_SESSION_LIFECYCLE_EVENTS, null)?.trim().orEmpty()
        if (serialized.isEmpty()) {
            return emptyList()
        }
        return try {
            val payload = JSONArray(serialized)
            val events = mutableListOf<RestrictionLifecycleEvent>()
            for (index in 0 until payload.length()) {
                val raw = payload.optJSONObject(index) ?: continue
                val parsed = RestrictionLifecycleEvent.fromStorageJson(raw) ?: continue
                events += parsed
            }
            events.sortedBy { it.id }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse active-session lifecycle payload", e)
            emptyList()
        }
    }

    @Synchronized
    fun ackLifecycleEventsThrough(throughEventId: String): Boolean {
        val normalizedId = throughEventId.trim()
        if (normalizedId.isEmpty()) {
            return false
        }

        return try {
            val events = loadLifecycleEvents()
            val next = events.filter { it.id > normalizedId }
            if (events.size != next.size) {
                persistLifecycleEvents(next, preferences.getLong(KEY_LIFECYCLE_EVENT_SEQ, 0L))
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to ack lifecycle events through id=$normalizedId", e)
            false
        }
    }

    private fun loadBlockedApps() {
        val storedApps = preferences.getString(KEY_BLOCKED_APPS, null)
        if (storedApps.isNullOrEmpty()) {
            Log.d(TAG, "No blocked apps found in storage")
            return
        }

        val trimmed = storedApps.trim()
        if (trimmed.startsWith("{") && loadFromJsonPayload(trimmed)) {
            Log.d(TAG, "Loaded ${blockedApps.size} blocked apps from JSON storage")
        } else {
            Log.w(TAG, "Blocked apps payload is not valid JSON; ignoring")
        }
    }

    private fun persistBlockedApps() {
        val payload = JSONObject()
            .put(KEY_BLOCKED_APPS_LIST, JSONArray(blockedApps.toList()))
        val serialized = payload.toString()
        preferences.edit()
            .putString(KEY_BLOCKED_APPS, serialized)
            .apply()
        Log.d(TAG, "Persisted ${blockedApps.size} blocked apps to storage")
    }

    private fun loadFromJsonPayload(serialized: String): Boolean {
        return try {
            val payload = JSONObject(serialized)
            val apps = payload.optJSONArray(KEY_BLOCKED_APPS_LIST) ?: JSONArray()
            for (index in 0 until apps.length()) {
                val packageId = apps.optString(index)
                if (packageId.isNotBlank()) {
                    blockedApps.add(packageId)
                }
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse blocked apps JSON payload", e)
            false
        }
    }

    private fun persistActiveSession(session: ActiveSession) {
        val blockedPayload = JSONArray()
        session.blockedAppIds.forEach(blockedPayload::put)
        val payload = JSONObject()
            .put(KEY_ACTIVE_SESSION_ID, session.sessionId)
            .put(KEY_ACTIVE_SESSION_MODE_ID, session.modeId)
            .put(KEY_ACTIVE_SESSION_BLOCKED_APPS, blockedPayload)
            .put(KEY_ACTIVE_SESSION_SOURCE, session.source.wireValue)
        preferences.edit()
            .putString(KEY_ACTIVE_SESSION, payload.toString())
            .apply()
    }

    private fun nextSessionId(nowMs: Long = System.currentTimeMillis()): String {
        val nextSeq = preferences.getLong(KEY_SESSION_ID_SEQ, 0L) + 1L
        preferences.edit()
            .putLong(KEY_SESSION_ID_SEQ, nextSeq)
            .apply()
        return "s-${formatCounter(nextSeq, 12)}-${formatEpochMs(nowMs)}"
    }

    private fun loadLifecycleEvents(): List<RestrictionLifecycleEvent> {
        val serialized = preferences.getString(KEY_LIFECYCLE_EVENTS, null)?.trim().orEmpty()
        if (serialized.isEmpty()) {
            return emptyList()
        }
        return try {
            val payload = JSONArray(serialized)
            val events = mutableListOf<RestrictionLifecycleEvent>()
            for (index in 0 until payload.length()) {
                val raw = payload.optJSONObject(index) ?: continue
                val parsed = RestrictionLifecycleEvent.fromStorageJson(raw) ?: continue
                events += parsed
            }
            events.sortedBy { it.id }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse lifecycle queue payload", e)
            emptyList()
        }
    }

    private fun persistLifecycleEvents(events: List<RestrictionLifecycleEvent>, seq: Long) {
        val payload = JSONArray()
        events.forEach { payload.put(it.toStorageJson()) }
        preferences.edit()
            .putString(KEY_LIFECYCLE_EVENTS, payload.toString())
            .putLong(KEY_LIFECYCLE_EVENT_SEQ, seq.coerceAtLeast(0L))
            .apply()
    }

    private fun persistActiveSessionLifecycleEvents(events: List<RestrictionLifecycleEvent>) {
        val payload = JSONArray()
        events.forEach { payload.put(it.toStorageJson()) }
        preferences.edit()
            .putString(KEY_ACTIVE_SESSION_LIFECYCLE_EVENTS, payload.toString())
            .apply()
    }

    private fun clearActiveSessionLifecycleEvents() {
        preferences.edit()
            .remove(KEY_ACTIVE_SESSION_LIFECYCLE_EVENTS)
            .apply()
    }

    private fun normalizeLifecycleDraft(
        draft: RestrictionLifecycleEventDraft,
    ): RestrictionLifecycleEventDraft? {
        val sessionId = draft.sessionId.trim()
        val modeId = draft.modeId.trim()
        val reason = draft.reason.trim()
        if (sessionId.isEmpty() || modeId.isEmpty() || reason.isEmpty()) {
            return null
        }
        if (draft.occurredAtEpochMs <= 0L) {
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
