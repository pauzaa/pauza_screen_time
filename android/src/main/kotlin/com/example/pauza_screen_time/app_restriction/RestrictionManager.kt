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
        private const val KEY_LIFECYCLE_QUEUE_VERSION = "lifecycle_queue_version"
        private const val KEY_LIFECYCLE_HEAD_SEQ = "lifecycle_head_seq"
        private const val KEY_LIFECYCLE_TAIL_SEQ = "lifecycle_tail_seq"
        private const val KEY_LIFECYCLE_GC_FLOOR_SEQ = "lifecycle_gc_floor_seq"
        private const val KEY_LIFECYCLE_EVENT_PREFIX = "lifecycle_event."
        private const val KEY_SESSION_ID_SEQ = "session_id_seq"
        private const val LIFECYCLE_QUEUE_VERSION = 2L
        private const val LIFECYCLE_GC_BATCH_SIZE = 128L
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
            var (headSeq, tailSeq) = readHeadTail()
            events.forEach { draft ->
                val normalized = normalizeLifecycleDraft(draft) ?: return@forEach
                val nextSeq = if (isQueueEmpty(headSeq, tailSeq)) headSeq else tailSeq + 1L
                val nextEvent = RestrictionLifecycleEvent(
                    id = nextLifecycleEventId(nextSeq, normalized.occurredAtEpochMs),
                    sessionId = normalized.sessionId,
                    modeId = normalized.modeId,
                    action = normalized.action,
                    source = normalized.source,
                    reason = normalized.reason,
                    occurredAtEpochMs = normalized.occurredAtEpochMs,
                )
                preferences.edit()
                    .putString(eventKey(nextSeq), nextEvent.toStorageJson().toString())
                    .apply()

                if (isQueueEmpty(headSeq, tailSeq)) {
                    headSeq = nextSeq
                }
                tailSeq = nextSeq

                while (!isQueueEmpty(headSeq, tailSeq) && (tailSeq - headSeq + 1L) > MAX_LIFECYCLE_EVENTS) {
                    headSeq += 1L
                }
            }

            persistLifecycleMetadata(headSeq, tailSeq)
            compactUpTo(headSeq - 1L)
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to append lifecycle events", e)
            false
        }
    }

    @Synchronized
    internal fun getPendingLifecycleEvents(limit: Int): List<RestrictionLifecycleEvent> {
        val normalizedLimit = limit.coerceIn(1, MAX_LIFECYCLE_EVENTS)
        val (headSeq, tailSeq) = readHeadTail()
        if (isQueueEmpty(headSeq, tailSeq)) {
            return emptyList()
        }

        val endSeq = minOf(tailSeq, headSeq + normalizedLimit - 1L)
        val pending = mutableListOf<RestrictionLifecycleEvent>()
        var seq = headSeq
        while (seq <= endSeq) {
            val event = loadLifecycleEvent(seq)
            if (event != null) {
                pending += event
            }
            seq += 1L
        }
        return pending
    }

    @Synchronized
    fun ackLifecycleEventsThrough(throughEventId: String): Boolean {
        val normalizedId = throughEventId.trim()
        if (normalizedId.isEmpty()) {
            return false
        }
        val throughSeq = parseSeqFromEventId(normalizedId) ?: return false

        return try {
            val (headSeq, tailSeq) = readHeadTail()
            if (isQueueEmpty(headSeq, tailSeq)) {
                return true
            }

            val nextHead = maxOf(headSeq, minOf(throughSeq + 1L, tailSeq + 1L))
            if (nextHead != headSeq) {
                persistLifecycleMetadata(nextHead, tailSeq)
                compactUpTo(nextHead - 1L)
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

    private fun loadLifecycleEvent(seq: Long): RestrictionLifecycleEvent? {
        val serialized = preferences.getString(eventKey(seq), null)?.trim().orEmpty()
        if (serialized.isEmpty()) {
            return null
        }
        return try {
            RestrictionLifecycleEvent.fromStorageJson(JSONObject(serialized))
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse lifecycle event at seq=$seq", e)
            null
        }
    }

    private fun persistLifecycleMetadata(headSeq: Long, tailSeq: Long) {
        val normalizedHead = maxOf(1L, headSeq)
        val normalizedTail = maxOf(0L, tailSeq)
        preferences.edit()
            .putLong(KEY_LIFECYCLE_QUEUE_VERSION, LIFECYCLE_QUEUE_VERSION)
            .putLong(KEY_LIFECYCLE_HEAD_SEQ, normalizedHead)
            .putLong(KEY_LIFECYCLE_TAIL_SEQ, normalizedTail)
            .apply()
    }

    private fun readHeadTail(): Pair<Long, Long> {
        var head = preferences.getLong(KEY_LIFECYCLE_HEAD_SEQ, 1L)
        var tail = preferences.getLong(KEY_LIFECYCLE_TAIL_SEQ, 0L)
        if (head <= 0L) {
            head = 1L
        }
        if (tail < 0L) {
            tail = 0L
        }
        if (head > tail + 1L) {
            head = tail + 1L
        }
        return head to tail
    }

    private fun isQueueEmpty(head: Long, tail: Long): Boolean {
        return head > tail
    }

    private fun parseSeqFromEventId(id: String): Long? {
        val seqPart = id.substringBefore('-', "").trim()
        if (seqPart.isEmpty()) {
            return null
        }
        return seqPart.toLongOrNull()
    }

    private fun eventKey(seq: Long): String {
        return "$KEY_LIFECYCLE_EVENT_PREFIX${formatCounter(seq, 20)}"
    }

    private fun compactUpTo(seqInclusive: Long) {
        if (seqInclusive < 0L) {
            return
        }

        val gcFloor = preferences.getLong(KEY_LIFECYCLE_GC_FLOOR_SEQ, 0L).coerceAtLeast(0L)
        val startSeq = gcFloor + 1L
        if (startSeq > seqInclusive) {
            return
        }

        val endSeq = minOf(seqInclusive, startSeq + LIFECYCLE_GC_BATCH_SIZE - 1L)
        val editor = preferences.edit()
        var seq = startSeq
        while (seq <= endSeq) {
            editor.remove(eventKey(seq))
            seq += 1L
        }
        editor
            .putLong(KEY_LIFECYCLE_QUEUE_VERSION, LIFECYCLE_QUEUE_VERSION)
            .putLong(KEY_LIFECYCLE_GC_FLOOR_SEQ, endSeq)
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
