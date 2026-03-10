package com.poc.screen_aware_ai

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.poc.screen_aware_ai/screen"
    private val SCREEN_CAPTURE_REQUEST_CODE = 1001
    private val TAG = "MainActivity"

    private var pendingResult: MethodChannel.Result? = null
    private var mediaProjectionManager: MediaProjectionManager? = null

    // Store projection data so we can reinitialize the service if needed.
    // IMPORTANT: Use 0 as sentinel — Activity.RESULT_OK is -1, so -1 can't be the default.
    private var projectionResultCode: Int = 0
    private var projectionData: Intent? = null

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
                    if (service == null) {
                        // Service not running at all — try to restart if we have stored data
                        if (projectionResultCode == Activity.RESULT_OK && projectionData != null) {
                            Log.w(TAG, "captureScreen: service is null, restarting with stored projection data")
                            try {
                                startCaptureService(projectionResultCode, projectionData!!)
                                // Return error so Flutter side can retry after service starts
                                result.error("NOT_INITIALIZED", "Service restarting, retry capture", null)
                            } catch (e: Exception) {
                                // On Android 14+ the token may be single-use — need fresh permission
                                Log.e(TAG, "captureScreen: failed to restart service with stored data", e)
                                projectionData = null
                                result.error("NO_SERVICE", "Screen capture token expired, need new permission", null)
                            }
                        } else {
                            result.error("NO_SERVICE", "Screen capture service not running, need permission", null)
                        }
                    } else if (!service.isInitialized) {
                        // Service exists but imageReader is null — try to reinitialize
                        if (projectionResultCode == Activity.RESULT_OK && projectionData != null) {
                            Log.w(TAG, "captureScreen: service not initialized, reinitializing with stored data")
                            try {
                                service.initializeProjection(projectionResultCode, projectionData!!)
                                // If initialization succeeded, capture immediately
                                if (service.isInitialized) {
                                    service.captureScreen(this) { path ->
                                        result.success(path)
                                    }
                                } else {
                                    result.error("NOT_INITIALIZED", "Failed to reinitialize, need new permission", null)
                                }
                            } catch (e: SecurityException) {
                                // Android 14+: projection token is single-use, can't be reused
                                Log.e(TAG, "captureScreen: SecurityException — token expired, need new permission", e)
                                projectionData = null
                                result.error("NOT_INITIALIZED", "Projection token expired, need new permission", null)
                            } catch (e: Exception) {
                                Log.e(TAG, "captureScreen: reinit failed", e)
                                result.error("NOT_INITIALIZED", "Reinit failed: ${e.message}", null)
                            }
                        } else {
                            result.error("NOT_INITIALIZED", "Service not initialized, need permission", null)
                        }
                    } else {
                        service.captureScreen(this) { path ->
                            result.success(path)
                        }
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
                "getUITree" -> {
                    val service = ScreenActionService.instance
                    if (service != null) {
                        result.success(service.getUITree())
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
                "clearScreenshots" -> {
                    val service = ScreenCaptureService.instance
                    if (service != null) {
                        service.clearScreenshots(this)
                    } else {
                        // Even if service is null, we can delete the files manually
                        try {
                            val screenshotsDir = java.io.File(filesDir, "screenshots")
                            if (screenshotsDir.exists()) {
                                screenshotsDir.listFiles()?.forEach { it.delete() }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "clearScreenshots: manual delete failed", e)
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startCaptureService(resultCode: Int, data: Intent) {
        val serviceIntent = Intent(this, ScreenCaptureService::class.java).apply {
            putExtra("resultCode", resultCode)
            putExtra("data", data)
        }
        startForegroundService(serviceIntent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SCREEN_CAPTURE_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                // Store projection data for potential reinitialization later
                projectionResultCode = resultCode
                projectionData = data.clone() as Intent

                Log.d(TAG, "onActivityResult: permission granted, starting capture service")

                startCaptureService(resultCode, data)

                // Wait for the service to fully initialize before returning success.
                // With the callback fix, onStartCommand should reliably initialize.
                // Do NOT try to reinitialize with stored data here — on Android 14+
                // the projection token is single-use and was already consumed by onStartCommand.
                android.os.Handler(mainLooper).postDelayed({
                    val service = ScreenCaptureService.instance
                    if (service != null && service.isInitialized) {
                        Log.d(TAG, "onActivityResult: service initialized successfully")
                        pendingResult?.success(true)
                    } else {
                        Log.w(TAG, "onActivityResult: service not initialized after 1.5s")
                        pendingResult?.success(false)
                    }
                    pendingResult = null
                }, 1500)
            } else {
                Log.w(TAG, "onActivityResult: permission denied or no data")
                pendingResult?.success(false)
                pendingResult = null
            }
        }
    }
}
