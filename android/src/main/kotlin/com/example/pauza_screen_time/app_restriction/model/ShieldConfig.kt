package com.example.pauza_screen_time.app_restriction.model

import android.util.Base64
import org.json.JSONObject

/**
 * Data class representing shield overlay configuration from Flutter.
 *
 * This model holds all visual and behavioral configuration for the blocking
 * shield overlay, including colors, text, button labels, and icon data.
 */
data class ShieldConfig(
    val title: String,
    val subtitle: String?,
    val backgroundColor: Int,
    val titleColor: Int,
    val subtitleColor: Int,
    val backgroundBlurStyle: String?,
    val iconBytes: ByteArray?,
    val primaryButtonLabel: String?,
    val primaryButtonBackgroundColor: Int?,
    val primaryButtonTextColor: Int?,
    val secondaryButtonLabel: String?,
    val secondaryButtonTextColor: Int?
) {
    companion object {
        /**
         * Default configuration used when no Flutter configuration is provided.
         */
        val DEFAULT = ShieldConfig(
            title = "App Blocked",
            subtitle = "This app has been restricted.",
            backgroundColor = 0xFF1A1A2E.toInt(),
            titleColor = 0xFFFFFFFF.toInt(),
            subtitleColor = 0xFFB0B0B0.toInt(),
            backgroundBlurStyle = null,
            iconBytes = null,
            primaryButtonLabel = "OK",
            primaryButtonBackgroundColor = 0xFF6366F1.toInt(),
            primaryButtonTextColor = 0xFFFFFFFF.toInt(),
            secondaryButtonLabel = null,
            secondaryButtonTextColor = null
        )

        private const val KEY_TITLE = "title"
        private const val KEY_SUBTITLE = "subtitle"
        private const val KEY_BACKGROUND_COLOR = "backgroundColor"
        private const val KEY_TITLE_COLOR = "titleColor"
        private const val KEY_SUBTITLE_COLOR = "subtitleColor"
        private const val KEY_BACKGROUND_BLUR_STYLE = "backgroundBlurStyle"
        private const val KEY_ICON_BASE64 = "iconBase64"
        private const val KEY_PRIMARY_BUTTON_LABEL = "primaryButtonLabel"
        private const val KEY_PRIMARY_BUTTON_BACKGROUND_COLOR = "primaryButtonBackgroundColor"
        private const val KEY_PRIMARY_BUTTON_TEXT_COLOR = "primaryButtonTextColor"
        private const val KEY_SECONDARY_BUTTON_LABEL = "secondaryButtonLabel"
        private const val KEY_SECONDARY_BUTTON_TEXT_COLOR = "secondaryButtonTextColor"

        /**
         * Creates a ShieldConfig from a Flutter method channel map.
         *
         * @param configMap Map containing configuration parameters from Flutter
         * @return Parsed ShieldConfig instance
         */
        fun fromMap(configMap: Map<String, Any?>): ShieldConfig {
            return ShieldConfig(
                title = configMap["title"] as? String ?: "App Blocked",
                subtitle = configMap["subtitle"] as? String,
                backgroundColor = (configMap["backgroundColor"] as? Number)?.toInt() ?: 0xFF1A1A2E.toInt(),
                titleColor = (configMap["titleColor"] as? Number)?.toInt() ?: 0xFFFFFFFF.toInt(),
                subtitleColor = (configMap["subtitleColor"] as? Number)?.toInt() ?: 0xFFB0B0B0.toInt(),
                backgroundBlurStyle = configMap["backgroundBlurStyle"] as? String,
                iconBytes = configMap["iconBytes"] as? ByteArray,
                primaryButtonLabel = configMap["primaryButtonLabel"] as? String,
                primaryButtonBackgroundColor = (configMap["primaryButtonBackgroundColor"] as? Number)?.toInt(),
                primaryButtonTextColor = (configMap["primaryButtonTextColor"] as? Number)?.toInt(),
                secondaryButtonLabel = configMap["secondaryButtonLabel"] as? String,
                secondaryButtonTextColor = (configMap["secondaryButtonTextColor"] as? Number)?.toInt()
            )
        }

        fun toJson(config: ShieldConfig): String {
            val payload = JSONObject()
                .put(KEY_TITLE, config.title)
                .put(KEY_SUBTITLE, config.subtitle)
                .put(KEY_BACKGROUND_COLOR, config.backgroundColor)
                .put(KEY_TITLE_COLOR, config.titleColor)
                .put(KEY_SUBTITLE_COLOR, config.subtitleColor)
                .put(KEY_BACKGROUND_BLUR_STYLE, config.backgroundBlurStyle)
                .put(KEY_PRIMARY_BUTTON_LABEL, config.primaryButtonLabel)
                .put(KEY_PRIMARY_BUTTON_BACKGROUND_COLOR, config.primaryButtonBackgroundColor)
                .put(KEY_PRIMARY_BUTTON_TEXT_COLOR, config.primaryButtonTextColor)
                .put(KEY_SECONDARY_BUTTON_LABEL, config.secondaryButtonLabel)
                .put(KEY_SECONDARY_BUTTON_TEXT_COLOR, config.secondaryButtonTextColor)

            val iconBytes = config.iconBytes
            if (iconBytes != null) {
                payload.put(KEY_ICON_BASE64, Base64.encodeToString(iconBytes, Base64.NO_WRAP))
            } else {
                payload.put(KEY_ICON_BASE64, JSONObject.NULL)
            }

            return payload.toString()
        }

        /**
         * Deserializes a [ShieldConfig] from its persisted JSON representation.
         *
         * @throws org.json.JSONException if [serialized] is not valid JSON.
         * @throws IllegalArgumentException if required fields are corrupt or undecodable.
         */
        fun fromJson(serialized: String): ShieldConfig {
            val payload = JSONObject(serialized)
            val iconBase64 = if (payload.has(KEY_ICON_BASE64) && !payload.isNull(KEY_ICON_BASE64)) {
                payload.getString(KEY_ICON_BASE64).trim()
            } else {
                ""
            }
            val iconBytes = if (iconBase64.isNotEmpty()) {
                try {
                    Base64.decode(iconBase64, Base64.DEFAULT)
                } catch (e: IllegalArgumentException) {
                    throw IllegalArgumentException("Shield icon bytes are not valid Base64", e)
                }
            } else {
                null
            }

            return ShieldConfig(
                title = payload.optString(KEY_TITLE, "App Blocked"),
                subtitle = payload.optStringOrNull(KEY_SUBTITLE),
                backgroundColor = payload.optInt(KEY_BACKGROUND_COLOR, 0xFF1A1A2E.toInt()),
                titleColor = payload.optInt(KEY_TITLE_COLOR, 0xFFFFFFFF.toInt()),
                subtitleColor = payload.optInt(KEY_SUBTITLE_COLOR, 0xFFB0B0B0.toInt()),
                backgroundBlurStyle = payload.optStringOrNull(KEY_BACKGROUND_BLUR_STYLE),
                iconBytes = iconBytes,
                primaryButtonLabel = payload.optStringOrNull(KEY_PRIMARY_BUTTON_LABEL),
                primaryButtonBackgroundColor = payload.optIntOrNull(KEY_PRIMARY_BUTTON_BACKGROUND_COLOR),
                primaryButtonTextColor = payload.optIntOrNull(KEY_PRIMARY_BUTTON_TEXT_COLOR),
                secondaryButtonLabel = payload.optStringOrNull(KEY_SECONDARY_BUTTON_LABEL),
                secondaryButtonTextColor = payload.optIntOrNull(KEY_SECONDARY_BUTTON_TEXT_COLOR),
            )
        }
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as ShieldConfig
        return title == other.title &&
            subtitle == other.subtitle &&
            backgroundColor == other.backgroundColor &&
            titleColor == other.titleColor &&
            subtitleColor == other.subtitleColor &&
            backgroundBlurStyle == other.backgroundBlurStyle &&
            iconBytes?.contentEquals(other.iconBytes) ?: (other.iconBytes == null) &&
            primaryButtonLabel == other.primaryButtonLabel &&
            primaryButtonBackgroundColor == other.primaryButtonBackgroundColor &&
            primaryButtonTextColor == other.primaryButtonTextColor &&
            secondaryButtonLabel == other.secondaryButtonLabel &&
            secondaryButtonTextColor == other.secondaryButtonTextColor
    }

    override fun hashCode(): Int {
        var result = title.hashCode()
        result = 31 * result + (subtitle?.hashCode() ?: 0)
        result = 31 * result + backgroundColor
        result = 31 * result + titleColor
        result = 31 * result + subtitleColor
        result = 31 * result + (backgroundBlurStyle?.hashCode() ?: 0)
        result = 31 * result + (iconBytes?.contentHashCode() ?: 0)
        result = 31 * result + (primaryButtonLabel?.hashCode() ?: 0)
        result = 31 * result + (primaryButtonBackgroundColor ?: 0)
        result = 31 * result + (primaryButtonTextColor ?: 0)
        result = 31 * result + (secondaryButtonLabel?.hashCode() ?: 0)
        result = 31 * result + (secondaryButtonTextColor ?: 0)
        return result
    }
}

private fun JSONObject.optStringOrNull(key: String): String? {
    return if (has(key) && !isNull(key)) {
        getString(key)
    } else {
        null
    }
}

private fun JSONObject.optIntOrNull(key: String): Int? {
    return if (has(key) && !isNull(key)) {
        optInt(key)
    } else {
        null
    }
}
