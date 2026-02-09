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
    private let manualActiveModeKey = "manualActiveMode"
    private let modesEnabledKey = "modesEnabled"
    private let modesKey = "modes"

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity == pauseActivityName || activity.rawValue.hasPrefix(scheduleActivityPrefix) else {
            return
        }
        applyEnforcementStateIfNeeded()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == pauseActivityName || activity.rawValue.hasPrefix(scheduleActivityPrefix) else {
            return
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

        let sessionState = resolveSessionState(defaults: defaults)
        guard sessionState.activeModeSource != .none,
              !sessionState.blockedAppIds.isEmpty else {
            clearRestrictions()
            return
        }

        let decodedTokens = decodeTokens(sessionState.blockedAppIds)
        if decodedTokens.count != sessionState.blockedAppIds.count {
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

    private func resolveSessionState(defaults: UserDefaults) -> SessionState {
        let modes = loadModes(defaults: defaults)
        let modesEnabled = defaults.bool(forKey: modesEnabledKey)
        let manualMode = loadManualMode(defaults: defaults)

        let scheduleState = resolveFromScheduledModes(enabled: modesEnabled, modes: modes)

        if let manualMode {
            return SessionState(
                activeModeSource: .manual,
                blockedAppIds: manualMode.blockedAppIds
            )
        }

        if scheduleState.isInScheduleNow {
            return SessionState(
                activeModeSource: .schedule,
                blockedAppIds: scheduleState.blockedAppIds
            )
        }

        return SessionState(activeModeSource: .none, blockedAppIds: [])
    }

    private func loadManualMode(defaults: UserDefaults) -> RestrictionMode? {
        if let raw = defaults.dictionary(forKey: manualActiveModeKey) {
            return RestrictionMode(dictionary: raw)
        }
        return nil
    }

    private func resolveFromScheduledModes(enabled: Bool, modes: [RestrictionMode]) -> ScheduleState {
        guard enabled else {
            return ScheduleState(isInScheduleNow: false, blockedAppIds: [])
        }
        let activeModes = modes.filter { mode in
            guard mode.isEnabled, let schedule = mode.schedule else {
                return false
            }
            return isInScheduleNow(schedules: [schedule], enabled: true)
        }
        guard activeModes.count == 1 else {
            return ScheduleState(isInScheduleNow: false, blockedAppIds: [])
        }
        return ScheduleState(isInScheduleNow: true, blockedAppIds: activeModes[0].blockedAppIds)
    }

    private func isInScheduleNow(schedules: [RestrictionSchedule], enabled: Bool) -> Bool {
        guard enabled, !schedules.isEmpty else {
            return false
        }
        let calendar = Calendar.current
        let now = Date()
        let weekday = isoWeekday(for: now, calendar: calendar)
        let previousDay = weekday == 1 ? 7 : weekday - 1
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minutesFromMidnight = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)

        for schedule in schedules {
            if schedule.endMinutes > schedule.startMinutes {
                if schedule.daysOfWeekIso.contains(weekday) &&
                    minutesFromMidnight >= schedule.startMinutes &&
                    minutesFromMidnight < schedule.endMinutes {
                    return true
                }
            } else {
                if schedule.daysOfWeekIso.contains(weekday) &&
                    minutesFromMidnight >= schedule.startMinutes {
                    return true
                }
                if schedule.daysOfWeekIso.contains(previousDay) &&
                    minutesFromMidnight < schedule.endMinutes {
                    return true
                }
            }
        }

        return false
    }

    private func isoWeekday(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    private struct RestrictionSchedule {
        let daysOfWeekIso: Set<Int>
        let startMinutes: Int
        let endMinutes: Int

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
        let isEnabled: Bool
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
            self.isEnabled = dictionary["isEnabled"] as? Bool ?? true
            self.blockedAppIds = (dictionary["blockedAppIds"] as? [Any] ?? []).compactMap { value in
                guard let raw = value as? String else {
                    return nil
                }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
    }

    private enum ModeSource {
        case none
        case manual
        case schedule
    }

    private struct SessionState {
        let activeModeSource: ModeSource
        let blockedAppIds: [String]
    }

    private struct ScheduleState {
        let isInScheduleNow: Bool
        let blockedAppIds: [String]
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
