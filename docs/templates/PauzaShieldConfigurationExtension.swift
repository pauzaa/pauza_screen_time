import FamilyControls
import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

@available(iOSApplicationExtension 16.0, *)
final class PauzaShieldConfigurationExtension: ShieldConfigurationDataSource {
    private let appGroupInfoPlistKey = "AppGroupIdentifier"
    private let configurationKey = "shieldConfiguration"

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let payload = loadConfigurationPayload()
        return ShieldConfiguration(
            backgroundBlurStyle: blurStyle(from: payload["backgroundBlurStyle"]),
            backgroundColor: color(from: payload["backgroundColor"], fallback: UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)),
            icon: icon(from: payload["iconBytes"]),
            title: ShieldConfiguration.Label(
                text: text(from: payload["title"], fallback: "Restricted"),
                color: color(from: payload["titleColor"], fallback: .white)
            ),
            subtitle: optionalLabel(
                text: payload["subtitle"],
                color: color(from: payload["subtitleColor"], fallback: .white)
            ),
            primaryButtonLabel: optionalLabel(
                text: payload["primaryButtonLabel"],
                color: color(from: payload["primaryButtonTextColor"], fallback: .white)
            ),
            primaryButtonBackgroundColor: optionalColor(from: payload["primaryButtonBackgroundColor"]),
            secondaryButtonLabel: optionalLabel(
                text: payload["secondaryButtonLabel"],
                color: color(from: payload["secondaryButtonTextColor"], fallback: .white)
            )
        )
    }

    private func loadConfigurationPayload() -> [String: Any] {
        guard let defaults = UserDefaults(suiteName: resolvedAppGroupIdentifier()) else {
            return [:]
        }
        return defaults.dictionary(forKey: configurationKey) ?? [:]
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

    private func text(from value: Any?, fallback: String) -> String {
        guard let raw = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return fallback
        }
        return raw
    }

    private func optionalLabel(text value: Any?, color: UIColor) -> ShieldConfiguration.Label? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return ShieldConfiguration.Label(text: text, color: color)
    }

    private func optionalColor(from value: Any?) -> UIColor? {
        guard value != nil else {
            return nil
        }
        return color(from: value, fallback: nil)
    }

    private func color(from value: Any?, fallback: UIColor?) -> UIColor {
        guard let intValue = intValue(from: value) else {
            return fallback ?? UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        }

        let argb = UInt32(bitPattern: Int32(truncatingIfNeeded: intValue))
        let alpha = CGFloat((argb >> 24) & 0xFF) / 255.0
        let red = CGFloat((argb >> 16) & 0xFF) / 255.0
        let green = CGFloat((argb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(argb & 0xFF) / 255.0
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private func intValue(from value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let intValue = value as? Int {
            return intValue
        }
        return nil
    }

    private func icon(from value: Any?) -> UIImage? {
        if let data = value as? Data {
            return UIImage(data: data)
        }
        if let bytes = value as? [UInt8] {
            return UIImage(data: Data(bytes))
        }
        return nil
    }

    private func blurStyle(from value: Any?) -> UIBlurEffect.Style? {
        guard let rawValue = value as? String else {
            return nil
        }
        switch rawValue {
        case "extraLight":
            return .extraLight
        case "light":
            return .light
        case "dark":
            return .dark
        case "regular":
            return .regular
        case "prominent":
            return .prominent
        default:
            return nil
        }
    }
}
