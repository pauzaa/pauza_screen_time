package com.example.pauza_screen_time.app_restriction.method_channel

import android.content.Context
import com.example.pauza_screen_time.app_restriction.AppMonitoringService
import com.example.pauza_screen_time.app_restriction.RestrictionManager
import com.example.pauza_screen_time.app_restriction.ShieldOverlayManager
import com.example.pauza_screen_time.app_restriction.alarm.RestrictionAlarmOrchestrator
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleCalculator
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleConfig
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleEntry
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModeEntry
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModeResolver
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModesStore
import com.example.pauza_screen_time.core.MethodNames
import com.example.pauza_screen_time.core.PluginErrorHelper
import com.example.pauza_screen_time.permissions.PermissionHandler
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class RestrictionsMethodHandler(
    private val contextProvider: () -> Context?,
) : MethodCallHandler {
    companion object {
        private const val ANDROID_ACCESSIBILITY_KEY = "android.accessibility"
        private const val FEATURE = "restrictions"
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
                MethodNames.IS_RESTRICTION_SESSION_CONFIGURED -> handleIsRestrictionSessionConfigured(result)
                MethodNames.PAUSE_ENFORCEMENT -> handlePauseEnforcement(call, result)
                MethodNames.RESUME_ENFORCEMENT -> handleResumeEnforcement(result)
                MethodNames.START_MODE_SESSION -> handleStartModeSession(call, result)
                MethodNames.END_MODE_SESSION -> handleEndModeSession(result)
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
            ShieldOverlayManager.getInstance(context).configure(configMap)
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
        val isEnabled = payload["isEnabled"] as? Boolean ?: true
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
                isEnabled = isEnabled,
                schedule = schedule,
                blockedAppIds = blockedAppIds,
            )

            val nextModes = store.getConfig().modes.toMutableList()
            val index = nextModes.indexOfFirst { it.modeId == mode.modeId }
            if (index >= 0) {
                nextModes[index] = mode
            } else {
                nextModes += mode
            }
            val scheduleCalculator = RestrictionScheduleCalculator()
            val shapeIsValid = scheduleCalculator.isScheduleShapeValid(
                RestrictionScheduleConfig(
                    enabled = true,
                    schedules = nextModes.filter { it.isEnabled && it.schedule != null }.mapNotNull { it.schedule },
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

            store.upsertMode(mode)
            RestrictionAlarmOrchestrator(context).rescheduleAll()
            applyCurrentEnforcementState(context, trigger = "upsert_mode")
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
            RestrictionScheduledModesStore(context).removeMode(modeId)
            val restrictionManager = RestrictionManager.getInstance(context)
            if (restrictionManager.getManualActiveModeId() == modeId) {
                restrictionManager.setManualActiveModeId(null)
            }
            RestrictionAlarmOrchestrator(context).rescheduleAll()
            applyCurrentEnforcementState(context, trigger = "remove_mode")
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
            applyCurrentEnforcementState(context, trigger = "set_modes_enabled")
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
            result.success(
                mapOf(
                    "enabled" to config.enabled,
                    "modes" to config.modes.map { mode ->
                        mapOf(
                            "modeId" to mode.modeId,
                            "isEnabled" to mode.isEnabled,
                            "schedule" to mode.schedule?.let {
                                mapOf(
                                    "daysOfWeekIso" to it.daysOfWeekIso.sorted(),
                                    "startMinutes" to it.startMinutes,
                                    "endMinutes" to it.endMinutes,
                                )
                            },
                            "blockedAppIds" to mode.blockedAppIds,
                        )
                    },
                ),
            )
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
            val sessionState = resolveSessionState(context)
            val isPausedNow = RestrictionManager.getInstance(context).isPausedNow()
            val isPrerequisitesMet = areRestrictionPrerequisitesMet(context)
            val shouldEnforceSession = sessionState.activeModeSource != "none"
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

    private fun handleIsRestrictionSessionConfigured(result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.IS_RESTRICTION_SESSION_CONFIGURED,
                message = "Application context is not available",
            )
            return
        }

        try {
            val hasConfig = RestrictionScheduledModesStore(context).getConfig().modes.any { it.blockedAppIds.isNotEmpty() }
            result.success(hasConfig)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.IS_RESTRICTION_SESSION_CONFIGURED,
                message = "Failed to get restriction session configuration state: ${e.message}",
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

        try {
            val restrictionManager = RestrictionManager.getInstance(context)
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
            ShieldOverlayManager.getInstanceOrNull()?.hideShield()
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

        try {
            RestrictionManager.getInstance(context).clearPause()
            RestrictionAlarmOrchestrator(context).rescheduleAll()
            AppMonitoringService.getInstance()?.enforceCurrentForegroundNow(
                trigger = "resume_enforcement",
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

    private fun handleStartModeSession(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.START_MODE_SESSION,
                message = "Application context is not available",
            )
            return
        }

        val modeId = call.argument<String>("modeId")?.trim().orEmpty()
        if (modeId.isEmpty()) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.START_MODE_SESSION,
                message = "Missing or invalid 'modeId' argument",
            )
            return
        }

        try {
            val store = RestrictionScheduledModesStore(context)
            val mode = store.getMode(modeId)
            if (mode == null || !mode.isEnabled) {
                PluginErrorHelper.invalidArgument(
                    result = result,
                    feature = FEATURE,
                    action = MethodNames.START_MODE_SESSION,
                    message = "Mode must exist and be enabled to start manual session",
                )
                return
            }

            RestrictionManager.getInstance(context).setManualActiveModeId(modeId)
            RestrictionAlarmOrchestrator(context).rescheduleAll()
            applyCurrentEnforcementState(context, trigger = "start_mode_session")
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.START_MODE_SESSION,
                message = "Failed to start mode session: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleEndModeSession(result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.END_MODE_SESSION,
                message = "Application context is not available",
            )
            return
        }

        try {
            RestrictionManager.getInstance(context).setManualActiveModeId(null)
            RestrictionAlarmOrchestrator(context).rescheduleAll()
            applyCurrentEnforcementState(context, trigger = "end_mode_session")
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.END_MODE_SESSION,
                message = "Failed to end mode session: ${e.message}",
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
            val isPrerequisitesMet = areRestrictionPrerequisitesMet(context)
            val state = resolveSessionState(context)
            val shouldEnforceSession = state.activeModeSource != "none"
            result.success(
                mapOf(
                    "isActiveNow" to (state.blockedAppIds.isNotEmpty() && !isPausedNow && isPrerequisitesMet && shouldEnforceSession),
                    "isPausedNow" to isPausedNow,
                    "isManuallyEnabled" to state.isManuallyEnabled,
                    "isScheduleEnabled" to state.isScheduleEnabled,
                    "isInScheduleNow" to state.isInScheduleNow,
                    "pausedUntilEpochMs" to if (isPausedNow) pausedUntilEpochMs else null,
                    "restrictedApps" to state.blockedAppIds,
                    "activeModeId" to state.activeModeId,
                    "activeModeSource" to state.activeModeSource,
                ),
            )
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

    private fun areRestrictionPrerequisitesMet(context: Context): Boolean {
        return getMissingPrerequisites(context).isEmpty()
    }

    private fun applyCurrentEnforcementState(context: Context, trigger: String) {
        val restrictionManager = RestrictionManager.getInstance(context)
        val state = resolveSessionState(context)
        restrictionManager.setRestrictedApps(state.blockedAppIds)

        val shouldEnforce = state.activeModeSource != "none"
        if (shouldEnforce) {
            AppMonitoringService.getInstance()?.enforceCurrentForegroundNow(trigger = trigger)
            return
        }
        ShieldOverlayManager.getInstanceOrNull()?.hideShield()
    }

    private fun resolveSessionState(context: Context): SessionState {
        val restrictionManager = RestrictionManager.getInstance(context)
        val modesConfig = RestrictionScheduledModesStore(context).getConfig()
        val manualModeId = restrictionManager.getManualActiveModeId()
        val manualMode = modesConfig.modes.firstOrNull { it.modeId == manualModeId && it.isEnabled }
        val scheduleResolution = RestrictionScheduledModeResolver.resolveNow(modesConfig)

        return when {
            manualMode != null -> SessionState(
                isManuallyEnabled = true,
                isScheduleEnabled = modesConfig.enabled,
                isInScheduleNow = scheduleResolution.isInScheduleNow,
                blockedAppIds = manualMode.blockedAppIds,
                activeModeId = manualMode.modeId,
                activeModeSource = "manual",
            )
            scheduleResolution.isInScheduleNow -> SessionState(
                isManuallyEnabled = manualModeId != null,
                isScheduleEnabled = modesConfig.enabled,
                isInScheduleNow = true,
                blockedAppIds = scheduleResolution.blockedAppIds,
                activeModeId = scheduleResolution.activeModeId,
                activeModeSource = "schedule",
            )
            else -> SessionState(
                isManuallyEnabled = manualModeId != null,
                isScheduleEnabled = modesConfig.enabled,
                isInScheduleNow = false,
                blockedAppIds = emptyList(),
                activeModeId = null,
                activeModeSource = "none",
            )
        }
    }

    private data class SessionState(
        val isManuallyEnabled: Boolean,
        val isScheduleEnabled: Boolean,
        val isInScheduleNow: Boolean,
        val blockedAppIds: List<String>,
        val activeModeId: String?,
        val activeModeSource: String,
    )

    private fun getMissingPrerequisites(context: Context): List<String> {
        val permissionHandler = PermissionHandler(context)
        val accessibilityStatus = permissionHandler.checkPermission(PermissionHandler.ACCESSIBILITY_KEY)
        if (accessibilityStatus == PermissionHandler.STATUS_GRANTED) {
            return emptyList()
        }
        return listOf(ANDROID_ACCESSIBILITY_KEY)
    }
}
