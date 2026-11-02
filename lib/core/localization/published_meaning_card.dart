import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:url_launcher/url_launcher.dart';
import 'app_localization.dart';
import 'quran_translation_source.dart';
import 'bundled_source_card.dart';

/// Only text and inline emphasis are rendered; provider HTML cannot run code or load images.
class PublishedTranslationText extends StatelessWidget {
  const PublishedTranslationText(this.text, {super.key});
  final String text;
  InlineSpan _span(dom.Node node) {
    if (node is dom.Text) return TextSpan(text: node.data);
    if (node is! dom.Element) return const TextSpan();
    if (['script', 'style', 'img', 'iframe'].contains(node.localName)) {
      return const TextSpan();
    }
    if (node.localName == 'br') return const TextSpan(text: '\n');
    return TextSpan(
      children: [
        for (final child in node.nodes) _span(child),
        if ([
          'p',
          'div',
          'li',
          'h1',
          'h2',
          'h3',
          'h4',
          'blockquote',
        ].contains(node.localName))
          const TextSpan(text: '\n'),
      ],
      style: TextStyle(
        fontWeight: ['b', 'strong'].contains(node.localName)
            ? FontWeight.bold
            : null,
        fontStyle: ['i', 'em'].contains(node.localName)
            ? FontStyle.italic
            : null,
        fontSize: node.localName == 'sup' ? 12 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SelectableText.rich(
    TextSpan(
      children: [
        for (final node in html.parseFragment(text).nodes) _span(node),
      ],
    ),
  );
}

class PublishedMeaningCard extends StatelessWidget {
  const PublishedMeaningCard({super.key, this.contentId, this.verseKey});
  final String? contentId, verseKey;
  @override
  Widget build(BuildContext context) {
    final localization = LocalizationScope.maybeOf(context);
    if (localization == null) return const SizedBox.shrink();
    final source =
        localization.installed[localization.contentCode]?.quranSource;
    if (source == null) {
      return BundledSourceCard(
        kind: 'quran',
        contentId: contentId,
        verseKey: verseKey,
      );
    }
    final rows = contentId != null
        ? source.forContent(contentId!)
        : <PublishedVerseMeaning>[?source.verses[verseKey]];
    if (rows.isEmpty) {
      return BundledSourceCard(
        kind: 'quran',
        contentId: contentId,
        verseKey: verseKey,
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Directionality(
          textDirection: source.direction == 'rtl'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('source.meanings'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final row in rows) ...[
                Text(row.key, textDirection: TextDirection.ltr),
                PublishedTranslationText(row.translation),
                if (row.footnotes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.tr('source.footnotes'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  PublishedTranslationText(row.footnotes),
                ],
                const SizedBox(height: 12),
              ],
              Text(source.attribution),
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.https('quranenc.com', '/en/home'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('QuranEnc.com'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
