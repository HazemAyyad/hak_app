import 'dart:async';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// CLDR formatting for ordinary interface data, never for scripture or identifiers.
class LocaleFormats {
  const LocaleFormats(this.code);
  final String code;
  static Future<void>? _initialization;
  static Future<void> prepare() =>
      _initialization ??= initializeDateFormatting();

  String _supported(bool Function(String) exists) {
    final canonical = Intl.canonicalizedLocale(code);
    if (exists(canonical)) return canonical;
    final language = canonical.split('_').first;
    return exists(language) ? language : 'en_US';
  }

  String number(num value) => NumberFormat.decimalPattern(
    _supported(NumberFormat.localeExists),
  ).format(value);

  // Gregorian dates only. Hijri dates retain the app's separate verified calendar.
  String gregorianDate(DateTime value) =>
      DateFormat.yMMMd(_dateLocale).format(value);

  String get _dateLocale {
    // Bundled Intl symbols are registered synchronously before this Future completes.
    unawaited(prepare());
    return _supported(DateFormat.localeExists);
  }

  String gregorianDateTime(DateTime value) =>
      DateFormat.yMMMd(_dateLocale).add_jm().format(value);

  String pluralCategory(num count) => Intl.pluralLogic(
    count,
    locale: Intl.canonicalizedLocale(code),
    useExplicitNumberCases: false,
    zero: 'zero',
    one: 'one',
    two: 'two',
    few: 'few',
    many: 'many',
    other: 'other',
  );
}
