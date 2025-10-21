package com.example.applauncher

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    
    private val CHANNEL = "launcher_exit"
    private var methodChannel: MethodChannel? = null
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Set up method channel
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger
        if (messenger != null) {
            methodChannel = MethodChannel(messenger, CHANNEL)
            methodChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "openSystemSettings" -> {
                        openSystemSettings()
                        result.success(null)
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
        }
        
        // Start the service to keep the launcher alive
        val serviceIntent = Intent(this, LauncherService::class.java)
        startForegroundService(serviceIntent)
    }
    
    override fun onResume() {
        super.onResume()
        // Ensure service is running when activity resumes
        val serviceIntent = Intent(this, LauncherService::class.java)
        startForegroundService(serviceIntent)
    }
    
    override fun onPause() {
        super.onPause()
        // Don't stop the service when pausing - keep it alive
    }
    
    override fun onBackPressed() {
        // Send back button event to Flutter
        methodChannel?.invokeMethod("onBackPressed", null)
    }
    
    private fun openSystemSettings() {
        try {
            // Try multiple approaches to open settings
            
            // First try: General settings
            try {
                val intent = Intent(android.provider.Settings.ACTION_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                startActivity(intent)
                return
            } catch (e: Exception) {
                // Continue to next attempt
            }
            
            // Second try: Home settings
            try {
                val homeSettingsIntent = Intent(android.provider.Settings.ACTION_HOME_SETTINGS)
                homeSettingsIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                startActivity(homeSettingsIntent)
                return
            } catch (e: Exception) {
                // Continue to next attempt
            }
            
            // Third try: Apps settings
            try {
                val appsIntent = Intent(android.provider.Settings.ACTION_APPLICATION_SETTINGS)
                appsIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                startActivity(appsIntent)
                return
            } catch (e: Exception) {
                // Continue to next attempt
            }
            
            // Fourth try: Device settings
            try {
                val deviceIntent = Intent(android.provider.Settings.ACTION_DEVICE_INFO_SETTINGS)
                deviceIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                startActivity(deviceIntent)
                return
            } catch (e: Exception) {
                // All attempts failed
            }
            
        } catch (e: Exception) {
            // Error opening settings
        }
    }
}
