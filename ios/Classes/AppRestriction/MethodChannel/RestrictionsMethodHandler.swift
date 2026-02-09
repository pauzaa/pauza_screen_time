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
        case MethodNames.upsertMode:
            handleUpsertMode(call: call, result: result)
        case MethodNames.removeMode:
            handleRemoveMode(call: call, result: result)
        case MethodNames.setModesEnabled:
            handleSetModesEnabled(call: call, result: result)
        case MethodNames.getModesConfig:
            handleGetModesConfig(result: result)
        case MethodNames.isRestrictionSessionActiveNow:
            handleIsRestrictionSessionActiveNow(result: result)
        case MethodNames.isRestrictionSessionConfigured:
            handleIsRestrictionSessionConfigured(result: result)
        case MethodNames.pauseEnforcement:
            handlePauseEnforcement(call: call, result: result)
        case MethodNames.resumeEnforcement:
            handleResumeEnforcement(result: result)
        case MethodNames.startModeSession:
            handleStartModeSession(call: call, result: result)
        case MethodNames.endModeSession:
            handleEndModeSession(result: result)
        case MethodNames.getRestrictionSession:
            handleGetRestrictionSession(result: result)
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

    private func handleIsRestrictionSessionActiveNow(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(false)
            return
        }

        applyDesiredRestrictionsIfNeeded()
        let state = resolveSessionState()
        let isPausedNow = RestrictionStateStore.loadPausedUntilEpochMs() > 0
        let isPrerequisitesMet = restrictionMissingPrerequisites().isEmpty
        let shouldEnforceSession = state.activeModeSource != "none"
        result(!state.blockedAppIds.isEmpty && !isPausedNow && isPrerequisitesMet && shouldEnforceSession)
    }

    private func handleIsRestrictionSessionConfigured(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(false)
            return
        }

        let hasConfig = RestrictionStateStore.loadModes().contains { !$0.blockedAppIds.isEmpty }
        result(hasConfig)
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

    private func handleStartModeSession(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.startModeSession,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }
        guard let args = call.arguments as? [String: Any],
              let modeIdRaw = args["modeId"] as? String else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.startModeSession,
                message: "Missing or invalid 'modeId' argument"
            ))
            return
        }
        let modeId = modeIdRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if modeId.isEmpty {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.startModeSession,
                message: "Missing or invalid 'modeId' argument"
            ))
            return
        }

        let mode = RestrictionStateStore.loadModes().first { $0.modeId == modeId }
        guard let mode, mode.isEnabled else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.startModeSession,
                message: "Mode must exist and be enabled to start manual session"
            ))
            return
        }

        switch RestrictionStateStore.storeManualActiveModeId(mode.modeId) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.startModeSession,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        applyDesiredRestrictionsIfNeeded()
        result(nil)
    }

    private func handleEndModeSession(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.endModeSession,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }

        switch RestrictionStateStore.storeManualActiveModeId(nil) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.endModeSession,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        applyDesiredRestrictionsIfNeeded()
        result(nil)
    }

    private func handleGetRestrictionSession(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result([
                "isActiveNow": false,
                "isPausedNow": false,
                "isManuallyEnabled": false,
                "isScheduleEnabled": false,
                "isInScheduleNow": false,
                "pausedUntilEpochMs": NSNull(),
                "restrictedApps": [String](),
                "activeModeId": NSNull(),
                "activeModeSource": "none",
            ])
            return
        }

        applyDesiredRestrictionsIfNeeded()
        let state = resolveSessionState()
        let pausedUntilEpochMs = RestrictionStateStore.loadPausedUntilEpochMs()
        let isPausedNow = pausedUntilEpochMs > 0
        let isPrerequisitesMet = restrictionMissingPrerequisites().isEmpty
        let shouldEnforceSession = state.activeModeSource != "none"
        result([
            "isActiveNow": !state.blockedAppIds.isEmpty && !isPausedNow && isPrerequisitesMet && shouldEnforceSession,
            "isPausedNow": isPausedNow,
            "isManuallyEnabled": state.isManuallyEnabled,
            "isScheduleEnabled": state.isScheduleEnabled,
            "isInScheduleNow": state.isInScheduleNow,
            "pausedUntilEpochMs": isPausedNow ? pausedUntilEpochMs : NSNull(),
            "restrictedApps": state.blockedAppIds,
            "activeModeId": state.activeModeId ?? NSNull(),
            "activeModeSource": state.activeModeSource,
        ])
    }

    private func handleUpsertMode(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.upsertMode,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }
        guard let args = call.arguments as? [String: Any],
              let mode = RestrictionScheduledMode(dictionary: args) else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.upsertMode,
                message: "Missing or invalid mode payload"
            ))
            return
        }

        if !mode.blockedAppIds.isEmpty {
            let decodeResult = ShieldManager.shared.decodeTokens(base64Tokens: mode.blockedAppIds)
            if !decodeResult.invalidTokens.isEmpty {
                result(PluginErrors.invalidArguments(
                    feature: Self.featureRestrictions,
                    action: MethodNames.upsertMode,
                    message: PluginErrorMessage.unableToDecodeTokens,
                    diagnostic: "invalidTokens=\(decodeResult.invalidTokens)"
                ))
                return
            }
        }

        let existing = RestrictionStateStore.loadModes()
        var nextModes = existing.filter { $0.modeId != mode.modeId }
        nextModes.append(mode)
        let schedules = nextModes.filter(\.isEnabled).compactMap(\.schedule)
        if !RestrictionScheduleEvaluator.isScheduleShapeValid(schedules) {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.upsertMode,
                message: "Mode schedule overlaps with an existing schedule"
            ))
            return
        }

        switch RestrictionStateStore.storeModes(nextModes) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.upsertMode,
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
                action: MethodNames.upsertMode,
                message: "Failed to schedule iOS boundary monitors",
                diagnostic: "error=\(String(describing: error))"
            ))
            return
        }

        applyDesiredRestrictionsIfNeeded()
        result(nil)
    }

    private func handleRemoveMode(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.removeMode,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }
        guard let args = call.arguments as? [String: Any],
              let modeIdRaw = args["modeId"] as? String else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.removeMode,
                message: "Missing or invalid 'modeId' argument"
            ))
            return
        }
        let modeId = modeIdRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if modeId.isEmpty {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.removeMode,
                message: "Missing or invalid 'modeId' argument"
            ))
            return
        }

        let existing = RestrictionStateStore.loadModes()
        let nextModes = existing.filter { $0.modeId != modeId }
        switch RestrictionStateStore.storeModes(nextModes) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.removeMode,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        if RestrictionStateStore.loadManualActiveModeId() == modeId {
            _ = RestrictionStateStore.storeManualActiveModeId(nil)
        }

        do {
            try RestrictionScheduleMonitorOrchestrator.rescheduleMonitors()
        } catch {
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.removeMode,
                message: "Failed to schedule iOS boundary monitors",
                diagnostic: "error=\(String(describing: error))"
            ))
            return
        }

        applyDesiredRestrictionsIfNeeded()
        result(nil)
    }

    private func handleSetModesEnabled(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.setModesEnabled,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }
        guard let args = call.arguments as? [String: Any],
              let enabled = args["enabled"] as? Bool else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.setModesEnabled,
                message: "Missing or invalid 'enabled' argument"
            ))
            return
        }

        switch RestrictionStateStore.storeModesEnabled(enabled) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.setModesEnabled,
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
                action: MethodNames.setModesEnabled,
                message: "Failed to schedule iOS boundary monitors",
                diagnostic: "error=\(String(describing: error))"
            ))
            return
        }

        applyDesiredRestrictionsIfNeeded()
        result(nil)
    }

    private func handleGetModesConfig(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result([
                "enabled": false,
                "modes": [[String: Any]](),
            ])
            return
        }
        result([
            "enabled": RestrictionStateStore.loadModesEnabled(),
            "modes": RestrictionStateStore.loadModes().map { $0.toDictionary() },
        ])
    }

    @available(iOS 16.0, *)
    private func applyDesiredRestrictionsIfNeeded() {
        guard restrictionMissingPrerequisites().isEmpty else {
            ShieldManager.shared.clearRestrictions()
            return
        }

        let isPausedNow = RestrictionStateStore.loadPausedUntilEpochMs() > 0
        if isPausedNow {
            ShieldManager.shared.clearRestrictions()
            return
        }

        let state = resolveSessionState()
        if state.activeModeSource == "none" || state.blockedAppIds.isEmpty {
            ShieldManager.shared.clearRestrictions()
            return
        }

        let decodeResult = ShieldManager.shared.decodeTokens(base64Tokens: state.blockedAppIds)
        if !decodeResult.invalidTokens.isEmpty {
            ShieldManager.shared.clearRestrictions()
            return
        }
        ShieldManager.shared.setRestrictedApps(decodeResult.tokens)
    }

    @available(iOS 16.0, *)
    private func resolveSessionState() -> SessionState {
        let modes = RestrictionStateStore.loadModes()
        let modesEnabled = RestrictionStateStore.loadModesEnabled()
        let manualModeId = RestrictionStateStore.loadManualActiveModeId()
        let manualMode = modes.first { $0.modeId == manualModeId && $0.isEnabled }

        let config = RestrictionScheduledModesConfig(
            enabled: modesEnabled,
            modes: modes
        )
        let resolution = RestrictionScheduledModeEvaluator.resolveNow(config: config)

        if let manualMode {
            return SessionState(
                isManuallyEnabled: true,
                isScheduleEnabled: modesEnabled,
                isInScheduleNow: resolution.isInScheduleNow,
                blockedAppIds: manualMode.blockedAppIds,
                activeModeId: manualMode.modeId,
                activeModeSource: "manual"
            )
        }

        if resolution.isInScheduleNow {
            return SessionState(
                isManuallyEnabled: manualModeId != nil,
                isScheduleEnabled: modesEnabled,
                isInScheduleNow: true,
                blockedAppIds: resolution.blockedAppIds,
                activeModeId: resolution.activeModeId,
                activeModeSource: "schedule"
            )
        }

        return SessionState(
            isManuallyEnabled: manualModeId != nil,
            isScheduleEnabled: modesEnabled,
            isInScheduleNow: false,
            blockedAppIds: [],
            activeModeId: nil,
            activeModeSource: "none"
        )
    }

    private struct SessionState {
        let isManuallyEnabled: Bool
        let isScheduleEnabled: Bool
        let isInScheduleNow: Bool
        let blockedAppIds: [String]
        let activeModeId: String?
        let activeModeSource: String
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
