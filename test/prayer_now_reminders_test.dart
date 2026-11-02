import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/prayer/data/prayer_controller.dart';
import 'package:haq_app/features/prayer/data/prayer_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final location = PrayerLocation(
    latitude: 31.53,
    longitude: 35.1,
    zone: 'Asia/Hebron',
    label: 'الخليل',
  );

  test(
    'old settings retain Haq voices; every new choice persists per account',
    () async {
      final legacy = PrayerConfig(location: location).toJson()
        ..remove('reminderSound');
      expect(
        PrayerConfig.fromJson(legacy).reminderSound,
        PrayerReminderSound.defaultVoice,
      );
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final account = ValueNotifier('guest');
      final controller = PrayerController(
        prefs,
        scopeOf: () => account.value,
        account: account,
        autoTick: false,
      );
      addTearDown(controller.dispose);
      addTearDown(account.dispose);
      for (final sound in PrayerReminderSound.values) {
        await controller.save(
          PrayerConfig(
            location: location,
            reminderSound: sound,
            reminderDialect: PrayerReminderDialect.egyptian,
          ),
        );
        final restored = PrayerController(
          prefs,
          scopeOf: () => 'guest',
          autoTick: false,
        );
        expect(restored.config.reminderSound, sound);
        expect(restored.reminderVariant, sound.variant ?? 'ar-eg');
        restored.dispose();
      }
      account.value = 'user:2';
      expect(controller.config.reminderSound, PrayerReminderSound.defaultVoice);
      account.value = 'guest';
      expect(controller.config.reminderSound, PrayerReminderSound.wake);
      await controller.save(
        controller.config.copyWith(
          reminderSound: PrayerReminderSound.defaultVoice,
        ),
      );
      expect(controller.reminderVariant, 'ar-eg');
    },
  );

  test(
    'new sounds route real before-adhan jobs, with Friday based on prayer timezone',
    () async {
      SharedPreferences.setMockInitialValues({});
      final controller = PrayerController(
        await SharedPreferences.getInstance(),
        scopeOf: () => 'guest',
        autoTick: false,
        // Thursday UTC is already Friday in Hebron.
        clock: () => DateTime.utc(2026, 11, 5, 22, 30),
      );
      addTearDown(controller.dispose);
      for (final sound in PrayerReminderSound.values.skip(1)) {
        await controller.save(
          PrayerConfig(
            location: location,
            notifications: true,
            reminderLanguage: 'en',
            reminderSound: sound,
          ),
        );
        controller.setAppLanguage('en');
        final jobs = controller.reminderJobs(days: 2);
        final before = jobs
            .where((j) => j.alertMode == 'reminderVoice')
            .toList();
        expect(before.length, 10);
        for (final job in before) {
          final prayer = PrayerName.values.byName(job.id.split(':')[2]);
          final local = tz.TZDateTime.fromMillisecondsSinceEpoch(
            location.timeZone,
            job.at!,
          );
          final friday =
              prayer == PrayerName.dhuhr &&
              local.weekday == DateTime.friday &&
              [
                PrayerReminderSound.prayerNow,
                PrayerReminderSound.prayerNowOld,
              ].contains(sound);
          expect(
            job.reminderVariant,
            '${sound.variant}${friday ? '-friday' : ''}',
          );
          expect(
            job.voice,
            prayerReminderVoiceId('guest', prayer, variant: sound.variant!),
          );
          expect(
            File(
              prayerReminderAsset(job.reminderVariant!, prayer),
            ).existsSync(),
            isTrue,
          );
        }
        // Changing the pre-adhan sound does not select it for the adhan itself.
        expect(
          jobs
              .where((j) => j.id.endsWith(':0'))
              .every(
                (j) =>
                    j.reminderVariant == null && j.alertMode != 'reminderVoice',
              ),
          isTrue,
        );
        expect(
          controller.reminderVariantFor(
            PrayerName.dhuhr,
            DateTime.utc(2026, 11, 5, 22, 30),
          ),
          [
                PrayerReminderSound.prayerNow,
                PrayerReminderSound.prayerNowOld,
              ].contains(sound)
              ? '${sound.variant}-friday'
              : sound.variant,
        );
      }
      expect(
        prayerReminderVoiceId('guest', PrayerName.fajr, variant: 'pn-current'),
        isNot(prayerReminderVoiceId('guest', PrayerName.fajr)),
      );
      expect(
        prayerReminderVoiceId('guest', PrayerName.fajr, variant: 'pn-current'),
        isNot(
          prayerReminderVoiceId(
            'user:2',
            PrayerName.fajr,
            variant: 'pn-current',
          ),
        ),
      );
    },
  );

  test(
    'all 19 original recordings and iOS notification sounds are bundled intact',
    () async {
      final manifest =
          jsonDecode(
                File(
                  'assets/prayer/reminders/prayer-now-provenance.json',
                ).readAsStringSync(),
              )
              as Map;
      final clips = manifest['clips'] as List;
      expect(clips.length, 19);
      final project = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final assets = <String>{};
      for (final sound in PrayerReminderSound.values.skip(1)) {
        for (final prayer in PrayerName.values.where(
          (p) => p != PrayerName.sunrise,
        )) {
          assets.add(prayerReminderAsset(sound.variant!, prayer));
        }
      }
      assets.add(prayerReminderAsset('pn-current-friday', PrayerName.dhuhr));
      assets.add(prayerReminderAsset('pn-old-friday', PrayerName.dhuhr));
      expect(assets, clips.map((c) => c['asset']).toSet());
      for (final clip in clips) {
        final bytes = File(clip['asset'] as String).readAsBytesSync();
        final bundled = await rootBundle.load(clip['asset'] as String);
        expect(
          sha256
              .convert(
                bundled.buffer.asUint8List(
                  bundled.offsetInBytes,
                  bundled.lengthInBytes,
                ),
              )
              .toString(),
          clip['sha256'],
        );
        expect(sha256.convert(bytes).toString(), clip['sha256']);
        expect(bytes.length, clip['bytes']);
        final name = clip['ios_sound'] as String;
        final caf = File('ios/Runner/PrayerReminders/$name').readAsBytesSync();
        expect(sha256.convert(caf).toString(), clip['ios_sha256']);
        expect(_cafDuration(caf), inInclusiveRange(0.1, 29.9));
        expect(project, contains('path = "PrayerReminders/$name"'));
        expect(project, contains('/* $name in Resources */,'));
      }
      expect(
        () => prayerReminderAsset('../outside', PrayerName.fajr),
        throwsFormatException,
      );
      expect(
        () => prayerReminderAsset('pn-current-friday', PrayerName.asr),
        throwsFormatException,
      );
      expect(
        () => prayerReminderAsset('pn-current', PrayerName.sunrise),
        throwsFormatException,
      );
    },
  );
}

double _cafDuration(Uint8List bytes) {
  expect(ascii.decode(bytes.sublist(0, 4)), 'caff');
  final data = ByteData.sublistView(bytes);
  double? rate;
  int? bytesPerPacket, framesPerPacket, audioBytes;
  for (var offset = 8; offset + 12 <= bytes.length;) {
    final kind = ascii.decode(bytes.sublist(offset, offset + 4));
    final size = data.getInt64(offset + 4);
    expect(size, greaterThanOrEqualTo(0));
    expect(offset + 12 + size, lessThanOrEqualTo(bytes.length));
    if (kind == 'desc') {
      rate = data.getFloat64(offset + 12);
      bytesPerPacket = data.getUint32(offset + 28);
      framesPerPacket = data.getUint32(offset + 32);
    } else if (kind == 'data') {
      audioBytes = size - 4;
    }
    offset += 12 + size;
  }
  return audioBytes! / bytesPerPacket! * framesPerPacket! / rate!;
}
