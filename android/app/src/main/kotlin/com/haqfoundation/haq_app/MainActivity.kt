package com.haqfoundation.haq_app

import com.ryanheise.audioservice.AudioServiceActivity
import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}
