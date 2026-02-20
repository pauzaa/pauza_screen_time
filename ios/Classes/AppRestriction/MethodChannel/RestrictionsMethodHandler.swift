import Flutter
import FamilyControls
import Foundation

final class RestrictionsMethodHandler {
    private static let iosFamilyControlsKey = "ios.familyControls"
    private static let featureRestrictions = "restrictions"
    private static let platformIOS = "ios"
    private static let maxReliablePauseDurationMs: Int64 = 24 * 60 * 60 * 1000
    private let lifecycleQueue = DispatchQueue(label: "pauza.restrictions.lifecycle.queue")

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
        case MethodNames.pauseEnforcement:
            handlePauseEnforcement(call: call, result: result)
        case MethodNames.resumeEnforcement:
            handleResumeEnforcement(result: result)
        case MethodNames.startSession:
            handleStartSession(call: call, result: result)
        case MethodNames.endSession:
            handleEndSession(result: result)
        case MethodNames.getPendingLifecycleEvents:
            handleGetPendingLifecycleEvents(call: call, result: result)
        case MethodNames.ackLifecycleEvents:
            handleAckLifecycleEvents(call: call, result: result)
        case MethodNames.getRestrictionSession:
            handleGetRestrictionSession(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleConfigureShield(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let configuration = call.arguments as? [String: Any] else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.configureShield,
                message: PluginErrorMessage.missingShieldConfiguration
            ))
            return
        }
        if let error = ConfigureShieldUseCase.execute(configuration: configuration) {
            result(error)
        } else {
            result(nil)
        }
    }

    private func handleIsRestrictionSessionActiveNow(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(false)
            return
        }
        let isPrerequisitesMet = restrictionMissingPrerequisites().isEmpty
        let isActive = SessionEnforcementUseCase.isRestrictionSessionActiveNow(isPrerequisitesMet: isPrerequisitesMet)
        result(isActive)
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
        if let preflightError = restrictionPreflightError(action: MethodNames.pauseEnforcement) {
            result(preflightError)
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
        if let error = SessionEnforcementUseCase.pauseEnforcement(durationMs: durationMs) {
            result(error)
        } else {
            result(nil)
        }
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
        if let preflightError = restrictionPreflightError(action: MethodNames.resumeEnforcement) {
            result(preflightError)
            return
        }
        if let error = SessionEnforcementUseCase.resumeEnforcement() {
            result(error)
        } else {
            result(nil)
        }
    }

    private func handleStartSession(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.startSession,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }
        if let preflightError = restrictionPreflightError(action: MethodNames.startSession) {
            result(preflightError)
            return
        }
        guard let args = call.arguments as? [String: Any] else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.startSession,
                message: "Missing or invalid mode payload"
            ))
            return
        }

        let modeId = (args["modeId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let blockedAppIdsRaw = args["blockedAppIds"] as? [Any] ?? []
        let blockedAppIds = blockedAppIdsRaw.compactMap { value -> String? in
            guard let raw = value as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if modeId.isEmpty || blockedAppIds.isEmpty {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.startSession,
                message: "Mode requires non-empty 'modeId' and 'blockedAppIds'"
            ))
            return
        }
        if let error = SessionEnforcementUseCase.startSession(modeId: modeId, blockedAppIds: blockedAppIds) {
            result(error)
        } else {
            result(nil)
        }
    }

    private func handleEndSession(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(PluginErrors.unsupported(
                feature: Self.featureRestrictions,
                action: MethodNames.endSession,
                message: PluginErrorMessage.restrictionsUnsupported
            ))
            return
        }
        if let error = SessionEnforcementUseCase.endSession() {
            result(error)
        } else {
            result(nil)
        }
    }

    private func handleGetPendingLifecycleEvents(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result([])
            return
        }
        let args = call.arguments as? [String: Any]
        let limit = (args?["limit"] as? NSNumber)?.intValue ?? 200
        if limit <= 0 {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.getPendingLifecycleEvents,
                message: "Missing or invalid 'limit' argument"
            ))
            return
        }
        lifecycleQueue.async {
            let events = RestrictionStateStore.loadPendingLifecycleEvents(limit: limit)
            DispatchQueue.main.async {
                result(events.map { $0.toChannelMap() })
            }
        }
    }

    private func handleAckLifecycleEvents(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(nil)
            return
        }
        guard let args = call.arguments as? [String: Any],
              let throughEventIdRaw = args["throughEventId"] as? String else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.ackLifecycleEvents,
                message: "Missing or invalid 'throughEventId' argument"
            ))
            return
        }
        let throughEventId = throughEventIdRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if throughEventId.isEmpty {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.ackLifecycleEvents,
                message: "Missing or invalid 'throughEventId' argument"
            ))
            return
        }
        lifecycleQueue.async {
            let error = LifecycleEventsUseCase.ackLifecycleEvents(throughEventId: throughEventId)
            DispatchQueue.main.async {
                if let error {
                    result(error)
                } else {
                    result(nil)
                }
            }
        }
    }

    private func handleGetRestrictionSession(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(RestrictionSessionSnapshot(
                isScheduleEnabled: false,
                isInScheduleNow: false,
                pausedUntilEpochMs: nil,
                activeMode: nil,
                activeModeSource: .none,
                currentSessionEvents: []
            ).toChannelMap())
            return
        }
        let session = SessionEnforcementUseCase.getRestrictionSession()
        result(session.toChannelMap())
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
        if let preflightError = restrictionPreflightError(action: MethodNames.upsertMode) {
            result(preflightError)
            return
        }
        guard let args = call.arguments as? [String: Any],
              let mode = RestrictionScheduledMode(channelMap: args) else {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.upsertMode,
                message: "Missing or invalid mode payload"
            ))
            return
        }
        if let error = ManageModesUseCase.upsertMode(mode: mode) {
            result(error)
        } else {
            result(nil)
        }
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
        if let error = ManageModesUseCase.removeMode(modeId: modeId) {
            result(error)
        } else {
            result(nil)
        }
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
        if let preflightError = restrictionPreflightError(action: MethodNames.setModesEnabled) {
            result(preflightError)
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
        if let error = ManageModesUseCase.setModesEnabled(enabled: enabled) {
            result(error)
        } else {
            result(nil)
        }
    }

    private func handleGetModesConfig(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(RestrictionScheduledModesConfig(enabled: false, modes: []).toChannelMap())
            return
        }
        let config = ManageModesUseCase.getModesConfig()
        result(config.toChannelMap())
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
        case .approved: return "approved"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }
}
