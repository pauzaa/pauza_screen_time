package com.example.pauza_screen_time.app_restriction

/**
 * Process-wide singleton tracking [LockActivity] visibility.
 *
 * Used by [AppMonitoringService] to guard against duplicate launches and by
 * session controllers to dismiss the lock when enforcement ends.
 *
 * All fields are @Volatile for safe cross-thread reads from the accessibility
 * service main thread and any background callers.
 */
object LockVisibilityState {

    @Volatile
    var isLockVisible: Boolean = false
        private set

    @Volatile
    var currentBlockedPackage: String? = null
        private set

    @Volatile
    private var lastLaunchTimestamp: Long = 0L

    /** Called from [LockActivity.onCreate] / [LockActivity.onResume]. */
    fun markVisible(packageId: String) {
        isLockVisible = true
        currentBlockedPackage = packageId
    }

    /** Called from [LockActivity.onDestroy] and [LockActivity.finishAndGoHome]. */
    fun markHidden() {
        isLockVisible = false
        currentBlockedPackage = null
    }

    /** Called immediately after [startActivity] for the lock intent. */
    fun markLaunched(packageId: String) {
        lastLaunchTimestamp = System.currentTimeMillis()
        currentBlockedPackage = packageId
    }

    /**
     * Returns `true` when a new launch should be suppressed, either because:
     * - the lock is already visible for the same [packageId], or
     * - a launch was attempted less than [throttleMs] ago.
     */
    fun shouldSuppressLaunch(packageId: String, now: Long, throttleMs: Long): Boolean {
        if (isLockVisible && currentBlockedPackage == packageId) return true
        if (now - lastLaunchTimestamp < throttleMs) return true
        return false
    }
}
