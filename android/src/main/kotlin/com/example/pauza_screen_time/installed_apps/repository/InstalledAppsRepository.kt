package com.example.pauza_screen_time.installed_apps.repository

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import com.example.pauza_screen_time.installed_apps.model.InstalledAppDto
import com.example.pauza_screen_time.utils.AppIconExtractor
import com.example.pauza_screen_time.utils.AppInfoUtils

/**
 * Queries [PackageManager] for installed application information.
 *
 * Single-responsibility: enumerate packages and map them to [InstalledAppDto].
 * Icon extraction failures are downgraded to a null icon with a logged warning
 * so that one bad icon never prevents the rest of the list from being returned.
 */
class InstalledAppsRepository(private val context: Context) {

    companion object {
        private const val TAG = "InstalledAppsRepository"
    }

    private val packageManager: PackageManager = context.packageManager

    /**
     * Returns all installed applications as typed DTOs.
     *
     * @param includeSystemApps Whether to include system applications.
     * @param includeIcons      Whether to load and include PNG icon bytes.
     * @return Non-null list; may be empty if no packages match the filter.
     */
    fun getInstalledApps(
        includeSystemApps: Boolean,
        includeIcons: Boolean = true,
    ): List<InstalledAppDto> {
        val packages = getInstalledApplications()
        return packages
            .filter { includeSystemApps || !AppInfoUtils.isSystemApp(it) }
            .map { appInfo -> buildDto(appInfo, includeIcons) }
    }

    /**
     * Returns information about a specific package, or null if not installed.
     *
     * @param packageId  Package name (e.g. "com.example.app").
     * @param includeIcons Whether to load and include PNG icon bytes.
     * @return [InstalledAppDto] or null when [PackageManager.NameNotFoundException] is thrown.
     */
    fun getAppInfo(packageId: String, includeIcons: Boolean = true): InstalledAppDto? {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageId, 0)
            buildDto(appInfo, includeIcons)
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    private fun getInstalledApplications(): List<ApplicationInfo> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
        }
    }

    private fun buildDto(appInfo: ApplicationInfo, includeIcons: Boolean): InstalledAppDto {
        val icon: ByteArray? = if (includeIcons) extractIconSafely(appInfo) else null
        return InstalledAppDto(
            platform = "android",
            packageId = appInfo.packageName,
            name = appInfo.loadLabel(packageManager).toString(),
            icon = icon,
            category = AppInfoUtils.getAppCategory(appInfo),
            isSystemApp = AppInfoUtils.isSystemApp(appInfo),
        )
    }

    /**
     * Attempts to extract the app icon. Logs a warning on failure and returns null.
     *
     * Icon extraction is a best-effort operation: a single app with a broken
     * drawable must not prevent the entire list from being returned.
     */
    private fun extractIconSafely(appInfo: ApplicationInfo): ByteArray? {
        return try {
            AppIconExtractor.extract(appInfo, packageManager)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to extract icon for ${appInfo.packageName}: ${e.message}")
            null
        }
    }
}
