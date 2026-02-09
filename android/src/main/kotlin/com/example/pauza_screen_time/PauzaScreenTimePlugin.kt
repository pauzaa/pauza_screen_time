package com.example.pauza_screen_time

import android.app.Activity
import android.content.Context
import com.example.pauza_screen_time.app_restriction.alarm.RestrictionAlarmOrchestrator
import com.example.pauza_screen_time.app_restriction.method_channel.RestrictionsChannelRegistrar
import com.example.pauza_screen_time.core.method_channel.CoreChannelRegistrar
import com.example.pauza_screen_time.installed_apps.method_channel.InstalledAppsChannelRegistrar
import com.example.pauza_screen_time.permissions.method_channel.PermissionsChannelRegistrar
import com.example.pauza_screen_time.usage_stats.method_channel.UsageStatsChannelRegistrar
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/**
 * Main plugin class for Pauza Screen Time.
 *
 * This plugin provides functionality for:
 * - Managing app restrictions and blocking
 * - Monitoring app usage statistics
 * - Enumerating installed applications
 * - Handling platform-specific permissions
 */
class PauzaScreenTimePlugin :
    FlutterPlugin,
    ActivityAware {

    private val coreRegistrar = CoreChannelRegistrar()
    private val permissionsRegistrar = PermissionsChannelRegistrar()
    private val installedAppsRegistrar = InstalledAppsChannelRegistrar()
    private val usageStatsRegistrar = UsageStatsChannelRegistrar()
    private val restrictionsRegistrar = RestrictionsChannelRegistrar()
    
    // Current activity reference, needed for permission requests
    private var activity: Activity? = null
    
    // Application context for service checks
    private var applicationContext: Context? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = flutterPluginBinding.binaryMessenger
        val context = flutterPluginBinding.applicationContext

        applicationContext = context
        coreRegistrar.attach(messenger)
        permissionsRegistrar.attach(messenger, context) { activity }
        installedAppsRegistrar.attach(messenger, context)
        usageStatsRegistrar.attach(messenger, context)
        restrictionsRegistrar.attach(messenger) { applicationContext }
        RestrictionAlarmOrchestrator(context).rescheduleAll()
    }

    // ============= Plugin Lifecycle =============

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        coreRegistrar.detach()
        permissionsRegistrar.detach()
        installedAppsRegistrar.detach()
        usageStatsRegistrar.detach()
        restrictionsRegistrar.detach()

        applicationContext = null
    }

    // ============= Activity Lifecycle =============

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
