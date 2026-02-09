import Flutter
import FamilyControls
import Foundation

final class RestrictionsMethodHandler {
    private static let iosFamilyControlsKey = "ios.familyControls"
    private static let featureRestrictions = "restrictions"
    private static let platformIOS = "ios"
    private static let maxReliablePauseDurationMs: Int64 = 24 * 60 * 60 * 1000

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case MethodNames.configureShield:
            handleConfigureShield(call: call, result: result)
        case MethodNames.setRestrictedApps:
            handleSetRestrictedApps(call: call, result: result)
        case MethodNames.addRestrictedApp:
            handleAddRestrictedApp(call: call, result: result)
        case MethodNames.removeRestriction:
            handleRemoveRestriction(call: call, result: result)
        case MethodNames.isRestricted:
            handleIsRestricted(call: call, result: result)
        case MethodNames.removeAllRestrictions:
            handleRemoveAllRestrictions(call: call, result: result)
        case MethodNames.getRestrictedApps:
            handleGetRestrictedApps(call: call, result: result)
        case MethodNames.isRestrictionSessionActiveNow:
            handleIsRestrictionSessionActiveNow(result: result)
        case MethodNames.isRestrictionSessionConfigured:
            handleIsRestrictionSessionConfigured(result: result)
        case MethodNames.pauseEnforcement:
            handlePauseEnforcement(call: call, result: result)
        case MethodNames.resumeEnforcement:
            handleResumeEnforcement(result: result)
        case MethodNames.startRestrictionSession:
            handleStartRestrictionSession(result: result)
        case MethodNames.endRestrictionSession:
            handleEndRestrictionSession(result: result)
        case MethodNames.setRestrictionScheduleConfig:
            handleSetRestrictionScheduleConfig(call: call, result: result)
        case MethodNames.getRestrictionScheduleConfig:
            handleGetRestrictionScheduleConfig(result: result)
        case MethodNames.getRestrictionSession:
            handleGetRestrictionSession(result: result)
        case MethodNames.upsertScheduledMode:
            handleUpsertScheduledMode(call: call, result: result)
        case MethodNames.removeScheduledMode:
            handleRemoveScheduledMode(call: call, result: result)
        case MethodNames.setScheduledModesEnabled:
            handleSetScheduledModesEnabled(call: call, result: result)
        case MethodNames.getScheduledModesConfig:
            handleGetScheduledModesConfig(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleConfigureShield(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard var configuration = call.arguments as? [String: Any] else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.configureShield,
                message: PluginErrorMessage.missingShieldConfiguration
            ))
            return
        }

        let appGroupId = configuration["appGroupId"] as? String
        AppGroupStore.updateGroupIdentifier(appGroupId)
        configuration.removeValue(forKey: "appGroupId")

        if let typedData = configuration["iconBytes"] as? FlutterStandardTypedData {
            configuration["iconBytes"] = typedData.data
        } else if configuration["iconBytes"] is NSNull {
            configuration.removeValue(forKey: "iconBytes")
        }

        switch ShieldConfigurationStore.storeConfiguration(configuration, appGroupId: appGroupId) {
        case .success:
            result(nil)
        case .appGroupUnavailable(let resolvedGroupId):
            var diagnostic = "Unable to access App Group for shield configuration. resolvedAppGroupId=\(resolvedGroupId)"
            if let appGroupId {
                diagnostic += ", appGroupId=\(appGroupId)"
            }
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.configureShield,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: diagnostic
            ))
        }
    }

    private func handleSetRestrictedApps(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.setRestrictedApps,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }
        guard let args = call.arguments as? [String: Any],
              let tokens = args["identifiers"] as? [String] else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.setRestrictedApps,
                message: PluginErrorMessage.missingIdentifiers
            ))
            return
        }
        if !tokens.isEmpty, let preflightError = restrictionPreflightError(action: MethodNames.setRestrictedApps) {
            result(preflightError)
            return
        }
        let decodeResult = ShieldManager.shared.decodeTokens(base64Tokens: tokens)
        if !decodeResult.invalidTokens.isEmpty {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.setRestrictedApps,
                message: PluginErrorMessage.unableToDecodeTokens,
                diagnostic: "invalidTokens=\(decodeResult.invalidTokens)"
            ))
            return
        }

        switch RestrictionStateStore.storeDesiredRestrictedApps(decodeResult.appliedBase64Tokens) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.setRestrictedApps,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        applyDesiredRestrictionsIfNeeded()
        result(decodeResult.appliedBase64Tokens)
    }

    private func handleAddRestrictedApp(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.addRestrictedApp,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }
        guard let args = call.arguments as? [String: Any],
              let token = args["identifier"] as? String else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.addRestrictedApp,
                message: PluginErrorMessage.missingIdentifier
            ))
            return
        }
        if let preflightError = restrictionPreflightError(action: MethodNames.addRestrictedApp) {
            result(preflightError)
            return
        }

        let decodeResult = ShieldManager.shared.decodeTokens(base64Tokens: [token])
        if !decodeResult.invalidTokens.isEmpty {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.addRestrictedApp,
                message: PluginErrorMessage.unableToDecodeToken,
                diagnostic: "invalidTokens=\(decodeResult.invalidTokens)"
            ))
            return
        }

        ensureDesiredRestrictionsInitializedFromManagedStore()
        var desired = RestrictionStateStore.loadDesiredRestrictedApps()
        if desired.contains(token) {
            result(false)
            return
        }
        desired.append(token)

        switch RestrictionStateStore.storeDesiredRestrictedApps(desired) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.addRestrictedApp,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        applyDesiredRestrictionsIfNeeded()
        result(true)
    }

    private func handleRemoveRestriction(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.removeRestriction,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }
        guard let args = call.arguments as? [String: Any],
              let token = args["identifier"] as? String else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.removeRestriction,
                message: PluginErrorMessage.missingIdentifier
            ))
            return
        }

        let decodeResult = ShieldManager.shared.decodeTokens(base64Tokens: [token])
        if !decodeResult.invalidTokens.isEmpty {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.removeRestriction,
                message: PluginErrorMessage.unableToDecodeToken,
                diagnostic: "invalidTokens=\(decodeResult.invalidTokens)"
            ))
            return
        }

        ensureDesiredRestrictionsInitializedFromManagedStore()
        var desired = RestrictionStateStore.loadDesiredRestrictedApps()
        let previousCount = desired.count
        desired.removeAll { $0 == token }
        let changed = desired.count != previousCount

        switch RestrictionStateStore.storeDesiredRestrictedApps(desired) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.removeRestriction,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        applyDesiredRestrictionsIfNeeded()
        result(changed)
    }

    private func handleIsRestricted(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.isRestricted,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }
        guard let args = call.arguments as? [String: Any],
              let token = args["identifier"] as? String else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.isRestricted,
                message: PluginErrorMessage.missingIdentifier
            ))
            return
        }

        let decodeResult = ShieldManager.shared.decodeTokens(base64Tokens: [token])
        if !decodeResult.invalidTokens.isEmpty {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.isRestricted,
                message: PluginErrorMessage.unableToDecodeToken,
                diagnostic: "invalidTokens=\(decodeResult.invalidTokens)"
            ))
            return
        }
        ensureDesiredRestrictionsInitializedFromManagedStore()
        let restricted = RestrictionStateStore.loadDesiredRestrictedApps().contains(token)
        result(restricted)
    }

    private func handleRemoveAllRestrictions(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.removeAllRestrictions,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }

        switch RestrictionStateStore.storeDesiredRestrictedApps([]) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.removeAllRestrictions,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        _ = RestrictionStateStore.storePausedUntilEpochMs(0)
        PauseAutoResumeMonitor.stopMonitoring()
        ShieldManager.shared.clearRestrictions()
        result(nil)
    }

    private func handleGetRestrictedApps(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result([])
            return
        }
        ensureDesiredRestrictionsInitializedFromManagedStore()
        let tokens = RestrictionStateStore.loadDesiredRestrictedApps()
        result(tokens)
    }

    private func handleIsRestrictionSessionActiveNow(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(false)
            return
        }

        ensureDesiredRestrictionsInitializedFromManagedStore()
        applyDesiredRestrictionsIfNeeded()
        let isManuallyEnabled = RestrictionStateStore.loadManualEnforcementEnabled()
        let scheduleState = resolveScheduleState()
        let restrictedApps = isManuallyEnabled ? RestrictionStateStore.loadDesiredRestrictedApps() : scheduleState.blockedAppIds
        let isPausedNow = RestrictionStateStore.loadPausedUntilEpochMs() > 0
        let isPrerequisitesMet = restrictionMissingPrerequisites().isEmpty
        let shouldEnforceSession = isManuallyEnabled || scheduleState.isInScheduleNow
        result(!restrictedApps.isEmpty && !isPausedNow && isPrerequisitesMet && shouldEnforceSession)
    }

    private func handleIsRestrictionSessionConfigured(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(false)
            return
        }

        ensureDesiredRestrictionsInitializedFromManagedStore()
        let restrictedApps = RestrictionStateStore.loadDesiredRestrictedApps()
        result(!restrictedApps.isEmpty)
    }

    private func handlePauseEnforcement(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.pauseEnforcement,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }

        guard let args = call.arguments as? [String: Any],
              let durationValue = args["durationMs"] as? NSNumber else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.pauseEnforcement,
                message: "Missing or invalid 'durationMs' argument"
            ))
            return
        }
        let durationMs = durationValue.int64Value
        if durationMs <= 0 {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.pauseEnforcement,
                message: "Missing or invalid 'durationMs' argument"
            ))
            return
        }
        if durationMs >= Self.maxReliablePauseDurationMs {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.pauseEnforcement,
                message: PluginErrorMessage.pauseTooLong
            ))
            return
        }

        if RestrictionStateStore.loadPausedUntilEpochMs() > 0 {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.pauseEnforcement,
                message: "Restriction enforcement is already paused"
            ))
            return
        }

        let pausedUntilEpochMs = RestrictionStateStore.currentEpochMs() + durationMs
        switch RestrictionStateStore.storePausedUntilEpochMs(pausedUntilEpochMs) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.pauseEnforcement,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        do {
            try PauseAutoResumeMonitor.startMonitoring(untilEpochMs: pausedUntilEpochMs)
        } catch {
            _ = RestrictionStateStore.storePausedUntilEpochMs(0)
            applyDesiredRestrictionsIfNeeded()
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.pauseEnforcement,
                message: PluginErrorMessage.pauseMonitoringStartFailed,
                diagnostic: "activityName=\(PauseAutoResumeMonitor.activityNameRaw), error=\(String(describing: error))"
            ))
            return
        }

        ShieldManager.shared.clearRestrictions()
        result(nil)
    }

    private func handleResumeEnforcement(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.resumeEnforcement,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }

        switch RestrictionStateStore.storePausedUntilEpochMs(0) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.resumeEnforcement,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        PauseAutoResumeMonitor.stopMonitoring()
        applyDesiredRestrictionsIfNeeded()
        result(nil)
    }

    private func handleStartRestrictionSession(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.startRestrictionSession,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }

        switch RestrictionStateStore.storeManualEnforcementEnabled(true) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.startRestrictionSession,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        applyDesiredRestrictionsIfNeeded()
        result(nil)
    }

    private func handleEndRestrictionSession(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.endRestrictionSession,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }

        switch RestrictionStateStore.storeManualEnforcementEnabled(false) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.endRestrictionSession,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        applyDesiredRestrictionsIfNeeded()
        result(nil)
    }

    private func handleSetRestrictionScheduleConfig(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.setRestrictionScheduleConfig,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }
        guard let args = call.arguments as? [String: Any] else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.setRestrictionScheduleConfig,
                message: "Missing or invalid schedule configuration payload"
            ))
            return
        }
        let enabled = args["enabled"] as? Bool ?? false
        guard let rawSchedules = args["schedules"] as? [[String: Any]] else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.setRestrictionScheduleConfig,
                message: "Missing or invalid 'schedules' argument"
            ))
            return
        }
        let schedules = rawSchedules.compactMap(RestrictionSchedule.init(dictionary:))
        if schedules.count != rawSchedules.count {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.setRestrictionScheduleConfig,
                message: "Each schedule must provide valid day/time fields"
            ))
            return
        }
        let scheduleShapeIsValid = RestrictionScheduleEvaluator.isScheduleShapeValid(schedules)
        if !scheduleShapeIsValid || (enabled && !RestrictionScheduleEvaluator.hasAnySchedule(schedules)) {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.setRestrictionScheduleConfig,
                message: "Schedule configuration is invalid or has overlapping windows"
            ))
            return
        }

        switch RestrictionStateStore.storeScheduleEnabled(enabled) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.setRestrictionScheduleConfig,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }
        switch RestrictionStateStore.storeRestrictionSchedules(schedules) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.setRestrictionScheduleConfig,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        do {
            try RestrictionScheduleMonitorOrchestrator.rescheduleMonitors()
        } catch {
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.setRestrictionScheduleConfig,
                message: "Failed to schedule iOS boundary monitors",
                diagnostic: "error=\(String(describing: error))"
            ))
            return
        }

        applyDesiredRestrictionsIfNeeded()
        result(nil)
    }

    private func handleGetRestrictionScheduleConfig(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result([
                "enabled": false,
                "schedules": [[String: Any]](),
            ])
            return
        }
        let schedules = RestrictionStateStore
            .loadRestrictionSchedules()
            .map { $0.toDictionary() }
        result([
            "enabled": RestrictionStateStore.loadScheduleEnabled(),
            "schedules": schedules,
        ])
    }

    private func handleGetRestrictionSession(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result([
                "isActiveNow": false,
                "isPausedNow": false,
                "isManuallyEnabled": true,
                "isScheduleEnabled": false,
                "isInScheduleNow": false,
                "pausedUntilEpochMs": NSNull(),
                "restrictedApps": [String]()
            ])
            return
        }

        ensureDesiredRestrictionsInitializedFromManagedStore()
        applyDesiredRestrictionsIfNeeded()
        let isManuallyEnabled = RestrictionStateStore.loadManualEnforcementEnabled()
        let scheduleState = resolveScheduleState()
        let restrictedApps = isManuallyEnabled ? RestrictionStateStore.loadDesiredRestrictedApps() : scheduleState.blockedAppIds
        let pausedUntilEpochMs = RestrictionStateStore.loadPausedUntilEpochMs()
        let isPausedNow = pausedUntilEpochMs > 0
        let isPrerequisitesMet = restrictionMissingPrerequisites().isEmpty
        let shouldEnforceSession = isManuallyEnabled || scheduleState.isInScheduleNow
        result([
            "isActiveNow": !restrictedApps.isEmpty && !isPausedNow && isPrerequisitesMet && shouldEnforceSession,
            "isPausedNow": isPausedNow,
            "isManuallyEnabled": isManuallyEnabled,
            "isScheduleEnabled": scheduleState.isScheduleEnabled,
            "isInScheduleNow": scheduleState.isInScheduleNow,
            "pausedUntilEpochMs": isPausedNow ? pausedUntilEpochMs : NSNull(),
            "restrictedApps": restrictedApps
        ])
    }

    private func handleUpsertScheduledMode(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.upsertScheduledMode,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }
        guard let args = call.arguments as? [String: Any],
              let mode = RestrictionScheduledMode(dictionary: args) else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.upsertScheduledMode,
                message: "Missing or invalid scheduled mode payload"
            ))
            return
        }

        if !mode.blockedAppIds.isEmpty {
            let decodeResult = ShieldManager.shared.decodeTokens(base64Tokens: mode.blockedAppIds)
            if !decodeResult.invalidTokens.isEmpty {
                result(PluginErrors.invalidArguments(
                    feature: Self.featureRestrictions,
                    action: MethodNames.upsertScheduledMode,
                    message: PluginErrorMessage.unableToDecodeTokens,
                    diagnostic: "invalidTokens=\(decodeResult.invalidTokens)"
                ))
                return
            }
        }

        let existing = RestrictionStateStore.loadScheduledModes()
        var nextModes = existing.filter { $0.modeId != mode.modeId }
        nextModes.append(mode)
        if !RestrictionScheduleEvaluator.isScheduleShapeValid(nextModes.filter(\.isEnabled).map(\.schedule)) {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.upsertScheduledMode,
                message: "Scheduled mode overlaps with an existing schedule"
            ))
            return
        }

        switch RestrictionStateStore.storeScheduledModes(nextModes) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.upsertScheduledMode,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        do {
            try RestrictionScheduleMonitorOrchestrator.rescheduleMonitors()
        } catch {
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.upsertScheduledMode,
                message: "Failed to schedule iOS boundary monitors",
                diagnostic: "error=\(String(describing: error))"
            ))
            return
        }

        applyDesiredRestrictionsIfNeeded()
        result(nil)
    }

    private func handleRemoveScheduledMode(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.removeScheduledMode,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }
        guard let args = call.arguments as? [String: Any],
              let modeIdRaw = args["modeId"] as? String else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.removeScheduledMode,
                message: "Missing or invalid 'modeId' argument"
            ))
            return
        }
        let modeId = modeIdRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if modeId.isEmpty {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.removeScheduledMode,
                message: "Missing or invalid 'modeId' argument"
            ))
            return
        }

        let existing = RestrictionStateStore.loadScheduledModes()
        let nextModes = existing.filter { $0.modeId != modeId }
        switch RestrictionStateStore.storeScheduledModes(nextModes) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.removeScheduledMode,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        do {
            try RestrictionScheduleMonitorOrchestrator.rescheduleMonitors()
        } catch {
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.removeScheduledMode,
                message: "Failed to schedule iOS boundary monitors",
                diagnostic: "error=\(String(describing: error))"
            ))
            return
        }

        applyDesiredRestrictionsIfNeeded()
        result(nil)
    }

    private func handleSetScheduledModesEnabled(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.setScheduledModesEnabled,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }
        guard let args = call.arguments as? [String: Any],
              let enabled = args["enabled"] as? Bool else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.setScheduledModesEnabled,
                message: "Missing or invalid 'enabled' argument"
            ))
            return
        }

        switch RestrictionStateStore.storeScheduledModesEnabled(enabled) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.setScheduledModesEnabled,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        do {
            try RestrictionScheduleMonitorOrchestrator.rescheduleMonitors()
        } catch {
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.setScheduledModesEnabled,
                message: "Failed to schedule iOS boundary monitors",
                diagnostic: "error=\(String(describing: error))"
            ))
            return
        }

        applyDesiredRestrictionsIfNeeded()
        result(nil)
    }

    private func handleGetScheduledModesConfig(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result([
                "enabled": false,
                "scheduledModes": [[String: Any]](),
            ])
            return
        }
        result([
            "enabled": RestrictionStateStore.loadScheduledModesEnabled(),
            "scheduledModes": RestrictionStateStore.loadScheduledModes().map { $0.toDictionary() },
        ])
    }

    @available(iOS 16.0, *)
    private func applyDesiredRestrictionsIfNeeded() {
        ensureDesiredRestrictionsInitializedFromManagedStore()
        guard restrictionMissingPrerequisites().isEmpty else {
            ShieldManager.shared.clearRestrictions()
            return
        }

        let isPausedNow = RestrictionStateStore.loadPausedUntilEpochMs() > 0
        if isPausedNow {
            ShieldManager.shared.clearRestrictions()
            return
        }

        let isManualEnabled = RestrictionStateStore.loadManualEnforcementEnabled()
        let scheduleState = resolveScheduleState()
        let blockedAppIds = isManualEnabled ? RestrictionStateStore.loadDesiredRestrictedApps() : scheduleState.blockedAppIds
        if blockedAppIds.isEmpty {
            ShieldManager.shared.clearRestrictions()
            return
        }

        let shouldEnforceSession = isManualEnabled || scheduleState.isInScheduleNow
        if !shouldEnforceSession {
            ShieldManager.shared.clearRestrictions()
            return
        }

        let decodeResult = ShieldManager.shared.decodeTokens(base64Tokens: blockedAppIds)
        if !decodeResult.invalidTokens.isEmpty {
            ShieldManager.shared.clearRestrictions()
            return
        }
        ShieldManager.shared.setRestrictedApps(decodeResult.tokens)
    }

    @available(iOS 16.0, *)
    private func resolveScheduleState() -> ScheduleState {
        let scheduledModes = RestrictionStateStore.loadScheduledModes()
        if !scheduledModes.isEmpty {
            let config = RestrictionScheduledModesConfig(
                enabled: RestrictionStateStore.loadScheduledModesEnabled(),
                scheduledModes: scheduledModes
            )
            let resolution = RestrictionScheduledModeEvaluator.resolveNow(config: config)
            return ScheduleState(
                isScheduleEnabled: config.enabled,
                isInScheduleNow: resolution.isInScheduleNow,
                blockedAppIds: resolution.blockedAppIds
            )
        }

        let isScheduleEnabled = RestrictionStateStore.loadScheduleEnabled()
        let isInScheduleNow = RestrictionScheduleEvaluator.isInScheduleNow(
            enabled: isScheduleEnabled,
            schedules: RestrictionStateStore.loadRestrictionSchedules()
        )
        return ScheduleState(
            isScheduleEnabled: isScheduleEnabled,
            isInScheduleNow: isInScheduleNow,
            blockedAppIds: isInScheduleNow ? RestrictionStateStore.loadDesiredRestrictedApps() : []
        )
    }

    private struct ScheduleState {
        let isScheduleEnabled: Bool
        let isInScheduleNow: Bool
        let blockedAppIds: [String]
    }

    @available(iOS 16.0, *)
    private func ensureDesiredRestrictionsInitializedFromManagedStore() {
        let desiredRestrictedApps = RestrictionStateStore.loadDesiredRestrictedApps()
        if !desiredRestrictedApps.isEmpty {
            return
        }

        let currentlyApplied = ShieldManager.shared.getRestrictedApps()
        if currentlyApplied.isEmpty {
            return
        }

        _ = RestrictionStateStore.storeDesiredRestrictedApps(currentlyApplied)
    }

    @available(iOS 16.0, *)
    private func restrictionMissingPrerequisites() -> [String] {
        let isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        return isAuthorized ? [] : [Self.iosFamilyControlsKey]
    }

    @available(iOS 16.0, *)
    private func restrictionPreflightError(action: String) -> FlutterError? {
        let authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        if authorizationStatus == .approved {
            return nil
        }

        let details: [String: Any] = [
            "feature": Self.featureRestrictions,
            "action": action,
            "platform": Self.platformIOS,
            "missing": [Self.iosFamilyControlsKey],
            "status": [
                "iosAuthorizationStatus": iosAuthorizationStatusKey(authorizationStatus)
            ],
        ]

        switch authorizationStatus {
        case .notDetermined:
            return PluginErrors.missingPermission(
                feature: Self.featureRestrictions,
                action: action,
                message: "Screen Time authorization is required for restrictions",
                missing: details["missing"] as? [String],
                status: details["status"] as? [String: Any]
            )
        case .denied:
            return PluginErrors.permissionDenied(
                feature: Self.featureRestrictions,
                action: action,
                message: "Screen Time authorization was denied",
                missing: details["missing"] as? [String],
                status: details["status"] as? [String: Any]
            )
        @unknown default:
            return PluginErrors.systemRestricted(
                feature: Self.featureRestrictions,
                action: action,
                message: "Screen Time authorization is unavailable",
                missing: details["missing"] as? [String],
                status: details["status"] as? [String: Any]
            )
        }
    }

    @available(iOS 16.0, *)
    private func iosAuthorizationStatusKey(_ status: AuthorizationStatus) -> String {
        switch status {
        case .approved:
            return "approved"
        case .denied:
            return "denied"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }
}
