package com.example.pauza_screen_time.app_restriction.storage

/**
 * Centralized SharedPreferences key constants for the restriction subsystem.
 */
internal object RestrictionStorageKeys {
    // ---- Shared preferences file names ----
    const val RESTRICTION_PREFS_NAME = "app_restriction_prefs"
    const val SCHEDULE_PREFS_NAME = "app_restriction_schedule_prefs"

    // ---- Keys in RESTRICTION_PREFS_NAME ----
    const val KEY_BLOCKED_APPS = "blocked_apps"
    const val KEY_PAUSED_UNTIL_EPOCH_MS = "paused_until_epoch_ms"
    const val KEY_MANUAL_SESSION_END_EPOCH_MS = "manual_session_end_epoch_ms"
    const val KEY_PENDING_END_SESSION_EPOCH_MS = "pending_end_session_epoch_ms"
    const val KEY_ACTIVE_SESSION = "active_session"
    const val KEY_SESSION_ID_SEQ = "session_id_seq"
    const val KEY_SUPPRESSED_SCHEDULE_MODE_ID = "suppressed_schedule_mode_id"
    const val KEY_SUPPRESSED_SCHEDULE_UNTIL_EPOCH_MS = "suppressed_schedule_until_epoch_ms"
    const val KEY_LIFECYCLE_EVENTS = "lifecycle_events"
    const val KEY_ACTIVE_SESSION_LIFECYCLE_EVENTS = "active_session_lifecycle_events"
    const val KEY_LIFECYCLE_EVENT_SEQ = "lifecycle_event_seq"

    // ---- Keys in SCHEDULE_PREFS_NAME ----
    const val KEY_SCHEDULED_MODES_ENABLED = "modes_enabled"
    const val KEY_SCHEDULED_MODES = "modes"
}
