import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/prayer/data/adhan_library.dart';
import 'package:haq_app/features/prayer/data/prayer_alert.dart';
import 'package:haq_app/features/prayer/data/prayer_controller.dart';
import 'package:haq_app/features/prayer/data/prayer_models.dart';
import 'package:haq_app/features/prayer/presentation/qibla_dial.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreviewAudio implements AdhanPreviewAudio {
  final calls = <Uri>[];
  Completer<void>? active;
  @override
  Future<void> play(Uri uri) {
    calls.add(uri);
    return (active = Completer<void>()).future;
  }

  @override
  Future<void> stop() async {
    if (active?.isCompleted == false) active!.complete();
  }

  @override
  Future<void> dispose() => stop();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final place = PrayerLocation(
    latitude: 31.53,
    longitude: 35.1,
    zone: 'Asia/Hebron',
    label: 'اختبار',
  );
  test(
    'new adhan preferences and actual location names preserve legacy data and isolate human clips',
    () async {
      final legacy = PrayerConfig(location: place).toJson()
        ..remove('defaultAlert')
        ..remove('adhanVolume')
        ..remove('showAdhanScreen')
        ..remove('iqamaMinutes');
      final old = PrayerConfig.fromJson(legacy);
      expect(old.adhanVolume, 100);
      expect(old.iqamaMinutes, 15);
      final config = old.copyWith(
        adhanVolume: 70,
        showAdhanScreen: false,
        iqamaMinutes: 20,
        defaultAlert: const PrayerAlert(
          mode: PrayerAlertMode.adhan,
          voice: 'nafees',
        ),
      );
      final restored = PrayerConfig.fromJson(config.toJson());
      expect(restored.adhanVolume, 70);
      expect(restored.showAdhanScreen, false);
      expect(restored.iqamaMinutes, 20);
      expect(restored.alert(PrayerName.asr).voice, 'nafees');
      expect(restored.alert(PrayerName.sunrise).mode, PrayerAlertMode.chime);
      final location = PrayerLocation(
        latitude: 31.53,
        longitude: 35.1,
        zone: 'Asia/Hebron',
        label: 'الخليل، فلسطين',
        city: 'الخليل',
        country: 'فلسطين',
      );
      expect(PrayerLocation.fromJson(location.toJson()).city, 'الخليل');
      expect(PrayerLocation.fromJson(location.toJson()).country, 'فلسطين');
      final guest = prayerReminderVoiceId('guest', PrayerName.fajr);
      expect(guest, matches(RegExp(r'^reminder-[0-9a-f]{16}-fajr$')));
      expect(guest, isNot(prayerReminderVoiceId('user:1', PrayerName.fajr)));
      expect(
        () => PrayerConfig.fromJson({...config.toJson(), 'adhanVolume': 101}),
        throwsFormatException,
      );
      SharedPreferences.setMockInitialValues({});
      final c = PrayerController(
        await SharedPreferences.getInstance(),
        scopeOf: () => 'guest',
        autoTick: false,
        clock: () => DateTime.utc(2026, 10, 27, 10),
      );
      addTearDown(c.dispose);
      await c.save(
        restored.copyWith(notifications: true, enabledPrayers: ['fajr']),
      );
      final jobs = c.reminderJobs();
      final audio = jobs.firstWhere((j) => j.alertMode == 'adhan');
      expect(audio.toJson()['volume'], 70);
      expect(audio.toJson()['showAdhanScreen'], false);
      expect(audio.toJson()['iqamaMinutes'], 20);
      expect(
        jobs.firstWhere((j) => j.alertMode == 'reminderVoice').voice,
        guest,
      );
    },
  );
  test(
    'expanded named catalog preserves old voices, uses unique IDs and pinned HTTPS audio, and round-trips alerts',
    () {
      expect(adhanVoices.length, greaterThan(200));
      expect(adhanVoices.map((v) => v.id).toSet().length, adhanVoices.length);
      expect(adhanVoices.take(4).map((v) => v.id), [
        'alafasy',
        'nafees',
        'mustafa',
        'zahrani',
      ]);
      for (final voice in adhanVoices) {
        expect(voice.uri.scheme, 'https');
        expect(voice.uri.path, endsWith('.mp3'));
        expect(voice.name.trim(), isNotEmpty);
        expect(
          PrayerAlert.fromJson(PrayerAlert(voice: voice.id).toJson()).voice,
          voice.id,
        );
      }
      expect(adhanVoices.any((v) => v.name.contains('عبد الباسط')), true);
      expect(adhanVoices.any((v) => v.name.contains('ملا')), true);
    },
  );
  test(
    'per-prayer audio modes survive save and old configuration remains readable',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = PrayerController(
        prefs,
        scopeOf: () => 'guest',
        autoTick: false,
        clock: () => DateTime.utc(2026, 10, 27, 10),
      );
      addTearDown(c.dispose);
      await c.save(
        PrayerConfig(
          location: place,
          notifications: true,
          enabledPrayers: ['fajr'],
          alerts: const {
            'fajr': PrayerAlert(
              mode: PrayerAlertMode.adhan,
              voice: 'nafees',
              full: true,
            ),
          },
        ),
      );
      final restored = PrayerConfig.fromJson(
        jsonDecode(prefs.getString('prayer.config.v1.guest')!) as Map,
      );
      expect(restored.alert(PrayerName.fajr).voice, 'nafees');
      expect(restored.alert(PrayerName.fajr).full, true);
      final legacy = restored.toJson()..remove('alerts');
      expect(PrayerConfig.fromJson(legacy).alerts, isEmpty);
      expect(
        () => PrayerAlert.fromJson({
          'mode': 'adhan',
          'voice': '../secret',
          'full': true,
        }),
        throwsFormatException,
      );
      expect(
        () => PrayerAlert.fromJson({
          'mode': 'unknown',
          'voice': 'nafees',
          'full': true,
        }),
        throwsArgumentError,
      );
    },
  );
  test(
    '15-minute warning is named and only the exact prayer carries audio metadata',
    () async {
      SharedPreferences.setMockInitialValues({});
      final c = PrayerController(
        await SharedPreferences.getInstance(),
        scopeOf: () => 'guest',
        autoTick: false,
        clock: () => DateTime.utc(2026, 10, 27, 10),
      );
      addTearDown(c.dispose);
      await c.save(
        PrayerConfig(
          location: place,
          notifications: true,
          enabledPrayers: ['fajr'],
          alerts: const {
            'fajr': PrayerAlert(
              mode: PrayerAlertMode.adhan,
              voice: 'nafees',
              full: true,
            ),
          },
        ),
      );
      final jobs = c.reminderJobs(days: 1);
      expect(jobs, hasLength(2));
      final at = jobs.singleWhere((j) => j.alertMode == 'adhan');
      final before = jobs.singleWhere((j) => j.alertMode == 'reminderVoice');
      expect(at.at! - before.at!, const Duration(minutes: 15).inMilliseconds);
      expect(before.title, 'اقترب أذان الفجر');
      expect(
        before.toJson()['voice'],
        prayerReminderVoiceId('guest', PrayerName.fajr),
      );
      expect(at.toJson()['voice'], 'nafees');
      expect(at.toJson()['fullAdhan'], true);
    },
  );
  test('additional night times use the following Fajr across civil days', () {
    final config = PrayerConfig(location: place);
    final now = DateTime.utc(2026, 10, 27, 10);
    final day = calculatePrayerDay(config, now);
    final next = calculatePrayerDay(config, DateTime.utc(2026, 10, 28, 10));
    final start = day.moments
        .singleWhere((m) => m.name == PrayerName.maghrib)
        .time;
    final end = next.moments.singleWhere((m) => m.name == PrayerName.fajr).time;
    final extra = additionalPrayerTimes(config, now);
    expect(
      extra['منتصف الليل']!.millisecondsSinceEpoch,
      (start.millisecondsSinceEpoch + end.millisecondsSinceEpoch) ~/ 2,
    );
    expect(
      extra['الثلث الأخير من الليل']!.isAfter(extra['منتصف الليل']!),
      true,
    );
    expect(extra['الثلث الأخير من الليل']!.isBefore(end), true);
    expect(prayerClockLabel(DateTime(2026, 1, 1, 0, 5)), '12:05 ص');
  });
  group('verified audio cache', () {
    late Directory temp;
    late Dio dio;
    late AdhanLibrary library;
    late PreviewAudio audio;
    final valid = List<int>.filled(1200, 0)..setRange(0, 3, [73, 68, 51]);
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('haq-adhan-test-');
      dio = Dio();
      audio = PreviewAudio();
      library = AdhanLibrary(
        dio: dio,
        audio: audio,
        directory: () async => temp,
        prepare: (_, _) async => true,
      );
    });
    tearDown(() async {
      library.dispose();
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    test(
      'download commits a hash receipt and restored cache rejects tampering',
      () async {
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) => h.resolve(
              Response(
                requestOptions: o,
                data: valid,
                statusCode: 200,
                headers: Headers.fromMap({
                  'content-type': ['audio/mpeg'],
                }),
              ),
            ),
          ),
        );
        expect(await library.download(adhanVoices.first), true);
        expect(library.downloaded, contains('alafasy'));
        final restored = AdhanLibrary(
          directory: () async => temp,
          audio: PreviewAudio(),
        );
        await restored.initialize();
        expect(restored.downloaded, contains('alafasy'));
        restored.dispose();
        await File(
          '${temp.path}/adhans/alafasy.mp3',
        ).writeAsBytes(List.filled(1200, 1));
        final corrupt = AdhanLibrary(
          directory: () async => temp,
          audio: PreviewAudio(),
        );
        await corrupt.initialize();
        expect(corrupt.downloaded, isEmpty);
        corrupt.dispose();
      },
    );
    test(
      'HTML disguised as MP3 and non-catalogue paths cannot be saved',
      () async {
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) => h.resolve(
              Response(
                requestOptions: o,
                data: List.filled(1300, 65),
                statusCode: 200,
                headers: Headers.fromMap({
                  'content-type': ['text/html'],
                }),
              ),
            ),
          ),
        );
        expect(await library.download(adhanVoices.first), false);
        expect(library.downloaded, isEmpty);
        expect(
          await library.download(
            const AdhanVoice('../escape', 'fake', 'bad.mp3'),
          ),
          false,
        );
        expect(await library.prepareVoice('nafees'), false);
        expect(library.error, contains('نزّل'));
      },
    );
    test(
      'late preview completion cannot clear a newer preview and stopping completes it',
      () async {
        final first = library.preview(adhanVoices[0]);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final second = library.preview(adhanVoices[1]);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(library.playing, 'nafees');
        await first;
        expect(library.playing, 'nafees');
        await library.stop();
        await second;
        expect(library.playing, isNull);
        expect(audio.calls.map((u) => u.host), everyElement('cdn.aladhan.com'));
      },
    );
  });
  testWidgets(
    'compass crosses zero on shortest path and movement effects settle',
    (tester) async {
      Future<void> show(double? angle, {bool reduced = false}) =>
          tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: Center(
                  child: SizedBox(width: 300, child: QiblaDial(angle: angle)),
                ),
              ),
            ),
          );
      QiblaDialPainter painter() =>
          tester
                  .widget<CustomPaint>(find.byKey(const ValueKey('qibla-dial')))
                  .painter!
              as QiblaDialPainter;
      await show(179);
      await tester.pumpAndSettle();
      await show(-179);
      await tester.pump(const Duration(milliseconds: 80));
      expect(painter().angle, greaterThan(179));
      expect(painter().angle, lessThanOrEqualTo(181));
      expect(painter().motion, greaterThan(0));
      await tester.pumpAndSettle();
      expect(painter().motion, 0);
      expect(painter().angle, closeTo(181, .001));
      await show(null);
      await tester.pump();
      expect(painter().angle, isNull);
      expect(painter().motion, 0);
      await show(40, reduced: true);
      await tester.pumpAndSettle();
      expect(painter().motion, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
