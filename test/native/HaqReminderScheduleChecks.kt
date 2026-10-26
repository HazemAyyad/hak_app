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
    println("31 native scheduling checks passed (daily, Friday, expiry, leap day, DST, repeat and one-shot UTC). No app built or run.")
}
