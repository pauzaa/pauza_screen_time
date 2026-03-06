package com.example.pauza_screen_time.app_restriction

import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Pure-JVM unit tests for [LockVisibilityState].
 *
 * These tests verify the atomic state management, suppress-launch logic, and
 * dismiss callback wiring without requiring an Android device/emulator.
 *
 * Note: [requestDismiss] main-thread dispatching cannot be tested here because
 * [android.os.Looper] is unavailable in plain unit tests. That path is covered
 * by verifying the callback is stored and invocable.
 */
internal class LockVisibilityStateTest {

    @BeforeTest
    fun setUp() {
        LockVisibilityState.reset()
    }

    @AfterTest
    fun tearDown() {
        LockVisibilityState.reset()
    }

    // -- Initial state --

    @Test
    fun initialState_isNotVisible() {
        assertFalse(LockVisibilityState.isLockVisible)
        assertNull(LockVisibilityState.currentBlockedPackage)
    }

    @Test
    fun initialSnapshot_hasDefaults() {
        val snap = LockVisibilityState.snapshot()
        assertFalse(snap.isLockVisible)
        assertNull(snap.currentBlockedPackage)
        assertEquals(0L, snap.lastLaunchTimestamp)
    }

    // -- markVisible / markHidden --

    @Test
    fun markVisible_setsVisibleAndPackage() {
        LockVisibilityState.markVisible("com.example.blocked")

        assertTrue(LockVisibilityState.isLockVisible)
        assertEquals("com.example.blocked", LockVisibilityState.currentBlockedPackage)
    }

    @Test
    fun markHidden_clearsVisibility() {
        LockVisibilityState.markVisible("com.example.blocked")
        LockVisibilityState.markHidden()

        assertFalse(LockVisibilityState.isLockVisible)
        assertNull(LockVisibilityState.currentBlockedPackage)
    }

    @Test
    fun markVisible_updatesPackageWhenCalledAgain() {
        LockVisibilityState.markVisible("com.example.app1")
        LockVisibilityState.markVisible("com.example.app2")

        assertTrue(LockVisibilityState.isLockVisible)
        assertEquals("com.example.app2", LockVisibilityState.currentBlockedPackage)
    }

    // -- markLaunched --

    @Test
    fun markLaunched_setsTimestampAndPackage() {
        LockVisibilityState.markLaunched("com.example.target")

        val snap = LockVisibilityState.snapshot()
        assertEquals("com.example.target", snap.currentBlockedPackage)
        assertTrue(snap.lastLaunchTimestamp > 0L)
        // isLockVisible remains false until markVisible is called
        assertFalse(snap.isLockVisible)
    }

    // -- shouldSuppressLaunch --

    @Test
    fun shouldSuppressLaunch_whenVisibleForSamePackage_returnsTrue() {
        LockVisibilityState.markVisible("com.example.blocked")

        val now = System.currentTimeMillis()
        assertTrue(LockVisibilityState.shouldSuppressLaunch("com.example.blocked", now, 800L))
    }

    @Test
    fun shouldSuppressLaunch_whenVisibleForDifferentPackage_returnsFalse() {
        LockVisibilityState.markVisible("com.example.other")

        val now = System.currentTimeMillis()
        assertFalse(LockVisibilityState.shouldSuppressLaunch("com.example.blocked", now, 800L))
    }

    @Test
    fun shouldSuppressLaunch_withinThrottleWindow_returnsTrue() {
        LockVisibilityState.markLaunched("com.example.blocked")

        val snap = LockVisibilityState.snapshot()
        // Call within throttle window
        val now = snap.lastLaunchTimestamp + 100L
        assertTrue(LockVisibilityState.shouldSuppressLaunch("com.example.blocked", now, 800L))
    }

    @Test
    fun shouldSuppressLaunch_afterThrottleWindowExpires_returnsFalse() {
        LockVisibilityState.markLaunched("com.example.blocked")

        val snap = LockVisibilityState.snapshot()
        // Call after throttle window
        val now = snap.lastLaunchTimestamp + 900L
        assertFalse(LockVisibilityState.shouldSuppressLaunch("com.example.blocked", now, 800L))
    }

    @Test
    fun shouldSuppressLaunch_withinThrottleButDifferentPackage_returnsFalse() {
        LockVisibilityState.markLaunched("com.example.other")

        val snap = LockVisibilityState.snapshot()
        val now = snap.lastLaunchTimestamp + 100L
        assertFalse(LockVisibilityState.shouldSuppressLaunch("com.example.blocked", now, 800L))
    }

    @Test
    fun shouldSuppressLaunch_notVisibleAndNoRecentLaunch_returnsFalse() {
        val now = System.currentTimeMillis()
        assertFalse(LockVisibilityState.shouldSuppressLaunch("com.example.blocked", now, 800L))
    }

    // -- Snapshot atomicity --

    @Test
    fun snapshot_returnsConsistentState() {
        LockVisibilityState.markVisible("com.example.blocked")
        LockVisibilityState.markLaunched("com.example.blocked")

        val snap = LockVisibilityState.snapshot()
        // markLaunched updates currentBlockedPackage and lastLaunchTimestamp but does
        // NOT touch isLockVisible, so visibility set by markVisible must be preserved.
        assertEquals("com.example.blocked", snap.currentBlockedPackage, "currentBlockedPackage must match after markLaunched")
        assertTrue(snap.lastLaunchTimestamp > 0L, "lastLaunchTimestamp must be set after markLaunched")
        assertTrue(snap.isLockVisible, "isLockVisible must remain true after markLaunched")
    }

    // -- reset --

    @Test
    fun reset_clearsAllState() {
        LockVisibilityState.markVisible("com.example.blocked")
        LockVisibilityState.onDismissRequest = { }

        LockVisibilityState.reset()

        assertFalse(LockVisibilityState.isLockVisible)
        assertNull(LockVisibilityState.currentBlockedPackage)
        assertNull(LockVisibilityState.onDismissRequest)
        assertEquals(LockVisibilityState.Snapshot(), LockVisibilityState.snapshot())
    }

    // -- onDismissRequest callback --

    @Test
    fun onDismissRequest_isNullByDefault() {
        assertNull(LockVisibilityState.onDismissRequest)
    }

    @Test
    fun onDismissRequest_canBeSetAndCleared() {
        var called = false
        LockVisibilityState.onDismissRequest = { called = true }

        // Invoke directly (bypassing requestDismiss which needs Looper)
        LockVisibilityState.onDismissRequest?.invoke()
        assertTrue(called)

        LockVisibilityState.onDismissRequest = null
        assertNull(LockVisibilityState.onDismissRequest)
    }
}
