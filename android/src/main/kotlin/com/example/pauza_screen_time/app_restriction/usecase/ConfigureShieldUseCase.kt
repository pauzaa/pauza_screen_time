package com.example.pauza_screen_time.app_restriction.usecase

import android.content.Context
import com.example.pauza_screen_time.app_restriction.storage.ShieldConfigStore

internal class ConfigureShieldUseCase(private val context: Context) {
    fun execute(configMap: Map<String, Any?>) {
        ShieldConfigStore.getInstance(context).configure(configMap)
    }
}
