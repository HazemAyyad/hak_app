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

/** Interface labels in the persisted plan, independent of the Android locale.
 * Older plans keep their Arabic defaults. Text payloads never select routes,
 * identifiers, recordings or calendar calculations. */
object HaqNativeText {
    fun text(plan: JSONObject, key: String, fallback: String, vararg args: Pair<String, Any>): String {
        val saved = plan.optJSONObject("ui")?.optJSONObject("strings")?.opt(key) as? String
        var value = saved?.takeIf { it.isNotBlank() && it.length <= 3000 } ?: fallback
        for ((name, item) in args) value = value.replace("{$name}", item.toString())
        return value
    }
    fun rtl(plan: JSONObject) = plan.optJSONObject("ui")?.optString("direction", "rtl") != "ltr"
    fun locale(plan: JSONObject): Locale = Locale.forLanguageTag(plan.optJSONObject("ui")?.optString("locale", "ar") ?: "ar")
}

/** Persisted native plan survives the Flutter process and device reboot. No
 * optional prayer exact alarms require explicit special access. */
object HaqReminders {
    private const val PREF = "haq_reminders_v1"
    private const val ROOT = "haq-reminder"
    const val NOTIFICATION_PERMISSION = 7248
    fun prefs(c: Context) = c.getSharedPreferences(PREF, Context.MODE_PRIVATE)
    fun plan(c: Context) = JSONObject(prefs(c).getString("plan", "{}") ?: "{}")
    fun ui(c: Context, key: String, fallback: String, vararg args: Pair<String, Any>) = HaqNativeText.text(plan(c), key, fallback, *args)
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
        manager.createNotificationChannel(NotificationChannel("haq_reminders_sound", HaqReminders.ui(c, "native.channel.reminders", "تذكيرات حق"), NotificationManager.IMPORTANCE_DEFAULT))
        manager.createNotificationChannel(NotificationChannel("haq_reminders_silent", HaqReminders.ui(c, "native.channel.silent", "تذكيرات حق الصامتة"), NotificationManager.IMPORTANCE_LOW).apply { setSound(null, null); enableVibration(false) })
        manager.createNotificationChannel(NotificationChannel("haq_overlay", HaqReminders.ui(c, "native.channel.overlay", "التنبيه العائم"), NotificationManager.IMPORTANCE_LOW).apply { setSound(null, null) })
        manager.createNotificationChannel(NotificationChannel("haq_prayer_vibration", HaqReminders.ui(c, "native.channel.vibration", "تنبيه الصلاة بالاهتزاز"), NotificationManager.IMPORTANCE_DEFAULT).apply { setSound(null, null); enableVibration(true); vibrationPattern = longArrayOf(0, 350, 150, 350) })
        manager.createNotificationChannel(NotificationChannel("haq_adhan_playback", HaqReminders.ui(c, "native.channel.adhan", "الأذان"), NotificationManager.IMPORTANCE_HIGH).apply { setSound(null, null); enableVibration(false) })
        manager.createNotificationChannel(NotificationChannel("haq_dhikr_alarm", HaqReminders.ui(c, "native.channel.dhikr", "منبّه أذكار الصباح والمساء والنوم"), NotificationManager.IMPORTANCE_HIGH).apply { setSound(null, null); enableVibration(false) })
        manager.createNotificationChannel(NotificationChannel("haq_community_push", HaqReminders.ui(c, "native.channel.community", "رسائل حق العامة"), NotificationManager.IMPORTANCE_DEFAULT).apply { setSound(null, null); enableVibration(false) })
    }
    fun status(c: Context): Map<String, Any> {
        channels(c)
        return mapOf("platform" to "android", "allowed" to allowed(c),
            "overlay" to Settings.canDrawOverlays(c), "overlayRunning" to (HaqOverlayService.current != null),
            "pending" to jobs(plan(c)).size, "speech" to true,
            "exact" to (Build.VERSION.SDK_INT < 31 || c.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()),
            "fullScreen" to (Build.VERSION.SDK_INT < 34 || c.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()),
            "failed" to prefs(c).getBoolean("scheduleError", false))
    }
    /** Explicit debug-only test through the real persisted AlarmManager path. */
    fun schedulePrayerTest(c:Context,kind:String,voice:String,variant:String):Long {
        require(c.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0)
        require(kind in listOf("adhan","reminderVoice") && HaqAdhanRules.voiceId(voice))
        require(HaqAdhanRules.reminderAsset(variant, "dhuhr") != null)
        check(allowed(c) && (Build.VERSION.SDK_INT < 31 || c.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()))
        val p=plan(c); val scope=p.optString("scope","guest"); val at=System.currentTimeMillis()+10000
        if (!p.has("revision")) p.put("revision",UUID.randomUUID().toString())
        p.put("scope",scope)
        val kept=JSONArray()
        for(job in jobs(p)) {
            if(job.optBoolean("test")) c.getSystemService(AlarmManager::class.java).cancel(pending(c,job.getString("id")))
            else kept.put(job)
        }
        val clip=if(kind=="adhan")voice else {
            val hash=java.security.MessageDigest.getInstance("SHA-256").digest(scope.toByteArray()).joinToString(""){"%02x".format(it)}.take(16)
            "reminder-$hash-${if(variant=="ar-ps")"" else "$variant-"}dhuhr"
        }
        val job=JSONObject().put("id","$scope:prayer:dhuhr:test-$at").put("test",true)
            .put("title",if(kind=="adhan")HaqReminders.ui(c, "native.testDhuhr", "اختبار • حان وقت صلاة الظهر") else HaqReminders.ui(c, "native.testBeforeDhuhr", "اختبار • اقتربت صلاة الظهر"))
            .put("body",HaqReminders.ui(c, "native.testPrayerBody", "اختبار حق على الجهاز — ليس موعد صلاة فعليًا")).put("route","prayer")
            .put("at",at).put("minute",0).put("alertMode",kind).put("voice",clip).put("reminderVariant",variant)
            .put("fullAdhan",true).put("showAdhanScreen",true).put("volume",100).put("iqamaMinutes",15)
        kept.put(job);p.put("jobs",kept)
        check(prefs(c).edit().putString("plan",p.toString()).commit())
        schedule(c,job,at)
        android.util.Log.i("HaqPrayerTest","Scheduled $kind after 10 seconds")
        return at
    }
    fun finishPrayerTest(c:Context,id:String?) {
        if(id==null)return
        if (JSONObject(prefs(c).getString("snoozes", "{}") ?: "{}").optLong(id) > System.currentTimeMillis()) return
        val p=plan(c);val kept=JSONArray()
        for(job in jobs(p))if(job.optString("id")!=id || !job.optBoolean("test"))kept.put(job)
        p.put("jobs",kept);prefs(c).edit().putString("plan",p.toString()).apply()
    }
    /** Visible development test; never changes a real reminder's time or enables it. */
    fun scheduleReminderTest(c: Context, kind: String, recurring: Boolean = false): Long {
        require(c.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0)
        val labels = mapOf("morning" to "أذكار الصباح", "evening" to "أذكار المساء", "sleep" to "أذكار النوم",
            "dailyWird" to "ورد القرآن", "friday" to "تذكير يوم الجمعة", "khatma" to "ورد الختمة")
        require(kind in labels)
        check(allowed(c) && (Build.VERSION.SDK_INT < 31 || c.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()))
        val p = plan(c); val scope = p.optString("scope", "guest")
        if (!p.has("revision")) p.put("revision", UUID.randomUUID().toString())
        p.put("scope", scope)
        val at = if (recurring) (System.currentTimeMillis() / 60000 + 1) * 60000 else System.currentTimeMillis() + 10000
        val source = jobs(p).find { if (kind == "khatma") it.optString("route") == "khatma" else it.optString("id") == "$scope:$kind" }
        val job = if (source != null) JSONObject(source.toString()) else JSONObject()
        for (key in listOf("weekday", "start", "end", "interval", "at")) job.remove(key)
        job.put("id", "$scope:timed-test:$kind:$at").put("test", true).put("title", ui(c, "native.testTitle", "اختبار • {name}", "name" to jobs(p).firstOrNull { it.optString("id").endsWith(":$kind") }?.optString("title").orEmpty().ifBlank { labels.getValue(kind) }))
            .put("body", HaqReminders.ui(c, "native.testBody", "اختبار حق على الجهاز — ليس موعدك المحفوظ"))
            .put("minute", Calendar.getInstance().apply { timeInMillis = at }.let { it.get(Calendar.HOUR_OF_DAY) * 60 + it.get(Calendar.MINUTE) })
            .put("route", when (kind) { "dailyWird" -> "quran"; "friday" -> "friday"; "khatma" -> "khatma"; else -> "adhkar-$kind" })
        if (!recurring) job.put("at", at)
        if (kind in listOf("morning", "evening", "sleep")) {
            job.put("alertMode", "dhikr").put("voice", "dhikr-$kind").put("volume", if (p.optBoolean("sound", true)) 100 else 0).put("showAdhanScreen", true)
        }
        val kept = JSONArray()
        for (old in jobs(p)) {
            if (old.optBoolean("test")) c.getSystemService(AlarmManager::class.java).cancel(pending(c, old.getString("id")))
            else kept.put(old)
        }
        p.put("jobs", kept.put(job))
        check(prefs(c).edit().putString("plan", p.toString()).commit())
        schedule(c, job, at)
        android.util.Log.i("HaqReminderTest", "Scheduled $kind recurring=$recurring at=$at")
        return at
    }
    fun clearReminderTests(c: Context) {
        require(c.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0)
        val p = plan(c); val kept = JSONArray()
        for (job in jobs(p)) {
            val id = job.getString("id")
            if (job.optBoolean("test") && id.contains(":timed-test:")) {
                c.getSystemService(AlarmManager::class.java).cancel(pending(c, id))
                c.getSystemService(AlarmManager::class.java).cancel(pending(c, id, "snoozed"))
                HaqAdhanService.stopFor(c, id)
            } else kept.put(job)
        }
        p.put("jobs", kept)
        check(prefs(c).edit().putString("plan", p.toString()).commit())
        if (Build.VERSION.SDK_INT >= 23) {
            val manager = c.getSystemService(NotificationManager::class.java)
            manager.activeNotifications.filter { it.tag?.startsWith("$ROOT:") == true && it.tag?.contains(":timed-test:") == true }
                .forEach { manager.cancel(it.tag, it.id) }
        }
        android.util.Log.i("HaqReminderTest", "Cleared timed test fixtures and their notifications")
    }
    private fun intent(c: Context, id: String, action: String = "fire", scheduledAt: Long? = null) = Intent(c, HaqReminderReceiver::class.java).apply {
        this.action = action; data = Uri.parse("$ROOT://job/${Uri.encode(id)}"); putExtra("id", id)
        putExtra("revision", plan(c).optString("revision"))
        if (scheduledAt != null) putExtra("scheduledAt", scheduledAt)
    }
    private fun pending(c: Context, id: String, action: String = "fire", scheduledAt: Long? = null) = PendingIntent.getBroadcast(c, 0,
        intent(c, id, action, scheduledAt), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun open(c: Context, route: String, scope: String): PendingIntent = PendingIntent.getActivity(c, 0,
        Intent(c, MainActivity::class.java).apply {
            action = "haq.open"; data = Uri.parse("$ROOT://open/${Uri.encode(scope)}/${Uri.encode(route)}")
            putExtra("haqRoute", route); putExtra("haqScope", scope)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun cancel(c: Context, p: JSONObject, stopPlayback: Boolean = true) {
        if (stopPlayback) c.stopService(Intent(c, HaqAdhanService::class.java))
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
        cancel(c, old, stopPlayback = !HaqAdhanRules.retainPlayback(old, next))
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
        val exact = !job.has("interval") && (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms())
        // Explicit times selected by the user can wake their alarm surface.
        // Repeating smart dhikr keeps the battery-friendly inexact schedule.
        if (exact) alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(c, job.getString("id"), action, at))
        else alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(c, job.getString("id"), action, at))
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
        val sound = (job.has("alertMode") || p.optBoolean("sound", true)) && mode !in listOf("vibration", "silent") && (mode != "dhikr" || job.optInt("volume", 100) > 0)
        val channelId = if (mode == "vibration") "haq_prayer_vibration" else if (sound) "haq_reminders_sound" else "haq_reminders_silent"
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, channelId) else Notification.Builder(c)
        builder.setSmallIcon(R.drawable.ic_haq_reminder).setContentTitle(job.getString("title")).setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body)).setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE).setCategory(Notification.CATEGORY_REMINDER)
            .setContentIntent(open(c, job.getString("route"), p.optString("scope")))
            .addAction(Notification.Action.Builder(null, ui(c, "native.snoozeMinutes", "تأجيل {count} د", "count" to p.optInt("snooze", 10)), pending(c, job.getString("id"), "snooze")).build())
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
        builder.setSmallIcon(R.drawable.ic_haq_reminder).setContentTitle(HaqReminders.ui(c, "native.communityTitle", "رسائل حق"))
            .setContentText(HaqReminders.ui(c, "native.communityBody", "وصل محتوى جديد إلى رسائل حق")).setAutoCancel(true)
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
            HaqAdhanService.stopFor(c, job.getString("id"))
            val at = System.currentTimeMillis() + p.optInt("snooze", 10).coerceIn(10, 60) * 60000L
            val saved = JSONObject(prefs(c).getString("snoozes", "{}") ?: "{}").put(job.getString("id"), at)
            if (prefs(c).edit().putString("snoozes", saved.toString()).commit()) schedule(c, job, at, "snoozed")
            c.getSystemService(NotificationManager::class.java).cancel("$ROOT:${job.getString("id")}", 0)
        } else {
            val at = event.getLongExtra("scheduledAt", job.optLong("at"))
            val snoozed = event.action == "snoozed"
            val occurrence = if (snoozed) JSONObject(prefs(c).getString("snoozes", "{}") ?: "{}").optLong(job.getString("id")) == at
                else HaqAdhanRules.occurrence(job, at)
            val timely = occurrence && HaqAdhanRules.timely(at, System.currentTimeMillis())
            val exact = Build.VERSION.SDK_INT < 31 || c.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
            val adhan = event.action in listOf("fire", "snoozed") && timely && exact && allowed(c) && HaqAdhanRules.alarmJob(job)
            var started = false
            if (adhan) {
                try {
                    val launch = Intent(c, HaqAdhanService::class.java).putExtra("id", job.getString("id")).putExtra("revision", p.optString("revision"))
                        .putExtra("scheduledAt", at).putExtra("snoozed", snoozed)
                    if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(launch) else c.startService(launch)
                    started = true
                } catch (_: Exception) { show(c, job); prefs(c).edit().putBoolean("scheduleError", true).apply() }
            } else show(c, job)
            if (job.optBoolean("test")) android.util.Log.i("HaqReminderTest", "Delivered route=${job.optString("route")} alarm=$started occurrence=$occurrence")
            if (event.action == "fire" && !job.optBoolean("test")) next(job, System.currentTimeMillis())?.let { schedule(c, job, it) }
            if (snoozed && !started) {
                val saved = JSONObject(prefs(c).getString("snoozes", "{}") ?: "{}")
                saved.remove(job.getString("id")); prefs(c).edit().putString("snoozes", saved.toString()).apply()
            }
            if (job.optBoolean("test") && !started) finishPrayerTest(c, job.getString("id"))
        }
    }
}

