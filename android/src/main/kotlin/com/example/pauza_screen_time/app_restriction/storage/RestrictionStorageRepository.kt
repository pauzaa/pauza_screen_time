package com.example.pauza_screen_time.app_restriction.storage

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.example.pauza_screen_time.app_restriction.model.ActiveSession
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class RestrictionStorageRepository private constructor(context: Context) {

    companion object {
        private const val TAG = "RestrictionStorageRepository"
        private const val PREFS_NAME = "app_restriction_prefs"
        private const val KEY_BLOCKED_APPS = "blocked_apps"
        private const val KEY_PAUSED_UNTIL_EPOCH_MS = "paused_until_epoch_ms"
        private const val KEY_MANUAL_SESSION_END_EPOCH_MS = "manual_session_end_epoch_ms"
        private const val KEY_ACTIVE_SESSION = "active_session"
        private const val KEY_SESSION_ID_SEQ = "session_id_seq"
        private const val KEY_SUPPRESSED_SCHEDULE_MODE_ID = "suppressed_schedule_mode_id"
        private const val KEY_SUPPRESSED_SCHEDULE_UNTIL_EPOCH_MS = "suppressed_schedule_until_epoch_ms"

        @Volatile
        private var instance: RestrictionStorageRepository? = null

        fun getInstance(context: Context): RestrictionStorageRepository {
            return instance ?: synchronized(this) {
                instance ?: RestrictionStorageRepository(context.applicationContext).also {
                    instance = it
                }
            }
        }
    }

    private val preferences: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val blockedApps: MutableSet<String> = mutableSetOf()
    private val json = Json { ignoreUnknownKeys = true }

    init {
        loadBlockedApps()
    }

    @Synchronized
    fun setRestrictedApps(packageIds: List<String>) {
        blockedApps.clear()
        blockedApps.addAll(packageIds.filter { it.isNotBlank() })
        persistBlockedApps()
        Log.d(TAG, "Set restricted apps: $blockedApps")
    }

    @Synchronized
    fun getRestrictedApps(): List<String> = blockedApps.toList()

    @Synchronized
    fun isRestricted(packageId: String): Boolean = blockedApps.contains(packageId)

    @Synchronized
    fun getPausedUntilEpochMs(
        nowMs: Long = System.currentTimeMillis(),
        clearExpired: Boolean = true,
    ): Long {
        val pausedUntil = preferences.getLong(KEY_PAUSED_UNTIL_EPOCH_MS, 0L)
        if (pausedUntil <= nowMs) {
            if (clearExpired && pausedUntil != 0L) {
                preferences.edit().putLong(KEY_PAUSED_UNTIL_EPOCH_MS, 0L).apply()
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
        preferences.edit().putLong(KEY_PAUSED_UNTIL_EPOCH_MS, pausedUntil).apply()
        Log.d(TAG, "Restriction enforcement paused until: $pausedUntil")
    }

    @Synchronized
    fun clearPause() {
        preferences.edit().putLong(KEY_PAUSED_UNTIL_EPOCH_MS, 0L).apply()
        Log.d(TAG, "Restriction pause cleared")
    }

    @Synchronized
    fun getManualSessionEndEpochMs(
        nowMs: Long = System.currentTimeMillis(),
        clearExpired: Boolean = true,
    ): Long {
        val sessionEnd = preferences.getLong(KEY_MANUAL_SESSION_END_EPOCH_MS, 0L)
        if (sessionEnd <= nowMs) {
            if (clearExpired && sessionEnd != 0L) {
                preferences.edit().putLong(KEY_MANUAL_SESSION_END_EPOCH_MS, 0L).apply()
            }
            return 0L
        }
        return sessionEnd
    }

    @Synchronized
    fun setManualSessionEndEpochMs(manualSessionEndEpochMs: Long) {
        preferences.edit().putLong(KEY_MANUAL_SESSION_END_EPOCH_MS, manualSessionEndEpochMs).apply()
    }

    @Synchronized
    fun clearManualSessionEndEpochMs() {
        preferences.edit().putLong(KEY_MANUAL_SESSION_END_EPOCH_MS, 0L).apply()
    }

    @Synchronized
    fun getActiveSession(): ActiveSession? {
        val serialized = preferences.getString(KEY_ACTIVE_SESSION, null)?.trim().orEmpty()
        if (serialized.isEmpty()) return null

        return try {
            val session = json.decodeFromString<ActiveSession>(serialized)
            if (session.modeId.isBlank() || session.blockedAppIds.isEmpty()) {
                clearActiveSession()
                null
            } else {
                session
            }
        } catch (e: Exception) {
            try {
                // Fallback for old JSON format
                val obj = json.parseToJsonElement(serialized).jsonObject
                val modeId = obj["modeId"]?.jsonPrimitive?.content ?: ""
                val blocked = obj["blockedAppIds"]?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList()
                val rawSource = obj["source"]?.jsonPrimitive?.content.orEmpty()
                val source = try {
                    RestrictionModeSource.fromWireValue(rawSource)
                } catch (e: IllegalArgumentException) {
                    Log.w(TAG, "Unknown RestrictionModeSource wire value '$rawSource' in legacy format; defaulting to MANUAL", e)
                    RestrictionModeSource.MANUAL
                }
                val sessionId = obj["sessionId"]?.jsonPrimitive?.content ?: nextSessionId()
                
                val session = ActiveSession(
                    sessionId = sessionId,
                    modeId = modeId,
                    blockedAppIds = blocked.distinct(),
                    source = source
                )
                if (session.modeId.isNotBlank() && session.blockedAppIds.isNotEmpty()) {
                    persistActiveSession(session)
                    session
                } else {
                    clearActiveSession()
                    null
                }
            } catch (fallbackEx: Exception) {
                Log.w(TAG, "Failed to parse active session payload", e)
                clearActiveSession()
                null
            }
        }
    }

    @Synchronized
    fun setActiveSession(
        modeId: String,
        blockedAppIds: List<String>,
        source: RestrictionModeSource,
        sessionId: String? = null,
    ): ActiveSession? {
        val normalizedModeId = modeId.trim()
        val normalizedBlockedIds = blockedAppIds.map(String::trim).filter { it.isNotEmpty() }.distinct()
        if (normalizedModeId.isEmpty() || normalizedBlockedIds.isEmpty()) {
            clearActiveSession()
            return null
        }

        val persisted = getActiveSession()
        val resolvedSessionId = sessionId?.trim()?.takeUnless { it.isEmpty() }
            ?: if (persisted != null && persisted.modeId == normalizedModeId && persisted.source == source) {
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
        if (source != RestrictionModeSource.MANUAL) {
            clearManualSessionEndEpochMs()
        }
        persistActiveSession(nextSession)
        Log.d(TAG, "Active session set to: $normalizedModeId [${source.wireValue}] sessionId=${nextSession.sessionId}")
        return nextSession
    }

    @Synchronized
    fun clearActiveSession() {
        preferences.edit()
            .remove(KEY_ACTIVE_SESSION)
            .apply()
        Log.d(TAG, "Active session cleared")
    }

    @Synchronized
    fun setScheduleSuppression(modeId: String, untilEpochMs: Long) {
        val normalizedModeId = modeId.trim()
        if (normalizedModeId.isEmpty() || untilEpochMs <= 0L) {
            clearScheduleSuppression()
            return
        }
        preferences.edit()
            .putString(KEY_SUPPRESSED_SCHEDULE_MODE_ID, normalizedModeId)
            .putLong(KEY_SUPPRESSED_SCHEDULE_UNTIL_EPOCH_MS, untilEpochMs)
            .apply()
    }

    @Synchronized
    fun getScheduleSuppression(
        nowMs: Long = System.currentTimeMillis(),
        clearExpired: Boolean = true,
    ): ScheduleSuppression? {
        val modeId = preferences.getString(KEY_SUPPRESSED_SCHEDULE_MODE_ID, null)?.trim().orEmpty()
        val untilEpochMs = preferences.getLong(KEY_SUPPRESSED_SCHEDULE_UNTIL_EPOCH_MS, 0L)
        if (modeId.isEmpty() || untilEpochMs <= 0L || untilEpochMs <= nowMs) {
            if (clearExpired && (modeId.isNotEmpty() || untilEpochMs > 0L)) {
                clearScheduleSuppression()
            }
            return null
        }
        return ScheduleSuppression(modeId = modeId, untilEpochMs = untilEpochMs)
    }

    @Synchronized
    fun clearScheduleSuppression() {
        preferences.edit()
            .remove(KEY_SUPPRESSED_SCHEDULE_MODE_ID)
            .remove(KEY_SUPPRESSED_SCHEDULE_UNTIL_EPOCH_MS)
            .apply()
    }

    private fun loadBlockedApps() {
        val storedApps = preferences.getString(KEY_BLOCKED_APPS, null)
        if (storedApps.isNullOrEmpty()) return

        try {
            val trimmed = storedApps.trim()
            if (trimmed.startsWith("{")) {
                val obj = json.parseToJsonElement(trimmed).jsonObject
                val apps = obj["blockedApps"]?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList()
                blockedApps.addAll(apps.filter { it.isNotBlank() })
            } else {
                val apps = json.decodeFromString<List<String>>(trimmed)
                blockedApps.addAll(apps.filter { it.isNotBlank() })
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse blocked apps JSON payload", e)
        }
    }

    private fun persistBlockedApps() {
        val serialized = json.encodeToString(blockedApps.toList())
        preferences.edit().putString(KEY_BLOCKED_APPS, serialized).apply()
        Log.d(TAG, "Persisted ${blockedApps.size} blocked apps to storage")
    }

    private fun persistActiveSession(session: ActiveSession) {
        val serialized = json.encodeToString(session)
        preferences.edit().putString(KEY_ACTIVE_SESSION, serialized).apply()
    }

    private fun nextSessionId(nowMs: Long = System.currentTimeMillis()): String {
        val nextSeq = preferences.getLong(KEY_SESSION_ID_SEQ, 0L) + 1L
        preferences.edit().putLong(KEY_SESSION_ID_SEQ, nextSeq).apply()
        return "s-${formatCounter(nextSeq, 12)}-${formatEpochMs(nowMs)}"
    }

    private fun formatCounter(value: Long, width: Int): String {
        return value.coerceAtLeast(0L).toString().padStart(width, '0')
    }

    private fun formatEpochMs(value: Long): String {
        return value.coerceAtLeast(0L).toString().padStart(13, '0')
    }

    data class ScheduleSuppression(
        val modeId: String,
        val untilEpochMs: Long,
    )
}
