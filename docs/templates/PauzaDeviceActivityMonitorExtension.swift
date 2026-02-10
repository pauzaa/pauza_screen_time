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
    private let modesEnabledKey = "modesEnabled"
    private let modesKey = "modes"

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity == pauseActivityName || activity.rawValue.hasPrefix(scheduleActivityPrefix) else {
            return
        }

        if activity.rawValue.hasPrefix(scheduleActivityPrefix),
           let defaults = UserDefaults(suiteName: resolvedAppGroupIdentifier()),
           let mode = scheduledModeForActivity(activity, defaults: defaults) {
            defaults.set(
                ActiveSession(modeId: mode.modeId, blockedAppIds: mode.blockedAppIds, source: .schedule).toDictionary(),
                forKey: activeSessionKey
            )
        }

        applyEnforcementStateIfNeeded()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == pauseActivityName || activity.rawValue.hasPrefix(scheduleActivityPrefix) else {
            return
        }

        if activity.rawValue.hasPrefix(scheduleActivityPrefix),
           let defaults = UserDefaults(suiteName: resolvedAppGroupIdentifier()),
           let mode = scheduledModeForActivity(activity, defaults: defaults),
           let activeSession = loadActiveSession(defaults: defaults),
           activeSession.source == .schedule,
           activeSession.modeId == mode.modeId {
            defaults.removeObject(forKey: activeSessionKey)
        }

        applyEnforcementStateIfNeeded()
    }

    private func applyEnforcementStateIfNeeded() {
        guard let defaults = UserDefaults(suiteName: resolvedAppGroupIdentifier()) else {
            return
        }

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
        guard defaults.bool(forKey: modesEnabledKey) else {
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
        guard let session = ActiveSession(dictionary: raw) else {
            defaults.removeObject(forKey: activeSessionKey)
            return nil
        }
        return session
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
        let modeId: String
        let blockedAppIds: [String]
        let source: ModeSource

        init?(dictionary: [String: Any]) {
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
            self.modeId = modeId
            self.blockedAppIds = blockedAppIds
            self.source = source
        }

        func toDictionary() -> [String: Any] {
            return [
                "modeId": modeId,
                "blockedAppIds": blockedAppIds,
                "source": source.rawValue,
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
