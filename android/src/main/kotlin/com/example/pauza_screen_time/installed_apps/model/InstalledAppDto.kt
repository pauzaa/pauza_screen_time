package com.example.pauza_screen_time.installed_apps.model

/**
 * Data-transfer object representing a single installed application.
 *
 * Encapsulates all information exchanged over the Flutter method channel.
 * [fromMap] is the canonical deserialisation path; [toChannelMap] is the
 * canonical serialisation path. Both are fail-fast: missing or wrong-typed
 * fields throw [IllegalArgumentException] immediately.
 */
class InstalledAppDto(
    val platform: String,
    val packageId: String,
    val name: String,
    val icon: ByteArray?,
    val category: String?,
    val isSystemApp: Boolean,
) {
    companion object {
        private const val PLATFORM_ANDROID = "android"

        /**
         * Deserialises a raw method-channel map into an [InstalledAppDto].
         *
         * @throws IllegalArgumentException if any required field is absent or has the wrong type.
         */
        fun fromMap(map: Map<String, Any?>): InstalledAppDto {
            val platform = map["platform"] as? String
                ?: throw IllegalArgumentException(
                    "InstalledAppDto: 'platform' must be a non-null String, got ${map["platform"]}"
                )
            if (platform != PLATFORM_ANDROID) {
                throw IllegalArgumentException(
                    "InstalledAppDto: expected platform='android', got '$platform'"
                )
            }
            val packageId = map["packageId"] as? String
                ?: throw IllegalArgumentException(
                    "InstalledAppDto: 'packageId' must be a non-null String, got ${map["packageId"]}"
                )
            if (packageId.isBlank()) {
                throw IllegalArgumentException("InstalledAppDto: 'packageId' must not be blank")
            }
            val name = map["name"] as? String
                ?: throw IllegalArgumentException(
                    "InstalledAppDto: 'name' must be a non-null String, got ${map["name"]}"
                )
            val iconRaw = map["icon"]
            if (iconRaw != null && iconRaw !is ByteArray) {
                throw IllegalArgumentException(
                    "InstalledAppDto: 'icon' must be ByteArray or null, got ${iconRaw::class.simpleName}"
                )
            }
            val category = map["category"] as? String
            val isSystemApp = map["isSystemApp"] as? Boolean ?: false

            return InstalledAppDto(
                platform = platform,
                packageId = packageId,
                name = name,
                icon = iconRaw as? ByteArray,
                category = category,
                isSystemApp = isSystemApp,
            )
        }
    }

    /** Serialises this DTO to the method-channel wire format. */
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

    // ByteArray's default equals/hashCode use reference equality, which breaks
    // structural comparison. Override explicitly to use content equality.
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is InstalledAppDto) return false
        return platform == other.platform &&
            packageId == other.packageId &&
            name == other.name &&
            icon.contentEquals(other.icon) &&
            category == other.category &&
            isSystemApp == other.isSystemApp
    }

    override fun hashCode(): Int {
        var result = platform.hashCode()
        result = 31 * result + packageId.hashCode()
        result = 31 * result + name.hashCode()
        result = 31 * result + icon.contentHashCode()
        result = 31 * result + (category?.hashCode() ?: 0)
        result = 31 * result + isSystemApp.hashCode()
        return result
    }

    override fun toString(): String =
        "InstalledAppDto(platform=$platform, packageId=$packageId, name=$name, " +
            "hasIcon=${icon != null}, category=$category, isSystemApp=$isSystemApp)"
}

// Extension helpers for nullable ByteArray content comparison
private fun ByteArray?.contentEquals(other: ByteArray?): Boolean {
    if (this === other) return true
    if (this == null || other == null) return false
    return java.util.Arrays.equals(this, other)
}

private fun ByteArray?.contentHashCode(): Int = if (this != null) java.util.Arrays.hashCode(this) else 0
