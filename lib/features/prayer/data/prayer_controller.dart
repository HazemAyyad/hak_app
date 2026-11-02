import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../settings/data/app_settings.dart';
import '../../settings/data/reminder_plan.dart';
import 'prayer_models.dart';
import 'prayer_alert.dart';
import 'place_catalog.dart';
import '../../../core/localization/interface_messages.dart';

class PrayerController extends ChangeNotifier {
  PrayerController(
    this.preferences, {
    required this.scopeOf,
    Listenable? account,
    DateTime Function()? clock,
    MethodChannel? channel,
    this.autoTick = true,
    this.placeCatalog = PlaceCatalog.load,
    this.timeZoneAt = prayerZoneAt,
  }) : account = account,
       clock = clock ?? DateTime.now,
       channel =
           channel ?? const MethodChannel('com.haqfoundation.haq_app/prayer') {
    initializePrayerZones();
    scope = scopeOf();
    _restore();
    account?.addListener(_accountChanged);
  }
  final SharedPreferences preferences;
  final String Function() scopeOf;
  final Listenable? account;
  final DateTime Function() clock;
  final MethodChannel channel;
  final bool autoTick;
  final Future<PlaceCatalog> Function() placeCatalog;
  final Future<String?> Function(double, double) timeZoneAt;
  final scheduleChanged = ChangeNotifier();
  late String scope;
  PrayerConfig config = PrayerConfig();
  PrayerDay? today;
  PrayerMoment? upcoming;
  String? error, calculationError;
  String? locationNotice;
  bool locating = false,
      _disposed = false,
      _corrupt = false,
      _foreground = true;
  int _revision = 0;
  int _locationRequest = 0;
  Timer? _timer;
  Future<void> _writes = Future.value();
  String? _day;
  String _appLanguage = 'ar';
  InterfaceMessages messages = InterfaceMessages.bundled('ar');
  String get reminderVariant =>
      (config.reminderLanguage == 'auto'
              ? _appLanguage
              : config.reminderLanguage) ==
          'en'
      ? 'en'
      : config.reminderDialect.assetKey;
  void setAppLanguage(String language) {
    setInterfaceMessages(
      InterfaceMessages.bundled(
        language.toLowerCase().split(RegExp('[-_]')).first,
      ),
    );
  }

  void setInterfaceMessages(InterfaceMessages next) {
    if (_disposed ||
        (_appLanguage == next.code &&
            mapEquals(messages.strings, next.strings))) {
      return;
    }
    _appLanguage = next.code;
    messages = next;
    notifyListeners();
    scheduleChanged.notifyListeners();
  }

  DateTime get now => clock();
  void _restore() {
    error = null;
    locationNotice = null;
    _corrupt = false;
    try {
      final raw = preferences.getString('prayer.config.v1.$scope');
      config = raw == null
          ? PrayerConfig()
          : PrayerConfig.fromJson(jsonDecode(raw) as Map);
    } catch (_) {
      config = PrayerConfig();
      error = 'تعذّر قراءة إعدادات الصلاة. أعد ضبط هذا القسم للمتابعة.';
      _corrupt = true;
    }
    _calculate();
  }

  void _accountChanged() {
    if (_disposed || scope == scopeOf()) return;
    scope = scopeOf();
    _revision++;
    _locationRequest++;
    locating = false;
    _restore();
    notifyListeners();
  }

  void reloadBackup() {
    ++_revision;
    _locationRequest++;
    locating = false;
    _restore();
    notifyListeners();
  }

  void _calculate() {
    _manageClock();
    today = null;
    upcoming = null;
    calculationError = null;
    if (config.location == null) {
      scheduleChanged.notifyListeners();
      return;
    }
    try {
      today = calculatePrayerDay(config, now);
      upcoming = nextPrayer(config, now);
      _day = '${today!.date.year}-${today!.date.month}-${today!.date.day}';
    } catch (_) {
      today = null;
      upcoming = null;
      calculationError =
          'تعذّر حساب المواقيت لهذا الموقع والتاريخ. راجع الطريقة وقاعدة خطوط العرض العالية.';
    }
    scheduleChanged.notifyListeners();
  }

