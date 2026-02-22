import Foundation

struct RestrictionSchedule {
    let daysOfWeekIso: Set<Int>
    let startMinutes: Int
    let endMinutes: Int

    static let minutesPerDay = 24 * 60

    init(daysOfWeekIso: Set<Int>, startMinutes: Int, endMinutes: Int) {
        self.daysOfWeekIso = daysOfWeekIso
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
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

        self.init(
            daysOfWeekIso: days,
            startMinutes: startMinutes,
            endMinutes: endMinutes
        )
    }

    var isValidBasic: Bool {
        !daysOfWeekIso.isEmpty &&
            daysOfWeekIso.allSatisfy { (1...7).contains($0) } &&
            (0..<Self.minutesPerDay).contains(startMinutes) &&
            (0..<Self.minutesPerDay).contains(endMinutes) &&
            startMinutes != endMinutes
    }

    func toDictionary() -> [String: Any] {
        [
            "daysOfWeekIso": daysOfWeekIso.sorted(),
            "startMinutes": startMinutes,
            "endMinutes": endMinutes,
        ]
    }

    init?(channelMap: [String: Any]) {
        self.init(dictionary: channelMap)
    }

    init?(storageMap: [String: Any]) {
        self.init(dictionary: storageMap)
    }

    func toChannelMap() -> [String: Any] {
        return toDictionary()
    }

    func toStorageMap() -> [String: Any] {
        return toDictionary()
    }
}

enum RestrictionScheduleEvaluator {
    static func hasAnySchedule(_ schedules: [RestrictionSchedule]) -> Bool {
        !schedules.isEmpty
    }

    static func isScheduleShapeValid(_ schedules: [RestrictionSchedule]) -> Bool {
        if schedules.isEmpty {
            return true
        }

        var byDay: [Int: [(start: Int, end: Int)]] = [:]
        for schedule in schedules {
            if !schedule.isValidBasic {
                return false
            }
            for day in schedule.daysOfWeekIso {
                if schedule.endMinutes > schedule.startMinutes {
                    byDay[day, default: []].append((schedule.startMinutes, schedule.endMinutes))
                } else {
                    byDay[day, default: []].append((schedule.startMinutes, RestrictionSchedule.minutesPerDay))
                    let nextDay = day == 7 ? 1 : day + 1
                    byDay[nextDay, default: []].append((0, schedule.endMinutes))
                }
            }
        }

        for (_, windows) in byDay {
            let sorted = windows.sorted { lhs, rhs in lhs.start < rhs.start }
            for index in 1..<sorted.count {
                if sorted[index].start < sorted[index - 1].end {
                    return false
                }
            }
        }
        return true
    }

    static func isInScheduleNow(
        enabled: Bool,
        schedules: [RestrictionSchedule],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard enabled, !schedules.isEmpty else {
            return false
        }

        let weekday = isoWeekday(for: now, calendar: calendar)
        let previousDay = weekday == 1 ? 7 : weekday - 1
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let minutesFromMidnight = hour * 60 + minute

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

    static func isoWeekday(for date: Date, calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }
}

struct RestrictionScheduledMode {
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
            guard let parsedSchedule = RestrictionSchedule(dictionary: scheduleDictionary) else {
                return nil
            }
            schedule = parsedSchedule
        } else {
            schedule = nil
        }
        let blocked = (dictionary["blockedAppIds"] as? [Any] ?? []).compactMap { value -> String? in
            guard let raw = value as? String else {
                return nil
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        self.modeId = modeId
        self.schedule = schedule
        self.blockedAppIds = Array(NSOrderedSet(array: blocked)) as? [String] ?? blocked
    }

    func toDictionary() -> [String: Any] {
        [
            "modeId": modeId,
            "schedule": schedule?.toDictionary() as Any,
            "blockedAppIds": blockedAppIds,
        ]
    }

    init?(channelMap: [String: Any]) {
        self.init(dictionary: channelMap)
    }

    init?(storageMap: [String: Any]) {
        self.init(dictionary: storageMap)
    }

    func toChannelMap() -> [String: Any] {
        return [
            "modeId": modeId,
            "schedule": schedule?.toChannelMap() as Any,
            "blockedAppIds": blockedAppIds,
        ]
    }

    func toStorageMap() -> [String: Any] {
        return toChannelMap()
    }

    var shouldPersistForScheduleEnforcement: Bool {
        return schedule != nil && !blockedAppIds.isEmpty
    }

    var isStartable: Bool {
        return !blockedAppIds.isEmpty
    }
}

struct RestrictionScheduledModesConfig {
    let enabled: Bool
    let modes: [RestrictionScheduledMode]

