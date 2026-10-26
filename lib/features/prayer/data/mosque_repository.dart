import 'dart:convert';
import 'package:dio/dio.dart';
import 'prayer_models.dart';

class NearbyMosque {
  const NearbyMosque(
    this.id,
    this.name,
    this.latitude,
    this.longitude,
    this.distance,
  );
  final String id, name;
  final double latitude, longitude, distance;
  Uri get mapUrl => Uri.https('www.openstreetmap.org', '/', {
    'mlat': '$latitude',
    'mlon': '$longitude',
  }).replace(fragment: 'map=17/$latitude/$longitude');
}

List<NearbyMosque> parseMosques(
  String source,
  PrayerLocation location,
  int radius,
) {
  final decoded = jsonDecode(source) as Map;
  if (decoded['remark'] != null || decoded['elements'] is! List) {
    throw const FormatException('Incomplete Overpass reply');
  }
  final seen = <String>{}, result = <NearbyMosque>[];
  for (final raw in decoded['elements'] as List) {
    if (raw is! Map || raw['tags'] is! Map) continue;
    final tags = raw['tags'] as Map;
    if (tags['amenity'] != 'place_of_worship' || tags['religion'] != 'muslim') {
      continue;
    }
    final center = raw['center'] is Map ? raw['center'] as Map : raw;
    final lat = (center['lat'] as num?)?.toDouble(),
        lng = (center['lon'] as num?)?.toDouble();
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180 ||
        !['node', 'way', 'relation'].contains(raw['type']) ||
        raw['id'] is! int) {
      continue;
    }
    final id = '${raw['type']}/${raw['id']}';
    final distance = distanceMetres(
      location.latitude,
      location.longitude,
      lat,
      lng,
    );
    if (distance > radius || !seen.add(id)) continue;
    final title = (tags['name:ar'] ?? tags['name'] ?? 'مسجد دون اسم في المصدر')
        .toString();
    result.add(
      NearbyMosque(
        id,
        title.length > 160 ? title.substring(0, 160) : title,
        lat,
        lng,
        distance,
      ),
    );
    if (result.length == 100) break;
  }
  result.sort((a, b) => a.distance.compareTo(b.distance));
  return result;
}

/// Explicit, bounded OSM query; no geocoding or automatic location upload.
class MosqueRepository {
  MosqueRepository({Dio? dio, DateTime Function()? clock})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          ),
      clock = clock ?? DateTime.now;
  final Dio dio;
  final DateTime Function() clock;
  DateTime? _lastRequest;
  bool _busy = false;
  CancelToken? _cancel;
  bool _disposed = false;
  Future<List<NearbyMosque>> search(
    PrayerLocation location, {
    int radius = 3000,
  }) async {
    if (_disposed || _busy) throw StateError('Search unavailable');
    if (radius < 500 || radius > 5000) throw ArgumentError('Invalid radius');
    if (_lastRequest != null &&
        clock().difference(_lastRequest!).inSeconds < 60) {
      throw StateError('انتظر دقيقة قبل طلب جديد');
    }
    _busy = true;
    _lastRequest = clock();
    _cancel = CancelToken();
    try {
      final query =
          '[out:json][timeout:20][maxsize:2097152];nwr["amenity"="place_of_worship"]["religion"="muslim"](around:$radius,${location.latitude},${location.longitude});out tags center 100;';
      final response = await dio.post<String>(
        'https://overpass-api.de/api/interpreter',
        data: {'data': query},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'HaqApp/1.0 (nearby mosques; OpenStreetMap)',
          },
        ),
        cancelToken: _cancel,
      );
      final body = response.data ?? '';
      if (body.length > 2097152) {
        throw const FormatException('Response too large');
      }
      return parseMosques(body, location, radius);
    } finally {
      _busy = false;
    }
  }

  void cancel() {
    _cancel?.cancel();
  }

  void dispose() {
    _disposed = true;
    cancel();
    dio.close(force: true);
  }
}
