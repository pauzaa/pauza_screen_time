package com.example.pauza_screen_time.app_restriction.method_channel

import android.content.Context
import com.example.pauza_screen_time.core.MethodNames
import com.example.pauza_screen_time.permissions.PermissionHandler
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

internal class RestrictionsMethodHandlerPreflightTest {
    @Test
    fun scopedMutationMethods_failFastWhenAccessibilityIsDenied() {
        val context = Mockito.mock(Context::class.java)
        val handler = RestrictionsMethodHandler(
            contextProvider = { context },
            accessibilityStatusProvider = { PermissionHandler.STATUS_DENIED },
        )

        val methods = listOf(
            MethodNames.UPSERT_MODE,
            MethodNames.SET_MODES_ENABLED,
            MethodNames.START_SESSION,
            MethodNames.PAUSE_ENFORCEMENT,
            MethodNames.RESUME_ENFORCEMENT,
        )

        methods.forEach { method ->
            val result = RecordingResult()
            handler.onMethodCall(MethodCall(method, null), result)

            assertEquals("MISSING_PERMISSION", result.errorCode, "method=$method")
            assertEquals("Accessibility permission is required for restrictions", result.errorMessage, "method=$method")
            val details = assertIs<Map<*, *>>(result.errorDetails, "method=$method")
            assertEquals("restrictions", details["feature"], "method=$method")
            assertEquals(method, details["action"], "method=$method")
            assertEquals("android", details["platform"], "method=$method")
            assertEquals(listOf("android.accessibility"), details["missing"], "method=$method")
            val status = assertIs<Map<*, *>>(details["status"], "method=$method")
            assertEquals(PermissionHandler.STATUS_DENIED, status["androidAccessibilityStatus"], "method=$method")
            assertEquals(0, result.successCalls, "method=$method")
        }
    }

    @Test
    fun setModesEnabled_reachesValidationWhenAccessibilityIsGranted() {
        val context = Mockito.mock(Context::class.java)
        val handler = RestrictionsMethodHandler(
            contextProvider = { context },
            accessibilityStatusProvider = { PermissionHandler.STATUS_GRANTED },
        )

        val result = RecordingResult()
        handler.onMethodCall(MethodCall(MethodNames.SET_MODES_ENABLED, emptyMap<String, Any?>()), result)

        assertEquals("INVALID_ARGUMENT", result.errorCode)
        val details = assertIs<Map<*, *>>(result.errorDetails)
        assertEquals(MethodNames.SET_MODES_ENABLED, details["action"])
        assertEquals(0, result.successCalls)
    }
}

private class RecordingResult : MethodChannel.Result {
    var errorCode: String? = null
    var errorMessage: String? = null
    var errorDetails: Any? = null
    var successCalls: Int = 0

    override fun success(result: Any?) {
        successCalls += 1
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        this.errorCode = errorCode
        this.errorMessage = errorMessage
        this.errorDetails = errorDetails
    }

    override fun notImplemented() {
        errorCode = "NOT_IMPLEMENTED"
        errorMessage = null
        errorDetails = null
    }
}
