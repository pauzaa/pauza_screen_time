package com.example.pauza_screen_time.app_restriction.usecase

import android.app.AlarmManager
import android.content.Context
import android.content.SharedPreferences
import com.example.pauza_screen_time.app_restriction.RestrictionManager
import com.example.pauza_screen_time.app_restriction.RestrictionSessionController
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduleEntry
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModeEntry
import com.example.pauza_screen_time.app_restriction.schedule.RestrictionScheduledModesStore
import org.mockito.Mockito
import java.time.LocalDate
import java.time.LocalTime
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

internal class SessionEnforcementUseCaseEndSessionTest {
    private lateinit var context: Context
    private val prefsByName = linkedMapOf<String, InMemorySharedPreferences>()

    @BeforeTest
    fun setUp() {
        resetSingleton(RestrictionManager::class.java, "instance")
        resetSingleton(
            Class.forName("com.example.pauza_screen_time.app_restriction.storage.RestrictionStorageRepository"),
            "instance",
        )
        resetSingleton(
            Class.forName("com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleLogger"),
            "instance",
        )
        context = Mockito.mock(Context::class.java)
        Mockito.`when`(context.applicationContext).thenReturn(context)
        Mockito.`when`(context.getSharedPreferences(Mockito.anyString(), Mockito.anyInt()))
            .thenAnswer { invocation ->
                val name = invocation.getArgument<String>(0)
                prefsByName.getOrPut(name) { InMemorySharedPreferences() }
            }
        Mockito.`when`(context.getSystemService(Context.ALARM_SERVICE))
            .thenReturn(Mockito.mock(AlarmManager::class.java))
    }

    @AfterTest
    fun tearDown() {
        resetSingleton(RestrictionManager::class.java, "instance")
        resetSingleton(
            Class.forName("com.example.pauza_screen_time.app_restriction.storage.RestrictionStorageRepository"),
            "instance",
        )
        resetSingleton(
            Class.forName("com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleLogger"),
            "instance",
        )
    }

    @Test
    fun endSession_clearsManualSession() {
        val manager = RestrictionManager.getInstance(context)
        manager.setActiveSession(
            modeId = "manual-focus",
            blockedAppIds = listOf("com.example.app"),
            source = RestrictionModeSource.MANUAL,
        )

        SessionEnforcementUseCase(context).endSession()

        assertNull(manager.getActiveSession())
    }

    @Test
    fun endSession_clearsScheduleSession() {
        val modeId = "schedule-focus"
        seedActiveScheduleMode(modeId)
        val manager = RestrictionManager.getInstance(context)

        SessionEnforcementUseCase(context).endSession()

        assertNull(manager.getActiveSession())
    }

    @Test
    fun endingScheduleSessionInsideActiveInterval_doesNotImmediatelyReactivate() {
        val modeId = "schedule-focus"
        seedActiveScheduleMode(modeId)
        val controller = RestrictionSessionController(context)
        val initial = controller.resolveSessionState()
        assertEquals(RestrictionModeSource.SCHEDULE, initial.activeModeSource)

        SessionEnforcementUseCase(context).endSession()

        val next = controller.resolveSessionState()
        assertEquals(RestrictionModeSource.NONE, next.activeModeSource)
        assertTrue(next.isInScheduleNow)
        val suppression = RestrictionManager.getInstance(context).getScheduleSuppression()
        assertNotNull(suppression)
        assertEquals(modeId, suppression.modeId)
    }

    @Test
    fun scheduleCanReactivateAfterSuppressionBoundaryExpires() {
        val modeId = "schedule-focus"
        seedActiveScheduleMode(modeId)
        val controller = RestrictionSessionController(context)
        val initial = controller.resolveSessionState()
        assertEquals(RestrictionModeSource.SCHEDULE, initial.activeModeSource)

        SessionEnforcementUseCase(context).endSession()
        RestrictionManager.getInstance(context).setScheduleSuppression(
            modeId = modeId,
            untilEpochMs = System.currentTimeMillis() - 1L,
        )

        val next = controller.resolveSessionState()
        assertEquals(RestrictionModeSource.SCHEDULE, next.activeModeSource)
        assertEquals(modeId, next.activeModeId)
    }

    @Test
    fun endSession_withoutActiveSession_throwsIllegalStateException() {
        try {
            SessionEnforcementUseCase(context).endSession()
            fail("Expected IllegalStateException when no active session exists")
        } catch (error: IllegalStateException) {
            assertEquals("No active restriction session to end", error.message)
        }
    }

