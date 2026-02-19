package com.example.pauza_screen_time.app_restriction

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityWindowInfo

class AppMonitoringService : AccessibilityService() {

    companion object {
        private const val TAG = "AppMonitoringService"
        private const val EVENT_DEBOUNCE_MS = 500L
        private const val MONITORING_EVENT_TYPES =
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or AccessibilityEvent.TYPE_WINDOWS_CHANGED
        private const val MONITORING_FLAGS =
            AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS

        @Volatile
        private var instance: AppMonitoringService? = null

        fun isRunning(context: Context): Boolean {
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            )

            if (enabledServices.isNullOrEmpty()) {
                return false
            }

            val expectedService = ComponentName(context, AppMonitoringService::class.java).flattenToString()
            return enabledServices.split(':').any { it == expectedService }
        }

        fun getInstance(): AppMonitoringService? = instance
    }

    private var lastForegroundPackage: String? = null
    private var lastEventTimestamp: Long = 0L
    private var isMonitoring = true

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        val sessionController = RestrictionSessionController(applicationContext)
        val state = sessionController.resolveSessionState()
        val isPausedNow = RestrictionManager.getInstance(applicationContext).isPausedNow()
        val shouldMonitor = RestrictionSessionController.shouldMonitorForegroundEvents(
            state = state,
            isPausedNow = isPausedNow,
        )
        setMonitoringEnabled(shouldMonitor)
        if (shouldMonitor) {
            enforceCurrentForegroundNow(trigger = "service_connected")
        }
        Log.d(TAG, "AppMonitoringService connected and configured; monitoring=$shouldMonitor")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || !isMonitoring) return

        if (
            event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event.eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED
        ) return

        val packageName = getFocusedApplicationPackageName()
            ?: event.packageName?.toString()
            ?: return

        val now = System.currentTimeMillis()
        if (now - lastEventTimestamp < EVENT_DEBOUNCE_MS) return
        lastEventTimestamp = now

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

    fun setMonitoringEnabled(enabled: Boolean) {
        if (isMonitoring != enabled) {
            lastForegroundPackage = null
            lastEventTimestamp = 0L
        }
        isMonitoring = enabled
        configureServiceMonitoring(enabled)
        Log.d(TAG, "Monitoring ${if (enabled) "enabled" else "disabled"}")
    }

    fun enforceCurrentForegroundNow(trigger: String) {
        if (!isMonitoring) return

        val packageName = getFocusedApplicationPackageName() ?: return
        evaluateForegroundPackage(packageName, trigger)
    }

    private fun isLauncherPackage(packageName: String): Boolean {
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
            "com.google.android.inputmethod",
            "com.samsung.android.honeyboard",
        )
        return knownImes.any { packageName.startsWith(it) } ||
            packageName.contains("keyboard", ignoreCase = true) ||
            packageName.contains("inputmethod", ignoreCase = true)
    }

    private fun isAppRestricted(packageName: String): Boolean {
        return RestrictionManager.getInstance(applicationContext).isRestricted(packageName)
    }

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

    private fun handleRestrictedAppDetected(packageName: String) {
        Log.d(TAG, "Handling restricted app detection: $packageName")

        ShieldOverlayManager.getInstance(applicationContext).showShield(
            packageName,
            contextOverride = this,
        )
    }

    private fun evaluateForegroundPackage(packageName: String, trigger: String) {
        lastForegroundPackage = packageName
        Log.d(TAG, "Evaluating foreground package=$packageName trigger=$trigger")

        val overlayManager = ShieldOverlayManager.getInstanceOrNull()

        if (packageName == applicationContext.packageName || isLauncherPackage(packageName)) {
            overlayManager?.hideShield()
            return
        }

        if (isSystemUiOrImePackage(packageName)) return

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

        val sessionState = RestrictionSessionController(applicationContext).resolveSessionState()
        restrictionManager.setRestrictedApps(sessionState.blockedAppIds)
        val shouldEnforce = RestrictionSessionController.shouldEnforceNow(
            state = sessionState,
            isPausedNow = false,
        )
        if (!shouldEnforce) {
            overlayManager?.hideShield()
            return
        }

        if (isAppRestricted(packageName)) {
            Log.d(TAG, "Restricted app detected: $packageName")
            handleRestrictedAppDetected(packageName)
        }
    }

    private fun configureServiceMonitoring(enabled: Boolean) {
        val nextEventTypes = if (enabled) MONITORING_EVENT_TYPES else 0
        val info = serviceInfo ?: AccessibilityServiceInfo()
        info.eventTypes = nextEventTypes
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.notificationTimeout = 100
        info.flags = MONITORING_FLAGS
        serviceInfo = info
    }

}
