import Foundation
import UIKit
import ManagedSettings
import ManagedSettingsUI
import FamilyControls

/// Provides the shield appearance for the iOS ShieldConfiguration extension.
@available(iOSApplicationExtension 16.0, *)
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let config = ShieldConfigurationPayload.load()
        return config.toShieldConfiguration()
    }
}

@available(iOSApplicationExtension 16.0, *)
private struct ShieldConfigurationPayload {
    let title: String
    let subtitle: String?
    let backgroundColor: UIColor
    let titleColor: UIColor
    let subtitleColor: UIColor
    let backgroundBlurStyle: UIBlurEffect.Style?
    let icon: UIImage?
    let primaryButtonLabel: ShieldConfiguration.Label?
    let primaryButtonBackgroundColor: UIColor?
    let secondaryButtonLabel: ShieldConfiguration.Label?

    static func load(appGroupId: String? = nil) -> ShieldConfigurationPayload {
        let stored = ShieldConfigurationStore.loadConfiguration(appGroupId: appGroupId)?.toStorageMap() ?? [:]
        return fromDictionary(stored)
    }

    static func fromDictionary(_ dictionary: [String: Any]) -> ShieldConfigurationPayload {
        let title = (dictionary["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = (dictionary["subtitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let backgroundColor = color(from: dictionary["backgroundColor"], fallback: defaultBackgroundColor)
        let titleColor = color(from: dictionary["titleColor"], fallback: defaultTitleColor)
        let subtitleColor = color(from: dictionary["subtitleColor"], fallback: defaultSubtitleColor)
        let blurStyle = blurStyle(from: dictionary["backgroundBlurStyle"])
        let icon = image(from: dictionary["iconBytes"])

        let primaryLabelText = (dictionary["primaryButtonLabel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryTextColor = color(from: dictionary["primaryButtonTextColor"], fallback: defaultPrimaryTextColor)
        let primaryLabel = label(text: primaryLabelText, color: primaryTextColor)
        let primaryButtonBackgroundColor = colorOptional(from: dictionary["primaryButtonBackgroundColor"])

        let secondaryLabelText = (dictionary["secondaryButtonLabel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondaryTextColor = color(from: dictionary["secondaryButtonTextColor"], fallback: defaultSecondaryTextColor)
        let secondaryLabel = label(text: secondaryLabelText, color: secondaryTextColor)

        return ShieldConfigurationPayload(
            title: title?.isEmpty == false ? title! : defaultTitle,
            subtitle: subtitle?.isEmpty == false ? subtitle : nil,
            backgroundColor: backgroundColor,
            titleColor: titleColor,
            subtitleColor: subtitleColor,
            backgroundBlurStyle: blurStyle,
            icon: icon,
            primaryButtonLabel: primaryLabel,
            primaryButtonBackgroundColor: primaryButtonBackgroundColor,
            secondaryButtonLabel: secondaryLabel
        )
    }

    func toShieldConfiguration() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: backgroundBlurStyle,
            backgroundColor: backgroundColor,
            icon: icon,
            title: ShieldConfiguration.Label(text: title, color: titleColor),
            subtitle: Self.label(text: subtitle, color: subtitleColor),
            primaryButtonLabel: primaryButtonLabel,
            primaryButtonBackgroundColor: primaryButtonBackgroundColor,
            secondaryButtonLabel: secondaryButtonLabel
        )
    }

    private static func label(text: String?, color: UIColor) -> ShieldConfiguration.Label? {
        guard let text, !text.isEmpty else {
            return nil
        }
        return ShieldConfiguration.Label(text: text, color: color)
    }

    private static func image(from value: Any?) -> UIImage? {
        if let data = value as? Data {
            return UIImage(data: data)
        }
        if let bytes = value as? [UInt8] {
            return UIImage(data: Data(bytes))
        }
        return nil
    }

    private static func blurStyle(from value: Any?) -> UIBlurEffect.Style? {
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

    private static func colorOptional(from value: Any?) -> UIColor? {
        guard let value else {
            return nil
        }
        return color(from: value, fallback: nil)
    }

    private static func color(from value: Any?, fallback: UIColor?) -> UIColor {
        guard let intValue = intValue(from: value) else {
            return fallback ?? defaultBackgroundColor
        }
        return colorFromARGB(intValue)
    }

    private static func intValue(from value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let intValue = value as? Int {
            return intValue
        }
        return nil
    }

    private static func colorFromARGB(_ value: Int) -> UIColor {
        let argb = UInt32(bitPattern: Int32(truncatingIfNeeded: value))
        let alpha = CGFloat((argb >> 24) & 0xFF) / 255.0
        let red = CGFloat((argb >> 16) & 0xFF) / 255.0
        let green = CGFloat((argb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(argb & 0xFF) / 255.0
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static let defaultTitle = "Restricted"
    private static let defaultBackgroundColor = colorFromARGB(0xFF1A1A2E)
    private static let defaultTitleColor = colorFromARGB(0xFFFFFFFF)
    private static let defaultSubtitleColor = colorFromARGB(0xFFB0B0B0)
    private static let defaultPrimaryTextColor = colorFromARGB(0xFFFFFFFF)
    private static let defaultSecondaryTextColor = colorFromARGB(0xFFFFFFFF)
}
