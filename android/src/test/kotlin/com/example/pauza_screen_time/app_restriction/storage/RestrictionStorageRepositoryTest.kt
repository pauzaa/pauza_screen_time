package com.example.pauza_screen_time.app_restriction.storage

import android.content.Context
import android.content.SharedPreferences
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import org.mockito.Mockito
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

internal class RestrictionStorageRepositoryTest {

    private lateinit var preferences: InMemorySharedPreferences
    private lateinit var repo: RestrictionStorageRepository

    @BeforeTest
    fun setUp() {
        resetSingleton()
        preferences = InMemorySharedPreferences()
        val context = Mockito.mock(Context::class.java)
        Mockito.`when`(context.applicationContext).thenReturn(context)
        Mockito.`when`(context.getSharedPreferences(Mockito.anyString(), Mockito.anyInt()))
            .thenReturn(preferences)
        repo = RestrictionStorageRepository.getInstance(context)
    }

    @AfterTest
    fun tearDown() {
        resetSingleton()
    }

    @Test
    fun getActiveSession_logsWarningAndDefaultsToManual_onUnknownSourceInLegacyFormat() {
        // Legacy format: plain JSON object (not the kotlinx-serialization format)
        // with an unrecognized "source" value — the field is present but unknown.
        val legacyJson = """{"modeId":"focus","blockedAppIds":["com.example.app"],"source":"unknown_wire_value"}"""
        preferences.edit().putString("active_session", legacyJson).apply()

        val session = repo.getActiveSession()

        assertNotNull(session)
        assertEquals("focus", session.modeId)
        assertEquals(RestrictionModeSource.MANUAL, session.source,
            "Unknown source wire value should fall back to MANUAL with a warning log")
    }

    private fun resetSingleton() {
        val field = RestrictionStorageRepository::class.java.getDeclaredField("instance")
        field.isAccessible = true
        field.set(null, null)
    }
}

// ---------------------------------------------------------------------------
// Minimal in-memory SharedPreferences
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
