package com.example.pauza_screen_time.app_restriction

import android.app.AlarmManager
import android.content.Context
import android.content.SharedPreferences
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleAction
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleEventDraft
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleSource
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import org.mockito.Mockito
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal class RestrictionManagerActiveSessionLifecycleEventsTest {
    private lateinit var preferences: InMemorySharedPreferences
    private lateinit var context: Context
    private lateinit var manager: RestrictionManager

    @BeforeTest
    fun setUp() {
        resetRestrictionManagerSingleton()
        preferences = InMemorySharedPreferences()
        context = Mockito.mock(Context::class.java)
        Mockito.`when`(context.getSharedPreferences(Mockito.anyString(), Mockito.anyInt()))
            .thenReturn(preferences)
        Mockito.`when`(context.getSystemService(Context.ALARM_SERVICE))
            .thenReturn(Mockito.mock(AlarmManager::class.java))
        Mockito.`when`(context.applicationContext).thenReturn(context)
        manager = RestrictionManager.getInstance(context)
    }

    @AfterTest
    fun tearDown() {
        resetRestrictionManagerSingleton()
    }

    @Test
    fun appendLifecycleEvents_dualWritesPendingAndActiveSessionLogs() {
        manager.setActiveSession(
            modeId = "focus",
            blockedAppIds = listOf("com.example.app"),
            source = RestrictionModeSource.MANUAL,
            sessionId = "session-a",
        )

        assertTrue(
            manager.appendLifecycleEvents(
                listOf(
                    lifecycleDraft(
                        sessionId = "session-a",
                        action = RestrictionLifecycleAction.START,
                        occurredAtEpochMs = 10L,
                    ),
                ),
            ),
        )

        assertEquals(1, manager.getPendingLifecycleEvents(10).size)
        assertEquals(1, manager.loadActiveSessionLifecycleEvents().size)
    }

    @Test
    fun ackLifecycleEventsThrough_doesNotMutateActiveSessionLog() {
        manager.setActiveSession(
            modeId = "focus",
            blockedAppIds = listOf("com.example.app"),
            source = RestrictionModeSource.MANUAL,
            sessionId = "session-a",
        )
        assertTrue(
            manager.appendLifecycleEvents(
                listOf(
                    lifecycleDraft("session-a", RestrictionLifecycleAction.START, 10L),
                    lifecycleDraft("session-a", RestrictionLifecycleAction.PAUSE, 20L),
                ),
            ),
        )

        val firstPendingId = manager.getPendingLifecycleEvents(10).first().id
        assertTrue(manager.ackLifecycleEventsThrough(firstPendingId))

        assertEquals(1, manager.getPendingLifecycleEvents(10).size)
        assertEquals(2, manager.loadActiveSessionLifecycleEvents().size)
    }

    @Test
    fun clearActiveSession_clearsActiveSessionLifecycleLog() {
        manager.setActiveSession(
            modeId = "focus",
            blockedAppIds = listOf("com.example.app"),
            source = RestrictionModeSource.MANUAL,
            sessionId = "session-a",
        )
        assertTrue(
            manager.appendLifecycleEvents(
                listOf(
                    lifecycleDraft(
                        sessionId = "session-a",
                        action = RestrictionLifecycleAction.START,
                        occurredAtEpochMs = 10L,
                    ),
                ),
            ),
        )

        manager.clearActiveSession()

        assertTrue(manager.loadActiveSessionLifecycleEvents().isEmpty())
    }

    @Test
    fun setActiveSession_newSessionIdResetsActiveSessionLifecycleLog() {
        manager.setActiveSession(
            modeId = "focus",
            blockedAppIds = listOf("com.example.app"),
            source = RestrictionModeSource.MANUAL,
            sessionId = "session-a",
        )
        assertTrue(
            manager.appendLifecycleEvents(
                listOf(
                    lifecycleDraft(
                        sessionId = "session-a",
                        action = RestrictionLifecycleAction.START,
                        occurredAtEpochMs = 10L,
                    ),
                ),
            ),
        )
        assertEquals(1, manager.loadActiveSessionLifecycleEvents().size)

        manager.setActiveSession(
            modeId = "focus",
            blockedAppIds = listOf("com.example.app"),
            source = RestrictionModeSource.MANUAL,
            sessionId = "session-b",
        )

        assertTrue(manager.loadActiveSessionLifecycleEvents().isEmpty())
    }

    private fun lifecycleDraft(
        sessionId: String,
        action: RestrictionLifecycleAction,
        occurredAtEpochMs: Long,
    ) = RestrictionLifecycleEventDraft(
        sessionId = sessionId,
        modeId = "focus",
        action = action,
        source = RestrictionLifecycleSource.MANUAL,
        reason = "test",
        occurredAtEpochMs = occurredAtEpochMs,
    )

    private fun resetRestrictionManagerSingleton() {
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

    private fun resetSingleton(clazz: Class<*>, fieldName: String) {
        val field = clazz.getDeclaredField(fieldName)
        field.isAccessible = true
        field.set(null, null)
    }
}

private class InMemorySharedPreferences : SharedPreferences {
    private val values = linkedMapOf<String, Any?>()

    override fun getAll(): MutableMap<String, *> = values.toMutableMap()

    override fun getString(key: String?, defValue: String?): String? {
        val value = values[key] ?: return defValue
        return value as? String ?: defValue
    }

    override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? {
        val value = values[key] ?: return defValues
        @Suppress("UNCHECKED_CAST")
        return ((value as? Set<String>)?.toMutableSet()) ?: defValues
    }

    override fun getInt(key: String?, defValue: Int): Int {
        val value = values[key] ?: return defValue
        return (value as? Number)?.toInt() ?: defValue
    }

    override fun getLong(key: String?, defValue: Long): Long {
        val value = values[key] ?: return defValue
        return (value as? Number)?.toLong() ?: defValue
    }

    override fun getFloat(key: String?, defValue: Float): Float {
        val value = values[key] ?: return defValue
        return (value as? Number)?.toFloat() ?: defValue
    }

    override fun getBoolean(key: String?, defValue: Boolean): Boolean {
        val value = values[key] ?: return defValue
        return value as? Boolean ?: defValue
    }

    override fun contains(key: String?): Boolean {
        return values.containsKey(key)
    }

    override fun edit(): SharedPreferences.Editor {
        return Editor(values)
    }

    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) {}

    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) {}

    private class Editor(
        private val values: MutableMap<String, Any?>,
    ) : SharedPreferences.Editor {
        private val staged = linkedMapOf<String, Any?>()
        private val removals = linkedSetOf<String>()
        private var clearRequested = false

        override fun putString(key: String?, value: String?): SharedPreferences.Editor {
            if (key != null) {
                staged[key] = value
                removals.remove(key)
            }
            return this
        }

        override fun putStringSet(key: String?, values: MutableSet<String>?): SharedPreferences.Editor {
            if (key != null) {
                staged[key] = values?.toSet()
                removals.remove(key)
            }
            return this
        }

        override fun putInt(key: String?, value: Int): SharedPreferences.Editor {
            if (key != null) {
                staged[key] = value
                removals.remove(key)
            }
            return this
        }

        override fun putLong(key: String?, value: Long): SharedPreferences.Editor {
            if (key != null) {
                staged[key] = value
                removals.remove(key)
            }
            return this
        }

        override fun putFloat(key: String?, value: Float): SharedPreferences.Editor {
            if (key != null) {
                staged[key] = value
                removals.remove(key)
            }
            return this
        }

        override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor {
            if (key != null) {
                staged[key] = value
                removals.remove(key)
            }
            return this
        }

        override fun remove(key: String?): SharedPreferences.Editor {
            if (key != null) {
                removals += key
                staged.remove(key)
            }
            return this
        }

        override fun clear(): SharedPreferences.Editor {
            clearRequested = true
            staged.clear()
            removals.clear()
            return this
        }

        override fun commit(): Boolean {
            applyChanges()
            return true
        }

        override fun apply() {
            applyChanges()
        }

        private fun applyChanges() {
            if (clearRequested) {
                values.clear()
            }
            removals.forEach(values::remove)
            staged.forEach { (key, value) ->
                values[key] = value
            }
        }
    }
}
