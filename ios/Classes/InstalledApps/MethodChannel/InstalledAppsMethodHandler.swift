import Flutter
import UIKit

final class InstalledAppsMethodHandler {
    private let feature = "installed_apps"

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case MethodNames.showFamilyActivityPicker:
            handleShowFamilyActivityPicker(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleShowFamilyActivityPicker(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.0, *) else {
            // Propagate a typed UNSUPPORTED error rather than a silent empty list.
            LegacyFamilyActivityPickerHandler.shared.showPicker(
                feature: feature,
                action: MethodNames.showFamilyActivityPicker,
                flutterResult: result
            )
            return
        }

        guard let viewController = getPresentationViewController() else {
            result(PluginErrors.internalFailure(
                feature: feature,
                action: MethodNames.showFamilyActivityPicker,
                message: PluginErrorMessage.viewControllerUnavailable
            ))
            return
        }

        var preSelectedTokens: [String]? = nil
        if let args = call.arguments as? [String: Any],
           let tokens = args["preSelectedTokens"] as? [String] {
            preSelectedTokens = tokens
        }

        FamilyActivityPickerHandler.shared.showPicker(
            from: viewController,
            preSelectedTokens: preSelectedTokens
        ) { [feature = self.feature] pickerResult in
            switch pickerResult {
            case .success(let selectedApps):
                result(selectedApps)
            case .failure(let error):
                result(PluginErrors.internalFailure(
                    feature: feature,
                    action: MethodNames.showFamilyActivityPicker,
                    message: "Failed to process app selection: \(error.localizedDescription)",
                    diagnostic: String(describing: error)
                ))
            }
        }
    }

    private func getPresentationViewController() -> UIViewController? {
        if #available(iOS 13.0, *) {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { scene in
                    scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive
                }

            for scene in scenes {
                if let root = (scene.windows.first(where: { $0.isKeyWindow }) ??
                               scene.windows.first(where: { !$0.isHidden }) ??
                               scene.windows.first)?.rootViewController {
                    return topMostViewController(from: root)
                }
            }

            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                if let root = scene.windows.first?.rootViewController {
                    return topMostViewController(from: root)
                }
            }
            return nil
        } else {
            return topMostViewController(from: UIApplication.shared.keyWindow?.rootViewController)
        }
    }

    private func topMostViewController(from root: UIViewController?) -> UIViewController? {
        var current = root
        while let presented = current?.presentedViewController {
            current = presented
        }
        return current
    }
}