    func toChannelMap() -> [String: Any] {
        return [
            "enabled": enabled,
            "modes": modes.map { $0.toChannelMap() },
        ]
    }
}

struct RestrictionSessionSnapshot {
    let isScheduleEnabled: Bool
    let isInScheduleNow: Bool
    let pausedUntilEpochMs: Int64?
    let activeMode: RestrictionScheduledMode?
    let activeModeSource: RestrictionModeSource
    let currentSessionEvents: [RestrictionLifecycleEvent]

    func toChannelMap() -> [String: Any] {
        return [
            "isScheduleEnabled": isScheduleEnabled,
            "isInScheduleNow": isInScheduleNow,
            "pausedUntilEpochMs": pausedUntilEpochMs as Any,
            "activeMode": activeMode?.toChannelMap() as Any,
            "activeModeSource": activeModeSource.wireValue,
            "currentSessionEvents": currentSessionEvents.map { $0.toChannelMap() },
        ]
    }
}

enum RestrictionModeSource: String {
    case none
    case manual
    case schedule

    var wireValue: String { rawValue }
}

enum RestrictionScheduledModeEvaluator {
    struct Resolution {
        let isInScheduleNow: Bool
        let activeModeId: String?
        let blockedAppIds: [String]
        let activeIntervalEndEpochMs: Int64?
    }

    static func resolveNow(
        config: RestrictionScheduledModesConfig,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Resolution {
        guard config.enabled else {
            return Resolution(
                isInScheduleNow: false,
                activeModeId: nil,
                blockedAppIds: [],
                activeIntervalEndEpochMs: nil
            )
        }
        var matchedMode: RestrictionScheduledMode?
        var matchedEndEpochMs: Int64?
        for mode in config.modes {
            guard let schedule = mode.schedule else {
                continue
            }
            let isInScheduleNow = RestrictionScheduleEvaluator.isInScheduleNow(
                enabled: true,
                schedules: [schedule],
                now: now,
                calendar: calendar
            )
            if !isInScheduleNow {
                continue
            }
            if matchedMode != nil {
                return Resolution(
                    isInScheduleNow: false,
                    activeModeId: nil,
                    blockedAppIds: [],
                    activeIntervalEndEpochMs: nil
                )
            }
            matchedMode = mode
            matchedEndEpochMs = activeIntervalEndEpochMs(for: schedule, now: now, calendar: calendar)
        }
        guard let matchedMode else {
            return Resolution(
                isInScheduleNow: false,
                activeModeId: nil,
                blockedAppIds: [],
                activeIntervalEndEpochMs: nil
            )
        }
        return Resolution(
            isInScheduleNow: true,
            activeModeId: matchedMode.modeId,
            blockedAppIds: matchedMode.blockedAppIds,
            activeIntervalEndEpochMs: matchedEndEpochMs
        )
    }

    private static func activeIntervalEndEpochMs(
        for schedule: RestrictionSchedule,
        now: Date,
        calendar: Calendar
    ) -> Int64? {
        let weekday = RestrictionScheduleEvaluator.isoWeekday(for: now, calendar: calendar)
        let previousDay = weekday == 1 ? 7 : weekday - 1
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minutesFromMidnight = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let startOfToday = calendar.startOfDay(for: now)

        if schedule.endMinutes > schedule.startMinutes {
            guard schedule.daysOfWeekIso.contains(weekday),
                  minutesFromMidnight >= schedule.startMinutes,
                  minutesFromMidnight < schedule.endMinutes else {
                return nil
            }
            guard let endDate = calendar.date(byAdding: .minute, value: schedule.endMinutes, to: startOfToday) else {
                return nil
            }
            return Int64(endDate.timeIntervalSince1970 * 1000)
        }

        if schedule.daysOfWeekIso.contains(weekday),
           minutesFromMidnight >= schedule.startMinutes {
            guard let endBaseDate = calendar.date(byAdding: .day, value: 1, to: startOfToday),
                  let endDate = calendar.date(byAdding: .minute, value: schedule.endMinutes, to: endBaseDate) else {
                return nil
            }
            return Int64(endDate.timeIntervalSince1970 * 1000)
        }

        if schedule.daysOfWeekIso.contains(previousDay),
           minutesFromMidnight < schedule.endMinutes {
            guard let endDate = calendar.date(byAdding: .minute, value: schedule.endMinutes, to: startOfToday) else {
                return nil
            }
            return Int64(endDate.timeIntervalSince1970 * 1000)
        }

        return nil
    }
}
