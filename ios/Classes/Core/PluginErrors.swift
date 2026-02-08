import Flutter

enum PluginErrorCode {
    static let invalidArguments = "INVALID_ARGUMENT"
    static let missingPermission = "MISSING_PERMISSION"
    static let permissionDenied = "PERMISSION_DENIED"
    static let systemRestricted = "SYSTEM_RESTRICTED"
    static let internalFailure = "INTERNAL_FAILURE"
    static let unsupported = "UNSUPPORTED"
}

enum PluginErrorMessage {
    static let missingPermissionKey = "Missing or invalid 'permissionKey' argument"
    static let missingIdentifiers = "Missing or invalid 'identifiers' argument"
    static let missingIdentifier = "Missing or invalid 'identifier' argument"
    static let missingShieldConfiguration = "Missing or invalid shield configuration"
    static let unableToDecodeToken = "Unable to decode application token"
    static let unableToDecodeTokens = "Unable to decode application token(s)"
    static let appGroupUnavailable = "Unable to access App Group for shield configuration"
    static let settingsUrlCreationFailed = "Could not create settings URL"
    static let settingsOpenFailed = "Failed to open settings"
    static let settingsCannotOpen = "Cannot open settings URL"
    static let viewControllerUnavailable = "Could not get root view controller"
    static let restrictionsUnsupported = "App restrictions require iOS 16.0 or later"
    static let usageStatsUnsupported = "Usage stats are only supported on Android. On iOS, use DeviceActivityReport platform view for usage statistics."
    static let pauseTooLong = "Pause duration must be less than 24 hours on iOS"
    static let pauseMonitoringStartFailed = "Failed to schedule reliable pause auto-resume. Configure a Device Activity Monitor extension and shared App Group."
}

enum PluginErrors {
    static func invalidArguments(
        feature: String,
        action: String,
        message: String,
        diagnostic: String? = nil
    ) -> FlutterError {
        FlutterError(
            code: PluginErrorCode.invalidArguments,
            message: message,
            details: details(feature: feature, action: action, diagnostic: diagnostic)
        )
    }

    static func unsupported(
        feature: String,
        action: String,
        message: String,
        diagnostic: String? = nil
    ) -> FlutterError {
        FlutterError(
            code: PluginErrorCode.unsupported,
            message: message,
            details: details(feature: feature, action: action, diagnostic: diagnostic)
        )
    }

    static func missingPermission(
        feature: String,
        action: String,
        message: String,
        missing: [String]? = nil,
        status: [String: Any]? = nil,
        diagnostic: String? = nil
    ) -> FlutterError {
        FlutterError(
            code: PluginErrorCode.missingPermission,
            message: message,
            details: details(
                feature: feature,
                action: action,
                missing: missing,
                status: status,
                diagnostic: diagnostic
            )
        )
    }

    static func permissionDenied(
        feature: String,
        action: String,
        message: String,
        missing: [String]? = nil,
        status: [String: Any]? = nil,
        diagnostic: String? = nil
    ) -> FlutterError {
        FlutterError(
            code: PluginErrorCode.permissionDenied,
            message: message,
            details: details(
                feature: feature,
                action: action,
                missing: missing,
                status: status,
                diagnostic: diagnostic
            )
        )
    }

    static func systemRestricted(
        feature: String,
        action: String,
        message: String,
        missing: [String]? = nil,
        status: [String: Any]? = nil,
        diagnostic: String? = nil
    ) -> FlutterError {
        FlutterError(
            code: PluginErrorCode.systemRestricted,
            message: message,
            details: details(
                feature: feature,
                action: action,
                missing: missing,
                status: status,
                diagnostic: diagnostic
            )
        )
    }

    static func internalFailure(
        feature: String,
        action: String,
        message: String,
        diagnostic: String? = nil
    ) -> FlutterError {
        FlutterError(
            code: PluginErrorCode.internalFailure,
            message: message,
            details: details(feature: feature, action: action, diagnostic: diagnostic)
        )
    }

    private static func details(
        feature: String,
        action: String,
        missing: [String]? = nil,
        status: [String: Any]? = nil,
        diagnostic: String? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "feature": feature,
            "action": action,
            "platform": "ios"
        ]
        if let missing, !missing.isEmpty {
            payload["missing"] = missing
        }
        if let status, !status.isEmpty {
            payload["status"] = status
        }
        if let diagnostic, !diagnostic.isEmpty {
            payload["diagnostic"] = diagnostic
        }
        return payload
    }
}
