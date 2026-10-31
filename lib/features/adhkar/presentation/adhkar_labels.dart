import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show Bidi;
import '../../../core/localization/app_localization.dart';
import '../../../core/localization/ui_text.dart';
import '../data/adhkar_repository.dart';

String adhkarNumber(BuildContext context, num value) =>
    LocalizationScope.maybeOf(context)?.formats.number(value) ??
    value.toString();
String adhkarPercent(BuildContext context, num value) =>
    LocalizationScope.maybeOf(context)?.formats.percent(value) ??
    '${(value * 100).round()}٪';

String adhkarGroupSize(BuildContext context, int count) =>
    LocalizationScope.maybeOf(context)?.pluralText('adhkar.groupSize', count) ??
    '$count ذكر';
String adhkarRepetitions(BuildContext context, int count) =>
    LocalizationScope.maybeOf(
      context,
    )?.pluralText('adhkar.repetitions', count) ??
    '$count مرة';

TextDirection adhkarTextDirection(String value) =>
    Bidi.detectRtlDirectionality(value) ? TextDirection.rtl : TextDirection.ltr;

double adhkarTileExtent(
  BuildContext context,
  List<DhikrGroup> groups,
  double width,
) {
  final scaler = MediaQuery.textScalerOf(context);
  var required = scaler.scale(152).clamp(156.0, 240.0);
  for (final group in groups) {
    final title = TextPainter(
      text: TextSpan(
        text: group.displayTitle(context),
        style: DefaultTextStyle.of(context).style.merge(
          const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout(maxWidth: width);
    final summary = TextPainter(
      text: TextSpan(
        text: context.tr(
          'adhkar.progress',
          args: {
            'completed': '100',
            'total': '100',
            'read': '1000',
            'target': '1000',
          },
        ),
        style: DefaultTextStyle.of(
          context,
        ).style.merge(const TextStyle(fontSize: 11)),
      ),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 2,
    )..layout(maxWidth: width);
    final height = 86 + title.height + summary.height;
    if (height > required) required = height;
    title.dispose();
    summary.dispose();
  }
  return required;
}

extension DhikrGroupInterface on DhikrGroup {
  String displayTitle(BuildContext context) {
    if (personal != null &&
        (!id.startsWith('daily:') ||
            title !=
                LocalizationScope.maybeOf(
                  context,
                )?.registry['adhkar.group.$id']?['ar'])) {
      return title;
    }
    if (id == 'personal:all') return context.adhkarLabel('كل أذكاري الشخصية');
    if (id == 'group:${AdhkarRepository.savedGroupId}') {
      return context.adhkarLabel('الأذكار المحفوظة');
    }
    return context.tr('adhkar.group.$id', fallback: title);
  }
}

extension DhikrEntryInterface on DhikrEntry {
  String displayTitle(BuildContext context) =>
      personal ? context.adhkarLabel('ذكر شخصي') : title;
  TextDirection get contentDirection =>
      personal ? adhkarTextDirection(text) : TextDirection.rtl;
}
