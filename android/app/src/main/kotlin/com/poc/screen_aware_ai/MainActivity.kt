package com.poc.screen_aware_ai

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
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
    private var methodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingInitializationListener: ((Boolean) -> Unit)? = null
    private var pendingInitializationTimeout: Runnable? = null

    // Store projection data so we can reinitialize the service if needed.
    // IMPORTANT: Use 0 as sentinel — Activity.RESULT_OK is -1, so -1 can't be the default.
    private var projectionResultCode: Int = 0
    private var projectionData: Intent? = null

    // Broadcast receiver for the stop notification action
    private val forceStopReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == OverlayService.ACTION_FORCE_STOP) {
                Log.d(TAG, "Received FORCE_STOP broadcast, forwarding to Flutter")
                methodChannel?.invokeMethod("onForceStop", null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        // Register broadcast receiver for the stop notification action
        val filter = IntentFilter(OverlayService.ACTION_FORCE_STOP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(forceStopReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(forceStopReceiver, filter)
        }

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
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
                                val initialized = service.initializeProjection(projectionResultCode, projectionData!!)
                                // If initialization succeeded, capture immediately
                                if (initialized && service.isInitialized) {
                                    service.captureScreen { bytes ->
                                        runOnUiThread { result.success(bytes) }
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
                        service.captureScreen { bytes ->
                            runOnUiThread { result.success(bytes) }
                        }
                    }
                }
                "isAccessibilityEnabled" -> {
                    result.success(ScreenActionService.instance != null)
                }
                "getUiChangeSequence" -> {
                    result.success(ScreenActionService.instance?.getUiChangeSequence() ?: 0L)
                }
                "waitForUiChange" -> {
                    val sinceSequence = call.argument<Number>("sinceSequence")?.toLong() ?: 0L
                    val timeoutMs = call.argument<Number>("timeoutMs")?.toLong() ?: 0L
                    val service = ScreenActionService.instance
                    if (service != null) {
                        service.waitForUiChange(sinceSequence, timeoutMs) { changed ->
                            runOnUiThread { result.success(changed) }
                        }
                    } else {
                        result.error("NO_SERVICE", "Accessibility service not enabled", null)
                    }
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
                "showStopOverlay" -> {
                    val intent = Intent(this, OverlayService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "hideStopOverlay" -> {
                    val service = OverlayService.instance
                    if (service != null) {
                        service.hideOverlay()
                        stopService(Intent(this, OverlayService::class.java))
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun clearPendingInitializationWait() {
        pendingInitializationListener?.let { listener ->
            ScreenCaptureService.removeInitializationListener(listener)
        }
        pendingInitializationListener = null
        pendingInitializationTimeout?.let { timeout ->
            mainHandler.removeCallbacks(timeout)
        }
        pendingInitializationTimeout = null
    }

    private fun resolvePendingScreenCaptureRequest(success: Boolean) {
        clearPendingInitializationWait()
        pendingResult?.success(success)
        pendingResult = null
    }

    private fun awaitScreenCaptureInitialization(timeoutMs: Long = 5000L) {
        if (ScreenCaptureService.instance?.isInitialized == true) {
            Log.d(TAG, "awaitScreenCaptureInitialization: service already initialized")
            resolvePendingScreenCaptureRequest(true)
            return
        }

        val listener: (Boolean) -> Unit = { success ->
            runOnUiThread {
                if (pendingResult == null) return@runOnUiThread
                Log.d(TAG, "awaitScreenCaptureInitialization: initialization completed (success=$success)")
                resolvePendingScreenCaptureRequest(success)
            }
        }

        pendingInitializationListener = listener
        ScreenCaptureService.addInitializationListener(listener)

        val timeout = Runnable {
            if (pendingResult == null) return@Runnable
            Log.w(TAG, "awaitScreenCaptureInitialization: timed out after ${timeoutMs}ms")
            resolvePendingScreenCaptureRequest(false)
        }
        pendingInitializationTimeout = timeout
        mainHandler.postDelayed(timeout, timeoutMs)
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

                clearPendingInitializationWait()
                startCaptureService(resultCode, data)
                awaitScreenCaptureInitialization()
            } else {
                Log.w(TAG, "onActivityResult: permission denied or no data")
                resolvePendingScreenCaptureRequest(false)
            }
        }
    }

    override fun onDestroy() {
        clearPendingInitializationWait()
        try {
            unregisterReceiver(forceStopReceiver)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to unregister forceStopReceiver", e)
        }
        methodChannel = null
        super.onDestroy()
    }
}
