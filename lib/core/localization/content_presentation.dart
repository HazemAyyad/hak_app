import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_localization.dart';
import 'published_meaning_card.dart';
import 'religious_translation_library.dart';
import 'source_text.dart';
import 'ui_text.dart';

/// Makes verified source text available to the existing reading surfaces.
/// No catalog, personal text, counters, audio identities or saved data is edited.
class ContentPresentationScope extends StatefulWidget {
  const ContentPresentationScope({super.key, required this.child});
  final Widget child;
  static ReligiousTranslationLibrary libraryOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ContentLibrary>()?.notifier ??
      ReligiousTranslationLibrary.shared;
  @override
  State<ContentPresentationScope> createState() =>
      _ContentPresentationScopeState();
}

class _ContentPresentationScopeState extends State<ContentPresentationScope> {
  String? _locale;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = LocalizationScope.maybeOf(context)?.contentCode ?? 'ar';
    if (locale == _locale) return;
    _locale = locale;
    if (ReligiousTranslationLibrary.supports(locale)) {
      for (final kind in ['names', 'dhikr', 'hadith', 'quran']) {
        unawaited(
          ReligiousTranslationLibrary.shared
              .load(locale, kind)
              .then<void>((_) {}, onError: (Object _) {}),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => _ContentLibrary(
    notifier: ReligiousTranslationLibrary.shared,
    child: widget.child,
  );
}

class _ContentLibrary extends InheritedNotifier<ReligiousTranslationLibrary> {
  const _ContentLibrary({required super.notifier, required super.child});
}

class PresentedSourceContent {
  const PresentedSourceContent({
    required this.locale,
    required this.kind,
    required this.source,
    required this.records,
    this.commentaryMissing = false,
    this.hasScripture = false,
  });
  final String locale, kind;
  final Map<String, dynamic> source;
  final List<Map<String, dynamic>> records;
  final bool commentaryMissing;
  final bool hasScripture;
  String get title => kind == 'quran' || kind == 'tafsir'
      ? ''
      : plainSourceText(records.first['title'] as String? ?? '');
  String get text => records.map((row) => row['text'] as String).join('\n\n');
  String get preview => plainSourceText(text);
  List<Map<String, dynamic>> get sources {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final row in records) {
      final metadata = row['source'] is Map
          ? Map<String, dynamic>.from(row['source'] as Map)
          : source;
      final key =
          '${metadata['url']}/${metadata['version']}/${metadata['title']}';
      if (seen.add(key)) result.add(metadata);
    }
    return result.isEmpty ? [source] : result;
  }

  Map<String, dynamic> get primarySource => sources.first;
  static String sourceTitle(Map<String, dynamic> value) =>
      (value['display_title'] ??
              value['name'] ??
              value['title'] ??
              value['provider'] ??
              '')
          as String;
  String get sourceName => sourceTitle(primarySource);
  String get explanation => records
      .map((row) => (row['fields'] as Map?)?['explanation'] as String? ?? '')
      .where((text) => text.isNotEmpty)
      .join('\n\n');

  static PresentedSourceContent? forContent(
    BuildContext context,
    String id,
    String original, {
    String? kind,
  }) {
    final localization = LocalizationScope.maybeOf(context);
    if (localization == null || localization.contentCode == 'ar') return null;
    final locale = localization.contentCode;
    final pack = localization.installed[locale];
    final hadith = pack?.hadithSource?.forContent(id, original);
    if (hadith != null) {
      return PresentedSourceContent(
        locale: locale,
        kind: 'hadith',
        source: {
          'title': pack!.hadithSource!.attribution,
          'provider': 'HadeethEnc.com',
          ...pack.hadithSource!.source,
        },
        records: [
          {
            'title': hadith['title'],
            'text': hadith['hadith_text'],
            'source_arabic': hadith['hadith_text_ar'],
            'fields': hadith,
            'source_url': hadith['link'],
          },
        ],
      );
    }
    final edited = localization.content(id);
    if (edited != null) {
      return PresentedSourceContent(
        locale: locale,
        kind: kind ?? 'content',
        source: {'title': edited['source'], 'url': edited['sourceUrl']},
        records: [
          {...edited},
        ],
      );
    }
    final meanings = pack?.quranSource?.forContent(id);
    if (meanings != null && meanings.isNotEmpty) {
      final source = pack!.quranSource!;
      return PresentedSourceContent(
        locale: locale,
        kind: 'quran',
        source: {
          'title': source.title,
          'version': source.version,
          'url': 'https://quranenc.com/en/home',
        },
        records: [
          for (final verse in meanings)
            {
              'title': verse.key,
              'text': verse.translation,
              'footnotes': verse.footnotes,
            },
        ],
      );
    }
    final selectedKind = kind ?? ReligiousTranslationLibrary.kindForContent(id);
    if (selectedKind == null) return null;
    final collection = ContentPresentationScope.libraryOf(
      context,
    ).cached(locale, selectedKind);
    if (collection == null) return null;
    final rows = collection.forContent(id, original);
    if (rows.isEmpty) return null;
    final scripture = collection.data['scripture'] as Map? ?? const {};
    final chapterIds =
        ((collection.data['chapters'] as Map?)?[id] as Map?)?['entries']
            as List? ??
        const [];
    return PresentedSourceContent(
      locale: locale,
      kind: selectedKind,
      source: collection.source,
      records: rows,
      hasScripture:
          selectedKind == 'quran' ||
          scripture.containsKey(id) ||
          chapterIds.any(scripture.containsKey),
    );
  }
}

/// A body only: the caller owns the established card, title and spacing.
class PresentedSourceText extends StatelessWidget {
  const PresentedSourceText(
    this.content, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
  });
  final PresentedSourceContent content;
  final TextStyle? style;
  final TextAlign textAlign;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, row) in content.records.indexed)
        Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
          child: PublishedTranslationText(
            row['text'] as String,
            style: style,
            textAlign: textAlign,
          ),
        ),
    ],
  );
}

