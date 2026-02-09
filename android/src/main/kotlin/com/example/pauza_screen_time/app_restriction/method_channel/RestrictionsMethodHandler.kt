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
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModesConfig
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModesStore
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleStore
import com.example.pauza_screen_time.core.MethodNames
import com.example.pauza_screen_time.core.PluginErrorHelper
import com.example.pauza_screen_time.permissions.PermissionHandler
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class RestrictionsMethodHandler(
    private val contextProvider: () -> Context?
) : MethodCallHandler {
    companion object {
        private const val ANDROID_ACCESSIBILITY_KEY = "android.accessibility"
        private const val FEATURE = "restrictions"
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                MethodNames.CONFIGURE_SHIELD -> handleConfigureShield(call, result)
                MethodNames.SET_RESTRICTED_APPS -> handleSetRestrictedApps(call, result)
                MethodNames.ADD_RESTRICTED_APP -> handleAddRestrictedApp(call, result)
                MethodNames.REMOVE_RESTRICTION -> handleRemoveRestriction(call, result)
                MethodNames.REMOVE_ALL_RESTRICTIONS -> handleRemoveAllRestrictions(result)
                MethodNames.GET_RESTRICTED_APPS -> handleGetRestrictedApps(result)
                MethodNames.IS_RESTRICTED -> handleIsRestricted(call, result)
                MethodNames.IS_RESTRICTION_SESSION_ACTIVE_NOW -> handleIsRestrictionSessionActiveNow(result)
                MethodNames.IS_RESTRICTION_SESSION_CONFIGURED -> handleIsRestrictionSessionConfigured(result)
                MethodNames.PAUSE_ENFORCEMENT -> handlePauseEnforcement(call, result)
                MethodNames.RESUME_ENFORCEMENT -> handleResumeEnforcement(result)
                MethodNames.START_RESTRICTION_SESSION -> handleStartRestrictionSession(result)
                MethodNames.END_RESTRICTION_SESSION -> handleEndRestrictionSession(result)
                MethodNames.SET_RESTRICTION_SCHEDULE_CONFIG -> handleSetRestrictionScheduleConfig(call, result)
                MethodNames.GET_RESTRICTION_SCHEDULE_CONFIG -> handleGetRestrictionScheduleConfig(result)
                MethodNames.GET_RESTRICTION_SESSION -> handleGetRestrictionSession(result)
                MethodNames.UPSERT_SCHEDULED_MODE -> handleUpsertScheduledMode(call, result)
                MethodNames.REMOVE_SCHEDULED_MODE -> handleRemoveScheduledMode(call, result)
                MethodNames.SET_SCHEDULED_MODES_ENABLED -> handleSetScheduledModesEnabled(call, result)
                MethodNames.GET_SCHEDULED_MODES_CONFIG -> handleGetScheduledModesConfig(result)
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

    private fun handleSetRestrictedApps(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.SET_RESTRICTED_APPS,
                message = "Application context is not available",
            )
            return
        }

        val args = call.arguments
        val identifiers: List<String>? = when (args) {
            is Map<*, *> -> {
                val raw = args["identifiers"]
                if (raw is List<*>) {
                    val list = raw.filterIsInstance<String>()
                    if (list.size == raw.size) list else null
                } else {
                    null
                }
            }
            is List<*> -> {
                val list = args.filterIsInstance<String>()
                if (list.size == args.size) list else null
            }
            else -> null
        }

        if (identifiers == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.SET_RESTRICTED_APPS,
                message = "Missing or invalid 'identifiers' argument",
            )
            return
        }

        try {
            val trimmed = identifiers.map { it.trim() }
            val hasBlank = trimmed.any { it.isBlank() }
            if (hasBlank) {
                PluginErrorHelper.invalidArgument(
                    result = result,
                    feature = FEATURE,
                    action = MethodNames.SET_RESTRICTED_APPS,
                    message = "Identifiers must be non-blank strings",
                )
                return
            }

            val applied = LinkedHashSet<String>()
            for (identifier in trimmed) {
                applied.add(identifier)
            }
            val appliedList = applied.toList()

            if (appliedList.isNotEmpty()) {
                val missingPrerequisites = getMissingPrerequisites(context)
                if (missingPrerequisites.isNotEmpty()) {
                    PluginErrorHelper.missingPermission(
                        result = result,
                        feature = FEATURE,
                        action = MethodNames.SET_RESTRICTED_APPS,
                        message = "Restriction prerequisites are not satisfied",
                        missing = missingPrerequisites,
                        status = mapOf(
                            ANDROID_ACCESSIBILITY_KEY to PermissionHandler(context)
                                .checkPermission(PermissionHandler.ACCESSIBILITY_KEY),
                        ),
                    )
                    return
                }
            }

            RestrictionManager.getInstance(context).setRestrictedApps(appliedList)
            result.success(appliedList)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.SET_RESTRICTED_APPS,
                message = "Failed to set restricted apps: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleAddRestrictedApp(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.ADD_RESTRICTED_APP,
                message = "Application context is not available",
            )
            return
        }

        val identifier = call.argument<String>("identifier")
        if (identifier == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.ADD_RESTRICTED_APP,
                message = "Missing or invalid 'identifier' argument",
            )
            return
        }

        try {
            val missingPrerequisites = getMissingPrerequisites(context)
            if (missingPrerequisites.isNotEmpty()) {
                PluginErrorHelper.missingPermission(
                    result = result,
                    feature = FEATURE,
                    action = MethodNames.ADD_RESTRICTED_APP,
                    message = "Restriction prerequisites are not satisfied",
                    missing = missingPrerequisites,
                    status = mapOf(
                        ANDROID_ACCESSIBILITY_KEY to PermissionHandler(context)
                            .checkPermission(PermissionHandler.ACCESSIBILITY_KEY),
                    ),
                )
                return
            }

            val added = RestrictionManager.getInstance(context).addRestrictedApp(identifier)
            result.success(added)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.ADD_RESTRICTED_APP,
                message = "Failed to add restricted app: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleRemoveRestriction(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.REMOVE_RESTRICTION,
                message = "Application context is not available",
            )
            return
        }

        val identifier = call.argument<String>("identifier")
        if (identifier == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.REMOVE_RESTRICTION,
                message = "Missing or invalid 'identifier' argument",
            )
            return
        }

        try {
            val removed = RestrictionManager.getInstance(context).removeRestriction(identifier)
            result.success(removed)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.REMOVE_RESTRICTION,
                message = "Failed to remove restriction: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleRemoveAllRestrictions(result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.REMOVE_ALL_RESTRICTIONS,
                message = "Application context is not available",
            )
            return
        }

        try {
            RestrictionManager.getInstance(context).removeAllRestrictions()
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.REMOVE_ALL_RESTRICTIONS,
                message = "Failed to remove all restrictions: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleGetRestrictedApps(result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.GET_RESTRICTED_APPS,
                message = "Application context is not available",
            )
            return
        }

        try {
            val apps = RestrictionManager.getInstance(context).getRestrictedApps()
            result.success(apps)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.GET_RESTRICTED_APPS,
                message = "Failed to get restricted apps: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleIsRestricted(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.IS_RESTRICTED,
                message = "Application context is not available",
            )
            return
        }

        val identifier = call.argument<String>("identifier")
        if (identifier == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.IS_RESTRICTED,
                message = "Missing or invalid 'identifier' argument",
            )
            return
        }

        try {
            val isRestricted = RestrictionManager.getInstance(context).isRestricted(identifier)
            result.success(isRestricted)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.IS_RESTRICTED,
                message = "Failed to check if app is restricted: ${e.message}",
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
            val restrictionManager = RestrictionManager.getInstance(context)
            val restrictedApps = restrictionManager.getRestrictedApps()
            val isPausedNow = restrictionManager.isPausedNow()
            val isPrerequisitesMet = areRestrictionPrerequisitesMet(context)
            val shouldEnforceSession = shouldEnforceSessionNow(context, restrictionManager)
            result.success(restrictedApps.isNotEmpty() && !isPausedNow && isPrerequisitesMet && shouldEnforceSession)
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
            val restrictedApps = RestrictionManager.getInstance(context).getRestrictedApps()
            result.success(restrictedApps.isNotEmpty())
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

    private fun handleStartRestrictionSession(result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.START_RESTRICTION_SESSION,
                message = "Application context is not available",
            )
            return
        }

        try {
            RestrictionManager.getInstance(context).setManualEnforcementEnabled(true)
            RestrictionAlarmOrchestrator(context).rescheduleAll()
            applyCurrentEnforcementState(context, trigger = "start_restriction_session")
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.START_RESTRICTION_SESSION,
                message = "Failed to start restriction session: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleEndRestrictionSession(result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.END_RESTRICTION_SESSION,
                message = "Application context is not available",
            )
            return
        }

        try {
            RestrictionManager.getInstance(context).setManualEnforcementEnabled(false)
            RestrictionAlarmOrchestrator(context).rescheduleAll()
            applyCurrentEnforcementState(context, trigger = "end_restriction_session")
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.END_RESTRICTION_SESSION,
                message = "Failed to end restriction session: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleSetRestrictionScheduleConfig(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.SET_RESTRICTION_SCHEDULE_CONFIG,
                message = "Application context is not available",
            )
            return
        }

        val configMap = call.arguments as? Map<*, *>
        if (configMap == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.SET_RESTRICTION_SCHEDULE_CONFIG,
                message = "Missing or invalid schedule configuration payload",
            )
            return
        }

        val enabled = configMap["enabled"] as? Boolean ?: false
        val scheduleMaps = configMap["schedules"] as? List<*>
        if (scheduleMaps == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.SET_RESTRICTION_SCHEDULE_CONFIG,
                message = "Missing or invalid 'schedules' argument",
            )
            return
        }

        val schedules = mutableListOf<RestrictionScheduleEntry>()
        for (rawSchedule in scheduleMaps) {
            val scheduleMap = rawSchedule as? Map<*, *>
            if (scheduleMap == null) {
                PluginErrorHelper.invalidArgument(
                    result = result,
                    feature = FEATURE,
                    action = MethodNames.SET_RESTRICTION_SCHEDULE_CONFIG,
                    message = "Each schedule must be a map",
                )
                return
            }
            val rawDays = scheduleMap["daysOfWeekIso"] as? List<*>
            val startMinutes = (scheduleMap["startMinutes"] as? Number)?.toInt()
            val endMinutes = (scheduleMap["endMinutes"] as? Number)?.toInt()
            if (rawDays == null || startMinutes == null || endMinutes == null) {
                PluginErrorHelper.invalidArgument(
                    result = result,
                    feature = FEATURE,
                    action = MethodNames.SET_RESTRICTION_SCHEDULE_CONFIG,
                    message = "Schedule requires 'daysOfWeekIso', 'startMinutes', and 'endMinutes'",
                )
                return
            }
            val days = rawDays.mapNotNull {
                val value = it as? Number
                value?.toInt()
            }.toSet()
            schedules += RestrictionScheduleEntry(
                daysOfWeekIso = days,
                startMinutes = startMinutes,
                endMinutes = endMinutes,
            )
        }

        val config = RestrictionScheduleConfig(enabled = enabled, schedules = schedules)
        val scheduleCalculator = RestrictionScheduleCalculator()
        val scheduleShapeIsValid =
            scheduleCalculator.isScheduleShapeValid(config) &&
                (!config.enabled || scheduleCalculator.hasAnySchedule(config))
        if (!scheduleShapeIsValid) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.SET_RESTRICTION_SCHEDULE_CONFIG,
                message = "Schedule configuration is invalid or has overlapping windows",
            )
            return
        }

        try {
            RestrictionScheduleStore(context).setConfig(config)
            RestrictionAlarmOrchestrator(context).rescheduleAll()
            applyCurrentEnforcementState(context, trigger = "set_restriction_schedule_config")
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.SET_RESTRICTION_SCHEDULE_CONFIG,
                message = "Failed to save schedule configuration: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleGetRestrictionScheduleConfig(result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.GET_RESTRICTION_SCHEDULE_CONFIG,
                message = "Application context is not available",
            )
            return
        }

        try {
            val config = RestrictionScheduleStore(context).getConfig()
            val schedules = config.schedules.map { schedule ->
                mapOf(
                    "daysOfWeekIso" to schedule.daysOfWeekIso.sorted(),
                    "startMinutes" to schedule.startMinutes,
                    "endMinutes" to schedule.endMinutes,
                )
            }
            result.success(
                mapOf(
                    "enabled" to config.enabled,
                    "schedules" to schedules,
                ),
            )
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.GET_RESTRICTION_SCHEDULE_CONFIG,
                message = "Failed to load schedule configuration: ${e.message}",
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
            val isManuallyEnabled = restrictionManager.isManualEnforcementEnabled()
            val scheduleState = resolveScheduleState(context)
            val restrictedApps = if (isManuallyEnabled) {
                restrictionManager.getRestrictedApps()
            } else {
                scheduleState.blockedAppIds
            }
            val shouldEnforceSession = isManuallyEnabled || scheduleState.isInScheduleNow
            result.success(
                mapOf(
                    "isActiveNow" to (restrictedApps.isNotEmpty() && !isPausedNow && isPrerequisitesMet && shouldEnforceSession),
                    "isPausedNow" to isPausedNow,
                    "isManuallyEnabled" to isManuallyEnabled,
                    "isScheduleEnabled" to scheduleState.isScheduleEnabled,
                    "isInScheduleNow" to scheduleState.isInScheduleNow,
                    "pausedUntilEpochMs" to if (isPausedNow) pausedUntilEpochMs else null,
                    "restrictedApps" to restrictedApps,
                )
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

    private fun shouldEnforceSessionNow(
        context: Context,
        restrictionManager: RestrictionManager = RestrictionManager.getInstance(context),
    ): Boolean {
        val isManualEnabled = restrictionManager.isManualEnforcementEnabled()
        if (isManualEnabled) {
            return true
        }
        return resolveScheduleState(context).isInScheduleNow
    }

    private fun applyCurrentEnforcementState(context: Context, trigger: String) {
        val restrictionManager = RestrictionManager.getInstance(context)
        if (!restrictionManager.isManualEnforcementEnabled()) {
            val scheduleState = resolveScheduleState(context)
            restrictionManager.setRestrictedApps(scheduleState.blockedAppIds)
        }
        val shouldEnforce = shouldEnforceSessionNow(context)
        if (shouldEnforce) {
            AppMonitoringService.getInstance()?.enforceCurrentForegroundNow(trigger = trigger)
            return
        }
        ShieldOverlayManager.getInstanceOrNull()?.hideShield()
    }

    private fun handleUpsertScheduledMode(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.UPSERT_SCHEDULED_MODE,
                message = "Application context is not available",
            )
            return
        }

        val payload = call.arguments as? Map<*, *>
        if (payload == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.UPSERT_SCHEDULED_MODE,
                message = "Missing or invalid scheduled mode payload",
            )
            return
        }

        val modeId = (payload["modeId"] as? String)?.trim().orEmpty()
        val isEnabled = payload["isEnabled"] as? Boolean ?: true
        val scheduleMap = payload["schedule"] as? Map<*, *>
        val blockedAppIdsRaw = payload["blockedAppIds"] as? List<*>
        if (modeId.isEmpty() || scheduleMap == null || blockedAppIdsRaw == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.UPSERT_SCHEDULED_MODE,
                message = "Scheduled mode requires 'modeId', 'schedule', and 'blockedAppIds'",
            )
            return
        }
        val rawDays = scheduleMap["daysOfWeekIso"] as? List<*>
        val startMinutes = (scheduleMap["startMinutes"] as? Number)?.toInt()
        val endMinutes = (scheduleMap["endMinutes"] as? Number)?.toInt()
        if (rawDays == null || startMinutes == null || endMinutes == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.UPSERT_SCHEDULED_MODE,
                message = "Schedule requires 'daysOfWeekIso', 'startMinutes', and 'endMinutes'",
            )
            return
        }
        val days = rawDays.mapNotNull { (it as? Number)?.toInt() }.toSet()
        val blockedAppIds = blockedAppIdsRaw.mapNotNull { (it as? String)?.trim() }.filter { it.isNotEmpty() }.distinct()
        val mode = RestrictionScheduledModeEntry(
            modeId = modeId,
            isEnabled = isEnabled,
            schedule = RestrictionScheduleEntry(
                daysOfWeekIso = days,
                startMinutes = startMinutes,
                endMinutes = endMinutes,
            ),
            blockedAppIds = blockedAppIds,
        )

        val scheduleCalculator = RestrictionScheduleCalculator()
        if (!scheduleCalculator.isScheduleShapeValid(RestrictionScheduleConfig(enabled = true, schedules = listOf(mode.schedule)))) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.UPSERT_SCHEDULED_MODE,
                message = "Scheduled mode payload is invalid",
            )
            return
        }

        try {
            val store = RestrictionScheduledModesStore(context)
            val current = store.getConfig()
            val nextModes = current.scheduledModes.toMutableList()
            val index = nextModes.indexOfFirst { it.modeId == mode.modeId }
            if (index >= 0) {
                nextModes[index] = mode
            } else {
                nextModes += mode
            }
            val shapeIsValid = scheduleCalculator.isScheduleShapeValid(
                RestrictionScheduleConfig(
                    enabled = true,
                    schedules = nextModes.filter { it.isEnabled }.map { it.schedule },
                ),
            )
            if (!shapeIsValid) {
                PluginErrorHelper.invalidArgument(
                    result = result,
                    feature = FEATURE,
                    action = MethodNames.UPSERT_SCHEDULED_MODE,
                    message = "Scheduled mode overlaps with an existing schedule",
                )
                return
            }

            store.upsertMode(mode)
            RestrictionAlarmOrchestrator(context).rescheduleAll()
            applyCurrentEnforcementState(context, trigger = "upsert_scheduled_mode")
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.UPSERT_SCHEDULED_MODE,
                message = "Failed to save scheduled mode: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleRemoveScheduledMode(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.REMOVE_SCHEDULED_MODE,
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
                action = MethodNames.REMOVE_SCHEDULED_MODE,
                message = "Missing or invalid 'modeId' argument",
            )
            return
        }

        try {
            RestrictionScheduledModesStore(context).removeMode(modeId)
            RestrictionAlarmOrchestrator(context).rescheduleAll()
            applyCurrentEnforcementState(context, trigger = "remove_scheduled_mode")
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.REMOVE_SCHEDULED_MODE,
                message = "Failed to remove scheduled mode: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleSetScheduledModesEnabled(call: MethodCall, result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.SET_SCHEDULED_MODES_ENABLED,
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
                action = MethodNames.SET_SCHEDULED_MODES_ENABLED,
                message = "Missing or invalid 'enabled' argument",
            )
            return
        }

        try {
            RestrictionScheduledModesStore(context).setEnabled(enabled)
            RestrictionAlarmOrchestrator(context).rescheduleAll()
            applyCurrentEnforcementState(context, trigger = "set_scheduled_modes_enabled")
            result.success(null)
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.SET_SCHEDULED_MODES_ENABLED,
                message = "Failed to update scheduled modes toggle: ${e.message}",
                error = e,
            )
        }
    }

    private fun handleGetScheduledModesConfig(result: Result) {
        val context = contextProvider()
        if (context == null) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.GET_SCHEDULED_MODES_CONFIG,
                message = "Application context is not available",
            )
            return
        }

        try {
            val config = RestrictionScheduledModesStore(context).getConfig()
            result.success(
                mapOf(
                    "enabled" to config.enabled,
                    "scheduledModes" to config.scheduledModes.map { mode ->
                        mapOf(
                            "modeId" to mode.modeId,
                            "isEnabled" to mode.isEnabled,
                            "schedule" to mapOf(
                                "daysOfWeekIso" to mode.schedule.daysOfWeekIso.sorted(),
                                "startMinutes" to mode.schedule.startMinutes,
                                "endMinutes" to mode.schedule.endMinutes,
                            ),
                            "blockedAppIds" to mode.blockedAppIds,
                        )
                    },
                ),
            )
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = MethodNames.GET_SCHEDULED_MODES_CONFIG,
                message = "Failed to load scheduled modes config: ${e.message}",
                error = e,
            )
        }
    }

    private fun resolveScheduleState(context: Context): ScheduleState {
        val scheduledModesConfig = RestrictionScheduledModesStore(context).getConfig()
        if (scheduledModesConfig.scheduledModes.isNotEmpty()) {
            val resolution = RestrictionScheduledModeResolver.resolveNow(scheduledModesConfig)
            return ScheduleState(
                isScheduleEnabled = scheduledModesConfig.enabled,
                isInScheduleNow = resolution.isInScheduleNow,
                blockedAppIds = resolution.blockedAppIds,
            )
        }
        val scheduleConfig = RestrictionScheduleStore(context).getConfig()
        val isInScheduleNow = RestrictionScheduleCalculator().isInSessionNow(scheduleConfig)
        return ScheduleState(
            isScheduleEnabled = scheduleConfig.enabled,
            isInScheduleNow = isInScheduleNow,
            blockedAppIds = if (isInScheduleNow) RestrictionManager.getInstance(context).getRestrictedApps() else emptyList(),
        )
    }

    private data class ScheduleState(
        val isScheduleEnabled: Boolean,
        val isInScheduleNow: Boolean,
        val blockedAppIds: List<String>,
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
