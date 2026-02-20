import Foundation
import Flutter

struct LifecycleEventsUseCase {
    static let featureRestrictions = "restrictions"

    static func ackLifecycleEvents(throughEventId: String) -> FlutterError? {
        let ackResult = RestrictionStateStore.ackLifecycleEvents(throughEventId: throughEventId)
        switch ackResult {
        case .success:
            return nil
        case .appGroupUnavailable(let resolvedGroupId):
            return PluginErrors.internalFailure(
                feature: featureRestrictions,
                action: MethodNames.ackLifecycleEvents,
                message: PluginErrorMessage.appGroupUnavailable,
                diagnostic: "resolvedAppGroupId=\(resolvedGroupId)"
            )
        }
    }
}
