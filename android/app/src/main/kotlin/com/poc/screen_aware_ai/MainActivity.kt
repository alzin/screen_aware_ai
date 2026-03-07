package com.poc.screen_aware_ai

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.poc.screen_aware_ai/screen"
    private val SCREEN_CAPTURE_REQUEST_CODE = 1001

    private var pendingResult: MethodChannel.Result? = null
    private var mediaProjectionManager: MediaProjectionManager? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestScreenCapture" -> {
                    pendingResult = result
                    val intent = mediaProjectionManager!!.createScreenCaptureIntent()
                    startActivityForResult(intent, SCREEN_CAPTURE_REQUEST_CODE)
                }
                "captureScreen" -> {
                    val service = ScreenCaptureService.instance
                    if (service != null) {
                        service.captureScreen(this) { path ->
                            result.success(path)
                        }
                    } else {
                        result.error("NO_SERVICE", "Screen capture service not running", null)
                    }
                }
                "isAccessibilityEnabled" -> {
                    result.success(ScreenActionService.instance != null)
                }
                "getScreenSize" -> {
                    val service = ScreenCaptureService.instance
                    if (service != null) {
                        result.success(mapOf("width" to service.screenWidth, "height" to service.screenHeight))
                    } else {
                        val wm = getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager
                        val metrics = android.util.DisplayMetrics()
                        @Suppress("DEPRECATION")
                        wm.defaultDisplay.getRealMetrics(metrics)
                        result.success(mapOf("width" to metrics.widthPixels, "height" to metrics.heightPixels))
                    }
                }
                "performTap" -> {
                    val x = call.argument<Double>("x")?.toFloat() ?: 0f
                    val y = call.argument<Double>("y")?.toFloat() ?: 0f
                    val service = ScreenActionService.instance
                    if (service != null) {
                        Thread {
                            val success = service.performTap(x, y)
                            runOnUiThread { result.success(success) }
                        }.start()
                    } else {
                        result.error("NO_SERVICE", "Accessibility service not enabled", null)
                    }
                }
                "performType" -> {
                    val text = call.argument<String>("text") ?: ""
                    val service = ScreenActionService.instance
                    if (service != null) {
                        service.performType(text)
                        result.success(true)
                    } else {
                        result.error("NO_SERVICE", "Accessibility service not enabled", null)
                    }
                }
                "pressBack" -> {
                    val service = ScreenActionService.instance
                    if (service != null) {
                        service.pressBack()
                        result.success(true)
                    } else {
                        result.error("NO_SERVICE", "Accessibility service not enabled", null)
                    }
                }
                "pressHome" -> {
                    val service = ScreenActionService.instance
                    if (service != null) {
                        service.pressHome()
                        result.success(true)
                    } else {
                        result.error("NO_SERVICE", "Accessibility service not enabled", null)
                    }
                }
                "openApp" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    try {
                        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                        if (launchIntent != null) {
                            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(launchIntent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("LAUNCH_FAILED", "Could not launch $packageName: ${e.message}", null)
                    }
                }
                "performSwipe" -> {
                    val startX = call.argument<Double>("startX")?.toFloat() ?: 0f
                    val startY = call.argument<Double>("startY")?.toFloat() ?: 0f
                    val endX = call.argument<Double>("endX")?.toFloat() ?: 0f
                    val endY = call.argument<Double>("endY")?.toFloat() ?: 0f
                    val service = ScreenActionService.instance
                    if (service != null) {
                        Thread {
                            val success = service.performSwipe(startX, startY, endX, endY)
                            runOnUiThread { result.success(success) }
                        }.start()
                    } else {
                        result.error("NO_SERVICE", "Accessibility service not enabled", null)
                    }
                }
                "openAccessibilitySettings" -> {
                    val intent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SCREEN_CAPTURE_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                // Start the foreground service with the projection data
                val serviceIntent = Intent(this, ScreenCaptureService::class.java).apply {
                    putExtra("resultCode", resultCode)
                    putExtra("data", data)
                }
                startForegroundService(serviceIntent)

                // Give the service a moment to start
                android.os.Handler(mainLooper).postDelayed({
                    pendingResult?.success(true)
                    pendingResult = null
                }, 500)
            } else {
                pendingResult?.success(false)
                pendingResult = null
            }
        }
    }
}
