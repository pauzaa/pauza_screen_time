package com.example.pauza_screen_time.app_restriction.usecase

import android.content.Context
import android.content.SharedPreferences
import com.example.pauza_screen_time.app_restriction.RestrictionManager
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import org.mockito.Mockito
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

internal class SessionEnforcementUseCasePauseResumeValidationTest {
    private lateinit var context: Context
    private val prefsByName = linkedMapOf<String, PauseResumeInMemorySharedPreferences>()

    @BeforeTest
    fun setUp() {
        resetSingleton(RestrictionManager::class.java, "instance")
        resetSingleton(
            Class.forName("com.example.pauza_screen_time.app_restriction.storage.RestrictionStorageRepository"),
            "instance",
        )
        context = Mockito.mock(Context::class.java)
        Mockito.`when`(context.applicationContext).thenReturn(context)
        Mockito.`when`(context.getSharedPreferences(Mockito.anyString(), Mockito.anyInt()))
            .thenAnswer { invocation ->
                val name = invocation.getArgument<String>(0)
                prefsByName.getOrPut(name) { PauseResumeInMemorySharedPreferences() }
            }
    }

    @AfterTest
    fun tearDown() {
        resetSingleton(RestrictionManager::class.java, "instance")
        resetSingleton(
            Class.forName("com.example.pauza_screen_time.app_restriction.storage.RestrictionStorageRepository"),
            "instance",
        )
    }

    @Test
    fun pauseEnforcement_withoutActiveSession_throwsIllegalStateException() {
        try {
            SessionEnforcementUseCase(context).pauseEnforcement(5_000L)
            fail("Expected IllegalStateException when no active session exists")
        } catch (error: IllegalStateException) {
            assertEquals("No active restriction session to pause.", error.message)
        }
    }

    @Test
    fun pauseEnforcement_whenAlreadyPaused_throwsIllegalStateException() {
        val manager = RestrictionManager.getInstance(context)
        manager.setActiveSession(
            modeId = "focus",
            blockedAppIds = listOf("com.example.app"),
            source = RestrictionModeSource.MANUAL,
        )
        manager.pauseFor(5_000L)

        try {
            SessionEnforcementUseCase(context).pauseEnforcement(5_000L)
            fail("Expected IllegalStateException when already paused")
        } catch (error: IllegalStateException) {
            assertEquals("Restriction enforcement is already paused.", error.message)
        }
    }

    @Test
    fun resumeEnforcement_withoutActiveSession_throwsIllegalStateException() {
        try {
            SessionEnforcementUseCase(context).resumeEnforcement()
            fail("Expected IllegalStateException when no active session exists")
        } catch (error: IllegalStateException) {
            assertEquals("No active restriction session to resume.", error.message)
        }
    }

    @Test
    fun resumeEnforcement_whenNotPaused_throwsIllegalStateException() {
        val manager = RestrictionManager.getInstance(context)
        manager.setActiveSession(
            modeId = "focus",
            blockedAppIds = listOf("com.example.app"),
            source = RestrictionModeSource.MANUAL,
        )

        try {
            SessionEnforcementUseCase(context).resumeEnforcement()
            fail("Expected IllegalStateException when not paused")
        } catch (error: IllegalStateException) {
            assertEquals("Restriction enforcement is not paused.", error.message)
        }
    }

    @Test
    fun pauseThenResume_withValidPreconditions_succeeds() {
        val manager = RestrictionManager.getInstance(context)
        manager.setActiveSession(
            modeId = "focus",
            blockedAppIds = listOf("com.example.app"),
            source = RestrictionModeSource.MANUAL,
        )
        val useCase = SessionEnforcementUseCase(context)

        useCase.pauseEnforcement(5_000L)
        assertTrue(manager.isPausedNow())

        useCase.resumeEnforcement()
        assertFalse(manager.isPausedNow())
    }

    private fun resetSingleton(clazz: Class<*>, fieldName: String) {
        val field = clazz.getDeclaredField(fieldName)
        field.isAccessible = true
        field.set(null, null)
    }
}

private class PauseResumeInMemorySharedPreferences : SharedPreferences {
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
