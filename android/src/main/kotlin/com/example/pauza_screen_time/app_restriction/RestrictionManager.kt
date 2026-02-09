package com.example.pauza_screen_time.app_restriction

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

class RestrictionManager private constructor(context: Context) {

    companion object {
        private const val TAG = "RestrictionManager"
        private const val PREFS_NAME = "app_restriction_prefs"
        private const val KEY_BLOCKED_APPS = "blocked_apps"
        private const val KEY_BLOCKED_APPS_LIST = "blockedApps"
        private const val KEY_PAUSED_UNTIL_EPOCH_MS = "paused_until_epoch_ms"
        private const val KEY_MANUAL_ACTIVE_MODE = "manual_active_mode"
        private const val KEY_MANUAL_ACTIVE_MODE_MODE_ID = "modeId"
        private const val KEY_MANUAL_ACTIVE_MODE_BLOCKED_APPS = "blockedAppIds"

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

    data class ManualActiveMode(
        val modeId: String,
        val blockedAppIds: List<String>,
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
    fun getPausedUntilEpochMs(nowMs: Long = System.currentTimeMillis()): Long {
        val pausedUntil = preferences.getLong(KEY_PAUSED_UNTIL_EPOCH_MS, 0L)
        if (pausedUntil <= nowMs) {
            if (pausedUntil != 0L) {
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
    fun getManualActiveMode(): ManualActiveMode? {
        val serialized = preferences.getString(KEY_MANUAL_ACTIVE_MODE, null)?.trim().orEmpty()
        if (serialized.isEmpty()) {
            return null
        }
        return try {
            val payload = JSONObject(serialized)
            val modeId = payload.optString(KEY_MANUAL_ACTIVE_MODE_MODE_ID, "").trim()
            if (modeId.isEmpty()) {
                clearManualActiveMode()
                return null
            }
            val blocked = payload.optJSONArray(KEY_MANUAL_ACTIVE_MODE_BLOCKED_APPS)
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
                clearManualActiveMode()
                return null
            }
            ManualActiveMode(
                modeId = modeId,
                blockedAppIds = blockedAppIds.distinct(),
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse manual active mode payload", e)
            clearManualActiveMode()
            null
        }
    }

    @Synchronized
    fun setManualActiveMode(modeId: String, blockedAppIds: List<String>) {
        val normalizedModeId = modeId.trim()
        val normalizedBlockedIds = blockedAppIds.map(String::trim).filter { it.isNotEmpty() }.distinct()
        if (normalizedModeId.isEmpty() || normalizedBlockedIds.isEmpty()) {
            clearManualActiveMode()
            return
        }
        val blockedPayload = JSONArray()
        normalizedBlockedIds.forEach(blockedPayload::put)
        val payload = JSONObject()
            .put(KEY_MANUAL_ACTIVE_MODE_MODE_ID, normalizedModeId)
            .put(KEY_MANUAL_ACTIVE_MODE_BLOCKED_APPS, blockedPayload)
        preferences.edit()
            .putString(KEY_MANUAL_ACTIVE_MODE, payload.toString())
            .apply()
        Log.d(TAG, "Manual active mode set to: $normalizedModeId")
    }

    @Synchronized
    fun clearManualActiveMode() {
        preferences.edit()
            .remove(KEY_MANUAL_ACTIVE_MODE)
            .apply()
        Log.d(TAG, "Manual active mode cleared")
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
}
