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
    static let setRestrictedApps = "setRestrictedApps"
    static let addRestrictedApp = "addRestrictedApp"
    static let removeRestriction = "removeRestriction"
    static let isRestricted = "isRestricted"
    static let removeAllRestrictions = "removeAllRestrictions"
    static let getRestrictedApps = "getRestrictedApps"
    static let isRestrictionSessionActiveNow = "isRestrictionSessionActiveNow"
    static let isRestrictionSessionConfigured = "isRestrictionSessionConfigured"
    static let pauseEnforcement = "pauseEnforcement"
    static let resumeEnforcement = "resumeEnforcement"
    static let startRestrictionSession = "startRestrictionSession"
    static let endRestrictionSession = "endRestrictionSession"
    static let setRestrictionScheduleConfig = "setRestrictionScheduleConfig"
    static let getRestrictionScheduleConfig = "getRestrictionScheduleConfig"
    static let getRestrictionSession = "getRestrictionSession"
    static let upsertScheduledMode = "upsertScheduledMode"
    static let removeScheduledMode = "removeScheduledMode"
    static let setScheduledModesEnabled = "setScheduledModesEnabled"
    static let getScheduledModesConfig = "getScheduledModesConfig"
}
