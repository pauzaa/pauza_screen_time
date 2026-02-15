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

        let payload = ShieldConfigurationStoragePayload.fromChannelMap(configuration)
        switch ShieldConfigurationStore.storeConfiguration(payload, appGroupId: appGroupId) {
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

        applyDesiredRestrictionsIfNeeded(trigger: "is_restriction_session_active_now")
        let state = resolveSessionState()
        let isPausedNow = RestrictionStateStore.loadPausedUntilEpochMs() > 0
        let isPrerequisitesMet = restrictionMissingPrerequisites().isEmpty
        let shouldEnforceSession = state.activeModeSource != .none
        result(!state.blockedAppIds.isEmpty && !isPausedNow && isPrerequisitesMet && shouldEnforceSession)
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

        let previousSnapshot = RestrictionStateStore.snapshotLifecycleState()
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
            applyDesiredRestrictionsIfNeeded(trigger: "pause_enforcement_rollback")
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.pauseEnforcement,
                message: PluginErrorMessage.pauseMonitoringStartFailed,
                diagnostic: "activityName=\(PauseAutoResumeMonitor.activityNameRaw), error=\(String(describing: error))"
            ))
            return
        }

        ShieldManager.shared.clearRestrictions()
        applyDesiredRestrictionsIfNeeded(
            trigger: "pause_enforcement",
            previousLifecycleSnapshot: previousSnapshot
        )
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
        if let preflightError = restrictionPreflightError(action: MethodNames.resumeEnforcement) {
            result(preflightError)
            return
        }

        let previousSnapshot = RestrictionStateStore.snapshotLifecycleState()
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
        applyDesiredRestrictionsIfNeeded(
            trigger: "resume_enforcement",
            previousLifecycleSnapshot: previousSnapshot
        )
        result(nil)
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
            guard let raw = value as? String else {
                return nil
            }
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

        let decodeResult = ShieldManager.shared.decodeTokens(base64Tokens: blockedAppIds)
        if !decodeResult.invalidTokens.isEmpty {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.startSession,
                message: PluginErrorMessage.unableToDecodeTokens,
                diagnostic: "invalidTokens=\(decodeResult.invalidTokens)"
            ))
            return
        }

        let previousSnapshot = RestrictionStateStore.snapshotLifecycleState()
        switch RestrictionStateStore.storeActiveSession(
            RestrictionStateStore.ActiveSession(
                sessionId: "",
                modeId: modeId,
                blockedAppIds: blockedAppIds,
                source: .manual
            )
        ) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.startSession,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
            return
        }

        applyDesiredRestrictionsIfNeeded(
            trigger: "start_session_manual",
            previousLifecycleSnapshot: previousSnapshot
        )
        result(nil)
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

        let previousSnapshot = RestrictionStateStore.snapshotLifecycleState()
        switch endSession(for: .manual) {
        case .success:
            applyDesiredRestrictionsIfNeeded(
                trigger: "end_session_manual",
                previousLifecycleSnapshot: previousSnapshot
            )
            result(nil)
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.endSession,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
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
        let events = RestrictionStateStore.loadPendingLifecycleEvents(limit: limit)
        result(events.map { $0.toChannelMap() })
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

        switch RestrictionStateStore.ackLifecycleEvents(throughEventId: throughEventId) {
        case .success:
            result(nil)
        case .appGroupUnavailable(let resolvedGroupId):
            result(PluginErrors.internalFailure(
                feature: Self.featureRestrictions,
                action: MethodNames.ackLifecycleEvents,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            ))
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

        applyDesiredRestrictionsIfNeeded(trigger: "get_restriction_session")
        let state = resolveSessionState()
        let pausedUntilEpochMs = RestrictionStateStore.loadPausedUntilEpochMs()
        let isPausedNow = pausedUntilEpochMs > 0
        let activeSessionId = RestrictionStateStore.loadActiveSession()?.sessionId
        let currentSessionEvents: [RestrictionLifecycleEvent]
        if let activeSessionId, !activeSessionId.isEmpty {
            currentSessionEvents = RestrictionStateStore
                .loadPendingLifecycleEvents(limit: Int.max)
                .filter { $0.sessionId == activeSessionId }
        } else {
            currentSessionEvents = []
        }
        let payload = RestrictionSessionSnapshot(
            isScheduleEnabled: state.isScheduleEnabled,
            isInScheduleNow: state.isInScheduleNow,
            pausedUntilEpochMs: isPausedNow ? pausedUntilEpochMs : nil,
            activeMode: state.activeModeId.map { activeModeId in
                RestrictionScheduledMode(
                    modeId: activeModeId,
                    schedule: nil,
                    blockedAppIds: state.blockedAppIds
                )
            },
            activeModeSource: state.activeModeSource,
            currentSessionEvents: currentSessionEvents
        )
        result(payload.toChannelMap())
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
        let previousSnapshot = RestrictionStateStore.snapshotLifecycleState()
        var nextModes = existing.filter { $0.modeId != mode.modeId }
        if mode.shouldPersistForScheduleEnforcement {
            nextModes.append(mode)
        }
        let schedules = nextModes.compactMap(\.schedule)
        if !RestrictionScheduleEvaluator.isScheduleShapeValid(schedules) {
            result(PluginErrors.invalidArguments(
                feature: Self.featureRestrictions,
                action: MethodNames.upsertMode,
                message: "Mode schedule overlaps with an existing schedule"
            ))
            return
        }

        let shouldRescheduleMonitors = scheduleModesSignature(existing) != scheduleModesSignature(nextModes)
        if shouldRescheduleMonitors {
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
        }

        if let activeSession = RestrictionStateStore.loadActiveSession(),
           activeSession.modeId == mode.modeId {
            let storeResult: RestrictionStateStore.StoreResult
            if mode.isStartable {
                storeResult = RestrictionStateStore.storeActiveSession(
                    RestrictionStateStore.ActiveSession(
                        sessionId: activeSession.sessionId,
                        modeId: mode.modeId,
                        blockedAppIds: mode.blockedAppIds,
                        source: activeSession.source
                    )
                )
            } else {
                storeResult = RestrictionStateStore.clearActiveSession()
            }
            if case .appGroupUnavailable(let resolvedGroupId) = storeResult {
                result(PluginErrors.internalFailure(
                    feature: Self.featureRestrictions,
                    action: MethodNames.upsertMode,
                    message: PluginErrorMessage.appGroupUnavailable,
                    diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
                ))
                return
            }
        }

        applyDesiredRestrictionsIfNeeded(
            trigger: "upsert_mode",
            previousLifecycleSnapshot: previousSnapshot
        )
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
        let previousSnapshot = RestrictionStateStore.snapshotLifecycleState()
        let nextModes = existing.filter { $0.modeId != modeId }
        let shouldRescheduleMonitors = scheduleModesSignature(existing) != scheduleModesSignature(nextModes)
        if shouldRescheduleMonitors {
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
        }

        if RestrictionStateStore.loadActiveSession()?.modeId == modeId {
            switch RestrictionStateStore.clearActiveSession() {
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
        }

        if shouldRescheduleMonitors {
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
        }

        applyDesiredRestrictionsIfNeeded(
            trigger: "remove_mode",
            previousLifecycleSnapshot: previousSnapshot
        )
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

        let previousSnapshot = RestrictionStateStore.snapshotLifecycleState()
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

        applyDesiredRestrictionsIfNeeded(
            trigger: "set_modes_enabled",
            previousLifecycleSnapshot: previousSnapshot
        )
        result(nil)
    }

    private func handleGetModesConfig(result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            result(RestrictionScheduledModesConfig(enabled: false, modes: []).toChannelMap())
            return
        }
        let config = RestrictionScheduledModesConfig(
            enabled: RestrictionStateStore.loadModesEnabled(),
            modes: RestrictionStateStore.loadModes()
        )
        result(config.toChannelMap())
    }

    @available(iOS 16.0, *)
    private func applyDesiredRestrictionsIfNeeded(
        trigger: String,
        previousLifecycleSnapshot: RestrictionLifecycleSnapshot? = nil
    ) {
        let previousSnapshot = previousLifecycleSnapshot ?? RestrictionStateStore.snapshotLifecycleState()
        defer {
            _ = RestrictionStateStore.appendLifecycleTransition(
                previous: previousSnapshot,
                next: RestrictionStateStore.snapshotLifecycleState(),
                reason: trigger
            )
        }

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
        if state.activeModeSource == .none || state.blockedAppIds.isEmpty {
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

        let config = RestrictionScheduledModesConfig(
            enabled: modesEnabled,
            modes: modes
        )
        let resolution = RestrictionScheduledModeEvaluator.resolveNow(config: config)
        let activeSession = RestrictionStateStore.loadActiveSession()

        if let activeSession {
            if activeSession.source == .manual {
                return SessionState(
                    isScheduleEnabled: modesEnabled,
                    isInScheduleNow: resolution.isInScheduleNow,
                    blockedAppIds: activeSession.blockedAppIds,
                    activeModeId: activeSession.modeId,
                    activeModeSource: .manual
                )
            }

            if resolution.isInScheduleNow, activeSession.modeId == resolution.activeModeId {
                return SessionState(
                    isScheduleEnabled: modesEnabled,
                    isInScheduleNow: true,
                    blockedAppIds: activeSession.blockedAppIds,
                    activeModeId: activeSession.modeId,
                    activeModeSource: .schedule
                )
            }

            _ = RestrictionStateStore.clearActiveSession()
        }

        if resolution.isInScheduleNow,
           let activeModeId = resolution.activeModeId,
           !resolution.blockedAppIds.isEmpty {
            _ = RestrictionStateStore.storeActiveSession(
                RestrictionStateStore.ActiveSession(
                    sessionId: "",
                    modeId: activeModeId,
                    blockedAppIds: resolution.blockedAppIds,
                    source: .schedule
                )
            )
            return SessionState(
                isScheduleEnabled: modesEnabled,
                isInScheduleNow: true,
                blockedAppIds: resolution.blockedAppIds,
                activeModeId: activeModeId,
                activeModeSource: .schedule
            )
        }

        return SessionState(
            isScheduleEnabled: modesEnabled,
            isInScheduleNow: false,
            blockedAppIds: [],
            activeModeId: nil,
            activeModeSource: .none
        )
    }

    @available(iOS 16.0, *)
    private func endSession(for source: RestrictionModeSource) -> RestrictionStateStore.StoreResult {
        guard let activeSession = RestrictionStateStore.loadActiveSession() else {
            return .success
        }
        if source == .schedule && activeSession.source != .schedule {
            return .success
        }
        return RestrictionStateStore.clearActiveSession()
    }

    private struct SessionState {
        let isScheduleEnabled: Bool
        let isInScheduleNow: Bool
        let blockedAppIds: [String]
        let activeModeId: String?
        let activeModeSource: RestrictionModeSource
    }

    private func scheduleModesSignature(_ modes: [RestrictionScheduledMode]) -> String {
        let sorted = modes
            .filter(\.shouldPersistForScheduleEnforcement)
            .sorted { $0.modeId < $1.modeId }
            .map { $0.toChannelMap() }
        guard let data = try? JSONSerialization.data(withJSONObject: sorted, options: [.sortedKeys]),
              let encoded = String(data: data, encoding: .utf8) else {
            return ""
        }
        return encoded
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