    @Test
    fun endSession_withDuration_storesPendingEndEpochMs() {
        val manager = RestrictionManager.getInstance(context)
        manager.setActiveSession(
            modeId = "manual-focus",
            blockedAppIds = listOf("com.example.app"),
            source = RestrictionModeSource.MANUAL,
        )

        SessionEnforcementUseCase(context).endSession(durationMs = 5_000L)

        assertTrue(manager.getPendingEndSessionEpochMs(clearExpired = false) > 0L)
        assertNotNull(manager.getActiveSession())
    }

    @Test
    fun endSession_withDuration_withoutActiveSession_throwsIllegalStateException() {
        try {
            SessionEnforcementUseCase(context).endSession(durationMs = 5_000L)
            fail("Expected IllegalStateException when no active session exists")
        } catch (error: IllegalStateException) {
            assertEquals("No active restriction session to end", error.message)
        }
    }

    private fun seedActiveScheduleMode(modeId: String) {
        val scheduleStore = RestrictionScheduledModesStore(context)
        scheduleStore.setEnabled(true)
        scheduleStore.upsertMode(
            RestrictionScheduledModeEntry(
                modeId = modeId,
                schedule = activeScheduleForNow(),
                blockedAppIds = listOf("com.example.app"),
            ),
        )
    }

    private fun activeScheduleForNow(): RestrictionScheduleEntry {
        val day = LocalDate.now().dayOfWeek.value
        val now = LocalTime.now()
        val minute = now.hour * 60 + now.minute
        return if (minute < (24 * 60 - 1)) {
            RestrictionScheduleEntry(
                daysOfWeekIso = setOf(day),
                startMinutes = minute,
                endMinutes = minute + 1,
            )
        } else {
            RestrictionScheduleEntry(
                daysOfWeekIso = setOf(day),
                startMinutes = minute - 1,
                endMinutes = 1,
            )
        }
    }

    private fun resetSingleton(clazz: Class<*>, fieldName: String) {
        val field = clazz.getDeclaredField(fieldName)
        field.isAccessible = true
        field.set(null, null)
    }
}

private class InMemorySharedPreferences : SharedPreferences {
    private val values = linkedMapOf<String, Any?>()

    override fun getAll(): MutableMap<String, *> = values.toMutableMap()
    override fun getString(key: String?, defValue: String?): String? =
        (values[key] as? String) ?: defValue
    override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
        @Suppress("UNCHECKED_CAST") ((values[key] as? Set<String>)?.toMutableSet()) ?: defValues
    override fun getInt(key: String?, defValue: Int): Int =
        (values[key] as? Number)?.toInt() ?: defValue
    override fun getLong(key: String?, defValue: Long): Long =
        (values[key] as? Number)?.toLong() ?: defValue
    override fun getFloat(key: String?, defValue: Float): Float =
        (values[key] as? Number)?.toFloat() ?: defValue
    override fun getBoolean(key: String?, defValue: Boolean): Boolean =
        (values[key] as? Boolean) ?: defValue
    override fun contains(key: String?): Boolean = values.containsKey(key)
    override fun edit(): SharedPreferences.Editor = Editor(values)
    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}

    private class Editor(private val values: MutableMap<String, Any?>) : SharedPreferences.Editor {
        private val staged = linkedMapOf<String, Any?>()
        private val removals = linkedSetOf<String>()
        private var clearRequested = false

        override fun putString(key: String?, value: String?) = apply { if (key != null) { staged[key] = value; removals.remove(key) } }
        override fun putStringSet(key: String?, value: MutableSet<String>?) = apply { if (key != null) { staged[key] = value?.toSet(); removals.remove(key) } }
        override fun putInt(key: String?, value: Int) = apply { if (key != null) { staged[key] = value; removals.remove(key) } }
        override fun putLong(key: String?, value: Long) = apply { if (key != null) { staged[key] = value; removals.remove(key) } }
        override fun putFloat(key: String?, value: Float) = apply { if (key != null) { staged[key] = value; removals.remove(key) } }
        override fun putBoolean(key: String?, value: Boolean) = apply { if (key != null) { staged[key] = value; removals.remove(key) } }
        override fun remove(key: String?) = apply { if (key != null) { removals += key; staged.remove(key) } }
        override fun clear() = apply { clearRequested = true; staged.clear(); removals.clear() }
        override fun commit(): Boolean { applyChanges(); return true }
        override fun apply() = applyChanges()

        private fun applyChanges() {
            if (clearRequested) values.clear()
            removals.forEach(values::remove)
            staged.forEach { (k, v) -> values[k] = v }
        }
    }
}
