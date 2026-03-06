package com.example.pauza_screen_time.app_restriction

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.KeyguardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityWindowInfo

class AppMonitoringService : AccessibilityService() {

    companion object {
        private const val TAG = "AppMonitoringService"
        private const val EVENT_DEBOUNCE_MS = 500L
        private const val LOCK_LAUNCH_THROTTLE_MS = 800L
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

    /** Cached controller to avoid re-creation on every [evaluateForegroundPackage] call. */
    private val sessionController: RestrictionSessionController by lazy(LazyThreadSafetyMode.NONE) {
        RestrictionSessionController(applicationContext)
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
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

        // Skip enforcement while screen is locked
        if (isKeyguardLocked()) return

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
        dismissLockIfVisible()
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        dismissLockIfVisible()
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

    // ---- Package classification helpers ----

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

    private fun isKeyguardLocked(): Boolean {
        val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        return keyguardManager?.isKeyguardLocked == true
    }

    // ---- Enforcement via LockActivity ----

    private fun handleRestrictedAppDetected(packageName: String) {
        Log.d(TAG, "Restricted app detected: $packageName")

        // Atomic snapshot avoids TOCTOU between isLockVisible and currentBlockedPackage reads.
        val snap = LockVisibilityState.snapshot()

        // Fast-path: lock is already visible for this exact package — nothing to do.
        if (snap.isLockVisible && snap.currentBlockedPackage == packageName) {
            Log.d(TAG, "Lock already visible for $packageName; skipping")
            return
        }

        // Guard: throttle rapid launches (also uses snapshot internally)
        val now = System.currentTimeMillis()
        if (LockVisibilityState.shouldSuppressLaunch(packageName, now, LOCK_LAUNCH_THROTTLE_MS)) {
            Log.d(TAG, "Lock launch throttled for $packageName")
            return
        }

        // Step 1: Send user HOME
        val homeSuccess = performGlobalAction(GLOBAL_ACTION_HOME)
        Log.d(TAG, "GLOBAL_ACTION_HOME result=$homeSuccess")

        // Step 2: Launch LockActivity immediately (don't wait for HOME)
        launchLockActivity(packageName)

        // Step 3: Fallback BACK action if HOME failed
        if (!homeSuccess) {
            performGlobalAction(GLOBAL_ACTION_BACK)
        }
    }

    private fun launchLockActivity(packageId: String) {
        val intent = Intent(applicationContext, LockActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_NO_ANIMATION
            putExtra(LockActivity.EXTRA_BLOCKED_PACKAGE, packageId)
        }
        try {
            applicationContext.startActivity(intent)
            LockVisibilityState.markLaunched(packageId)
            Log.d(TAG, "LockActivity launched for $packageId")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch LockActivity", e)
            // Ultimate fallback: try BACK to at least leave the blocked app
            performGlobalAction(GLOBAL_ACTION_BACK)
        }
    }

    private fun evaluateForegroundPackage(packageName: String, trigger: String) {
        lastForegroundPackage = packageName
        Log.d(TAG, "Evaluating foreground package=$packageName trigger=$trigger")

        // Self-detection guard: skip our own package (Flutter host or LockActivity)
        if (packageName == applicationContext.packageName) {
            return
        }

        if (isLauncherPackage(packageName)) {
            // User is on home screen -- dismiss lock if visible
            dismissLockIfVisible()
            return
        }

        if (isSystemUiOrImePackage(packageName)) return

        // If lock is visible for a different package, dismiss it first
        val snap = LockVisibilityState.snapshot()
        if (snap.isLockVisible && snap.currentBlockedPackage != null && snap.currentBlockedPackage != packageName) {
            dismissLockIfVisible()
        }

        val restrictionManager = RestrictionManager.getInstance(applicationContext)
        if (restrictionManager.isPausedNow()) {
            dismissLockIfVisible()
            return
        }

        val sessionState = sessionController.resolveSessionState()
        restrictionManager.setRestrictedApps(sessionState.blockedAppIds)
        val shouldEnforce = RestrictionSessionController.shouldEnforceNow(
            state = sessionState,
            isPausedNow = false,
        )
        if (!shouldEnforce) {
            dismissLockIfVisible()
            return
        }

        if (isAppRestricted(packageName)) {
            handleRestrictedAppDetected(packageName)
        }
    }

    /**
     * Dismisses [LockActivity] via in-process callback if the lock is currently visible.
     */
    private fun dismissLockIfVisible() {
        val snap = LockVisibilityState.snapshot()
        if (snap.isLockVisible) {
            LockVisibilityState.requestDismiss()
            Log.d(TAG, "Dismiss requested for LockActivity")
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
