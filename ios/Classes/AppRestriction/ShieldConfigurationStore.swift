import Foundation

struct ShieldConfigurationStoragePayload {
    let title: String?
    let subtitle: String?
    let backgroundColor: Int?
    let titleColor: Int?
    let subtitleColor: Int?
    let backgroundBlurStyle: String?
    let iconBytes: Data?
    let primaryButtonLabel: String?
    let primaryButtonBackgroundColor: Int?
    let primaryButtonTextColor: Int?
    let secondaryButtonLabel: String?
    let secondaryButtonTextColor: Int?

    static func fromChannelMap(_ map: [String: Any]) -> ShieldConfigurationStoragePayload {
        return ShieldConfigurationStoragePayload(
            title: map["title"] as? String,
            subtitle: map["subtitle"] as? String,
            backgroundColor: number(from: map["backgroundColor"]),
            titleColor: number(from: map["titleColor"]),
            subtitleColor: number(from: map["subtitleColor"]),
            backgroundBlurStyle: map["backgroundBlurStyle"] as? String,
            iconBytes: map["iconBytes"] as? Data,
            primaryButtonLabel: map["primaryButtonLabel"] as? String,
            primaryButtonBackgroundColor: number(from: map["primaryButtonBackgroundColor"]),
            primaryButtonTextColor: number(from: map["primaryButtonTextColor"]),
            secondaryButtonLabel: map["secondaryButtonLabel"] as? String,
            secondaryButtonTextColor: number(from: map["secondaryButtonTextColor"])
        )
    }

    static func fromStorageMap(_ map: [String: Any]) -> ShieldConfigurationStoragePayload {
        return fromChannelMap(map)
    }

    func toStorageMap() -> [String: Any] {
        var result: [String: Any] = [:]
        if let title { result["title"] = title }
        if let subtitle { result["subtitle"] = subtitle }
        if let backgroundColor { result["backgroundColor"] = backgroundColor }
        if let titleColor { result["titleColor"] = titleColor }
        if let subtitleColor { result["subtitleColor"] = subtitleColor }
        if let backgroundBlurStyle { result["backgroundBlurStyle"] = backgroundBlurStyle }
        if let iconBytes { result["iconBytes"] = iconBytes }
        if let primaryButtonLabel { result["primaryButtonLabel"] = primaryButtonLabel }
        if let primaryButtonBackgroundColor { result["primaryButtonBackgroundColor"] = primaryButtonBackgroundColor }
        if let primaryButtonTextColor { result["primaryButtonTextColor"] = primaryButtonTextColor }
        if let secondaryButtonLabel { result["secondaryButtonLabel"] = secondaryButtonLabel }
        if let secondaryButtonTextColor { result["secondaryButtonTextColor"] = secondaryButtonTextColor }
        return result
    }

    private static func number(from value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        return value as? Int
    }
}

/// Stores shield configuration for the ShieldConfiguration extension.
enum ShieldConfigurationStore {
    static let configurationKey = "shieldConfiguration"

    enum StoreResult {
        case success
        case appGroupUnavailable(resolvedGroupId: String)
    }

    @discardableResult
    static func storeConfiguration(_ configuration: ShieldConfigurationStoragePayload, appGroupId: String? = nil) -> StoreResult {
        let resolvedGroupId = AppGroupStore.effectiveGroupIdentifier(appGroupId)
        guard let defaults = UserDefaults(suiteName: resolvedGroupId) else {
            return .appGroupUnavailable(resolvedGroupId: resolvedGroupId)
        }
        defaults.set(configuration.toStorageMap(), forKey: configurationKey)
        return .success
    }

    static func loadConfiguration(appGroupId: String? = nil) -> ShieldConfigurationStoragePayload? {
        guard let defaults = AppGroupStore.sharedDefaults(groupId: appGroupId) else {
            return nil
        }
        guard let raw = defaults.dictionary(forKey: configurationKey) else {
            return nil
        }
        return ShieldConfigurationStoragePayload.fromStorageMap(raw)
    }
}
