package com.example.pauza_screen_time.app_restriction

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityWindowInfo
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleCalculator
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModeResolver
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModesStore
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleStore

/**
 * AccessibilityService implementation for monitoring foreground app changes.
 *
 * This service detects when apps are launched (via TYPE_WINDOW_STATE_CHANGED events)
 * and checks if the launched app is on the blocklist. If blocked, it triggers
 * the shield overlay to be displayed over the restricted app.
 *
 * Features:
 * - Monitors foreground app changes in real-time
 * - Integrates with RestrictionManager for blocklist checking
 * - Triggers ShieldOverlayManager when blocked app is detected
 * - Shows shield overlay for restricted apps
 */
class AppMonitoringService : AccessibilityService() {

    companion object {
        private const val TAG = "AppMonitoringService"
        private const val EVENT_DEBOUNCE_MS = 500L
        
        // Reference to the running service instance
        @Volatile
        private var instance: AppMonitoringService? = null
        
        /**
         * Checks if the accessibility service is enabled in system settings.
         *
         * @param context The application context
         * @return true if the service is enabled, false otherwise
         */
        fun isRunning(context: Context): Boolean {
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )
            
            if (enabledServices.isNullOrEmpty()) {
                return false
            }

            val expectedService = ComponentName(context, AppMonitoringService::class.java).flattenToString()
            return enabledServices.split(':').any { it == expectedService }
        }
        
