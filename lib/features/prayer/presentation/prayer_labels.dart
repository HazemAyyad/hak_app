import 'package:flutter/widgets.dart';
import '../../../core/localization/app_localization.dart';
import '../../../core/localization/ui_text.dart';
import '../data/prayer_controller.dart';
import '../data/prayer_models.dart';
import '../data/place_catalog.dart';
import '../data/prayer_alert.dart';

extension PrayerAlertInterfaceLabel on PrayerAlertMode {
  String displayLabel(BuildContext context) => context.prayerLabel(label);
}

extension AdhanVoiceInterfaceLabel on AdhanVoice {
  String displayLabel(BuildContext context) =>
      LocalizationScope.maybeOf(context)?.code == 'en'
      ? englishName ?? name
      : name;
}

extension PrayerNameInterfaceLabel on PrayerName {
  String displayLabel(BuildContext context) => context.prayerLabel(label);
}

extension PrayerMethodInterfaceLabel on PrayerMethod {
  String displayLabel(BuildContext context) => context.prayerLabel(label);
}

extension PrayerDialectInterfaceLabel on PrayerReminderDialect {
  String displayLabel(BuildContext context) => context.prayerLabel(label);
}

String prayerCountryLabel(BuildContext context, PlaceCountry country) =>
    LocalizationScope.maybeOf(context)?.code == 'en'
    ? country.english
    : country.name;
String prayerCityLabel(BuildContext context, PlaceCity city) =>
    LocalizationScope.maybeOf(context)?.code == 'en' ? city.english : city.name;

String prayerHijriInterfaceLabel(
  BuildContext context,
  PrayerController controller,
) {
  final localization = LocalizationScope.maybeOf(context);
  if (localization == null || localization.code == 'ar') {
    return controller.hijriLabel;
  }
  final parts = controller.hijriParts;
  if (parts == null) return controller.hijriLabel;
  return localization.text(
    'prayer.hijriDate',
    args: {
      'day': localization.formats.integer(parts.day),
      'month': localization.text('prayer.hijriMonth.${parts.month}'),
      'year': localization.formats.integer(parts.year),
    },
  );
}