/** No network, arbitrary file path or religious text in the alarm intent.
 * A persisted current plan is revalidated before the downloaded audio starts. */
object HaqAdhanRules {
    /** Updating interface labels must not interrupt an active, same-account
     * recording. A changed schedule, permission-sensitive mode, volume or
     * selected scripture still requires cancellation. */
    fun retainPlayback(old: JSONObject, next: JSONObject): Boolean {
        if (old.optString("scope").isBlank() || old.optString("scope") != next.optString("scope")) return false
        val oldLocale = old.optJSONObject("ui")?.optString("locale").orEmpty()
        val newLocale = next.optJSONObject("ui")?.optString("locale").orEmpty()
        val changedLanguage = oldLocale.isNotBlank() && newLocale.isNotBlank() && oldLocale != newLocale
        fun playbackPlan(value: JSONObject): JSONObject {
            val copy = JSONObject(value.toString())
            for (key in listOf("ui", "signature", "revision")) copy.remove(key)
            for (job in HaqReminders.jobs(copy)) {
                job.remove("title"); job.remove("body")
                // The old spoken cue may finish; future alarms use the newly
                // selected automatic language without replacing its current file.
                if (changedLanguage) { job.remove("voice"); job.remove("reminderVariant") }
            }
            return copy
        }
        return equivalent(playbackPlan(old), playbackPlan(next))
    }
    private fun equivalent(a: Any?, b: Any?): Boolean = when {
        a is JSONObject && b is JSONObject -> {
            val keys = a.keys().asSequence().toSet()
            keys == b.keys().asSequence().toSet() && keys.all { equivalent(a.opt(it), b.opt(it)) }
        }
        a is JSONArray && b is JSONArray -> a.length() == b.length() && (0 until a.length()).all { equivalent(a.opt(it), b.opt(it)) }
        else -> a == b
    }
    fun dhikrKind(job: JSONObject): String? = job.optString("voice").removePrefix("dhikr-").takeIf {
        job.optString("alertMode") == "dhikr" && it in listOf("morning", "evening", "sleep") && job.optString("voice") == "dhikr-$it"
    }
    fun alarmJob(job: JSONObject) = dhikrKind(job) != null || (job.has("at") && job.optString("alertMode") in listOf("adhan", "reminderVoice"))
    fun occurrence(job: JSONObject, at: Long) = at > 0 && HaqReminders.next(job, at - 1) == at
    fun receipt(job: JSONObject, revision: String, at: Long) = "${job.getString("id")}:$revision:$at"
    fun voiceId(id: String) = id in listOf("alafasy", "nafees", "mustafa", "zahrani") || Regex("archive-[0-9a-f]{16}|nusuk-[1-9][0-9]*").matches(id)
    fun reminderId(id: String) = Regex("reminder-[0-9a-f]{16}-((ar-eg|ar-gulf|en|pn-(current|old|intro|yarab|road|salaty|light|knock|wake))-)?(fajr|dhuhr|asr|maghrib|isha)").matches(id)
    fun reminderAsset(variant: String, prayer: String): String? {
        if (prayer !in listOf("fajr", "dhuhr", "asr", "maghrib", "isha")) return null
        return when (variant) {
            "ar-ps", "ar-eg", "ar-gulf", "en", "pn-current", "pn-old" -> "$variant/$prayer.mp3"
            "pn-current-friday", "pn-old-friday" -> if (prayer == "dhuhr") "${variant.removeSuffix("-friday")}/friday.mp3" else null
            "pn-intro" -> "pn-general/intro.mp3"
            "pn-yarab" -> "pn-general/yarab.mp3"
            "pn-road" -> "pn-general/road.mp3"
            "pn-salaty" -> "pn-general/salaty.mp3"
            "pn-light" -> "pn-general/light.wav"
            "pn-knock" -> "pn-general/knock.wav"
            "pn-wake" -> "pn-general/wake.mp3"
            else -> null
        }
    }
    fun playbackId(id: String) = voiceId(id) || reminderId(id)
    fun targetVolume(maximum: Int, percent: Int) = kotlin.math.ceil(maximum * percent.coerceIn(0, 100) / 100.0).toInt()
    // Three reference takbeer files contain the full adhan. Keep short mode
    // bounded while allowing genuine takbeer recordings (up to ~32s) to finish.
    fun playbackLimit(human: Boolean, full: Boolean, shortRecording: Boolean, duration: Int, reminderVariant: String = ""): Long =
        if (human) {
            if (reminderVariant == "pn-wake" && duration in 1..45000) 45000L else 30000L
        } else if (full) 360000L else if (shortRecording && duration in 1..45000) 45000L else 25000L
    fun timely(at: Long, now: Long) = now >= at && now - at <= 120000
    fun faceDown(x: Float, y: Float, z: Float) = z < -7f && kotlin.math.abs(x) < 6f && kotlin.math.abs(y) < 6f
}

