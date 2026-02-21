package com.example.pauza_screen_time.usage_stats.method_channel

import android.content.Context
import com.example.pauza_screen_time.core.ChannelNames
import com.example.pauza_screen_time.usage_stats.repository.AppStatusRepository
import com.example.pauza_screen_time.usage_stats.repository.DeviceEventStatsRepository
import com.example.pauza_screen_time.usage_stats.repository.UsageEventsRepository
import com.example.pauza_screen_time.usage_stats.repository.UsageStatsRepository
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class UsageStatsChannelRegistrar {
    private var channel: MethodChannel? = null
    private var methodHandler: UsageStatsMethodHandler? = null

    fun attach(messenger: BinaryMessenger, context: Context) {
        val usageStatsRepository = UsageStatsRepository(context)
        val usageEventsRepository = UsageEventsRepository(context)
        val deviceEventStatsRepository = DeviceEventStatsRepository(context)
        val appStatusRepository = AppStatusRepository(context)

        methodHandler = UsageStatsMethodHandler(
            usageStatsRepository = usageStatsRepository,
            usageEventsRepository = usageEventsRepository,
            deviceEventStatsRepository = deviceEventStatsRepository,
            appStatusRepository = appStatusRepository,
        )
        channel = MethodChannel(messenger, ChannelNames.USAGE_STATS).apply {
            setMethodCallHandler(methodHandler)
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        methodHandler?.detach()
        methodHandler = null
    }
}
