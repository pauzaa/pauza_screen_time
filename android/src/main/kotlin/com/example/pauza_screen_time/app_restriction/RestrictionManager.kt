package com.example.pauza_screen_time.app_restriction

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Manages the blocklist of restricted applications using SharedPreferences.
 *
 * This singleton class persists the list of blocked package IDs across app restarts
 * and device reboots. The blocklist is stored in SharedPreferences so that the
 * AccessibilityService (AppMonitoringService) can access it even when the Flutter
 * app is not running.
 *
 * Features:
 * - Persistent storage of blocked package IDs
 * - Thread-safe operations using synchronized blocks
 * - Singleton pattern for consistent state across the app
 */
class RestrictionManager private constructor(context: Context) {

    companion object {
        private const val TAG = "RestrictionManager"
        private const val PREFS_NAME = "app_restriction_prefs"
        private const val KEY_BLOCKED_APPS = "blocked_apps"
        private const val KEY_BLOCKED_APPS_LIST = "blockedApps"
        private const val KEY_PAUSED_UNTIL_EPOCH_MS = "paused_until_epoch_ms"
        private const val KEY_MANUAL_ENFORCEMENT_ENABLED = "manual_enforcement_enabled"

        @Volatile
        private var instance: RestrictionManager? = null

        /**
         * Gets the singleton instance of RestrictionManager.
         *
         * @param context The application context
         * @return The singleton RestrictionManager instance
         */
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

    /**
     * In-memory cache of blocked apps for fast lookups.
     * Synchronized with SharedPreferences on every modification.
     */
    private val blockedApps: MutableSet<String> = mutableSetOf()

    init {
        // Load blocked apps from SharedPreferences on initialization
        loadBlockedApps()
    }

    /**
     * Sets the complete list of restricted apps, replacing any existing entries.
     *
     * @param packageIds List of package IDs to restrict
     */
    @Synchronized
    fun setRestrictedApps(packageIds: List<String>) {
        blockedApps.clear()
        blockedApps.addAll(packageIds.filter { it.isNotBlank() })
        persistBlockedApps()
        Log.d(TAG, "Set restricted apps: $blockedApps")
    }

    /**
     * Adds a single app to the restriction blocklist.
     *
     * @param packageId The package ID to add
     * @return true if the app was added, false if it was already blocked
     */
    @Synchronized
    fun addRestrictedApp(packageId: String): Boolean {
        if (packageId.isBlank()) {
            Log.w(TAG, "Attempted to add blank package ID")
            return false
        }
        
        val added = blockedApps.add(packageId)
        if (added) {
            persistBlockedApps()
            Log.d(TAG, "Added restricted app: $packageId")
        } else {
            Log.d(TAG, "App already restricted: $packageId")
        }
        return added
    }

    /**
     * Removes a single app from the restriction blocklist.
     *
     * @param packageId The package ID to remove
     * @return true if the app was removed, false if it wasn't in the blocklist
     */
    @Synchronized
    fun removeRestriction(packageId: String): Boolean {
        val removed = blockedApps.remove(packageId)
        if (removed) {
            persistBlockedApps()
            Log.d(TAG, "Removed restriction for: $packageId")
        } else {
            Log.d(TAG, "App was not restricted: $packageId")
        }
        return removed
    }

    /**
     * Removes all apps from the restriction blocklist.
     */
    @Synchronized
    fun removeAllRestrictions() {
        blockedApps.clear()
        persistBlockedApps()
        Log.d(TAG, "Removed all restrictions")
    }

    /**
     * Gets the current list of restricted package IDs.
     *
     * @return List of currently restricted package IDs
     */
    @Synchronized
    fun getRestrictedApps(): List<String> {
        return blockedApps.toList()
    }

    /**
     * Checks if a specific app is currently restricted.
     *
     * @param packageId The package ID to check
     * @return true if the app is restricted, false otherwise
     */
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
    fun isManualEnforcementEnabled(): Boolean {
        return preferences.getBoolean(KEY_MANUAL_ENFORCEMENT_ENABLED, true)
    }

    @Synchronized
    fun setManualEnforcementEnabled(enabled: Boolean) {
        preferences.edit()
            .putBoolean(KEY_MANUAL_ENFORCEMENT_ENABLED, enabled)
            .apply()
        Log.d(TAG, "Manual restriction enforcement set to: $enabled")
    }

    /**
     * Loads the blocked apps from SharedPreferences into the in-memory cache.
     */
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

    /**
     * Persists the current blocklist to SharedPreferences.
     */
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