        /**
         * Gets the current service instance if running.
         *
         * @return The service instance or null if not running
         */
        fun getInstance(): AppMonitoringService? = instance
    }
    
    // Track the last detected foreground package to avoid duplicate processing
    private var lastForegroundPackage: String? = null

    // Track last processed event time to avoid rapid toggles
    private var lastEventTimestamp: Long = 0L
    
    // Flag to indicate if monitoring is active
    private var isMonitoring = true
    private val scheduleStore by lazy { RestrictionScheduleStore(applicationContext) }
    private val scheduledModesStore by lazy { RestrictionScheduledModesStore(applicationContext) }
    private val scheduleCalculator = RestrictionScheduleCalculator()

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        
        // Configure the service programmatically (supplements XML config)
        val info = AccessibilityServiceInfo().apply {
            eventTypes =
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                AccessibilityEvent.TYPE_WINDOWS_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 100
            flags =
                AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        serviceInfo = info
        
        Log.d(TAG, "AppMonitoringService connected and configured")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || !isMonitoring) return
        
        // Only process window state change events
        if (
            event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event.eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED
        ) return
        
        // Prefer the focused interactive application window package if available.
        // This avoids false positives where a background/PiP window emits an event
        // (commonly observed with YouTube) while the launcher is actually focused.
        val packageName = getFocusedApplicationPackageName()
            ?: event.packageName?.toString()
            ?: return

        val now = System.currentTimeMillis()
        if (now - lastEventTimestamp < EVENT_DEBOUNCE_MS) return
        lastEventTimestamp = now

        // Skip if same as last detected package (avoid duplicate processing)
        if (packageName == lastForegroundPackage) return

        evaluateForegroundPackage(packageName, trigger = "accessibility_event")
    }

    override fun onInterrupt() {
        Log.d(TAG, "AppMonitoringService interrupted")
        ShieldOverlayManager.getInstanceOrNull()?.hideShield()
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        ShieldOverlayManager.getInstanceOrNull()?.hideShield()
        Log.d(TAG, "AppMonitoringService destroyed")
    }
    
    /**
     * Enables or disables foreground app monitoring.
     *
     * @param enabled true to enable monitoring, false to disable
     */
    fun setMonitoringEnabled(enabled: Boolean) {
        isMonitoring = enabled
        Log.d(TAG, "Monitoring ${if (enabled) "enabled" else "disabled"}")
    }

    fun enforceCurrentForegroundNow(trigger: String) {
        if (!isMonitoring) return

        val packageName = getFocusedApplicationPackageName() ?: return
        evaluateForegroundPackage(packageName, trigger)
    }

    private fun isLauncherPackage(packageName: String): Boolean {
        // Common launcher packages across OEMs; plus a heuristic fallback.
        val knownLaunchers = listOf(
            "com.android.launcher",
            "com.android.launcher3",
            "com.google.android.apps.nexuslauncher",
            "com.google.android.apps.launcher",
            "com.samsung.android.launcher",
            "com.miui.home",
            "com.oneplus.launcher",
            "com.huawei.android.launcher",
            "com.oppo.launcher",
            "com.vivo.launcher",
        )
        return knownLaunchers.any { packageName.startsWith(it) } ||
            packageName.contains("launcher", ignoreCase = true)
    }

    private fun isSystemUiOrImePackage(packageName: String): Boolean {
        if (packageName.startsWith("com.android.systemui")) return true

        val knownImes = listOf(
            "com.google.android.inputmethod", // Gboard
            "com.samsung.android.honeyboard",
        )
        return knownImes.any { packageName.startsWith(it) } ||
            packageName.contains("keyboard", ignoreCase = true) ||
            packageName.contains("inputmethod", ignoreCase = true)
    }
    
    /**
     * Checks if the given package is on the restriction blocklist.
     *
     * @param packageName The package name to check
     * @return true if the app is restricted
     */
    private fun isAppRestricted(packageName: String): Boolean {
        return RestrictionManager.getInstance(applicationContext).isRestricted(packageName)
    }

    /**
     * Attempts to resolve the "real" foreground app by reading interactive windows
     * and picking the focused (or active) application window.
     *
     * This is more reliable than trusting `AccessibilityEvent.packageName`, which
     * may refer to transient/non-focused windows (e.g. YouTube PiP/miniplayer).
     */
    private fun getFocusedApplicationPackageName(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return null

        return try {
            val windowList = windows ?: return null

            val focusedWindow = windowList.firstOrNull { w ->
                w.type == AccessibilityWindowInfo.TYPE_APPLICATION && w.isFocused
            } ?: windowList.firstOrNull { w ->
                w.type == AccessibilityWindowInfo.TYPE_APPLICATION && w.isActive
            }

            focusedWindow?.root?.packageName?.toString()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to resolve focused application window", e)
            null
        }
    }
    
    /**
     * Called when a restricted app is launched.
     * 
     * Shows the shield overlay.
     *
     * @param packageName The package name of the restricted app
     */
    private fun handleRestrictedAppDetected(packageName: String) {
        Log.d(TAG, "Handling restricted app detection: $packageName")
        
        // Show shield overlay
        ShieldOverlayManager.getInstance(applicationContext).showShield(
            packageName,
            contextOverride = this
        )
        
    }

    private fun evaluateForegroundPackage(packageName: String, trigger: String) {
        lastForegroundPackage = packageName
        Log.d(TAG, "Evaluating foreground package=$packageName trigger=$trigger")

        val overlayManager = ShieldOverlayManager.getInstanceOrNull()

        // If we navigated away from a restricted app, dismiss the shield.
        // This is critical for cases where the user presses Home/Recents instead of tapping "OK".
        if (packageName == applicationContext.packageName || isLauncherPackage(packageName)) {
            overlayManager?.hideShield()
            return
        }

        // Ignore transient window changes for system UI / keyboards without dismissing,
        // otherwise the shield could flicker when notifications/IME appear.
        if (isSystemUiOrImePackage(packageName)) return

        // If the foreground app changed away from the currently blocked package, hide the shield.
        // (e.g. user switches to another allowed app)
        if (overlayManager?.isShowing() == true) {
            val blocked = overlayManager.getCurrentBlockedPackage()
            if (blocked != null && blocked != packageName) {
                overlayManager.hideShield()
            }
        }

        val restrictionManager = RestrictionManager.getInstance(applicationContext)
        if (restrictionManager.isPausedNow()) {
            overlayManager?.hideShield()
            return
        }

        val scheduleResolution = resolveScheduledModeNow()
        if (!restrictionManager.isManualEnforcementEnabled()) {
            restrictionManager.setRestrictedApps(scheduleResolution.blockedAppIds)
        }
        val shouldEnforce = restrictionManager.isManualEnforcementEnabled() || scheduleResolution.isInScheduleNow
        if (!shouldEnforce) {
            overlayManager?.hideShield()
            return
        }

        if (isAppRestricted(packageName)) {
            Log.d(TAG, "Restricted app detected: $packageName")
            handleRestrictedAppDetected(packageName)
        }
    }

    private fun resolveScheduledModeNow(): RestrictionScheduledModeResolver.Resolution {
        val scheduledModesConfig = scheduledModesStore.getConfig()
        if (scheduledModesConfig.scheduledModes.isNotEmpty()) {
            return RestrictionScheduledModeResolver.resolveNow(
                config = scheduledModesConfig,
                scheduleCalculator = scheduleCalculator,
            )
        }
        val isInLegacyScheduleNow = scheduleCalculator.isInSessionNow(scheduleStore.getConfig())
        return RestrictionScheduledModeResolver.Resolution(
            isInScheduleNow = isInLegacyScheduleNow,
            blockedAppIds = if (isInLegacyScheduleNow) {
                RestrictionManager.getInstance(applicationContext).getRestrictedApps()
            } else {
                emptyList()
            },
        )
    }
}
