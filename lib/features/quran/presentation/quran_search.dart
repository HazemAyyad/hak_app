import '../../../core/localization/ui_text.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_appearance.dart';
import '../../../app_loading.dart';
import '../../../core/localization/app_localization.dart';
import '../../../core/localization/quran_translation_source.dart';
import '../../../core/localization/source_text.dart';
import '../../../core/localization/religious_translation_library.dart';
import '../data/quran_controller.dart';
import '../data/quran_repository.dart';
import '../data/quran_cached_search.dart';
import 'quran_widgets.dart';

class QuranSearchPage extends StatefulWidget {
  const QuranSearchPage({
    super.key,
    required this.controller,
    required this.onRead,
    this.initialQuery = '',
  });
  final QuranController controller;
  final void Function(QuranVerse, String) onRead;
  final String initialQuery;
  @override
  State<QuranSearchPage> createState() => _QuranSearchPageState();
}

class _QuranSearchPageState extends State<QuranSearchPage> {
  late final TextEditingController query;
  final scroll = ScrollController();
  Timer? debounce;
  int? surahId, juzId;
  bool group = true, fullText = true;
  List<QuranVerse> results = [];
  String executedQuery = '';
  int type = 0, generation = 0;
  bool searching = false;
  Map<String, QuranContentMatch> contentMatches = {};
  QuranTranslationSource? _source;
  String? _contentLocale;

  String _surahLabel(int id) {
    final name = widget.controller.repository!.surah(id).localizedName(context);
    return context.tr(
      'search.surah',
      fallback: 'سورة $name',
      args: {'name': name},
    );
  }

  String _juzLabel(int id) {
    final localization = LocalizationScope.maybeOf(context);
    return localization == null || localization.code == 'ar'
        ? juzName(id)
        : localization.text(
            'search.juz',
            args: {'number': localization.formats.number(id)},
          );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final localization = LocalizationScope.maybeOf(context);
    final source =
        localization?.installed[localization.contentCode]?.quranSource;
    if (!identical(source, _source) ||
        _contentLocale != localization?.contentCode) {
      _source = source;
      _contentLocale = localization?.contentCode;
      if (type == 3) _search();
    }
  }

  @override
  void initState() {
    super.initState();
    query = TextEditingController(text: widget.initialQuery);
    _search();
  }

  @override
  void dispose() {
    debounce?.cancel();
    query.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    debounce?.cancel();
    final request = ++generation;
    setState(() {
      executedQuery = query.text.trim();
      contentMatches = {};
      searching = type != 0;
      results = type == 0
          ? widget.controller.repository!.search(
              executedQuery,
              surahId: surahId,
              juzId: juzId,
            )
          : [];
    });
    if (type == 0) return;
    if (type == 3) {
      final repo = widget.controller.repository!;
      final matches = <QuranContentMatch>[];
      final meanings = <String, PublishedVerseMeaning>{};
      String? attribution;
      if (ReligiousTranslationLibrary.supports(_contentLocale ?? 'ar')) {
        try {
          final bundled = await ReligiousTranslationLibrary.shared.load(
            _contentLocale!,
            'quran',
          );
          if (!mounted || request != generation) return;
          final needle = normalizeMeaningSearch(executedQuery);
          for (final entry in (bundled.data['verses'] as Map).entries) {
            final row = entry.value as Map;
            if (needle.isNotEmpty &&
                normalizeMeaningSearch(
                  plainSourceText(row['text'] as String),
                ).contains(needle)) {
              meanings[entry.key as String] = PublishedVerseMeaning(
                entry.key as String,
                row['text'] as String,
                row['footnotes'] as String,
              );
            }
          }
          attribution =
              '${bundled.source['provider']} — ${bundled.source['title']} — v${bundled.source['version']}';
        } catch (_) {
          // A verified downloaded source remains searchable independently.
        }
      }
      final downloadedKeys = <String>{};
      for (final row
          in _source?.search(executedQuery) ?? <PublishedVerseMeaning>[]) {
        meanings[row.key] = row;
        downloadedKeys.add(row.key);
      }
      if (!mounted || request != generation) return;
      for (final meaning in meanings.values) {
        final verse = repo.byKey[meaning.key];
        if (verse == null ||
            surahId != null && verse.surah != surahId ||
            juzId != null && verse.juz != juzId) {
          continue;
        }
        matches.add(
          QuranContentMatch(
            verse,
            plainSourceText(meaning.translation),
            downloadedKeys.contains(meaning.key)
                ? _source!.attribution
                : attribution!,
          ),
        );
      }
      matches.sort(
        (a, b) => a.verse.surah == b.verse.surah
            ? a.verse.ayah.compareTo(b.verse.ayah)
            : a.verse.surah.compareTo(b.verse.surah),
      );
      setState(() {
        contentMatches = {for (final match in matches) match.verse.key: match};
        results = matches.map((match) => match.verse).toList();
        searching = false;
      });
      return;
    }
    try {
      final found = await searchQuranCache(
        widget.controller.content,
        widget.controller.repository!,
        executedQuery,
        meanings: type == 2,
        surah: surahId,
        juz: juzId,
      );
      if (!mounted || request != generation) return;
      setState(() {
        contentMatches = {for (final match in found) match.verse.key: match};
        results = found.map((m) => m.verse).toList();
        searching = false;
      });
    } catch (_) {
      if (mounted && request == generation) setState(() => searching = false);
    }
  }

