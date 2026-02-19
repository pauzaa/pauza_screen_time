package com.example.pauza_screen_time.app_restriction.method_channel

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.example.pauza_screen_time.app_restriction.RestrictionManager
import com.example.pauza_screen_time.app_restriction.RestrictionSessionController
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeDto
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import com.example.pauza_screen_time.app_restriction.model.RestrictionSessionDto
import com.example.pauza_screen_time.app_restriction.alarm.RestrictionAlarmOrchestrator
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleCalculator
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleConfig
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleEntry
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModeEntry
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModesStore
import com.example.pauza_screen_time.core.MethodNames
import com.example.pauza_screen_time.core.PluginErrorHelper
import com.example.pauza_screen_time.permissions.PermissionHandler
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class RestrictionsMethodHandler(
    private val contextProvider: () -> Context?,
    private val accessibilityStatusProvider: (Context) -> String = {
        PermissionHandler(it).checkPermission(PermissionHandler.ACCESSIBILITY_KEY)
    },
    private val lifecycleExecutor: ExecutorService = Executors.newSingleThreadExecutor(),
    private val resultPoster: ((() -> Unit) -> Unit)? = null,
) : MethodCallHandler {
    companion object {
        private const val ANDROID_ACCESSIBILITY_KEY = "android.accessibility"
        private const val FEATURE = "restrictions"
        private const val MAX_RELIABLE_PAUSE_DURATION_MS = 24 * 60 * 60 * 1000L
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                MethodNames.CONFIGURE_SHIELD -> handleConfigureShield(call, result)
                MethodNames.UPSERT_MODE -> handleUpsertMode(call, result)
                MethodNames.REMOVE_MODE -> handleRemoveMode(call, result)
                MethodNames.SET_MODES_ENABLED -> handleSetModesEnabled(call, result)
                MethodNames.GET_MODES_CONFIG -> handleGetModesConfig(result)
                MethodNames.IS_RESTRICTION_SESSION_ACTIVE_NOW -> handleIsRestrictionSessionActiveNow(result)
                MethodNames.PAUSE_ENFORCEMENT -> handlePauseEnforcement(call, result)
                MethodNames.RESUME_ENFORCEMENT -> handleResumeEnforcement(result)
                MethodNames.START_SESSION -> handleStartSession(call, result)
                MethodNames.END_SESSION -> handleEndSession(result)
                MethodNames.GET_PENDING_LIFECYCLE_EVENTS -> handleGetPendingLifecycleEvents(call, result)
                MethodNames.ACK_LIFECYCLE_EVENTS -> handleAckLifecycleEvents(call, result)
                MethodNames.GET_RESTRICTION_SESSION -> handleGetRestrictionSession(result)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = call.method,
                message = "Unexpected restriction error: ${e.message}",
                error = e,
            )
        }
    }

    fun dispose() {
        lifecycleExecutor.shutdown()
    }

    private fun postResult(action: () -> Unit) {
        val poster = resultPoster
        if (poster != null) {
            poster(action)
            return
        }
        Handler(Looper.getMainLooper()).post(action)
    }

    private fun handleConfigureShield(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.CONFIGURE_SHIELD,
                message = "Application context is not available",
            )
            return
        }

        val configMap = call.arguments as? Map<String, Any?>
        if (configMap == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.CONFIGURE_SHIELD,
                message = "Shield configuration map is required",
            )
            return
        }

        try {
            com.example.pauza_screen_time.app_restriction.ShieldOverlayManager.getInstance(context).configure(configMap)
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.CONFIGURE_SHIELD,
                message = "Failed to configure shield: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleUpsertMode(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.UPSERT_MODE,
                message = "Application context is not available",
            )
            return
        }
        if (emitRestrictionPreflightErrorIfAny(context, MethodNames.UPSERT_MODE, result)) {
            return
        }

        val payload = call.arguments as? Map<*, *>
        if (payload == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.UPSERT_MODE,
                message = "Missing or invalid mode payload",
            )
            return
        }

        val modeId = (payload["modeId"] as? String)?.trim().orEmpty()
        val blockedAppIdsRaw = payload["blockedAppIds"] as? List<*>
        if (modeId.isEmpty() || blockedAppIdsRaw == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.UPSERT_MODE,
                message = "Mode requires 'modeId' and 'blockedAppIds'",
            )
            return
        }

        val blockedAppIds = blockedAppIdsRaw.mapNotNull { (it as? String)?.trim() }.filter { it.isNotEmpty() }.distinct()
        val scheduleMap = payload["schedule"] as? Map<*, *>
        val schedule = if (scheduleMap == null) {
            null
        } else {
            val rawDays = scheduleMap["daysOfWeekIso"] as? List<*>
            val startMinutes = (scheduleMap["startMinutes"] as? Number)?.toInt()
            val endMinutes = (scheduleMap["endMinutes"] as? Number)?.toInt()
            if (rawDays == null || startMinutes == null || endMinutes == null) {
                PluginErrorHelper.invalidArgument(
                    result = result,
                    feature = FEATURE,
                    action = MethodNames.UPSERT_MODE,
                    message = "Schedule requires 'daysOfWeekIso', 'startMinutes', and 'endMinutes'",
                )
                return
            }
            val days = rawDays.mapNotNull { (it as? Number)?.toInt() }.toSet()
            RestrictionScheduleEntry(
                daysOfWeekIso = days,
                startMinutes = startMinutes,
                endMinutes = endMinutes,
            )
        }

        if (schedule != null) {
            val scheduleCalculator = RestrictionScheduleCalculator()
            if (!scheduleCalculator.isScheduleShapeValid(RestrictionScheduleConfig(enabled = true, schedules = listOf(schedule)))) {
                PluginErrorHelper.invalidArgument(
                    result = result,
                    feature = FEATURE,
                    action = MethodNames.UPSERT_MODE,
                    message = "Mode schedule payload is invalid",
                )
                return
            }
        }

        try {
            val store = RestrictionScheduledModesStore(context)
            val mode = RestrictionScheduledModeEntry(
                modeId = modeId,
                schedule = schedule,
                blockedAppIds = blockedAppIds,
            )

            val nextModes = store.getConfig().modes.toMutableList()
            nextModes.removeAll { it.modeId == mode.modeId }
            if (mode.shouldPersistForScheduleEnforcement()) {
                nextModes += mode
            }
            val scheduleCalculator = RestrictionScheduleCalculator()
            val shapeIsValid = scheduleCalculator.isScheduleShapeValid(
                RestrictionScheduleConfig(
                    enabled = true,
                    schedules = nextModes.filter { it.schedule != null }.mapNotNull { it.schedule },
                ),
            )
            if (!shapeIsValid) {
                PluginErrorHelper.invalidArgument(
                    result = result,
                    feature = FEATURE,
                    action = MethodNames.UPSERT_MODE,
                    message = "Mode schedule overlaps with an existing schedule",
                )
                return
            }

            if (mode.shouldPersistForScheduleEnforcement()) {
                store.upsertMode(mode)
            } else {
                store.removeMode(mode.modeId)
            }

            val restrictionManager = RestrictionManager.getInstance(context)
            val activeSession = restrictionManager.getActiveSession()
            if (activeSession?.modeId == mode.modeId) {
                if (mode.blockedAppIds.isNotEmpty()) {
                    restrictionManager.setActiveSession(mode.modeId, mode.blockedAppIds, activeSession.source)
                } else {
                    restrictionManager.clearActiveSession()
                }
            }

            RestrictionAlarmOrchestrator(context).rescheduleAll()
            RestrictionSessionController(context).applyCurrentEnforcementState(trigger = "upsert_mode")
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.UPSERT_MODE,
                message = "Failed to save mode: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleRemoveMode(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.REMOVE_MODE,
                message = "Application context is not available",
            )
            return
        }

        val payload = call.arguments as? Map<*, *>
        val modeId = (payload?.get("modeId") as? String)?.trim().orEmpty()
        if (modeId.isEmpty()) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.REMOVE_MODE,
                message = "Missing or invalid 'modeId' argument",
            )
            return
        }

        try {
            val modesStore = RestrictionScheduledModesStore(context)
            modesStore.removeMode(modeId)
            val restrictionManager = RestrictionManager.getInstance(context)
            if (restrictionManager.getActiveSession()?.modeId == modeId) {
                restrictionManager.clearActiveSession()
            }
            RestrictionAlarmOrchestrator(context).rescheduleAll()
            RestrictionSessionController(context).applyCurrentEnforcementState(trigger = "remove_mode")
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.REMOVE_MODE,
                message = "Failed to remove mode: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleSetModesEnabled(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.SET_MODES_ENABLED,
                message = "Application context is not available",
            )
            return
        }
        if (emitRestrictionPreflightErrorIfAny(context, MethodNames.SET_MODES_ENABLED, result)) {
            return
        }

        val payload = call.arguments as? Map<*, *>
        val enabled = payload?.get("enabled") as? Boolean
        if (enabled == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.SET_MODES_ENABLED,
                message = "Missing or invalid 'enabled' argument",
            )
            return
        }

        try {
            RestrictionScheduledModesStore(context).setEnabled(enabled)
            RestrictionAlarmOrchestrator(context).rescheduleAll()
            RestrictionSessionController(context).applyCurrentEnforcementState(trigger = "set_modes_enabled")
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.SET_MODES_ENABLED,
                message = "Failed to update modes toggle: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleGetModesConfig(result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.GET_MODES_CONFIG,
                message = "Application context is not available",
            )
            return
        }

        try {
            val config = RestrictionScheduledModesStore(context).getConfig()
            result.success(config.toChannelMap())
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.GET_MODES_CONFIG,
                message = "Failed to load modes config: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleIsRestrictionSessionActiveNow(result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.IS_RESTRICTION_SESSION_ACTIVE_NOW,
                message = "Application context is not available",
            )
            return
        }

        try {
            val sessionState = RestrictionSessionController(context).resolveSessionState()
            val isPausedNow = RestrictionManager.getInstance(context).isPausedNow()
            val isPrerequisitesMet = areRestrictionPrerequisitesMet(context)
            val shouldEnforceSession = sessionState.activeModeSource != RestrictionModeSource.NONE
            result.success(sessionState.blockedAppIds.isNotEmpty() && !isPausedNow && isPrerequisitesMet && shouldEnforceSession)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.IS_RESTRICTION_SESSION_ACTIVE_NOW,
                message = "Failed to get restriction session active state: ${e.message}",
                error = e,
            )
        }
    }

    private fun handlePauseEnforcement(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.PAUSE_ENFORCEMENT,
                message = "Application context is not available",
            )
            return
        }
        if (emitRestrictionPreflightErrorIfAny(context, MethodNames.PAUSE_ENFORCEMENT, result)) {
            return
        }

        val durationMs = call.argument<Number>("durationMs")?.toLong()
        if (durationMs == null || durationMs <= 0L) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.PAUSE_ENFORCEMENT,
                message = "Missing or invalid 'durationMs' argument",
            )
            return
        }
        if (durationMs >= MAX_RELIABLE_PAUSE_DURATION_MS) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.PAUSE_ENFORCEMENT,
                message = "Pause duration must be less than 24 hours on Android",
            )
            return
        }

        try {
            val restrictionManager = RestrictionManager.getInstance(context)
            val sessionController = RestrictionSessionController(context)
            val previousSnapshot = sessionController.captureLifecycleSnapshot()
            if (restrictionManager.isPausedNow()) {
                PluginErrorHelper.invalidArgument(
                    result = result,
                    feature = FEATURE,
                    action = MethodNames.PAUSE_ENFORCEMENT,
                    message = "Restriction enforcement is already paused",
                )
                return
            }

            restrictionManager.pauseFor(durationMs)
            RestrictionAlarmOrchestrator(context).rescheduleAll()
            com.example.pauza_screen_time.app_restriction.ShieldOverlayManager.getInstanceOrNull()?.hideShield()
            sessionController.applyCurrentEnforcementState(
                trigger = "pause_enforcement",
                previousLifecycleSnapshot = previousSnapshot,
            )
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.PAUSE_ENFORCEMENT,
                message = "Failed to pause restriction enforcement: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleResumeEnforcement(result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.RESUME_ENFORCEMENT,
                message = "Application context is not available",
            )
            return
        }
        if (emitRestrictionPreflightErrorIfAny(context, MethodNames.RESUME_ENFORCEMENT, result)) {
            return
        }

        try {
            val sessionController = RestrictionSessionController(context)
            val previousSnapshot = sessionController.captureLifecycleSnapshot()
            RestrictionManager.getInstance(context).clearPause()
            RestrictionAlarmOrchestrator(context).rescheduleAll()
            sessionController.applyCurrentEnforcementState(
                trigger = "resume_enforcement",
                previousLifecycleSnapshot = previousSnapshot,
            )
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.RESUME_ENFORCEMENT,
                message = "Failed to resume restriction enforcement: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleStartSession(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.START_SESSION,
                message = "Application context is not available",
            )
            return
        }
        if (emitRestrictionPreflightErrorIfAny(context, MethodNames.START_SESSION, result)) {
            return
        }

        val payload = call.arguments as? Map<*, *>
        if (payload == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.START_SESSION,
                message = "Missing or invalid mode payload",
            )
            return
        }

        val modeId = (payload["modeId"] as? String)?.trim().orEmpty()
        val blockedAppIdsRaw = payload["blockedAppIds"] as? List<*>
        if (modeId.isEmpty() || blockedAppIdsRaw == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.START_SESSION,
                message = "Mode requires 'modeId' and 'blockedAppIds'",
            )
            return
        }
        val blockedAppIds = blockedAppIdsRaw
            .mapNotNull { (it as? String)?.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
        if (blockedAppIds.isEmpty()) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.START_SESSION,
                message = "Mode requires non-empty 'blockedAppIds'",
            )
            return
        }

        try {
            RestrictionSessionController(context).startSession(
                modeId = modeId,
                blockedAppIds = blockedAppIds,
                source = RestrictionModeSource.MANUAL,
                trigger = "start_session_manual",
            )
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.START_SESSION,
                message = "Failed to start session: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleEndSession(result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.END_SESSION,
                message = "Application context is not available",
            )
            return
        }

        try {
            RestrictionSessionController(context).endSession(
                source = RestrictionModeSource.MANUAL,
                trigger = "end_session_manual",
            )
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.END_SESSION,
                message = "Failed to end session: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleGetRestrictionSession(result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.GET_RESTRICTION_SESSION,
                message = "Application context is not available",
            )
            return
        }

        try {
            val restrictionManager = RestrictionManager.getInstance(context)
            val pausedUntilEpochMs = restrictionManager.getPausedUntilEpochMs()
            val isPausedNow = pausedUntilEpochMs > 0L
            val state = RestrictionSessionController(context).resolveSessionState()
            val activeSession = restrictionManager.getActiveSession()
            val currentSessionEvents = if (activeSession == null) {
                emptyList()
            } else {
                restrictionManager
                    .getPendingLifecycleEvents(Int.MAX_VALUE)
                    .filter { it.sessionId == activeSession.sessionId }
                    .map { it.toChannelMap() }
            }
            val payload = RestrictionSessionDto(
                isScheduleEnabled = state.isScheduleEnabled,
                isInScheduleNow = state.isInScheduleNow,
                pausedUntilEpochMs = if (isPausedNow) pausedUntilEpochMs else null,
                activeMode = state.activeModeId?.let { activeModeId ->
                    RestrictionModeDto(
                        modeId = activeModeId,
                        blockedAppIds = state.blockedAppIds,
                    )
                },
                activeModeSource = state.activeModeSource,
                currentSessionEvents = currentSessionEvents,
            )
            result.success(payload.toChannelMap())
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.GET_RESTRICTION_SESSION,
                message = "Failed to get restriction session: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleGetPendingLifecycleEvents(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.GET_PENDING_LIFECYCLE_EVENTS,
                message = "Application context is not available",
            )
            return
        }

        val payload = call.arguments as? Map<*, *>
        val limit = (payload?.get("limit") as? Number)?.toInt() ?: 200
        if (limit <= 0) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.GET_PENDING_LIFECYCLE_EVENTS,
                message = "Missing or invalid 'limit' argument",
            )
            return
        }

        lifecycleExecutor.execute {
            try {
                val events = RestrictionManager.getInstance(context).getPendingLifecycleEvents(limit)
                postResult {
                    result.success(events.map { it.toChannelMap() })
                }
            } catch (e: Exception) {
                postResult {
                    PluginErrorHelper.internalFailure(
                        result = result,
                        feature = FEATURE,
                        action = MethodNames.GET_PENDING_LIFECYCLE_EVENTS,
                        message = "Failed to load pending lifecycle events: ${e.message}",
                        error = e,
                    )
                }
            }
        }
    }

    private fun handleAckLifecycleEvents(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.ACK_LIFECYCLE_EVENTS,
                message = "Application context is not available",
            )
            return
        }

        val payload = call.arguments as? Map<*, *>
        val throughEventId = (payload?.get("throughEventId") as? String)?.trim().orEmpty()
        if (throughEventId.isEmpty()) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.ACK_LIFECYCLE_EVENTS,
                message = "Missing or invalid 'throughEventId' argument",
            )
            return
        }

        lifecycleExecutor.execute {
            try {
                val success = RestrictionManager.getInstance(context).ackLifecycleEventsThrough(throughEventId)
                if (!success) {
                    postResult {
                        PluginErrorHelper.internalFailure(
                            result = result,
                            feature = FEATURE,
                            action = MethodNames.ACK_LIFECYCLE_EVENTS,
                            message = "Failed to acknowledge lifecycle events",
                        )
                    }
                    return@execute
                }
                postResult {
                    result.success(null)
                }
            } catch (e: Exception) {
                postResult {
                    PluginErrorHelper.internalFailure(
                        result = result,
                        feature = FEATURE,
                        action = MethodNames.ACK_LIFECYCLE_EVENTS,
                        message = "Failed to acknowledge lifecycle events: ${e.message}",
                        error = e,
                    )
                }
            }
        }
    }

    private fun areRestrictionPrerequisitesMet(context: Context): Boolean {
        return getMissingPrerequisites(context).isEmpty()
    }

    private fun getMissingPrerequisites(context: Context): List<String> {
        val accessibilityStatus = accessibilityStatusProvider(context)
        if (accessibilityStatus == PermissionHandler.STATUS_GRANTED) {
            return emptyList()
        }
        return listOf(ANDROID_ACCESSIBILITY_KEY)
    }

    private fun emitRestrictionPreflightErrorIfAny(context: Context, action: String, result: Result): Boolean {
        val accessibilityStatus = accessibilityStatusProvider(context)
        if (accessibilityStatus == PermissionHandler.STATUS_GRANTED) {
            return false
        }

        PluginErrorHelper.missingPermission(
            result = result,
            feature = FEATURE,
            action = action,
            message = "Accessibility permission is required for restrictions",
            missing = listOf(ANDROID_ACCESSIBILITY_KEY),
            status = mapOf("androidAccessibilityStatus" to accessibilityStatus),
        )
        return true
    }
}

private fun RestrictionScheduledModeEntry.shouldPersistForScheduleEnforcement(): Boolean {
    return schedule != null && blockedAppIds.isNotEmpty()
}
