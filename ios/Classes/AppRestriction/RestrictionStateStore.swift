import Foundation

/// Shared app-group-backed storage for restriction session state.
enum RestrictionStateStore {
    static let pausedUntilEpochMsKey = "pausedUntilEpochMs"
    static let manualActiveModeIdKey = "manualActiveModeId"
    static let scheduleMonitorNamesKey = "scheduleMonitorNames"
    static let modesEnabledKey = "modesEnabled"
    static let modesKey = "modes"

    enum StoreResult {
        case success
        case appGroupUnavailable(resolvedGroupId: String)
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

    static func loadManualActiveModeId() -> String? {
        guard let defaults = AppGroupStore.sharedDefaults() else {
            return nil
        }
        let value = (defaults.string(forKey: manualActiveModeIdKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    @discardableResult
    static func storeManualActiveModeId(_ modeId: String?) -> StoreResult {
        let resolvedGroupId = AppGroupStore.effectiveGroupIdentifier()
        guard let defaults = UserDefaults(suiteName: resolvedGroupId) else {
            return .appGroupUnavailable(resolvedGroupId: resolvedGroupId)
        }
        let normalized = modeId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized, !normalized.isEmpty {
            defaults.set(normalized, forKey: manualActiveModeIdKey)
        } else {
            defaults.removeObject(forKey: manualActiveModeIdKey)
        }
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

    static func loadModesEnabled() -> Bool {
        guard let defaults = AppGroupStore.sharedDefaults() else {
            return false
        }
        return defaults.bool(forKey: modesEnabledKey)
    }

    @discardableResult
    static func storeModesEnabled(_ enabled: Bool) -> StoreResult {
        let resolvedGroupId = AppGroupStore.effectiveGroupIdentifier()
        guard let defaults = UserDefaults(suiteName: resolvedGroupId) else {
            return .appGroupUnavailable(resolvedGroupId: resolvedGroupId)
        }
        defaults.set(enabled, forKey: modesEnabledKey)
        return .success
    }

    static func loadModes() -> [RestrictionScheduledMode] {
        guard let defaults = AppGroupStore.sharedDefaults() else {
            return []
        }
        guard let values = defaults.array(forKey: modesKey) as? [[String: Any]] else {
            return []
        }
        return values.compactMap(RestrictionScheduledMode.init(dictionary:))
    }

    @discardableResult
    static func storeModes(_ modes: [RestrictionScheduledMode]) -> StoreResult {
        let resolvedGroupId = AppGroupStore.effectiveGroupIdentifier()
        guard let defaults = UserDefaults(suiteName: resolvedGroupId) else {
            return .appGroupUnavailable(resolvedGroupId: resolvedGroupId)
        }
        defaults.set(modes.map { $0.toDictionary() }, forKey: modesKey)
        return .success
    }
}
