import DeviceActivity
import Foundation

@available(iOS 16.0, *)
enum PendingEndSessionMonitor {
    static let activityNameRaw = "pauza_pending_end_session"
    static let activityName = DeviceActivityName(activityNameRaw)

    static func startMonitoring(untilEpochMs: Int64, nowEpochMs: Int64 = RestrictionStateStore.currentEpochMs()) throws {
        try ActivityMonitorBase.startMonitoring(name: activityName, untilEpochMs: untilEpochMs, nowEpochMs: nowEpochMs)
    }

    static func stopMonitoring() {
        ActivityMonitorBase.stopMonitoring(name: activityName)
    }
}
