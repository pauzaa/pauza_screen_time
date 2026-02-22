package com.example.pauza_screen_time.app_restriction.method_channel

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.example.pauza_screen_time.core.PlatformConstants
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModeEntry
import com.example.pauza_screen_time.app_restriction.usecase.ConfigureShieldUseCase
import com.example.pauza_screen_time.app_restriction.usecase.LifecycleEventsUseCase
import com.example.pauza_screen_time.app_restriction.usecase.ManageModesUseCase
import com.example.pauza_screen_time.app_restriction.usecase.SessionEnforcementUseCase
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
        private const val ACTIVE_SESSION_ERROR_MESSAGE =
            "A restriction session is already active. End the current session before starting a new one."
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
        val context = contextProvider() ?: return noContext(result, MethodNames.CONFIGURE_SHIELD)
        val configMap = call.arguments as? Map<String, Any?>
        if (configMap == null) {
            PluginErrorHelper.invalidArgument(result, FEATURE, MethodNames.CONFIGURE_SHIELD, "Shield configuration map is required")
            return
        }
        try {
            ConfigureShieldUseCase(context).execute(configMap)
            result.success(null)
        } catch (e: Exception) {
            internalFailure(result, MethodNames.CONFIGURE_SHIELD, "Failed to configure shield", e)
        }
    }

    private fun handleUpsertMode(call: MethodCall, result: Result) {
        val context = contextProvider() ?: return noContext(result, MethodNames.UPSERT_MODE)
        if (emitRestrictionPreflightErrorIfAny(context, MethodNames.UPSERT_MODE, result)) return

        val payload = call.arguments as? Map<*, *>
        if (payload == null) {
            PluginErrorHelper.invalidArgument(result, FEATURE, MethodNames.UPSERT_MODE, "Missing or invalid mode payload")
            return
        }

        try {
            val mode = RestrictionScheduledModeEntry.fromMap(payload)
            ManageModesUseCase(context).upsertMode(mode.modeId, mode.blockedAppIds, mode.schedule)
            result.success(null)
        } catch (e: IllegalArgumentException) {
            PluginErrorHelper.invalidArgument(result, FEATURE, MethodNames.UPSERT_MODE, e.message ?: "Invalid mode payload")
        } catch (e: Exception) {
            internalFailure(result, MethodNames.UPSERT_MODE, "Failed to save mode", e)
        }
    }

    private fun handleRemoveMode(call: MethodCall, result: Result) {
        val context = contextProvider() ?: return noContext(result, MethodNames.REMOVE_MODE)
        val modeId = ((call.arguments as? Map<*, *>)?.get("modeId") as? String)?.trim().orEmpty()
        if (modeId.isEmpty()) {
            PluginErrorHelper.invalidArgument(result, FEATURE, MethodNames.REMOVE_MODE, "Missing or invalid 'modeId' argument")
            return
        }
        try {
            ManageModesUseCase(context).removeMode(modeId)
            result.success(null)
        } catch (e: Exception) {
            internalFailure(result, MethodNames.REMOVE_MODE, "Failed to remove mode", e)
        }
    }

    private fun handleSetModesEnabled(call: MethodCall, result: Result) {
        val context = contextProvider() ?: return noContext(result, MethodNames.SET_MODES_ENABLED)
        if (emitRestrictionPreflightErrorIfAny(context, MethodNames.SET_MODES_ENABLED, result)) return
        val enabled = (call.arguments as? Map<*, *>)?.get("enabled") as? Boolean
        if (enabled == null) {
            PluginErrorHelper.invalidArgument(result, FEATURE, MethodNames.SET_MODES_ENABLED, "Missing or invalid 'enabled' argument")
            return
        }
        try {
            ManageModesUseCase(context).setModesEnabled(enabled)
            result.success(null)
        } catch (e: Exception) {
            internalFailure(result, MethodNames.SET_MODES_ENABLED, "Failed to update modes toggle", e)
        }
    }

    private fun handleGetModesConfig(result: Result) {
        val context = contextProvider() ?: return noContext(result, MethodNames.GET_MODES_CONFIG)
        try {
            val config = ManageModesUseCase(context).getModesConfig()
            result.success(config.toChannelMap())
        } catch (e: Exception) {
            internalFailure(result, MethodNames.GET_MODES_CONFIG, "Failed to load modes config", e)
        }
    }

    private fun handleIsRestrictionSessionActiveNow(result: Result) {
        val context = contextProvider() ?: return noContext(result, MethodNames.IS_RESTRICTION_SESSION_ACTIVE_NOW)
        try {
            val isActive = SessionEnforcementUseCase(context).isRestrictionSessionActiveNow(areRestrictionPrerequisitesMet(context))
            result.success(isActive)
        } catch (e: Exception) {
            internalFailure(result, MethodNames.IS_RESTRICTION_SESSION_ACTIVE_NOW, "Failed to get restriction session active state", e)
        }
    }

    private fun handlePauseEnforcement(call: MethodCall, result: Result) {
        val context = contextProvider() ?: return noContext(result, MethodNames.PAUSE_ENFORCEMENT)
        if (emitRestrictionPreflightErrorIfAny(context, MethodNames.PAUSE_ENFORCEMENT, result)) return

        val durationMs = call.argument<Number>("durationMs")?.toLong()
        if (durationMs == null || durationMs <= 0L) {
            PluginErrorHelper.invalidArgument(result, FEATURE, MethodNames.PAUSE_ENFORCEMENT, "Missing or invalid 'durationMs' argument")
            return
        }
        if (durationMs >= PlatformConstants.MAX_RELIABLE_PAUSE_DURATION_MS) {
            PluginErrorHelper.invalidArgument(result, FEATURE, MethodNames.PAUSE_ENFORCEMENT, "Pause duration must be less than 24 hours on Android")
            return
        }

        try {
            SessionEnforcementUseCase(context).pauseEnforcement(durationMs)
            result.success(null)
        } catch (e: IllegalStateException) {
            PluginErrorHelper.invalidArgument(result, FEATURE, MethodNames.PAUSE_ENFORCEMENT, e.message ?: "Invalid state for pause")
        } catch (e: Exception) {
            internalFailure(result, MethodNames.PAUSE_ENFORCEMENT, "Failed to pause restriction enforcement", e)
        }
    }

    private fun handleResumeEnforcement(result: Result) {
        val context = contextProvider() ?: return noContext(result, MethodNames.RESUME_ENFORCEMENT)
        if (emitRestrictionPreflightErrorIfAny(context, MethodNames.RESUME_ENFORCEMENT, result)) return
        try {
            SessionEnforcementUseCase(context).resumeEnforcement()
            result.success(null)
        } catch (e: Exception) {
            internalFailure(result, MethodNames.RESUME_ENFORCEMENT, "Failed to resume restriction enforcement", e)
        }
    }

    private fun handleStartSession(call: MethodCall, result: Result) {
        val context = contextProvider() ?: return noContext(result, MethodNames.START_SESSION)
        if (emitRestrictionPreflightErrorIfAny(context, MethodNames.START_SESSION, result)) return
        val sessionUseCase = SessionEnforcementUseCase(context)
        if (emitActiveSessionErrorIfAny(sessionUseCase, MethodNames.START_SESSION, result)) return

        val payload = call.arguments as? Map<*, *>
        if (payload == null) {
            PluginErrorHelper.invalidArgument(result, FEATURE, MethodNames.START_SESSION, "Missing or invalid mode payload")
            return
        }

        try {
            val mode = RestrictionScheduledModeEntry.fromMap(payload)
            if (mode.blockedAppIds.isEmpty()) {
                PluginErrorHelper.invalidArgument(result, FEATURE, MethodNames.START_SESSION, "Mode requires non-empty 'blockedAppIds'")
                return
            }
            val durationMs = payload["durationMs"]?.let { rawDuration ->
                parseStartSessionDurationMs(rawDuration, result) ?: return
            }
            sessionUseCase.startSession(mode.modeId, mode.blockedAppIds, durationMs)
            result.success(null)
        } catch (e: IllegalArgumentException) {
            PluginErrorHelper.invalidArgument(result, FEATURE, MethodNames.START_SESSION, e.message ?: "Invalid mode payload")
        } catch (e: Exception) {
            internalFailure(result, MethodNames.START_SESSION, "Failed to start session", e)
        }
    }

    private fun handleEndSession(result: Result) {
        val context = contextProvider() ?: return noContext(result, MethodNames.END_SESSION)
        try {
            SessionEnforcementUseCase(context).endSession()
            result.success(null)
        } catch (e: Exception) {
            internalFailure(result, MethodNames.END_SESSION, "Failed to end session", e)
        }
    }

    private fun handleGetRestrictionSession(result: Result) {
        val context = contextProvider() ?: return noContext(result, MethodNames.GET_RESTRICTION_SESSION)
        try {
            val session = SessionEnforcementUseCase(context).getRestrictionSession()
            result.success(session.toChannelMap())
        } catch (e: Exception) {
            internalFailure(result, MethodNames.GET_RESTRICTION_SESSION, "Failed to get restriction session", e)
        }
    }

    private fun handleGetPendingLifecycleEvents(call: MethodCall, result: Result) {
        val context = contextProvider() ?: return noContext(result, MethodNames.GET_PENDING_LIFECYCLE_EVENTS)
        val limit = ((call.arguments as? Map<*, *>)?.get("limit") as? Number)?.toInt() ?: PlatformConstants.DEFAULT_LIFECYCLE_EVENTS_LIMIT
        if (limit <= 0) {
            PluginErrorHelper.invalidArgument(result, FEATURE, MethodNames.GET_PENDING_LIFECYCLE_EVENTS, "Missing or invalid 'limit' argument")
            return
        }

        lifecycleExecutor.execute {
            try {
                val events = LifecycleEventsUseCase(context).getPendingLifecycleEvents(limit)
                postResult { result.success(events.map { it.toChannelMap() }) }
            } catch (e: Exception) {
                postResult { internalFailure(result, MethodNames.GET_PENDING_LIFECYCLE_EVENTS, "Failed to load pending lifecycle events", e) }
            }
        }
    }

    private fun handleAckLifecycleEvents(call: MethodCall, result: Result) {
        val context = contextProvider() ?: return noContext(result, MethodNames.ACK_LIFECYCLE_EVENTS)
        val throughEventId = ((call.arguments as? Map<*, *>)?.get("throughEventId") as? String)?.trim().orEmpty()
        if (throughEventId.isEmpty()) {
            PluginErrorHelper.invalidArgument(result, FEATURE, MethodNames.ACK_LIFECYCLE_EVENTS, "Missing or invalid 'throughEventId' argument")
            return
        }

        lifecycleExecutor.execute {
            try {
                LifecycleEventsUseCase(context).ackLifecycleEventsThrough(throughEventId)
                postResult { result.success(null) }
            } catch (e: Exception) {
                postResult { internalFailure(result, MethodNames.ACK_LIFECYCLE_EVENTS, "Failed to acknowledge lifecycle events", e) }
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

    private fun emitActiveSessionErrorIfAny(
        sessionUseCase: SessionEnforcementUseCase,
        action: String,
        result: Result,
    ): Boolean {
        if (!sessionUseCase.hasActiveSession()) {
            return false
        }
        PluginErrorHelper.invalidArgument(result, FEATURE, action, ACTIVE_SESSION_ERROR_MESSAGE)
        return true
    }

    private fun parseStartSessionDurationMs(rawDurationMs: Any?, result: Result): Long? {
        val durationMs = (rawDurationMs as? Number)?.toLong()
        if (durationMs == null || durationMs <= 0L) {
            PluginErrorHelper.invalidArgument(
                result,
                FEATURE,
                MethodNames.START_SESSION,
                "Missing or invalid 'durationMs' argument",
            )
            return null
        }
        if (durationMs >= PlatformConstants.MAX_RELIABLE_PAUSE_DURATION_MS) {
            PluginErrorHelper.invalidArgument(
                result,
                FEATURE,
                MethodNames.START_SESSION,
                "Session duration must be less than 24 hours on Android",
            )
            return null
        }
        return durationMs
    }

    private fun noContext(result: Result, action: String) {
        PluginErrorHelper.internalFailure(result, FEATURE, action, "Application context is not available")
    }

    private fun internalFailure(result: Result, action: String, message: String, e: Exception) {
        PluginErrorHelper.internalFailure(result, FEATURE, action, "$message: ${e.message}", e.message)
    }
}
