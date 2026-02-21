package com.example.pauza_screen_time.app_restriction.lifecycle

import android.content.Context
import android.content.SharedPreferences
import com.example.pauza_screen_time.app_restriction.schedule.StorageDecodeException
import org.mockito.Mockito
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull

internal class RestrictionLifecycleLoggerTest {

    private lateinit var preferences: InMemorySharedPreferences
    private lateinit var logger: RestrictionLifecycleLogger

    @BeforeTest
    fun setUp() {
        resetSingleton()
        preferences = InMemorySharedPreferences()
        val context = Mockito.mock(Context::class.java)
        Mockito.`when`(context.applicationContext).thenReturn(context)
        Mockito.`when`(context.getSharedPreferences(Mockito.anyString(), Mockito.anyInt()))
            .thenReturn(preferences)
        logger = RestrictionLifecycleLogger.getInstance(context)
    }

    @AfterTest
    fun tearDown() {
        resetSingleton()
    }

    // ---------- getPendingLifecycleEvents ----------

    @Test
    fun getPendingLifecycleEvents_returnsEmptyAndClearsKey_onCorruptJson() {
        preferences.edit().putString("lifecycle_events", "not-valid-json").apply()

        val result = logger.getPendingLifecycleEvents(10)

        assertEquals(emptyList(), result)
        assertNull(preferences.getString("lifecycle_events", null), "Corrupt key should be cleared")
    }

    // ---------- appendLifecycleEvents ----------

    @Test
    fun appendLifecycleEvents_returnsFalseAndClearsKey_onCorruptPersistedJson() {
        preferences.edit().putString("lifecycle_events", "not-valid-json").apply()

        val returned = logger.appendLifecycleEvents(listOf(validDraft()), activeSessionId = "s1")

        assertFalse(returned)
        assertNull(preferences.getString("lifecycle_events", null), "Corrupt lifecycle_events key should be cleared")
    }

    @Test
    fun appendLifecycleEvents_returnsFalseAndClearsKey_onCorruptActiveSessionJson() {
        // Write valid lifecycle_events but corrupt active-session events
        preferences.edit()
            .putString("lifecycle_events", "[]")
            .putString("active_session_lifecycle_events", "not-valid-json")
            .apply()

        val returned = logger.appendLifecycleEvents(listOf(validDraft()), activeSessionId = "s1")

        assertFalse(returned)
        assertNull(
            preferences.getString("active_session_lifecycle_events", null),
            "Corrupt active-session key should be cleared",
        )
    }

    // ---------- ackLifecycleEventsThrough ----------

    @Test
    fun ackLifecycleEventsThrough_returnsFalseAndClearsKey_onCorruptJson() {
        preferences.edit().putString("lifecycle_events", "not-valid-json").apply()

        val returned = logger.ackLifecycleEventsThrough("some-id")

        assertFalse(returned)
        assertNull(preferences.getString("lifecycle_events", null), "Corrupt key should be cleared after ack")
    }

    // ---------- helpers ----------

    private fun validDraft() = RestrictionLifecycleEventDraft(
        sessionId = "s1",
        modeId = "focus",
        action = RestrictionLifecycleAction.START,
        source = RestrictionLifecycleSource.MANUAL,
        reason = "test",
        occurredAtEpochMs = 1_000L,
    )

    private fun resetSingleton() {
        val field = RestrictionLifecycleLogger::class.java.getDeclaredField("instance")
        field.isAccessible = true
        field.set(null, null)
    }
}

// ---------------------------------------------------------------------------
// Minimal in-memory SharedPreferences (same pattern as the rest of the suite)
// ---------------------------------------------------------------------------

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
    override fun registerOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) {}
    override fun unregisterOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) {}

    private class Editor(private val values: MutableMap<String, Any?>) : SharedPreferences.Editor {
        private val staged = linkedMapOf<String, Any?>()
        private val removals = linkedSetOf<String>()
        private var clearRequested = false

        override fun putString(key: String?, value: String?) = apply { if (key != null) { staged[key] = value; removals.remove(key) } }
        override fun putStringSet(key: String?, v: MutableSet<String>?) = apply { if (key != null) { staged[key] = v?.toSet(); removals.remove(key) } }
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
