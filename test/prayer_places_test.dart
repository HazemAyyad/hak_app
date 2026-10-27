import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/prayer/data/place_catalog.dart';
import 'package:haq_app/features/prayer/data/prayer_controller.dart';
import 'package:haq_app/features/prayer/data/prayer_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlaceCatalog catalog;
  setUpAll(() async {
    catalog = await PlaceCatalog.load();
    initializePrayerZones();
  });

  test(
    'bundled countries and Arabic/English city results are real GeoNames coordinates',
    () {
      expect(catalog.cities.length, greaterThan(170000));
      final palestine = catalog.search('فلسطين').countries.single;
      expect(palestine.code, 'PS');
      final hebron = catalog.search('الخَلِيل').cities.first;
      final english = catalog.search('Hebron', countryCode: 'PS').cities.first;
      expect(hebron.id, english.id);
      expect(hebron.zone, 'Asia/Hebron');
      expect(hebron.latitude, 31.52935);
      expect(hebron.longitude, 35.0938);
      expect(hebron.location.label, 'الخليل، فلسطين');
      expect(
        catalog.search('nablus palestine').cities.first.country.code,
        'PS',
      );
      expect(catalog.search('فلسطين نابلس').cities.first.id, 282615);
      expect(
        catalog.search('المملكة العربية السعودية').countries.first.code,
        'SA',
      );
      expect(
        normalizePlaceQuery(
          catalog.search('Amman', countryCode: 'JO').cities.first.name,
        ),
        'عمان',
      );
      expect(
        catalog.search('London', countryCode: 'GB').cities.first.name,
        'لندن',
      );
      expect(catalog.search('مدينة غير موجودة xyz123').cities, isEmpty);
      expect(
        catalog
            .search('', countryCode: 'PS')
            .cities
            .every((c) => c.country.code == 'PS'),
        true,
      );
      expect(catalog.search('', countryCode: 'PS').cities.length, 40);
    },
  );

  test(
    'asset digest, IDs, coordinates, timezone identifiers and country references are valid',
    () {
      final manifest =
          jsonDecode(
                File('assets/prayer_places/manifest.json').readAsStringSync(),
              )
              as Map;
      expect(
        sha256
            .convert(
              File('assets/prayer_places/cities.json.gz').readAsBytesSync(),
            )
            .toString(),
        manifest['assetSha256'],
      );
      expect(
        catalog.cities.map((c) => c.id).toSet().length,
        catalog.cities.length,
      );
      for (final city in catalog.cities) {
        expect(
          city.latitude.isFinite && city.latitude.abs() <= 90,
          true,
          reason: '${city.id} latitude',
        );
        expect(
          city.longitude.isFinite && city.longitude.abs() <= 180,
          true,
          reason: '${city.id} longitude',
        );
        expect(
          tz.timeZoneDatabase.locations.containsKey(city.zone),
          true,
          reason: '${city.id} ${city.zone}',
        );
        expect(city.name.isNotEmpty && city.country.name.isNotEmpty, true);
      }
    },
  );

  test(
    'map timezone follows polygons across Palestine and DST borders, never the phone zone',
    () async {
      for (final sample in [
        (31.52935, 35.0938, 'Asia/Hebron'),
        (31.50161, 34.46672, 'Asia/Gaza'),
        (31.95522, 35.94503, 'Asia/Amman'),
        (30.06263, 31.24967, 'Africa/Cairo'),
        (51.50853, -0.12574, 'Europe/London'),
        (40.71427, -74.00597, 'America/New_York'),
        (33.4484, -112.074, 'America/Phoenix'),
        (35.1983, -111.6513, 'America/Phoenix'),
        (-33.8688, 151.2093, 'Australia/Sydney'),
      ]) {
        expect(await prayerZoneAt(sample.$1, sample.$2), sample.$3);
      }
      expect(await prayerZoneAt(0, -140), isNull);
      await expectLater(prayerZoneAt(91, 0), throwsArgumentError);
    },
  );

  test(
    'map saves exact pin and timezone, nearby label is explicitly approximate and survives reopen',
    () async {
      const lat = 31.53234567, lng = 35.09876543;
      final point = catalog.point(lat, lng, 'Asia/Hebron');
      expect(point.label, startsWith('قرب '));
      expect(point.fromDevice, false);
      expect(point.latitude, lat);
      expect(point.longitude, lng);
      expect(catalog.point(0, -140, 'Etc/UTC').label, 'موقع على الخريطة');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = PrayerController(
        prefs,
        scopeOf: () => 'guest',
        autoTick: false,
      );
      expect(await c.save(PrayerConfig(location: point)), true);
      c.dispose();
      final reopened = PrayerController(
        prefs,
        scopeOf: () => 'guest',
        autoTick: false,
      );
      expect(reopened.config.location!.toJson(), point.toJson());
      expect(reopened.today, isNotNull);
      reopened.dispose();
      final city = catalog.search('نابلس').cities.first.location;
      expect(PrayerLocation.fromJson(city.toJson()).label, city.label);
    },
  );
}
