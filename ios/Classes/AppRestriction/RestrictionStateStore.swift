import Foundation

/// Shared app-group-backed storage for restriction session state.
enum RestrictionStateStore {
    static let pausedUntilEpochMsKey = "pausedUntilEpochMs"
    static let activeSessionKey = "activeSession"
    static let scheduleMonitorNamesKey = "scheduleMonitorNames"
    static let modesEnabledKey = "modesEnabled"
    static let modesKey = "modes"

    enum StoreResult {
        case success
        case appGroupUnavailable(resolvedGroupId: String)
    }

    struct ActiveSession {
        let modeId: String
        let blockedAppIds: [String]
        let source: RestrictionModeSource

        func toStorageMap() -> [String: Any] {
            [
                "modeId": modeId,
                "blockedAppIds": blockedAppIds,
                "source": source.wireValue,
            ]
        }

        static func fromStorageMap(_ map: [String: Any]) -> ActiveSession? {
            let modeId = (map["modeId"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let blockedAppIds = (map["blockedAppIds"] as? [Any] ?? []).compactMap { value -> String? in
                guard let raw = value as? String else {
                    return nil
                }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            let sourceRaw = (map["source"] as? String ?? RestrictionModeSource.manual.wireValue)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let source = RestrictionModeSource(rawValue: sourceRaw) ?? .manual
            let uniqueBlockedAppIds = Array(NSOrderedSet(array: blockedAppIds)) as? [String] ?? blockedAppIds
            guard !modeId.isEmpty, !uniqueBlockedAppIds.isEmpty else {
                return nil
            }
            return ActiveSession(modeId: modeId, blockedAppIds: uniqueBlockedAppIds, source: source)
        }
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

    static func loadActiveSession() -> ActiveSession? {
        guard let defaults = AppGroupStore.sharedDefaults() else {
            return nil
        }
        guard let raw = defaults.dictionary(forKey: activeSessionKey) else {
            return nil
        }
        guard let parsed = ActiveSession.fromStorageMap(raw) else {
            _ = clearActiveSession()
            return nil
        }
        return parsed
    }

    @discardableResult
    static func storeActiveSession(_ session: ActiveSession?) -> StoreResult {
        let resolvedGroupId = AppGroupStore.effectiveGroupIdentifier()
        guard let defaults = UserDefaults(suiteName: resolvedGroupId) else {
            return .appGroupUnavailable(resolvedGroupId: resolvedGroupId)
        }
        if let session {
            defaults.set(session.toStorageMap(), forKey: activeSessionKey)
        } else {
            defaults.removeObject(forKey: activeSessionKey)
        }
        return .success
    }

    @discardableResult
    static func clearActiveSession() -> StoreResult {
        return storeActiveSession(nil)
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
        let parsed = values.compactMap(RestrictionScheduledMode.init(storageMap:))
        let filtered = parsed.filter(\.shouldPersistForScheduleEnforcement)
        if filtered.count != parsed.count {
            _ = storeModes(filtered)
        }
        return filtered
    }

    @discardableResult
    static func storeModes(_ modes: [RestrictionScheduledMode]) -> StoreResult {
        let resolvedGroupId = AppGroupStore.effectiveGroupIdentifier()
        guard let defaults = UserDefaults(suiteName: resolvedGroupId) else {
            return .appGroupUnavailable(resolvedGroupId: resolvedGroupId)
        }
        defaults.set(
            modes
                .filter(\.shouldPersistForScheduleEnforcement)
                .map { $0.toStorageMap() },
            forKey: modesKey
        )
        return .success
    }
}
