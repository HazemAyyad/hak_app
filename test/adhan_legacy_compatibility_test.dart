import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/prayer/data/adhan_library.dart';
import 'package:haq_app/features/prayer/data/prayer_alert.dart';
import 'package:haq_app/features/prayer/data/prayer_controller.dart';
import 'package:haq_app/features/prayer/data/prayer_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legacy recording IDs round-trip without resetting prayer configuration',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final original = PrayerConfig(
        location: PrayerLocation(
          latitude: 31.5,
          longitude: 34.45,
          zone: 'Asia/Hebron',
          label: 'غزة',
        ),
        beforeMinutes: 12,
        notifications: true,
        defaultAlert: PrayerAlert(
          mode: PrayerAlertMode.adhan,
          voice: legacyAdhanVoices.last.id,
          full: true,
        ),
        alerts: {
          'fajr': const PrayerAlert(
            mode: PrayerAlertMode.adhan,
            voice: 'alafasy',
          ),
          'asr': const PrayerAlert(
            mode: PrayerAlertMode.adhan,
            voice: 'nafees',
          ),
        },
      );
      await preferences.setString(
        'prayer.config.v1.guest',
        jsonEncode(original.toJson()),
      );
      final restored = PrayerController(
        preferences,
        scopeOf: () => 'guest',
        autoTick: false,
      );
      addTearDown(restored.dispose);
      expect(restored.error, isNull);
      expect(restored.config.toJson(), original.toJson());
      expect(
        await restored.save(restored.config.copyWith(beforeMinutes: 13)),
        true,
      );
      expect(restored.config.location!.label, 'غزة');
      for (final voice in legacyAdhanVoices) {
        expect(adhanVoiceById(voice.id)?.uri, voice.uri);
        expect(
          PrayerAlert.fromJson(PrayerAlert(voice: voice.id).toJson()).voice,
          voice.id,
        );
      }
      expect(adhanVoiceById('../sound'), isNull);
      expect(
        allAdhanVoices.map((voice) => voice.id).toSet().length,
        allAdhanVoices.length,
      );
    },
  );

  test(
    'cache restoration keeps legacy audio only when its receipt matches the recording source',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'haq-adhan-legacy-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final folder = await Directory('${directory.path}/adhans').create();
      final bytes = List<int>.filled(1200, 0)..setRange(0, 3, [73, 68, 51]);
      final legacy = legacyAdhanVoices.last;
      final another = legacyAdhanVoices.first;
      for (final entry in [legacy, another]) {
        await File('${folder.path}/${entry.id}.mp3').writeAsBytes(bytes);
        await File('${folder.path}/${entry.id}.json').writeAsString(
          jsonEncode({
            'bytes': bytes.length,
            'sha256': sha256.convert(bytes).toString(),
            'source': entry == legacy
                ? entry.uri.toString()
                : 'https://wrong.example/different-recording.mp3',
          }),
        );
      }
      final prepared = <String>[];
      final library = AdhanLibrary(
        directory: () async => directory,
        audio: _IdlePreview(),
        prepare: (id, path) async {
          prepared.add(id);
          return true;
        },
      );
      addTearDown(library.dispose);
      await library.initialize();
      expect(library.downloaded, {legacy.id, 'nusuk-1', 'nusuk-2'});
      expect(await library.prepareVoice(legacy.id), true);
      expect(await library.prepareVoice(another.id), false);
      expect(prepared, [legacy.id]);
    },
  );
}

class _IdlePreview implements AdhanPreviewAudio {
  @override
  Future<void> play(Uri uri) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
