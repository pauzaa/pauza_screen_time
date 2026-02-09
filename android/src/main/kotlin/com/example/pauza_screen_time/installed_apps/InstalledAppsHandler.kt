package com.example.pauza_screen_time.installed_apps

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import com.example.pauza_screen_time.utils.AppInfoUtils

/**
 * Handler for installed applications enumeration.
 *
 * This class provides functionality to query and retrieve information
 * about installed applications on the device using Android's PackageManager.
 * It handles app enumeration, icon extraction, and app categorization.
 */
class InstalledAppsHandler(private val context: Context) {

    private val packageManager: PackageManager = context.packageManager

    /**
     * Retrieves a list of all installed applications.
     *
     * @param includeSystemApps Whether to include system apps in the results
     * @param includeIcons Whether to include app icons (can be expensive)
     * @return List of maps containing app information (packageId, name, icon, category)
     */
    fun getInstalledApps(
        includeSystemApps: Boolean,
        includeIcons: Boolean = true
    ): List<Map<String, Any?>> {
        val installedApps = mutableListOf<Map<String, Any?>>()
        // Get all installed packages
        val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
        }

        for (appInfo in packages) {
            // Skip system apps if not requested
            if (!includeSystemApps && AppInfoUtils.isSystemApp(appInfo)) {
                continue
            }

            installedApps.add(extractAppInfo(appInfo, includeIcons))
        }

        return installedApps
    }

    /**
     * Retrieves information about a specific app by package ID.
     *
     * @param packageId The package name/ID of the app
     * @param includeIcons Whether to include app icons (can be expensive)
     * @return Map containing app information, or null if app not found
     */
    fun getAppInfo(
        packageId: String,
        includeIcons: Boolean = true
    ): Map<String, Any?>? {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageId, 0)
            extractAppInfo(appInfo, includeIcons)
        } catch (e: PackageManager.NameNotFoundException) {
            // App not found
            null
        }
    }

    /**
     * Extracts app information into a map format.
     *
     * @param appInfo ApplicationInfo object from PackageManager
     * @param includeIcons Whether to include app icons (can be expensive)
     * @return Map containing platform, packageId, name, icon (as byte array), and category
     */
    private fun extractAppInfo(
        appInfo: ApplicationInfo,
        includeIcons: Boolean
    ): Map<String, Any?> {
        val packageId = appInfo.packageName
        val name = appInfo.loadLabel(packageManager).toString()
        val icon = if (includeIcons) {
            AppInfoUtils.extractAppIcon(appInfo, packageManager)
        } else {
            null
        }
        val category = AppInfoUtils.getAppCategory(appInfo)
        val isSystemApp = AppInfoUtils.isSystemApp(appInfo)

        return mapOf(
            "platform" to "android",
            "packageId" to packageId,
            "name" to name,
            "icon" to icon,
            "category" to category,
            "isSystemApp" to isSystemApp
        )
    }
}
