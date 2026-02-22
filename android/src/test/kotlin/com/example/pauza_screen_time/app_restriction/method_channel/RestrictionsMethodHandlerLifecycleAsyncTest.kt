package com.example.pauza_screen_time.app_restriction.method_channel

import android.content.Context
import android.content.SharedPreferences
import com.example.pauza_screen_time.app_restriction.RestrictionManager
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleAction
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleEventDraft
import com.example.pauza_screen_time.app_restriction.lifecycle.RestrictionLifecycleSource
import com.example.pauza_screen_time.app_restriction.model.RestrictionModeSource
import com.example.pauza_screen_time.core.MethodNames
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class RestrictionsMethodHandlerLifecycleAsyncTest {
    private lateinit var preferences: InMemorySharedPreferences
    private lateinit var context: Context

    @BeforeTest
    fun setUp() {
        resetRestrictionManagerSingleton()
        preferences = InMemorySharedPreferences()
        context = Mockito.mock(Context::class.java)
        Mockito.`when`(context.getSharedPreferences(Mockito.anyString(), Mockito.anyInt()))
            .thenReturn(preferences)
    }

    @AfterTest
    fun tearDown() {
        resetRestrictionManagerSingleton()
    }

    @Test
    fun getPendingLifecycleEvents_returnsPayloadViaAsyncExecutorPath() {
        val manager = RestrictionManager.getInstance(context)
        assertTrue(
            manager.appendLifecycleEvents(
                listOf(
                    RestrictionLifecycleEventDraft(
                        sessionId = "s1",
                        modeId = "focus",
                        action = RestrictionLifecycleAction.START,
                        source = RestrictionLifecycleSource.MANUAL,
                        reason = "test",
                        occurredAtEpochMs = 1L,
                    ),
                ),
            ),
        )

        val executor = Executors.newSingleThreadExecutor()
        val handler = RestrictionsMethodHandler(
            contextProvider = { context },
            lifecycleExecutor = executor,
            resultPoster = { action -> action() },
        )
        val result = LatchingResult()

        handler.onMethodCall(
            MethodCall(MethodNames.GET_PENDING_LIFECYCLE_EVENTS, mapOf("limit" to 10)),
            result,
        )

        assertTrue(result.await())
        val success = result.successValue as? List<*>
        assertNotNull(success)
        assertEquals(1, success.size)
        val first = success.first() as? Map<*, *>
        assertNotNull(first)
        assertEquals("START", first["action"])
        assertNull(result.errorCode)

        handler.dispose()
        executor.shutdown()
    }

    @Test
    fun ackLifecycleEvents_returnsSuccessViaAsyncExecutorPath() {
        val manager = RestrictionManager.getInstance(context)
        assertTrue(
            manager.appendLifecycleEvents(
                listOf(
                    RestrictionLifecycleEventDraft(
                        sessionId = "s1",
                        modeId = "focus",
                        action = RestrictionLifecycleAction.START,
                        source = RestrictionLifecycleSource.MANUAL,
                        reason = "test",
                        occurredAtEpochMs = 1L,
                    ),
                ),
            ),
        )
        val throughId = manager.getPendingLifecycleEvents(1).first().id

        val executor = Executors.newSingleThreadExecutor()
        val handler = RestrictionsMethodHandler(
            contextProvider = { context },
            lifecycleExecutor = executor,
            resultPoster = { action -> action() },
        )
        val result = LatchingResult()

        handler.onMethodCall(
            MethodCall(MethodNames.ACK_LIFECYCLE_EVENTS, mapOf("throughEventId" to throughId)),
            result,
        )

        assertTrue(result.await())
        assertNull(result.errorCode)
        assertEquals(null, result.successValue)

        handler.dispose()
        executor.shutdown()
    }

    @Test
    fun getRestrictionSession_readsCurrentSessionEventsFromDedicatedActiveLog() {
        val manager = RestrictionManager.getInstance(context)
        manager.setActiveSession(
            modeId = "focus",
            blockedAppIds = listOf("com.example.app"),
            source = RestrictionModeSource.MANUAL,
            sessionId = "session-a",
        )
        assertTrue(
            manager.appendLifecycleEvents(
                listOf(
                    RestrictionLifecycleEventDraft(
                        sessionId = "session-a",
                        modeId = "focus",
                        action = RestrictionLifecycleAction.START,
                        source = RestrictionLifecycleSource.MANUAL,
                        reason = "session_a_start",
                        occurredAtEpochMs = 1L,
                    ),
                    RestrictionLifecycleEventDraft(
                        sessionId = "session-b",
                        modeId = "focus",
                        action = RestrictionLifecycleAction.START,
                        source = RestrictionLifecycleSource.MANUAL,
                        reason = "session_b_start",
                        occurredAtEpochMs = 2L,
                    ),
                ),
            ),
        )
        assertEquals(2, manager.getPendingLifecycleEvents(10).size)
        assertEquals(1, manager.loadActiveSessionLifecycleEvents().size)

        val handler = RestrictionsMethodHandler(
            contextProvider = { context },
            resultPoster = { action -> action() },
        )
        val result = LatchingResult()
        handler.onMethodCall(
            MethodCall(MethodNames.GET_RESTRICTION_SESSION, null),
            result,
        )

        assertTrue(result.await())
        val payload = result.successValue as? Map<*, *>
        assertNotNull(payload)
        val currentSessionEvents = payload["currentSessionEvents"] as? List<*>
        assertNotNull(currentSessionEvents)
        assertEquals(1, currentSessionEvents.size)
        val first = currentSessionEvents.firstOrNull() as? Map<*, *>
        assertNotNull(first)
        assertEquals("session-a", first["sessionId"])
        assertNull(result.errorCode)

        handler.dispose()
    }

    @Test
    fun invalidArgs_failFastWithoutExecutorWork() {
        val handler = RestrictionsMethodHandler(
            contextProvider = { context },
            lifecycleExecutor = Executors.newSingleThreadExecutor(),
            resultPoster = { action -> action() },
        )
        val result = LatchingResult()

        handler.onMethodCall(
            MethodCall(MethodNames.GET_PENDING_LIFECYCLE_EVENTS, mapOf("limit" to 0)),
            result,
        )

        assertEquals("INVALID_ARGUMENT", result.errorCode)
        handler.dispose()
    }

    @Test
    fun endSession_withoutActiveSession_returnsInvalidArgument() {
        val handler = RestrictionsMethodHandler(
            contextProvider = { context },
            resultPoster = { action -> action() },
        )
        val result = LatchingResult()

        handler.onMethodCall(
            MethodCall(MethodNames.END_SESSION, null),
            result,
        )

        assertTrue(result.await())
        assertEquals("INVALID_ARGUMENT", result.errorCode)
        assertEquals("No active restriction session to end", result.errorMessage)
        handler.dispose()
    }

    @Test
    fun asyncFailure_mapsToInternalFailure() {
        val badContext = Mockito.mock(Context::class.java)
        Mockito.`when`(badContext.getSharedPreferences(Mockito.anyString(), Mockito.anyInt()))
            .thenThrow(IllegalStateException("boom"))

        val executor = Executors.newSingleThreadExecutor()
        val handler = RestrictionsMethodHandler(
            contextProvider = { badContext },
            lifecycleExecutor = executor,
            resultPoster = { action -> action() },
        )
        val result = LatchingResult()

        handler.onMethodCall(
            MethodCall(MethodNames.GET_PENDING_LIFECYCLE_EVENTS, mapOf("limit" to 1)),
            result,
        )

        assertTrue(result.await())
        assertEquals("INTERNAL_FAILURE", result.errorCode)

        handler.dispose()
        executor.shutdown()
    }

    private fun resetRestrictionManagerSingleton() {
        val field = RestrictionManager::class.java.getDeclaredField("instance")
        field.isAccessible = true
        field.set(null, null)
    }
}

private class LatchingResult : MethodChannel.Result {
    private val latch = CountDownLatch(1)
    var successValue: Any? = null
    var errorCode: String? = null
    var errorMessage: String? = null
    var errorDetails: Any? = null

    override fun success(result: Any?) {
        successValue = result
        latch.countDown()
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        this.errorCode = errorCode
        this.errorMessage = errorMessage
        this.errorDetails = errorDetails
        latch.countDown()
    }

    override fun notImplemented() {
        errorCode = "NOT_IMPLEMENTED"
        latch.countDown()
    }

    fun await(timeoutMs: Long = 2000): Boolean = latch.await(timeoutMs, TimeUnit.MILLISECONDS)
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
