package com.haqfoundation.haq_app

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.database.ContentObserver
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.WindowManager.LayoutParams
import java.io.File
import android.os.*
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.*
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale
import java.util.UUID

/** Persisted native plan survives the Flutter process and device reboot. No
 * optional prayer exact alarms require explicit special access. */
object HaqReminders {
    private const val PREF = "haq_reminders_v1"
    private const val ROOT = "haq-reminder"
    const val NOTIFICATION_PERMISSION = 7248
    fun prefs(c: Context) = c.getSharedPreferences(PREF, Context.MODE_PRIVATE)
    fun plan(c: Context) = JSONObject(prefs(c).getString("plan", "{}") ?: "{}")
    fun jobs(p: JSONObject): List<JSONObject> {
        val values = p.optJSONArray("jobs") ?: JSONArray()
        return (0 until values.length()).map { values.getJSONObject(it) }
    }
    fun allowed(c: Context): Boolean = (Build.VERSION.SDK_INT < 33 ||
        c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
        (Build.VERSION.SDK_INT < 24 || c.getSystemService(NotificationManager::class.java).areNotificationsEnabled())
    fun channels(c: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = c.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("haq_reminders_sound", "تذكيرات حق", NotificationManager.IMPORTANCE_DEFAULT))
        manager.createNotificationChannel(NotificationChannel("haq_reminders_silent", "تذكيرات حق الصامتة", NotificationManager.IMPORTANCE_LOW).apply { setSound(null, null); enableVibration(false) })
        manager.createNotificationChannel(NotificationChannel("haq_overlay", "التنبيه العائم", NotificationManager.IMPORTANCE_LOW).apply { setSound(null, null) })
        manager.createNotificationChannel(NotificationChannel("haq_prayer_vibration", "تنبيه الصلاة بالاهتزاز", NotificationManager.IMPORTANCE_DEFAULT).apply { setSound(null, null); enableVibration(true); vibrationPattern = longArrayOf(0, 350, 150, 350) })
        manager.createNotificationChannel(NotificationChannel("haq_adhan_playback", "الأذان", NotificationManager.IMPORTANCE_HIGH).apply { setSound(null, null); enableVibration(false) })
        manager.createNotificationChannel(NotificationChannel("haq_community_push", "رسائل حق العامة", NotificationManager.IMPORTANCE_DEFAULT).apply { setSound(null, null); enableVibration(false) })
    }
    fun status(c: Context): Map<String, Any> {
        channels(c)
        return mapOf("platform" to "android", "allowed" to allowed(c),
            "overlay" to Settings.canDrawOverlays(c), "overlayRunning" to (HaqOverlayService.current != null),
            "pending" to jobs(plan(c)).size, "speech" to true,
            "failed" to prefs(c).getBoolean("scheduleError", false))
    }
    private fun intent(c: Context, id: String, action: String = "fire") = Intent(c, HaqReminderReceiver::class.java).apply {
        this.action = action; data = Uri.parse("$ROOT://job/${Uri.encode(id)}"); putExtra("id", id)
        putExtra("revision", plan(c).optString("revision"))
    }
    private fun pending(c: Context, id: String, action: String = "fire") = PendingIntent.getBroadcast(c, 0,
        intent(c, id, action), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun open(c: Context, route: String, scope: String): PendingIntent = PendingIntent.getActivity(c, 0,
        Intent(c, MainActivity::class.java).apply {
            action = "haq.open"; data = Uri.parse("$ROOT://open/${Uri.encode(scope)}/${Uri.encode(route)}")
            putExtra("haqRoute", route); putExtra("haqScope", scope)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun cancel(c: Context, p: JSONObject) {
        c.stopService(Intent(c, HaqAdhanService::class.java))
        val alarms = c.getSystemService(AlarmManager::class.java)
        for (job in jobs(p)) {
            val id = job.getString("id")
            alarms.cancel(pending(c, id)); alarms.cancel(pending(c, id, "snoozed"))
        }
        // Namespace only: never cancel audio-service or other module notices.
        if (Build.VERSION.SDK_INT >= 23) {
            val manager = c.getSystemService(NotificationManager::class.java)
            manager.activeNotifications.filter { it.tag?.startsWith(ROOT) == true }.forEach { manager.cancel(it.tag, it.id) }
        }
    }
    fun changeScope(c: Context, scope: String) {
        val old = plan(c)
        if (old.optString("scope") == scope) return
        cancel(c, old); c.stopService(Intent(c, HaqOverlayService::class.java))
        check(prefs(c).edit().putString("plan", JSONObject().put("scope", scope).put("jobs", JSONArray()).toString())
            .remove("index").remove("snoozes").commit())
    }
    fun replace(c: Context, next: JSONObject) {
        require(next.getJSONArray("jobs").length() <= 512)
        val old = plan(c)
        if (old.optString("signature").isNotEmpty() && old.optString("signature") == next.optString("signature")) {
            restore(c); return
        }
        cancel(c, old)
        next.put("revision", UUID.randomUUID().toString())
        check(prefs(c).edit().putString("plan", next.toString()).remove("snoozes").putBoolean("scheduleError", false).commit())
        if (!hasOverlay(next)) c.stopService(Intent(c, HaqOverlayService::class.java))
        HaqOverlayService.current?.reload()
        restore(c)
    }
    fun hasOverlay(p: JSONObject) = p.optString("type") == "overlay" && jobs(p).any { it.has("interval") }
    fun next(job: JSONObject, after: Long): Long? {
        if (job.has("at")) return job.getLong("at").takeIf { it > after }
        if (job.has("interval")) return after + job.getInt("interval").coerceIn(1, 300) * 60000L
        val cal = Calendar.getInstance().apply {
            timeInMillis = after
            set(Calendar.HOUR_OF_DAY, job.getInt("minute") / 60)
            set(Calendar.MINUTE, job.getInt("minute") % 60)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        if (cal.timeInMillis <= after) cal.add(Calendar.DATE, 1)
        // Calendar.DATE preserves wall-clock time through timezone/DST changes.
        for (i in 0..3660) {
            val day = String.format(Locale.US, "%04d-%02d-%02d", cal.get(Calendar.YEAR), cal.get(Calendar.MONTH)+1, cal.get(Calendar.DATE))
            if (job.has("end") && day > job.getString("end")) return null
            val weekday = (cal.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
            if ((!job.has("start") || day >= job.getString("start")) &&
                (!job.has("weekday") || weekday == job.getInt("weekday"))) return cal.timeInMillis
            cal.add(Calendar.DATE, 1)
        }
        return null
    }
    private fun schedule(c: Context, job: JSONObject, at: Long, action: String = "fire") {
        val alarms = c.getSystemService(AlarmManager::class.java)
        val exact = job.getString("id").contains(":prayer:") && (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms())
        // Only user-selected prayer alerts can start the audible FGS from an
        // exact alarm. General reminders retain the existing inexact plan.
        if (exact) alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(c, job.getString("id"), action))
        else alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(c, job.getString("id"), action))
    }
    fun restore(c: Context) {
        channels(c)
        val p = plan(c)
        for (job in jobs(p)) {
            if (job.has("interval") && hasOverlay(p) && HaqOverlayService.current != null) {
                c.getSystemService(AlarmManager::class.java).cancel(pending(c, job.getString("id")))
                continue
            }
            next(job, System.currentTimeMillis())?.let { schedule(c, job, it) }
        }
        val snoozes = JSONObject(prefs(c).getString("snoozes", "{}") ?: "{}")
        for (job in jobs(p)) {
            val at = snoozes.optLong(job.getString("id"), 0)
            if (at > System.currentTimeMillis()) schedule(c, job, at, "snoozed")
        }
        prefs(c).edit().putBoolean("scheduleError", false).apply()
    }
    fun body(c: Context, job: JSONObject): String {
        if (!job.has("interval")) return job.optString("body")
        val p = plan(c); val items = p.optJSONArray("smartItems") ?: return ""
        if (items.length() == 0) return ""
        val index = if (p.optBoolean("ordered", true)) prefs(c).getInt("index", 0).coerceAtLeast(0) % items.length()
                    else (0 until items.length()).random()
        prefs(c).edit().putInt("index", (index + 1) % items.length()).apply()
        return items.getString(index)
    }
    fun show(c: Context, job: JSONObject) {
        if (!allowed(c)) return
        val p = plan(c); val body = body(c, job)
        if (body.isBlank()) return
        val mode = job.optString("alertMode")
        val sound = (job.has("alertMode") || p.optBoolean("sound", true)) && mode !in listOf("vibration", "silent")
        val channelId = if (mode == "vibration") "haq_prayer_vibration" else if (sound) "haq_reminders_sound" else "haq_reminders_silent"
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, channelId) else Notification.Builder(c)
        builder.setSmallIcon(R.drawable.ic_haq_reminder).setContentTitle(job.getString("title")).setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body)).setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE).setCategory(Notification.CATEGORY_REMINDER)
            .setContentIntent(open(c, job.getString("route"), p.optString("scope")))
            .addAction(Notification.Action.Builder(null, "تأجيل ${p.optInt("snooze", 10)} د", pending(c, job.getString("id"), "snooze")).build())
        if (Build.VERSION.SDK_INT < 26) {
            if (sound) builder.setDefaults(Notification.DEFAULT_SOUND)
            else if (mode == "vibration") builder.setVibrate(longArrayOf(0, 350, 150, 350))
        }
        c.getSystemService(NotificationManager::class.java).notify("$ROOT:${job.getString("id")}", 0, builder.build())
    }
    fun communityMessage(c: Context, scope: String, id: Int, sound: Boolean): Boolean {
        if (!allowed(c) || plan(c).optString("scope") != scope) return false
        channels(c)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c,
            if (sound) "haq_reminders_sound" else "haq_reminders_silent") else Notification.Builder(c)
        builder.setSmallIcon(R.drawable.ic_haq_reminder).setContentTitle("رسائل حق")
            .setContentText("وصل محتوى جديد إلى رسائل حق").setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE).setContentIntent(open(c, "messages", scope))
        if (Build.VERSION.SDK_INT < 26 && sound) builder.setDefaults(Notification.DEFAULT_SOUND)
        c.getSystemService(NotificationManager::class.java).notify("$ROOT:community", 0, builder.build())
        return true
    }
    fun receive(c: Context, event: Intent) {
        if (event.action in listOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)) {
            if (plan(c).optBoolean("startup", true) || event.action != Intent.ACTION_BOOT_COMPLETED) restore(c)
            return
        }
        val p = plan(c)
        if (event.getStringExtra("revision") != p.optString("revision")) return
        val job = jobs(p).find { it.getString("id") == event.getStringExtra("id") } ?: return
        if (job.has("at") && System.currentTimeMillis() - job.getLong("at") > 7200000L) return
        val today = java.text.SimpleDateFormat("yyyy-MM-dd", Locale.US).format(java.util.Date())
        if (job.has("end") && today > job.getString("end")) return
        if (event.action == "snooze") {
            val at = System.currentTimeMillis() + p.optInt("snooze", 10).coerceIn(10, 60) * 60000L
            val saved = JSONObject(prefs(c).getString("snoozes", "{}") ?: "{}").put(job.getString("id"), at)
            if (prefs(c).edit().putString("snoozes", saved.toString()).commit()) schedule(c, job, at, "snoozed")
            c.getSystemService(NotificationManager::class.java).cancel("$ROOT:${job.getString("id")}", 0)
        } else {
            val timely = job.has("at") && System.currentTimeMillis() - job.getLong("at") in 0..120000
            val exact = Build.VERSION.SDK_INT < 31 || c.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
            val adhan = event.action == "fire" && timely && exact && allowed(c) && job.optString("alertMode") in listOf("adhan", "reminderVoice")
            if (adhan) {
                try {
                    val launch = Intent(c, HaqAdhanService::class.java).putExtra("id", job.getString("id")).putExtra("revision", p.optString("revision"))
                    if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(launch) else c.startService(launch)
                } catch (_: Exception) { show(c, job); prefs(c).edit().putBoolean("scheduleError", true).apply() }
            } else show(c, job)
            if (event.action == "fire") next(job, System.currentTimeMillis())?.let { schedule(c, job, it) }
            else {
                val saved = JSONObject(prefs(c).getString("snoozes", "{}") ?: "{}")
                saved.remove(job.getString("id")); prefs(c).edit().putString("snoozes", saved.toString()).apply()
            }
        }
    }
}

