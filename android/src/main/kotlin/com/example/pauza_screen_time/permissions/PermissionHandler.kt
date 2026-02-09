package com.example.pauza_screen_time.permissions

import android.app.Activity
import android.app.AlarmManager
import android.app.AppOpsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.example.pauza_screen_time.app_restriction.AppMonitoringService

/**
 * Handles permission checking, requesting, and settings navigation for Android.
 *
 * This class manages all permission-related operations for the plugin including:
 * - Usage stats permission (PACKAGE_USAGE_STATS)
 * - Accessibility service permission
 * - Query all packages permission (QUERY_ALL_PACKAGES)
 */
open class PermissionHandler(private val context: Context) {

    companion object {
        // Permission keys matching Flutter AndroidPermission enum
        const val USAGE_STATS_KEY = "android.usageStats"
        const val ACCESSIBILITY_KEY = "android.accessibility"
        const val EXACT_ALARM_KEY = "android.exactAlarm"
        const val QUERY_ALL_PACKAGES_KEY = "android.queryAllPackages"

        // Permission status strings matching Flutter PermissionStatus enum
        const val STATUS_GRANTED = "granted"
        const val STATUS_DENIED = "denied"
        const val STATUS_UNKNOWN = "unknown"

        // Request codes for permission results
        const val REQUEST_USAGE_STATS = 1001
        const val REQUEST_ACCESSIBILITY = 1002
    }

    /**
     * Checks the status of a specific permission.
     *
     * @param permissionKey The permission key from AndroidPermission enum
     * @return String status: "granted", "denied", or "unknown"
     */
    fun checkPermission(permissionKey: String): String {
        return when (permissionKey) {
            USAGE_STATS_KEY -> checkUsageStatsPermission()
            ACCESSIBILITY_KEY -> checkAccessibilityPermission()
            EXACT_ALARM_KEY -> checkExactAlarmPermission()
            QUERY_ALL_PACKAGES_KEY -> checkQueryAllPackagesPermission()
            else -> STATUS_UNKNOWN
        }
    }

    /**
     * Requests a specific permission from the user.
     *
     * @param activity The current activity for launching intents
     * @param permissionKey The permission key from AndroidPermission enum
     * @return Boolean indicating if the request was initiated successfully
     */
    fun requestPermission(activity: Activity, permissionKey: String): Boolean {
        return when (permissionKey) {
            USAGE_STATS_KEY -> requestUsageStatsPermission(activity)
            ACCESSIBILITY_KEY -> requestAccessibilityPermission(activity)
            EXACT_ALARM_KEY -> requestExactAlarmPermission(activity)
            QUERY_ALL_PACKAGES_KEY -> {
                // QUERY_ALL_PACKAGES is a manifest permission, cannot be requested at runtime
                // User needs to allow it in the manifest and potentially through Play Store review
                false
            }
            else -> false
        }
    }

    /**
     * Opens the system settings page for a specific permission.
     *
     * @param activity The current activity for launching intents
     * @param permissionKey The permission key from AndroidPermission enum
     */
    fun openPermissionSettings(activity: Activity, permissionKey: String) {
        when (permissionKey) {
            USAGE_STATS_KEY -> openUsageStatsSettings(activity)
            ACCESSIBILITY_KEY -> openAccessibilitySettings(activity)
            EXACT_ALARM_KEY -> openExactAlarmSettings(activity)
            QUERY_ALL_PACKAGES_KEY -> openAppDetailsSettings(activity)
            else -> openAppDetailsSettings(activity)
        }
    }

    // ============= Usage Stats Permission =============

