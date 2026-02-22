import DeviceActivity
import Foundation

@available(iOS 16.0, *)
enum PendingEndSessionMonitor {
    static let activityNameRaw = "pauza_pending_end_session"
    static let activityName = DeviceActivityName(activityNameRaw)

    enum MonitorError: Error {
        case invalidInterval
        case missingDateComponents
    }

    static func startMonitoring(untilEpochMs: Int64, nowEpochMs: Int64 = RestrictionStateStore.currentEpochMs()) throws {
        guard untilEpochMs > nowEpochMs else {
            throw MonitorError.invalidInterval
        }

        let calendar = Calendar.current
        let nowDate = Date(timeIntervalSince1970: TimeInterval(nowEpochMs) / 1000.0)
        let untilDate = Date(timeIntervalSince1970: TimeInterval(untilEpochMs) / 1000.0)

        let startComponents = dateComponents(for: nowDate, calendar: calendar)
        let endComponents = dateComponents(for: untilDate, calendar: calendar)
        guard startComponents.year != nil,
              endComponents.year != nil else {
            throw MonitorError.missingDateComponents
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )
        try DeviceActivityCenter().startMonitoring(activityName, during: schedule)
    }

    static func stopMonitoring() {
        DeviceActivityCenter().stopMonitoring([activityName])
    }

    private static func dateComponents(for date: Date, calendar: Calendar) -> DateComponents {
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }
}
