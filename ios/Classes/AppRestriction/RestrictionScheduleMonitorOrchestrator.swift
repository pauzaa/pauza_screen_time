import DeviceActivity
import Foundation

@available(iOS 16.0, *)
enum RestrictionScheduleMonitorOrchestrator {
    private static let scheduleActivityPrefix = "pauza_schedule_"

    static func rescheduleMonitors() throws {
        let center = DeviceActivityCenter()
        let previousNames = RestrictionStateStore.loadScheduleMonitorNames()
        if !previousNames.isEmpty {
            center.stopMonitoring(Set(previousNames.map(DeviceActivityName.init)))
        }

        let scheduledModes = RestrictionStateStore.loadScheduledModes()
        let schedules: [RestrictionSchedule]
        let scheduleEnabled: Bool
        if !scheduledModes.isEmpty {
            schedules = scheduledModes.filter { $0.isEnabled }.map { $0.schedule }
            scheduleEnabled = RestrictionStateStore.loadScheduledModesEnabled()
        } else {
            schedules = RestrictionStateStore.loadRestrictionSchedules()
            scheduleEnabled = enabled
        }
        guard scheduleEnabled, !schedules.isEmpty else {
            _ = RestrictionStateStore.storeScheduleMonitorNames([])
            return
        }

        var createdNames: [String] = []
        let calendar = Calendar.current

        for (index, schedule) in schedules.enumerated() {
            let segments = splitSchedule(schedule)
            for (segmentIndex, segment) in segments.enumerated() {
                let activityNameRaw = "\(scheduleActivityPrefix)\(index)_\(segmentIndex)_\(segment.day)"
                let activityName = DeviceActivityName(activityNameRaw)
                let startComponents = dateComponents(
                    weekdayIso: segment.day,
                    minutesFromMidnight: segment.startMinutes,
                    calendar: calendar
                )
                let endDay = segment.endMinutes == RestrictionSchedule.minutesPerDay
                    ? (segment.day == 7 ? 1 : segment.day + 1)
                    : segment.day
                let endMinutes = segment.endMinutes == RestrictionSchedule.minutesPerDay ? 0 : segment.endMinutes
                let endComponents = dateComponents(
                    weekdayIso: endDay,
                    minutesFromMidnight: endMinutes,
                    calendar: calendar
                )
                let scheduleConfig = DeviceActivitySchedule(
                    intervalStart: startComponents,
                    intervalEnd: endComponents,
                    repeats: true
                )
                try center.startMonitoring(activityName, during: scheduleConfig)
                createdNames.append(activityNameRaw)
            }
        }

        _ = RestrictionStateStore.storeScheduleMonitorNames(createdNames)
    }

    private static func splitSchedule(_ schedule: RestrictionSchedule) -> [(day: Int, startMinutes: Int, endMinutes: Int)] {
        if schedule.endMinutes > schedule.startMinutes {
            return schedule.daysOfWeekIso.map { day in
                (day: day, startMinutes: schedule.startMinutes, endMinutes: schedule.endMinutes)
            }
        }

        var segments: [(day: Int, startMinutes: Int, endMinutes: Int)] = []
        for day in schedule.daysOfWeekIso {
            segments.append((day: day, startMinutes: schedule.startMinutes, endMinutes: RestrictionSchedule.minutesPerDay))
            let nextDay = day == 7 ? 1 : day + 1
            segments.append((day: nextDay, startMinutes: 0, endMinutes: schedule.endMinutes))
        }
        return segments
    }

    private static func dateComponents(
        weekdayIso: Int,
        minutesFromMidnight: Int,
        calendar: Calendar
    ) -> DateComponents {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.weekday = isoToCalendarWeekday(weekdayIso)
        components.hour = minutesFromMidnight / 60
        components.minute = minutesFromMidnight % 60
        components.second = 0
        return components
    }

    private static func isoToCalendarWeekday(_ isoDay: Int) -> Int {
        isoDay == 7 ? 1 : isoDay + 1
    }
}
