package com.example.pauza_screen_time.app_restriction.usecase

import android.content.Context
import com.example.pauza_screen_time.app_restriction.RestrictionManager
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleEvent

internal class LifecycleEventsUseCase(private val context: Context) {

    fun getPendingLifecycleEvents(limit: Int): List<RestrictionLifecycleEvent> {
        return RestrictionManager.getInstance(context).getPendingLifecycleEvents(limit)
    }

    fun ackLifecycleEventsThrough(throughEventId: String) {
        val success = RestrictionManager.getInstance(context).ackLifecycleEventsThrough(throughEventId)
        if (!success) {
            throw IllegalStateException("Failed to acknowledge lifecycle events")
        }
    }
}
