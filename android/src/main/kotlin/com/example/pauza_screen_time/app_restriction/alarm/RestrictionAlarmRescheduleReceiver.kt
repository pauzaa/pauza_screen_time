package com.example.pauza_screen_time.app_restriction.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class RestrictionAlarmRescheduleReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "RestrictionAlarmRescheduleReceiver"

        private val supportedActions = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
        )
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action
        if (action !in supportedActions) {
            return
        }

        Log.d(TAG, "Rescheduling restriction alarms for action=$action")
        RestrictionAlarmOrchestrator(context).rescheduleAll()
    }
}
