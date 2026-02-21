package com.example.pauza_screen_time.usage_stats.repository

import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import com.example.pauza_screen_time.permissions.PermissionHandler
import com.example.pauza_screen_time.usage_stats.model.AppStandbyBucket

/**
 * Repository for app inactivity status and standby bucket queries.
 *
 * Requires [android.Manifest.permission.PACKAGE_USAGE_STATS].
 * Throws [SecurityException] when the permission is not granted.
 */
class AppStatusRepository(private val context: Context) {

    private val usageStatsManager: UsageStatsManager =
        context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    private val permissionHandler = PermissionHandler(context)

    /**
     * Returns whether the specified app is currently considered inactive by the system.
     *
     * An app is inactive if it has not been used (directly or indirectly) for a
     * system-defined period (typically several hours or days). Apps are never
     * considered inactive while the device is charging.
     *
     * @param packageId Package name of the app to check
     * @return true if the app is inactive, false otherwise
     * @throws SecurityException if Usage Access permission is not granted
     */
    fun isAppInactive(packageId: String): Boolean {
        ensurePermission()
        return usageStatsManager.isAppInactive(packageId)
    }

    /**
     * Returns the current standby bucket of the **calling** app.
     *
     * **Requires API 28+.** Throws [UnsupportedOperationException] on older devices
     * instead of returning an ambiguous sentinel value.
     *
     * @return The [AppStandbyBucket] the calling app is currently assigned to
     * @throws UnsupportedOperationException if the device is running on API < 28
     */
    fun getAppStandbyBucket(): AppStandbyBucket {
        requireApi28()
        return AppStandbyBucket.fromRawValue(usageStatsManager.appStandbyBucket)
    }

    private fun requireApi28() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            throw UnsupportedOperationException(
                "getAppStandbyBucket requires Android 9 (API 28). " +
                    "Current API level: ${Build.VERSION.SDK_INT}"
            )
        }
    }

    private fun ensurePermission() {
        val status = permissionHandler.checkPermission(PermissionHandler.USAGE_STATS_KEY)
        if (status != PermissionHandler.STATUS_GRANTED) {
            throw SecurityException("Usage Access is not granted for android.usageStats")
        }
    }

    companion object {
        private const val TAG = "AppStatusRepository"
    }
}
