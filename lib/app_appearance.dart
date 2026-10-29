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

enum MoreDirectoryLayout { grid, list }

enum AppColor {
  haq('حق الأصلي', Color(0xFF2A8C82)),
  emerald('زمردي', Color(0xFF26734D)),
  olive('زيتوني', Color(0xFF626C32)),
  gold('ذهبي', Color(0xFF87651F)),
  sand('رملي', Color(0xFF8A6241)),
  rose('وردي هادئ', Color(0xFF9A526B)),
  plum('برقوقي', Color(0xFF825279)),
  violet('بنفسجي', Color(0xFF6C58A0)),
  indigo('نيلي', Color(0xFF4E6097)),
  blue('أزرق هادئ', Color(0xFF286E96));

  const AppColor(this.label, this.seed);
  final String label;
  final Color seed;
}

/// Keeps the original artwork's palette until a different accent is selected.
class AppAccent extends ThemeExtension<AppAccent> {
  const AppAccent(this.color, this.brightness);
  final AppColor color;
  final Brightness brightness;
  bool get original => color == AppColor.haq;
  Color get primary => brightness == Brightness.dark
      ? Color.lerp(color.seed, Colors.white, .55)!
      : color.seed;
  Color get strong => Color.lerp(color.seed, Colors.black, .2)!;
  Color get soft => Color.lerp(
    color.seed,
    brightness == Brightness.dark ? const Color(0xFF0B1722) : Colors.white,
    brightness == Brightness.dark ? .75 : .91,
  )!;

  @override
  AppAccent copyWith({AppColor? color, Brightness? brightness}) =>
      AppAccent(color ?? this.color, brightness ?? this.brightness);

  @override
  AppAccent lerp(covariant AppAccent? other, double t) =>
      other == null || t < .5 ? this : other;
}

/// Replaces decorative accents, preserving semantic colors and source images.
Color appAccent(BuildContext context, Color original) {
  final accent = Theme.of(context).extension<AppAccent>();
  return accent == null || accent.original ? original : accent.primary;
}

Color appAccentFill(BuildContext context, Color original) {
  final accent = Theme.of(context).extension<AppAccent>();
  return accent == null || accent.original ? original : accent.strong;
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
    color = AppColor.values.firstWhere(
      (value) => value.name == preferences.getString('appearance.color'),
      orElse: () => AppColor.haq,
    );
    moreDirectoryLayout = MoreDirectoryLayout.values.firstWhere(
      (value) => value.name == preferences.getString('appearance.moreLayout'),
      orElse: () => MoreDirectoryLayout.grid,
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
  late AppColor color;
  late MoreDirectoryLayout moreDirectoryLayout;
  final DateTime Function() clock;
  late bool timed;
  late int dayStart, nightStart;
  Timer? _timer;
  ThemeMode? _lastMode;
  bool? _lastDaytime;
  bool get isDaytime {
    final now = clock(), minute = now.hour * 60 + now.minute;
    return dayStart < nightStart
        ? minute >= dayStart && minute < nightStart
        : minute >= dayStart || minute < nightStart;
  }

  String get dailyAdhkarGroup => isDaytime ? 'daily:morning' : 'daily:evening';

  ThemeMode get effectiveMode {
    if (!timed) return mode;
    return isDaytime ? ThemeMode.light : ThemeMode.dark;
  }

  void refreshTime() {
    final nextMode = effectiveMode, nextDaytime = isDaytime;
    if (_lastMode == nextMode && _lastDaytime == nextDaytime) return;
    _lastMode = nextMode;
    _lastDaytime = nextDaytime;
    notifyListeners();
  }

  void _startClock() {
    _timer?.cancel();
    _lastMode = effectiveMode;
    _lastDaytime = isDaytime;
    if (!hasListeners) return;
    // The home card follows the clock even with a manually selected theme.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refreshTime());
  }

  @override
  void addListener(VoidCallback listener) {
    final listening = hasListeners;
    super.addListener(listener);
    if (!listening) _startClock();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _timer?.cancel();
  }

  Future<void> setColor(AppColor value) async {
    color = value;
    notifyListeners();
    await preferences.setString('appearance.color', value.name);
  }

  Future<void> setMoreDirectoryLayout(MoreDirectoryLayout value) async {
    if (moreDirectoryLayout == value) return;
    moreDirectoryLayout = value;
    notifyListeners();
    await preferences.setString('appearance.moreLayout', value.name);
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
    : dark = Theme.of(context).brightness == Brightness.dark,
      accent = Theme.of(context).extension<AppAccent>();
  final bool dark;
  final AppAccent? accent;
  Color get heading => dark ? const Color(0xFFF1F5F9) : const Color(0xFF102A43);
  Color get tealHeading => accent != null && !accent!.original
      ? accent!.primary
      : dark
      ? const Color(0xFF89DAD0)
      : const Color(0xFF075C57);
  Color get background =>
      dark ? const Color(0xFF0B1722) : const Color(0xFFFFFCF7);
  Color get surface => dark ? const Color(0xFF132331) : Colors.white;
  Color get muted => dark ? const Color(0xFFA9B8C5) : const Color(0xFF78838D);
  Color get border => dark ? const Color(0xFF314452) : const Color(0xFFE9E5DC);
  Color get paleTeal => accent != null && !accent!.original
      ? accent!.soft
      : dark
      ? const Color(0xFF173C3E)
      : const Color(0xFFEAF5F2);
  Color get neutral => dark ? const Color(0xFF1C2C39) : const Color(0xFFFAF8F4);
  Color get notice => dark ? const Color(0xFF342F24) : const Color(0xFFFFF6E6);
  Color get gold => dark ? const Color(0xFFD7B76B) : const Color(0xFFB9964C);
}
