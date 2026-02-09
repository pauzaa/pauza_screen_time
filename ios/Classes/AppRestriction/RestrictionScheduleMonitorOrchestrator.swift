import DeviceActivity
import Foundation

@available(iOS 16.0, *)
enum RestrictionScheduleMonitorOrchestrator {
    private static let monitorPrefix = "pauza.schedule.mode."

    static func rescheduleMonitors() throws {
        let center = DeviceActivityCenter()

        let existing = RestrictionStateStore.loadScheduleMonitorNames()
        for name in existing {
            center.stopMonitoring(DeviceActivityName(name))
        }

        let modes = RestrictionStateStore.loadModes()
        let schedules = modes.filter { $0.isEnabled }.compactMap { $0.schedule }
        let enabled = RestrictionStateStore.loadModesEnabled()

        guard enabled else {
            _ = RestrictionStateStore.storeScheduleMonitorNames([])
            return
        }

        let validSchedules = schedules.filter(\.isValidBasic)
        var names: [String] = []
        names.reserveCapacity(validSchedules.count)

        for (index, schedule) in validSchedules.enumerated() {
            let nameRaw = "\(monitorPrefix)\(index)"
            let name = DeviceActivityName(nameRaw)
            let eventName = DeviceActivityEvent.Name("\(nameRaw).event")
            let scheduleConfig = makeDeviceActivitySchedule(from: schedule)
            let events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [
                eventName: DeviceActivityEvent(
                    applications: [],
                    categories: .all,
                    threshold: DateComponents(minute: 1)
                ),
            ]
            try center.startMonitoring(name, during: scheduleConfig, events: events)
            names.append(nameRaw)
        }

        _ = RestrictionStateStore.storeScheduleMonitorNames(names)
    }

    private static func makeDeviceActivitySchedule(from schedule: RestrictionSchedule) -> DeviceActivitySchedule {
        var start = DateComponents()
        start.hour = schedule.startMinutes / 60
        start.minute = schedule.startMinutes % 60

        var end = DateComponents()
        end.hour = schedule.endMinutes / 60
        end.minute = schedule.endMinutes % 60

        if schedule.endMinutes > schedule.startMinutes {
            return DeviceActivitySchedule(
                intervalStart: start,
                intervalEnd: end,
                repeats: true,
                warningTime: nil
            )
        }

        return DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: true,
            warningTime: nil
        )
    }
}
