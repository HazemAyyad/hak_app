import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:timezone_finder/timezone_finder.dart' as boundaries;
import 'prayer_models.dart';

String normalizePlaceQuery(String value) => value
    .toLowerCase()
    .replaceAll(RegExp('[\u064b-\u065f\u0670\u0640]'), '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

class PlaceCountry {
  PlaceCountry(
    this.code,
    this.name,
    this.english, {
    List<String> aliases = const [],
  }) : search = normalizePlaceQuery(
         '$name $english $code ${aliases.join(' ')}',
       );
  final String code, name, english, search;
}

class PlaceCity {
  PlaceCity({
    required this.id,
    required this.name,
    required this.english,
    required this.country,
    required this.latitude,
    required this.longitude,
    required this.zone,
    required this.population,
    List<String> aliases = const [],
  }) : search = normalizePlaceQuery('$name $english ${aliases.join(' ')}'),
       normalizedName = normalizePlaceQuery(name),
       normalizedEnglish = normalizePlaceQuery(english);
  final int id, population;
  final String name, english, zone, search, normalizedName, normalizedEnglish;
  final PlaceCountry country;
  final double latitude, longitude;
  String get label => '$name، ${country.name}';
  PrayerLocation get location => PrayerLocation(
    latitude: latitude,
    longitude: longitude,
    zone: zone,
    label: label.length > 100 ? label.substring(0, 100) : label,
  );
}

class PlaceResults {
  const PlaceResults(this.countries, this.cities);
  final List<PlaceCountry> countries;
  final List<PlaceCity> cities;
}

class PlaceDistrict {
  const PlaceDistrict({
    required this.id,
    required this.name,
    required this.country,
    required this.latitude,
    required this.longitude,
    this.city,
  });
  final int id;
  final String name;
  final String? city;
  final PlaceCountry country;
  final double latitude, longitude;
}

class PlaceCatalog {
  PlaceCatalog(this.countries, this.cities, {this.districts = const []});
  final List<PlaceCountry> countries;
  final List<PlaceDistrict> districts;

  /// Population-descending, stable GeoNames ID tiebreaker.
  final List<PlaceCity> cities;
  static Future<PlaceCatalog>? _loading;
  static Future<PlaceCatalog> load() =>
      _loading ??= _load().catchError((Object e) {
        _loading = null; // A transient asset failure must allow Retry.
        throw e;
      });
  static Future<PlaceCatalog> _load() async {
    final bytes = await rootBundle.load('assets/prayer_places/cities.json.gz');
    final districts = await rootBundle.load(
      'assets/prayer_places/districts.json',
    );
    return compute(_decodeCatalog, [
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      districts.buffer.asUint8List(
        districts.offsetInBytes,
        districts.lengthInBytes,
      ),
    ]);
  }

  PlaceResults search(String query, {String? countryCode, int limit = 40}) {
    final q = normalizePlaceQuery(query);
    final terms = q.split(' ').where((t) => t.isNotEmpty).toList();
    bool matches(String value) => terms.every(value.contains);
    final foundCountries = countryCode != null || q.isEmpty
        ? <PlaceCountry>[]
        : countries.where((c) => matches(c.search)).take(8).toList();
    final exact = <PlaceCity>[], prefix = <PlaceCity>[], rest = <PlaceCity>[];
    for (final city in cities) {
      if (countryCode != null && city.country.code != countryCode) continue;
      if (!matches('${city.search} ${city.country.search}')) continue;
      final bucket =
          q.isNotEmpty &&
              (city.normalizedName == q || city.normalizedEnglish == q)
          ? exact
          : q.isNotEmpty &&
                (city.normalizedName.startsWith(q) ||
                    city.normalizedEnglish.startsWith(q))
          ? prefix
          : rest;
      if (bucket.length < limit) bucket.add(city);
      // Empty searches show the largest cities, without scanning the database.
      if (q.isEmpty && rest.length == limit) break;
    }
    return PlaceResults(
      foundCountries,
      [...exact, ...prefix, ...rest].take(limit).toList(),
    );
  }

  /// A nearby settlement is a label hint, never a claimed administrative city
  /// or country boundary. Retain the tapped coordinates and polygon timezone.
  PlaceCity? nearby(double latitude, double longitude, {double maxKm = 80}) {
    final cosLat = math.cos(latitude * math.pi / 180);
    var best = maxKm * maxKm;
    PlaceCity? result;
    for (final city in cities) {
      final dy = (city.latitude - latitude) * 111.2;
      if (dy.abs() > maxKm) continue;
      var delta = (city.longitude - longitude).abs();
      if (delta > 180) delta = 360 - delta;
      final dx = delta * 111.2 * cosLat;
      final distance = dx * dx + dy * dy;
      if (distance < best) {
        best = distance;
        result = city;
      }
    }
    return result;
  }

  /// Points have no neighborhood boundaries. Return an explicitly approximate
  /// hint only for a precise fix, within 800m, and away from competing names.
  PlaceDistrict? nearbyDistrict(
    double latitude,
    double longitude, {
    required double accuracy,
    String? countryCode,
  }) {
    if (!accuracy.isFinite || accuracy < 0 || accuracy > 200) return null;
    final cosLat = math.cos(latitude * math.pi / 180);
    var best = double.infinity, second = double.infinity;
    PlaceDistrict? result;
    for (final district in districts) {
      if (countryCode != null &&
          district.country.code != countryCode.toUpperCase()) {
        continue;
      }
      final dy = (district.latitude - latitude) * 111200;
      final dx = (district.longitude - longitude) * 111200 * cosLat;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance < best) {
        second = best;
        best = distance;
        result = district;
      } else if (distance < second) {
        second = distance;
      }
    }
    return best + accuracy <= 800 && second - best > accuracy * 2
        ? result
        : null;
  }

  PrayerLocation point(double latitude, double longitude, String zone) {
    final near = nearby(latitude, longitude);
    final label = near == null ? 'موقع على الخريطة' : 'قرب ${near.label}';
    return PrayerLocation(
      latitude: latitude,
      longitude: longitude,
      zone: zone,
      label: label.length > 100 ? label.substring(0, 100) : label,
    );
  }
}

