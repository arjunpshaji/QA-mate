package com.example.qa_mate

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler {

    private val CHANNEL = "com.example.qa_mate/screen_recorder"
    private val SCREEN_RECORD_REQUEST_CODE = 4242

    private var pendingResult: MethodChannel.Result? = null
    private var pendingOutputPath: String? = null
    private var isRecording = false
    private var originalShowTouches: Int = 0
    private var showTouchesModifiedByUs: Boolean = false

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> {
                result.success(true)
            }
            "startRecording" -> {
                val outputPath = call.argument<String>("outputPath")
                val showTouches = call.argument<Boolean>("showTouches") ?: false
                if (outputPath.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "outputPath is required", null)
                    return
                }

                if (isRecording) {
                    result.error("ALREADY_RECORDING", "A recording is already active", null)
                    return
                }

                if (showTouches) {
                    try {
                        originalShowTouches = Settings.System.getInt(contentResolver, "show_touches", 0)
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.System.canWrite(this)) {
                            val success = Settings.System.putInt(contentResolver, "show_touches", 1)
                            if (success && originalShowTouches == 0) {
                                showTouchesModifiedByUs = true
                            }
                        }
                    } catch (_: Exception) {}
                }

                pendingResult = result
                pendingOutputPath = outputPath

                val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                val intent = projectionManager.createScreenCaptureIntent()
                startActivityForResult(intent, SCREEN_RECORD_REQUEST_CODE)
            }
            "stopRecording" -> {
                if (showTouchesModifiedByUs) {
                    try {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.System.canWrite(this)) {
                            Settings.System.putInt(contentResolver, "show_touches", originalShowTouches)
                        }
                    } catch (_: Exception) {}
                    showTouchesModifiedByUs = false
                }

                if (!isRecording) {
                    result.success(pendingOutputPath)
                    return
                }

                // Capture path BEFORE clearing state
                val savedPath = pendingOutputPath

                val service = ScreenCaptureService.instance
                val finalPath = if (service != null) {
                    // stopRecordingAndCleanup() is synchronous: stop() → reset() → release()
                    // so the moov atom is guaranteed written before we return the path.
                    service.stopRecordingAndCleanup() ?: savedPath
                } else {
                    // Service instance lost (killed by OS); path still valid on disk
                    val stopIntent = Intent(this, ScreenCaptureService::class.java).apply {
                        action = ScreenCaptureService.ACTION_STOP
                    }
                    startService(stopIntent)
                    // Give the service a moment to flush before we return the path
                    Thread.sleep(300)
                    savedPath
                }

                isRecording = false
                pendingOutputPath = null
                result.success(finalPath)
            }
            "pauseRecording" -> {
                val service = ScreenCaptureService.instance
                val ok = service?.pauseRecording() ?: false
                result.success(ok)
            }
            "resumeRecording" -> {
                val service = ScreenCaptureService.instance
                val ok = service?.resumeRecording() ?: false
                result.success(ok)
            }
            "bringAppToForeground" -> {
                try {
                    val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    }
                    if (intent != null) {
                        applicationContext.startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            }
            "openSettings" -> {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", packageName, null)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
                result.success(true)
            }
            "generateThumbnail" -> {
                val videoPath = call.argument<String>("videoPath")
                val outputPath = call.argument<String>("outputPath")
                if (videoPath.isNullOrBlank() || outputPath.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "videoPath and outputPath are required", null)
                    return
                }

                Thread {
                    try {
                        val retriever = android.media.MediaMetadataRetriever()
                        retriever.setDataSource(videoPath)
                        val bitmap = retriever.getFrameAtTime(0, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                        retriever.release()

                        if (bitmap != null) {
                            val file = File(outputPath)
                            file.parentFile?.mkdirs()
                            java.io.FileOutputStream(file).use { out ->
                                bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, out)
                            }
                            runOnUiThread { result.success(outputPath) }
                        } else {
                            runOnUiThread { result.error("EXTRACTION_FAILED", "Could not extract video frame", null) }
                        }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("THUMBNAIL_ERROR", e.message, null) }
                    }
                }.start()
            }
            "canWriteSettings" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    result.success(Settings.System.canWrite(this))
                } else {
                    result.success(true)
                }
            }
            "getShowTouches" -> {
                try {
                    val showTouches = Settings.System.getInt(contentResolver, "show_touches", 0) == 1
                    result.success(showTouches)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "setShowTouches" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.System.canWrite(this)) {
                    result.error("PERMISSION_REQUIRED", "WRITE_SETTINGS permission is required to change show_touches", null)
                    return
                }
                try {
                    val success = Settings.System.putInt(contentResolver, "show_touches", if (enabled) 1 else 0)
                    result.success(success)
                } catch (e: SecurityException) {
                    result.error("SECURITY_EXCEPTION", e.message, null)
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            }
            "openWriteSettings" -> {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                            data = Uri.parse("package:$packageName")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            }
            "openDeveloperSettings" -> {
                try {
                    val intent = Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    try {
                        val fallback = Intent(Settings.ACTION_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(fallback)
                        result.success(true)
                    } catch (e2: Exception) {
                        result.error("ERROR", e2.message, null)
                    }
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == SCREEN_RECORD_REQUEST_CODE) {
            val result = pendingResult
            pendingResult = null

            if (resultCode == Activity.RESULT_OK && data != null) {
                // Use the path Flutter sent; fall back to cache dir only if missing.
                val outputPath = if (!pendingOutputPath.isNullOrBlank()) pendingOutputPath!!
                                 else "${cacheDir.absolutePath}/rec_${System.currentTimeMillis()}.mp4"
                // Always keep pendingOutputPath in sync so stopRecording returns
                // the EXACT file the service will write to.
                pendingOutputPath = outputPath

                val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
                val metrics = DisplayMetrics()
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay.getRealMetrics(metrics)

                // Scale down slightly to ensure video encoder performance (720p or 1080p width)
                var width = metrics.widthPixels
                var height = metrics.heightPixels
                val density = metrics.densityDpi

                // Ensure dimensions are even numbers (required by AVC/H264 encoders)
                if (width % 2 != 0) width -= 1
                if (height % 2 != 0) height -= 1

                val serviceIntent = Intent(this, ScreenCaptureService::class.java).apply {
                    action = ScreenCaptureService.ACTION_START
                    putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                    putExtra(ScreenCaptureService.EXTRA_RESULT_DATA, data)
                    putExtra(ScreenCaptureService.EXTRA_OUTPUT_PATH, outputPath)
                    putExtra(ScreenCaptureService.EXTRA_WIDTH, width)
                    putExtra(ScreenCaptureService.EXTRA_HEIGHT, height)
                    putExtra(ScreenCaptureService.EXTRA_DENSITY, density)
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }

                isRecording = true
                result?.success(true)
            } else {
                if (showTouchesModifiedByUs) {
                    try {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.System.canWrite(this)) {
                            Settings.System.putInt(contentResolver, "show_touches", originalShowTouches)
                        }
                    } catch (_: Exception) {}
                    showTouchesModifiedByUs = false
                }
                pendingOutputPath = null
                result?.error(
                    "PERMISSION_DENIED",
                    "User canceled or denied screen recording permission.",
                    null
                )
            }
        }
    }
}
