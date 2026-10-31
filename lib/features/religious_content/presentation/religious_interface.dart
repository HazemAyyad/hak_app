import 'package:flutter/widgets.dart';
import '../../../core/localization/app_localization.dart';
import '../../../core/localization/ui_text.dart';
import '../data/religious_catalog.dart';

extension ReligiousCategoryInterface on ReligiousCategory {
  String interfaceTitle(BuildContext context) => context.tr(
    'religious.category.$id.title',
    fallback: context.religiousLabel(title),
  );
}

extension ReligiousMoodInterface on ReligiousMood {
  String interfaceTitle(BuildContext context) =>
      context.tr('religious.mood.$id.title', fallback: title);
}

String religiousNumber(BuildContext context, int value) =>
    LocalizationScope.maybeOf(context)?.formats.integer(value) ??
    value.toString();
