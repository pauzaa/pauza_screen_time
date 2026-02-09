package com.example.pauza_screen_time.app_restriction.alarm

internal sealed class RestrictionAlarmTimebase {
    data class ElapsedRealtime(val triggerAtElapsedMs: Long) : RestrictionAlarmTimebase()

    data class Rtc(val triggerAtEpochMs: Long) : RestrictionAlarmTimebase()
}
