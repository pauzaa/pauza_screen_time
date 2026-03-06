package com.example.pauza_screen_time.app_restriction.storage

import android.content.Context
import android.util.Log
import com.example.pauza_screen_time.app_restriction.model.ShieldConfig

/**
 * Standalone persistence store for [ShieldConfig].
 *
 * Used by [LockActivity] and [ConfigureShieldUseCase] to read and write the
 * shield configuration independently of the UI layer.
 */
class ShieldConfigStore private constructor(context: Context) {

    companion object {
        private const val TAG = "ShieldConfigStore"
        private const val PREFS_NAME = "app_restriction_shield_prefs"
        private const val KEY_SHIELD_CONFIG = "shield_config"

        @Volatile
        private var instance: ShieldConfigStore? = null

        fun getInstance(context: Context): ShieldConfigStore {
            return instance ?: synchronized(this) {
                instance ?: ShieldConfigStore(context.applicationContext).also {
                    instance = it
                }
            }
        }
    }

    private val preferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun configure(configMap: Map<String, Any?>) {
        val config = ShieldConfig.fromMap(configMap)
        persistConfig(config)
        Log.d(TAG, "Shield config persisted: ${config.title}")
    }

    fun loadConfig(): ShieldConfig? {
        val serialized = preferences.getString(KEY_SHIELD_CONFIG, null)?.trim().orEmpty()
        if (serialized.isEmpty()) return null
        return try {
            ShieldConfig.fromJson(serialized)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse persisted shield config; reverting to DEFAULT", e)
            preferences.edit()
                .remove(KEY_SHIELD_CONFIG)
                .apply()
            null
        }
    }

    private fun persistConfig(config: ShieldConfig) {
        preferences.edit()
            .putString(KEY_SHIELD_CONFIG, ShieldConfig.toJson(config))
            .apply()
    }
}