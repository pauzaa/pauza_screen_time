import Foundation
import FamilyControls
import Flutter

@available(iOS 16.0, *)
struct ManageModesUseCase {
    static let featureRestrictions = "restrictions"

    static func upsertMode(mode: RestrictionScheduledMode) -> FlutterError? {
        if !mode.blockedAppIds.isEmpty {
            let decodeResult = ShieldManager.shared.decodeTokens(base64Tokens: mode.blockedAppIds)
            if !decodeResult.invalidTokens.isEmpty {
                return PluginErrors.invalidArguments(
                    feature: featureRestrictions,
                    action: MethodNames.upsertMode,
                    message: PluginErrorMessage.unableToDecodeTokens,
                    diagnostic: "invalidTokens=\(decodeResult.invalidTokens)"
                )
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
            return PluginErrors.invalidArguments(
                feature: featureRestrictions,
                action: MethodNames.upsertMode,
                message: "Mode schedule overlaps with an existing schedule"
            )
        }

        let shouldRescheduleMonitors = scheduleModesSignature(existing) != scheduleModesSignature(nextModes)
        if shouldRescheduleMonitors {
            switch RestrictionStateStore.storeModes(nextModes) {
            case .success:
                break
            case .appGroupUnavailable(let resolvedGroupId):
                return PluginErrors.internalFailure(
                    feature: featureRestrictions,
                    action: MethodNames.upsertMode,
                    message: PluginErrorMessage.appGroupUnavailable,
                    diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
                )
            }

            do {
                try RestrictionScheduleMonitorOrchestrator.rescheduleMonitors()
            } catch {
                return PluginErrors.internalFailure(
                    feature: featureRestrictions,
                    action: MethodNames.upsertMode,
                    message: "Failed to schedule iOS boundary monitors",
                    diagnostic: "error=\(String(describing: error))"
                )
            }
        }

        if let activeSession = try? RestrictionStateStore.loadActiveSession(),
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
                return PluginErrors.internalFailure(
                    feature: featureRestrictions,
                    action: MethodNames.upsertMode,
                    message: PluginErrorMessage.appGroupUnavailable,
                    diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
                )
            }
        }

        SessionEnforcementUseCase.applyDesiredRestrictionsIfNeeded(
            trigger: LifecycleReasonConstants.manual,
            previousLifecycleSnapshot: previousSnapshot
        )
        return nil
    }

    static func removeMode(modeId: String) -> FlutterError? {
        let existing = RestrictionStateStore.loadModes()
        let previousSnapshot = RestrictionStateStore.snapshotLifecycleState()
        let nextModes = existing.filter { $0.modeId != modeId }
        let shouldRescheduleMonitors = scheduleModesSignature(existing) != scheduleModesSignature(nextModes)
        if shouldRescheduleMonitors {
            switch RestrictionStateStore.storeModes(nextModes) {
            case .success:
                break
            case .appGroupUnavailable(let resolvedGroupId):
                return PluginErrors.internalFailure(
                    feature: featureRestrictions,
                    action: MethodNames.removeMode,
                    message: PluginErrorMessage.appGroupUnavailable,
                    diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
                )
            }
        }

        if (try? RestrictionStateStore.loadActiveSession())?.modeId == modeId {
            switch RestrictionStateStore.clearActiveSession() {
            case .success:
                break
            case .appGroupUnavailable(let resolvedGroupId):
                return PluginErrors.internalFailure(
                    feature: featureRestrictions,
                    action: MethodNames.removeMode,
                    message: PluginErrorMessage.appGroupUnavailable,
                    diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
                )
            }
        }

        if shouldRescheduleMonitors {
            do {
                try RestrictionScheduleMonitorOrchestrator.rescheduleMonitors()
            } catch {
                return PluginErrors.internalFailure(
                    feature: featureRestrictions,
                    action: MethodNames.removeMode,
                    message: "Failed to schedule iOS boundary monitors",
                    diagnostic: "error=\(String(describing: error))"
                )
            }
        }

        SessionEnforcementUseCase.applyDesiredRestrictionsIfNeeded(
            trigger: LifecycleReasonConstants.manual,
            previousLifecycleSnapshot: previousSnapshot
        )
        return nil
    }

    static func setModesEnabled(enabled: Bool) -> FlutterError? {
        let previousSnapshot = RestrictionStateStore.snapshotLifecycleState()
        switch RestrictionStateStore.storeModesEnabled(enabled) {
        case .success:
            break
        case .appGroupUnavailable(let resolvedGroupId):
            return PluginErrors.internalFailure(
                feature: featureRestrictions,
                action: MethodNames.setModesEnabled,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            )
        }

        do {
            try RestrictionScheduleMonitorOrchestrator.rescheduleMonitors()
        } catch {
            return PluginErrors.internalFailure(
                feature: featureRestrictions,
                action: MethodNames.setModesEnabled,
                message: "Failed to schedule iOS boundary monitors",
                diagnostic: "error=\(String(describing: error))"
            )
        }

        SessionEnforcementUseCase.applyDesiredRestrictionsIfNeeded(
            trigger: LifecycleReasonConstants.manual,
            previousLifecycleSnapshot: previousSnapshot
        )
        return nil
    }

    static func getModesConfig() -> RestrictionScheduledModesConfig {
        return RestrictionScheduledModesConfig(
            enabled: RestrictionStateStore.loadModesEnabled(),
            modes: RestrictionStateStore.loadModes()
        )
    }

    private static func scheduleModesSignature(_ modes: [RestrictionScheduledMode]) -> Int {
        var hasher = Hasher()
        for mode in modes {
            hasher.combine(mode.modeId)
            hasher.combine(mode.schedule?.startMinutes)
            hasher.combine(mode.schedule?.endMinutes)
            hasher.combine(mode.schedule?.daysOfWeekIso)
        }
        return hasher.finalize()
    }
}
