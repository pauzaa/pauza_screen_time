import Foundation

struct RestrictionCachedMode {
    let modeId: String
    let isEnabled: Bool
    let blockedAppIds: [String]
}

enum RestrictionModeUpsertCache {
    private static var order: [String] = []
    private static var modes: [String: RestrictionCachedMode] = [:]
    private static let maxEntries = 50
    private static let lock = NSLock()

    static func upsert(_ mode: RestrictionCachedMode) {
        lock.lock()
        defer { lock.unlock() }
        modes[mode.modeId] = mode
        order.removeAll { $0 == mode.modeId }
        order.append(mode.modeId)
        while order.count > maxEntries {
            let evicted = order.removeFirst()
            modes.removeValue(forKey: evicted)
        }
    }

    static func get(modeId: String) -> RestrictionCachedMode? {
        lock.lock()
        defer { lock.unlock() }
        guard let mode = modes[modeId] else {
            return nil
        }
        order.removeAll { $0 == modeId }
        order.append(modeId)
        return mode
    }

    static func remove(modeId: String) {
        lock.lock()
        defer { lock.unlock() }
        modes.removeValue(forKey: modeId)
        order.removeAll { $0 == modeId }
    }
}
