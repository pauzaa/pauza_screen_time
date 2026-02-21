package com.example.pauza_screen_time.app_restriction

import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.ComposeView
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.example.pauza_screen_time.app_restriction.model.ShieldConfig
import com.example.pauza_screen_time.app_restriction.overlay.OverlayLifecycleOwner
import com.example.pauza_screen_time.app_restriction.overlay.OverlaySavedStateRegistryOwner
import com.example.pauza_screen_time.app_restriction.overlay.ShieldOverlayContent

/**
 * Manages the shield overlay display on Android using Jetpack Compose.
 *
 * This singleton class handles the overlay lifecycle including:
 * - Storing shield configuration from Flutter
 * - Displaying shield overlay using WindowManager with Compose UI
 * - Hiding overlay and navigating to home screen
 * - Handling button taps and navigating to home
 *
 * Uses TYPE_ACCESSIBILITY_OVERLAY for the overlay window type, which requires
 * the AccessibilityService to be enabled.
 */
class ShieldOverlayManager private constructor(context: Context) {

    companion object {
        private const val TAG = "ShieldOverlayManager"
        private const val PREFS_NAME = "app_restriction_shield_prefs"
        private const val KEY_SHIELD_CONFIG = "shield_config"

        @Volatile
        private var instance: ShieldOverlayManager? = null

        /**
         * Gets the singleton instance, creating it if necessary.
         *
         * @param context Application context
         * @return The ShieldOverlayManager singleton
         */
        fun getInstance(context: Context): ShieldOverlayManager {
            return instance ?: synchronized(this) {
                instance ?: ShieldOverlayManager(context.applicationContext).also {
                    instance = it
                }
            }
        }

        /**
         * Gets the existing instance without creating a new one.
         *
         * @return The existing instance or null
         */
        fun getInstanceOrNull(): ShieldOverlayManager? = instance
    }

    // WindowManager for overlay display
    private val appContext: Context = context.applicationContext
    private var overlayContext: Context = appContext

    private val windowManager: WindowManager
        get() = overlayContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    // Current overlay view reference
    private var overlayView: ComposeView? = null

    // Current blocked package (for event emission)
    private var currentBlockedPackage: String? = null

    private val preferences =
        appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // Shield configuration (stored from Flutter)
    private var configuration by mutableStateOf<ShieldConfig?>(null)

    init {
        configuration = loadPersistedConfig()
    }

    /**
     * Configures the shield appearance from Flutter method channel data.
     *
     * @param configMap Map containing shield configuration parameters
     */
    fun configure(configMap: Map<String, Any?>) {
        val config = ShieldConfig.fromMap(configMap)
        configuration = config
        persistConfig(config)
        Log.d(TAG, "Shield configured: ${config.title}")
    }

    /**
     * Shows the shield overlay for a blocked app.
     *
     * @param packageId The package ID of the blocked app
     */
    fun showShield(packageId: String, contextOverride: Context? = null) {
        if (overlayView != null) {
            // If we're already showing for the same package, no-op.
            // If a different restricted app becomes foreground, update by recreating.
            if (currentBlockedPackage == packageId) {
                Log.d(TAG, "Shield already showing for: $packageId")
                return
            }
            Log.d(TAG, "Shield showing for $currentBlockedPackage; switching to $packageId")
            hideShield()
        }

        if (contextOverride != null) {
            overlayContext = contextOverride
        }

        currentBlockedPackage = packageId

        val config = configuration ?: ShieldConfig.DEFAULT

        // Create the overlay ComposeView
        val composeView = ComposeView(overlayContext).apply {
            setViewTreeLifecycleOwner(OverlayLifecycleOwner())
            setViewTreeSavedStateRegistryOwner(OverlaySavedStateRegistryOwner())

            setContent {
                ShieldOverlayContent(
                    config = config,
                    onPrimaryClick = { handleButtonTap("primary") },
                    onSecondaryClick = { handleButtonTap("secondary") }
                )
            }
        }

        // Configure window parameters
        val params = createWindowParams()

        try {
            windowManager.addView(composeView, params)
            overlayView = composeView
            Log.d(TAG, "Shield shown for: $packageId")
        } catch (e: Exception) {
            overlayView = null
            currentBlockedPackage = null
            overlayContext = appContext
            Log.e(TAG, "Failed to show shield overlay", e)
        }
    }

    /**
     * Hides the shield overlay if currently visible.
     */
    fun hideShield() {
        overlayView?.let { view ->
            try {
                windowManager.removeView(view)
                Log.d(TAG, "Shield hidden")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to hide shield overlay", e)
            }
        }
        overlayView = null
        currentBlockedPackage = null
        overlayContext = appContext
    }

    /**
     * Checks if the shield overlay is currently visible.
     *
     * @return true if overlay is showing
     */
    fun isShowing(): Boolean = overlayView != null

    /**
     * Gets the package name this shield is currently shown for, if any.
     */
    fun getCurrentBlockedPackage(): String? = currentBlockedPackage

    /**
     * Creates WindowManager.LayoutParams for the overlay window.
     */
    private fun createWindowParams(): WindowManager.LayoutParams {
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }
    }

    /**
     * Handles button tap events and navigates to home.
     */
    private fun handleButtonTap(buttonType: String) {
        val packageId = currentBlockedPackage ?: return

        // Navigate to home screen (matching iOS .close behavior)
        navigateToHome()

        // Hide the shield
        hideShield()
    }

    /**
     * Navigates to the home screen launcher.
     */
    private fun navigateToHome() {
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        appContext.startActivity(homeIntent)
    }

    private fun persistConfig(config: ShieldConfig) {
        preferences.edit()
            .putString(KEY_SHIELD_CONFIG, ShieldConfig.toJson(config))
            .apply()
    }

    private fun loadPersistedConfig(): ShieldConfig? {
        val serialized = preferences.getString(KEY_SHIELD_CONFIG, null)?.trim().orEmpty()
        if (serialized.isEmpty()) {
            return null
        }
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
}
