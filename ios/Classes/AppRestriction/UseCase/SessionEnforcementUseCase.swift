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
}

@available(iOS 16.0, *)
struct SessionEnforcementUseCase {
    static let featureRestrictions = "restrictions"

    static func isRestrictionSessionActiveNow(isPrerequisitesMet: Bool) -> Bool {
        applyDesiredRestrictionsIfNeeded(trigger: "is_restriction_session_active_now")
        let state = resolveSessionState()
        let isPausedNow = RestrictionStateStore.loadPausedUntilEpochMs() > 0
        let shouldEnforceSession = state.activeModeSource != .none
        return !state.blockedAppIds.isEmpty && !isPausedNow && isPrerequisitesMet && shouldEnforceSession
    }

    static func pauseEnforcement(durationMs: Int64) -> FlutterError? {
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
            applyDesiredRestrictionsIfNeeded(trigger: "pause_enforcement_rollback")
            return PluginErrors.internalFailure(
                feature: featureRestrictions,
                action: MethodNames.pauseEnforcement,
                message: PluginErrorMessage.pauseMonitoringStartFailed,
                diagnostic: "activityName=\(PauseAutoResumeMonitor.activityNameRaw), error=\(String(describing: error))"
            )
        }

        ShieldManager.shared.clearRestrictions()
        applyDesiredRestrictionsIfNeeded(
            trigger: "pause_enforcement",
            previousLifecycleSnapshot: previousSnapshot
        )
        return nil
    }

    static func resumeEnforcement() -> FlutterError? {
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
            trigger: "resume_enforcement",
            previousLifecycleSnapshot: previousSnapshot
        )
        return nil
    }

    static func startSession(modeId: String, blockedAppIds: [String]) -> FlutterError? {
        let decodeResult = ShieldManager.shared.decodeTokens(base64Tokens: blockedAppIds)
        if !decodeResult.invalidTokens.isEmpty {
            return PluginErrors.invalidArguments(
                feature: featureRestrictions,
                action: MethodNames.startSession,
                message: PluginErrorMessage.unableToDecodeTokens,
                diagnostic: "invalidTokens=\(decodeResult.invalidTokens)"
            )
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
            return PluginErrors.internalFailure(
                feature: featureRestrictions,
                action: MethodNames.startSession,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            )
        }

        applyDesiredRestrictionsIfNeeded(
            trigger: "start_session_manual",
            previousLifecycleSnapshot: previousSnapshot
        )
        return nil
    }

    static func endSession() -> FlutterError? {
        let previousSnapshot = RestrictionStateStore.snapshotLifecycleState()
        
        let storeResult: RestrictionStateStore.StoreResult
        if let activeSession = RestrictionStateStore.loadActiveSession(), activeSession.source == .manual {
            storeResult = RestrictionStateStore.clearActiveSession()
        } else {
            storeResult = .success
        }

        switch storeResult {
        case .success:
            applyDesiredRestrictionsIfNeeded(
                trigger: "end_session_manual",
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
        applyDesiredRestrictionsIfNeeded(trigger: "get_restriction_session")
        let state = resolveSessionState()
        let pausedUntilEpochMs = RestrictionStateStore.loadPausedUntilEpochMs()
        let isPausedNow = pausedUntilEpochMs > 0
        let activeSessionId = RestrictionStateStore.loadActiveSession()?.sessionId
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
}
