import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/prayer/data/prayer_models.dart';
import 'package:haq_app/features/prayer/data/prayer_controller.dart';
import 'package:haq_app/features/prayer/data/heading_controller.dart';
import 'package:haq_app/features/prayer/data/mosque_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initializePrayerZones();
  PrayerLocation raleigh() => PrayerLocation(
    latitude: 35.775,
    longitude: -78.6336,
    zone: 'America/New_York',
    label: 'Raleigh',
  );
  PrayerLocation hebron() => PrayerLocation(
    latitude: 31.53,
    longitude: 35.10,
    zone: 'Asia/Hebron',
    label: 'موقع يدوي للاختبار',
  );
  late SharedPreferences prefs;
  late PrayerController c;
  late ValueNotifier<String> owner;
  late DateTime now;
  test(
    'previous civil day Isha remains next after midnight at high latitude',
    () {
      final location = PrayerLocation(
        latitude: 64.1466,
        longitude: -21.9426,
        zone: 'Atlantic/Reykjavik',
        label: 'Reykjavik',
      );
      final config = PrayerConfig(location: location);
      final day = calculatePrayerDay(config, DateTime.utc(2026, 6, 21, 12));
      final isha = day.obligatory.last;
      expect(isha.time.day, 22);
      expect(
        nextPrayer(config, isha.time.subtract(const Duration(minutes: 5))).time,
        isha.time,
      );
    },
  );
  const channel = MethodChannel('test.haq.prayer');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    owner = ValueNotifier('guest');
    now = DateTime.utc(2026, 10, 26, 10);
    c = PrayerController(
      prefs,
      scopeOf: () => owner.value,
      account: owner,
      clock: () => now,
      channel: channel,
      autoTick: false,
    );
  });
  tearDown(() async {
    await c.flush();
    c.dispose();
    owner.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'unknown location produces no prayer times, countdown or notifications',
    () {
      expect(c.config.location, isNull);
      expect(c.today, isNull);
      expect(c.upcoming, isNull);
      expect(c.countdown, '--:--:--');
      expect(c.reminderJobs(), isEmpty);
    },
  );
  test(
    'Raleigh reference fixture matches all six times, not implementation-derived guesses',
    () {
      // Primary reference: batoulapps/adhan-js test/adhan.test.ts (2015-07-12).
      final config = PrayerConfig(
        location: raleigh(),
        method: PrayerMethod.northAmerica,
        hanafi: true,
      );
      final day = calculatePrayerDay(config, DateTime.utc(2015, 7, 12, 12));
      expect(day.moments.map((e) => e.label), [
        '04:42',
        '06:08',
        '13:21',
        '18:22',
        '20:32',
        '21:57',
      ]);
    },
  );
  test(
    'Hanafi changes Asr only and per-prayer correction changes exactly the selected time',
    () {
      final config = PrayerConfig(location: raleigh());
      final date = DateTime.utc(2015, 7, 12, 12);
      final a = calculatePrayerDay(config, date),
          b = calculatePrayerDay(config.copyWith(hanafi: true), date);
      expect(b.moments[3].time.isAfter(a.moments[3].time), true);
      for (final i in [0, 1, 2, 4, 5]) {
        expect(a.moments[i].time, b.moments[i].time);
      }
      final changed = calculatePrayerDay(
        config.copyWith(adjustments: {'fajr': 7}),
        date,
      );
      expect(
        changed.moments.first.time.difference(a.moments.first.time).inMinutes,
        7,
      );
      expect(
        changed.moments.skip(1).map((e) => e.time),
        a.moments.skip(1).map((e) => e.time),
      );
    },
  );
  test(
    'selected timezone determines civil day and DST independently of host device',
    () {
      final config = PrayerConfig(location: hebron());
      final a = calculatePrayerDay(config, DateTime.utc(2026, 10, 20, 12));
      final b = calculatePrayerDay(config, DateTime.utc(2026, 10, 28, 12));
      expect(a.moments.first.time.timeZoneOffset, const Duration(hours: 3));
      expect(b.moments.first.time.timeZoneOffset, const Duration(hours: 2));
      final east = PrayerConfig(
        location: PrayerLocation(
          latitude: -36.85,
          longitude: 174.76,
          zone: 'Pacific/Auckland',
          label: 'Auckland',
        ),
      );
      final local = calculatePrayerDay(east, DateTime.utc(2026, 1, 1, 18));
      expect(local.date.day, 2);
      expect(local.date.month, 1);
      expect(local.moments.every((m) => m.time.day == 2), true);
    },
  );
  test('after Isha next prayer is next-day Fajr, including year rollover', () {
    final config = PrayerConfig(location: raleigh());
    final place = raleigh();
    final late = tz.TZDateTime(place.timeZone, 2026, 12, 31, 23, 59);
    final next = nextPrayer(config, late);
    expect(next.name, PrayerName.fajr);
    expect(next.time.year, 2027);
    expect(next.time.day, 1);
  });
  test(
    'Qibla points toward known bearing and rejects undefined bearing at Kaaba',
    () {
      final ny = PrayerLocation(
        latitude: 40.7128,
        longitude: -74.0059,
        zone: 'America/New_York',
        label: 'NY',
      );
      expect(qiblaBearing(ny), closeTo(58.48, .1));
      expect(headingDifference(1, 359), 2);
      expect(headingDifference(359, 1), -2);
      final kaaba = PrayerLocation(
        latitude: 21.4225241,
        longitude: 39.8261818,
        zone: 'Asia/Riyadh',
        label: 'Kaaba',
      );
      expect(() => qiblaBearing(kaaba), throwsFormatException);
    },
  );
  test(
    'persisted preferences reopen; accounts, reset and corrupt payload stay isolated',
    () async {
      await c.save(
        PrayerConfig(
          location: hebron(),
          method: PrayerMethod.jordan,
          adjustments: {'fajr': -3},
          notifications: true,
        ),
      );
      await prefs.reload();
      final reopened = PrayerController(
        prefs,
        scopeOf: () => owner.value,
        autoTick: false,
        clock: () => now,
      );
      expect(reopened.config.method, PrayerMethod.jordan);
      expect(reopened.config.adjustments['fajr'], -3);
      reopened.dispose();
      owner.value = 'account.42';
      expect(c.config.location, isNull);
      expect(c.today, isNull);
      await c.save(PrayerConfig(location: raleigh()));
      owner.value = 'guest';
      expect(c.config.location!.zone, 'Asia/Hebron');
      await c.reset();
      expect(c.config.location, isNull);
      owner.value = 'account.42';
      expect(c.config.location!.zone, 'America/New_York');
      await prefs.setString('prayer.config.v1.account.2', 'broken');
      owner.value = 'account.2';
      expect(c.error, isNotNull);
      expect(await c.save(PrayerConfig(location: hebron())), false);
      expect(prefs.getString('prayer.config.v1.account.2'), 'broken');
      await c.reset();
      expect(c.error, isNull);
    },
  );
  test(
    'denial, stale location and late reply never fabricate or overwrite coordinates',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'denied');
      });
      await c.locate();
      expect(c.config.location, isNull);
      expect(c.error, contains('لم يُسمح'));
      await c.save(PrayerConfig(location: hebron()));
      final reply = Completer<Map<String, Object>>();
      messenger.setMockMethodCallHandler(channel, (call) => reply.future);
      final locating = c.locate();
      await Future<void>.delayed(Duration.zero);
      owner.value = 'account.42';
      reply.complete({
        'lat': 35.0,
        'lng': 35.0,
        'zone': 'Asia/Hebron',
        'accuracy': 20.0,
        'measured': now.millisecondsSinceEpoch,
      });
      await locating;
      expect(c.config.location, isNull);
      expect(c.locating, false);
    },
  );
  test(
    'GPS success preserves measured accuracy and timezone; stale samples are rejected',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var measured = now;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'lat': 31.53,
          'lng': 35.1,
          'accuracy': 40.0,
          'zone': 'Asia/Hebron',
          'measured': measured.millisecondsSinceEpoch,
        },
      );
      await c.locate();
      expect(c.config.location!.fromDevice, true);
      expect(c.config.location!.accuracy, 40);
      expect(c.today, isNotNull);
      measured = now.subtract(const Duration(hours: 1));
      await c.locate();
      expect(c.config.location!.measuredAt, now);
      expect(c.error, isNotNull);
    },
  );
  test(
    'bounded UTC prayer jobs preserve identity across ticks and skip sunrise',
    () async {
      await c.save(
        PrayerConfig(
          location: hebron(),
          notifications: true,
          beforeMinutes: 10,
          afterMinutes: 5,
        ),
      );
      final jobs = c.reminderJobs();
      expect(jobs.length, 14 * 5 * 3);
      expect(jobs.every((j) => j.at != null), true);
      expect(jobs.any((j) => j.id.contains('sunrise')), false);
      expect(jobs.map((j) => j.id).toSet().length, jobs.length);
      final ids = jobs.map((j) => j.id).toList();
      now = now.add(const Duration(seconds: 1));
      c.tick();
      expect(c.reminderJobs().map((j) => j.id), ids);
      await c.save(c.config.copyWith(notifications: false));
      expect(c.reminderJobs(), isEmpty);
    },
  );
  test(
    'Hijri conversion has independent known date and day correction bounds',
    () {
      expect(
        prayerHijriDate(DateTime.utc(2018, 11, 12)),
        '4 ربيع الأول 1440 هـ',
      );
      expect(
        prayerHijriDate(DateTime.utc(2018, 11, 12), correction: 1),
        '5 ربيع الأول 1440 هـ',
      );
      expect(
        () => PrayerLocation(
          latitude: double.nan,
          longitude: 0,
          zone: 'Etc/UTC',
          label: 'x',
        ),
        throwsFormatException,
      );
      expect(() => PrayerConfig(beforeMinutes: 61), throwsFormatException);
      expect(
        () => PrayerConfig(adjustments: {'asr': 31}),
        throwsFormatException,
      );
    },
  );
  test(
    'heading rejects unreliable magnetic-only samples and smooths wraparound',
    () async {
      final events = StreamController<dynamic>();
      final heading = HeadingController(readings: (_) => events.stream);
      heading.start(hebron());
      events.add({'degrees': 359.0, 'accuracy': 3, 'trueNorth': true});
      await Future<void>.delayed(Duration.zero);
      expect(heading.usable, true);
      events.add({'degrees': 1.0, 'accuracy': 3, 'trueNorth': true});
      await Future<void>.delayed(Duration.zero);
      expect(heading.degrees, closeTo(359.5, .01));
      events.add({'degrees': 20.0, 'accuracy': 0, 'trueNorth': true});
      await Future<void>.delayed(Duration.zero);
      expect(heading.usable, false);
      events.add({'degrees': 20.0, 'accuracy': 3, 'trueNorth': false});
      await Future<void>.delayed(Duration.zero);
      expect(heading.usable, false);
      heading.stop();
      expect(heading.degrees, isNull);
      heading.dispose();
      await events.close();
    },
  );
  test(
    'mosque parser validates religion, coordinates, deduplication, radius, names and straight-line order',
    () {
      final place = hebron();
      Map<String, Object> node(
        int id,
        double lat, {
        String religion = 'muslim',
      }) => {
        'type': 'node',
        'id': id,
        'lat': lat,
        'lon': 35.10,
        'tags': {
          'amenity': 'place_of_worship',
          'religion': religion,
          'name:ar': 'مسجد $id',
        },
      };
      final source = jsonEncode({
        'elements': [
          node(2, 31.54),
          node(1, 31.531),
          node(2, 31.54),
          node(3, 31.6),
          node(4, 31.531, religion: 'christian'),
          {
            'type': 'way',
            'id': 5,
            'center': {'lat': 31.532, 'lon': 35.1},
            'tags': {'amenity': 'place_of_worship', 'religion': 'muslim'},
          },
        ],
      });
      final list = parseMosques(source, place, 3000);
      expect(list.map((e) => e.id), ['node/1', 'way/5', 'node/2']);
      expect(list[1].name, contains('دون اسم'));
      expect(list.first.mapUrl.host, 'www.openstreetmap.org');
      expect(
        () => parseMosques('{"remark":"timeout","elements":[]}', place, 3000),
        throwsFormatException,
      );
    },
  );
  test(
    'mosque requests are explicit, rate limited, bounded and do not silently retry',
    () async {
      final dio = Dio();
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            expect(options.uri.host, 'overpass-api.de');
            expect(options.data['data'], contains('around:3000'));
            handler.resolve(
              Response(requestOptions: options, data: '{"elements":[]}'),
            );
          },
        ),
      );
      final repository = MosqueRepository(dio: dio, clock: () => now);
      expect(requests, 0);
      expect(await repository.search(hebron()), isEmpty);
      expect(requests, 1);
      await expectLater(repository.search(hebron()), throwsStateError);
      expect(requests, 1);
      now = now.add(const Duration(minutes: 1));
      await repository.search(hebron());
      expect(requests, 2);
      repository.dispose();
    },
  );
}
