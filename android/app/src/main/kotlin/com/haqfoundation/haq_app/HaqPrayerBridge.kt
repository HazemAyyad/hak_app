package com.haqfoundation.haq_app

import android.Manifest
import android.content.*
import android.content.pm.PackageManager
import android.hardware.*
import android.location.*
import android.net.Uri
import android.os.*
import android.provider.Settings
import android.view.Surface
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/** Foreground-only location and real orientation readings. No background grant,
 * fake north, reverse geocoding, or location upload. */
class HaqPrayerBridge(private val activity: MainActivity, channel: MethodChannel, events: EventChannel) : SensorEventListener {
    companion object { const val PERMISSION = 7351 }
    private val locations = activity.getSystemService(LocationManager::class.java)
    private val sensors = activity.getSystemService(SensorManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var requestRevision = 0L
    private var cancellation: CancellationSignal? = null
    private var listener: LocationListener? = null
    private var sink: EventChannel.EventSink? = null
    private var declination = 0f
    private var accuracy = SensorManager.SENSOR_STATUS_UNRELIABLE
    private var useVector = false
    private var gravity: FloatArray? = null
    private var magnetic: FloatArray? = null
    private var lastEmit = 0L
    private val timeout = Runnable { finishError("timeout", "No recent location available") }
    private fun permission() = activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
        activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    private fun enabled() = locations.isProviderEnabled(LocationManager.GPS_PROVIDER) || locations.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(mapOf("permission" to permission(), "enabled" to enabled(),
                        "zone" to TimeZone.getDefault().id,
                        "heading" to (sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR) != null ||
                            (sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null && sensors.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD) != null))))
                    "requestLocation" -> {
                        if (pending != null) { result.error("busy", "Location request pending", null); return@setMethodCallHandler }
                        pending = result
                        requestRevision++
                        handler.postDelayed(timeout, 30000)
                        if (!permission()) activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), PERMISSION)
                        else locate()
                    }
                    "settings" -> { activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}"))); result.success(null) }
                    "openMap" -> {
                        val uri = Uri.parse(call.arguments as String)
                        require(uri.scheme == "https" && uri.host == "www.openstreetmap.org")
                        activity.startActivity(Intent(Intent.ACTION_VIEW, uri)); result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                if (call.method == "requestLocation") finishError("location", "Location unavailable")
                else result.error("device", "Device operation unavailable", null)
            }
        }
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                stopHeading(); sink = events
                try {
                    val args = arguments as Map<*, *>
                    val lat = (args["lat"] as Number).toDouble(); val lng = (args["lng"] as Number).toDouble()
                    require(lat.isFinite() && lng.isFinite() && lat in -90.0..90.0 && lng in -180.0..180.0)
                    declination = GeomagneticField(lat.toFloat(), lng.toFloat(), 0f, System.currentTimeMillis()).declination
                    val vector = sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
                    useVector = vector != null
                    if (vector != null) {
                        if (!sensors.registerListener(this@HaqPrayerBridge, vector, SensorManager.SENSOR_DELAY_UI)) throw IllegalStateException()
                    } else {
                        val a = sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: throw IllegalStateException()
                        val m = sensors.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD) ?: throw IllegalStateException()
                        if (!sensors.registerListener(this@HaqPrayerBridge, a, SensorManager.SENSOR_DELAY_UI) ||
                            !sensors.registerListener(this@HaqPrayerBridge, m, SensorManager.SENSOR_DELAY_UI)) throw IllegalStateException()
                    }
                } catch (_: Exception) { events.error("sensor", "Heading sensor unavailable", null); stopHeading() }
            }
            override fun onCancel(arguments: Any?) { stopHeading() }
        })
    }
    fun permissionResult() { if (pending != null) { if (permission()) locate() else finishError("denied", "Location permission denied") } }
    private fun locate() {
        val revision = requestRevision
        try {
            if (!enabled()) { finishError("disabled", "Location services disabled"); return }
            val fine = activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            val provider = if (fine && locations.isProviderEnabled(LocationManager.GPS_PROVIDER)) LocationManager.GPS_PROVIDER
                else if (locations.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) LocationManager.NETWORK_PROVIDER
                else { finishError("disabled", "Network location unavailable"); return }
            if (Build.VERSION.SDK_INT >= 30) {
                val signal = CancellationSignal(); cancellation = signal
                locations.getCurrentLocation(provider, signal, activity.mainExecutor) { location -> if (revision == requestRevision) accept(location) }
            } else {
                val callback = object : LocationListener {
                    override fun onLocationChanged(location: Location) { if (revision == requestRevision) accept(location) }
                    override fun onProviderDisabled(provider: String) { if (revision == requestRevision) finishError("disabled", "Location services disabled") }
                    override fun onProviderEnabled(provider: String) {}
                    @Deprecated("Legacy location callback")
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                }
                listener = callback
                locations.requestSingleUpdate(provider, callback, Looper.getMainLooper())
            }
        } catch (_: SecurityException) { finishError("denied", "Location permission denied") }
        catch (_: Exception) { finishError("location", "Location unavailable") }
    }
    private fun accept(location: Location?) {
        val result = pending ?: return
        if (location == null || !location.hasAccuracy() || location.accuracy > 5000 ||
            SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos > 300000000000L) {
            finishError("stale", "No accurate recent location"); return
        }
        pending = null; requestRevision++; cleanupLocation()
        result.success(mapOf("lat" to location.latitude, "lng" to location.longitude, "accuracy" to location.accuracy.toDouble(),
            "measured" to location.time, "zone" to TimeZone.getDefault().id))
    }
    private fun cleanupLocation() {
        handler.removeCallbacks(timeout); cancellation?.cancel(); cancellation = null
        listener?.let { locations.removeUpdates(it) }; listener = null
    }
    private fun finishError(code: String, message: String) {
        val result = pending; pending = null; requestRevision++; cleanupLocation(); result?.error(code, message, null)
    }
    fun stopHeading() {
        sensors.unregisterListener(this); sink = null; gravity = null; magnetic = null
        accuracy = SensorManager.SENSOR_STATUS_UNRELIABLE; lastEmit = 0
    }
    fun dispose() { stopHeading(); finishError("cancelled", "Activity closed") }
    override fun onAccuracyChanged(sensor: Sensor?, value: Int) {
        if (sensor?.type == Sensor.TYPE_MAGNETIC_FIELD || sensor?.type == Sensor.TYPE_ROTATION_VECTOR) accuracy = value
    }
    override fun onSensorChanged(event: SensorEvent) {
        if (sink == null) return
        if (SystemClock.elapsedRealtimeNanos() - event.timestamp > 5000000000L) return
        val matrix = FloatArray(9)
        if (useVector) { SensorManager.getRotationMatrixFromVector(matrix, event.values); accuracy = event.accuracy }
        else {
            if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) gravity = event.values.clone()
            if (event.sensor.type == Sensor.TYPE_MAGNETIC_FIELD) { magnetic = event.values.clone(); accuracy = event.accuracy }
            val a = gravity ?: return; val m = magnetic ?: return
            if (!SensorManager.getRotationMatrix(matrix, null, a, m)) return
        }
        val now = SystemClock.elapsedRealtime()
        if (now - lastEmit < 100) return
        lastEmit = now
        @Suppress("DEPRECATION") val rotation = activity.windowManager.defaultDisplay.rotation
        val axes = when (rotation) {
            Surface.ROTATION_90 -> Pair(SensorManager.AXIS_Y, SensorManager.AXIS_MINUS_X)
            Surface.ROTATION_180 -> Pair(SensorManager.AXIS_MINUS_X, SensorManager.AXIS_MINUS_Y)
            Surface.ROTATION_270 -> Pair(SensorManager.AXIS_MINUS_Y, SensorManager.AXIS_X)
            else -> Pair(SensorManager.AXIS_X, SensorManager.AXIS_Y)
        }
        val display = FloatArray(9)
        if (!SensorManager.remapCoordinateSystem(matrix, axes.first, axes.second, display)) return
        val angles = SensorManager.getOrientation(display, FloatArray(3))
        val degrees = ((Math.toDegrees(angles[0].toDouble()) + declination) % 360 + 360) % 360
        sink?.success(mapOf("degrees" to degrees, "accuracy" to accuracy, "trueNorth" to true))
    }
}
