package com.poc.screen_aware_ai

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean

class ScreenCaptureService : Service() {

    companion object {
        private const val TAG = "ScreenCaptureService"
        var instance: ScreenCaptureService? = null
        private const val CHANNEL_ID = "screen_capture_channel"
        private const val NOTIFICATION_ID = 1
        // Use a sentinel that does NOT collide with Activity.RESULT_OK (-1)
        private const val RESULT_CODE_DEFAULT = 0
    }

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var projectionCallback: MediaProjection.Callback? = null
    // Generation counter to guard against stale callbacks
    private var projectionGeneration = 0L
    private var captureThread: HandlerThread? = null
    private var captureHandler: Handler? = null
    var screenWidth = 0
        private set
    var screenHeight = 0
        private set
    private var screenDensity = 0

    val isInitialized: Boolean
        get() = imageReader != null && mediaProjection != null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        captureThread = HandlerThread("ScreenCaptureWorker").apply { start() }
        captureHandler = Handler(captureThread!!.looper)
        getScreenMetrics()
        Log.d(TAG, "onCreate: service created, screenWidth=$screenWidth, screenHeight=$screenHeight")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)

        // IMPORTANT: Activity.RESULT_OK == -1, so use 0 as the default sentinel
        val resultCode = intent?.getIntExtra("resultCode", RESULT_CODE_DEFAULT) ?: RESULT_CODE_DEFAULT
        val data: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra("data", Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra("data")
        }

        Log.d(TAG, "onStartCommand: resultCode=$resultCode (RESULT_OK=${Activity.RESULT_OK}), data=${data != null}")

        if (resultCode == Activity.RESULT_OK && data != null) {
            initializeProjection(resultCode, data)
        } else {
            Log.w(TAG, "onStartCommand: missing or invalid projection data (resultCode=$resultCode), service will not capture")
        }

        return START_NOT_STICKY
    }

    fun initializeProjection(resultCode: Int, data: Intent) {
        Log.d(TAG, "initializeProjection: setting up with resultCode=$resultCode")

        // IMPORTANT: Unregister the old callback BEFORE stopping the old projection.
        // If we don't, the old onStop callback fires asynchronously on the main looper
        // AFTER the new resources are set up, wiping them out.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            projectionCallback?.let { cb ->
                try {
                    mediaProjection?.unregisterCallback(cb)
                    Log.d(TAG, "initializeProjection: unregistered old callback")
                } catch (e: Exception) {
                    Log.w(TAG, "initializeProjection: failed to unregister old callback", e)
                }
            }
            projectionCallback = null
        }

        // Now safely clean up old resources — no callback will fire
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        mediaProjection?.stop()
        mediaProjection = null

        // Increment generation so any leaked stale callbacks become no-ops
        val currentGeneration = ++projectionGeneration

        try {
            val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = projectionManager.getMediaProjection(resultCode, data)

            if (mediaProjection == null) {
                Log.e(TAG, "initializeProjection: getMediaProjection returned null")
                return
            }

            // Android 14+ requires registering a callback BEFORE createVirtualDisplay
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val callback = object : MediaProjection.Callback() {
                    override fun onStop() {
                        // Guard: ignore if this callback belongs to a stale generation
                        if (projectionGeneration != currentGeneration) {
                            Log.d(TAG, "MediaProjection.Callback: onStop for stale generation $currentGeneration (current=$projectionGeneration), ignoring")
                            return
                        }
                        Log.d(TAG, "MediaProjection.Callback: onStop — projection revoked by system")
                        virtualDisplay?.release()
                        virtualDisplay = null
                        imageReader?.close()
                        imageReader = null
                        mediaProjection = null
                    }
                }
                projectionCallback = callback
                mediaProjection!!.registerCallback(callback, Handler(Looper.getMainLooper()))
            }

            setupVirtualDisplay()
            Log.d(TAG, "initializeProjection: success, imageReader=${imageReader != null}")
        } catch (e: Exception) {
            Log.e(TAG, "initializeProjection: failed", e)
        }
    }

    private fun getScreenMetrics() {
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getRealMetrics(metrics)
        screenWidth = metrics.widthPixels
        screenHeight = metrics.heightPixels
        screenDensity = metrics.densityDpi
    }

    private fun setupVirtualDisplay() {
        imageReader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 2)
        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "ScreenCapture",
            screenWidth, screenHeight, screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface, null, null
        )
        Log.d(TAG, "setupVirtualDisplay: virtualDisplay=${virtualDisplay != null}")
    }

    fun captureScreen(context: Context, callback: (String?) -> Unit) {
        val reader = imageReader
        if (reader == null) {
            Log.w(TAG, "captureScreen: imageReader is null, not initialized")
            callback(null)
            return
        }

        val workerHandler = captureHandler
        if (workerHandler == null) {
            Log.w(TAG, "captureScreen: capture handler is null")
            callback(null)
            return
        }

        val appContext = context.applicationContext

        workerHandler.post {
            // Strategy 1: Try to acquire the latest available frame directly.
            // This is the fastest path and avoids timeouts when the display
            // hasn't produced a new frame (e.g., static screen content).
            // The frame in the buffer IS the current screen — no need to drain and wait.
            try {
                val image = reader.acquireLatestImage()
                if (image != null) {
                    val path = saveImageToFile(appContext, image)
                    callback(path)
                    return@post
                }
            } catch (e: Exception) {
                Log.w(TAG, "captureScreen: direct acquire failed: ${e.message}")
            }

            // Strategy 2: No image available yet — wait for the next frame
            // from the VirtualDisplay (e.g., right after initialization).
            Log.d(TAG, "captureScreen: no image in buffer, waiting for next frame")
            val done = AtomicBoolean(false)

            reader.setOnImageAvailableListener({ ir ->
                if (done.compareAndSet(false, true)) {
                    ir.setOnImageAvailableListener(null, null)
                    try {
                        val image = ir.acquireLatestImage()
                        if (image != null) {
                            val path = saveImageToFile(appContext, image)
                            callback(path)
                        } else {
                            Log.w(TAG, "captureScreen: acquireLatestImage returned null in listener")
                            callback(null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "captureScreen: error in listener", e)
                        callback(null)
                    }
                }
            }, workerHandler)

            // Timeout: 1.5 seconds (reduced from 3s since this is only the fallback path)
            workerHandler.postDelayed({
                if (done.compareAndSet(false, true)) {
                    reader.setOnImageAvailableListener(null, null)
                    Log.w(TAG, "captureScreen: timed out waiting for frame (1.5s)")
                    callback(null)
                }
            }, 1500)
        }
    }

    private fun saveImageToFile(context: Context, image: Image): String? {
        try {
            val planes = image.planes
            val buffer = planes[0].buffer
            val pixelStride = planes[0].pixelStride
            val rowStride = planes[0].rowStride
            val rowPadding = rowStride - pixelStride * screenWidth

            val bitmap = Bitmap.createBitmap(
                screenWidth + rowPadding / pixelStride,
                screenHeight,
                Bitmap.Config.ARGB_8888
            )
            bitmap.copyPixelsFromBuffer(buffer)
            image.close()

            val croppedBitmap = Bitmap.createBitmap(bitmap, 0, 0, screenWidth, screenHeight)
            if (croppedBitmap != bitmap) bitmap.recycle()

            // Use persistent filesDir instead of cacheDir to prevent system purging
            val screenshotsDir = File(context.filesDir, "screenshots")
            if (!screenshotsDir.exists()) {
                screenshotsDir.mkdirs()
            }

            // Cleanup old screenshots before saving new one
            cleanupOldScreenshots(screenshotsDir, maxCount = 50)

            val file = File(screenshotsDir, "screenshot_${System.currentTimeMillis()}.png")
            FileOutputStream(file).use { out ->
                croppedBitmap.compress(Bitmap.CompressFormat.PNG, 85, out)
            }
            croppedBitmap.recycle()

            Log.d(TAG, "captureScreen: saved to ${file.absolutePath}")
            return file.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "saveImageToFile: error", e)
            image.close()
            return null
        }
    }

    private fun cleanupOldScreenshots(dir: File, maxCount: Int) {
        try {
            val files = dir.listFiles { file -> file.isFile && file.name.startsWith("screenshot_") }
            if (files != null && files.size >= maxCount) {
                // Sort by last modified ascending (oldest first)
                files.sortBy { it.lastModified() }
                
                // Delete oldest files until we are below the limit
                val numToDelete = files.size - maxCount + 1
                for (i in 0 until numToDelete) {
                    if (files[i].delete()) {
                        Log.d(TAG, "cleanupOldScreenshots: deleted old screenshot ${files[i].name}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "cleanupOldScreenshots: failed", e)
        }
    }

    fun clearScreenshots(context: Context) {
        try {
            val screenshotsDir = File(context.filesDir, "screenshots")
            if (screenshotsDir.exists()) {
                val deleted = screenshotsDir.listFiles()?.map { it.delete() }?.all { it } ?: true
                Log.d(TAG, "clearScreenshots: deleted all screenshots: $deleted")
            }
        } catch (e: Exception) {
            Log.e(TAG, "clearScreenshots: failed", e)
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Screen Capture",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Notification for screen capture service"
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun createNotification(): Notification {
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Lucy")
            .setContentText("Capturing screen for analysis...")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy: cleaning up")
        captureHandler?.removeCallbacksAndMessages(null)
        captureHandler = null
        captureThread?.quitSafely()
        captureThread = null
        // Unregister callback before stopping to prevent it from running during cleanup
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            projectionCallback?.let { cb ->
                try {
                    mediaProjection?.unregisterCallback(cb)
                } catch (e: Exception) {
                    Log.w(TAG, "onDestroy: failed to unregister callback", e)
                }
            }
            projectionCallback = null
        }
        // Increment generation to invalidate any leaked callbacks
        projectionGeneration++
        virtualDisplay?.release()
        imageReader?.close()
        mediaProjection?.stop()
        instance = null
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
