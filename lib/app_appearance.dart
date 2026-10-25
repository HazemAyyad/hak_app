import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppFont {
  cairo('Cairo', 'القاهرة', 'QuranUI'),
  tajawal('Tajawal', 'تجوال', 'Tajawal'),
  system('System', 'خط الجهاز', null);

  const AppFont(this.id, this.label, this.family);
  final String id;
  final String label;
  final String? family;
}

/// The single source of appearance preferences for every route.
class AppAppearance extends ChangeNotifier {
  AppAppearance(this.preferences, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now {
    mode = ThemeMode.values.firstWhere(
      (value) => value.name == preferences.getString('appearance.mode'),
      orElse: () => ThemeMode.system,
    );
    fontScale = (preferences.getDouble('appearance.fontScale') ?? 1).clamp(
      .85,
      1.2,
    );
    font = AppFont.values.firstWhere(
      (value) => value.id == preferences.getString('appearance.font'),
      orElse: () => AppFont.cairo,
    );
    timed = preferences.getBool('appearance.timed') ?? false;
    dayStart = (preferences.getInt('appearance.dayStart') ?? 360).clamp(
      0,
      1439,
    );
    nightStart = (preferences.getInt('appearance.nightStart') ?? 1080).clamp(
      0,
      1439,
    );
    if (dayStart == nightStart) {
      dayStart = 360;
      nightStart = 1080;
    }
    _startClock();
  }

  final SharedPreferences preferences;
  late ThemeMode mode;
  late double fontScale;
  late AppFont font;
  final DateTime Function() clock;
  late bool timed;
  late int dayStart, nightStart;
  Timer? _timer;
  ThemeMode? _lastMode;
  ThemeMode get effectiveMode {
    if (!timed) return mode;
    final now = clock(), minute = now.hour * 60 + now.minute;
    final light = dayStart < nightStart
        ? minute >= dayStart && minute < nightStart
        : minute >= dayStart || minute < nightStart;
    return light ? ThemeMode.light : ThemeMode.dark;
  }

  void _startClock() {
    _timer?.cancel();
    _lastMode = effectiveMode;
    if (timed) {
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_lastMode != effectiveMode) {
          _lastMode = effectiveMode;
          notifyListeners();
        }
      });
    }
  }

  Future<void> setTimed(bool value) async {
    timed = value;
    _startClock();
    notifyListeners();
    await preferences.setBool('appearance.timed', value);
  }

  Future<void> setSchedule({required int day, required int night}) async {
    if (day < 0 || day > 1439 || night < 0 || night > 1439 || day == night) {
      throw ArgumentError('Invalid appearance schedule');
    }
    dayStart = day;
    nightStart = night;
    _startClock();
    notifyListeners();
    await preferences.setInt('appearance.dayStart', day);
    await preferences.setInt('appearance.nightStart', night);
  }

  Future<void> setFont(AppFont value) async {
    font = value;
    notifyListeners();
    await preferences.setString('appearance.font', value.id);
  }

  Future<void> setMode(ThemeMode value) async {
    mode = value;
    timed = false;
    _startClock();
    notifyListeners();
    await preferences.setBool('appearance.timed', false);
    await preferences.setString('appearance.mode', value.name);
  }

  Future<void> setFontScale(double value) async {
    fontScale = value.clamp(.85, 1.2);
    notifyListeners();
    await preferences.setDouble('appearance.fontScale', fontScale);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class AppearanceScope extends InheritedNotifier<AppAppearance> {
  const AppearanceScope({
    required AppAppearance controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppAppearance of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()!.notifier!;
}

/// Semantic colors; new screens should use these rather than fixed surfaces.
class AppPalette {
  AppPalette.of(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get heading => dark ? const Color(0xFFF1F5F9) : const Color(0xFF102A43);
  Color get tealHeading =>
      dark ? const Color(0xFF89DAD0) : const Color(0xFF075C57);
  Color get background =>
      dark ? const Color(0xFF0B1722) : const Color(0xFFFFFCF7);
  Color get surface => dark ? const Color(0xFF132331) : Colors.white;
  Color get muted => dark ? const Color(0xFFA9B8C5) : const Color(0xFF78838D);
  Color get border => dark ? const Color(0xFF314452) : const Color(0xFFE9E5DC);
  Color get paleTeal =>
      dark ? const Color(0xFF173C3E) : const Color(0xFFEAF5F2);
  Color get neutral => dark ? const Color(0xFF1C2C39) : const Color(0xFFFAF8F4);
  Color get notice => dark ? const Color(0xFF342F24) : const Color(0xFFFFF6E6);
  Color get gold => dark ? const Color(0xFFD7B76B) : const Color(0xFFB9964C);
}
