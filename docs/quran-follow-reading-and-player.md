# Quran following playback and player controls

Implemented on 2026-11-03.

## Behavior

- The reader top-bar play button starts an ayah-by-ayah queue from the selected/current ayah to the end of its surah, using the ayah reciter. It pauses/resumes an existing following session.
- The playing ayah has its own highlight, independent of a manual selection. Continuous reading scrolls to the next ayah; Mushaf pages and single-ayah mode follow the current track.
- Verse options include starting recitation from that ayah. The bottom player still defaults to full-surah playback when no ayah/session is selected.
- The chevrons or horizontal swipe hide the player into a floating circle on the corresponding side. Restoring the player does not replace the queue or restart playback. This also works with the global audio dock and fullscreen reading.
- The moon opens a staged sleep-timer sheet: 5, 10, 15, 20, 30 or 60 minutes, or end of the current surah, with the existing final-five-second fade option. Set applies the choice; dismissing does not apply it; an active timer can be cancelled. The moon shows remaining time.
- The existing player surface, rounded outline, accent, headphones, reciter picker, play button and expandable details are retained.

## Text and monochrome fixes

- Added missing Arabic/English/Turkish settings labels, font hints, offline status and source attribution; regenerated bundled localization.
- The original QCF glyphs, layout and font bytes remain unchanged. When Tajweed colors are disabled, luminance grayscale retains the light medallion interiors and dark ayah digits.
- The reader toolbar fits narrow 320px layouts, including English labels.

## Validation

- All 104 Quran, interface-message and audio-dock regression tests passed. Scoped Flutter analysis reported no issues.
- Quran regression tests cover existing playback ownership, repeat/timer behavior, selection, modes, settings and rendering.
- New tests cover per-ayah queues, following and independent highlighting in all three modes, automatic page/scroll changes, hidden playback, restore without restart, fullscreen controls, and complete settings localization.
- Font tests decode the actual bundled QCF asset directly and do not require a separately generated build fixture.
- A raster test checks both the light interior and dark ink of a real QCF ayah-number medallion without Tajweed colors.
- Local Flutter renders are previews with a test audio controller; they do not prove device audio or operating-system background behavior.
- A debug APK is built locally. Per the user request, the disconnected phone is not required for this delivery. Installation and physical-device/background/lock-screen verification remain unperformed for these changes.
- The user subsequently requested committing and pushing this work on main. Backend deployment and schema changes are outside this task.
