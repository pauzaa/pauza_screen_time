import Foundation

/// Shared app-group-backed storage for restriction session state.
enum RestrictionStateStore {
    static let pausedUntilEpochMsKey = "pausedUntilEpochMs"
    static let activeSessionKey = "activeSession"
    static let scheduleMonitorNamesKey = "scheduleMonitorNames"
    static let modesEnabledKey = "modesEnabled"
    static let modesKey = "modes"
    static let lifecycleEventsKey = "lifecycleEvents"
    static let activeSessionLifecycleEventsKey = "activeSessionLifecycleEvents"
    static let lifecycleEventSeqKey = "lifecycleEventSeq"
    static let sessionIdSeqKey = "sessionIdSeq"

    private static let maxLifecycleEvents = 10_000
    private static let lifecycleLock = NSLock()

    enum StoreResult {
        case success
        case appGroupUnavailable(resolvedGroupId: String)
    }

    struct ActiveSession {
        let sessionId: String
        let modeId: String
        let blockedAppIds: [String]
        let source: RestrictionModeSource

        func toStorageMap() -> [String: Any] {
            [
                "sessionId": sessionId,
                "modeId": modeId,
                "blockedAppIds": blockedAppIds,
                "source": source.wireValue,
            ]
        }

        static func fromStorageMap(_ map: [String: Any]) -> ActiveSession? {
            let sessionId = (map["sessionId"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
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
            return ActiveSession(
                sessionId: sessionId,
                modeId: modeId,
                blockedAppIds: uniqueBlockedAppIds,
                source: source
            )
        }
    }

    static func loadPausedUntilEpochMs(
        nowEpochMs: Int64 = currentEpochMs(),
        clearExpired: Bool = true
    ) -> Int64 {
        guard let defaults = AppGroupStore.sharedDefaults() else {
            return 0
        }
        let pausedUntil = pausedUntilValue(defaults)
        if pausedUntil <= nowEpochMs {
            if clearExpired, pausedUntil > 0 {
                defaults.set(Int64(0), forKey: pausedUntilEpochMsKey)
            }
            return 0
        }
        return pausedUntil
    }

    static func hasPauseMarker() -> Bool {
        guard let defaults = AppGroupStore.sharedDefaults() else {
            return false
        }
        return pausedUntilValue(defaults) > 0
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
        if parsed.sessionId.isEmpty {
            let migrated = ActiveSession(
                sessionId: nextSessionId(defaults: defaults),
                modeId: parsed.modeId,
                blockedAppIds: parsed.blockedAppIds,
                source: parsed.source
            )
            defaults.set(migrated.toStorageMap(), forKey: activeSessionKey)
            return migrated
        }
        return parsed
    }

    @discardableResult
    static func storeActiveSession(_ session: ActiveSession?) -> StoreResult {
        let resolvedGroupId = AppGroupStore.effectiveGroupIdentifier()
        guard let defaults = UserDefaults(suiteName: resolvedGroupId) else {
            return .appGroupUnavailable(resolvedGroupId: resolvedGroupId)
        }
        let previousSessionId = ActiveSession.fromStorageMap(defaults.dictionary(forKey: activeSessionKey) ?? [:])?.sessionId
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let session {
            let normalizedSessionId = session.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
            let persisted = ActiveSession(
                sessionId: normalizedSessionId.isEmpty ? nextSessionId(defaults: defaults) : normalizedSessionId,
                modeId: session.modeId,
                blockedAppIds: session.blockedAppIds,
                source: session.source
            )
            if previousSessionId != persisted.sessionId {
                clearActiveSessionLifecycleEvents(defaults: defaults)
            }
            defaults.set(persisted.toStorageMap(), forKey: activeSessionKey)
        } else {
            defaults.removeObject(forKey: activeSessionKey)
            clearActiveSessionLifecycleEvents(defaults: defaults)
        }
        return .success
    }

    @discardableResult
    static func clearActiveSession() -> StoreResult {
        return storeActiveSession(nil)
    }

    static func snapshotLifecycleState() -> RestrictionLifecycleSnapshot {
        let activeSession = loadActiveSession()
        if let activeSession {
            return RestrictionLifecycleSnapshot(
                isActive: true,
                isPaused: hasPauseMarker(),
                modeId: activeSession.modeId,
                source: activeSession.source,
                sessionId: activeSession.sessionId
            )
        }
        return RestrictionLifecycleSnapshot.inactive(isPaused: hasPauseMarker())
    }

    @discardableResult
    static func appendLifecycleTransition(
        previous: RestrictionLifecycleSnapshot,
        next: RestrictionLifecycleSnapshot,
        reason: String,
        occurredAtEpochMs: Int64 = currentEpochMs()
    ) -> StoreResult {
        let drafts = RestrictionLifecycleTransitionMapper.map(
            previous: previous,
            next: next,
            reason: reason,
            occurredAtEpochMs: occurredAtEpochMs
        )
        return appendLifecycleEvents(drafts)
    }

    static func loadPendingLifecycleEvents(limit: Int) -> [RestrictionLifecycleEvent] {
        guard let defaults = AppGroupStore.sharedDefaults() else {
            return []
        }
        let normalizedLimit = max(1, min(limit, maxLifecycleEvents))
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return loadLifecycleEvents(defaults: defaults).prefix(normalizedLimit).map { $0 }
    }

    static func loadActiveSessionLifecycleEvents(limit: Int) -> [RestrictionLifecycleEvent] {
        guard let defaults = AppGroupStore.sharedDefaults() else {
            return []
        }
        let normalizedLimit = max(1, min(limit, maxLifecycleEvents))
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return loadActiveSessionLifecycleEvents(defaults: defaults).prefix(normalizedLimit).map { $0 }
    }

    @discardableResult
    static func ackLifecycleEvents(throughEventId: String) -> StoreResult {
        let normalizedId = throughEventId.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedId.isEmpty {
            return .success
        }

        let resolvedGroupId = AppGroupStore.effectiveGroupIdentifier()
        guard let defaults = UserDefaults(suiteName: resolvedGroupId) else {
            return .appGroupUnavailable(resolvedGroupId: resolvedGroupId)
        }
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        let events = loadLifecycleEvents(defaults: defaults)
        let filtered = events.filter { $0.id > normalizedId }
        if filtered.count != events.count {
            persistLifecycleEvents(
                filtered,
                seq: sequenceValue(defaults, key: lifecycleEventSeqKey),
                defaults: defaults
            )
        }
        return .success
    }

    @discardableResult
    static func appendLifecycleEvents(_ drafts: [RestrictionLifecycleEventDraft]) -> StoreResult {
        if drafts.isEmpty {
            return .success
        }
        let resolvedGroupId = AppGroupStore.effectiveGroupIdentifier()
        guard let defaults = UserDefaults(suiteName: resolvedGroupId) else {
            return .appGroupUnavailable(resolvedGroupId: resolvedGroupId)
        }
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        var events = loadLifecycleEvents(defaults: defaults)
        var activeSessionEvents = loadActiveSessionLifecycleEvents(defaults: defaults)
        let activeSessionId = ActiveSession.fromStorageMap(defaults.dictionary(forKey: activeSessionKey) ?? [:])?.sessionId
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var nextSeq = sequenceValue(defaults, key: lifecycleEventSeqKey)
        for draft in drafts {
            guard let normalized = normalizeLifecycleDraft(draft) else {
                continue
            }
            nextSeq += 1
            let generated = RestrictionLifecycleEvent(
                id: nextLifecycleEventId(seq: nextSeq, occurredAtEpochMs: normalized.occurredAtEpochMs),
                sessionId: normalized.sessionId,
                modeId: normalized.modeId,
                action: normalized.action,
                source: normalized.source,
                reason: normalized.reason,
                occurredAtEpochMs: normalized.occurredAtEpochMs
            )
            events.append(generated)
            if !activeSessionId.isEmpty, generated.sessionId == activeSessionId {
                activeSessionEvents.append(generated)
            }
        }
        if events.count > maxLifecycleEvents {
            events = Array(events.suffix(maxLifecycleEvents))
        }
        if activeSessionEvents.count > maxLifecycleEvents {
            activeSessionEvents = Array(activeSessionEvents.suffix(maxLifecycleEvents))
        }
        persistLifecycleEvents(events, seq: nextSeq, defaults: defaults)
        persistActiveSessionLifecycleEvents(activeSessionEvents, defaults: defaults)
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

    private static func pausedUntilValue(_ defaults: UserDefaults) -> Int64 {
        if let number = defaults.object(forKey: pausedUntilEpochMsKey) as? NSNumber {
            return number.int64Value
        }
        if let raw = defaults.object(forKey: pausedUntilEpochMsKey) as? Int64 {
            return raw
        }
        if let raw = defaults.object(forKey: pausedUntilEpochMsKey) as? Int {
            return Int64(raw)
        }
        return 0
    }

    private static func sequenceValue(_ defaults: UserDefaults, key: String) -> Int64 {
        if let number = defaults.object(forKey: key) as? NSNumber {
            return number.int64Value
        }
        if let raw = defaults.object(forKey: key) as? Int64 {
            return raw
        }
        if let raw = defaults.object(forKey: key) as? Int {
            return Int64(raw)
        }
        return 0
    }

    private static func nextSessionId(defaults: UserDefaults) -> String {
        let nextSeq = sequenceValue(defaults, key: sessionIdSeqKey) + 1
        defaults.set(nextSeq, forKey: sessionIdSeqKey)
        return "s-\(formatCounter(nextSeq, width: 12))-\(formatEpochMs(currentEpochMs()))"
    }

    private static func loadLifecycleEvents(defaults: UserDefaults) -> [RestrictionLifecycleEvent] {
        guard let values = defaults.array(forKey: lifecycleEventsKey) as? [[String: Any]] else {
            return []
        }
        return values
            .compactMap(RestrictionLifecycleEvent.init)
            .sorted { $0.id < $1.id }
    }

    private static func loadActiveSessionLifecycleEvents(defaults: UserDefaults) -> [RestrictionLifecycleEvent] {
        guard let values = defaults.array(forKey: activeSessionLifecycleEventsKey) as? [[String: Any]] else {
            return []
        }
        return values
            .compactMap(RestrictionLifecycleEvent.init)
            .sorted { $0.id < $1.id }
    }

    private static func persistLifecycleEvents(
        _ events: [RestrictionLifecycleEvent],
        seq: Int64,
        defaults: UserDefaults
    ) {
        defaults.set(events.map { $0.toStorageMap() }, forKey: lifecycleEventsKey)
        defaults.set(max(seq, 0), forKey: lifecycleEventSeqKey)
    }

    private static func persistActiveSessionLifecycleEvents(
        _ events: [RestrictionLifecycleEvent],
        defaults: UserDefaults
    ) {
        defaults.set(events.map { $0.toStorageMap() }, forKey: activeSessionLifecycleEventsKey)
    }

    static func clearActiveSessionLifecycleEvents(defaults: UserDefaults? = nil) {
        if let defaults {
            defaults.removeObject(forKey: activeSessionLifecycleEventsKey)
            return
        }
        guard let sharedDefaults = AppGroupStore.sharedDefaults() else {
            return
        }
        sharedDefaults.removeObject(forKey: activeSessionLifecycleEventsKey)
    }

    private static func normalizeLifecycleDraft(
        _ draft: RestrictionLifecycleEventDraft
    ) -> RestrictionLifecycleEventDraft? {
        let sessionId = draft.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        let modeId = draft.modeId.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = draft.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionId.isEmpty,
              !modeId.isEmpty,
              !reason.isEmpty,
              draft.occurredAtEpochMs > 0 else {
            return nil
        }
        return RestrictionLifecycleEventDraft(
            sessionId: sessionId,
            modeId: modeId,
            action: draft.action,
            source: draft.source,
            reason: reason,
            occurredAtEpochMs: draft.occurredAtEpochMs
        )
    }

    private static func nextLifecycleEventId(seq: Int64, occurredAtEpochMs: Int64) -> String {
        return "\(formatCounter(seq, width: 20))-\(formatEpochMs(occurredAtEpochMs))"
    }

    private static func formatCounter(_ value: Int64, width: Int) -> String {
        return String(max(value, 0)).leftPadded(to: width, with: "0")
    }

    private static func formatEpochMs(_ value: Int64) -> String {
        return String(max(value, 0)).leftPadded(to: 13, with: "0")
    }
}

private extension String {
    func leftPadded(to length: Int, with pad: String) -> String {
        guard count < length else {
            return self
        }
        return String(repeating: pad, count: length - count) + self
    }
}
