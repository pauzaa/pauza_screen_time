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
        private const val KEY_MANUAL_ACTIVE_MODE_ID = "manual_active_mode_id"

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
    fun getManualActiveModeId(): String? {
        val value = preferences.getString(KEY_MANUAL_ACTIVE_MODE_ID, null)?.trim().orEmpty()
        return value.ifEmpty { null }
    }

    @Synchronized
    fun setManualActiveModeId(modeId: String?) {
        val normalized = modeId?.trim().orEmpty().ifEmpty { null }
        preferences.edit().apply {
            if (normalized == null) {
                remove(KEY_MANUAL_ACTIVE_MODE_ID)
            } else {
                putString(KEY_MANUAL_ACTIVE_MODE_ID, normalized)
            }
        }.apply()
        Log.d(TAG, "Manual active mode id set to: ${normalized ?: "<none>"}")
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
