package com.example.pauza_screen_time.app_restriction

import android.content.Context
import android.content.SharedPreferences
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleAction
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleEventDraft
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleSource
import org.mockito.Mockito
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class RestrictionManagerLifecycleQueueTest {
    private lateinit var preferences: InMemorySharedPreferences
    private lateinit var manager: RestrictionManager

    @BeforeTest
    fun setUp() {
        resetRestrictionManagerSingleton()
        preferences = InMemorySharedPreferences()
        val context = Mockito.mock(Context::class.java)
        Mockito.`when`(context.getSharedPreferences(Mockito.anyString(), Mockito.anyInt()))
            .thenReturn(preferences)
        manager = RestrictionManager.getInstance(context)
    }

    @AfterTest
    fun tearDown() {
        resetRestrictionManagerSingleton()
    }

    @Test
    fun getPendingLifecycleEvents_readsHeadWindowInOrder() {
        assertTrue(manager.appendLifecycleEvents((1..3).map(::draft)))

        val pending = manager.getPendingLifecycleEvents(limit = 2)

        assertEquals(2, pending.size)
        assertEquals(eventIdForSeq(1L, 1L), pending[0].id)
        assertEquals(eventIdForSeq(2L, 2L), pending[1].id)
    }

    @Test
    fun ackLifecycleEventsThrough_advancesCursorInclusively() {
        assertTrue(manager.appendLifecycleEvents((1..3).map(::draft)))

        assertTrue(manager.ackLifecycleEventsThrough(eventIdForSeq(1L, 1L)))
        val pending = manager.getPendingLifecycleEvents(limit = 10)

        assertEquals(2, pending.size)
        assertEquals(eventIdForSeq(2L, 2L), pending[0].id)
        assertEquals(eventIdForSeq(3L, 3L), pending[1].id)
    }

    @Test
    fun ackLifecycleEventsThrough_futureId_drainsQueue() {
        assertTrue(manager.appendLifecycleEvents((1..3).map(::draft)))

        assertTrue(manager.ackLifecycleEventsThrough("00000000000000001000-0000000000000"))

        assertTrue(manager.getPendingLifecycleEvents(limit = 10).isEmpty())
    }

    @Test
    fun ackLifecycleEventsThrough_malformedId_returnsFalse() {
        assertTrue(manager.appendLifecycleEvents((1..3).map(::draft)))

        assertFalse(manager.ackLifecycleEventsThrough("bad-id"))
    }

    @Test
    fun queueCap_prunesOldestEventsLogically() {
        val drafts = (1..10_002).map(::draft)
        assertTrue(manager.appendLifecycleEvents(drafts))

        val firstPending = manager.getPendingLifecycleEvents(limit = 1).single()
        assertEquals(eventIdForSeq(3L, 3L), firstPending.id)
    }

    @Test
    fun missingEventRecord_isSkipped() {
        assertTrue(manager.appendLifecycleEvents((1..3).map(::draft)))
        preferences.edit().remove(eventKeyForSeq(2L)).commit()

        val pending = manager.getPendingLifecycleEvents(limit = 3)

        assertEquals(2, pending.size)
        assertEquals(eventIdForSeq(1L, 1L), pending[0].id)
        assertEquals(eventIdForSeq(3L, 3L), pending[1].id)
    }

    @Test
    fun ackTriggersBoundedGcDeletion() {
        assertTrue(manager.appendLifecycleEvents((1..5).map(::draft)))
        assertTrue(preferences.contains(eventKeyForSeq(1L)))
        assertTrue(preferences.contains(eventKeyForSeq(2L)))

        assertTrue(manager.ackLifecycleEventsThrough(eventIdForSeq(3L, 3L)))

        assertFalse(preferences.contains(eventKeyForSeq(1L)))
        assertFalse(preferences.contains(eventKeyForSeq(2L)))
        assertFalse(preferences.contains(eventKeyForSeq(3L)))
        assertTrue(preferences.contains(eventKeyForSeq(4L)))
    }

    private fun draft(index: Int): RestrictionLifecycleEventDraft {
        val seq = index.toLong()
        return RestrictionLifecycleEventDraft(
            sessionId = "s1",
            modeId = "focus",
            action = RestrictionLifecycleAction.START,
            source = RestrictionLifecycleSource.MANUAL,
            reason = "test_$index",
            occurredAtEpochMs = seq,
        )
    }

    private fun resetRestrictionManagerSingleton() {
        val field = RestrictionManager::class.java.getDeclaredField("instance")
        field.isAccessible = true
        field.set(null, null)
    }
}

private fun eventKeyForSeq(seq: Long): String {
    return "lifecycle_event.${seq.toString().padStart(20, '0')}"
}

private fun eventIdForSeq(seq: Long, occurredAtEpochMs: Long): String {
    return "${seq.toString().padStart(20, '0')}-${occurredAtEpochMs.toString().padStart(13, '0')}"
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
        private var clearAll = false

        override fun putString(key: String?, value: String?): SharedPreferences.Editor {
            if (key != null) {
                staged[key] = value
                removals.remove(key)
            }
            return this
        }

        override fun putStringSet(
            key: String?,
            values: MutableSet<String>?,
        ): SharedPreferences.Editor {
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
                removals.add(key)
                staged.remove(key)
            }
            return this
        }

        override fun clear(): SharedPreferences.Editor {
            clearAll = true
            staged.clear()
            removals.clear()
            return this
        }

        override fun commit(): Boolean {
            apply()
            return true
        }

        override fun apply() {
            if (clearAll) {
                values.clear()
                clearAll = false
            }
            removals.forEach(values::remove)
            removals.clear()
            staged.forEach { (key, value) ->
                if (value == null) {
                    values.remove(key)
                } else {
                    values[key] = value
                }
            }
            staged.clear()
        }
    }
}
