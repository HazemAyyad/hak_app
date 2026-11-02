import 'package:flutter/widgets.dart';
import '../../../core/localization/app_localization.dart';
import '../../../core/localization/ui_text.dart';
import '../data/religious_catalog.dart';
import '../../../core/localization/content_presentation.dart';
import '../../quran/data/quran_repository.dart' show normalizeQuranSearch;

List<ReligiousItem> religiousSearch(
  BuildContext context,
  ReligiousCatalog catalog, {
  String? category,
  String query = '',
  String? tag,
  Set<String>? favorites,
}) {
  final items = catalog.search(
    category: category,
    tag: tag,
    favorites: favorites,
  );
  final needle = normalizeQuranSearch(query);
  if (needle.isEmpty) return items;
  return items
      .where(
        (item) =>
            item.searchable.contains(needle) ||
            normalizeQuranSearch(
              '${item.displayTitle(context)} ${item.presentation(context)?.title ?? ''} ${item.displaySummary(context)} ${item.displaySource(context)}',
            ).contains(needle),
      )
      .toList();
}

extension ReligiousCategoryInterface on ReligiousCategory {
  String interfaceTitle(BuildContext context) => context.tr(
    'religious.category.$id.title',
    fallback: context.religiousLabel(title),
  );
  String interfaceDescription(BuildContext context) =>
      context.tr('religious.category.$id.description', fallback: description);
}

extension ReligiousItemPresentation on ReligiousItem {
  PresentedSourceContent? presentation(BuildContext context) =>
      PresentedSourceContent.forContent(context, id, text);
  String displayTitle(BuildContext context) {
    final locale = LocalizationScope.maybeOf(context)?.contentCode ?? 'ar';
    if (locale == 'ar' || type == 'name') return title;
    if (type == 'playlist')
      return context.tr('religious.ruqyaPlaylistTitle', fallback: title);
    if (type == 'quran' && verseKeys.isNotEmpty) {
      final parts = verseKeys.first.split(':');
      return context.tr(
        verseKeys.length == 1 ? 'search.verse' : 'search.surah',
        args: {
          'name': context.tr('quran.surah.${parts.first}'),
          'ayah': parts.last,
        },
      );
    }
    final translated = presentation(context)?.title ?? '';
    return translated.isEmpty ? title : translated;
  }

  String displaySummary(BuildContext context) =>
      presentation(context)?.preview ?? summary;
  String displaySource(BuildContext context) =>
      presentation(context)?.sourceName ?? source;
  String displayReference(BuildContext context) {
    if (type != 'quran' ||
        verseKeys.isEmpty ||
        (LocalizationScope.maybeOf(context)?.contentCode ?? 'ar') == 'ar')
      return source;
    return verseKeys.length == 1
        ? displayTitle(context)
        : '${displayTitle(context)} • ${verseKeys.first.split(':').last}–${verseKeys.last.split(':').last}';
  }

  String displayText(BuildContext context) =>
      type == 'quran' ? text : presentation(context)?.text ?? text;
}

extension ReligiousMoodInterface on ReligiousMood {
  String interfaceTitle(BuildContext context) =>
      context.tr('religious.mood.$id.title', fallback: title);
}

String religiousNumber(BuildContext context, int value) =>
    LocalizationScope.maybeOf(context)?.formats.integer(value) ??
    value.toString();