/** No network, arbitrary file path or religious text in the alarm intent.
 * A persisted current plan is revalidated before the downloaded audio starts. */
object HaqAdhanRules {
    fun voiceId(id: String) = id in listOf("alafasy", "nafees", "mustafa", "zahrani") || Regex("archive-[0-9a-f]{16}").matches(id)
    fun reminderId(id: String) = Regex("reminder-[0-9a-f]{16}-(fajr|dhuhr|asr|maghrib|isha)").matches(id)
    fun playbackId(id: String) = voiceId(id) || reminderId(id)
    fun targetVolume(maximum: Int, percent: Int) = kotlin.math.ceil(maximum * percent.coerceIn(0, 100) / 100.0).toInt()
    fun timely(at: Long, now: Long) = now >= at && now - at <= 120000
    fun faceDown(x: Float, y: Float, z: Float) = z < -7f && kotlin.math.abs(x) < 6f && kotlin.math.abs(y) < 6f
}

class HaqAdhanService : Service(), SensorEventListener {
    companion object {
        const val ID = 7401
        var current: HaqAdhanService? = null; private set
        fun stop(c: Context) { c.stopService(Intent(c, HaqAdhanService::class.java)) }
    }
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var focus: AudioFocusRequest? = null
    private var sensor: SensorManager? = null
    private var volume: ContentObserver? = null
    private var originalVolume = -1
    private var playbackVolume = -1
    private var originalMusicVolume = -1
    private var legacyFocus: AudioManager.OnAudioFocusChangeListener? = null
    private var activeId: String? = null
    private var faceDownSince = 0L
    private var registered = false
    private var wake: PowerManager.WakeLock? = null
    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) { if (intent.action == Intent.ACTION_SCREEN_OFF) stopSelf() }
    }
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") { stopSelf(); return START_NOT_STICKY }
        if (activeId != null) return START_NOT_STICKY // Preserve the active playback and its volume ownership.
        val p = HaqReminders.plan(this)
        val job = HaqReminders.jobs(p).find { it.optString("id") == intent?.getStringExtra("id") }
        val valid = job != null && intent?.getStringExtra("revision") == p.optString("revision") &&
            job.optString("alertMode") in listOf("adhan", "reminderVoice") &&
            HaqAdhanRules.timely(job.optLong("at"), System.currentTimeMillis()) && HaqReminders.allowed(this)
        if (!valid) { stopSelf(); return START_NOT_STICKY }
        val voice = job!!.optString("voice")
        if (!HaqAdhanRules.playbackId(voice)) { stopSelf(); return START_NOT_STICKY }
        val audio = File(filesDir, "adhan/$voice.mp3")
        if (!audio.isFile) { HaqReminders.show(this, job); stopSelf(); return START_NOT_STICKY }
        val receipt = job.getString("id") + ":" + p.optString("revision")
        if (HaqReminders.prefs(this).getString("lastAdhan", null) == receipt) { stopSelf(); return START_NOT_STICKY }
        if (!HaqReminders.prefs(this).edit().putString("lastAdhan", receipt).commit()) { stopSelf(); return START_NOT_STICKY }
        activeId = job.getString("id")
        current = this
        HaqReminders.channels(this)
        val humanReminder = job.optString("alertMode") == "reminderVoice"
        val launch = Intent(this, HaqAdhanActivity::class.java).putExtra("title", job.optString("title"))
            .putExtra("at", job.optLong("at")).putExtra("iqamaMinutes", job.optInt("iqamaMinutes", 15))
            .putExtra("scope", p.optString("scope"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val screen = PendingIntent.getActivity(this, ID, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, ID, Intent(this, HaqAdhanService::class.java).setAction("stop"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "haq_adhan_playback") else Notification.Builder(this)
        builder.setSmallIcon(R.drawable.ic_haq_reminder).setContentTitle(job.optString("title"))
            .setContentText("المس للإيقاف، أو اقلب الهاتف على وجهه")
            .setCategory(Notification.CATEGORY_ALARM).setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true).setContentIntent(if (humanReminder) HaqReminders.open(this, "prayer", p.optString("scope")) else screen).setDeleteIntent(stop)
            .addAction(Notification.Action.Builder(null, "إيقاف الأذان", stop).build())
        if (Build.VERSION.SDK_INT < 26) builder.setPriority(Notification.PRIORITY_HIGH)
        if (!humanReminder && job.optBoolean("showAdhanScreen", true) && (Build.VERSION.SDK_INT < 34 || getSystemService(NotificationManager::class.java).canUseFullScreenIntent())) {
            builder.setFullScreenIntent(screen, true)
        }
        try {
            startForeground(ID, builder.build())
            player?.release()
            val audioManager = getSystemService(AudioManager::class.java)
            val attrs = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
            val listener = AudioManager.OnAudioFocusChangeListener { change -> if (change <= 0) stopSelf() }
            legacyFocus = listener
            val granted = if (Build.VERSION.SDK_INT >= 26) {
                focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attrs)
                    .setOnAudioFocusChangeListener(listener).build()
                audioManager.requestAudioFocus(focus!!)
            } else audioManager.requestAudioFocus(listener, AudioManager.STREAM_ALARM, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            if (granted != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { stopSelf(); return START_NOT_STICKY }
            wake = (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "haq:adhan").apply { acquire(360000) }
            sensor = getSystemService(SENSOR_SERVICE) as SensorManager
            sensor?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let { sensor?.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
            originalVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
            var managedVolume = false
            if (!humanReminder && !audioManager.isVolumeFixed && getSystemService(NotificationManager::class.java).currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_ALL) {
                try { audioManager.setStreamVolume(AudioManager.STREAM_ALARM,
                    HaqAdhanRules.targetVolume(audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM), job.optInt("volume", 100)), 0); managedVolume = true } catch (_: SecurityException) { }
            }
            playbackVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
            originalMusicVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            volume = object : ContentObserver(handler) {
                override fun onChange(selfChange: Boolean) {
                    val now = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
                    if (now != playbackVolume || audioManager.getStreamVolume(AudioManager.STREAM_MUSIC) != originalMusicVolume) stopSelf()
                }
            }.also { contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, it) }
            if (!registered) {
                if (Build.VERSION.SDK_INT >= 33) registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF), RECEIVER_NOT_EXPORTED)
                else registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
                registered = true
            }
            player = MediaPlayer().apply {
                setAudioAttributes(attrs)
                val gain = if (humanReminder || managedVolume) 1f else job.optInt("volume",100).coerceIn(0,100)/100f
                setVolume(gain, gain)
                setDataSource(audio.path)
                setOnCompletionListener { stopSelf() }
                setOnErrorListener { _, _, _ -> stopSelf(); true }
                setOnPreparedListener { it.start() }
                prepareAsync()
            }
            handler.postDelayed({ stopSelf() }, if (humanReminder) 30000 else if (job.optBoolean("fullAdhan")) 360000 else 25000)
        } catch (_: Exception) { HaqReminders.prefs(this).edit().putBoolean("scheduleError", true).apply(); stopSelf() }
        return START_NOT_STICKY
    }
    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
        val down = HaqAdhanRules.faceDown(event.values[0], event.values[1], event.values[2])
        if (!down) { faceDownSince = 0; return }
        val now = SystemClock.elapsedRealtime()
        if (faceDownSince == 0L) faceDownSince = now
        if (now - faceDownSince >= 450) stopSelf()
    }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        sensor?.unregisterListener(this)
        volume?.let { contentResolver.unregisterContentObserver(it) }
        val audioManager = getSystemService(AudioManager::class.java)
        if (originalVolume >= 0 && playbackVolume >= 0 && audioManager.getStreamVolume(AudioManager.STREAM_ALARM) == playbackVolume) {
            try { audioManager.setStreamVolume(AudioManager.STREAM_ALARM, originalVolume, 0) } catch (_: SecurityException) { }
        }
        if (registered) unregisterReceiver(screenOff)
        player?.release(); player = null
        if (Build.VERSION.SDK_INT >= 26) focus?.let { getSystemService(AudioManager::class.java).abandonAudioFocusRequest(it) }
        else legacyFocus?.let { getSystemService(AudioManager::class.java).abandonAudioFocus(it) }
        if (wake?.isHeld == true) wake?.release()
        current = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}

