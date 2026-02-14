package com.example.pauza_screen_time.app_restriction.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

internal class RestrictionAlarmScheduler(
    private val context: Context,
) {
    companion object {
        private const val TAG = "RestrictionAlarmScheduler"
    }

    private val appContext = context.applicationContext
    private val alarmManager: AlarmManager =
        appContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    fun schedule(type: RestrictionAlarmType, timebase: RestrictionAlarmTimebase) {
        val pendingIntent = createPendingIntent(type, PendingIntent.FLAG_UPDATE_CURRENT)
            ?: run {
                Log.e(TAG, "Failed to create pending intent for ${type.value} alarm")
                return
            }
        val triggerAtMs = when (timebase) {
            is RestrictionAlarmTimebase.ElapsedRealtime -> timebase.triggerAtElapsedMs
            is RestrictionAlarmTimebase.Rtc -> timebase.triggerAtEpochMs
        }

        if (triggerAtMs <= 0L) {
            Log.w(TAG, "Skipping ${type.value} alarm with invalid trigger: $triggerAtMs")
            return
        }

        val alarmType = when (timebase) {
            is RestrictionAlarmTimebase.ElapsedRealtime -> AlarmManager.ELAPSED_REALTIME_WAKEUP
            is RestrictionAlarmTimebase.Rtc -> AlarmManager.RTC_WAKEUP
        }

        try {
            scheduleExactOrFallback(alarmType, triggerAtMs, pendingIntent)
            Log.d(TAG, "Scheduled ${type.value} alarm at $triggerAtMs (alarmType=$alarmType)")
        } catch (error: Exception) {
            Log.e(TAG, "Failed to schedule ${type.value} alarm", error)
        }
    }

    fun cancel(type: RestrictionAlarmType) {
        val pendingIntent = createPendingIntent(type, PendingIntent.FLAG_NO_CREATE)
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
            Log.d(TAG, "Cancelled ${type.value} alarm")
        }
    }

    private fun scheduleExactOrFallback(
        alarmType: Int,
        triggerAtMs: Long,
        pendingIntent: PendingIntent,
    ) {
        val canUseExact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarmManager.canScheduleExactAlarms()
        } else {
            true
        }

        if (canUseExact) {
            try {
                alarmManager.setExactAndAllowWhileIdle(alarmType, triggerAtMs, pendingIntent)
                return
            } catch (securityError: SecurityException) {
                Log.w(TAG, "Exact alarm denied, falling back to inexact scheduling", securityError)
            }
        }

        alarmManager.setAndAllowWhileIdle(alarmType, triggerAtMs, pendingIntent)
    }

    private fun createPendingIntent(type: RestrictionAlarmType, flags: Int): PendingIntent? {
        val intent = Intent(appContext, RestrictionAlarmReceiver::class.java).apply {
            action = RestrictionAlarmConstants.ALARM_ACTION
            setPackage(appContext.packageName)
            putExtra(RestrictionAlarmConstants.EXTRA_ALARM_TYPE, type.value)
        }
        val intentFlags = flags or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(appContext, type.requestCode, intent, intentFlags)
    }
}
