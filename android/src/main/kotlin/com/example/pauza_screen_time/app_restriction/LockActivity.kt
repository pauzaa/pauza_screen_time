package com.example.pauza_screen_time.app_restriction

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.mutableStateOf
import androidx.core.view.WindowCompat
import com.example.pauza_screen_time.app_restriction.model.ShieldConfig
import com.example.pauza_screen_time.app_restriction.overlay.ShieldOverlayContent
import com.example.pauza_screen_time.app_restriction.storage.ShieldConfigStore

/**
 * Fullscreen lock activity that displays the shield screen for restricted apps.
 *
 * Launched by [AppMonitoringService] when a restricted app is detected in the
 * foreground. Displays the Compose-based shield UI ([ShieldOverlayContent]).
 *
 * Key behaviors:
 * - Runs in its own task (`:pauza_lock` affinity) so it does not interfere with
 *   the Flutter host activity.
 * - Excluded from recents.
 * - Back press is intercepted (no-op).
 * - Dismissable via in-process callback on [LockVisibilityState] or button tap
 *   (navigates HOME).
 * - Tracks visibility through [LockVisibilityState] singleton.
 */
class LockActivity : ComponentActivity() {

    companion object {
        private const val TAG = "LockActivity"
        const val EXTRA_BLOCKED_PACKAGE = "blocked_package_id"

        /** Minimum interval between self-relaunch attempts from [onStop]. */
        private const val RELAUNCH_THROTTLE_MS = 1_000L

        /** Delay before self-relaunch to allow accessibility service to dismiss if needed. */
        private const val RELAUNCH_DELAY_MS = 400L
    }

    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    private var blockedPackageId: String? = null

    /** Timestamp of the last self-relaunch from [onStop], used to prevent infinite loops. */
    private var lastRelaunchTimestamp: Long = 0L

    /** Mutable Compose state so the UI recomposes when config changes. */
    private val shieldConfig = mutableStateOf(ShieldConfig.DEFAULT)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Fullscreen / edge-to-edge
        WindowCompat.setDecorFitsSystemWindows(window, false)
        enableEdgeToEdge()

        // Show over lock screen if device is locked
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        blockedPackageId = extractAndValidatePackageId(intent)
        if (blockedPackageId == null) {
            Log.w(TAG, "onCreate: missing or empty EXTRA_BLOCKED_PACKAGE — finishing immediately")
            finish()
            return
        }

        LockVisibilityState.markVisible(blockedPackageId!!)
        Log.d(TAG, "onCreate: blockedPackage=$blockedPackageId")

        shieldConfig.value = loadShieldConfig()

        setContent {
            ShieldOverlayContent(
                config = shieldConfig.value,
                onPrimaryClick = { finishAndGoHome() },
                onSecondaryClick = { finishAndGoHome() },
            )
        }

        // Register in-process dismiss callback
        LockVisibilityState.onDismissRequest = { finishAndGoHome() }

        // Block back press
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                // No-op: prevent dismissal via back button
                Log.d(TAG, "Back press blocked")
            }
        })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Update blocked package if re-launched for a different app
        val newPackageId = extractAndValidatePackageId(intent)
        if (newPackageId == null) {
            Log.w(TAG, "onNewIntent: missing or empty EXTRA_BLOCKED_PACKAGE — ignoring")
            return
        }
        if (newPackageId != blockedPackageId) {
            Log.d(TAG, "onNewIntent: switching from $blockedPackageId to $newPackageId")
            blockedPackageId = newPackageId
            LockVisibilityState.markVisible(newPackageId)
        }
        // Always reload config so Compose UI updates if shield was reconfigured
        shieldConfig.value = loadShieldConfig()
    }

    override fun onResume() {
        super.onResume()
        blockedPackageId?.let { LockVisibilityState.markVisible(it) }
    }

    override fun onStop() {
        super.onStop()
        // If we're not finishing (e.g. notification shade pulled down), schedule a
        // delayed self re-launch. The delay allows the accessibility service to detect
        // the launcher (HOME press) and dismiss the lock before we relaunch.
        if (!isFinishing) {
            LockVisibilityState.markStopped()
            val now = System.currentTimeMillis()
            if (now - lastRelaunchTimestamp < RELAUNCH_THROTTLE_MS) {
                Log.d(TAG, "onStop: relaunch throttled (too recent)")
                return
            }
            lastRelaunchTimestamp = now
            Log.d(TAG, "onStop without finishing — scheduling delayed self re-launch")
            mainHandler.postDelayed({
                if (isFinishing || !LockVisibilityState.isLockVisible) {
                    Log.d(TAG, "onStop: lock dismissed or finishing; skipping relaunch")
                    return@postDelayed
                }
                val relaunchIntent = Intent(this, LockActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_NO_ANIMATION
                    putExtra(EXTRA_BLOCKED_PACKAGE, blockedPackageId)
                }
                try {
                    startActivity(relaunchIntent)
                } catch (e: Exception) {
                    Log.w(
                        TAG,
                        "Failed to re-launch self from onStop " +
                            "(API ${Build.VERSION.SDK_INT}, ${e.javaClass.simpleName}: ${e.message})",
                    )
                }
            }, RELAUNCH_DELAY_MS)
        }
    }

    override fun onDestroy() {
        mainHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
        LockVisibilityState.onDismissRequest = null
        // markHidden is idempotent — safe even if finishAndGoHome already called it.
        // We call it here as a safety net for cases where the Activity is destroyed
        // without going through finishAndGoHome (e.g. system-initiated destruction).
        LockVisibilityState.markHidden()
        Log.d(TAG, "onDestroy: visibility cleared")
    }

    private fun finishAndGoHome() {
        LockVisibilityState.markHidden()
        // Navigate to home first, then finish
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(homeIntent)
        Log.d(TAG, "finishAndGoHome: navigated home and finishing")
        finish()
    }

    /**
     * Extracts and validates the blocked package ID from the intent.
     * Returns null if the extra is missing or blank, instead of falling
     * back to an empty string.
     */
    private fun extractAndValidatePackageId(intent: Intent?): String? {
        val value = intent?.getStringExtra(EXTRA_BLOCKED_PACKAGE)
        return if (value.isNullOrBlank()) null else value
    }

    private fun loadShieldConfig(): ShieldConfig {
        return ShieldConfigStore.getInstance(applicationContext).loadConfig()
            ?: ShieldConfig.DEFAULT
    }
}
