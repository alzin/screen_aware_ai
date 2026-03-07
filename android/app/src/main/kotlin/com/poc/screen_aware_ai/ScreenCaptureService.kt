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

        // Clean up any existing resources first
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        mediaProjection?.stop()
        mediaProjection = null

        try {
            val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = projectionManager.getMediaProjection(resultCode, data)

            if (mediaProjection == null) {
                Log.e(TAG, "initializeProjection: getMediaProjection returned null")
                return
            }

            // Android 14+ requires registering a callback BEFORE createVirtualDisplay
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                mediaProjection!!.registerCallback(object : MediaProjection.Callback() {
                    override fun onStop() {
                        Log.d(TAG, "MediaProjection.Callback: onStop — projection revoked")
                        virtualDisplay?.release()
                        virtualDisplay = null
                        imageReader?.close()
                        imageReader = null
                        mediaProjection = null
                    }
                }, Handler(Looper.getMainLooper()))
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

        val handler = Handler(Looper.getMainLooper())
        val done = AtomicBoolean(false)

        // Drain any stale images so the next frame from the listener is fresh
        try {
            reader.acquireLatestImage()?.close()
        } catch (_: Exception) {}

        // Listen for the next fresh frame rendered to the ImageReader surface
        reader.setOnImageAvailableListener({ ir ->
            if (done.compareAndSet(false, true)) {
                ir.setOnImageAvailableListener(null, null)
                try {
                    val image = ir.acquireLatestImage()
                    if (image != null) {
                        val path = saveImageToFile(context, image)
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
        }, handler)

        // Timeout fallback: if no new frame arrives within 3 seconds
        handler.postDelayed({
            if (done.compareAndSet(false, true)) {
                reader.setOnImageAvailableListener(null, null)
                Log.w(TAG, "captureScreen: timed out waiting for frame, trying fallback")
                try {
                    val image = reader.acquireLatestImage()
                    if (image != null) {
                        val path = saveImageToFile(context, image)
                        callback(path)
                    } else {
                        Log.w(TAG, "captureScreen: fallback acquireLatestImage also null")
                        callback(null)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "captureScreen: error in fallback", e)
                    callback(null)
                }
            }
        }, 3000)
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

            val file = File(context.cacheDir, "screenshot_${System.currentTimeMillis()}.png")
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
            .setContentTitle("Screen Aware AI")
            .setContentText("Capturing screen for analysis...")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy: cleaning up")
        virtualDisplay?.release()
        imageReader?.close()
        mediaProjection?.stop()
        instance = null
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
