enum MethodNames {
    static let getPlatformVersion = "getPlatformVersion"

    // Permissions
    static let checkPermission = "checkPermission"
    static let requestPermission = "requestPermission"
    static let openPermissionSettings = "openPermissionSettings"

    // Installed apps
    static let showFamilyActivityPicker = "showFamilyActivityPicker"

    // Usage stats
    static let queryUsageStats = "queryUsageStats"
    static let queryAppUsageStats = "queryAppUsageStats"

    // Restrictions
    static let configureShield = "configureShield"
    static let upsertMode = "upsertMode"
    static let removeMode = "removeMode"
    static let setModesEnabled = "setModesEnabled"
    static let getModesConfig = "getModesConfig"
    static let isRestrictionSessionActiveNow = "isRestrictionSessionActiveNow"
    static let pauseEnforcement = "pauseEnforcement"
    static let resumeEnforcement = "resumeEnforcement"
    static let startSession = "startSession"
    static let endSession = "endSession"
    static let getRestrictionSession = "getRestrictionSession"
}
