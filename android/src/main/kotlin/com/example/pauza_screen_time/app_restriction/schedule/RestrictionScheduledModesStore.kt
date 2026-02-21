package com.example.pauza_screen_time.app_restriction.schedule

import android.content.Context
import android.content.SharedPreferences

internal class RestrictionScheduledModesStore(
    context: Context,
) {
    companion object {
        private const val PREFS_NAME = "app_restriction_schedule_prefs"
        private const val KEY_SCHEDULED_MODES_ENABLED = "modes_enabled"
        private const val KEY_SCHEDULED_MODES = "modes"
    }

    private val preferences: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getConfig(): RestrictionScheduledModesConfig {
        val persistedModes = loadModes()
        val filteredModes = persistedModes.filter(RestrictionScheduledModeEntry::isEnforceableScheduled)
        if (persistedModes.size != filteredModes.size) {
            storeModes(filteredModes)
        }
        return RestrictionScheduledModesConfig(
            enabled = preferences.getBoolean(KEY_SCHEDULED_MODES_ENABLED, false),
            modes = filteredModes,
        )
    }

    fun setEnabled(enabled: Boolean) {
        preferences.edit()
            .putBoolean(KEY_SCHEDULED_MODES_ENABLED, enabled)
            .apply()
    }

    fun upsertMode(mode: RestrictionScheduledModeEntry) {
        if (!mode.isEnforceableScheduled()) {
            removeMode(mode.modeId)
            return
        }

        val next = getConfig().modes.toMutableList()
        val existingIndex = next.indexOfFirst { it.modeId == mode.modeId }
        if (existingIndex >= 0) {
            next[existingIndex] = mode
        } else {
            next += mode
        }
        storeModes(next)
    }

    fun removeMode(modeId: String) {
        val filtered = getConfig().modes.filterNot { it.modeId == modeId }
        storeModes(filtered)
    }

    fun getMode(modeId: String): RestrictionScheduledModeEntry? {
        return getConfig().modes.firstOrNull { it.modeId == modeId }
    }

    private fun storeModes(modes: List<RestrictionScheduledModeEntry>) {
        preferences.edit()
            .putString(
                KEY_SCHEDULED_MODES,
                RestrictionScheduledModesStorageCodec.toStorageJson(
                    modes.filter(RestrictionScheduledModeEntry::isEnforceableScheduled),
                ),
            )
            .apply()
    }

    private fun loadModes(): List<RestrictionScheduledModeEntry> {
        val serialized = preferences.getString(KEY_SCHEDULED_MODES, null)
        if (serialized.isNullOrBlank()) {
            return emptyList()
        }
        return try {
            RestrictionScheduledModesStorageCodec.fromStorageJson(serialized)
        } catch (e: StorageDecodeException) {
            android.util.Log.w("RestrictionScheduledModesStore", "Corrupt scheduled modes storage; resetting", e)
            preferences.edit().remove(KEY_SCHEDULED_MODES).apply()
            emptyList()
        }
    }
}

private fun RestrictionScheduledModeEntry.isEnforceableScheduled(): Boolean {
    return schedule != null && blockedAppIds.isNotEmpty()
}