PlaceCatalog _decodeCatalog(List<Uint8List> bytes) {
  final raw = jsonDecode(utf8.decode(gzip.decode(bytes[0]))) as Map;
  final details = jsonDecode(utf8.decode(bytes[1])) as Map;
  if (raw['version'] != 1) throw const FormatException('Place catalog version');
  if (details['version'] != 1) {
    throw const FormatException('District catalog version');
  }
  final countries = <String, PlaceCountry>{};
  for (final e in (raw['countries'] as Map).entries) {
    final names = e.value as List;
    countries[e.key as String] = PlaceCountry(
      e.key as String,
      names[0] as String,
      names[1] as String,
      aliases: names.skip(2).cast<String>().toList(),
    );
  }
  return PlaceCatalog(
    countries.values.toList(),
    [
      for (final row in raw['cities'] as List)
        PlaceCity(
          id: row[0] as int,
          name: row[1] as String,
          english: row[2] as String,
          aliases: [row[3] as String, ...(row[9] as List).cast<String>()],
          country: countries[row[4]]!,
          latitude: (row[5] as num).toDouble(),
          longitude: (row[6] as num).toDouble(),
          zone: row[7] as String,
          population: row[8] as int,
        ),
    ],
    districts: [
      for (final row in details['districts'] as List)
        PlaceDistrict(
          id: row['id'] as int,
          name: row['name'] as String,
          country: countries[row['countryCode']]!,
          city: row['city'] as String?,
          latitude: (row['latitude'] as num).toDouble(),
          longitude: (row['longitude'] as num).toDouble(),
        ),
    ],
  );
}

/// Decode polygon boundaries away from the UI isolate. No location leaves the
/// device. No fallback to the device timezone or nearest city's timezone.
Future<String?> prayerZoneAt(double latitude, double longitude) =>
    compute(_pointZone, [latitude, longitude]);

String? _pointZone(List<double> point) {
  initializePrayerZones();
  return boundaries.findLocation(point[1], point[0])?.name;
}
