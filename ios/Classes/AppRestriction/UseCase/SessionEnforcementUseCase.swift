import Foundation
import FamilyControls
import Flutter

@available(iOS 16.0, *)
struct SessionState {
    let isScheduleEnabled: Bool
    let isInScheduleNow: Bool
    let blockedAppIds: [String]
    let activeModeId: String?
    let activeModeSource: RestrictionModeSource
    let activeScheduleBoundaryEndEpochMs: Int64?
}

@available(iOS 16.0, *)
struct SessionEnforcementUseCase {
    static let featureRestrictions = "restrictions"

    static func isRestrictionSessionActiveNow(isPrerequisitesMet: Bool) -> Bool {
        applyDesiredRestrictionsIfNeeded(trigger: LifecycleReasonConstants.manual)
        let state = resolveSessionState()
        let isPausedNow = RestrictionStateStore.loadPausedUntilEpochMs() > 0
        let shouldEnforceSession = state.activeModeSource != .none
        return !state.blockedAppIds.isEmpty && !isPausedNow && isPrerequisitesMet && shouldEnforceSession
    }

    static func pauseEnforcement(durationMs: Int64) -> FlutterError? {
        let state = resolveSessionState()
        if state.activeModeSource == .none {
            return PluginErrors.invalidArguments(
                feature: featureRestrictions,
                action: MethodNames.pauseEnforcement,
                message: "No active restriction session to pause."
            )
        }
        if RestrictionStateStore.loadPausedUntilEpochMs() > 0 {
            return PluginErrors.invalidArguments(
                feature: featureRestrictions,
                action: MethodNames.pauseEnforcement,
                message: "Restriction enforcement is already paused."
            )
        }

        let previousSnapshot = RestrictionStateStore.snapshotLifecycleState()
        let pausedUntilEpochMs = RestrictionStateStore.currentEpochMs() + durationMs
        switch RestrictionStateStore.storePausedUntilEpochMs(pausedUntilEpochMs) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            return PluginErrors.internalFailure(
                feature: featureRestrictions,
                action: MethodNames.pauseEnforcement,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            )
        }

        do {
            try PauseAutoResumeMonitor.startMonitoring(untilEpochMs: pausedUntilEpochMs)
        } catch {
            _ = RestrictionStateStore.storePausedUntilEpochMs(0)
            applyDesiredRestrictionsIfNeeded(trigger: LifecycleReasonConstants.manual)
            return PluginErrors.internalFailure(
                feature: featureRestrictions,
                action: MethodNames.pauseEnforcement,
                message: PluginErrorMessage.pauseMonitoringStartFailed,
                diagnostic: "activityName=\(PauseAutoResumeMonitor.activityNameRaw), error=\(String(describing: error))"
            )
        }

