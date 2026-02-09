package com.example.pauza_screen_time.app_restriction.schedule

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

internal class RestrictionScheduleStore(context: Context) {
    companion object {
        private const val PREFS_NAME = "app_restriction_schedule_prefs"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_SCHEDULES = "schedules"

        private const val LEGACY_KEY_DAYS_OF_WEEK = "days_of_week"
        private const val LEGACY_KEY_START_MINUTES = "start_minutes"
        private const val LEGACY_KEY_END_MINUTES = "end_minutes"

        private const val MINUTES_PER_DAY = 24 * 60
    }

    private val preferences: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getConfig(): RestrictionScheduleConfig {
        val enabled = preferences.getBoolean(KEY_ENABLED, false)
        val schedules = loadSchedules()

        return RestrictionScheduleConfig(
            enabled = enabled,
            schedules = schedules,
        )
    }

    fun setConfig(config: RestrictionScheduleConfig) {
        preferences.edit()
            .putBoolean(KEY_ENABLED, config.enabled)
            .putString(KEY_SCHEDULES, serializeSchedules(config.schedules))
            .apply()
    }

    private fun loadSchedules(): List<RestrictionScheduleEntry> {
        val serialized = preferences.getString(KEY_SCHEDULES, null)
        if (!serialized.isNullOrBlank()) {
            return parseSchedules(serialized)
        }
        return loadLegacySchedule()
    }

    private fun serializeSchedules(schedules: List<RestrictionScheduleEntry>): String {
        val payload = JSONArray()
        schedules.forEach { schedule ->
            val days = JSONArray()
            schedule.daysOfWeekIso.sorted().forEach(days::put)
            payload.put(
                JSONObject()
                    .put("daysOfWeekIso", days)
                    .put("startMinutes", schedule.startMinutes)
                    .put("endMinutes", schedule.endMinutes),
            )
        }
        return payload.toString()
    }

    private fun parseSchedules(serialized: String): List<RestrictionScheduleEntry> {
        return try {
            val values = JSONArray(serialized)
            val parsed = mutableListOf<RestrictionScheduleEntry>()
            for (index in 0 until values.length()) {
                val raw = values.optJSONObject(index) ?: continue
                val days = mutableSetOf<Int>()
                val rawDays = raw.optJSONArray("daysOfWeekIso")
                if (rawDays != null) {
                    for (dayIndex in 0 until rawDays.length()) {
                        val day = rawDays.optInt(dayIndex, -1)
                        if (day in 1..7) {
                            days += day
                        }
                    }
                }
                val startMinutes = raw.optInt("startMinutes", -1)
                val endMinutes = raw.optInt("endMinutes", -1)
                if (
                    days.isEmpty() ||
                    startMinutes !in 0 until MINUTES_PER_DAY ||
                    endMinutes !in 0 until MINUTES_PER_DAY ||
                    startMinutes == endMinutes
                ) {
                    continue
                }
                parsed += RestrictionScheduleEntry(
                    daysOfWeekIso = days,
                    startMinutes = startMinutes,
                    endMinutes = endMinutes,
                )
            }
            parsed
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun loadLegacySchedule(): List<RestrictionScheduleEntry> {
        val days = preferences.getStringSet(LEGACY_KEY_DAYS_OF_WEEK, emptySet())
            ?.mapNotNull { it.toIntOrNull() }
            ?.filter { it in 1..7 }
            ?.toSet()
            ?: emptySet()
        val startMinutes = preferences.getInt(LEGACY_KEY_START_MINUTES, 0)
            .coerceIn(0, MINUTES_PER_DAY - 1)
        val endMinutes = preferences.getInt(LEGACY_KEY_END_MINUTES, 0)
            .coerceIn(0, MINUTES_PER_DAY - 1)
        if (days.isEmpty() || startMinutes == endMinutes) {
            return emptyList()
        }
        return listOf(
            RestrictionScheduleEntry(
                daysOfWeekIso = days,
                startMinutes = startMinutes,
                endMinutes = endMinutes,
            ),
        )
    }
}
