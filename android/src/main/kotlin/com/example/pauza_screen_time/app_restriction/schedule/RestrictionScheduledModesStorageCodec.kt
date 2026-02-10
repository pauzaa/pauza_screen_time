package com.example.pauza_screen_time.app_restriction.schedule

import org.json.JSONArray
import org.json.JSONObject

internal object RestrictionScheduledModesStorageCodec {
    fun toStorageJson(modes: List<RestrictionScheduledModeEntry>): String {
        val payload = JSONArray()
        modes.forEach { mode ->
            val blockedAppIds = JSONArray()
            mode.blockedAppIds.forEach(blockedAppIds::put)
            val modePayload = JSONObject()
                .put("modeId", mode.modeId)
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

    fun fromStorageJson(serialized: String): List<RestrictionScheduledModeEntry> {
        return try {
            val raw = JSONArray(serialized)
            val parsed = mutableListOf<RestrictionScheduledModeEntry>()
            for (index in 0 until raw.length()) {
                val mode = raw.optJSONObject(index) ?: continue
                val parsedMode = parseMode(mode) ?: continue
                parsed += parsedMode
            }
            parsed
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun parseMode(mode: JSONObject): RestrictionScheduledModeEntry? {
        val modeId = mode.optString("modeId", "").trim()
        if (modeId.isEmpty()) {
            return null
        }
        val blockedAppIds = parseBlockedAppIds(mode)
        val schedule = parseSchedule(mode.optJSONObject("schedule"))
        return RestrictionScheduledModeEntry(
            modeId = modeId,
            schedule = schedule,
            blockedAppIds = blockedAppIds.distinct(),
        )
    }

    private fun parseBlockedAppIds(mode: JSONObject): List<String> {
        val blockedAppIds = mutableListOf<String>()
        val rawBlocked = mode.optJSONArray("blockedAppIds") ?: return blockedAppIds
        for (appIndex in 0 until rawBlocked.length()) {
            val appId = rawBlocked.optString(appIndex, "").trim()
            if (appId.isNotEmpty()) {
                blockedAppIds += appId
            }
        }
        return blockedAppIds
    }

    private fun parseSchedule(scheduleRaw: JSONObject?): RestrictionScheduleEntry? {
        if (scheduleRaw == null) {
            return null
        }
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
            return null
        }
        return RestrictionScheduleEntry(
            daysOfWeekIso = days,
            startMinutes = startMinutes,
            endMinutes = endMinutes,
        )
    }
}
