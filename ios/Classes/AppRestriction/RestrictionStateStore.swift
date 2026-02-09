import Foundation

/// Shared app-group-backed storage for restriction session state.
enum RestrictionStateStore {
    static let desiredRestrictedAppsKey = "desiredRestrictedApps"
    static let pausedUntilEpochMsKey = "pausedUntilEpochMs"
    static let manualEnforcementEnabledKey = "manualEnforcementEnabled"
    static let scheduleMonitorNamesKey = "scheduleMonitorNames"
    static let scheduledModesEnabledKey = "scheduledModesEnabled"
    static let scheduledModesKey = "scheduledModes"

    enum StoreResult {
        case success
        case appGroupUnavailable(resolvedGroupId: String)
    }

    static func loadDesiredRestrictedApps() -> [String] {
        guard let defaults = AppGroupStore.sharedDefaults() else {
            return []
        }
        let values = defaults.array(forKey: desiredRestrictedAppsKey) as? [String] ?? []
        var unique: [String] = []
        var seen = Set<String>()
        unique.reserveCapacity(values.count)
        for token in values {
            if seen.insert(token).inserted {
                unique.append(token)
            }
        }
        return unique
    }

    @discardableResult
    static func storeDesiredRestrictedApps(_ tokens: [String]) -> StoreResult {
        let resolvedGroupId = AppGroupStore.effectiveGroupIdentifier()
        guard let defaults = UserDefaults(suiteName: resolvedGroupId) else {
            return .appGroupUnavailable(resolvedGroupId: resolvedGroupId)
        }
        defaults.set(tokens, forKey: desiredRestrictedAppsKey)
        return .success
    }

    static func loadPausedUntilEpochMs(nowEpochMs: Int64 = currentEpochMs()) -> Int64 {
        guard let defaults = AppGroupStore.sharedDefaults() else {
            return 0
        }
        let pausedUntil: Int64
        if let number = defaults.object(forKey: pausedUntilEpochMsKey) as? NSNumber {
            pausedUntil = number.int64Value
        } else if let raw = defaults.object(forKey: pausedUntilEpochMsKey) as? Int64 {
            pausedUntil = raw
        } else {
            pausedUntil = 0
        }
        if pausedUntil <= nowEpochMs {
            defaults.set(Int64(0), forKey: pausedUntilEpochMsKey)
            return 0
        }
        return pausedUntil
    }

    static func loadManualEnforcementEnabled() -> Bool {
        guard let defaults = AppGroupStore.sharedDefaults() else {
            return true
        }
        if defaults.object(forKey: manualEnforcementEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: manualEnforcementEnabledKey)
    }

    @discardableResult
    static func storeManualEnforcementEnabled(_ enabled: Bool) -> StoreResult {
        let resolvedGroupId = AppGroupStore.effectiveGroupIdentifier()
        guard let defaults = UserDefaults(suiteName: resolvedGroupId) else {
            return .appGroupUnavailable(resolvedGroupId: resolvedGroupId)
        }
        defaults.set(enabled, forKey: manualEnforcementEnabledKey)
        return .success
    }

    static func loadScheduleMonitorNames() -> [String] {
        guard let defaults = AppGroupStore.sharedDefaults() else {
            return []
        }
        return defaults.array(forKey: scheduleMonitorNamesKey) as? [String] ?? []
    }

    @discardableResult
    static func storeScheduleMonitorNames(_ names: [String]) -> StoreResult {
        let resolvedGroupId = AppGroupStore.effectiveGroupIdentifier()
        guard let defaults = UserDefaults(suiteName: resolvedGroupId) else {
            return .appGroupUnavailable(resolvedGroupId: resolvedGroupId)
        }
        defaults.set(names, forKey: scheduleMonitorNamesKey)
        return .success
    }

    @discardableResult
    static func storePausedUntilEpochMs(_ epochMs: Int64) -> StoreResult {
        let resolvedGroupId = AppGroupStore.effectiveGroupIdentifier()
        guard let defaults = UserDefaults(suiteName: resolvedGroupId) else {
            return .appGroupUnavailable(resolvedGroupId: resolvedGroupId)
        }
        defaults.set(epochMs, forKey: pausedUntilEpochMsKey)
        return .success
    }

    static func currentEpochMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    static func loadScheduledModesEnabled() -> Bool {
        guard let defaults = AppGroupStore.sharedDefaults() else {
            return false
        }
        return defaults.bool(forKey: scheduledModesEnabledKey)
    }

    @discardableResult
    static func storeScheduledModesEnabled(_ enabled: Bool) -> StoreResult {
        let resolvedGroupId = AppGroupStore.effectiveGroupIdentifier()
        guard let defaults = UserDefaults(suiteName: resolvedGroupId) else {
            return .appGroupUnavailable(resolvedGroupId: resolvedGroupId)
        }
        defaults.set(enabled, forKey: scheduledModesEnabledKey)
        return .success
    }

    static func loadScheduledModes() -> [RestrictionScheduledMode] {
        guard let defaults = AppGroupStore.sharedDefaults() else {
            return []
        }
        guard let values = defaults.array(forKey: scheduledModesKey) as? [[String: Any]] else {
            return []
        }
        return values.compactMap(RestrictionScheduledMode.init(dictionary:))
    }

    @discardableResult
    static func storeScheduledModes(_ modes: [RestrictionScheduledMode]) -> StoreResult {
        let resolvedGroupId = AppGroupStore.effectiveGroupIdentifier()
        guard let defaults = UserDefaults(suiteName: resolvedGroupId) else {
            return .appGroupUnavailable(resolvedGroupId: resolvedGroupId)
        }
        defaults.set(modes.map { $0.toDictionary() }, forKey: scheduledModesKey)
        return .success
    }
}
