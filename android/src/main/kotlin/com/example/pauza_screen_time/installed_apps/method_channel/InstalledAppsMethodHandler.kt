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

class InstalledAppsMethodHandler(
    private val installedAppsHandler: InstalledAppsHandler
) : MethodCallHandler {
    companion object {
        private const val FEATURE = "installed_apps"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                MethodNames.GET_INSTALLED_APPS -> handleGetInstalledApps(call, result)
                MethodNames.GET_APP_INFO -> handleGetAppInfo(call, result)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = call.method,
                message = "Unexpected installed apps error: ${e.message}",
                error = e,
            )
        }
    }

    fun detach() {
        scope.cancel()
    }

    private fun handleGetInstalledApps(call: MethodCall, result: Result) {
        val includeSystemApps = call.argument<Boolean>("includeSystemApps") ?: false
        val includeIcons = call.argument<Boolean>("includeIcons") ?: true

        scope.launch {
            try {
                val apps = installedAppsHandler.getInstalledApps(includeSystemApps, includeIcons)
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
        val packageId = call.argument<String>("packageId")
        val includeIcons = call.argument<Boolean>("includeIcons") ?: true

        if (packageId == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.GET_APP_INFO,
                message = "Package ID is required",
            )
            return
        }

        scope.launch {
            try {
                val appInfo = installedAppsHandler.getAppInfo(packageId, includeIcons)
                withContext(Dispatchers.Main) {
                    result.success(appInfo?.toChannelMap())
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
