package com.example.pauza_screen_time.installed_apps.model

data class InstalledAppDto(
    val platform: String,
    val packageId: String,
    val name: String,
    val icon: ByteArray?,
    val category: String?,
    val isSystemApp: Boolean,
) {
    fun toChannelMap(): Map<String, Any?> {
        return mapOf(
            "platform" to platform,
            "packageId" to packageId,
            "name" to name,
            "icon" to icon,
            "category" to category,
            "isSystemApp" to isSystemApp,
        )
    }
}
