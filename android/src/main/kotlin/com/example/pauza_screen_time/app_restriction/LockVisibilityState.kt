package com.example.pauza_screen_time.app_restriction

import android.os.Handler
import android.os.Looper
import java.util.concurrent.atomic.AtomicReference

/**
 * Process-wide singleton tracking [LockActivity] visibility.
 *
 * Used by [AppMonitoringService] to guard against duplicate launches and by
 * session controllers to dismiss the lock when enforcement ends.
 *
 * Thread-safety is achieved via an [AtomicReference] wrapping an immutable
 * [Snapshot] data class, ensuring compound reads are always consistent.
 *
 * Dismiss communication uses an in-process callback ([onDismissRequest]) instead
 * of a system broadcast, eliminating the risk of third-party apps sending a
 * spoofed dismiss intent on pre-Tiramisu devices.
 */
object LockVisibilityState {

    /**
     * Immutable snapshot of the lock visibility state.
     * All state reads/writes go through [AtomicReference] to avoid
     * non-atomic volatile compound reads.
     */
    data class Snapshot(
        val isLockVisible: Boolean = false,
        val currentBlockedPackage: String? = null,
        val lastLaunchTimestamp: Long = 0L,
    )

    private val state = AtomicReference(Snapshot())

    /** Lazy to avoid [Looper] initialization in pure-JVM unit tests. */
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    /**
     * Callback invoked when an in-process caller requests the lock to dismiss.
     * Set by [LockActivity.onCreate], cleared on [LockActivity.onDestroy].
     */
    @Volatile
    var onDismissRequest: (() -> Unit)? = null

    /** Convenience accessor: whether the lock is currently visible. */
    val isLockVisible: Boolean
        get() = state.get().isLockVisible

    /** Convenience accessor: the package the lock is currently blocking. */
    val currentBlockedPackage: String?
        get() = state.get().currentBlockedPackage

    /** Returns an atomic snapshot of the current state. */
    fun snapshot(): Snapshot = state.get()

    /** Called from [LockActivity.onCreate] / [LockActivity.onResume]. */
    fun markVisible(packageId: String) {
        state.updateAndGet { it.copy(isLockVisible = true, currentBlockedPackage = packageId) }
    }

    /** Called from [LockActivity.onDestroy] and [LockActivity.finishAndGoHome]. */
    fun markHidden() {
        state.updateAndGet { it.copy(isLockVisible = false, currentBlockedPackage = null) }
    }

    /** Called immediately after [startActivity] for the lock intent. */
    fun markLaunched(packageId: String) {
        state.updateAndGet {
            it.copy(lastLaunchTimestamp = System.currentTimeMillis(), currentBlockedPackage = packageId)
        }
    }

    /**
     * Requests the currently visible [LockActivity] to dismiss itself.
     * Safe to call from any thread; the callback is always dispatched on the
     * main thread so that [Activity.finish] / [Activity.startActivity] run on
     * the UI thread.
     */
    fun requestDismiss() {
        val callback = onDismissRequest ?: return
        if (Looper.myLooper() == Looper.getMainLooper()) {
            callback.invoke()
        } else {
            mainHandler.post { callback.invoke() }
        }
    }

    /**
     * Returns `true` when a new launch should be suppressed, either because:
     * - the lock is already visible for the same [packageId], or
     * - a launch for the same [packageId] was attempted less than [throttleMs] ago.
     */
    fun shouldSuppressLaunch(packageId: String, now: Long, throttleMs: Long): Boolean {
        val snap = state.get()
        if (snap.isLockVisible && snap.currentBlockedPackage == packageId) return true
        if (now - snap.lastLaunchTimestamp < throttleMs && snap.currentBlockedPackage == packageId) return true
        return false
    }

    /**
     * Resets all state. Intended for testing only.
     */
    internal fun reset() {
        state.set(Snapshot())
        onDismissRequest = null
    }
}
