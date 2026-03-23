package com.example.pauza_screen_time.app_restriction.lifecycle

import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import org.json.JSONObject

@Serializable
internal enum class RestrictionLifecycleAction(val wireValue: String) {
    @SerialName("START") START("START"),
    @SerialName("PAUSE") PAUSE("PAUSE"),
    @SerialName("RESUME") RESUME("RESUME"),
    @SerialName("END") END("END");

    companion object {
        fun fromWireValue(raw: String?): RestrictionLifecycleAction? {
            if (raw == null) {
                return null
            }
            return entries.firstOrNull { it.wireValue == raw }
        }
    }
}

@Serializable
internal enum class RestrictionLifecycleSource(val wireValue: String) {
    @SerialName("manual") MANUAL("manual"),
    @SerialName("schedule") SCHEDULE("schedule");

    companion object {
        fun fromWireValue(raw: String?): RestrictionLifecycleSource? {
            if (raw == null) {
                return null
            }
            return entries.firstOrNull { it.wireValue == raw }
        }
    }
}

@Serializable
internal data class RestrictionLifecycleEventDraft(
    val sessionId: String,
    val modeId: String,
    val action: RestrictionLifecycleAction,
    val source: RestrictionLifecycleSource,
    val reason: String,
    val occurredAtEpochMs: Long,
)

@Serializable
internal data class RestrictionLifecycleEvent(
    val id: String,
    val sessionId: String,
    val modeId: String,
    val action: RestrictionLifecycleAction,
    val source: RestrictionLifecycleSource,
    val reason: String,
    val occurredAtEpochMs: Long,
) {
    fun toChannelMap(): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "sessionId" to sessionId,
            "modeId" to modeId,
            "action" to action.wireValue,
            "source" to source.wireValue,
            "reason" to reason,
            "occurredAtEpochMs" to occurredAtEpochMs,
        )
    }
}

/// Server-compatible reason values stored in lifecycle events.
internal object LifecycleReasonConstants {
    const val MANUAL = "manual"
    const val NFC = "nfc"
    const val QR = "qr"
    const val TIMER = "timer"
    const val EMERGENCY = "emergency"
    const val SCHEDULE = "schedule"
}

internal fun RestrictionModeSource.toLifecycleSourceOrNull(): RestrictionLifecycleSource? {
    return when (this) {
        RestrictionModeSource.MANUAL -> RestrictionLifecycleSource.MANUAL
        RestrictionModeSource.SCHEDULE -> RestrictionLifecycleSource.SCHEDULE
        RestrictionModeSource.NONE -> null
    }
}
