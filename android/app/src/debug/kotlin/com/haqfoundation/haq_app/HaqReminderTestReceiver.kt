package com.haqfoundation.haq_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Fixed, local development fixtures; this receiver is absent from release APKs. */
class HaqReminderTestReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            val kind = intent.getStringExtra("kind") ?: "morning"
            if (kind == "clear") HaqReminders.clearReminderTests(context)
            else if (kind == "advance") HaqAdhanService.current?.advanceTestRecording()
            else HaqReminders.scheduleReminderTest(context, kind, intent.getBooleanExtra("recurring", false))
        } catch (error: Exception) {
            android.util.Log.e("HaqReminderTest", "Unable to schedule test", error)
        }
    }
}
