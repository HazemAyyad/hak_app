import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_localization.dart';
import 'published_meaning_card.dart';
import 'religious_translation_library.dart';

/// A translation belongs to the publisher narration shown with it. It never
/// replaces scripture, personal text, recitation audio or counting identities.
class BundledSourceCard extends StatelessWidget {
  const BundledSourceCard({
    super.key,
    required this.kind,
    this.contentId,
    this.verseKey,
    this.chapter,
    this.originalText = '',
    this.showMissing = false,
  });
  final String kind;
  final String? contentId, verseKey;
  final int? chapter;
  final String originalText;
  final bool showMissing;

  @override
  Widget build(BuildContext context) {
    final locale = LocalizationScope.maybeOf(context)?.contentCode ?? 'ar';
    if (!ReligiousTranslationLibrary.supports(locale)) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<SourceCollection>(
      key: ValueKey(
        'bundled-source-$locale-$kind-${contentId ?? verseKey ?? chapter}',
      ),
      future: ReligiousTranslationLibrary.shared.load(locale, kind),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MissingSource(label: context.tr('source.localUnavailable'));
        }
        if (!snapshot.hasData) return const SizedBox.shrink();
        final collection = snapshot.data!;
        final rows = chapter != null
            ? collection.forChapter(chapter!)
            : verseKey != null
            ? collection.forVerse(verseKey!)
            : collection.forContent(contentId!, originalText);
        if (rows.isEmpty) {
          return showMissing
              ? _MissingSource(label: context.tr('content.missing'))
              : const SizedBox.shrink();
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr(
                      kind == 'tafsir'
                          ? 'source.tafsir'
                          : kind == 'names'
                          ? 'source.nameMeaning'
                          : kind == 'quran'
                          ? 'source.meanings'
                          : 'source.publisherTranslation',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (kind == 'tafsir' &&
                      verseKey != null &&
                      (collection.data['without_distinct_commentary']
                                  as List? ??
                              const [])
                          .contains(verseKey)) ...[
                    Text(context.tr('source.notSeparateTafsir')),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (context) => Scaffold(
                            appBar: AppBar(
                              title: Text(context.tr('source.fullChapter')),
                            ),
                            body: SingleChildScrollView(
                              child: BundledSourceCard(
                                kind: 'tafsir',
                                chapter: int.parse(verseKey!.split(':').first),
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: Text(context.tr('source.readChapterTafsir')),
                    ),
                  ],
                  for (final (index, row) in rows.indexed)
                    _SourceRecord(
                      storageId:
                          '$locale/$kind/${contentId ?? verseKey ?? chapter}/$index',
                      row: row,
                      source: collection.source,
                      kind: kind,
                    ),
                  if (rows.any((row) => row['source'] == null))
                    _Attribution(
                      source: collection.source,
                      storageId:
                          '$locale/$kind/${contentId ?? verseKey ?? chapter}/source',
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class BundledContentCard extends StatelessWidget {
  const BundledContentCard({
    super.key,
    required this.contentId,
    required this.originalText,
  });
  final String contentId, originalText;
  @override
  Widget build(BuildContext context) {
    final locale = LocalizationScope.maybeOf(context)?.contentCode ?? 'ar';
    if (!ReligiousTranslationLibrary.supports(locale)) {
      return Text(context.tr('content.missing'));
    }
    final kind = ReligiousTranslationLibrary.kindForContent(contentId);
    if (kind == null) return Text(context.tr('content.missing'));
    return BundledSourceCard(
      kind: kind,
      contentId: contentId,
      originalText: originalText,
      showMissing: true,
    );
  }
}

class _MissingSource extends StatelessWidget {
  const _MissingSource({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(12), child: Text(label));
}

class _SourceRecord extends StatelessWidget {
  const _SourceRecord({
    required this.storageId,
    required this.row,
    required this.source,
    required this.kind,
  });
  final Map<String, dynamic> row, source;
  final String kind;
  final String storageId;
  @override
  Widget build(BuildContext context) {
    final fields = row['fields'] as Map?;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (row['title'] is String)
          Text(
            row['title'] as String,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        if (row['alignment'] == 'publisher_record_variant') ...[
          Text(
            context.tr('source.narrationNotice'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if ((row['source_arabic'] as String? ?? '').isNotEmpty)
            ExpansionTile(
              key: PageStorageKey('bundled/$storageId/publisher-arabic'),
              tilePadding: EdgeInsets.zero,
              title: Text(context.tr('source.publisherArabic')),
              children: [
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: PublishedTranslationText(
                    row['source_arabic'] as String,
                  ),
                ),
              ],
            ),
        ],
        PublishedTranslationText(row['text'] as String),
        if ((row['footnotes'] as String? ?? '').isNotEmpty)
          ExpansionTile(
            key: PageStorageKey('bundled/$storageId/footnotes'),
            tilePadding: EdgeInsets.zero,
            title: Text(context.tr('source.footnotes')),
            children: [PublishedTranslationText(row['footnotes'] as String)],
          ),
        if (fields != null)
          for (final pair in const [
            ('explanation', 'hadith.explanation'),
            ('benefits', 'hadith.benefits'),
            ('grade', 'hadith.grade'),
            ('takhrij', 'hadith.reference'),
          ])
            if ((fields[pair.$1] as String? ?? '').isNotEmpty)
              ExpansionTile(
                key: PageStorageKey('bundled/$storageId/${pair.$1}'),
                tilePadding: EdgeInsets.zero,
                title: Text(context.tr(pair.$2)),
                children: [PublishedTranslationText(fields[pair.$1] as String)],
              ),
        if (row['source'] is Map)
          _Attribution(
            source: Map<String, dynamic>.from(row['source'] as Map),
            storageId: '$storageId/source',
          )
        else if (row['source_url'] is String)
          _SourceLink(
            url: row['source_url'] as String,
            label: context.tr('source.openRecord'),
          ),
        const SizedBox(height: 12),
      ],
    );
    return kind == 'tafsir'
        ? ExpansionTile(
            key: PageStorageKey('bundled/$storageId/tafsir'),
            tilePadding: EdgeInsets.zero,
            title: Text(
              row['type'] == 'المقطع'
                  ? context.tr('source.meanings')
                  : (source['display_title'] ??
                            source['name'] ??
                            source['title'])
                        as String,
            ),
            children: [text],
          )
        : text;
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution({required this.source, required this.storageId});
  final Map<String, dynamic> source;
  final String storageId;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        (source['display_title'] ?? source['name'] ?? source['title'])
            as String,
      ),
      Text(
        '${source['provider']} • ${source['version']}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      _SourceLink(
        url: source['url'] as String,
        label: context.tr('source.openPublisher'),
      ),
      if (source['document'] is String)
        ExpansionTile(
          key: PageStorageKey('bundled/$storageId/document'),
          tilePadding: EdgeInsets.zero,
          title: Text(context.tr('source.documentMetadata')),
          children: [
            SelectableText(
              source['document'] as String,
              key: const PageStorageKey('publisher-document-text-scroll'),
            ),
          ],
        ),
    ],
  );
}

class _SourceLink extends StatelessWidget {
  const _SourceLink({required this.url, required this.label});
  final String url, label;
  @override
  Widget build(BuildContext context) =>
      LocalizationScope.maybeOf(context)?.showSourceLinks != true
      ? const SizedBox.shrink()
      : TextButton.icon(
          icon: const Icon(Icons.open_in_new, size: 16),
          label: Text(label),
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
