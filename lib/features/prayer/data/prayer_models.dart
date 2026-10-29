import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:adhan_dart/adhan_dart.dart' as adhan;
import 'package:hijri/hijri_calendar.dart';
import 'package:timezone/data/latest_all.dart' as data;
import 'package:timezone/timezone.dart' as tz;
import 'prayer_alert.dart';

/// Stable local clip ID. A signed-in account never uses another account's clip.
String prayerReminderVoiceId(String scope, PrayerName prayer) =>
    'reminder-${sha256.convert(utf8.encode(scope)).toString().substring(0, 16)}-${prayer.name}';

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
    this.city,
    this.country,
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
  final String? city, country;
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
    if (city != null) 'city': city,
    if (country != null) 'country': country,
    'accuracy': accuracy,
    'measured': measuredAt?.toUtc().toIso8601String(),
  };
  factory PrayerLocation.fromJson(Map data) => PrayerLocation(
    latitude: (data['lat'] as num).toDouble(),
    longitude: (data['lng'] as num).toDouble(),
    zone: data['zone'] as String,
    label: data['label'] as String,
    fromDevice: data['device'] == true,
    city: data['city'] as String?,
    country: data['country'] as String?,
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
    this.beforeMinutes = 15,
    this.afterMinutes = 0,
    this.adhanVolume = 100,
    this.showAdhanScreen = true,
    this.iqamaMinutes = 15,
    this.defaultAlert = const PrayerAlert(),
    Map<String, PrayerAlert> alerts = const {},
    List<String> enabledPrayers = const [
      'fajr',
      'dhuhr',
      'asr',
      'maghrib',
      'isha',
    ],
  }) : alerts = Map.unmodifiable(alerts),
       adjustments = Map.unmodifiable(adjustments),
       enabledPrayers = List.unmodifiable(enabledPrayers) {
    if (iqamaMinutes < 0 ||
        iqamaMinutes > 60 ||
        adhanVolume < 0 ||
        adhanVolume > 100 ||
        alerts.keys.any((k) => !PrayerName.values.any((p) => p.name == k)) ||
        !['recommended', 'middle', 'seventh', 'angle'].contains(highLatitude) ||
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
          (key) => !PrayerName.values.any((p) => p.name == key),
        )) {
      throw const FormatException('Invalid prayer preferences');
    }
  }
  final PrayerLocation? location;
  final PrayerMethod method;
  final bool hanafi, notifications;
  final String highLatitude;
  final Map<String, int> adjustments;
  final int beforeMinutes, afterMinutes, adhanVolume, iqamaMinutes;
  final bool showAdhanScreen;
  final PrayerAlert defaultAlert;
  final List<String> enabledPrayers;
  final Map<String, PrayerAlert> alerts;
  PrayerAlert alert(PrayerName name) =>
      alerts[name.name] ??
      (name == PrayerName.sunrise ? const PrayerAlert() : defaultAlert);
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
    int? adhanVolume,
    int? iqamaMinutes,
    bool? showAdhanScreen,
    PrayerAlert? defaultAlert,
    List<String>? enabledPrayers,
    Map<String, PrayerAlert>? alerts,
  }) => PrayerConfig(
    location: clearLocation ? null : location ?? this.location,
    method: method ?? this.method,
    hanafi: hanafi ?? this.hanafi,
    highLatitude: highLatitude ?? this.highLatitude,
    adjustments: adjustments ?? this.adjustments,
    notifications: notifications ?? this.notifications,
    beforeMinutes: beforeMinutes ?? this.beforeMinutes,
    afterMinutes: afterMinutes ?? this.afterMinutes,
    adhanVolume: adhanVolume ?? this.adhanVolume,
    iqamaMinutes: iqamaMinutes ?? this.iqamaMinutes,
    showAdhanScreen: showAdhanScreen ?? this.showAdhanScreen,
    defaultAlert: defaultAlert ?? this.defaultAlert,
    enabledPrayers: enabledPrayers ?? this.enabledPrayers,
    alerts: alerts ?? this.alerts,
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
    'adhanVolume': adhanVolume,
    'iqamaMinutes': iqamaMinutes,
    'showAdhanScreen': showAdhanScreen,
    'defaultAlert': defaultAlert.toJson(),
    'prayers': enabledPrayers,
    'alerts': alerts.map((key, value) => MapEntry(key, value.toJson())),
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
    adhanVolume: data['adhanVolume'] as int? ?? 100,
    iqamaMinutes: data['iqamaMinutes'] as int? ?? 15,
    showAdhanScreen: data['showAdhanScreen'] as bool? ?? true,
    defaultAlert: data['defaultAlert'] == null
        ? const PrayerAlert()
        : PrayerAlert.fromJson(data['defaultAlert'] as Map),
    enabledPrayers: List<String>.from(data['prayers'] as List),
    alerts: (data['alerts'] as Map? ?? {}).map(
      (key, value) =>
          MapEntry(key as String, PrayerAlert.fromJson(value as Map)),
    ),
  );
}

class PrayerMoment {
  const PrayerMoment(this.name, this.time);
  final PrayerName name;
  final tz.TZDateTime time;
  String get label => prayerClockLabel(time);
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

String prayerClockLabel(DateTime time) =>
    '${time.hour % 12 == 0 ? 12 : time.hour % 12}:${time.minute.toString().padLeft(2, '0')} ${time.hour < 12 ? 'ص' : 'م'}';

String prayerGregorianDate(DateTime time) {
  const months = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];
  return '${time.day} ${months[time.month - 1]} ${time.year}';
}

Map<String, tz.TZDateTime> additionalPrayerTimes(
  PrayerConfig config,
  DateTime now,
) {
  if (config.location == null) return {};
  try {
    final day = calculatePrayerDay(config, now),
        zone = config.location!.timeZone;
    final next = calculatePrayerDay(
      config,
      tz.TZDateTime(zone, day.date.year, day.date.month, day.date.day + 1, 12),
    );
    final sunset = day.moments
        .firstWhere((m) => m.name == PrayerName.maghrib)
        .time;
    final fajr = next.moments.firstWhere((m) => m.name == PrayerName.fajr).time;
    final sunrise = day.moments
        .firstWhere((m) => m.name == PrayerName.sunrise)
        .time;
    final night = fajr.difference(sunset);
    if (night <= Duration.zero) return {};
    return {
      'الضحى (تقريبي)': sunrise.add(const Duration(minutes: 20)),
      'منتصف الليل': sunset.add(
        Duration(milliseconds: night.inMilliseconds ~/ 2),
      ),
      'الثلث الأخير من الليل': sunset.add(
        Duration(milliseconds: night.inMilliseconds * 2 ~/ 3),
      ),
    };
  } catch (_) {
    return {};
  }
}

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