        ShieldManager.shared.clearRestrictions()
        applyDesiredRestrictionsIfNeeded(
            trigger: LifecycleReasonConstants.manual,
            previousLifecycleSnapshot: previousSnapshot
        )
        return nil
    }

    static func resumeEnforcement() -> FlutterError? {
        let state = resolveSessionState()
        if state.activeModeSource == .none {
            return PluginErrors.invalidArguments(
                feature: featureRestrictions,
                action: MethodNames.resumeEnforcement,
                message: "No active restriction session to resume."
            )
        }
        if RestrictionStateStore.loadPausedUntilEpochMs() <= 0 {
            return PluginErrors.invalidArguments(
                feature: featureRestrictions,
                action: MethodNames.resumeEnforcement,
                message: "Restriction enforcement is not paused."
            )
        }

        let previousSnapshot = RestrictionStateStore.snapshotLifecycleState()
        switch RestrictionStateStore.storePausedUntilEpochMs(0) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            return PluginErrors.internalFailure(
                feature: featureRestrictions,
                action: MethodNames.resumeEnforcement,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            )
        }

        PauseAutoResumeMonitor.stopMonitoring()
        applyDesiredRestrictionsIfNeeded(
            trigger: LifecycleReasonConstants.manual,
            previousLifecycleSnapshot: previousSnapshot
        )
        return nil
    }

    static func hasActiveSession() -> Bool {
        return resolveSessionState().activeModeSource != .none
    }

    static func startSession(modeId: String, blockedAppIds: [String], durationMs: Int64? = nil) -> FlutterError? {
        let decodeResult = ShieldManager.shared.decodeTokens(base64Tokens: blockedAppIds)
        if !decodeResult.invalidTokens.isEmpty {
            return PluginErrors.invalidArguments(
                feature: featureRestrictions,
                action: MethodNames.startSession,
                message: PluginErrorMessage.unableToDecodeTokens,
                diagnostic: "invalidTokens=\(decodeResult.invalidTokens)"
            )
        }

        if let durationMs {
            let manualSessionEndEpochMs = RestrictionStateStore.currentEpochMs() + durationMs
            switch RestrictionStateStore.storeManualSessionEndEpochMs(manualSessionEndEpochMs) {
            case .success:
                break
            case .appGroupUnavailable(let resolvedGroupId):
                return PluginErrors.internalFailure(
                    feature: featureRestrictions,
                    action: MethodNames.startSession,
                    message: PluginErrorMessage.appGroupUnavailable,
                    diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
                )
            }
            do {
                try ManualSessionAutoEndMonitor.startMonitoring(untilEpochMs: manualSessionEndEpochMs)
            } catch {
                _ = RestrictionStateStore.storeManualSessionEndEpochMs(0)
                return PluginErrors.internalFailure(
                    feature: featureRestrictions,
                    action: MethodNames.startSession,
                    message: "Failed to start manual session auto-end monitor",
                    diagnostic: "activityName=\(ManualSessionAutoEndMonitor.activityNameRaw), error=\(String(describing: error))"
                )
            }
        } else {
            _ = RestrictionStateStore.storeManualSessionEndEpochMs(0)
            ManualSessionAutoEndMonitor.stopMonitoring()
        }
        _ = RestrictionStateStore.storePendingEndSessionEpochMs(0)
        PendingEndSessionMonitor.stopMonitoring()

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
            return PluginErrors.internalFailure(
                feature: featureRestrictions,
                action: MethodNames.startSession,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            )
        }

        applyDesiredRestrictionsIfNeeded(
            trigger: LifecycleReasonConstants.manual,
            previousLifecycleSnapshot: previousSnapshot
        )
        return nil
    }

    static func endSession(durationMs: Int64? = nil, reason: String? = nil) -> FlutterError? {
        if let durationMs {
            return scheduleEndSession(durationMs: durationMs)
        }
        return endSessionNow(reason: reason)
    }

    private static func scheduleEndSession(durationMs: Int64) -> FlutterError? {
        let state = resolveSessionState()
        guard state.activeModeSource != .none else {
            return PluginErrors.invalidArguments(
                feature: featureRestrictions,
                action: MethodNames.endSession,
                message: "No active restriction session to end"
            )
        }

        let pendingEndSessionEpochMs = RestrictionStateStore.currentEpochMs() + durationMs
        switch RestrictionStateStore.storePendingEndSessionEpochMs(pendingEndSessionEpochMs) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            return PluginErrors.internalFailure(
                feature: featureRestrictions,
                action: MethodNames.endSession,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            )
        }

        do {
            try PendingEndSessionMonitor.startMonitoring(untilEpochMs: pendingEndSessionEpochMs)
        } catch {
            _ = RestrictionStateStore.storePendingEndSessionEpochMs(0)
            return PluginErrors.internalFailure(
                feature: featureRestrictions,
                action: MethodNames.endSession,
                message: "Failed to start delayed end session monitor",
                diagnostic: "activityName=\(PendingEndSessionMonitor.activityNameRaw), error=\(String(describing: error))"
            )
        }
        return nil
    }

    private static func endSessionNow(reason: String? = nil) -> FlutterError? {
        let state = resolveSessionState()
        guard state.activeModeSource != .none, let activeModeId = state.activeModeId else {
            return PluginErrors.invalidArguments(
                feature: featureRestrictions,
                action: MethodNames.endSession,
                message: "No active restriction session to end"
            )
        }
        let previousSnapshot = RestrictionStateStore.snapshotLifecycleState()
        _ = RestrictionStateStore.storeManualSessionEndEpochMs(0)
        _ = RestrictionStateStore.storePendingEndSessionEpochMs(0)
        ManualSessionAutoEndMonitor.stopMonitoring()
        PendingEndSessionMonitor.stopMonitoring()

        if state.activeModeSource == .schedule,
           let suppressionUntilEpochMs = state.activeScheduleBoundaryEndEpochMs,
           suppressionUntilEpochMs > RestrictionStateStore.currentEpochMs() {
            let suppressionStoreResult = RestrictionStateStore.storeScheduleSuppression(
                modeId: activeModeId,
                untilEpochMs: suppressionUntilEpochMs
            )
            if case .appGroupUnavailable(let resolvedGroupId) = suppressionStoreResult {
                return PluginErrors.internalFailure(
                    feature: featureRestrictions,
                    action: MethodNames.endSession,
                    message: PluginErrorMessage.appGroupUnavailable,
                    diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
                )
            }
        }

        let storeResult: RestrictionStateStore.StoreResult
        if (try? RestrictionStateStore.loadActiveSession()) != nil {
            storeResult = RestrictionStateStore.clearActiveSession()
        } else {
            storeResult = .success
        }

        switch storeResult {
        case .success:
            applyDesiredRestrictionsIfNeeded(
                trigger: reason ?? LifecycleReasonConstants.manual,
                previousLifecycleSnapshot: previousSnapshot
            )
            return nil
        case .appGroupUnavailable(let resolvedGroupId):
            return PluginErrors.internalFailure(
                feature: featureRestrictions,
                action: MethodNames.endSession,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            )
        }
    }

    static func getRestrictionSession() -> RestrictionSessionSnapshot {
        applyDesiredRestrictionsIfNeeded(trigger: LifecycleReasonConstants.manual)
        let state = resolveSessionState()
        let pausedUntilEpochMs = RestrictionStateStore.loadPausedUntilEpochMs()
        let isPausedNow = pausedUntilEpochMs > 0
        let activeSessionId = (try? RestrictionStateStore.loadActiveSession())?.sessionId
        let currentSessionEvents: [RestrictionLifecycleEvent]
        if let activeSessionId, !activeSessionId.isEmpty {
            currentSessionEvents = RestrictionStateStore
                .loadActiveSessionLifecycleEvents(limit: Int.max)
        } else {
            currentSessionEvents = []
        }
        let activeMode = state.activeModeId.flatMap { activeModeId in
            RestrictionScheduledMode(channelMap: [
                "modeId": activeModeId,
                "blockedAppIds": state.blockedAppIds,
            ])
        }
        return RestrictionSessionSnapshot(
            isScheduleEnabled: state.isScheduleEnabled,
            isInScheduleNow: state.isInScheduleNow,
            pausedUntilEpochMs: isPausedNow ? pausedUntilEpochMs : nil,
            activeMode: activeMode,
            activeModeSource: state.activeModeSource,
            currentSessionEvents: currentSessionEvents
        )
    }

    static func applyDesiredRestrictionsIfNeeded(
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

        if AuthorizationCenter.shared.authorizationStatus != .approved {
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

    static func resolveSessionState() -> SessionState {
        let modes = RestrictionStateStore.loadModes()
        let modesEnabled = RestrictionStateStore.loadModesEnabled()

        let config = RestrictionScheduledModesConfig(
            enabled: modesEnabled,
            modes: modes
        )
        let resolution = RestrictionScheduledModeEvaluator.resolveNow(config: config)
        let suppression = RestrictionStateStore.loadScheduleSuppression(nowEpochMs: RestrictionStateStore.currentEpochMs())
        let shouldSuppressCurrentMode = suppression != nil &&
            resolution.isInScheduleNow &&
            resolution.activeModeId == suppression?.modeId
        if suppression != nil && !shouldSuppressCurrentMode {
            _ = RestrictionStateStore.clearScheduleSuppression()
        }
        let activeSession = try? RestrictionStateStore.loadActiveSession()
        let manualSessionEndEpochMs = RestrictionStateStore.loadManualSessionEndEpochMs(clearExpired: false)
        let pendingEndSessionEpochMs = RestrictionStateStore.loadPendingEndSessionEpochMs(clearExpired: false)
        let nowEpochMs = RestrictionStateStore.currentEpochMs()

        if let activeSession {
            if pendingEndSessionEpochMs > 0, pendingEndSessionEpochMs <= nowEpochMs {
                _ = RestrictionStateStore.storePendingEndSessionEpochMs(0)
                PendingEndSessionMonitor.stopMonitoring()
                if activeSession.source == .schedule,
                   resolution.isInScheduleNow,
                   activeSession.modeId == resolution.activeModeId,
                   let suppressionUntilEpochMs = resolution.activeIntervalEndEpochMs,
                   suppressionUntilEpochMs > nowEpochMs {
                    _ = RestrictionStateStore.storeScheduleSuppression(
                        modeId: activeSession.modeId,
                        untilEpochMs: suppressionUntilEpochMs
                    )
                }
                _ = RestrictionStateStore.clearActiveSession()
                return resolveSessionState()
            } else if pendingEndSessionEpochMs > 0 {
                do {
                    try PendingEndSessionMonitor.startMonitoring(untilEpochMs: pendingEndSessionEpochMs, nowEpochMs: nowEpochMs)
                } catch {
                    // Keep session active; monitor failures are non-fatal for state resolution.
                }
            }
            if activeSession.source == .manual {
                if manualSessionEndEpochMs > 0, manualSessionEndEpochMs <= nowEpochMs {
                    _ = RestrictionStateStore.storeManualSessionEndEpochMs(0)
                    ManualSessionAutoEndMonitor.stopMonitoring()
                    _ = RestrictionStateStore.clearActiveSession()
                } else {
                    if manualSessionEndEpochMs > 0 {
                        do {
                            try ManualSessionAutoEndMonitor.startMonitoring(untilEpochMs: manualSessionEndEpochMs, nowEpochMs: nowEpochMs)
                        } catch {
                            // Keep session active; monitor failures are non-fatal for state resolution.
                        }
                    }
                    return SessionState(
                        isScheduleEnabled: modesEnabled,
                        isInScheduleNow: resolution.isInScheduleNow,
                        blockedAppIds: activeSession.blockedAppIds,
                        activeModeId: activeSession.modeId,
                        activeModeSource: .manual,
                        activeScheduleBoundaryEndEpochMs: nil
                    )
                }
            } else if manualSessionEndEpochMs > 0 {
                _ = RestrictionStateStore.storeManualSessionEndEpochMs(0)
                ManualSessionAutoEndMonitor.stopMonitoring()
            }

            if !shouldSuppressCurrentMode,
               resolution.isInScheduleNow,
               activeSession.modeId == resolution.activeModeId {
                return SessionState(
                    isScheduleEnabled: modesEnabled,
                    isInScheduleNow: true,
                    blockedAppIds: activeSession.blockedAppIds,
                    activeModeId: activeSession.modeId,
                    activeModeSource: .schedule,
                    activeScheduleBoundaryEndEpochMs: resolution.activeIntervalEndEpochMs
                )
            }

            _ = RestrictionStateStore.clearActiveSession()
        } else if pendingEndSessionEpochMs > 0 {
            _ = RestrictionStateStore.storePendingEndSessionEpochMs(0)
            PendingEndSessionMonitor.stopMonitoring()
        }

        if !shouldSuppressCurrentMode,
           resolution.isInScheduleNow,
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
                activeModeSource: .schedule,
                activeScheduleBoundaryEndEpochMs: resolution.activeIntervalEndEpochMs
            )
        }

        if shouldSuppressCurrentMode, resolution.isInScheduleNow {
            return SessionState(
                isScheduleEnabled: modesEnabled,
                isInScheduleNow: true,
                blockedAppIds: [],
                activeModeId: nil,
                activeModeSource: .none,
                activeScheduleBoundaryEndEpochMs: nil
            )
        }

        return SessionState(
            isScheduleEnabled: modesEnabled,
            isInScheduleNow: false,
            blockedAppIds: [],
            activeModeId: nil,
            activeModeSource: .none,
            activeScheduleBoundaryEndEpochMs: nil
        )
    }
}
