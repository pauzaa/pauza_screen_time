package com.example.pauza_screen_time.app_restriction.model

/**
 * Typed DTO for a restriction schedule transmitted over the method channel.
 *
 * Replaces the previous [Any?] schedule field in [RestrictionModeDto].
 * Both [fromMap] and [toChannelMap] are owned by this model so parsing logic
 * does not leak into the handler layer.
 */
data class RestrictionScheduleDto(
    val daysOfWeekIso: Set<Int>,
    val startMinutes: Int,
    val endMinutes: Int,
) {
    companion object {
        /**
         * Parses a schedule from a raw method-channel map.
         * @throws IllegalArgumentException if required fields are missing or invalid.
         */
        fun fromMap(map: Map<*, *>): RestrictionScheduleDto {
            val rawDays = map["daysOfWeekIso"] as? List<*>
                ?: throw IllegalArgumentException("Schedule missing 'daysOfWeekIso'")
            val days = rawDays.mapNotNull { (it as? Number)?.toInt() }.toSet()
            if (days.isEmpty()) {
                throw IllegalArgumentException("Schedule 'daysOfWeekIso' must not be empty")
            }
            val startMinutes = (map["startMinutes"] as? Number)?.toInt()
                ?: throw IllegalArgumentException("Schedule missing 'startMinutes'")
            val endMinutes = (map["endMinutes"] as? Number)?.toInt()
                ?: throw IllegalArgumentException("Schedule missing 'endMinutes'")
            return RestrictionScheduleDto(
                daysOfWeekIso = days,
                startMinutes = startMinutes,
                endMinutes = endMinutes,
            )
        }
    }

    fun toChannelMap(): Map<String, Any?> = mapOf(
        "daysOfWeekIso" to daysOfWeekIso.sorted(),
        "startMinutes" to startMinutes,
        "endMinutes" to endMinutes,
    )
}