/** System-owned full-screen alarm surface: never overlays other apps through
 * SYSTEM_ALERT_WINDOW and never dismisses the user's keyguard. */
class HaqAdhanActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private var shown = false
    private var touched = false
    private var frame = 0
    private lateinit var photo: ImageView
    private lateinit var countdown: TextView
    private lateinit var brandFont: Typeface
    private val scenes = listOf("assets/home/dawn.png", "assets/religious/hands.png", "assets/religious/madina.png")
    private var deadline = 0L
    private val clock = object : Runnable {
        override fun run() {
            if (HaqAdhanService.current == null && !touched) { finish(); return }
            val remaining = ((deadline - System.currentTimeMillis()) / 1000).coerceAtLeast(0)
            countdown.text = if (remaining > 0) "الإقامة بعد\n%02d:%02d".format(remaining / 60, remaining % 60) else "حان وقت الصلاة"
            handler.postDelayed(this, 1000)
        }
    }
    private val backgrounds = object : Runnable {
        override fun run() {
            frame++
            photo.animate().alpha(.35f).setDuration(500).withEndAction {
                loadScene()
                photo.animate().alpha(1f).setDuration(850).start()
            }.start()
            handler.postDelayed(this, 5000)
        }
    }
    private fun dp(n: Int) = (n * resources.displayMetrics.density).toInt()
    private fun loadScene() {
        try { assets.open("flutter_assets/" + scenes[frame % scenes.size]).use { photo.setImageDrawable(android.graphics.drawable.Drawable.createFromStream(it, null)) } }
        catch (_: Exception) { photo.setBackgroundColor(Color.rgb(16,42,67)) }
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        if (HaqAdhanService.current == null) { finish(); return }
        window.addFlags(LayoutParams.FLAG_SHOW_WHEN_LOCKED or LayoutParams.FLAG_TURN_SCREEN_ON or LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(true); setTurnScreenOn(true) }
        val navy = Color.rgb(16,42,67); val teal = Color.rgb(42,140,130); val gold = Color.rgb(199,164,90)
        brandFont = try { Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/Cairo.ttf") } catch (_: Exception) { Typeface.DEFAULT }
        deadline = intent.getLongExtra("at", System.currentTimeMillis()) + intent.getIntExtra("iqamaMinutes",15).coerceIn(0,60) * 60000L
        val root = FrameLayout(this).apply { setBackgroundColor(navy); layoutDirection = View.LAYOUT_DIRECTION_RTL }
        photo = ImageView(this).apply { scaleType = ImageView.ScaleType.CENTER_CROP }
        root.addView(photo, FrameLayout.LayoutParams(-1,-1)); loadScene()
        root.addView(View(this).apply { background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(Color.argb(130,11,23,34),Color.argb(20,11,23,34),Color.argb(235,11,23,34))) }, FrameLayout.LayoutParams(-1,-1))
        fun text(value:String,size:Float,color:Int=Color.WHITE) = TextView(this).apply {
            this.text=value; textSize=size; typeface=brandFont; setTextColor(color); gravity=Gravity.CENTER; setPadding(dp(8),dp(8),dp(8),dp(8))
        }
        val content = LinearLayout(this).apply { orientation=LinearLayout.VERTICAL; gravity=Gravity.CENTER_HORIZONTAL; setPadding(dp(20),dp(24),dp(20),dp(24)) }
        val header=LinearLayout(this).apply { gravity=Gravity.CENTER_VERTICAL }
        val close=Button(this).apply { text="×"; contentDescription="إيقاف الأذان"; setTextColor(Color.WHITE); setBackgroundColor(Color.TRANSPARENT); setOnClickListener { stop() } }
        header.addView(close,LinearLayout.LayoutParams(dp(48),dp(48)))
        header.addView(text("حق · نداء الصلاة",18f),LinearLayout.LayoutParams(0,dp(52),1f))
        header.addView(Button(this).apply { text="⚙"; contentDescription="إعدادات الأذان"; setTextColor(Color.WHITE); setBackgroundColor(Color.TRANSPARENT); setOnClickListener { open("prayer-settings") } },LinearLayout.LayoutParams(dp(48),dp(48)))
        content.addView(header,LinearLayout.LayoutParams(-1,dp(52)))
        content.addView(text(intent.getStringExtra("title") ?: "حان وقت الصلاة",25f,gold))
        val logo = ImageView(this).apply {
            scaleType=ImageView.ScaleType.FIT_CENTER; contentDescription="شعار حق"; setPadding(dp(12),dp(12),dp(12),dp(12))
            background=GradientDrawable().apply { shape=GradientDrawable.OVAL; setColor(Color.rgb(247,244,237)); setStroke(dp(1),gold) }
        }
        try { assets.open("flutter_assets/assets/branding/haq_logo_transparent.png").use { logo.setImageDrawable(android.graphics.drawable.Drawable.createFromStream(it,null)) } } catch (_:Exception) { }
        content.addView(logo,LinearLayout.LayoutParams(dp(84),dp(84)))
        content.addView(text("الله أكبر",44f))
        content.addView(Space(this),LinearLayout.LayoutParams(1,0,1f))
        countdown=text("",24f).apply {
            gravity=Gravity.CENTER
            background=GradientDrawable().apply { shape=GradientDrawable.OVAL; setColor(Color.argb(205,12,75,76)); setStroke(dp(2),gold) }
        }
        if(intent.getIntExtra("iqamaMinutes",15)>0) {
            content.addView(countdown,LinearLayout.LayoutParams(dp(164),dp(164)).apply { bottomMargin=dp(18) })
            content.addView(text("مدة الإقامة حسب إعدادك",11f,Color.LTGRAY))
        }
        fun button(title:String, route:String?, filled:Boolean):Button = Button(this).apply {
            text=title; typeface=brandFont; textSize=16f; isAllCaps=false; setTextColor(Color.WHITE)
            background=GradientDrawable().apply { cornerRadius=dp(18).toFloat(); setColor(if(filled)teal else Color.argb(60,16,42,67)); setStroke(dp(1),if(filled)teal else gold) }
            setOnClickListener { if(route==null)stop() else open(route) }
        }
        content.addView(button("أذكار الصلاة","adhkar",true),LinearLayout.LayoutParams(-1,dp(54)).apply{ bottomMargin=dp(10) })
        val shortcuts=LinearLayout(this)
        shortcuts.addView(button("القرآن","quran",false),LinearLayout.LayoutParams(0,dp(50),1f).apply{ marginEnd=dp(6) })
        shortcuts.addView(button("القبلة","qibla",false),LinearLayout.LayoutParams(0,dp(50),1f).apply{ marginStart=dp(6) })
        content.addView(shortcuts,LinearLayout.LayoutParams(-1,dp(50)))
        content.addView(text("المس الشاشة أو اقلب الهاتف لإيقاف الأذان",11f,Color.LTGRAY))
        val scroll = ScrollView(this).apply { isFillViewport=true; clipToPadding=false; setPadding(0,dp(8),0,dp(16)) }
        scroll.addView(content,FrameLayout.LayoutParams(-1,-2))
        root.addView(scroll,FrameLayout.LayoutParams(-1,-1)); setContentView(root)
        shown=true; handler.post(clock); handler.postDelayed(backgrounds,5000)
    }
    private fun open(route:String) {
        HaqAdhanService.stop(this)
        try { HaqReminders.open(this,route,intent.getStringExtra("scope") ?: "guest").send() } catch(_:Exception) {}
        finish()
    }
    private fun stop() { HaqAdhanService.stop(this); finish() }
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if(shown && event.action==MotionEvent.ACTION_DOWN) { touched=true; HaqAdhanService.stop(this) }
        val consumed=super.dispatchTouchEvent(event)
        if(shown && event.action in listOf(MotionEvent.ACTION_UP,MotionEvent.ACTION_CANCEL)) handler.postDelayed({if(!isFinishing)finish()},120)
        return consumed
    }
    override fun dispatchKeyEvent(event: KeyEvent): Boolean { if(event.action==KeyEvent.ACTION_DOWN)stop();return true }
    @Deprecated("Deprecated in Android") override fun onBackPressed() { stop() }
    override fun onUserLeaveHint() { super.onUserLeaveHint();stop() }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null);if(::photo.isInitialized)photo.animate().cancel();super.onDestroy() }
}

class HaqReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try { HaqReminders.receive(context, intent) } catch (_: Exception) {
            HaqReminders.prefs(context).edit().putBoolean("scheduleError", true).apply()
        }
    }
}

/** Explicitly started while the activity is visible, with a persistent Stop
 * action. Never starts itself on boot or from an alarm/background receiver. */
class HaqOverlayService : Service(), TextToSpeech.OnInitListener {
    companion object { var current: HaqOverlayService? = null; private set }
    private val handler = Handler(Looper.getMainLooper())
    private var view: View? = null
    private var speaker: TextToSpeech? = null
    private var speechReady = false
    private var queuedSpeech: String? = null
    private var nextAt = 0L
    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) { removeCard() }
    }
    private val tick = object : Runnable {
        override fun run() {
            val p = HaqReminders.plan(this@HaqOverlayService)
            if (!HaqReminders.hasOverlay(p) || !Settings.canDrawOverlays(this@HaqOverlayService) || !HaqReminders.allowed(this@HaqOverlayService)) { stopSelf(); return }
            if (SystemClock.elapsedRealtime() >= nextAt) {
                val job = HaqReminders.jobs(p).find { it.has("interval") } ?: return
                showCard(HaqReminders.body(this@HaqOverlayService, job), p)
                nextAt = SystemClock.elapsedRealtime() + job.getInt("interval").coerceIn(1, 300) * 60000L
            }
            handler.postDelayed(this, 1500)
        }
    }
    override fun onBind(intent: Intent?) = null
    override fun onCreate() {
        super.onCreate(); current = this
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF), Context.RECEIVER_NOT_EXPORTED)
        else registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") { stopSelf(); return START_NOT_STICKY }
        if (!Settings.canDrawOverlays(this) || !HaqReminders.allowed(this) || !HaqReminders.hasOverlay(HaqReminders.plan(this))) { stopSelf(); return START_NOT_STICKY }
        HaqReminders.channels(this)
        val stop = PendingIntent.getService(this, 0, Intent(this, HaqOverlayService::class.java).setAction("stop"), PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "haq_overlay") else Notification.Builder(this)
        startForeground(7249, builder.setSmallIcon(R.drawable.ic_haq_reminder).setContentTitle("تذكيرات حق العائمة تعمل")
            .setContentText("اضغط إيقاف لإنهاء الظهور فوق التطبيقات").setOngoing(true)
            .addAction(Notification.Action.Builder(null, "إيقاف", stop).build()).build())
        reload(); HaqReminders.restore(this)
        return START_NOT_STICKY
    }
    fun reload() {
        handler.removeCallbacksAndMessages(null); removeCard()
        val p = HaqReminders.plan(this)
        val job = HaqReminders.jobs(p).find { it.has("interval") }
        if (!HaqReminders.hasOverlay(p) || job == null) { stopSelf(); return }
        nextAt = SystemClock.elapsedRealtime() + job.getInt("interval").coerceIn(1, 300) * 60000L
        handler.post(tick)
    }
    private fun removeCard() {
        view?.let { try { getSystemService(WindowManager::class.java).removeView(it) } catch (_: Exception) {} }
        view = null; speaker?.stop(); queuedSpeech = null
    }
    private fun showCard(text: String, p: JSONObject) {
        removeCard()
        if (text.isBlank() || getSystemService(KeyguardManager::class.java).isKeyguardLocked) return
        try {
            val card = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL; layoutDirection = View.LAYOUT_DIRECTION_RTL; setPadding(24, 16, 24, 12)
                background = GradientDrawable().apply {
                    setColor(if (p.optBoolean("transparent")) Color.TRANSPARENT else p.optLong("background", 0xFF2A8C82).toInt())
                    cornerRadius = 24f; setStroke(2, p.optLong("border", 0xFFC7A45A).toInt())
                }
            }
            val message = TextView(this).apply {
                this.text = text; textSize = p.optInt("fontSize", 20).coerceIn(12, 50).toFloat()
                setTextColor(p.optLong("textColor", 0xFFFFFCF7).toInt()); gravity = Gravity.CENTER
                val asset = when (p.optString("font")) { "Tajawal" -> "Tajawal-Regular.ttf"; "Amiri" -> "AmiriQuran.ttf"; else -> "Cairo.ttf" }
                try { typeface = Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/$asset") } catch (_: Exception) {}
            }
            message.measure(View.MeasureSpec.makeMeasureSpec((resources.displayMetrics.widthPixels * .92).toInt() - 48, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            card.addView(ScrollView(this).apply { addView(message) }, LinearLayout.LayoutParams(-1, -2).apply {
                height = minOf(message.measuredHeight, (resources.displayMetrics.heightPixels * .30).toInt()).coerceAtLeast(44)
            })
            card.addView(LinearLayout(this).apply {
                addView(Button(this@HaqOverlayService).apply { this.text = "إخفاء"; setOnClickListener { removeCard() } })
                addView(Button(this@HaqOverlayService).apply { this.text = "تأجيل"; setOnClickListener {
                    nextAt = SystemClock.elapsedRealtime() + p.optInt("snooze", 10) * 60000L; removeCard()
                } })
            })
            val params = WindowManager.LayoutParams((resources.displayMetrics.widthPixels * .92).toInt(), -2,
                if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT).apply {
                gravity = Gravity.CENTER_HORIZONTAL or when (p.optString("position")) { "bottom" -> Gravity.BOTTOM; "center" -> Gravity.CENTER_VERTICAL; else -> Gravity.TOP }
                y = if (p.optString("position") == "center") 0 else 72
            }
            getSystemService(WindowManager::class.java).addView(card, params); view = card
            if (p.optBoolean("effects", true)) {
                val animation = p.optString("animation", "zoom")
                when (animation) {
                    "zoom", "bounce" -> { card.scaleX = .8f; card.scaleY = .8f }
                    "height" -> card.scaleY = .1f
                    "width" -> card.scaleX = .1f
                    "horizontal" -> card.translationX = 80f
                    "vertical" -> card.translationY = -80f
                    else -> card.alpha = 0f
                }
                val animator = card.animate().alpha(1f).scaleX(1f).scaleY(1f).translationX(0f).translationY(0f).setDuration(350)
                if (animation == "bounce") animator.setInterpolator(android.view.animation.OvershootInterpolator())
                animator.start()
            }
            val seconds = when (val hide = p.optInt("hide", -1)) { -1 -> (text.split(Regex("\\s+")).size * .6).toInt().coerceIn(5, 120); else -> hide }
            if (seconds > 0) handler.postDelayed({ removeCard() }, seconds * 1000L)
            if (p.optBoolean("speech")) {
                queuedSpeech = text
                if (speaker == null) speaker = TextToSpeech(this, this)
                else speak()
            }
        } catch (_: Exception) { stopSelf() }
    }
    override fun onInit(status: Int) {
        speechReady = status == TextToSpeech.SUCCESS && (speaker?.setLanguage(Locale("ar")) ?: -1) >= 0
        speak()
    }
    private fun speak() { if (speechReady) queuedSpeech?.let { speaker?.speak(it, TextToSpeech.QUEUE_FLUSH, null, "haq-reminder"); queuedSpeech = null } }
    override fun onDestroy() {
        unregisterReceiver(screenOff)
        handler.removeCallbacksAndMessages(null); removeCard(); speaker?.shutdown(); current = null
        stopForeground(STOP_FOREGROUND_REMOVE); super.onDestroy()
        // Fall back to notification center when Android/user stops the service.
        try { HaqReminders.restore(this) } catch (_: Exception) {}
    }
}

class HaqRemindersBridge(private val activity: MainActivity, private val channel: MethodChannel) {
    private var pendingRoute: String? = null
    private var pendingNotificationPermission: MethodChannel.Result? = null
    init {
        capture(activity.intent, false)
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "scope" -> { HaqReminders.changeScope(activity, call.arguments as String); result.success(null) }
                    "replace" -> { HaqReminders.replace(activity, JSONObject(call.arguments as Map<*, *>)); result.success(null) }
                    "status" -> result.success(HaqReminders.status(activity))
                    "preparePublicPush" -> { HaqReminders.channels(activity); result.success(null) }
                    "adhanStatus" -> result.success(mapOf("platform" to "android",
                        "exact" to (Build.VERSION.SDK_INT < 31 || activity.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()),
                        "fullScreen" to (Build.VERSION.SDK_INT < 34 || activity.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()),
                        "reminderRecordings" to (File(activity.filesDir, "adhan").listFiles()?.filter { it.isFile && it.extension == "mp3" && HaqAdhanRules.reminderId(it.nameWithoutExtension) }?.map { it.nameWithoutExtension } ?: emptyList<String>())))
                    "prepareAdhan", "preparePrayerReminder" -> {
                        val id = call.argument<String>("id") ?: error("voice")
                        require(if (call.method == "preparePrayerReminder") HaqAdhanRules.reminderId(id) else HaqAdhanRules.voiceId(id))
                        val source = File(call.argument<String>("path") ?: error("path")).canonicalFile
                        require(source.path.startsWith(File(activity.applicationInfo.dataDir).canonicalPath + File.separator) && source.isFile && source.length() in 1000..20971520)
                        if (call.method == "preparePrayerReminder") {
                            require(source.length() <= 4194304)
                            val metadata = android.media.MediaMetadataRetriever()
                            try { metadata.setDataSource(source.path); require((metadata.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0) in 1..30000) }
                            finally { metadata.release() }
                        }
                        val target = File(activity.filesDir, "adhan/$id.mp3")
                        target.parentFile!!.mkdirs()
                        val temp = File(target.parentFile, "$id.part")
                        source.copyTo(temp, overwrite = true)
                        check(temp.renameTo(target))
                        result.success(true)
                    }
                    "exactAlarmPermission" -> {
                        if (Build.VERSION.SDK_INT >= 31) activity.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${activity.packageName}")))
                        result.success(null)
                    }
                    "fullScreenPermission" -> {
                        if (Build.VERSION.SDK_INT >= 34) activity.startActivity(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:${activity.packageName}")))
                        result.success(null)
                    }
                    "communityMessage" -> {
                        val scope = call.argument<String>("scope") ?: error("Missing scope")
                        val id = call.argument<Int>("id") ?: error("Missing ID")
                        require(id > 0)
                        result.success(HaqReminders.communityMessage(activity, scope, id, call.argument<Boolean>("sound") == true))
                    }
                    "pendingOpen" -> { result.success(pendingRoute); pendingRoute = null }
                    "requestPermission" -> {
                        if (HaqReminders.allowed(activity)) result.success(null)
                        else if (pendingNotificationPermission != null) result.error("busy", "Permission request is already open", null)
                        else if (Build.VERSION.SDK_INT >= 33) {
                            pendingNotificationPermission = result
                            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), HaqReminders.NOTIFICATION_PERMISSION)
                        } else {
                            activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName))
                            result.success(null)
                        }
                    }
                    "overlayPermission" -> { activity.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${activity.packageName}"))); result.success(null) }
                    "notificationSettings" -> { activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)); result.success(null) }
                    "batterySettings" -> { activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)); result.success(null) }
                    "startOverlay" -> {
                        check(Settings.canDrawOverlays(activity) && HaqReminders.allowed(activity))
                        val intent = Intent(activity, HaqOverlayService::class.java)
                        if (Build.VERSION.SDK_INT >= 26) activity.startForegroundService(intent) else activity.startService(intent)
                        result.success(null)
                    }
                    "stopOverlay" -> { activity.stopService(Intent(activity, HaqOverlayService::class.java)); result.success(null) }
                    "preview" -> {
                        val job = HaqReminders.jobs(HaqReminders.plan(activity)).firstOrNull()
                            ?: JSONObject().put("id", "preview").put("title", "معاينة تذكيرات حق").put("body", "هذه معاينة لمظهر التذكير").put("route", "settings")
                        HaqReminders.show(activity, job); result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                if (pendingNotificationPermission === result) pendingNotificationPermission = null
                result.error("reminders", "Unable to update reminders", null)
            }
        }
    }
    fun notificationPermissionResult() {
        pendingNotificationPermission?.success(null); pendingNotificationPermission = null
        channel.invokeMethod("permissionChanged", HaqReminders.status(activity))
    }
    fun dispose() { pendingNotificationPermission?.success(null); pendingNotificationPermission = null }

    fun capture(intent: Intent?, deliver: Boolean = true) {
        val route = intent?.getStringExtra("haqRoute") ?: return
        if (intent.getStringExtra("haqScope") != HaqReminders.plan(activity).optString("scope")) return
        intent.removeExtra("haqRoute")
        if (deliver) channel.invokeMethod("open", route) else pendingRoute = route
    }
}
