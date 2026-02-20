import Foundation
import Flutter

struct ConfigureShieldUseCase {
    static let featureRestrictions = "restrictions"

    static func execute(configuration: [String: Any]) -> FlutterError? {
        var mutableConfig = configuration
        let appGroupId = mutableConfig["appGroupId"] as? String
        AppGroupStore.updateGroupIdentifier(appGroupId)
        mutableConfig.removeValue(forKey: "appGroupId")

        if let typedData = mutableConfig["iconBytes"] as? FlutterStandardTypedData {
            mutableConfig["iconBytes"] = typedData.data
        } else if mutableConfig["iconBytes"] is NSNull {
            mutableConfig.removeValue(forKey: "iconBytes")
        }

        let payload = ShieldConfigurationStoragePayload.fromChannelMap(mutableConfig)
        switch ShieldConfigurationStore.storeConfiguration(payload, appGroupId: appGroupId) {
        case .success:
            return nil
        case .appGroupUnavailable(let resolvedGroupId):
            var diagnostic = "Unable to access App Group for shield configuration. resolvedAppGroupId=\(resolvedGroupId)"
            if let appGroupId {
                diagnostic += ", appGroupId=\(appGroupId)"
            }
            return PluginErrors.internalFailure(
                feature: featureRestrictions,
                action: MethodNames.configureShield,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: diagnostic
            )
        }
    }
}
