package com.example.pauza_screen_time.app_restriction.method_channel

import android.content.Context
import com.example.pauza_screen_time.app_restriction.AppMonitoringService
import com.example.pauza_screen_time.app_restriction.RestrictionCachedMode
import com.example.pauza_screen_time.app_restriction.RestrictionManualModeResolver
import com.example.pauza_screen_time.app_restriction.RestrictionManager
import com.example.pauza_screen_time.app_restriction.RestrictionModeUpsertCache
import com.example.pauza_screen_time.app_restriction.ShieldOverlayManager
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import com.example.pauza_screen_time.app_restriction.model.RestrictionSessionDto
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
            val isStartableMode = mode.blockedAppIds.isNotEmpty()
            if (isStartableMode) {
                RestrictionModeUpsertCache.upsert(
                    RestrictionCachedMode(
                        modeId = mode.modeId,
                        blockedAppIds = mode.blockedAppIds,
                    ),
                )
            } else {
                RestrictionModeUpsertCache.remove(mode.modeId)
            }

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
            val activeManualMode = RestrictionManualModeResolver.resolveActiveManualMode(
                restrictionManager = restrictionManager,
            )
            if (activeManualMode?.modeId == mode.modeId) {
                if (isStartableMode) {
                    restrictionManager.setManualActiveMode(mode.modeId, mode.blockedAppIds)
                } else {
                    restrictionManager.clearManualActiveMode()
                }
            }
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
            val modesStore = RestrictionScheduledModesStore(context)
            modesStore.removeMode(modeId)
            RestrictionModeUpsertCache.remove(modeId)
            val restrictionManager = RestrictionManager.getInstance(context)
            val activeManualMode = RestrictionManualModeResolver.resolveActiveManualMode(
                restrictionManager = restrictionManager,
            )
            if (activeManualMode?.modeId == modeId) {
                restrictionManager.clearManualActiveMode()
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
            val sessionState = resolveSessionState(context)
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
            val scheduledMode = store.getMode(modeId)
            val cachedMode = RestrictionModeUpsertCache.get(modeId)
            val resolvedBlockedIds = when {
                scheduledMode != null -> scheduledMode.blockedAppIds
                cachedMode != null && cachedMode.blockedAppIds.isNotEmpty() -> cachedMode.blockedAppIds
                else -> null
            }
            if (resolvedBlockedIds == null) {
                PluginErrorHelper.invalidArgument(
                    result = result,
                    feature = FEATURE,
                    action = MethodNames.START_MODE_SESSION,
                    message = "Mode must exist with blocked apps to start manual session. Call upsertMode first for unscheduled modes.",
                )
                return
            }

            RestrictionManager.getInstance(context).setManualActiveMode(modeId, resolvedBlockedIds)
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
            val restrictionManager = RestrictionManager.getInstance(context)
            val activeManualMode = restrictionManager.getManualActiveMode()
            restrictionManager.clearManualActiveMode()
            if (activeManualMode != null) {
                RestrictionModeUpsertCache.remove(activeManualMode.modeId)
            }
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
            val shouldEnforceSession = state.activeModeSource != RestrictionModeSource.NONE
            val payload = RestrictionSessionDto(
                isActiveNow = state.blockedAppIds.isNotEmpty() && !isPausedNow && isPrerequisitesMet && shouldEnforceSession,
                isPausedNow = isPausedNow,
                isScheduleEnabled = state.isScheduleEnabled,
                isInScheduleNow = state.isInScheduleNow,
                pausedUntilEpochMs = if (isPausedNow) pausedUntilEpochMs else null,
                restrictedApps = state.blockedAppIds,
                activeModeId = state.activeModeId,
                activeModeSource = state.activeModeSource,
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

    private fun areRestrictionPrerequisitesMet(context: Context): Boolean {
        return getMissingPrerequisites(context).isEmpty()
    }

    private fun applyCurrentEnforcementState(context: Context, trigger: String) {
        val restrictionManager = RestrictionManager.getInstance(context)
        val state = resolveSessionState(context)
        restrictionManager.setRestrictedApps(state.blockedAppIds)

        val shouldEnforce = state.activeModeSource != RestrictionModeSource.NONE
        if (shouldEnforce) {
            AppMonitoringService.getInstance()?.enforceCurrentForegroundNow(trigger = trigger)
            return
        }
        ShieldOverlayManager.getInstanceOrNull()?.hideShield()
    }

    private fun resolveSessionState(context: Context): SessionState {
        val restrictionManager = RestrictionManager.getInstance(context)
        val modesStore = RestrictionScheduledModesStore(context)
        val modesConfig = modesStore.getConfig()
        val manualMode = RestrictionManualModeResolver.resolveActiveManualMode(
            restrictionManager = restrictionManager,
        )
        val scheduleResolution = RestrictionScheduledModeResolver.resolveNow(modesConfig)

        return when {
            manualMode != null -> SessionState(
                isScheduleEnabled = modesConfig.enabled,
                isInScheduleNow = scheduleResolution.isInScheduleNow,
                blockedAppIds = manualMode.blockedAppIds,
                activeModeId = manualMode.modeId,
                activeModeSource = RestrictionModeSource.MANUAL,
            )
            scheduleResolution.isInScheduleNow -> SessionState(
                isScheduleEnabled = modesConfig.enabled,
                isInScheduleNow = true,
                blockedAppIds = scheduleResolution.blockedAppIds,
                activeModeId = scheduleResolution.activeModeId,
                activeModeSource = RestrictionModeSource.SCHEDULE,
            )
            else -> SessionState(
                isScheduleEnabled = modesConfig.enabled,
                isInScheduleNow = false,
                blockedAppIds = emptyList(),
                activeModeId = null,
                activeModeSource = RestrictionModeSource.NONE,
            )
        }
    }

    private data class SessionState(
        val isScheduleEnabled: Boolean,
        val isInScheduleNow: Boolean,
        val blockedAppIds: List<String>,
        val activeModeId: String?,
        val activeModeSource: RestrictionModeSource,
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

private fun RestrictionScheduledModeEntry.shouldPersistForScheduleEnforcement(): Boolean {
    return schedule != null && blockedAppIds.isNotEmpty()
}
