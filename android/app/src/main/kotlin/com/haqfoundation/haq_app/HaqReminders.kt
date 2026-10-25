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
 * exact-alarm grant, lock-screen overlay, or automatic permission request. */
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
        require(next.getJSONArray("jobs").length() <= 200)
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
        c.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at,
            pending(c, job.getString("id"), action))
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
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c,
            if (p.optBoolean("sound", true)) "haq_reminders_sound" else "haq_reminders_silent") else Notification.Builder(c)
        builder.setSmallIcon(R.drawable.ic_haq_reminder).setContentTitle(job.getString("title")).setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body)).setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE).setCategory(Notification.CATEGORY_REMINDER)
            .setContentIntent(open(c, job.getString("route"), p.optString("scope")))
            .addAction(Notification.Action.Builder(null, "تأجيل ${p.optInt("snooze", 10)} د", pending(c, job.getString("id"), "snooze")).build())
        if (Build.VERSION.SDK_INT < 26 && p.optBoolean("sound", true)) builder.setDefaults(Notification.DEFAULT_SOUND)
        c.getSystemService(NotificationManager::class.java).notify("$ROOT:${job.getString("id")}", 0, builder.build())
    }
    fun receive(c: Context, event: Intent) {
        if (event.action in listOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED)) {
            if (plan(c).optBoolean("startup", true) || event.action != Intent.ACTION_BOOT_COMPLETED) restore(c)
            return
        }
        val p = plan(c)
        if (event.getStringExtra("revision") != p.optString("revision")) return
        val job = jobs(p).find { it.getString("id") == event.getStringExtra("id") } ?: return
        val today = java.text.SimpleDateFormat("yyyy-MM-dd", Locale.US).format(java.util.Date())
        if (job.has("end") && today > job.getString("end")) return
        if (event.action == "snooze") {
            val at = System.currentTimeMillis() + p.optInt("snooze", 10).coerceIn(10, 60) * 60000L
            val saved = JSONObject(prefs(c).getString("snoozes", "{}") ?: "{}").put(job.getString("id"), at)
            if (prefs(c).edit().putString("snoozes", saved.toString()).commit()) schedule(c, job, at, "snoozed")
            c.getSystemService(NotificationManager::class.java).cancel("$ROOT:${job.getString("id")}", 0)
        } else {
            show(c, job)
            if (event.action == "fire") next(job, System.currentTimeMillis())?.let { schedule(c, job, it) }
            else {
                val saved = JSONObject(prefs(c).getString("snoozes", "{}") ?: "{}")
                saved.remove(job.getString("id")); prefs(c).edit().putString("snoozes", saved.toString()).apply()
            }
        }
    }
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
    init {
        capture(activity.intent, false)
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "scope" -> { HaqReminders.changeScope(activity, call.arguments as String); result.success(null) }
                    "replace" -> { HaqReminders.replace(activity, JSONObject(call.arguments as Map<*, *>)); result.success(null) }
                    "status" -> result.success(HaqReminders.status(activity))
                    "pendingOpen" -> { result.success(pendingRoute); pendingRoute = null }
                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33) activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), HaqReminders.NOTIFICATION_PERMISSION)
                        else activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName))
                        result.success(null)
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
            } catch (e: Exception) { result.error("reminders", "Unable to update reminders", null) }
        }
    }
    fun capture(intent: Intent?, deliver: Boolean = true) {
        val route = intent?.getStringExtra("haqRoute") ?: return
        if (intent.getStringExtra("haqScope") != HaqReminders.plan(activity).optString("scope")) return
        intent.removeExtra("haqRoute")
        if (deliver) channel.invokeMethod("open", route) else pendingRoute = route
    }
}
