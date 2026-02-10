package com.example.pauza_screen_time.usage_stats.method_channel

import com.example.pauza_screen_time.core.MethodNames
import com.example.pauza_screen_time.core.PluginErrorHelper
import com.example.pauza_screen_time.usage_stats.UsageStatsHandler
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class UsageStatsMethodHandler(
    private val usageStatsHandler: UsageStatsHandler
) : MethodCallHandler {
    companion object {
        private const val FEATURE = "usage_stats"
        private const val ANDROID_USAGE_STATS_PERMISSION = "android.usageStats"
        private const val STATUS_DENIED = "denied"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                MethodNames.QUERY_USAGE_STATS -> handleQueryUsageStats(call, result)
                MethodNames.QUERY_APP_USAGE_STATS -> handleQueryAppUsageStats(call, result)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            PluginErrorHelper.internalFailure(
                result = result,
                feature = FEATURE,
                action = call.method,
                message = "Unexpected usage stats error: ${e.message}",
                error = e,
            )
        }
    }

    fun detach() {
        scope.cancel()
    }

    private fun handleQueryUsageStats(call: MethodCall, result: Result) {
        val startTimeMs = call.argument<Long>("startTimeMs")
        val endTimeMs = call.argument<Long>("endTimeMs")
        val includeIcons = call.argument<Boolean>("includeIcons") ?: true

        if (startTimeMs == null || endTimeMs == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.QUERY_USAGE_STATS,
                message = "Start time and end time are required",
            )
            return
        }

        scope.launch {
            try {
                val stats = usageStatsHandler.queryUsageStats(startTimeMs, endTimeMs, includeIcons)
                withContext(Dispatchers.Main) {
                    result.success(stats.map { it.toChannelMap() })
                }
            } catch (e: SecurityException) {
                withContext(Dispatchers.Main) {
                    reportMissingUsageStatsPermission(
                        result = result,
                        action = MethodNames.QUERY_USAGE_STATS,
                        message = "Usage Access is not granted. Enable Usage Access for this app in Settings.",
                    )
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    PluginErrorHelper.internalFailure(
                        result = result,
                        feature = FEATURE,
                        action = MethodNames.QUERY_USAGE_STATS,
                        message = "Failed to query usage stats: ${e.message}",
                        error = e,
                    )
                }
            }
        }
    }

    private fun handleQueryAppUsageStats(call: MethodCall, result: Result) {
        val packageId = call.argument<String>("packageId")
        val startTimeMs = call.argument<Long>("startTimeMs")
        val endTimeMs = call.argument<Long>("endTimeMs")
        val includeIcons = call.argument<Boolean>("includeIcons") ?: true

        if (packageId == null || startTimeMs == null || endTimeMs == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.QUERY_APP_USAGE_STATS,
                message = "Package ID, start time, and end time are required",
            )
            return
        }

        scope.launch {
            try {
                val stats = usageStatsHandler.queryAppUsageStats(packageId, startTimeMs, endTimeMs, includeIcons)
                withContext(Dispatchers.Main) {
                    result.success(stats?.toChannelMap())
                }
            } catch (e: SecurityException) {
                withContext(Dispatchers.Main) {
                    reportMissingUsageStatsPermission(
                        result = result,
                        action = MethodNames.QUERY_APP_USAGE_STATS,
                        message = "Usage Access is not granted. Enable Usage Access for this app in Settings.",
                    )
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    PluginErrorHelper.internalFailure(
                        result = result,
                        feature = FEATURE,
                        action = MethodNames.QUERY_APP_USAGE_STATS,
                        message = "Failed to query app usage stats: ${e.message}",
                        error = e,
                    )
                }
            }
        }
    }

    private fun reportMissingUsageStatsPermission(
        result: Result,
        action: String,
        message: String,
    ) {
        PluginErrorHelper.missingPermission(
            result = result,
            feature = FEATURE,
            action = action,
            message = message,
            missing = listOf(ANDROID_USAGE_STATS_PERMISSION),
            status = mapOf(ANDROID_USAGE_STATS_PERMISSION to STATUS_DENIED),
        )
    }
}