/** Only bundled catalog IDs, never paths or URLs supplied by an alarm intent. */
object HaqDhikrRules {
    fun stopOnKey(dhikr: Boolean, key: Int) = !dhikr || key !in listOf(KeyEvent.KEYCODE_POWER, KeyEvent.KEYCODE_SLEEP, KeyEvent.KEYCODE_WAKEUP)
    fun recordings(manifest: JSONObject, kind: String): List<String> {
        require(kind in listOf("morning", "evening", "sleep") && manifest.getInt("schema_version") == 1)
        val values = manifest.getJSONObject("groups").getJSONArray(kind)
        val ids = (0 until values.length()).map { values.getString(it) }
        require(ids.size in 1..64 && ids.toSet().size == ids.size)
        require(ids.all { Regex("hisn-api-[0-9]{3}").matches(it) && manifest.getJSONObject("recordings").has(it) })
        return ids
    }
}

class HaqDhikrQueue(private val recordings: List<String>) {
    var index = -1; private set
    fun next(): String? {
        if (index >= recordings.size) return null
        index++
        return recordings.getOrNull(index)
    }
}

class HaqAdhanService : Service(), SensorEventListener {
    companion object {
        const val ID = 7401
        var current: HaqAdhanService? = null; private set
        fun stop(c: Context) { current?.traceStop("stop-service-request"); c.stopService(Intent(c, HaqAdhanService::class.java)) }
        fun stopFor(c: Context, id: String) { if (current?.activeId == id) stop(c) }
    }
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var prepared = false
    private var testPlayback = false
    private var dhikrPlayback = false
    private var dhikrIndex = 0
    private var dhikrTotal = 0
    fun dhikrProgress(): Pair<Int, Int>? = if (dhikrPlayback) dhikrIndex to dhikrTotal else null
    fun traceStop(reason: String) { if (testPlayback) android.util.Log.i("HaqReminderTest", "Stop reason=$reason") }
    fun advanceTestRecording() {
        require(applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0)
        check(testPlayback && dhikrPlayback && prepared)
        val active = player ?: error("No test player")
        active.seekTo((active.duration - 300).coerceAtLeast(0))
        android.util.Log.i("HaqReminderTest", "Seeking test recording to its end; real completion must advance the queue")
    }
    fun playback(): Pair<Int, Int>? = if (!prepared) null else try {
        player?.let { it.currentPosition to it.duration }
    } catch (_: IllegalStateException) { null }
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
        override fun onReceive(c: Context, intent: Intent) { if (intent.action == Intent.ACTION_SCREEN_OFF && !dhikrPlayback) stopSelf() }
    }
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") { stopSelf(); return START_NOT_STICKY }
        if (activeId != null) return START_NOT_STICKY // Preserve the active playback and its volume ownership.
        val p = HaqReminders.plan(this)
        val job = HaqReminders.jobs(p).find { it.optString("id") == intent?.getStringExtra("id") }
        val at = intent?.getLongExtra("scheduledAt", job?.optLong("at") ?: 0) ?: 0
        val snoozed = intent?.getBooleanExtra("snoozed", false) == true
        val occurrence = job != null && if (snoozed) JSONObject(HaqReminders.prefs(this).getString("snoozes", "{}") ?: "{}").optLong(job.getString("id")) == at else HaqAdhanRules.occurrence(job, at)
        val valid = job != null && intent?.getStringExtra("revision") == p.optString("revision") &&
            HaqAdhanRules.alarmJob(job) && occurrence &&
            HaqAdhanRules.timely(at, System.currentTimeMillis()) && HaqReminders.allowed(this)
        if (!valid) { stopSelf(); return START_NOT_STICKY }
        val voice = job!!.optString("voice")
        val dhikr = HaqAdhanRules.dhikrKind(job)
        if (dhikr == null && !HaqAdhanRules.playbackId(voice)) { stopSelf(); return START_NOT_STICKY }
        HaqReminders.channels(this)
        if (dhikr != null && Build.VERSION.SDK_INT >= 26 && getSystemService(NotificationManager::class.java).getNotificationChannel("haq_dhikr_alarm")?.importance == NotificationManager.IMPORTANCE_NONE) {
            stopSelf(); return START_NOT_STICKY
        }
        var audio = File(filesDir, "adhan/$voice.mp3")
        val shortAudio = File(filesDir, "adhan/$voice-takbeer.mp3")
        val useShortRecording = job.optString("alertMode") == "adhan" && !job.optBoolean("fullAdhan") && shortAudio.isFile
        if (useShortRecording) audio = shortAudio
        if (!audio.isFile && job.optString("alertMode") == "reminderVoice" && HaqAdhanRules.reminderId(voice)) {
            val prayer = voice.substringAfterLast('-')
            val variant = job.optString("reminderVariant", "ar-ps")
            val relative = HaqAdhanRules.reminderAsset(variant, prayer)
            try {
                requireNotNull(relative)
                val extension = relative.substringAfterLast('.')
                val bundled = File(filesDir, "adhan/bundled-v2-$variant-$prayer.$extension")
                if (!bundled.isFile) {
                    bundled.parentFile!!.mkdirs()
                    val temp = File(bundled.parentFile, "bundled-v2-$variant-$prayer.part")
                    assets.open("flutter_assets/assets/prayer/reminders/$relative").use { input -> temp.outputStream().use { input.copyTo(it) } }
                    check(temp.renameTo(bundled))
                }
                audio = bundled
            } catch (_: Exception) { }
        }
        if (dhikr != null) {
            audio = File(filesDir, "adhan/bundled-dhikr-v1-$dhikr.mp3")
            try {
                if (!audio.isFile) {
                    audio.parentFile!!.mkdirs()
                    val temp = File(audio.parentFile, "bundled-dhikr-v1-$dhikr.part")
                    assets.open("flutter_assets/assets/prayer/reminders/dhikr-$dhikr.mp3").use { input -> temp.outputStream().use { input.copyTo(it) } }
                    check(temp.renameTo(audio))
                }
            } catch (_: Exception) { }
        }
        if (!audio.isFile) { HaqReminders.show(this, job); stopSelf(); return START_NOT_STICKY }
        val recordingFiles = mutableListOf(audio)
        if (dhikr != null && job.optInt("volume", 100) > 0) {
            try {
                val manifest = assets.open("flutter_assets/assets/prayer/reminders/dhikr-playlists.json").bufferedReader().use { JSONObject(it.readText()) }
                for (id in HaqDhikrRules.recordings(manifest, dhikr)) {
                    val recording = File(filesDir, "adhan/dhikr-recordings-v1/$id.mp3")
                    if (!recording.isFile) {
                        recording.parentFile!!.mkdirs()
                        val temp = File(recording.parentFile, "$id.part")
                        assets.open("flutter_assets/assets/prayer/dhikr_recitations/$id.mp3").use { input -> temp.outputStream().use { input.copyTo(it) } }
                        check(temp.renameTo(recording))
                    }
                    recordingFiles.add(recording)
                }
            } catch (_: Exception) {
                HaqReminders.prefs(this).edit().putBoolean("scheduleError", true).apply()
                HaqReminders.show(this, JSONObject(job.toString()).put("body", HaqReminders.ui(this@HaqAdhanService, "native.recordingError", "تعذّر تشغيل تسجيلات الأذكار؛ افتح المجموعة للاستماع")))
                stopSelf(); return START_NOT_STICKY
            }
        }
        val receipt = HaqAdhanRules.receipt(job, p.optString("revision"), at)
        if (HaqReminders.prefs(this).getString("lastAdhan", null) == receipt) { stopSelf(); return START_NOT_STICKY }
        if (!HaqReminders.prefs(this).edit().putString("lastAdhan", receipt).commit()) { stopSelf(); return START_NOT_STICKY }
        activeId = job.getString("id")
        if (snoozed) {
            val saved = JSONObject(HaqReminders.prefs(this).getString("snoozes", "{}") ?: "{}")
            saved.remove(activeId); HaqReminders.prefs(this).edit().putString("snoozes", saved.toString()).apply()
        }
        testPlayback = job.optBoolean("test")
        dhikrPlayback = dhikr != null
        dhikrTotal = recordingFiles.size - 1
        current = this
        HaqReminders.channels(this)
        val humanReminder = job.optString("alertMode") == "reminderVoice"
        val launch = Intent(this, HaqAdhanActivity::class.java).putExtra("title", job.optString("title"))
            .putExtra("at", at).putExtra("iqamaMinutes", if (dhikr != null) 0 else job.optInt("iqamaMinutes", 15))
            .putExtra("scope", p.optString("scope"))
            .putExtra("dhikr", dhikr).putExtra("route", job.optString("route"))
            .putExtra("fajr", job.optString("id").contains(":prayer:fajr:"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val screen = PendingIntent.getActivity(this, ID, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, ID, Intent(this, HaqAdhanService::class.java).setAction("stop"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, if (dhikr != null) "haq_dhikr_alarm" else "haq_adhan_playback") else Notification.Builder(this)
        builder.setSmallIcon(R.drawable.ic_haq_reminder).setContentTitle(job.optString("title"))
            .setContentText(HaqReminders.ui(this@HaqAdhanService, "native.stopHint", "المس للإيقاف، أو اقلب الهاتف على وجهه"))
            .setCategory(Notification.CATEGORY_ALARM).setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true).setContentIntent(if (humanReminder) HaqReminders.open(this, "prayer", p.optString("scope")) else screen).setDeleteIntent(stop)
            .addAction(Notification.Action.Builder(null, if(humanReminder || dhikr != null)HaqReminders.ui(this@HaqAdhanService, "native.stopAudio", "إيقاف الصوت") else HaqReminders.ui(this@HaqAdhanService, "native.stopAdhan", "إيقاف الأذان"), stop).build())
        if (dhikr != null) builder.addAction(Notification.Action.Builder(null, HaqReminders.ui(this@HaqAdhanService, "native.snoozeMinutes", "تأجيل {count} د", "count" to p.optInt("snooze",10)), PendingIntent.getBroadcast(this, 0,
            Intent(this, HaqReminderReceiver::class.java).setAction("snooze").setData(Uri.parse("haq-reminder://job/${Uri.encode(job.getString("id"))}"))
                .putExtra("id", job.getString("id")).putExtra("revision", p.optString("revision")), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)).build())
        if (Build.VERSION.SDK_INT < 26) builder.setPriority(Notification.PRIORITY_HIGH)
        if (!humanReminder && job.optBoolean("showAdhanScreen", true) && (Build.VERSION.SDK_INT < 34 || getSystemService(NotificationManager::class.java).canUseFullScreenIntent())) {
            builder.setFullScreenIntent(screen, true)
        }
        try {
            startForeground(ID, builder.build())
            if(humanReminder) HaqReminders.show(this,JSONObject(job.toString()).put("alertMode","silent"))
            if(testPlayback) android.util.Log.i("HaqPrayerTest","Started ${job.optString("alertMode")} voice=$voice")
            player?.release()
            val audioManager = getSystemService(AudioManager::class.java)
            val attrs = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
            val listener = AudioManager.OnAudioFocusChangeListener { change -> if (change <= 0) { traceStop("audio-focus-$change"); stopSelf() } }
            legacyFocus = listener
            val granted = if (Build.VERSION.SDK_INT >= 26) {
                focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attrs)
                    .setOnAudioFocusChangeListener(listener).build()
                audioManager.requestAudioFocus(focus!!)
            } else audioManager.requestAudioFocus(listener, AudioManager.STREAM_ALARM, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            if (granted != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { stopSelf(); return START_NOT_STICKY }
            wake = (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "haq:adhan").apply { acquire(if(dhikrPlayback) 2700000 else 360000) }
            sensor = getSystemService(SENSOR_SERVICE) as SensorManager
            sensor?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let { sensor?.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
            originalVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
            var managedVolume = false
            if (!humanReminder && job.optInt("volume", 100) > 0 && !audioManager.isVolumeFixed && getSystemService(NotificationManager::class.java).currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_ALL) {
                try { audioManager.setStreamVolume(AudioManager.STREAM_ALARM,
                    HaqAdhanRules.targetVolume(audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM), job.optInt("volume", 100)), 0); managedVolume = true } catch (_: SecurityException) { }
            }
            playbackVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
            originalMusicVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            volume = object : ContentObserver(handler) {
                override fun onChange(selfChange: Boolean) {
                    val now = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
                    if (now != playbackVolume || audioManager.getStreamVolume(AudioManager.STREAM_MUSIC) != originalMusicVolume) { traceStop("volume-change"); stopSelf() }
                }
            }.also { contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, it) }
            if (!registered) {
                if (Build.VERSION.SDK_INT >= 33) registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF), RECEIVER_NOT_EXPORTED)
                else registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
                registered = true
            }
            val queue = HaqDhikrQueue(recordingFiles.map { it.path })
            val preparationTimeout = Runnable { stopSelf() }
            val trackTimeout = Runnable { stopSelf() }
            fun playNext() {
                if (current !== this || activeId != job.getString("id")) return
                val path = queue.next() ?: run { stopSelf(); return }
                handler.removeCallbacks(preparationTimeout); handler.removeCallbacks(trackTimeout)
                prepared = false
                player?.release()
                dhikrIndex = queue.index
                player = MediaPlayer().apply {
                    setAudioAttributes(attrs)
                    val gain = if (humanReminder || managedVolume) 1f else job.optInt("volume",100).coerceIn(0,100)/100f
                    setVolume(gain, gain)
                    setDataSource(path)
                    setOnCompletionListener { completed ->
                        if (player === completed && current === this@HaqAdhanService) {
                            if (dhikrPlayback) playNext() else stopSelf()
                        }
                    }
                    setOnErrorListener { _, what, extra -> traceStop("media-error-$what-$extra"); HaqReminders.prefs(this@HaqAdhanService).edit().putBoolean("scheduleError", true).apply(); stopSelf(); true }
                    setOnPreparedListener {
                        if (player !== it || current !== this@HaqAdhanService) return@setOnPreparedListener
                        handler.removeCallbacks(preparationTimeout)
                        prepared = true
                        it.start()
                        if(testPlayback) android.util.Log.i("HaqReminderTest", "Audio playing mode=${job.optString("alertMode")} track=${queue.index}/${recordingFiles.size-1} file=${File(path).name} duration=${it.duration} volume=${job.optInt("volume",100)}")
                        val limit = if (dhikrPlayback) it.duration.toLong() + 5000 else HaqAdhanRules.playbackLimit(humanReminder, job.optBoolean("fullAdhan"), useShortRecording, it.duration, job.optString("reminderVariant"))
                        handler.postDelayed(trackTimeout, limit)
                    }
                    prepareAsync()
                }
                handler.postDelayed(preparationTimeout, 15000)
            }
            playNext()
            if (dhikrPlayback) handler.postDelayed({ stopSelf() }, 2700000)
        } catch (_: Exception) { HaqReminders.prefs(this).edit().putBoolean("scheduleError", true).apply(); stopSelf() }
        return START_NOT_STICKY
    }
    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
        val down = HaqAdhanRules.faceDown(event.values[0], event.values[1], event.values[2])
        if (!down) { faceDownSince = 0; return }
        val now = SystemClock.elapsedRealtime()
        if (faceDownSince == 0L) faceDownSince = now
        if (now - faceDownSince >= 450) { traceStop("face-down"); stopSelf() }
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
        prepared = false; player?.release(); player = null
        if (Build.VERSION.SDK_INT >= 26) focus?.let { getSystemService(AudioManager::class.java).abandonAudioFocusRequest(it) }
        else legacyFocus?.let { getSystemService(AudioManager::class.java).abandonAudioFocus(it) }
        if (wake?.isHeld == true) wake?.release()
        current = null
        if(testPlayback) {
            android.util.Log.i("HaqPrayerTest","Stopped playback; alarm volume restored if still owned")
            HaqReminders.finishPrayerTest(this,activeId)
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}

