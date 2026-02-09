package com.example.pauza_screen_time.app_restriction.schedule

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

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
        return RestrictionScheduledModesConfig(
            enabled = preferences.getBoolean(KEY_SCHEDULED_MODES_ENABLED, false),
            modes = loadModes(),
        )
    }

    fun setEnabled(enabled: Boolean) {
        preferences.edit()
            .putBoolean(KEY_SCHEDULED_MODES_ENABLED, enabled)
            .apply()
    }

    fun upsertMode(mode: RestrictionScheduledModeEntry) {
        val next = loadModes().toMutableList()
        val existingIndex = next.indexOfFirst { it.modeId == mode.modeId }
        if (existingIndex >= 0) {
            next[existingIndex] = mode
        } else {
            next += mode
        }
        storeModes(next)
    }

    fun removeMode(modeId: String) {
        val filtered = loadModes().filterNot { it.modeId == modeId }
        storeModes(filtered)
    }

    fun getMode(modeId: String): RestrictionScheduledModeEntry? {
        return loadModes().firstOrNull { it.modeId == modeId }
    }

    private fun storeModes(modes: List<RestrictionScheduledModeEntry>) {
        preferences.edit()
            .putString(KEY_SCHEDULED_MODES, serializeModes(modes))
            .apply()
    }

    private fun loadModes(): List<RestrictionScheduledModeEntry> {
        val serialized = preferences.getString(KEY_SCHEDULED_MODES, null)
        if (serialized.isNullOrBlank()) {
            return emptyList()
        }
        return parseModes(serialized)
    }

    private fun serializeModes(modes: List<RestrictionScheduledModeEntry>): String {
        val payload = JSONArray()
        modes.forEach { mode ->
            val blockedAppIds = JSONArray()
            mode.blockedAppIds.forEach(blockedAppIds::put)
            val modePayload = JSONObject()
                .put("modeId", mode.modeId)
                .put("isEnabled", mode.isEnabled)
                .put("blockedAppIds", blockedAppIds)
            if (mode.schedule != null) {
                val days = JSONArray()
                mode.schedule.daysOfWeekIso.sorted().forEach(days::put)
                modePayload.put(
                    "schedule",
                    JSONObject()
                        .put("daysOfWeekIso", days)
                        .put("startMinutes", mode.schedule.startMinutes)
                        .put("endMinutes", mode.schedule.endMinutes),
                )
            }
            payload.put(modePayload)
        }
        return payload.toString()
    }

    private fun parseModes(serialized: String): List<RestrictionScheduledModeEntry> {
        return try {
            val raw = JSONArray(serialized)
            val parsed = mutableListOf<RestrictionScheduledModeEntry>()
            for (index in 0 until raw.length()) {
                val mode = raw.optJSONObject(index) ?: continue
                val modeId = mode.optString("modeId", "").trim()
                if (modeId.isEmpty()) {
                    continue
                }
                val isEnabled = mode.optBoolean("isEnabled", true)
                val scheduleRaw = mode.optJSONObject("schedule")
                val schedule = if (scheduleRaw == null) {
                    null
                } else {
                    val days = mutableSetOf<Int>()
                    val rawDays = scheduleRaw.optJSONArray("daysOfWeekIso")
                    if (rawDays != null) {
                        for (dayIndex in 0 until rawDays.length()) {
                            val day = rawDays.optInt(dayIndex, -1)
                            if (day in 1..7) {
                                days += day
                            }
                        }
                    }
                    val startMinutes = scheduleRaw.optInt("startMinutes", -1)
                    val endMinutes = scheduleRaw.optInt("endMinutes", -1)
                    if (
                        days.isEmpty() ||
                        startMinutes !in 0 until 24 * 60 ||
                        endMinutes !in 0 until 24 * 60 ||
                        startMinutes == endMinutes
                    ) {
                        null
                    } else {
                        RestrictionScheduleEntry(
                            daysOfWeekIso = days,
                            startMinutes = startMinutes,
                            endMinutes = endMinutes,
                        )
                    }
                }
                val blockedAppIds = mutableListOf<String>()
                val rawBlocked = mode.optJSONArray("blockedAppIds")
                if (rawBlocked != null) {
                    for (appIndex in 0 until rawBlocked.length()) {
                        val appId = rawBlocked.optString(appIndex, "").trim()
                        if (appId.isNotEmpty()) {
                            blockedAppIds += appId
                        }
                    }
                }
                parsed += RestrictionScheduledModeEntry(
                    modeId = modeId,
                    isEnabled = isEnabled,
                    schedule = schedule,
                    blockedAppIds = blockedAppIds.distinct(),
                )
            }
            parsed
        } catch (_: Exception) {
            emptyList()
        }
    }
}
