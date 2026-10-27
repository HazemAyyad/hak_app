import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/prayer/data/place_catalog.dart';
import 'package:haq_app/features/prayer/data/prayer_controller.dart';
import 'package:haq_app/features/prayer/data/prayer_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.prayer.refresh');
  final country = PlaceCountry('PS', 'فلسطين', 'Palestine');
  final catalog = PlaceCatalog(
    [country],
    [
      PlaceCity(
        id: 285066,
        name: 'الخليل',
        english: 'Hebron',
        country: country,
        latitude: 31.52935,
        longitude: 35.0938,
        zone: 'Asia/Hebron',
        population: 160470,
      ),
    ],
  );
  late PrayerController c;
  late ValueNotifier<String> account;
  late DateTime now;
  Completer<Map<String, String>?>? names;
  var nativeNames = true;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 10, 27, 9);
    account = ValueNotifier('guest');
    names = null;
    nativeNames = true;
    c = PrayerController(
      prefs,
      scopeOf: () => account.value,
      account: account,
      autoTick: false,
      channel: channel,
      clock: () => now,
      placeCatalog: () async => catalog,
      timeZoneAt: (_, _) async => 'Asia/Hebron',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestLocation') {
            return {
              'lat': 31.53,
              'lng': 35.10,
              'accuracy': 20.0,
              'measured': now.millisecondsSinceEpoch,
              'zone': 'Europe/London',
            };
          }
          if (call.method == 'reverseGeocode') {
            if (names != null) return names!.future;
            return nativeNames ? {'city': 'الخليل', 'country': 'فلسطين'} : null;
          }
          return null;
        });
  });
  tearDown(() {
    c.dispose();
    account.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'GPS saves real city/country and point timezone, refresh reports progress then success with fresh timestamp',
    () async {
      names = Completer();
      final job = c.locate();
      await Future<void>.delayed(Duration.zero);
      expect(c.locating, true);
      expect(c.locationNotice, isNull);
      names!.complete({'city': 'الخليل', 'country': 'فلسطين'});
      await job;
      expect(c.locating, false);
      expect(c.config.location?.label, 'الخليل، فلسطين');
      expect(c.config.location?.zone, 'Asia/Hebron');
      expect(c.config.location?.latitude, 31.53);
      expect(c.locationNotice, contains('تم تحديث الموقع'));
      names = null;
      now = now.add(const Duration(minutes: 2));
      await c.locate();
      expect(c.config.location?.measuredAt, now);
      final reopened = PrayerController(
        c.preferences,
        scopeOf: () => 'guest',
        autoTick: false,
      );
      expect(reopened.config.location?.label, 'الخليل، فلسطين');
      reopened.dispose();
      await c.save(
        c.config.copyWith(
          location: PrayerLocation(
            latitude: 32.22,
            longitude: 35.25,
            zone: 'Asia/Hebron',
            label: 'نابلس، فلسطين',
          ),
        ),
      );
      expect(
        c.locationNotice,
        isNull,
      ); // Never show the previous GPS success after a manual change.
    },
  );

  test(
    'offline naming retains measured point with explicitly approximate city, not a fake geocoder success',
    () async {
      nativeNames = false;
      await c.locate();
      expect(c.config.location?.label, 'قرب الخليل، فلسطين');
      expect(c.config.location?.accuracy, 20);
      expect(c.locationNotice, contains('تقريبي'));
    },
  );

  test(
    'geocoder reply after account switch cannot set another account location or success status',
    () async {
      names = Completer();
      final job = c.locate();
      await Future<void>.delayed(Duration.zero);
      account.value = 'account.42';
      names!.complete({'city': 'الخليل', 'country': 'فلسطين'});
      await job;
      expect(c.config.location, isNull);
      expect(c.locationNotice, isNull);
      expect(c.locating, false);
    },
  );

  test(
    'all prayer moments display 12-hour AM/PM including midnight, noon and evening',
    () {
      for (final (hour, label) in [
        (0, '12:05 ص'),
        (12, '12:05 م'),
        (13, '1:05 م'),
        (23, '11:05 م'),
      ]) {
        final moment = PrayerMoment(
          PrayerName.isha,
          tz.TZDateTime(tz.getLocation('Asia/Hebron'), 2026, 10, 27, hour, 5),
        );
        expect(moment.label, label);
        expect(prayerClockLabel(moment.time), label);
      }
    },
  );
}
