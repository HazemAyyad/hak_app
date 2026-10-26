import 'dart:math' as math;
import 'package:adhan_dart/adhan_dart.dart' as adhan;
import 'package:hijri/hijri_calendar.dart';
import 'package:timezone/data/latest_all.dart' as data;
import 'package:timezone/timezone.dart' as tz;

bool _zonesReady = false;
void initializePrayerZones() {
  if (!_zonesReady) {
    data.initializeTimeZones();
    _zonesReady = true;
  }
}

enum PrayerMethod {
  worldLeague('رابطة العالم الإسلامي'),
  egyptian('الهيئة المصرية للمساحة'),
  karachi('جامعة كراتشي'),
  ummAlQura('أم القرى'),
  northAmerica('أمريكا الشمالية'),
  dubai('دبي'),
  jordan('الأردن'),
  kuwait('الكويت'),
  moonsighting('لجنة رؤية الهلال');

  const PrayerMethod(this.label);
  final String label;
  adhan.CalculationParameters parameters() => switch (this) {
    worldLeague => adhan.CalculationMethodParameters.muslimWorldLeague(),
    egyptian => adhan.CalculationMethodParameters.egyptian(),
    karachi => adhan.CalculationMethodParameters.karachi(),
    ummAlQura => adhan.CalculationMethodParameters.ummAlQura(),
    northAmerica => adhan.CalculationMethodParameters.northAmerica(),
    dubai => adhan.CalculationMethodParameters.dubai(),
    jordan => adhan.CalculationMethodParameters.jordan(),
    kuwait => adhan.CalculationMethodParameters.kuwait(),
    moonsighting => adhan.CalculationMethodParameters.moonsightingCommittee(),
  };
}

enum PrayerName {
  fajr('الفجر'),
  sunrise('الشروق'),
  dhuhr('الظهر'),
  asr('العصر'),
  maghrib('المغرب'),
  isha('العشاء');

  const PrayerName(this.label);
  final String label;
}

class PrayerLocation {
  PrayerLocation({
    required this.latitude,
    required this.longitude,
    required this.zone,
    required this.label,
    this.fromDevice = false,
    this.accuracy,
    this.measuredAt,
  }) {
    initializePrayerZones();
    tz.getLocation(zone);
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180 ||
        label.trim().isEmpty ||
        label.length > 100 ||
        (accuracy != null && (!accuracy!.isFinite || accuracy! < 0))) {
      throw const FormatException('Invalid location');
    }
  }
  final double latitude, longitude;
  final String zone, label;
  final bool fromDevice;
  final double? accuracy;
  final DateTime? measuredAt;
  tz.Location get timeZone => tz.getLocation(zone);
  Map<String, Object?> toJson() => {
    'lat': latitude,
    'lng': longitude,
    'zone': zone,
    'label': label,
    'device': fromDevice,
    'accuracy': accuracy,
    'measured': measuredAt?.toUtc().toIso8601String(),
  };
  factory PrayerLocation.fromJson(Map data) => PrayerLocation(
    latitude: (data['lat'] as num).toDouble(),
    longitude: (data['lng'] as num).toDouble(),
    zone: data['zone'] as String,
    label: data['label'] as String,
    fromDevice: data['device'] == true,
    accuracy: (data['accuracy'] as num?)?.toDouble(),
    measuredAt: data['measured'] == null
        ? null
        : DateTime.parse(data['measured'] as String),
  );
}

class PrayerConfig {
  PrayerConfig({
    this.location,
    this.method = PrayerMethod.worldLeague,
    this.hanafi = false,
    this.highLatitude = 'recommended',
    Map<String, int> adjustments = const {},
    this.notifications = false,
    this.beforeMinutes = 0,
    this.afterMinutes = 0,
    List<String> enabledPrayers = const [
      'fajr',
      'dhuhr',
      'asr',
      'maghrib',
      'isha',
    ],
  }) : adjustments = Map.unmodifiable(adjustments),
       enabledPrayers = List.unmodifiable(enabledPrayers) {
    if (!['recommended', 'middle', 'seventh', 'angle'].contains(highLatitude) ||
        beforeMinutes < 0 ||
        beforeMinutes > 60 ||
        afterMinutes < 0 ||
        afterMinutes > 30 ||
        adjustments.entries.any(
          (e) =>
              !PrayerName.values.any((p) => p.name == e.key) ||
              e.value.abs() > 30,
        ) ||
        enabledPrayers.toSet().length != enabledPrayers.length ||
        enabledPrayers.any(
          (key) => !PrayerName.values.any(
            (p) => p != PrayerName.sunrise && p.name == key,
          ),
        )) {
      throw const FormatException('Invalid prayer preferences');
    }
  }
  final PrayerLocation? location;
  final PrayerMethod method;
  final bool hanafi, notifications;
  final String highLatitude;
  final Map<String, int> adjustments;
  final int beforeMinutes, afterMinutes;
  final List<String> enabledPrayers;
  PrayerConfig copyWith({
    PrayerLocation? location,
    bool clearLocation = false,
    PrayerMethod? method,
    bool? hanafi,
    String? highLatitude,
    Map<String, int>? adjustments,
    bool? notifications,
    int? beforeMinutes,
    int? afterMinutes,
    List<String>? enabledPrayers,
  }) => PrayerConfig(
    location: clearLocation ? null : location ?? this.location,
    method: method ?? this.method,
    hanafi: hanafi ?? this.hanafi,
    highLatitude: highLatitude ?? this.highLatitude,
    adjustments: adjustments ?? this.adjustments,
    notifications: notifications ?? this.notifications,
    beforeMinutes: beforeMinutes ?? this.beforeMinutes,
    afterMinutes: afterMinutes ?? this.afterMinutes,
    enabledPrayers: enabledPrayers ?? this.enabledPrayers,
  );
  Map<String, Object?> toJson() => {
    'location': location?.toJson(),
    'method': method.name,
    'hanafi': hanafi,
    'highLatitude': highLatitude,
    'adjustments': adjustments,
    'notifications': notifications,
    'before': beforeMinutes,
    'after': afterMinutes,
    'prayers': enabledPrayers,
  };
  factory PrayerConfig.fromJson(Map data) => PrayerConfig(
    location: data['location'] == null
        ? null
        : PrayerLocation.fromJson(data['location'] as Map),
    method: PrayerMethod.values.byName(data['method'] as String),
    hanafi: data['hanafi'] as bool,
    highLatitude: data['highLatitude'] as String,
    adjustments: Map<String, int>.from(data['adjustments'] as Map),
    notifications: data['notifications'] as bool,
    beforeMinutes: data['before'] as int,
    afterMinutes: data['after'] as int,
    enabledPrayers: List<String>.from(data['prayers'] as List),
  );
}

