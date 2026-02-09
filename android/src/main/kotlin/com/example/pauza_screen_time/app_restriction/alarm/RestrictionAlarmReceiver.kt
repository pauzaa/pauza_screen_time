package com.example.pauza_screen_time.app_restriction.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class RestrictionAlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "RestrictionAlarmReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != RestrictionAlarmConstants.ALARM_ACTION) {
            return
        }

        val alarmType = RestrictionAlarmType.fromValue(
            intent.getStringExtra(RestrictionAlarmConstants.EXTRA_ALARM_TYPE),
        )
        if (alarmType == null) {
            Log.w(TAG, "Unknown alarm type, skipping")
            return
        }

        RestrictionAlarmOrchestrator(context).onAlarmFired(alarmType)
    }
}
