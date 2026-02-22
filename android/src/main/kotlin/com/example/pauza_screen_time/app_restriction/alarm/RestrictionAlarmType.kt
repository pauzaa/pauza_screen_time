package com.example.pauza_screen_time.app_restriction.alarm

internal enum class RestrictionAlarmType(
    val requestCode: Int,
    val value: String,
) {
    PAUSE_END(requestCode = 10101, value = "pause_end"),
    SCHEDULE_SESSION_START(requestCode = 10102, value = "schedule_session_start"),
    SCHEDULE_SESSION_END(requestCode = 10103, value = "schedule_session_end"),
    MANUAL_SESSION_END(requestCode = 10104, value = "manual_session_end"),
    DELAYED_END_SESSION(requestCode = 10105, value = "delayed_end_session");

    companion object {
        fun fromValue(value: String?): RestrictionAlarmType? {
            return entries.firstOrNull { it.value == value }
        }
    }
}