    private fun checkUsageStatsPermission(): String {
        val appOpsManager = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOpsManager.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOpsManager.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName
            )
        }
        return if (mode == AppOpsManager.MODE_ALLOWED) STATUS_GRANTED else STATUS_DENIED
    }

    private fun requestUsageStatsPermission(activity: Activity): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            intent.data = Uri.parse("package:${context.packageName}")
            activity.startActivityForResult(intent, REQUEST_USAGE_STATS)
            true
        } catch (e: Exception) {
            // Fallback to app-specific settings if the general settings fail
            openUsageStatsSettings(activity)
            false
        }
    }

    private fun openUsageStatsSettings(activity: Activity) {
        try {
            // Try to open the app-specific usage access settings
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            intent.data = Uri.parse("package:${context.packageName}")
            activity.startActivity(intent)
        } catch (e: Exception) {
            // Fallback to general usage access settings
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            activity.startActivity(intent)
        }
    }

    // ============= Accessibility Permission =============

    private fun checkAccessibilityPermission(): String {
        val enabledServices = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        )

        if (enabledServices.isNullOrEmpty()) {
            return STATUS_DENIED
        }

        val expectedService = ComponentName(context, AppMonitoringService::class.java).flattenToString()
        val enabledServiceList = enabledServices.split(':')

        return if (enabledServiceList.any { it == expectedService }) {
            STATUS_GRANTED
        } else {
            STATUS_DENIED
        }
    }

    private fun requestAccessibilityPermission(activity: Activity): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            activity.startActivityForResult(intent, REQUEST_ACCESSIBILITY)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun openAccessibilitySettings(activity: Activity) {
        try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            activity.startActivity(intent)
        } catch (e: Exception) {
            // Fallback to app settings
            openAppDetailsSettings(activity)
        }
    }

    // ============= Exact Alarm Capability =============

    private fun checkExactAlarmPermission(): String {
        if (sdkInt() < Build.VERSION_CODES.S) {
            return STATUS_GRANTED
        }
        return if (canScheduleExactAlarms()) STATUS_GRANTED else STATUS_DENIED
    }

    private fun requestExactAlarmPermission(activity: Activity): Boolean {
        if (sdkInt() < Build.VERSION_CODES.S) {
            return true
        }

        val started = launchIntent(activity, buildExactAlarmSettingsIntent())
        if (!started) {
            openAppDetailsSettings(activity)
        }
        return started
    }

    private fun openExactAlarmSettings(activity: Activity) {
        if (sdkInt() < Build.VERSION_CODES.S) {
            openAppDetailsSettings(activity)
            return
        }

        val started = launchIntent(activity, buildExactAlarmSettingsIntent())
        if (!started) {
            openAppDetailsSettings(activity)
        }
    }

    internal open fun sdkInt(): Int = Build.VERSION.SDK_INT

    internal open fun canScheduleExactAlarms(): Boolean {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return alarmManager.canScheduleExactAlarms()
    }

    internal open fun buildExactAlarmSettingsIntent(): Intent {
        return Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
            data = Uri.parse("package:${context.packageName}")
        }
    }

    internal open fun launchIntent(activity: Activity, intent: Intent): Boolean {
        return try {
            activity.startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    // ============= Query All Packages Permission =============

    private fun checkQueryAllPackagesPermission(): String {
        // This is a manifest permission that's checked at install time
        // We can only verify if it's declared in the manifest and try a guarded query
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                if (!isQueryAllPackagesDeclared()) {
                    STATUS_DENIED
                } else {
                    try {
                        // On Android 11+, this call throws if permission is not granted.
                        val packageManager = context.packageManager
                        val packages = packageManager.getInstalledApplications(0)
                        if (packages.isNotEmpty()) STATUS_GRANTED else STATUS_UNKNOWN
                    } catch (e: SecurityException) {
                        STATUS_DENIED
                    } catch (e: Exception) {
                        STATUS_UNKNOWN
                    }
                }
            } else {
                // Pre-Android 11, this permission is not needed
                STATUS_GRANTED
            }
        } catch (e: Exception) {
            STATUS_UNKNOWN
        }
    }

    private fun isQueryAllPackagesDeclared(): Boolean {
        return try {
            val packageManager = context.packageManager
            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    context.packageName,
                    android.content.pm.PackageManager.PackageInfoFlags.of(
                        android.content.pm.PackageManager.GET_PERMISSIONS.toLong()
                    )
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(context.packageName, android.content.pm.PackageManager.GET_PERMISSIONS)
            }
            val permissions = packageInfo.requestedPermissions ?: return false
            permissions.contains(android.Manifest.permission.QUERY_ALL_PACKAGES)
        } catch (e: Exception) {
            false
        }
    }

    private fun openAppDetailsSettings(activity: Activity) {
        val started = launchIntent(activity, buildAppDetailsSettingsIntent())
        if (!started) {
            // Fallback to general settings
            launchIntent(activity, Intent(Settings.ACTION_SETTINGS))
        }
    }

    internal open fun buildAppDetailsSettingsIntent(): Intent {
        return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
        }
    }
}
