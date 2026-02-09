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
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleCalculator
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModeResolver
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModesStore

class AppMonitoringService : AccessibilityService() {

    companion object {
        private const val TAG = "AppMonitoringService"
        private const val EVENT_DEBOUNCE_MS = 500L

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
    private val modesStore by lazy { RestrictionScheduledModesStore(applicationContext) }
    private val scheduleCalculator = RestrictionScheduleCalculator()

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this

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
        isMonitoring = enabled
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

        val config = modesStore.getConfig()
        val manualModeId = restrictionManager.getManualActiveModeId()
        val manualMode = config.modes.firstOrNull { it.modeId == manualModeId && it.isEnabled }
        val scheduleResolution = resolveScheduledModeNow(config)

        val blockedAppIds = when {
            manualMode != null -> manualMode.blockedAppIds
            else -> scheduleResolution.blockedAppIds
        }
        restrictionManager.setRestrictedApps(blockedAppIds)

        val shouldEnforce = when {
            manualMode != null -> true
            else -> scheduleResolution.isInScheduleNow
        }
        if (!shouldEnforce) {
            overlayManager?.hideShield()
            return
        }

        if (isAppRestricted(packageName)) {
            Log.d(TAG, "Restricted app detected: $packageName")
            handleRestrictedAppDetected(packageName)
        }
    }

    private fun resolveScheduledModeNow(config: com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModesConfig): RestrictionScheduledModeResolver.Resolution {
        return RestrictionScheduledModeResolver.resolveNow(
            config = config,
            scheduleCalculator = scheduleCalculator,
        )
    }
}