/** System-owned full-screen alarm surface: never overlays other apps through
 * SYSTEM_ALERT_WINDOW and never dismisses the user's keyguard. */
class HaqAdhanActivity : Activity() {
    private val handler=Handler(Looper.getMainLooper())
    private var frame=0
    private lateinit var photo:ImageView
    private lateinit var countdown:TextView
    private var listening:TextView? = null
    private var pulse:android.animation.ValueAnimator?=null
    private var deadline=0L
    private var dhikr: String? = null
    private val scenes=listOf("assets/home/dawn.png","assets/religious/hands.png","assets/religious/madina.png")
    private val clock=object:Runnable {
        override fun run() {
            if(HaqAdhanService.current==null) { finish();return }
            HaqAdhanService.current?.dhikrProgress()?.let { (index, total) ->
                listening?.text = if(index == 0) HaqReminders.ui(this@HaqAdhanActivity, "native.dhikrCue", "نداء التذكير") else HaqReminders.ui(this@HaqAdhanActivity, "native.dhikrProgress", "القراءة الصوتية · المقطع {index} من {total}", "index" to index, "total" to total)
            }
            val remaining=((deadline-System.currentTimeMillis())/1000).coerceAtLeast(0)
            countdown.text=if(remaining>0) HaqReminders.ui(this@HaqAdhanActivity, "native.iqama", "الإقامة بعد\n{time}", "time" to String.format(HaqNativeText.locale(HaqReminders.plan(this@HaqAdhanActivity)), "%02d:%02d", remaining/60, remaining%60)) else HaqReminders.ui(this@HaqAdhanActivity, "native.prayerTime", "حان وقت الصلاة")
            handler.postDelayed(this,1000)
        }
    }
    private val backgrounds=object:Runnable {
        override fun run() {
            frame++
            photo.animate().alpha(.4f).setDuration(500).withEndAction {
                loadScene();photo.animate().alpha(1f).setDuration(850).start()
            }.start()
            handler.postDelayed(this,5000)
        }
    }
    private fun dp(n:Int)=(n*resources.displayMetrics.density).toInt()
    private fun loadScene() {
        try { assets.open("flutter_assets/"+scenes[frame%scenes.size]).use {
            photo.setImageDrawable(android.graphics.drawable.Drawable.createFromStream(it,null))
        } } catch(_:Exception) { photo.setBackgroundColor(Color.rgb(16,42,67)) }
    }
    override fun onCreate(state:Bundle?) {
        super.onCreate(state)
        actionBar?.hide()
        if(HaqAdhanService.current==null) { finish();return }
        dhikr = intent.getStringExtra("dhikr")?.takeIf { it in listOf("morning", "evening", "sleep") }
        window.addFlags(LayoutParams.FLAG_SHOW_WHEN_LOCKED or LayoutParams.FLAG_TURN_SCREEN_ON)
        if (dhikr == null) window.addFlags(LayoutParams.FLAG_KEEP_SCREEN_ON)
        if(Build.VERSION.SDK_INT>=27) { setShowWhenLocked(true);setTurnScreenOn(true) }
        val navy=Color.rgb(16,42,67);val teal=Color.rgb(42,140,130);val gold=Color.rgb(199,164,90)
        val compact=resources.configuration.screenHeightDp<700 || resources.configuration.fontScale>1.3f
        val brand=try { Typeface.createFromAsset(assets,"flutter_assets/assets/fonts/Cairo.ttf") } catch(_:Exception) { Typeface.DEFAULT }
        deadline=intent.getLongExtra("at",System.currentTimeMillis())+intent.getIntExtra("iqamaMinutes",15).coerceIn(0,60)*60000L
        val root=FrameLayout(this).apply { setBackgroundColor(navy);layoutDirection=if(HaqNativeText.rtl(HaqReminders.plan(this@HaqAdhanActivity))) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR }
        photo=ImageView(this).apply { scaleType=ImageView.ScaleType.CENTER_CROP }
        root.addView(photo,FrameLayout.LayoutParams(-1,-1));loadScene()
        root.addView(View(this).apply { background=GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(Color.argb(150,11,23,34),Color.argb(70,11,23,34),Color.argb(245,11,23,34))) },FrameLayout.LayoutParams(-1,-1))
        fun text(value:String,size:Float,color:Int=Color.WHITE)=TextView(this).apply {
            this.text=value;textSize=size;typeface=brand;setTextColor(color);gravity=Gravity.CENTER
            setPadding(dp(4),0,dp(4),0)
        }
        fun autosize(view:TextView,min:Int,max:Int) {
            if(Build.VERSION.SDK_INT>=26)view.setAutoSizeTextTypeUniformWithConfiguration(min,max,1,android.util.TypedValue.COMPLEX_UNIT_SP)
        }
        val content=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL;gravity=Gravity.CENTER_HORIZONTAL;setPadding(dp(18),dp(12),dp(18),dp(12)) }
        val header=LinearLayout(this).apply { gravity=Gravity.CENTER_VERTICAL }
        fun icon(value:String,label:String,action:()->Unit)=Button(this).apply {
            text=value;contentDescription=label;setTextColor(Color.WHITE);setBackgroundColor(Color.TRANSPARENT);setOnClickListener { action() }
        }
        header.addView(icon("×",if(dhikr != null) HaqReminders.ui(this@HaqAdhanActivity, "native.stopDhikr", "إيقاف التذكير") else HaqReminders.ui(this@HaqAdhanActivity, "native.stopAdhan", "إيقاف الأذان"),::stop),LinearLayout.LayoutParams(dp(48),dp(48)))
        header.addView(text(if(dhikr != null) HaqReminders.ui(this@HaqAdhanActivity, "native.headerDhikr", "حق · تذكير الأذكار") else HaqReminders.ui(this@HaqAdhanActivity, "native.headerPrayer", "حق · نداء الصلاة"),16f).apply { maxLines=1;autosize(this,12,16) },LinearLayout.LayoutParams(0,dp(48),1f))
        header.addView(icon("⚙",if(dhikr != null) HaqReminders.ui(this@HaqAdhanActivity, "native.reminderSettings", "إعدادات التذكير") else HaqReminders.ui(this@HaqAdhanActivity, "native.prayerSettings", "إعدادات الأذان")) { open(if(dhikr != null) "settings" else "prayer-settings") },LinearLayout.LayoutParams(dp(48),dp(48)))
        content.addView(header,LinearLayout.LayoutParams(-1,dp(48)))
        content.addView(text(intent.getStringExtra("title") ?: HaqReminders.ui(this@HaqAdhanActivity, "native.prayerTime", "حان وقت الصلاة"),24f,gold).apply { maxLines=2;autosize(this,15,24) },
            LinearLayout.LayoutParams(-1,dp(if(compact)44 else 56)))
        val logo=ImageView(this).apply {
            scaleType=ImageView.ScaleType.FIT_CENTER;contentDescription=HaqReminders.ui(this@HaqAdhanActivity, "native.logo", "شعار حق")
        }
        try { assets.open("flutter_assets/assets/branding/haq_logo_light.png").use { logo.setImageDrawable(android.graphics.drawable.Drawable.createFromStream(it,null)) } } catch(_:Exception) { }
        val logoSize=dp(if(compact)48 else 68)
        content.addView(logo,LinearLayout.LayoutParams(logoSize,logoSize))
        val middle=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL;gravity=Gravity.CENTER }
        val words=text(if(dhikr != null) HaqReminders.ui(this@HaqAdhanActivity, "native.dhikrTime", "حان وقت الذكر") else "الله أكبر",56f).apply { maxLines=1;autosize(this,28,56) }
        middle.addView(words,LinearLayout.LayoutParams(-1,dp(if(compact)76 else 110)))
        if(dhikr != null) {
            listening = text(HaqReminders.ui(this@HaqAdhanActivity, "native.dhikrCue", "نداء التذكير"),16f,gold).apply { maxLines=2;autosize(this,12,16) }
            middle.addView(listening,LinearLayout.LayoutParams(-1,dp(48)))
        }
        if(Build.VERSION.SDK_INT<26 || android.animation.ValueAnimator.areAnimatorsEnabled()) {
            pulse=android.animation.ValueAnimator.ofFloat(0f,1f).apply {
                duration=2200;repeatCount=android.animation.ValueAnimator.INFINITE;repeatMode=android.animation.ValueAnimator.REVERSE
                addUpdateListener { val v=it.animatedValue as Float;words.alpha=.75f+.25f*v;words.scaleX=.96f+.04f*v;words.scaleY=.96f+.04f*v }
                start()
            }
        }
        countdown=text("",if(compact)14f else 18f).apply {
            gravity=Gravity.CENTER;maxLines=3;autosize(this,12,if(compact)14 else 18)
            background=GradientDrawable().apply { shape=GradientDrawable.OVAL;setColor(Color.argb(205,12,75,76));setStroke(dp(2),gold) }
        }
        if(intent.getIntExtra("iqamaMinutes",15)>0) {
            val circle=dp(if(compact)76 else 106)
            middle.addView(countdown,LinearLayout.LayoutParams(circle,circle).apply { topMargin=dp(8) })
            middle.addView(text(HaqReminders.ui(this@HaqAdhanActivity, "native.iqamaPersonal", "مدة الإقامة حسب إعدادك"),11f,Color.LTGRAY),LinearLayout.LayoutParams(-1,dp(24)))
        }
        content.addView(middle,LinearLayout.LayoutParams(-1,0,1f))
        fun button(title:String,route:String?,filled:Boolean)=Button(this).apply {
            text=title;typeface=brand;textSize=15f;isAllCaps=false;setTextColor(Color.WHITE);maxLines=1;autosize(this,12,15)
            background=GradientDrawable().apply { cornerRadius=dp(18).toFloat();setColor(if(filled)teal else Color.argb(80,16,42,67));setStroke(dp(1),if(filled)teal else gold) }
            setOnClickListener { if(route==null)stop() else open(route) }
        }
        content.addView(button(if(dhikr != null) HaqReminders.ui(this@HaqAdhanActivity, "native.beginDhikr", "ابدأ الأذكار") else HaqReminders.ui(this@HaqAdhanActivity, "native.afterPrayer", "أذكار بعد الصلاة"),if(dhikr != null) "adhkar-$dhikr" else "adhkar-after-prayer",true),LinearLayout.LayoutParams(-1,dp(48)).apply { bottomMargin=dp(8) })
        val shortcuts=LinearLayout(this)
        shortcuts.addView(button(HaqReminders.ui(this@HaqAdhanActivity, "native.quran", "القرآن"),"quran",false),LinearLayout.LayoutParams(0,dp(48),1f).apply { marginEnd=dp(4) })
        shortcuts.addView(button(HaqReminders.ui(this@HaqAdhanActivity, "native.qibla", "القبلة"),"qibla",false),LinearLayout.LayoutParams(0,dp(48),1f).apply { marginStart=dp(4) })
        content.addView(shortcuts,LinearLayout.LayoutParams(-1,dp(48)))
        content.addView(button(if(dhikr != null) HaqReminders.ui(this@HaqAdhanActivity, "native.stopDhikr", "إيقاف التذكير") else HaqReminders.ui(this@HaqAdhanActivity, "native.stopAdhan", "إيقاف الأذان"),null,false),LinearLayout.LayoutParams(-1,dp(44)).apply { topMargin=dp(8) })
        content.addView(text(HaqReminders.ui(this@HaqAdhanActivity, "native.deviceStop", "زر الجهاز أو قلب الهاتف يوقف الصوت"),11f,Color.LTGRAY).apply { maxLines=1;autosize(this,9,11) },LinearLayout.LayoutParams(-1,dp(24)))
        root.addView(content,FrameLayout.LayoutParams(-1,-1))
        root.setOnApplyWindowInsetsListener { _, insets ->
            content.setPadding(dp(18)+insets.systemWindowInsetLeft,dp(8)+insets.systemWindowInsetTop,
                dp(18)+insets.systemWindowInsetRight,dp(8)+insets.systemWindowInsetBottom)
            insets
        }
        setContentView(root);root.requestApplyInsets();handler.post(clock);handler.postDelayed(backgrounds,5000)
    }
    private fun open(route:String) {
        if(dhikr == null || route != "adhkar-$dhikr") HaqAdhanService.stop(this)
        try { HaqReminders.open(this,route,intent.getStringExtra("scope") ?: "guest").send() } catch(_:Exception) { }
        finish()
    }
    private fun stop() { HaqAdhanService.stop(this);finish() }
    override fun dispatchKeyEvent(event:KeyEvent):Boolean {
        if (!HaqDhikrRules.stopOnKey(dhikr != null, event.keyCode)) return super.dispatchKeyEvent(event)
        if(event.action==KeyEvent.ACTION_DOWN)stop();return true
    }
    @Deprecated("Deprecated in Android") override fun onBackPressed() { stop() }
    override fun onUserLeaveHint() { super.onUserLeaveHint();if(dhikr == null)stop() else finish() }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null);pulse?.cancel();if(::photo.isInitialized)photo.animate().cancel();super.onDestroy() }
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
        startForeground(7249, builder.setSmallIcon(R.drawable.ic_haq_reminder).setContentTitle(HaqReminders.ui(this@HaqOverlayService, "native.overlayTitle", "تذكيرات حق العائمة تعمل"))
            .setContentText(HaqReminders.ui(this@HaqOverlayService, "native.overlayBody", "اضغط إيقاف لإنهاء الظهور فوق التطبيقات")).setOngoing(true)
            .setOnlyAlertOnce(true).setShowWhen(false).setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(HaqReminders.open(this, "settings", HaqReminders.plan(this).optString("scope")))
            .setSound(null).setDefaults(0)
            .apply { if (Build.VERSION.SDK_INT < 26) setPriority(Notification.PRIORITY_LOW) }
            .addAction(Notification.Action.Builder(null, HaqReminders.ui(this@HaqOverlayService, "native.stop", "إيقاف"), stop).build()).build())
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
                orientation = LinearLayout.VERTICAL; layoutDirection = if(HaqNativeText.rtl(p)) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR; setPadding(24, 16, 24, 12)
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
                addView(Button(this@HaqOverlayService).apply { this.text = HaqReminders.ui(this@HaqOverlayService, "native.hide", "إخفاء"); setOnClickListener { removeCard() } })
                addView(Button(this@HaqOverlayService).apply { this.text = HaqReminders.ui(this@HaqOverlayService, "native.snooze", "تأجيل"); setOnClickListener {
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
                    "schedulePrayerTest" -> result.success(HaqReminders.schedulePrayerTest(activity,
                        call.argument<String>("kind") ?: "reminderVoice",call.argument<String>("voice") ?: "alafasy",
                        call.argument<String>("variant") ?: "ar-ps"))
                    "scheduleReminderTest" -> result.success(HaqReminders.scheduleReminderTest(activity,
                        call.argument<String>("kind") ?: "morning", call.argument<Boolean>("recurring") == true))
                    "clearReminderTests" -> { HaqReminders.clearReminderTests(activity); result.success(null) }
                    "preparePublicPush" -> { HaqReminders.channels(activity); result.success(null) }
                    "adhanStatus" -> result.success(mapOf("platform" to "android", "vendor" to Build.MANUFACTURER.lowercase(Locale.ROOT),
                        "exact" to (Build.VERSION.SDK_INT < 31 || activity.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()),
                        "fullScreen" to (Build.VERSION.SDK_INT < 34 || activity.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()),
                        "preparedVoices" to (File(activity.filesDir,"adhan").listFiles()?.filter { it.isFile && it.extension=="mp3" && HaqAdhanRules.voiceId(it.nameWithoutExtension) && (!it.nameWithoutExtension.startsWith("nusuk-") || File(it.parentFile,"${it.nameWithoutExtension}-takbeer.mp3").isFile) }?.map { it.nameWithoutExtension } ?: emptyList<String>()),
                        "reminderRecordings" to (File(activity.filesDir, "adhan").listFiles()?.filter { it.isFile && it.extension == "mp3" && HaqAdhanRules.reminderId(it.nameWithoutExtension) }?.map { it.nameWithoutExtension } ?: emptyList<String>())))
                    "removePrayerReminder" -> {
                        val id=call.argument<String>("id") ?: error("voice")
                        require(HaqAdhanRules.reminderId(id))
                        val file=File(activity.filesDir,"adhan/$id.mp3")
                        result.success(!file.exists() || file.delete())
                    }
                    "prepareAdhan", "preparePrayerReminder" -> {
                        val id = call.argument<String>("id") ?: error("voice")
                        require(if (call.method == "preparePrayerReminder") HaqAdhanRules.reminderId(id) else HaqAdhanRules.voiceId(id))
                        val source = File(call.argument<String>("path") ?: error("path")).canonicalFile
                        require(source.path.startsWith(File(activity.applicationInfo.dataDir).canonicalPath + File.separator) && source.isFile && source.length() in 1000..20971520)
                        val shortSource = call.argument<String>("shortPath")?.let { File(it).canonicalFile }
                        require(!id.startsWith("nusuk-") || shortSource != null)
                        if (shortSource != null) require(call.method == "prepareAdhan" && shortSource.path.startsWith(File(activity.applicationInfo.dataDir).canonicalPath + File.separator) && shortSource.isFile && shortSource.length() in 1000..20971520)
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
                        if (shortSource != null) {
                            val shortTarget = File(target.parentFile, "$id-takbeer.mp3")
                            val shortTemp = File(target.parentFile, "$id-takbeer.part")
                            shortSource.copyTo(shortTemp, overwrite = true)
                            check(shortTemp.renameTo(shortTarget))
                        }
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
                    "vendorAlarmPermissions" -> {
                        try {
                            activity.startActivity(Intent("miui.intent.action.APP_PERM_EDITOR").putExtra("extra_pkgname",activity.packageName))
                        } catch (_:Exception) {
                            activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:${activity.packageName}")))
                        }
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
                    "overlayNotificationSettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName).putExtra(Settings.EXTRA_CHANNEL_ID, "haq_overlay"))
                        result.success(null)
                    }
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
                            ?: JSONObject().put("id", "preview").put("title", HaqReminders.ui(activity, "native.previewTitle", "معاينة تذكيرات حق")).put("body", HaqReminders.ui(activity, "native.previewBody", "هذه معاينة لمظهر التذكير")).put("route", "settings")
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
