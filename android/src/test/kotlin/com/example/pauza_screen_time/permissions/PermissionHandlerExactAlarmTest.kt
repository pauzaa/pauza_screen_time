package com.example.pauza_screen_time.permissions

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class PermissionHandlerExactAlarmTest {
    @Test
    fun checkPermission_exactAlarm_isGrantedOnPreAndroid12() {
        val handler = TestPermissionHandler(
            context = mockContext(),
            fakeSdkInt = Build.VERSION_CODES.R,
            exactAlarmsAllowed = false,
        )

        val status = handler.checkPermission(PermissionHandler.EXACT_ALARM_KEY)

        assertEquals(PermissionHandler.STATUS_GRANTED, status)
    }

    @Test
    fun checkPermission_exactAlarm_reflectsCapabilityOnAndroid12Plus() {
        val grantedHandler = TestPermissionHandler(
            context = mockContext(),
            fakeSdkInt = Build.VERSION_CODES.S,
            exactAlarmsAllowed = true,
        )
        val deniedHandler = TestPermissionHandler(
            context = mockContext(),
            fakeSdkInt = Build.VERSION_CODES.S,
            exactAlarmsAllowed = false,
        )

        assertEquals(
            PermissionHandler.STATUS_GRANTED,
            grantedHandler.checkPermission(PermissionHandler.EXACT_ALARM_KEY),
        )
        assertEquals(
            PermissionHandler.STATUS_DENIED,
            deniedHandler.checkPermission(PermissionHandler.EXACT_ALARM_KEY),
        )
    }

    @Test
    fun requestPermission_exactAlarm_launchesExactAlarmSettingsOnAndroid12Plus() {
        val handler = TestPermissionHandler(
            context = mockContext(),
            fakeSdkInt = Build.VERSION_CODES.S,
            exactAlarmsAllowed = false,
        )

        val started = handler.requestPermission(
            Mockito.mock(Activity::class.java),
            PermissionHandler.EXACT_ALARM_KEY,
        )

        assertTrue(started)
        assertEquals(
            listOf(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM),
            handler.launchedActions,
        )
        assertEquals(listOf<String?>("package:com.example.test"), handler.launchedData)
    }

    @Test
    fun requestPermission_exactAlarm_fallsBackToAppDetailsWhenPrimaryLaunchFails() {
        val handler = TestPermissionHandler(
            context = mockContext(),
            fakeSdkInt = Build.VERSION_CODES.S,
            exactAlarmsAllowed = false,
            failExactAlarmLaunch = true,
        )

        val started = handler.requestPermission(
            Mockito.mock(Activity::class.java),
            PermissionHandler.EXACT_ALARM_KEY,
        )

        assertFalse(started)
        assertEquals(
            listOf(
                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            ),
            handler.launchedActions,
        )
    }

    @Test
    fun openPermissionSettings_exactAlarm_fallsBackToAppDetailsWhenPrimaryLaunchFails() {
        val handler = TestPermissionHandler(
            context = mockContext(),
            fakeSdkInt = Build.VERSION_CODES.S,
            exactAlarmsAllowed = false,
            failExactAlarmLaunch = true,
        )

        handler.openPermissionSettings(
            Mockito.mock(Activity::class.java),
            PermissionHandler.EXACT_ALARM_KEY,
        )

        assertEquals(
            listOf(
                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            ),
            handler.launchedActions,
        )
    }

    private fun mockContext(): Context {
        val context = Mockito.mock(Context::class.java)
        Mockito.`when`(context.packageName).thenReturn("com.example.test")
        return context
    }
}

private class TestPermissionHandler(
    context: Context,
    private val fakeSdkInt: Int,
    private val exactAlarmsAllowed: Boolean,
    private val failExactAlarmLaunch: Boolean = false,
    private val failAppDetailsLaunch: Boolean = false,
) : PermissionHandler(context) {
    val launchedActions = mutableListOf<String>()
    val launchedData = mutableListOf<String?>()

    override fun sdkInt(): Int = fakeSdkInt

    override fun canScheduleExactAlarms(): Boolean = exactAlarmsAllowed

    override fun launchIntent(activity: Activity, intent: Intent): Boolean {
        launchedActions.add(intent.action.orEmpty())
        launchedData.add(intent.dataString)
        return when (intent.action) {
            Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM -> !failExactAlarmLaunch
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS -> !failAppDetailsLaunch
            else -> true
        }
    }
}
