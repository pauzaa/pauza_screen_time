package com.example.pauza_screen_time.usage_stats.method_channel

import com.example.pauza_screen_time.core.MethodNames
import com.example.pauza_screen_time.core.PluginErrorHelper
import com.example.pauza_screen_time.usage_stats.model.UsageStatsInterval
import com.example.pauza_screen_time.usage_stats.repository.AppStatusRepository
import com.example.pauza_screen_time.usage_stats.repository.DeviceEventStatsRepository
import com.example.pauza_screen_time.usage_stats.repository.UsageEventsRepository
import com.example.pauza_screen_time.usage_stats.repository.UsageStatsRepository
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Method-call handler for the Usage Stats feature.
 *
 * Delegates each method call to the appropriate focused repository and maps
 * results back through the Flutter method channel.
 */
class UsageStatsMethodHandler(
    private val usageStatsRepository: UsageStatsRepository,
    private val usageEventsRepository: UsageEventsRepository,
    private val deviceEventStatsRepository: DeviceEventStatsRepository,
    private val appStatusRepository: AppStatusRepository,
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
                MethodNames.QUERY_USAGE_EVENTS -> handleQueryUsageEvents(call, result)
                MethodNames.QUERY_EVENT_STATS -> handleQueryEventStats(call, result)
                MethodNames.IS_APP_INACTIVE -> handleIsAppInactive(call, result)
                MethodNames.GET_APP_STANDBY_BUCKET -> handleGetAppStandbyBucket(result)
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

    // ============================================================
    // Handlers
    // ============================================================

    private fun handleQueryUsageStats(call: MethodCall, result: Result) {
        val startTimeMs = call.argument<Long>("startTimeMs")
        val endTimeMs = call.argument<Long>("endTimeMs")
        val includeIcons = call.argument<Boolean>("includeIcons") ?: true

        if (startTimeMs == null || endTimeMs == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.QUERY_USAGE_STATS,
                message = "startTimeMs and endTimeMs are required",
            )
            return
        }

        scope.launch {
            try {
                val stats = usageStatsRepository.queryUsageStats(startTimeMs, endTimeMs, includeIcons)
                withContext(Dispatchers.Main) {
                    result.success(stats.map { it.toChannelMap() })
                }
            } catch (e: SecurityException) {
                withContext(Dispatchers.Main) {
                    reportMissingUsageStatsPermission(result, MethodNames.QUERY_USAGE_STATS)
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
                message = "packageId, startTimeMs, and endTimeMs are required",
            )
            return
        }

        scope.launch {
            try {
                val stats = usageStatsRepository.queryAppUsageStats(
                    packageId, startTimeMs, endTimeMs, includeIcons,
                )
                withContext(Dispatchers.Main) {
                    result.success(stats?.toChannelMap())
                }
            } catch (e: SecurityException) {
                withContext(Dispatchers.Main) {
                    reportMissingUsageStatsPermission(result, MethodNames.QUERY_APP_USAGE_STATS)
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

    private fun handleQueryUsageEvents(call: MethodCall, result: Result) {
        val startTimeMs = call.argument<Long>("startTimeMs")
        val endTimeMs = call.argument<Long>("endTimeMs")
        val eventTypesList = call.argument<List<Int>>("eventTypes")
        val eventTypes = eventTypesList?.toSet()

        if (startTimeMs == null || endTimeMs == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.QUERY_USAGE_EVENTS,
                message = "startTimeMs and endTimeMs are required",
            )
            return
        }

        scope.launch {
            try {
                val events = usageEventsRepository.queryUsageEvents(startTimeMs, endTimeMs, eventTypes)
                withContext(Dispatchers.Main) {
                    result.success(events.map { it.toChannelMap() })
                }
            } catch (e: SecurityException) {
                withContext(Dispatchers.Main) {
                    reportMissingUsageStatsPermission(result, MethodNames.QUERY_USAGE_EVENTS)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    PluginErrorHelper.internalFailure(
                        result = result,
                        feature = FEATURE,
                        action = MethodNames.QUERY_USAGE_EVENTS,
                        message = "Failed to query usage events: ${e.message}",
                        error = e,
                    )
                }
            }
        }
    }

    private fun handleQueryEventStats(call: MethodCall, result: Result) {
        val startTimeMs = call.argument<Long>("startTimeMs")
        val endTimeMs = call.argument<Long>("endTimeMs")
        val rawIntervalType = call.argument<Int>("intervalType") ?: UsageStatsInterval.BEST.rawValue
        val intervalType = UsageStatsInterval.fromRawValue(rawIntervalType)

        if (startTimeMs == null || endTimeMs == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.QUERY_EVENT_STATS,
                message = "startTimeMs and endTimeMs are required",
            )
            return
        }

        scope.launch {
            try {
                val stats = deviceEventStatsRepository.queryEventStats(intervalType, startTimeMs, endTimeMs)
                withContext(Dispatchers.Main) {
                    result.success(stats.map { it.toChannelMap() })
                }
            } catch (e: SecurityException) {
                withContext(Dispatchers.Main) {
                    reportMissingUsageStatsPermission(result, MethodNames.QUERY_EVENT_STATS)
                }
            } catch (e: Exception) {
                // Includes UnsupportedOperationException on API < 28.
                withContext(Dispatchers.Main) {
                    PluginErrorHelper.internalFailure(
                        result = result,
                        feature = FEATURE,
                        action = MethodNames.QUERY_EVENT_STATS,
                        message = "Failed to query event stats: ${e.message}",
                        error = e,
                    )
                }
            }
        }
    }

    private fun handleIsAppInactive(call: MethodCall, result: Result) {
        val packageId = call.argument<String>("packageId")

        if (packageId == null) {
            PluginErrorHelper.invalidArgument(
                result = result,
                feature = FEATURE,
                action = MethodNames.IS_APP_INACTIVE,
                message = "packageId is required",
            )
            return
        }

        scope.launch {
            try {
                val inactive = appStatusRepository.isAppInactive(packageId)
                withContext(Dispatchers.Main) {
                    result.success(inactive)
                }
            } catch (e: SecurityException) {
                withContext(Dispatchers.Main) {
                    reportMissingUsageStatsPermission(result, MethodNames.IS_APP_INACTIVE)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    PluginErrorHelper.internalFailure(
                        result = result,
                        feature = FEATURE,
                        action = MethodNames.IS_APP_INACTIVE,
                        message = "Failed to check app inactive state: ${e.message}",
                        error = e,
                    )
                }
            }
        }
    }

    private fun handleGetAppStandbyBucket(result: Result) {
        scope.launch {
            try {
                val bucket = appStatusRepository.getAppStandbyBucket()
                withContext(Dispatchers.Main) {
                    result.success(bucket.rawValue)
                }
            } catch (e: SecurityException) {
                withContext(Dispatchers.Main) {
                    reportMissingUsageStatsPermission(result, MethodNames.GET_APP_STANDBY_BUCKET)
                }
            } catch (e: Exception) {
                // Includes UnsupportedOperationException on API < 28.
                withContext(Dispatchers.Main) {
                    PluginErrorHelper.internalFailure(
                        result = result,
                        feature = FEATURE,
                        action = MethodNames.GET_APP_STANDBY_BUCKET,
                        message = "Failed to get app standby bucket: ${e.message}",
                        error = e,
                    )
                }
            }
        }
    }

    // ============================================================
    // Helpers
    // ============================================================

    private fun reportMissingUsageStatsPermission(result: Result, action: String) {
        PluginErrorHelper.missingPermission(
            result = result,
            feature = FEATURE,
            action = action,
            message = "Usage Access is not granted. Enable it for this app in Settings → Privacy → Usage Access.",
            missing = listOf(ANDROID_USAGE_STATS_PERMISSION),
            status = mapOf(ANDROID_USAGE_STATS_PERMISSION to STATUS_DENIED),
        )
    }
}
