package com.haqfoundation.haq_app

import com.ryanheise.audioservice.AudioServiceActivity
import android.os.StatFs
import android.os.Build
import android.content.ContentValues
import android.content.Intent
import android.provider.MediaStore
import android.app.Activity
import android.view.KeyEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : AudioServiceActivity() {
    private var prayerDevice: HaqPrayerBridge? = null
    private var reminders: HaqRemindersBridge? = null
    private var adhkarControls: MethodChannel? = null
    private var countWithVolumeKeys = false
    private var pendingImage: ByteArray? = null
    private var pendingImageResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        prayerDevice = HaqPrayerBridge(this, MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.haqfoundation.haq_app/prayer"),
            EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.haqfoundation.haq_app/heading"))
        reminders = HaqRemindersBridge(this, MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.haqfoundation.haq_app/reminders"))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.haqfoundation.haq_app/image_export")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveImage") { result.notImplemented(); return@setMethodCallHandler }
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("name")
                if (bytes == null || bytes.size > 20000000 || name == null || !Regex("haq-[0-9]+\\.png").matches(name)) {
                    result.error("image", "Invalid image", null); return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val values = ContentValues().apply {
                        put(MediaStore.Images.Media.DISPLAY_NAME, name)
                        put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                        put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Haq")
                        put(MediaStore.Images.Media.IS_PENDING, 1)
                    }
                    val resolver = contentResolver
                    var uri: android.net.Uri? = null
                    try {
                        uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                            ?: throw IllegalStateException("Cannot create image")
                        val stream = resolver.openOutputStream(uri) ?: throw IllegalStateException("Cannot write image")
                        stream.use { it.write(bytes) }
                        values.clear(); values.put(MediaStore.Images.Media.IS_PENDING, 0)
                        resolver.update(uri, values, null, null)
                        result.success(true)
                    } catch (e: Exception) {
                        if (uri != null) resolver.delete(uri, null, null)
                        result.error("image", "Unable to save image", null)
                    }
                } else {
                    if (pendingImageResult != null) { result.error("busy", "Save already pending", null); return@setMethodCallHandler }
                    pendingImage = bytes; pendingImageResult = result
                    try {
                        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE); type = "image/png"; putExtra(Intent.EXTRA_TITLE, name)
                        }, 7144)
                    } catch (e: Exception) {
                        pendingImage = null; pendingImageResult = null
                        result.error("image", "Unable to open save dialog", null)
                    }
                }
            }
        adhkarControls = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.haqfoundation.haq_app/adhkar_controls")
        adhkarControls?.setMethodCallHandler { call, result ->
            if (call.method == "enable") {
                countWithVolumeKeys = call.arguments == true
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.haqfoundation.haq_app/storage")
            .setMethodCallHandler { call, result ->
                if (call.method == "diskSpace") {
                    val stats = StatFs(filesDir.absolutePath)
                    result.success(mapOf("total" to stats.totalBytes, "free" to stats.availableBytes))
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (countWithVolumeKeys && (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP || event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                adhkarControls?.invokeMethod("count", null)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onPause() {
        prayerDevice?.stopHeading()
        countWithVolumeKeys = false
        super.onPause()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        reminders?.capture(intent)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == HaqPrayerBridge.PERMISSION) prayerDevice?.permissionResult()
    }
    override fun onDestroy() {
        prayerDevice?.dispose()
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != 7144) { super.onActivityResult(requestCode, resultCode, data); return }
        val result = pendingImageResult ?: return
        val bytes = pendingImage
        pendingImageResult = null; pendingImage = null
        if (resultCode != Activity.RESULT_OK || data?.data == null || bytes == null) { result.success(false); return }
        try {
            val stream = contentResolver.openOutputStream(data.data!!) ?: throw IllegalStateException("Cannot write image")
            stream.use { it.write(bytes) }; result.success(true)
        } catch (e: Exception) { result.error("image", "Unable to save image", null) }
    }
}