  void _changed(String _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), _search);
  }

  Future<void> _filters() async {
    var scope = surahId != null
        ? 1
        : juzId != null
        ? 2
        : 0;
    var surah = surahId ?? 1;
    var juz = juzId ?? 1;
    var grouped = group;
    var full = fullText;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).surface,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.quranLabel('تصفية نتائج البحث'),
                  style: qText(
                    context,
                    size: 21,
                    weight: FontWeight.w800,
                    color: AppPalette.of(context).tealHeading,
                  ),
                ),
                Text(
                  context.quranLabel('حدد معايير البحث لعرض نتائج أكثر دقة'),
                  style: qText(context, size: 12),
                ),
                const SizedBox(height: 20),
                QCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.quranLabel('نطاق البحث'),
                        style: qText(
                          context,
                          size: 17,
                          weight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      QSegments(
                        labels: const ['كل القرآن', 'سورة محددة', 'جزء محدد'],
                        selected: scope,
                        onSelect: (value) => update(() => scope = value),
                      ),
                    ],
                  ),
                ),
                if (scope == 1) ...[
                  const SizedBox(height: 12),
                  QCard(
                    child: DropdownButtonFormField<int>(
                      initialValue: surah,
                      decoration: InputDecoration(
                        labelText: context.quranLabel('اختر السورة'),
                        labelStyle: qText(context, size: 12),
                      ),
                      items: widget.controller.repository!.surahs
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(_surahLabel(s.id)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => update(() => surah = value!),
                    ),
                  ),
                ],
                if (scope == 2) ...[
                  const SizedBox(height: 12),
                  QCard(
                    child: DropdownButtonFormField<int>(
                      initialValue: juz,
                      decoration: InputDecoration(
                        labelText: context.quranLabel('اختر الجزء'),
                        labelStyle: qText(context, size: 12),
                      ),
                      items: widget.controller.repository!.juzs
                          .map(
                            (j) => DropdownMenuItem(
                              value: j.id,
                              child: Text(_juzLabel(j.id)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => update(() => juz = value!),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                QCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.quranLabel('خيارات إضافية'),
                        style: qText(
                          context,
                          size: 17,
                          weight: FontWeight.w800,
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: qAccent(context),
                        title: Text(
                          context.quranLabel('تجميع النتائج حسب السور'),
                          style: qText(context, size: 12),
                        ),
                        value: grouped,
                        onChanged: (value) => update(() => grouped = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: qAccent(context),
                        title: Text(
                          context.quranLabel('عرض نص الآية بالكامل'),
                          style: qText(context, size: 12),
                        ),
                        value: full,
                        onChanged: (value) => update(() => full = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: QPrimaryButton(
                        label: context.quranLabel('عرض النتائج'),
                        icon: Icons.search,
                        onTap: () => Navigator.pop(context, true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton.icon(
                      onPressed: () => update(() {
                        scope = 0;
                        grouped = true;
                        full = true;
                      }),
                      icon: const Icon(Icons.restart_alt, color: qGold),
                      label: Text(
                        context.quranLabel('إعادة الضبط'),
                        style: qText(context, color: qGold, size: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied != true || !mounted) return;
    surahId = scope == 1 ? surah : null;
    juzId = scope == 2 ? juz : null;
    group = grouped;
    fullText = full;
    _search();
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.controller.repository!;
    return CustomScrollView(
      controller: scroll,
      slivers: [
        SliverToBoxAdapter(
          child: QuranHeader(
            title: 'البحث في القرآن الكريم',
            subtitle: 'ابحث في آيات القرآن الكريم',
            dark: true,
            height: 164,
            onBack: () => Navigator.pop(context),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                QSearchField(
                  controller: query,
                  hint: 'ابحث بكلمة أو عبارة ...',
                  onChanged: _changed,
                  onSubmit: (_) => _search(),
                  trailing: IconButton(
                    tooltip: context.quranLabel('تصفية نتائج البحث'),
                    icon: Icon(Icons.tune, color: qAccent(context)),
                    onPressed: _filters,
                  ),
                ),
                const SizedBox(height: 10),
                QSegments(
                  labels: [
                    'الآيات',
                    'التفسير',
                    'معاني الكلمات',
                    context.tr('search.translation', fallback: 'ترجمة المعاني'),
                  ],
                  selected: type,
                  onSelect: (value) {
                    type = value;
                    _search();
                  },
                ),
                if (type != 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      type == 3
                          ? context.tr(
                              _source == null
                                  ? 'search.translationUnavailable'
                                  : 'search.translationNotice',
                            )
                          : context.tr(
                              type == 1
                                  ? 'search.cachedTafsir'
                                  : 'search.cachedMeanings',
                              fallback:
                                  'البحث في ${type == 1 ? 'التفاسير' : 'المعاني'} التي فُتحت وحُفظت على هذا الجهاز فقط. افتح المحتوى المطلوب لتنزيله أولًا.',
                            ),
                      style: qText(
                        context,
                        size: 11,
                        color: AppPalette.of(context).muted,
                      ),
                    ),
                  ),
                if (searching) LinearProgressIndicator(color: qAccent(context)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        executedQuery.isEmpty
                            ? context.quranLabel('البحث يعمل دون إنترنت')
                            : context.tr(
                                'search.results',
                                fallback: 'نتائج البحث: ${results.length}',
                                args: {
                                  'count':
                                      LocalizationScope.maybeOf(
                                        context,
                                      )?.formats.number(results.length) ??
                                      results.length,
                                },
                              ),
                        style: qText(
                          context,
                          size: 12,
                          color: AppPalette.of(context).muted,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _filters,
                      icon: const Icon(Icons.filter_alt_outlined, size: 17),
                      label: Text(
                        surahId != null
                            ? _surahLabel(surahId!)
                            : juzId != null
                            ? _juzLabel(juzId!)
                            : context.quranLabel('كل القرآن'),
                        style: qText(
                          context,
                          size: 11,
                          color: qAccent(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (searching)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: AppLoadingSkeleton(
                label: context.quranLabel('جارٍ البحث'),
                page: false,
              ),
            ),
          ),
        if (!searching && executedQuery.isNotEmpty && results.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 35),
              child: QCard(
                child: Column(
                  children: [
                    const Icon(Icons.search_off, size: 66, color: qGold),
                    const SizedBox(height: 12),
                    Text(
                      context.quranLabel('لا توجد نتائج بحث'),
                      style: qText(context, size: 22, weight: FontWeight.w800),
                    ),
                    Text(
                      context.quranLabel(
                        'جرّب كلمة أخرى أو أعد ضبط نطاق البحث',
                      ),
                      textAlign: TextAlign.center,
                      style: qText(
                        context,
                        size: 13,
                        color: AppPalette.of(context).muted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    QPrimaryButton(
                      label: context.quranLabel('إعادة ضبط التصفية'),
                      onTap: () {
                        surahId = null;
                        juzId = null;
                        _search();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 105),
          sliver: SliverList.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final verse = results[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (group &&
                      (index == 0 || results[index - 1].surah != verse.surah))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _surahLabel(verse.surah),
                        style: qText(
                          context,
                          size: 17,
                          weight: FontWeight.w800,
                          color: AppPalette.of(context).tealHeading,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: QCard(
                      onTap: () {
                        debounce?.cancel();
                        widget.onRead(verse, executedQuery);
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.chevron_right, color: qAccent(context)),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.tr(
                                    'search.verse',
                                    fallback:
                                        'سورة ${repo.surah(verse.surah).localizedName(context)} • الآية ${verse.ayah}',
                                    args: {
                                      'name': repo
                                          .surah(verse.surah)
                                          .localizedName(context),
                                      'ayah': quranNumber(context, verse.ayah),
                                    },
                                  ),
                                  style: qText(
                                    context,
                                    size: 12,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                if (type == 3)
                                  Text(
                                    verse.text,
                                    textDirection: TextDirection.rtl,
                                    style: const TextStyle(
                                      fontFamily: 'AmiriQuran',
                                      fontSize: 20,
                                      height: 1.8,
                                    ),
                                  ),
                                Text(
                                  contentMatches[verse.key]?.text ?? verse.text,
                                  textDirection: type == 3
                                      ? (_source?.direction == 'rtl'
                                            ? TextDirection.rtl
                                            : TextDirection.ltr)
                                      : TextDirection.rtl,
                                  maxLines: fullText ? null : 3,
                                  overflow: fullText
                                      ? null
                                      : TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: type == 0
                                        ? 'AmiriQuran'
                                        : 'QuranUI',
                                    fontSize: type == 0 ? 20 : 13,
                                    height: 1.8,
                                    color: AppPalette.of(context).heading,
                                  ),
                                ),
                                if (type != 0)
                                  Text(
                                    contentMatches[verse.key]?.source ?? '',
                                    style: qText(
                                      context,
                                      size: 10,
                                      color: qAccent(context),
                                    ),
                                  ),
                                Text(
                                  context.tr(
                                    'search.location',
                                    fallback:
                                        '${juzName(verse.juz)} • الصفحة ${verse.page}',
                                    args: {
                                      'juz': _juzLabel(verse.juz),
                                      'page': quranNumber(context, verse.page),
                                    },
                                  ),
                                  style: qText(
                                    context,
                                    size: 10,
                                    color: AppPalette.of(context).muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          QMedallion(number: verse.ayah, size: 36),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
