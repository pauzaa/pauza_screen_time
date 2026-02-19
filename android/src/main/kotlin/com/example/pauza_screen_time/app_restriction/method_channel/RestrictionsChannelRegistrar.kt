package com.example.pauza_screen_time.app_restriction.method_channel

import android.content.Context
import com.example.pauza_screen_time.core.ChannelNames
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class RestrictionsChannelRegistrar {
    private var channel: MethodChannel? = null
    private var methodHandler: RestrictionsMethodHandler? = null

    fun attach(messenger: BinaryMessenger, contextProvider: () -> Context?) {
        methodHandler = RestrictionsMethodHandler(contextProvider)
        channel = MethodChannel(messenger, ChannelNames.RESTRICTIONS).apply {
            setMethodCallHandler(methodHandler)
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        methodHandler?.dispose()
        methodHandler = null
    }
}