class PrayerMoment {
  const PrayerMoment(this.name, this.time);
  final PrayerName name;
  final tz.TZDateTime time;
  String get label =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class PrayerDay {
  const PrayerDay(this.date, this.moments);
  final tz.TZDateTime date;
  final List<PrayerMoment> moments;
  Iterable<PrayerMoment> get obligatory =>
      moments.where((m) => m.name != PrayerName.sunrise);
}

PrayerDay calculatePrayerDay(PrayerConfig config, DateTime instant) {
  final place = config.location;
  if (place == null) throw StateError('Location required');
  final local = tz.TZDateTime.from(instant, place.timeZone);
  final coordinates = adhan.Coordinates(place.latitude, place.longitude);
  final params = config.method.parameters()
    ..madhab = config.hanafi ? adhan.Madhab.hanafi : adhan.Madhab.shafi
    ..highLatitudeRule = switch (config.highLatitude) {
      'middle' => adhan.HighLatitudeRule.middleOfTheNight,
      'seventh' => adhan.HighLatitudeRule.seventhOfTheNight,
      'angle' => adhan.HighLatitudeRule.twilightAngle,
      _ => adhan.HighLatitudeRule.recommended(coordinates),
    };
  for (final prayer in PrayerName.values) {
    params.adjustments[adhan.Prayer.values.byName(prayer.name)] =
        config.adjustments[prayer.name] ?? 0;
  }
  final times = adhan.PrayerTimes(
    coordinates: coordinates,
    date: DateTime(local.year, local.month, local.day),
    calculationParameters: params,
  );
  final raw = [
    times.fajr,
    times.sunrise,
    times.dhuhr,
    times.asr,
    times.maghrib,
    times.isha,
  ];
  final moments = List.generate(
    6,
    (i) => PrayerMoment(
      PrayerName.values[i],
      tz.TZDateTime.from(raw[i], place.timeZone),
    ),
  );
  // A polar calculation may be unresolved. Never fill gaps with another city.
  if (moments.any((p) => p.time.difference(local).inDays.abs() > 2)) {
    throw const FormatException('Unresolved prayer day');
  }
  return PrayerDay(
    tz.TZDateTime(place.timeZone, local.year, local.month, local.day),
    List.unmodifiable(moments),
  );
}

PrayerMoment nextPrayer(PrayerConfig config, DateTime instant) {
  final today = calculatePrayerDay(config, instant);
  final candidates = [...today.obligatory];
  // The previous civil day's Isha can fall after midnight at high latitudes.
  for (final offset in [-1, 1]) {
    final date = tz.TZDateTime(
      today.date.location,
      today.date.year,
      today.date.month,
      today.date.day + offset,
      12,
    );
    candidates.addAll(calculatePrayerDay(config, date).obligatory);
  }
  candidates.sort((a, b) => a.time.compareTo(b.time));
  return candidates.firstWhere((m) => m.time.isAfter(instant));
}

double qiblaBearing(PrayerLocation place) {
  if (distanceMetres(place.latitude, place.longitude, 21.4225241, 39.8261818) <
      20) {
    throw const FormatException('At Kaaba: bearing is undefined');
  }
  return adhan.Qibla.qibla(adhan.Coordinates(place.latitude, place.longitude));
}

double headingDifference(double target, double heading) =>
    ((target - heading + 540) % 360) - 180;
double distanceMetres(double lat1, double lng1, double lat2, double lng2) {
  double r(double d) => d * math.pi / 180;
  final a =
      math.pow(math.sin(r(lat2 - lat1) / 2), 2) +
      math.cos(r(lat1)) *
          math.cos(r(lat2)) *
          math.pow(math.sin(r(lng2 - lng1) / 2), 2);
  return 6371000 *
      2 *
      math.atan2(math.sqrt(a.clamp(0, 1)), math.sqrt((1 - a).clamp(0, 1)));
}

String prayerHijriDate(DateTime date, {int correction = 0}) {
  const months = [
    'محرم',
    'صفر',
    'ربيع الأول',
    'ربيع الآخر',
    'جمادى الأولى',
    'جمادى الآخرة',
    'رجب',
    'شعبان',
    'رمضان',
    'شوال',
    'ذو القعدة',
    'ذو الحجة',
  ];
  try {
    final civil = DateTime.utc(
      date.year,
      date.month,
      date.day + correction.clamp(-3, 3),
    );
    final h = HijriCalendar.fromDate(civil);
    return '${h.hDay} ${months[h.hMonth - 1]} ${h.hYear} هـ';
  } catch (_) {
    return '${date.year}/${date.month}/${date.day}';
  }
}
