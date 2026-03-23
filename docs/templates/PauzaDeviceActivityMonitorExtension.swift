import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

@available(iOSApplicationExtension 16.0, *)
final class PauzaDeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let store = ManagedSettingsStore()

    private let pauseActivityName = DeviceActivityName("pauza_pause_auto_resume")
    private let scheduleActivityPrefix = "pauza.schedule.mode."
    private let appGroupInfoPlistKey = "AppGroupIdentifier"
    private let pausedUntilEpochMsKey = "pausedUntilEpochMs"
    private let activeSessionKey = "activeSession"
    private let scheduleEnforcementEnabledKey = "scheduleEnforcementEnabled"
    private let modesKey = "modes"
    private let lifecycleEventsKey = "lifecycleEvents"
    private let lifecycleEventSeqKey = "lifecycleEventSeq"
    private let sessionIdSeqKey = "sessionIdSeq"
    private let maxLifecycleEvents = 10_000

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity == pauseActivityName || activity.rawValue.hasPrefix(scheduleActivityPrefix) else {
            return
        }
        guard let defaults = UserDefaults(suiteName: resolvedAppGroupIdentifier()) else {
            return
        }

        let previousSnapshot = captureLifecycleSnapshot(defaults: defaults)
        if activity.rawValue.hasPrefix(scheduleActivityPrefix),
           let mode = scheduledModeForActivity(activity, defaults: defaults) {
            defaults.set(
                ActiveSession(
                    sessionId: nextSessionId(defaults: defaults),
                    modeId: mode.modeId,
                    blockedAppIds: mode.blockedAppIds,
                    source: .schedule
                ).toDictionary(),
                forKey: activeSessionKey
            )
        }

        applyEnforcementStateIfNeeded(defaults: defaults)
        appendTransitions(
            previous: previousSnapshot,
            next: captureLifecycleSnapshot(defaults: defaults),
            reason: activity.rawValue.hasPrefix(scheduleActivityPrefix) ? "schedule_boundary_start" : "pause_interval_start",
            defaults: defaults
        )
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == pauseActivityName || activity.rawValue.hasPrefix(scheduleActivityPrefix) else {
            return
        }
        guard let defaults = UserDefaults(suiteName: resolvedAppGroupIdentifier()) else {
            return
        }

        let previousSnapshot = captureLifecycleSnapshot(defaults: defaults)
        if activity.rawValue.hasPrefix(scheduleActivityPrefix),
           let mode = scheduledModeForActivity(activity, defaults: defaults),
           let activeSession = loadActiveSession(defaults: defaults),
           activeSession.source == .schedule,
           activeSession.modeId == mode.modeId {
            defaults.removeObject(forKey: activeSessionKey)
        }

        applyEnforcementStateIfNeeded(defaults: defaults)
        appendTransitions(
            previous: previousSnapshot,
            next: captureLifecycleSnapshot(defaults: defaults),
            reason: activity == pauseActivityName ? "pause_end_alarm" : "schedule_boundary_end",
            defaults: defaults
        )
    }

    private func applyEnforcementStateIfNeeded(defaults: UserDefaults) {
        let nowEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
        let pausedUntilEpochMs = loadPausedUntilEpochMs(defaults: defaults)
        if pausedUntilEpochMs > nowEpochMs {
            clearRestrictions()
            return
        }
        if pausedUntilEpochMs > 0 {
            defaults.set(Int64(0), forKey: pausedUntilEpochMsKey)
        }

        guard let activeSession = loadActiveSession(defaults: defaults) else {
            clearRestrictions()
            return
        }

        let decodedTokens = decodeTokens(activeSession.blockedAppIds)
        if decodedTokens.count != activeSession.blockedAppIds.count {
            clearRestrictions()
            return
        }
        store.shield.applications = Set(decodedTokens)
    }

    private func clearRestrictions() {
        store.shield.applications = nil
        store.shield.webDomains = nil
    }

    private func loadPausedUntilEpochMs(defaults: UserDefaults) -> Int64 {
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

    private func decodeTokens(_ values: [String]) -> [ApplicationToken] {
        var decoded: [ApplicationToken] = []
        decoded.reserveCapacity(values.count)
        for value in values {
            guard let data = Data(base64Encoded: value),
                  let token = try? JSONDecoder().decode(ApplicationToken.self, from: data) else {
                continue
            }
            decoded.append(token)
        }
        return decoded
    }

    private func loadModes(defaults: UserDefaults) -> [RestrictionMode] {
        guard let raw = defaults.array(forKey: modesKey) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap(RestrictionMode.init(dictionary:))
    }

    private func scheduledModeForActivity(_ activity: DeviceActivityName, defaults: UserDefaults) -> RestrictionMode? {
        let rawName = activity.rawValue
        guard rawName.hasPrefix(scheduleActivityPrefix) else {
            return nil
        }
        guard defaults.bool(forKey: scheduleEnforcementEnabledKey) else {
            return nil
        }

        let suffix = rawName.replacingOccurrences(of: scheduleActivityPrefix, with: "")
        guard let index = Int(suffix) else {
            return nil
        }

        let validScheduledModes = loadModes(defaults: defaults).filter { mode in
            mode.schedule?.isValidBasic == true && !mode.blockedAppIds.isEmpty
        }
        guard index >= 0 && index < validScheduledModes.count else {
            return nil
        }
        return validScheduledModes[index]
    }

    private func loadActiveSession(defaults: UserDefaults) -> ActiveSession? {
        guard let raw = defaults.dictionary(forKey: activeSessionKey) else {
            return nil
        }
        guard var session = ActiveSession(dictionary: raw) else {
            defaults.removeObject(forKey: activeSessionKey)
            return nil
        }
        if session.sessionId.isEmpty {
            session = ActiveSession(
                sessionId: nextSessionId(defaults: defaults),
                modeId: session.modeId,
                blockedAppIds: session.blockedAppIds,
                source: session.source
            )
            defaults.set(session.toDictionary(), forKey: activeSessionKey)
        }
        return session
    }

    private func captureLifecycleSnapshot(defaults: UserDefaults) -> LifecycleSnapshot {
        let activeSession = loadActiveSession(defaults: defaults)
        if let activeSession {
            return LifecycleSnapshot(
                isActive: true,
                isPaused: loadPausedUntilEpochMs(defaults: defaults) > 0,
                modeId: activeSession.modeId,
                source: activeSession.source,
                sessionId: activeSession.sessionId
            )
        }
        return LifecycleSnapshot(isActive: false, isPaused: loadPausedUntilEpochMs(defaults: defaults) > 0, modeId: nil, source: nil, sessionId: nil)
    }

    private func appendTransitions(
        previous: LifecycleSnapshot,
        next: LifecycleSnapshot,
        reason: String,
        defaults: UserDefaults
    ) {
        let events = mapTransitions(previous: previous, next: next, reason: reason, occurredAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000))
        guard !events.isEmpty else {
            return
        }
        var persisted = loadLifecycleEvents(defaults: defaults)
        var seq = loadSequence(defaults: defaults, key: lifecycleEventSeqKey)
        for draft in events {
            seq += 1
            persisted.append(
                LifecycleEvent(
                    id: nextLifecycleEventId(seq: seq, occurredAtEpochMs: draft.occurredAtEpochMs),
                    sessionId: draft.sessionId,
                    modeId: draft.modeId,
                    action: draft.action,
                    source: draft.source,
                    reason: draft.reason,
                    occurredAtEpochMs: draft.occurredAtEpochMs
                )
            )
        }
        if persisted.count > maxLifecycleEvents {
            persisted = Array(persisted.suffix(maxLifecycleEvents))
        }
        defaults.set(persisted.map { $0.toDictionary() }, forKey: lifecycleEventsKey)
        defaults.set(seq, forKey: lifecycleEventSeqKey)
    }

    private func mapTransitions(
        previous: LifecycleSnapshot,
        next: LifecycleSnapshot,
        reason: String,
        occurredAtEpochMs: Int64
    ) -> [LifecycleEventDraft] {
        if !previous.isActive && !next.isActive {
            return []
        }
        if previous.isActive && !next.isActive {
            return eventDraft(from: previous, action: "END", reason: reason, occurredAtEpochMs: occurredAtEpochMs)
        }
        if !previous.isActive && next.isActive {
            return eventDraft(from: next, action: "START", reason: reason, occurredAtEpochMs: occurredAtEpochMs)
        }

        let modeOrSourceChanged = previous.modeId != next.modeId || previous.source != next.source || previous.sessionId != next.sessionId
        if modeOrSourceChanged {
            return eventDraft(from: previous, action: "END", reason: reason, occurredAtEpochMs: occurredAtEpochMs) +
                eventDraft(from: next, action: "START", reason: reason, occurredAtEpochMs: occurredAtEpochMs)
        }
        if !previous.isPaused && next.isPaused {
            return eventDraft(from: next, action: "PAUSE", reason: reason, occurredAtEpochMs: occurredAtEpochMs)
        }
        if previous.isPaused && !next.isPaused {
            return eventDraft(from: next, action: "RESUME", reason: reason, occurredAtEpochMs: occurredAtEpochMs)
        }
        return []
    }

    private func eventDraft(
        from snapshot: LifecycleSnapshot,
        action: String,
        reason: String,
        occurredAtEpochMs: Int64
    ) -> [LifecycleEventDraft] {
        guard let source = snapshot.source,
              let modeId = snapshot.modeId,
              let sessionId = snapshot.sessionId,
              !modeId.isEmpty,
              !sessionId.isEmpty,
              !reason.isEmpty else {
            return []
        }
        return [LifecycleEventDraft(
            sessionId: sessionId,
            modeId: modeId,
            action: action,
            source: source.rawValue,
            reason: reason,
            occurredAtEpochMs: occurredAtEpochMs
        )]
    }

    private func loadLifecycleEvents(defaults: UserDefaults) -> [LifecycleEvent] {
        guard let values = defaults.array(forKey: lifecycleEventsKey) as? [[String: Any]] else {
            return []
        }
        return values.compactMap(LifecycleEvent.init(dictionary:)).sorted { $0.id < $1.id }
    }

    private func loadSequence(defaults: UserDefaults, key: String) -> Int64 {
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

    private func nextSessionId(defaults: UserDefaults) -> String {
        let nextSeq = loadSequence(defaults: defaults, key: sessionIdSeqKey) + 1
        defaults.set(nextSeq, forKey: sessionIdSeqKey)
        return "s-\(leftPad(nextSeq, width: 12))-\(leftPad(Int64(Date().timeIntervalSince1970 * 1000), width: 13))"
    }

    private func nextLifecycleEventId(seq: Int64, occurredAtEpochMs: Int64) -> String {
        return "\(leftPad(seq, width: 20))-\(leftPad(occurredAtEpochMs, width: 13))"
    }

    private func leftPad(_ value: Int64, width: Int) -> String {
        let raw = String(max(0, value))
        if raw.count >= width {
            return raw
        }
        return String(repeating: "0", count: width - raw.count) + raw
    }

    private struct RestrictionSchedule {
        let daysOfWeekIso: Set<Int>
        let startMinutes: Int
        let endMinutes: Int

        var isValidBasic: Bool {
            !daysOfWeekIso.isEmpty &&
                daysOfWeekIso.allSatisfy { (1...7).contains($0) } &&
                startMinutes >= 0 && startMinutes < 24 * 60 &&
                endMinutes >= 0 && endMinutes < 24 * 60 &&
                startMinutes != endMinutes
        }

        init?(dictionary: [String: Any]) {
            let rawDays = dictionary["daysOfWeekIso"] as? [Any] ?? []
            let days = Set(rawDays.compactMap { value -> Int? in
                if let number = value as? NSNumber {
                    return number.intValue
                }
                if let number = value as? Int {
                    return number
                }
                return nil
            })
            let startValue = dictionary["startMinutes"]
            let endValue = dictionary["endMinutes"]
            let startMinutes = (startValue as? NSNumber)?.intValue ?? (startValue as? Int) ?? -1
            let endMinutes = (endValue as? NSNumber)?.intValue ?? (endValue as? Int) ?? -1
            guard !days.isEmpty,
                  days.allSatisfy({ (1...7).contains($0) }),
                  startMinutes >= 0,
                  startMinutes < 24 * 60,
                  endMinutes >= 0,
                  endMinutes < 24 * 60,
                  startMinutes != endMinutes else {
                return nil
            }
            self.daysOfWeekIso = days
            self.startMinutes = startMinutes
            self.endMinutes = endMinutes
        }
    }

    private struct RestrictionMode {
        let modeId: String
        let schedule: RestrictionSchedule?
        let blockedAppIds: [String]

        init?(dictionary: [String: Any]) {
            let modeId = (dictionary["modeId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modeId.isEmpty else {
                return nil
            }
            let schedule: RestrictionSchedule?
            if let scheduleDictionary = dictionary["schedule"] as? [String: Any] {
                guard let parsed = RestrictionSchedule(dictionary: scheduleDictionary) else {
                    return nil
                }
                schedule = parsed
            } else {
                schedule = nil
            }
            self.modeId = modeId
            self.blockedAppIds = (dictionary["blockedAppIds"] as? [Any] ?? []).compactMap { value in
                guard let raw = value as? String else {
                    return nil
                }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
    }

    private enum ModeSource: String {
        case manual
        case schedule
    }

    private struct ActiveSession {
        let sessionId: String
        let modeId: String
        let blockedAppIds: [String]
        let source: ModeSource

        init?(dictionary: [String: Any]) {
            let sessionId = (dictionary["sessionId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let modeId = (dictionary["modeId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let blockedAppIds = (dictionary["blockedAppIds"] as? [Any] ?? []).compactMap { value -> String? in
                guard let raw = value as? String else {
                    return nil
                }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            let sourceRaw = (dictionary["source"] as? String ?? ModeSource.manual.rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modeId.isEmpty,
                  !blockedAppIds.isEmpty,
                  let source = ModeSource(rawValue: sourceRaw) else {
                return nil
            }
            self.sessionId = sessionId
            self.modeId = modeId
            self.blockedAppIds = blockedAppIds
            self.source = source
        }

        func toDictionary() -> [String: Any] {
            return [
                "sessionId": sessionId,
                "modeId": modeId,
                "blockedAppIds": blockedAppIds,
                "source": source.rawValue,
            ]
        }
    }

    private struct LifecycleSnapshot {
        let isActive: Bool
        let isPaused: Bool
        let modeId: String?
        let source: ModeSource?
        let sessionId: String?
    }

    private struct LifecycleEventDraft {
        let sessionId: String
        let modeId: String
        let action: String
        let source: String
        let reason: String
        let occurredAtEpochMs: Int64
    }

    private struct LifecycleEvent {
        let id: String
        let sessionId: String
        let modeId: String
        let action: String
        let source: String
        let reason: String
        let occurredAtEpochMs: Int64

        init?(
            dictionary: [String: Any]
        ) {
            let id = (dictionary["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let sessionId = (dictionary["sessionId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let modeId = (dictionary["modeId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let action = (dictionary["action"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let source = (dictionary["source"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let reason = (dictionary["reason"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let occurredAtEpochMs: Int64 = {
                if let number = dictionary["occurredAtEpochMs"] as? NSNumber {
                    return number.int64Value
                }
                if let value = dictionary["occurredAtEpochMs"] as? Int64 {
                    return value
                }
                if let value = dictionary["occurredAtEpochMs"] as? Int {
                    return Int64(value)
                }
                return -1
            }()
            guard !id.isEmpty,
                  !sessionId.isEmpty,
                  !modeId.isEmpty,
                  !action.isEmpty,
                  !source.isEmpty,
                  !reason.isEmpty,
                  occurredAtEpochMs > 0 else {
                return nil
            }
            self.id = id
            self.sessionId = sessionId
            self.modeId = modeId
            self.action = action
            self.source = source
            self.reason = reason
            self.occurredAtEpochMs = occurredAtEpochMs
        }

        func toDictionary() -> [String: Any] {
            return [
                "id": id,
                "sessionId": sessionId,
                "modeId": modeId,
                "action": action,
                "source": source,
                "reason": reason,
                "occurredAtEpochMs": occurredAtEpochMs,
            ]
        }
    }

    private func resolvedAppGroupIdentifier() -> String {
        if let fromInfo = Bundle.main.object(forInfoDictionaryKey: appGroupInfoPlistKey) as? String,
           !fromInfo.isEmpty {
            return fromInfo
        }
        if let bundleId = Bundle.main.bundleIdentifier,
           !bundleId.isEmpty {
            return "group.\(bundleId)"
        }
        return "group.com.example.pauza_screen_time"
    }
}
