package com.example.applauncher

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.KeyEvent
import android.view.accessibility.AccessibilityNodeInfo

class TvLauncherService : AccessibilityService() {
    
    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("TvLauncherService", "Service connected")
    }
    
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event?.let {
            if (it.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                // Check if we're on the home screen
                if (it.packageName?.contains("launcher") == true || 
                    it.packageName?.contains("home") == true) {
                    Log.d("TvLauncherService", "Detected home screen - launching kiosk app")
                    // Launch our app
                    launchKioskApp()
                }
            }
        }
    }
    
    override fun onKeyEvent(event: KeyEvent?): Boolean {
        event?.let {
            if (it.keyCode == KeyEvent.KEYCODE_HOME && it.action == KeyEvent.ACTION_DOWN) {
                Log.d("TvLauncherService", "Home button pressed - launching kiosk app")
                launchKioskApp()
                return true // Consume the event
            }
        }
        return super.onKeyEvent(event)
    }
    
    private fun launchKioskApp() {
        try {
            val intent = Intent(this, MainActivity::class.java)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            intent.addCategory(Intent.CATEGORY_HOME)
            intent.addCategory(Intent.CATEGORY_DEFAULT)
            startActivity(intent)
        } catch (e: Exception) {
            Log.e("TvLauncherService", "Failed to launch kiosk app", e)
        }
    }
    
    override fun onInterrupt() {
        Log.d("TvLauncherService", "Service interrupted")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d("TvLauncherService", "Service destroyed")
    }
}
