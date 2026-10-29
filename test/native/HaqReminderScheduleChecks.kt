package com.haqfoundation.haq_app

import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone

/** Runs the actual native calendar calculation on the JVM, without an app. */
fun main() {
    TimeZone.setDefault(TimeZone.getTimeZone("Asia/Hebron"))
    fun instant(year: Int, month: Int, day: Int, hour: Int, minute: Int): Long = Calendar.getInstance().apply {
        clear(); set(year, month - 1, day, hour, minute)
    }.timeInMillis
    val morning = JSONObject().put("minute", 300)
    check(HaqReminders.next(morning, instant(2026, 10, 26, 4, 59)) == instant(2026, 10, 26, 5, 0))
    check(HaqReminders.next(morning, instant(2026, 10, 26, 5, 0)) == instant(2026, 10, 27, 5, 0))
    val friday = JSONObject().put("minute", 540).put("weekday", 5)
    check(HaqReminders.next(friday, instant(2026, 10, 29, 9, 0)) == instant(2026, 10, 30, 9, 0))
    check(HaqReminders.next(friday, instant(2026, 10, 30, 9, 0)) == instant(2026, 11, 6, 9, 0))
    val bounded = JSONObject().put("minute", 480).put("start", "2026-11-20").put("end", "2026-11-22")
    check(HaqReminders.next(bounded, instant(2026, 10, 26, 12, 0)) == instant(2026, 11, 20, 8, 0))
    check(HaqReminders.next(bounded, instant(2026, 11, 22, 8, 0)) == null)
    val leap = JSONObject().put("minute", 540).put("start", "2028-02-29").put("end", "2028-02-29")
    check(HaqReminders.next(leap, instant(2028, 2, 28, 12, 0)) == instant(2028, 2, 29, 9, 0))
    for (month in listOf(3, 10)) {
        for (day in 20..29) {
            check(HaqReminders.next(morning, instant(2026, month, day, 8, 0)) == instant(2026, month, day + 1, 5, 0))
        }
    }
    val repeat = JSONObject().put("interval", 3)
    val now = instant(2026, 10, 26, 12, 0)
    check(HaqReminders.next(repeat, now) == now + 180000)
    val once = JSONObject().put("at", now + 1000)
    check(HaqReminders.next(once, now) == now + 1000)
    check(HaqReminders.next(once, now + 1000) == null)
    check(HaqReminders.next(once, now + 60000) == null)
    check(HaqAdhanRules.timely(now, now))
    check(HaqAdhanRules.timely(now, now + 120000))
    check(!HaqAdhanRules.timely(now, now + 120001))
    check(!HaqAdhanRules.timely(now, now - 1))
    check(HaqAdhanRules.faceDown(0f, 0f, -9.8f))
    check(!HaqAdhanRules.faceDown(0f, 0f, 9.8f))
    check(!HaqAdhanRules.faceDown(8f, 0f, -8f))
    check(!HaqAdhanRules.faceDown(0f, 9.8f, 0f))
    check(HaqAdhanRules.voiceId("archive-8c0b40d74122a584"))
    check(!HaqAdhanRules.voiceId("../../sound"))
    check(!HaqAdhanRules.voiceId("archive-INVALID"))
    for (voice in listOf("nusuk-1", "nusuk-247", "alafasy", "nafees", "mustafa", "zahrani")) check(HaqAdhanRules.voiceId(voice))
    for (voice in listOf("nusuk-0", "nusuk-01", "nusuk--1", "nusuk-1.mp3", "nusuk-../1", "nusuk-1/../../sound")) check(!HaqAdhanRules.voiceId(voice))
    check(HaqAdhanRules.reminderId("reminder-aabbccddeeff0011-fajr"))
    check(!HaqAdhanRules.reminderId("reminder-aabbccddeeff0011-sunrise"))
    check(HaqAdhanRules.targetVolume(15,100)==15)
    check(HaqAdhanRules.targetVolume(15,50)==8)
    check(HaqAdhanRules.targetVolume(15,0)==0)
    check(HaqAdhanRules.reminderId("reminder-aabbccddeeff0011-en-fajr"))
    check(HaqAdhanRules.reminderId("reminder-aabbccddeeff0011-ar-eg-dhuhr"))
    check(HaqAdhanRules.reminderId("reminder-aabbccddeeff0011-ar-gulf-isha"))
    check(!HaqAdhanRules.reminderId("reminder-aabbccddeeff0011-fr-fajr"))
    check(!HaqAdhanRules.reminderId("reminder-aabbccddeeff0011-en-../fajr"))
    check(HaqAdhanRules.playbackLimit(false, false, true, 29884) == 45000L) // Ali Mulla takbeer finishes at ~30s.
    check(HaqAdhanRules.playbackLimit(false, false, true, 104516) == 25000L) // Nusuk 25 contains full audio in takbeer.
    check(HaqAdhanRules.playbackLimit(false, true, true, 251193) == 360000L)
    check(HaqAdhanRules.playbackLimit(false, false, false, 251193) == 25000L)
    check(HaqAdhanRules.playbackLimit(true, true, true, 29884) == 30000L)
    for (kind in listOf("morning", "evening", "sleep")) {
        val job = JSONObject().put("id", "guest:$kind").put("minute", 300).put("alertMode", "dhikr").put("voice", "dhikr-$kind")
        check(HaqAdhanRules.dhikrKind(job) == kind)
        check(HaqAdhanRules.alarmJob(job))
        val first = instant(2026, 10, 26, 5, 0)
        val second = instant(2026, 10, 27, 5, 0)
        check(HaqAdhanRules.occurrence(job, first))
        check(HaqAdhanRules.occurrence(job, second))
        check(!HaqAdhanRules.occurrence(job, first + 1000))
        check(HaqAdhanRules.receipt(job, "revision", first) != HaqAdhanRules.receipt(job, "revision", second))
        check(HaqAdhanRules.receipt(job, "revision", first) == HaqAdhanRules.receipt(job, "revision", first))
    }
    val invalid = JSONObject().put("minute", 300).put("alertMode", "dhikr").put("voice", "dhikr-../morning")
    check(HaqAdhanRules.dhikrKind(invalid) == null)
    check(!HaqAdhanRules.alarmJob(invalid))
    check(!HaqAdhanRules.alarmJob(JSONObject().put("alertMode", "adhan")))
    check(HaqAdhanRules.alarmJob(JSONObject().put("alertMode", "adhan").put("at", now)))
    check(HaqAdhanRules.occurrence(JSONObject().put("at", now), now))
    check(!HaqAdhanRules.occurrence(JSONObject().put("at", now), now + 1))
    val manifest = JSONObject(java.io.File("assets/prayer/reminders/dhikr-playlists.json").readText())
    for ((kind, count) in mapOf("morning" to 23, "evening" to 21, "sleep" to 15)) {
        val ids = HaqDhikrRules.recordings(manifest, kind)
        check(ids.size == count)
        check(ids.distinct().size == count)
        val expected = listOf("intro") + ids
        val queue = HaqDhikrQueue(expected)
        val consumed = mutableListOf<String>()
        while (true) consumed.add(queue.next() ?: break)
        check(consumed == expected)
        check(queue.next() == null)
        check(queue.index == expected.size)
    }
    check(runCatching { HaqDhikrRules.recordings(manifest, "../morning") }.isFailure)
    val unsafe = JSONObject(manifest.toString())
    unsafe.getJSONObject("groups").put("morning", org.json.JSONArray().put("../outside"))
    check(runCatching { HaqDhikrRules.recordings(unsafe, "morning") }.isFailure)
    unsafe.getJSONObject("groups").put("morning", org.json.JSONArray().put("hisn-api-075").put("hisn-api-075"))
    check(runCatching { HaqDhikrRules.recordings(unsafe, "morning") }.isFailure)
    check(!HaqDhikrRules.stopOnKey(true, android.view.KeyEvent.KEYCODE_SLEEP))
    check(!HaqDhikrRules.stopOnKey(true, android.view.KeyEvent.KEYCODE_POWER))
    check(HaqDhikrRules.stopOnKey(true, android.view.KeyEvent.KEYCODE_VOLUME_DOWN))
    check(HaqDhikrRules.stopOnKey(false, android.view.KeyEvent.KEYCODE_POWER))
    println("118 native checks passed (scheduling, daily occurrences, audio identifiers, ordered Hisn playlists, queue completion, screen-off playback, and face-down detection). No app built or run.")
}
