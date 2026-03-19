package com.poc.screen_aware_ai

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

class OverlayService : Service() {

    companion object {
        var instance: OverlayService? = null
        private const val TAG = "OverlayService"
        const val ACTION_FORCE_STOP = "com.poc.screen_aware_ai.FORCE_STOP"
    }

    private var windowManager: WindowManager? = null
    private var overlayView: LinearLayout? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (overlayView == null) {
            showOverlay()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun showOverlay() {
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }

        // Build the stop button view programmatically
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(48, 24, 48, 24)

            // Red rounded pill background
            val bg = GradientDrawable().apply {
                setColor(Color.parseColor("#E53935"))
                cornerRadius = 60f
            }
            background = bg

            // Elevation/shadow
            elevation = 16f

            // "Stop" label
            val label = TextView(this@OverlayService).apply {
                text = "Stop"
                textSize = 16f
                setTextColor(Color.WHITE)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            }
            addView(label)

            // On tap → broadcast force-stop intent
            setOnClickListener {
                Log.d(TAG, "Stop button tapped — broadcasting FORCE_STOP")
                val stopIntent = Intent(ACTION_FORCE_STOP)
                stopIntent.setPackage(packageName)
                sendBroadcast(stopIntent)
            }
        }

        try {
            windowManager?.addView(layout, params)
            overlayView = layout
            Log.d(TAG, "Overlay stop button shown")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show overlay", e)
        }
    }

    fun hideOverlay() {
        overlayView?.let {
            try {
                windowManager?.removeView(it)
                Log.d(TAG, "Overlay stop button hidden")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to hide overlay", e)
            }
            overlayView = null
        }
    }

    override fun onDestroy() {
        hideOverlay()
        instance = null
        super.onDestroy()
    }
}
