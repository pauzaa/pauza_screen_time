package com.example.pauza_screen_time.app_restriction.lifecycle

import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import org.json.JSONObject

internal enum class RestrictionLifecycleAction(val wireValue: String) {
    START("START"),
    PAUSE("PAUSE"),
    RESUME("RESUME"),
    END("END");

    companion object {
        fun fromWireValue(raw: String?): RestrictionLifecycleAction? {
            if (raw == null) {
                return null
            }
            return entries.firstOrNull { it.wireValue == raw }
        }
    }
}

internal enum class RestrictionLifecycleSource(val wireValue: String) {
    MANUAL("manual"),
    SCHEDULE("schedule");

    companion object {
        fun fromWireValue(raw: String?): RestrictionLifecycleSource? {
            if (raw == null) {
                return null
            }
            return entries.firstOrNull { it.wireValue == raw }
        }
    }
}

internal data class RestrictionLifecycleEventDraft(
    val sessionId: String,
    val modeId: String,
    val action: RestrictionLifecycleAction,
    val source: RestrictionLifecycleSource,
    val reason: String,
    val occurredAtEpochMs: Long,
)

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

    fun toStorageJson(): JSONObject {
        return JSONObject()
            .put("id", id)
            .put("sessionId", sessionId)
            .put("modeId", modeId)
            .put("action", action.wireValue)
            .put("source", source.wireValue)
            .put("reason", reason)
            .put("occurredAtEpochMs", occurredAtEpochMs)
    }

    companion object {
        fun fromStorageJson(raw: JSONObject): RestrictionLifecycleEvent? {
            val id = raw.optString("id", "").trim()
            val sessionId = raw.optString("sessionId", "").trim()
            val modeId = raw.optString("modeId", "").trim()
            val action = RestrictionLifecycleAction.fromWireValue(raw.optString("action", null))
            val source = RestrictionLifecycleSource.fromWireValue(raw.optString("source", null))
            val reason = raw.optString("reason", "").trim()
            val occurredAtEpochMs = raw.optLong("occurredAtEpochMs", -1L)

            if (id.isEmpty() || sessionId.isEmpty() || modeId.isEmpty() || action == null || source == null) {
                return null
            }
            if (reason.isEmpty() || occurredAtEpochMs <= 0L) {
                return null
            }
            return RestrictionLifecycleEvent(
                id = id,
                sessionId = sessionId,
                modeId = modeId,
                action = action,
                source = source,
                reason = reason,
                occurredAtEpochMs = occurredAtEpochMs,
            )
        }
    }
}

internal fun RestrictionModeSource.toLifecycleSourceOrNull(): RestrictionLifecycleSource? {
    return when (this) {
        RestrictionModeSource.MANUAL -> RestrictionLifecycleSource.MANUAL
        RestrictionModeSource.SCHEDULE -> RestrictionLifecycleSource.SCHEDULE
        RestrictionModeSource.NONE -> null
    }
}
