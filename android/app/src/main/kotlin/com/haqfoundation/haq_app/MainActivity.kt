package com.haqfoundation.haq_app

import com.ryanheise.audioservice.AudioServiceActivity
import android.os.StatFs
import android.view.KeyEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var adhkarControls: MethodChannel? = null
    private var countWithVolumeKeys = false
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        countWithVolumeKeys = false
        super.onPause()
    }
}
