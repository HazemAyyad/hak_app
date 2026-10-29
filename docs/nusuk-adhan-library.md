# On-demand Nusuk adhan library

The selectable library contains 48 voices from the user's downloaded Nusuk 17.5.8 recordings. The first two voices, Ali Ahmed Mulla and Hamad Ibn Ahmad Al-Daghriri, are bundled with their full adhan and takbeer MP3s (8,015,214 bytes total). No other adhan audio is included in the app assets.

`nusuk_adhan_catalog.dart` pins each variant's SHA-256/byte length and resolves downloads through the existing `HAQ_API_BASE` at `/v1/religious/adhans/{voice}/{full|takbeer}`. The remaining 46 voices download only on request. Initialization installs the two asset pairs without HTTP; preview can stream a remote full recording without saving it. Cached preview and prayer alarms use local files.

Both variants must verify before the voice is marked available. Corrupt receipts/files cannot count as ready; the bundled pair is repaired from assets on initialization. Existing `alafasy`, `nafees`, `mustafa`, `zahrani` and `archive-*` IDs remain resolvable and retain their old source/recording identity so an upgrade cannot silently relabel saved choices or reset prayer settings. The new selector lists Nusuk choices, while the selected historical recording remains readable until the user changes it.

The native `prepareAdhan` bridge now accepts `shortPath` alongside `path`. Android stores separate full and takbeer recordings; short mode uses takbeer, full mode uses full audio. Genuine takbeer files complete naturally within a 45-second safety limit. Three reference takbeer files contain full audio and retain a 25-second short-mode fallback. iOS notification clips use the takbeer source and keep the existing 25-second limit; full background notification playback is not claimed.

Backend media must be published before distributing an app that points at production. The local Laravel checkout has the complete ignored media directory plus `resources/religious/nusuk_adhans.json` and `ADHAN-README.md`, with a separate delivery archive. This source change has not been deployed or installed on a phone.

Checks: `flutter test --no-pub test/nusuk_adhan_library_test.dart test/adhan_legacy_compatibility_test.dart test/qibla_video_test.dart test/prayer_screens_test.dart`; targeted prayer analysis; `tool/check_reminders_android.ps1`. The tests exercise actual bundled bytes, no startup HTTP, paired downloads, checksum tampering, partial failure, legacy preferences and UI selection at small/enlarged screen sizes.