class PresentedSourceFooter extends StatelessWidget {
  const PresentedSourceFooter(this.content, {super.key});
  final PresentedSourceContent content;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, row) in content.records.indexed)
        if ((row['footnotes'] as String? ?? '').trim().isNotEmpty)
          ExpansionTile(
            key: PageStorageKey(
              'inline/${content.locale}/${content.kind}/$index/${row['original_sha256'] ?? row['title']}/footnotes',
            ),
            tilePadding: EdgeInsets.zero,
            title: Text(context.tr('source.footnotes')),
            children: [PublishedTranslationText(row['footnotes'] as String)],
          ),
      for (final row in content.records)
        if (((row['fields'] as Map?)?['grade'] as String? ?? '').isNotEmpty)
          Text(
            '${context.tr('hadith.grade')}: ${plainSourceText((row['fields'] as Map)['grade'] as String)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      for (final metadata in content.sources)
        Text(
          PresentedSourceContent.sourceTitle(metadata),
          textDirection: contentTextDirection(content.sourceName),
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      if (LocalizationScope.maybeOf(context)?.showSourceLinks == true)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            icon: const Icon(Icons.info_outline, size: 16),
            label: Text(context.tr('source.details')),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (context) => DraggableScrollableSheet(
                expand: false,
                initialChildSize: .65,
                minChildSize: .3,
                builder: (context, scroll) => ListView(
                  controller: scroll,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      content.sourceName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${content.primarySource['provider'] ?? ''} ${content.primarySource['version'] ?? ''}',
                    ),
                    for (final row in content.records) ...[
                      if (row['alignment'] == 'publisher_record_variant')
                        Text(context.tr('source.narrationNotice')),
                      if ((row['source_url'] as String? ?? '').isNotEmpty)
                        _PublisherLink(
                          row['source_url'] as String,
                          'source.openRecord',
                        ),
                      if ((row['fields'] as Map?) case final fields?)
                        for (final pair in const [
                          ('grade', 'hadith.grade'),
                          ('takhrij', 'hadith.reference'),
                          ('benefits', 'hadith.benefits'),
                        ])
                          if ((fields[pair.$1] as String? ?? '')
                              .isNotEmpty) ...[
                            Text(
                              context.tr(pair.$2),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            PublishedTranslationText(fields[pair.$1] as String),
                          ],
                      if (row['source'] is Map) ...[
                        Text((row['source'] as Map)['title'] as String? ?? ''),
                        if ((row['source'] as Map)['url'] is String)
                          _PublisherLink(
                            (row['source'] as Map)['url'] as String,
                            'source.openPublisher',
                          ),
                      ],
                    ],
                    if (content.records.any((row) => row['source'] == null) &&
                        content.source['url'] is String)
                      _PublisherLink(
                        content.source['url'] as String,
                        'source.openPublisher',
                      ),
                    if (content.records.any((row) => row['source'] == null) &&
                        content.source['document'] is String)
                      SelectableText(
                        content.source['document'] as String,
                        key: const PageStorageKey(
                          'inline-source-document-scroll',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _PublisherLink extends StatelessWidget {
  const _PublisherLink(this.url, this.label);
  final String url, label;
  @override
  Widget build(BuildContext context) =>
      LocalizationScope.maybeOf(context)?.showSourceLinks != true
      ? const SizedBox.shrink()
      : TextButton.icon(
          icon: const Icon(Icons.open_in_new, size: 16),
          label: Text(context.tr(label)),
          onPressed: () async {
            if (LocalizationScope.maybeOf(context)?.showSourceLinks != true) {
              return;
            }
            final uri = Uri.tryParse(url);
            if (uri?.scheme == 'https') {
              await launchUrl(uri!, mode: LaunchMode.externalApplication);
            }
          },
        );
}

class VerseMeaningBody extends StatelessWidget {
  const VerseMeaningBody({super.key, required this.verseKey});
  final String verseKey;
  @override
  Widget build(BuildContext context) {
    final localization = LocalizationScope.maybeOf(context);
    final locale = localization?.contentCode ?? 'ar';
    if (locale == 'ar') return const SizedBox.shrink();
    final published = localization?.installed[locale]?.quranSource;
    final verse = published?.verses[verseKey];
    if (verse != null) {
      return _body(
        context,
        PresentedSourceContent(
          locale: locale,
          kind: 'quran',
          source: {
            'title': published!.title,
            'version': published.version,
            'url': 'https://quranenc.com/en/home',
          },
          records: [
            {
              'title': verse.key,
              'text': verse.translation,
              'footnotes': verse.footnotes,
            },
          ],
        ),
      );
    }
    if (!ReligiousTranslationLibrary.supports(locale)) {
      return Text(context.tr('content.missing'));
    }
    return FutureBuilder<SourceCollection>(
      key: ValueKey('meaning-inline-$locale-$verseKey'),
      future: ReligiousTranslationLibrary.shared.load(locale, 'quran'),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(context.tr('source.localUnavailable'));
        }
        if (!snapshot.hasData) return const SizedBox.shrink();
        final rows = snapshot.data!.forVerse(verseKey);
        if (rows.isEmpty) return Text(context.tr('content.missing'));
        return _body(
          context,
          PresentedSourceContent(
            locale: locale,
            kind: 'quran',
            source: snapshot.data!.source,
            records: rows,
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, PresentedSourceContent content) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('source.meanings'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        PresentedSourceText(
          content,
          style: const TextStyle(fontSize: 16, height: 1.7),
        ),
        PresentedSourceFooter(content),
      ],
    ),
  );
}

class BundledTafsirBody extends StatelessWidget {
  const BundledTafsirBody({super.key, this.verseKey, this.chapter})
    : assert((verseKey == null) != (chapter == null));
  final String? verseKey;
  final int? chapter;
  @override
  Widget build(BuildContext context) {
    final locale = LocalizationScope.maybeOf(context)?.contentCode ?? 'ar';
    if (!ReligiousTranslationLibrary.supports(locale)) {
      return Text(context.tr('content.missing'));
    }
    return FutureBuilder<SourceCollection>(
      key: ValueKey('inline-tafsir-$locale-${verseKey ?? chapter}'),
      future: ReligiousTranslationLibrary.shared.load(locale, 'tafsir'),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(context.tr('source.localUnavailable'));
        }
        if (!snapshot.hasData) return Text(context.tr('common.loading'));
        final collection = snapshot.data!;
        final rows = chapter != null
            ? collection.forChapter(chapter!)
            : collection.forVerse(verseKey!);
        final missing =
            verseKey != null &&
            (collection.data['without_distinct_commentary'] as List? ??
                    const [])
                .contains(verseKey);
        final content = PresentedSourceContent(
          locale: locale,
          kind: 'tafsir',
          source: collection.source,
          records: rows,
          commentaryMissing: missing,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (missing) ...[
              Text(context.tr('source.notSeparateTafsir')),
              TextButton(
                child: Text(context.tr('source.readChapterTafsir')),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) {
                      return Scaffold(
                        appBar: AppBar(
                          title: Text(context.tr('source.fullChapter')),
                        ),
                        body: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: BundledTafsirBody(
                            chapter: int.parse(verseKey!.split(':').first),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ] else if (rows.isEmpty)
              Text(context.tr('content.missing'))
            else
              PresentedSourceText(content),
            const SizedBox(height: 8),
            PresentedSourceFooter(content),
          ],
        );
      },
    );
  }
}
