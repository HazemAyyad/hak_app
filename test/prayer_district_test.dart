import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/prayer/data/place_catalog.dart';
import 'package:haq_app/features/prayer/data/prayer_controller.dart';
import 'package:haq_app/features/prayer/data/prayer_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.haq.district');
  late PlaceCatalog catalog;
  late PrayerController controller;
  final now = DateTime.utc(2026, 10, 29, 20);
  Map<String, Object?>? names;
  var accuracy = 20.0, precise = true;
  var latitude = 31.50981, longitude = 34.42739;
  var pointZone = 'Asia/Gaza';
  setUpAll(() async {
    catalog = await PlaceCatalog.load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    accuracy = 20;
    precise = true;
    latitude = 31.50981;
    longitude = 34.42739;
    pointZone = 'Asia/Gaza';
    names = {
      'district': 'الشيخ عجلين',
      'city': 'غزة',
      'country': 'فلسطين',
      'countryCode': 'PS',
    };
    controller = PrayerController(
      await SharedPreferences.getInstance(),
      scopeOf: () => 'guest',
      channel: channel,
      clock: () => now,
      autoTick: false,
      placeCatalog: () async => catalog,
      timeZoneAt: (_, _) async => pointZone,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestLocation') {
            return {
              'lat': latitude,
              'lng': longitude,
              'accuracy': accuracy,
              'precise': precise,
              'measured': now.millisecondsSinceEpoch,
              'zone': 'Europe/London',
            };
          }
          if (call.method == 'reverseGeocode') return names;
          return null;
        });
  });
  tearDown(() {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'public neighborhood asset includes Sheikh Ijlin with pinned data and a Gaza city hint',
    () {
      final manifest =
          jsonDecode(
                File(
                  'assets/prayer_places/districts-manifest.json',
                ).readAsStringSync(),
              )
              as Map;
      final bytes = File(
        'assets/prayer_places/districts.json',
      ).readAsBytesSync();
      expect(sha256.convert(bytes).toString(), manifest['assetSha256']);
      expect(catalog.districts.length, manifest['districtCount']);
      expect(
        catalog.districts.map((d) => d.id).toSet().length,
        catalog.districts.length,
      );
      final district = catalog.nearbyDistrict(
        31.50981,
        34.42739,
        accuracy: 20,
      )!;
      expect(district.id, 8041220);
      expect(district.name, 'الشيخ عجلين');
      expect(district.city, 'غزة');
      expect(district.country.code, 'PS');
      expect(district.latitude, 31.50981);
    },
  );

  test(
    'system neighborhood displays before city and survives reopening without changing measured coordinates or preferences',
    () async {
      await controller.save(
        controller.config.copyWith(beforeMinutes: 12, adhanVolume: 65),
      );
      await controller.locate();
      final location = controller.config.location!;
      expect(location.label, 'الشيخ عجلين، غزة، فلسطين');
      expect(location.district, 'الشيخ عجلين');
      expect(location.city, 'غزة');
      expect(location.approximateName, false);
      expect(location.latitude, 31.50981);
      expect(location.longitude, 34.42739);
      expect(location.zone, 'Asia/Gaza');
      expect(location.accuracy, 20);
      expect(controller.config.beforeMinutes, 12);
      expect(controller.config.adhanVolume, 65);
      final reopened = PrayerController(
        controller.preferences,
        scopeOf: () => 'guest',
        autoTick: false,
      );
      expect(reopened.config.location!.toJson(), location.toJson());
      reopened.dispose();
    },
  );

  test(
    'offline naming uses the nearby neighborhood as an explicit hint while retaining the GPS point',
    () async {
      names = null;
      await controller.locate();
      final location = controller.config.location!;
      expect(location.label, 'قرب الشيخ عجلين، غزة، فلسطين');
      expect(location.district, 'الشيخ عجلين');
      expect(location.approximateName, true);
      expect(location.latitude, 31.50981);
      expect(location.longitude, 34.42739);
      expect(controller.locationNotice, contains('تقريبي'));
    },
  );

  test(
    'city-only system reply can be supplemented without claiming a neighborhood boundary',
    () async {
      names = {'city': 'غزة', 'country': 'فلسطين', 'countryCode': 'PS'};
      await controller.locate();
      expect(controller.config.location!.label, 'قرب الشيخ عجلين، غزة، فلسطين');
      expect(controller.config.location!.approximateName, true);
    },
  );

  test(
    'coarse permission or poor accuracy cannot display a neighborhood as a precise fix',
    () async {
      for (final sample in [(1000.0, true), (20.0, false)]) {
        accuracy = sample.$1;
        precise = sample.$2;
        await controller.locate();
        expect(controller.config.location!.district, isNull);
        expect(controller.config.location!.label, 'غزة، فلسطين');
        expect(controller.locationNotice, contains('موقعًا أدق'));
      }
    },
  );

  test(
    'distant, cross-country and competing neighborhood hints are rejected',
    () {
      expect(catalog.nearbyDistrict(31.50981, 34.42739, accuracy: 201), isNull);
      expect(
        catalog.nearbyDistrict(
          31.50981,
          34.42739,
          accuracy: 20,
          countryCode: 'EG',
        ),
        isNull,
      );
      expect(catalog.nearbyDistrict(0, 0, accuracy: 20), isNull);
      final country = PlaceCountry('PS', 'فلسطين', 'Palestine');
      final adjacent = PlaceCatalog(
        [country],
        [],
        districts: [
          PlaceDistrict(
            id: 1,
            name: 'A',
            country: country,
            latitude: 31.5,
            longitude: 34.4,
          ),
          PlaceDistrict(
            id: 2,
            name: 'B',
            country: country,
            latitude: 31.5,
            longitude: 34.4005,
          ),
        ],
      );
      expect(adjacent.nearbyDistrict(31.5, 34.40025, accuracy: 40), isNull);
      expect(adjacent.nearbyDistrict(31.6, 34.4, accuracy: 20), isNull);
    },
  );

  test(
    'duplicate city and district names display once; legacy saved locations remain readable',
    () async {
      names = {'city': 'غزة', 'district': 'غزّة', 'country': 'فلسطين'};
      await controller.locate();
      expect(controller.config.location!.label, 'غزّة، فلسطين');
      final old = PrayerLocation.fromJson({
        'lat': 31.5,
        'lng': 34.4,
        'zone': 'Asia/Gaza',
        'label': 'غزة، فلسطين',
        'city': 'غزة',
        'country': 'فلسطين',
        'device': true,
        'accuracy': 40,
      });
      expect(old.district, isNull);
      expect(old.approximateName, false);
      expect(old.city, 'غزة');
    },
  );

  test(
    'Egypt uses its system neighborhood and Cairo timezone without a Palestinian fallback',
    () async {
      latitude = 30.0444;
      longitude = 31.2357;
      pointZone = 'Africa/Cairo';
      names = {
        'district': 'جاردن سيتي',
        'city': 'القاهرة',
        'country': 'مصر',
        'countryCode': 'EG',
      };
      await controller.locate();
      expect(controller.config.location!.label, 'جاردن سيتي، القاهرة، مصر');
      expect(controller.config.location!.district, 'جاردن سيتي');
      expect(controller.config.location!.zone, 'Africa/Cairo');
      expect(controller.today, isNotNull);
      expect(qiblaBearing(controller.config.location!).isFinite, true);
      expect(await prayerZoneAt(latitude, longitude), 'Africa/Cairo');
      names = {'city': 'القاهرة', 'country': 'مصر', 'countryCode': 'EG'};
      await controller.locate();
      expect(controller.config.location!.label, 'القاهرة، مصر');
      expect(controller.config.location!.district, isNull);
      expect(controller.config.location!.approximateName, false);
    },
  );
}
