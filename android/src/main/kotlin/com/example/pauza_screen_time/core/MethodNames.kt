package com.example.pauza_screen_time.core

object MethodNames {
    const val GET_PLATFORM_VERSION = "getPlatformVersion"

    // Permissions
    const val CHECK_PERMISSION = "checkPermission"
    const val REQUEST_PERMISSION = "requestPermission"
    const val OPEN_PERMISSION_SETTINGS = "openPermissionSettings"

    // Installed apps
    const val GET_INSTALLED_APPS = "getInstalledApps"
    const val GET_APP_INFO = "getAppInfo"
    const val SHOW_FAMILY_ACTIVITY_PICKER = "showFamilyActivityPicker"

    // Usage stats
    const val QUERY_USAGE_STATS = "queryUsageStats"
    const val QUERY_APP_USAGE_STATS = "queryAppUsageStats"
    const val QUERY_USAGE_EVENTS = "queryUsageEvents"
    const val QUERY_EVENT_STATS = "queryEventStats"
    const val IS_APP_INACTIVE = "isAppInactive"
    const val GET_APP_STANDBY_BUCKET = "getAppStandbyBucket"

    // Restrictions
    const val CONFIGURE_SHIELD = "configureShield"
    const val UPSERT_MODE = "upsertMode"
    const val REMOVE_MODE = "removeMode"
    const val REPLACE_ALL_MODES = "replaceAllModes"
    const val SET_SCHEDULE_ENFORCEMENT_ENABLED = "setScheduleEnforcementEnabled"
    const val GET_MODES_CONFIG = "getModesConfig"
    const val IS_RESTRICTION_SESSION_ACTIVE_NOW = "isRestrictionSessionActiveNow"
    const val PAUSE_ENFORCEMENT = "pauseEnforcement"
    const val RESUME_ENFORCEMENT = "resumeEnforcement"
    const val START_SESSION = "startSession"
    const val END_SESSION = "endSession"
    const val GET_PENDING_LIFECYCLE_EVENTS = "getPendingLifecycleEvents"
    const val ACK_LIFECYCLE_EVENTS = "ackLifecycleEvents"
    const val GET_RESTRICTION_SESSION = "getRestrictionSession"
}
