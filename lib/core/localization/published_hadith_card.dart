import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_localization.dart';
import 'published_meaning_card.dart';

/// Full publisher text, explanation, benefits and grading are retained. The
/// publisher's Arabic narration stays identifiable beside Haq's local original.
class PublishedHadithRecord extends StatelessWidget {
  const PublishedHadithRecord({
    super.key,
    required this.record,
    required this.source,
    required this.direction,
    this.expandArabic = false,
  });
  final Map<String, String> record;
  final Map<String, dynamic> source;
  final String direction;
  final bool expandArabic;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: direction == 'rtl' ? TextDirection.rtl : TextDirection.ltr,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(record['title']!, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        PublishedTranslationText(record['hadith_text']!),
        for (final section in [
          ('grade', 'hadith.grade'),
          ('takhrij', 'hadith.reference'),
          ('explanation', 'hadith.explanation'),
          ('benefits', 'hadith.benefits'),
        ])
          if (record[section.$1]!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              context.tr(section.$2),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            PublishedTranslationText(record[section.$1]!),
          ],
        const SizedBox(height: 12),
        ExpansionTile(
          key: PageStorageKey(
            'published-hadith/${record['lang']}/${record['id']}/${source['version']}/arabic',
          ),
          initiallyExpanded: expandArabic,
          tilePadding: EdgeInsets.zero,
          title: Text(context.tr('hadith.publisherArabic')),
          children: [
            Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final key in [
                    'title_ar',
                    'hadith_text_ar',
                    'grade_ar',
                    'takhrij_ar',
                    'explanation_ar',
                    'benefits_ar',
                  ])
                    if (record[key]!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: PublishedTranslationText(record[key]!),
                      ),
                ],
              ),
            ),
          ],
        ),
        Text(
          'HadeethEnc.com — v${source['version']}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Text(context.tr('hadith.editionNotice')),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(record['link']!),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new),
              label: Text(context.tr('hadith.publisherLink')),
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(source['update_url'] as String),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(context.tr('hadith.checkUpdates')),
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://hadeethenc.com/en/home'),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(context.tr('hadith.policyLink')),
            ),
          ],
        ),
        ExpansionTile(
          key: PageStorageKey(
            'published-hadith/${record['lang']}/${record['id']}/${source['version']}/document',
          ),
          tilePadding: EdgeInsets.zero,
          title: Text(context.tr('hadith.document')),
          children: [
            SelectableText(
              key: const PageStorageKey('publisher-document-text-scroll'),
              source['document'] as String,
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
      ],
    ),
  );
}

class PublishedHadithCard extends StatelessWidget {
  const PublishedHadithCard({
    super.key,
    required this.contentId,
    required this.originalText,
  });
  final String contentId, originalText;
  @override
  Widget build(BuildContext context) {
    final localization = LocalizationScope.maybeOf(context);
    if (localization == null || localization.contentCode == 'ar') {
      return const SizedBox.shrink();
    }
    final source =
        localization.installed[localization.contentCode]?.hadithSource;
    final record = source?.forContent(contentId, originalText);
    if (source == null || record == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('hadith.translation'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            PublishedHadithRecord(
              record: record,
              source: source.source,
              direction: source.direction,
            ),
          ],
        ),
      ),
    );
  }
}