  void tick() {
    if (_disposed || !_foreground) return;
    final location = config.location;
    if (location != null) {
      final local = tz.TZDateTime.from(now, location.timeZone);
      if (_day != '${local.year}-${local.month}-${local.day}' ||
          upcoming == null ||
          !upcoming!.time.isAfter(now)) {
        _calculate();
      }
    }
    notifyListeners();
  }

  void setForeground(bool active) {
    _foreground = active;
    _manageClock();
    if (active) tick();
  }

  void _manageClock() {
    _timer?.cancel();
    _timer = null;
    if (autoTick && _foreground && config.location != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    }
  }

  String get countdown {
    if (upcoming == null) return '--:--:--';
    final seconds = upcoming!.time.difference(now).inSeconds.clamp(0, 172800);
    return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String get hijriLabel {
    final context = _hijriContext;
    return prayerHijriDate(context.date, correction: context.offset);
  }

  ({int day, int month, int year})? get hijriParts {
    final context = _hijriContext;
    return prayerHijriParts(context.date, correction: context.offset);
  }

  ({DateTime date, int offset}) get _hijriContext {
    final general = AppSettings(preferences, scope);
    final offset = general.flag('correctHijri')
        ? general.number('hijriOffset', 0)
        : 0;
    general.dispose();
    final date = config.location == null
        ? now
        : tz.TZDateTime.from(now, config.location!.timeZone);
    return (date: date, offset: offset);
  }

  Future<bool> save(PrayerConfig next) async {
    if (_disposed || _corrupt) return false;
    final owner = scope;
    final revision = ++_revision;
    var saved = false;
    final job = _writes.then((_) async {
      try {
        if (!await preferences.setString(
          'prayer.config.v1.$owner',
          jsonEncode(next.toJson()),
        )) {
          throw StateError('Preferences');
        }
        saved = true;
        if (!_disposed && scope == owner && revision == _revision) {
          config = next;
          error = null;
          locationNotice = null;
          _calculate();
          notifyListeners();
        }
      } catch (_) {
        if (!_disposed && scope == owner) {
          error = 'تعذّر حفظ إعدادات الصلاة؛ حاول مجدداً.';
          notifyListeners();
        }
      }
    });
    _writes = job;
    await job;
    return saved;
  }

  Future<void> locate() async {
    if (_disposed || locating) return;
    final owner = scope;
    final revision = ++_revision;
    locating = true;
    final request = ++_locationRequest;
    error = null;
    locationNotice = null;
    notifyListeners();
    try {
      final raw = await channel.invokeMapMethod<String, dynamic>(
        'requestLocation',
      );
      if (_disposed || scope != owner || revision != _revision) return;
      if (raw == null) throw StateError('No location');
      final measured = PrayerLocation(
        latitude: (raw['lat'] as num).toDouble(),
        longitude: (raw['lng'] as num).toDouble(),
        zone: raw['zone'] as String,
        label: 'موقع الجهاز',
        fromDevice: true,
        accuracy: (raw['accuracy'] as num).toDouble(),
        measuredAt: DateTime.fromMillisecondsSinceEpoch(
          raw['measured'] as int,
          isUtc: true,
        ),
      );
      if (measured.accuracy! > 5000 ||
          now.difference(measured.measuredAt!).abs() >
              const Duration(minutes: 5)) {
        throw StateError('Stale location');
      }
      Map<String, dynamic>? names;
      PlaceCatalog? catalog;
      String? zone;
      await Future.wait([
        (() async {
          try {
            names = await channel
                .invokeMapMethod<String, dynamic>('reverseGeocode', {
                  'lat': measured.latitude,
                  'lng': measured.longitude,
                })
                .timeout(const Duration(seconds: 5));
          } catch (_) {
            /* Retain measured coordinates if system naming fails. */
          }
        })(),
        (() async {
          try {
            catalog = await placeCatalog();
          } catch (_) {}
        })(),
        (() async {
          try {
            zone = await timeZoneAt(measured.latitude, measured.longitude);
          } catch (_) {}
        })(),
      ]);
      if (_disposed || scope != owner || revision != _revision) return;
      String? name(String key) {
        final value = names?[key];
        return value is String &&
                value.trim().isNotEmpty &&
                value.trim().length <= 100
            ? value.trim()
            : null;
      }

      var city = name('city'), country = name('country');
      final precise = raw['precise'] != false && measured.accuracy! <= 200;
      var district = precise ? name('district') : null;
      final validNames = country != null && (city != null || district != null);
      final nearbyDistrict = precise && district == null
          ? catalog?.nearbyDistrict(
              measured.latitude,
              measured.longitude,
              accuracy: measured.accuracy!,
              countryCode: name('countryCode'),
            )
          : null;
      if (nearbyDistrict != null) {
        district = nearbyDistrict.name;
        city ??= nearbyDistrict.city;
        country ??= nearbyDistrict.country.name;
      }
      final parts = <String>[];
      final normalized = <String>{};
      for (final part in [district, city, country]) {
        if (part != null && normalized.add(normalizePlaceQuery(part))) {
          parts.add(part);
        }
      }
      final near = catalog?.nearby(measured.latitude, measured.longitude);
      final approximateName = nearbyDistrict != null || !validNames;
      final label = nearbyDistrict != null
          ? 'قرب ${parts.join('، ')}'
          : validNames
          ? parts.join('، ')
          : near == null
          ? 'موقع الجهاز'
          : 'قرب ${near.label}';
      final place = PrayerLocation(
        latitude: measured.latitude,
        longitude: measured.longitude,
        zone: zone ?? measured.zone,
        label: label.length > 100 ? label.substring(0, 100) : label,
        city: validNames || nearbyDistrict != null ? city : null,
        country: validNames || nearbyDistrict != null ? country : null,
        district: district,
        approximateName: approximateName,
        fromDevice: true,
        accuracy: measured.accuracy,
        measuredAt: measured.measuredAt,
      );
      final saved = await save(config.copyWith(location: place));
      if (saved &&
          !_disposed &&
          scope == owner &&
          identical(config.location, place)) {
        locationNotice = nearbyDistrict != null
            ? 'تم تحديث الإحداثيات؛ اسم أقرب حي تقريبي: ${place.label}.'
            : validNames
            ? 'تم تحديث الموقع: ${place.label}${precise ? '' : '؛ اسم الحي يحتاج موقعًا أدق. فعّل الموقع الدقيق وأعد التحديث.'}'
            : near != null
            ? 'تم تحديث الإحداثيات؛ اسم أقرب مدينة تقريبي.'
            : 'تم تحديث الإحداثيات؛ تعذّر تحديد اسم المدينة والدولة. أعد التحديث أو اختر المدينة يدويًا.';
      }
    } on PlatformException catch (e) {
      if (!_disposed && scope == owner && revision == _revision) {
        error = switch (e.code) {
          'denied' =>
            'لم يُسمح بالموقع. يمكنك تحديده يدوياً أو فتح إعدادات الجهاز.',
          'disabled' =>
            'خدمة الموقع متوقفة. فعّلها من إعدادات الجهاز أو اختر الموقع يدوياً.',
          _ =>
            'تعذّر تحديد موقع حديث؛ أعد المحاولة في مكان مفتوح أو حدده يدوياً.',
        };
      }
    } on MissingPluginException {
      if (!_disposed && scope == owner) {
        error =
            'الموقع الأصلي غير متاح في بيئة العرض الحالية. استخدم الإدخال اليدوي.';
      }
    } catch (_) {
      if (!_disposed && scope == owner && revision == _revision) {
        error =
            'الموقع غير دقيق أو المنطقة الزمنية غير معروفة؛ استخدم الإدخال اليدوي.';
      }
    } finally {
      if (!_disposed && scope == owner && request == _locationRequest) {
        locating = false;
        notifyListeners();
      }
    }
  }

  Future<Map<String, dynamic>> deviceStatus() async {
    try {
      return await channel.invokeMapMethod<String, dynamic>('status') ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<void> openSettings() async {
    try {
      await channel.invokeMethod<void>('settings');
    } catch (_) {
      if (!_disposed) {
        error = 'تعذّر فتح إعدادات الجهاز';
        notifyListeners();
      }
    }
  }

  Future<void> openMap(Uri uri) async {
    try {
      await channel.invokeMethod<void>('openMap', uri.toString());
    } catch (_) {
      if (!_disposed) {
        error = 'تعذّر فتح الخريطة على هذا الجهاز';
        notifyListeners();
      }
    }
  }

  Future<void> reset() async {
    final owner = scope;
    ++_revision;
    await _writes;
    try {
      if (!await preferences.remove('prayer.config.v1.$owner')) {
        throw StateError('Preferences');
      }
      if (!_disposed && scope == owner) {
        _restore();
        notifyListeners();
      }
    } catch (_) {
      if (!_disposed && scope == owner) {
        error = 'تعذّرت إعادة الضبط';
        notifyListeners();
      }
    }
  }

  List<ReminderJob> reminderJobs({int days = 14}) {
    if (config.location == null ||
        !config.notifications ||
        calculationError != null) {
      return [];
    }
    final jobs = <ReminderJob>[];
    final place = config.location!;
    final local = tz.TZDateTime.from(now, place.timeZone);
    try {
      for (var day = 0; day < days; day++) {
        final date = tz.TZDateTime(
          place.timeZone,
          local.year,
          local.month,
          local.day + day,
          12,
        );
        final times = calculatePrayerDay(config, date);
        for (final m in times.moments.where(
          (m) => config.enabledPrayers.contains(m.name.name),
        )) {
          final actions = {
            0: messages.text(
              'prayer.timeFor',
              args: {'prayer': messages.text('prayer.name.${m.name.name}')},
            ),
            if (config.beforeMinutes > 0)
              -config.beforeMinutes: m.name == PrayerName.sunrise
                  ? messages.text('reminder.sunrise')
                  : messages.text(
                      'prayer.approaching',
                      args: {
                        'prayer': messages.text('prayer.name.${m.name.name}'),
                      },
                    ),
            if (config.afterMinutes > 0)
              config.afterMinutes: messages.text(
                'reminder.afterPrayer',
                args: {'prayer': messages.text('prayer.name.${m.name.name}')},
              ),
          };
          for (final entry in actions.entries) {
            final at = m.time.add(Duration(minutes: entry.key));
            jobs.add(
              ReminderJob(
                id: '$scope:prayer:${m.name.name}:${at.toUtc().millisecondsSinceEpoch}:${entry.key}',
                title: entry.value,
                body: entry.key > 0
                    ? messages.text('reminder.afterBody')
                    : '${place.label} • ${messages.formats.clock24(m.time)}',
                route: entry.key > 0 ? 'adhkar' : 'prayer',
                minute: 0,
                at: at.toUtc().millisecondsSinceEpoch,
                volume: entry.key == 0 ? config.adhanVolume : null,
                reminderVariant: entry.key < 0 ? reminderVariant : null,
                showAdhanScreen: entry.key == 0 ? config.showAdhanScreen : null,
                iqamaMinutes: entry.key == 0 ? config.iqamaMinutes : null,
                alertMode: entry.key == 0
                    ? config.alert(m.name).mode.name
                    : entry.key < 0 && m.name != PrayerName.sunrise
                    ? 'reminderVoice'
                    : null,
                voice:
                    entry.key == 0 &&
                        config.alert(m.name).mode == PrayerAlertMode.adhan &&
                        m.name != PrayerName.sunrise
                    ? config.alert(m.name).voice
                    : entry.key < 0 && m.name != PrayerName.sunrise
                    ? prayerReminderVoiceId(
                        scope,
                        m.name,
                        variant: reminderVariant,
                      )
                    : null,
                fullAdhan:
                    entry.key == 0 &&
                    m.name != PrayerName.sunrise &&
                    config.alert(m.name).full,
              ),
            );
          }
        }
      }
    } catch (_) {
      return [];
    }
    return jobs;
  }

  Future<void> flush() => _writes;
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    account?.removeListener(_accountChanged);
    scheduleChanged.dispose();
    super.dispose();
  }
}
