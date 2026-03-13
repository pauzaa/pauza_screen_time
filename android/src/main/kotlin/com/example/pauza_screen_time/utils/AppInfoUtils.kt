package com.example.pauza_screen_time.utils

import android.content.pm.ApplicationInfo
import android.os.Build

/**
 * Utility object for common application metadata (category, system-app flag).
 *
 * Icon extraction has been consolidated into [AppIconExtractor].
 */
object AppInfoUtils {

    /**
     * Gets the app category as a string.
     *
     * @param appInfo ApplicationInfo object
     * @return Category name or null if not available
     */
    fun getAppCategory(appInfo: ApplicationInfo): String? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            when (appInfo.category) {
                ApplicationInfo.CATEGORY_GAME -> "Games"
                ApplicationInfo.CATEGORY_AUDIO -> "Audio"
                ApplicationInfo.CATEGORY_VIDEO -> "Video"
                ApplicationInfo.CATEGORY_IMAGE -> "Image"
                ApplicationInfo.CATEGORY_SOCIAL -> "Social"
                ApplicationInfo.CATEGORY_NEWS -> "News"
                ApplicationInfo.CATEGORY_MAPS -> "Maps"
                ApplicationInfo.CATEGORY_PRODUCTIVITY -> "Productivity"
                else -> null
            }
        } else {
            null
        }
    }

    /**
     * Checks if an app is a system app.
     *
     * @param appInfo ApplicationInfo object
     * @return true if the app is a system app, false otherwise
     */
    fun isSystemApp(appInfo: ApplicationInfo): Boolean {
        return (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
    }
}
