package com.example.pauza_screen_time.app_restriction.schedule

internal data class RestrictionScheduledModeEntry(
    val modeId: String,
    val schedule: RestrictionScheduleEntry?,
    val blockedAppIds: List<String>,
) {
    companion object {
        /**
         * Parses a [RestrictionScheduledModeEntry] from a raw method-channel map.
         * @throws IllegalArgumentException if required fields are missing or invalid.
         */
        fun fromMap(payload: Map<*, *>): RestrictionScheduledModeEntry {
            val modeId = (payload["modeId"] as? String)?.trim().orEmpty()
            if (modeId.isEmpty()) {
                throw IllegalArgumentException("Mode requires a non-empty 'modeId'")
            }
            val blockedAppIdsRaw = payload["blockedAppIds"] as? List<*>
                ?: throw IllegalArgumentException("Mode requires 'blockedAppIds'")
            val blockedAppIds = blockedAppIdsRaw
                .mapNotNull { (it as? String)?.trim() }
                .filter { it.isNotEmpty() }
                .distinct()

            val scheduleMap = payload["schedule"] as? Map<*, *>
            val schedule: RestrictionScheduleEntry? = if (scheduleMap != null) {
                val rawDays = scheduleMap["daysOfWeekIso"] as? List<*>
                    ?: throw IllegalArgumentException("Schedule requires 'daysOfWeekIso'")
                val startMinutes = (scheduleMap["startMinutes"] as? Number)?.toInt()
                    ?: throw IllegalArgumentException("Schedule requires 'startMinutes'")
                val endMinutes = (scheduleMap["endMinutes"] as? Number)?.toInt()
                    ?: throw IllegalArgumentException("Schedule requires 'endMinutes'")
                val days = rawDays.mapNotNull { (it as? Number)?.toInt() }.toSet()
                RestrictionScheduleEntry(
                    daysOfWeekIso = days,
                    startMinutes = startMinutes,
                    endMinutes = endMinutes,
                )
            } else {
                null
            }

            return RestrictionScheduledModeEntry(
                modeId = modeId,
                schedule = schedule,
                blockedAppIds = blockedAppIds,
            )
        }
    }

    fun toChannelMap(): Map<String, Any?> {
        return mapOf(
            "modeId" to modeId,
            "schedule" to schedule?.toChannelMap(),
            "blockedAppIds" to blockedAppIds,
        )
    }
}
