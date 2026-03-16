package com.example.pauza_screen_time.installed_apps.method_channel

import com.example.pauza_screen_time.core.MethodNames
import com.example.pauza_screen_time.core.PluginErrorHelper
import com.example.pauza_screen_time.installed_apps.InstalledAppsHandler
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

class InstalledAppsMethodHandler(
    private val installedAppsHandler: InstalledAppsHandler
) : MethodCallHandler {
    companion object {
        private const val FEATURE = "installed_apps"
    }

    /** Wrapper to distinguish a genuine `null` result from a timeout `null`. */
    private data class Optional<T>(val value: T)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onMethodCall(call: MethodCall, result: Result) {
        // Do NOT add a top-level try/catch here.
        // Argument errors are handled per-method before the coroutine launches.
        // Runtime errors are caught inside each coroutine and reported precisely.
        when (call.method) {
            MethodNames.GET_INSTALLED_APPS -> handleGetInstalledApps(call, result)
            MethodNames.GET_APP_INFO -> handleGetAppInfo(call, result)
            else -> result.notImplemented()
        }
    }

    fun detach() {
        scope.cancel()
    }

    private fun handleGetInstalledApps(call: MethodCall, result: Result) {
        // Validate arguments synchronously before launching the coroutine so
        // that INVALID_ARGUMENT errors are reported with the correct error code
        // instead of being swallowed by a generic INTERNAL_FAILURE catch.
        val includeSystemApps = call.argument<Boolean>("includeSystemApps") ?: false
        val includeIcons = call.argument<Boolean>("includeIcons") ?: true

        scope.launch {
            try {
                val apps = withTimeoutOrNull(30_000L) {
                    installedAppsHandler.getInstalledApps(includeSystemApps, includeIcons)
                }
                if (apps == null) {
                    withContext(Dispatchers.Main) {
                        PluginErrorHelper.internalFailure(
                            result = result,
                            feature = FEATURE,
                            action = MethodNames.GET_INSTALLED_APPS,
                            message = "Operation timed out",
                        )
                    }
                    return@launch
                }
                withContext(Dispatchers.Main) {
                    result.success(apps.map { it.toChannelMap() })
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    PluginErrorHelper.internalFailure(
                        result = result,
                        feature = FEATURE,
                        action = MethodNames.GET_INSTALLED_APPS,
                        message = "Failed to get installed apps: ${e.message}",
                        error = e,
                    )
                }
            }
        }
    }

    private fun handleGetAppInfo(call: MethodCall, result: Result) {
        // Validate required argument before launching the coroutine.
        val packageId = call.argument<String>("packageId")
        if (packageId.isNullOrBlank()) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.GET_APP_INFO,
                message = "packageId must be a non-blank String",
            )
            return
        }
        val includeIcons = call.argument<Boolean>("includeIcons") ?: true

        scope.launch {
            try {
                val wrapped = withTimeoutOrNull(30_000L) {
                    installedAppsHandler.getAppInfo(packageId, includeIcons).let { Optional(it) }
                }
                if (wrapped == null) {
                    withContext(Dispatchers.Main) {
                        PluginErrorHelper.internalFailure(
                            result = result,
                            feature = FEATURE,
                            action = MethodNames.GET_APP_INFO,
                            message = "Operation timed out",
                        )
                    }
                    return@launch
                }
                withContext(Dispatchers.Main) {
                    result.success(wrapped.value?.toChannelMap())
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    PluginErrorHelper.internalFailure(
                        result = result,
                        feature = FEATURE,
                        action = MethodNames.GET_APP_INFO,
                        message = "Failed to get app info for $packageId: ${e.message}",
                        error = e,
                    )
                }
            }
        }
    }
}
