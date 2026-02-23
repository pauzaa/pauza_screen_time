package com.example.pauza_screen_time.installed_apps

import android.content.Context
import com.example.pauza_screen_time.installed_apps.model.InstalledAppDto
import com.example.pauza_screen_time.installed_apps.repository.InstalledAppsRepository

/**
 * Façade for installed applications enumeration.
 *
 * Delegates all logic to [InstalledAppsRepository]. Kept for backwards
 * compatibility with [InstalledAppsMethodHandler] which already depends on it.
 */
class InstalledAppsHandler(context: Context) {

    private val repository = InstalledAppsRepository(context)

    /**
     * Returns all installed apps.
     *
     * @param includeSystemApps Whether to include system apps.
     * @param includeIcons Whether to include PNG icon bytes.
     */
    fun getInstalledApps(
        includeSystemApps: Boolean,
        includeIcons: Boolean = true,
    ): List<InstalledAppDto> = repository.getInstalledApps(includeSystemApps, includeIcons)

    /**
     * Returns info for a specific package, or null if not installed.
     *
     * @param packageId Package name (e.g. "com.example.app").
     * @param includeIcons Whether to include PNG icon bytes.
     */
    fun getAppInfo(packageId: String, includeIcons: Boolean = true): InstalledAppDto? =
        repository.getAppInfo(packageId, includeIcons)
}
