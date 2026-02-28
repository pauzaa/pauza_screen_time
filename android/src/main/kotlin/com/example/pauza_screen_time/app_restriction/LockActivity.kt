package com.example.pauza_screen_time.app_restriction

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.view.WindowCompat
import com.example.pauza_screen_time.app_restriction.model.ShieldConfig
import com.example.pauza_screen_time.app_restriction.overlay.ShieldOverlayContent
import com.example.pauza_screen_time.app_restriction.storage.ShieldConfigStore

/**
 * Fullscreen lock activity that replaces the accessibility overlay approach.
 *
 * Launched by [AppMonitoringService] when a restricted app is detected in the
 * foreground. Displays the same Compose-based shield UI ([ShieldOverlayContent])
 * previously shown via [WindowManager] overlay.
 *
 * Key behaviors:
 * - Runs in its own task (`:pauza_lock` affinity) so it does not interfere with
 *   the Flutter host activity.
 * - Excluded from recents.
 * - Back press is intercepted (no-op).
 * - Dismissable via [ACTION_DISMISS] broadcast or button tap (navigates HOME).
 * - Tracks visibility through [LockVisibilityState] singleton.
 */
class LockActivity : ComponentActivity() {

    companion object {
        private const val TAG = "LockActivity"
        const val EXTRA_BLOCKED_PACKAGE = "blocked_package_id"
        const val ACTION_DISMISS = "com.example.pauza_screen_time.DISMISS_LOCK"
    }

    private var blockedPackageId: String? = null

    private val dismissReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            Log.d(TAG, "Dismiss broadcast received")
            finishAndGoHome()
        }
    }

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

        blockedPackageId = intent?.getStringExtra(EXTRA_BLOCKED_PACKAGE)
        LockVisibilityState.markVisible(blockedPackageId ?: "")
        Log.d(TAG, "onCreate: blockedPackage=$blockedPackageId")

        val config = ShieldConfigStore.getInstance(applicationContext).loadConfig()
            ?: ShieldConfig.DEFAULT

        setContent {
            ShieldOverlayContent(
                config = config,
                onPrimaryClick = { finishAndGoHome() },
                onSecondaryClick = { finishAndGoHome() },
            )
        }

        // Register dismiss broadcast receiver
        val filter = IntentFilter(ACTION_DISMISS)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(dismissReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(dismissReceiver, filter)
        }

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
        val newPackageId = intent.getStringExtra(EXTRA_BLOCKED_PACKAGE)
        if (newPackageId != null && newPackageId != blockedPackageId) {
            Log.d(TAG, "onNewIntent: switching from $blockedPackageId to $newPackageId")
            blockedPackageId = newPackageId
            LockVisibilityState.markVisible(newPackageId)
        }
    }

    override fun onResume() {
        super.onResume()
        LockVisibilityState.markVisible(blockedPackageId ?: "")
    }

    override fun onStop() {
        super.onStop()
        // If we're not finishing (e.g. notification shade pulled down), re-launch
        // self to force back to foreground. This prevents bypass via notifications.
        if (!isFinishing) {
            Log.d(TAG, "onStop without finishing — scheduling self re-launch")
            val relaunchIntent = Intent(this, LockActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_BLOCKED_PACKAGE, blockedPackageId)
            }
            try {
                startActivity(relaunchIntent)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to re-launch self from onStop", e)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(dismissReceiver)
        } catch (_: Exception) {
            // Receiver may already be unregistered
        }
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
        finish()
        Log.d(TAG, "finishAndGoHome: navigated home and finishing")
    }
}
