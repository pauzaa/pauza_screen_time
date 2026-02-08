import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

@available(iOSApplicationExtension 16.0, *)
final class PauzaDeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let store = ManagedSettingsStore()

    private let pauseActivityName = DeviceActivityName("pauza_pause_auto_resume")
    private let appGroupInfoPlistKey = "AppGroupIdentifier"
    private let desiredRestrictedAppsKey = "desiredRestrictedApps"
    private let pausedUntilEpochMsKey = "pausedUntilEpochMs"

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity == pauseActivityName else {
            return
        }
        applyDesiredRestrictionsIfNeeded()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == pauseActivityName else {
            return
        }
        applyDesiredRestrictionsIfNeeded()
    }

    private func applyDesiredRestrictionsIfNeeded() {
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

        let desiredTokens = defaults.array(forKey: desiredRestrictedAppsKey) as? [String] ?? []
        if desiredTokens.isEmpty {
            clearRestrictions()
            return
        }

        let decodedTokens = decodeTokens(desiredTokens)
        if decodedTokens.count != desiredTokens.count {
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
