import 'dart:async';
import 'package:flutter/material.dart';
import 'app_localization.dart';
import 'published_meaning_card.dart';
import 'published_hadith_card.dart';

class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key, this.onContinue, this.contentOnly = false});
  final Future<void> Function()? onContinue;
  final bool contentOnly;
  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  AppLocalization? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = LocalizationScope.maybeOf(context);
    if (next != _controller) {
      _controller = next;
      if (next != null) unawaited(next.refresh());
    }
  }

  Future<void> _choose(AppLanguage language) async {
    final controller = _controller!;
    if (!controller.local(language.code)) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(language.name),
          content: Text(ctx.tr('language.download')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr('common.continue')),
            ),
          ],
        ),
      );
      if (confirm != true ||
          !await controller.install(
            language.code,
            contentOnly: widget.contentOnly,
          )) {
        return;
      }
    }
    try {
      if (widget.contentOnly) {
        await controller.selectContent(language.code);
      } else {
        await controller.select(language.code);
      }
      await widget.onContinue?.call();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('common.error'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = LocalizationScope.maybeOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(
            widget.contentOnly ? 'language.content' : 'language.title',
          ),
        ),
      ),
      body: controller == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.contentOnly)
                  ListTile(
                    title: Text(context.tr('language.followInterface')),
                    leading: controller.contentSelection == null
                        ? const Icon(Icons.check_circle)
                        : const Icon(Icons.sync),
                    onTap: controller.busy
                        ? null
                        : () => controller.selectContent(null),
                  ),
                if (!widget.contentOnly && widget.onContinue == null)
                  ListTile(
                    title: Text(context.tr('language.content')),
                    subtitle: Text(controller.contentLanguage.name),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const LanguagePage(contentOnly: true),
                      ),
                    ),
                  ),
                Text(
                  context.tr('language.choose'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  controller.pluralText(
                    'language.localPackages',
                    controller.localPackageCount,
                  ),
                ),
                Text(context.tr('language.offline')),
                const SizedBox(height: 8),
                Text(context.tr('language.scope')),
                if (controller.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    context.tr(controller.error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (controller.busy) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: controller.total > 0
                        ? controller.received / controller.total
                        : null,
                  ),
                  Text(
                    context.tr(
                      'language.downloadProgress',
                      args: {
                        'received': controller.formats.number(
                          controller.received,
                        ),
                        'total': controller.total > 0
                            ? controller.formats.number(controller.total)
                            : '…',
                      },
                    ),
                  ),
                  TextButton(
                    onPressed: controller.pause,
                    child: const Icon(Icons.pause),
                  ),
                ],
                const SizedBox(height: 12),
                for (final language
                    in widget.contentOnly
                        ? controller.availableContent
                        : controller.available)
                  ListTile(
                    key: ValueKey(
                      'language-${widget.contentOnly ? "content" : "interface"}-${language.code}',
                    ),
                    title: Text(
                      language.name,
                      textDirection: language.direction,
                    ),
                    subtitle: Text(
                      context.tr(
                        controller.local(language.code)
                            ? 'language.available'
                            : 'language.download',
                      ),
                    ),
                    leading:
                        (widget.contentOnly
                                ? controller.contentCode
                                : controller.code) ==
                            language.code
                        ? const Icon(Icons.check_circle)
                        : const Icon(Icons.language),
                    onTap: controller.busy ? null : () => _choose(language),
                    trailing:
                        controller.local(language.code) &&
                            controller.published.containsKey(language.code)
                        ? IconButton(
                            tooltip: context.tr('language.update'),
                            icon: const Icon(Icons.system_update_alt),
                            onPressed: controller.busy
                                ? null
                                : () async {
                                    await controller.install(
                                      language.code,
                                      contentOnly: widget.contentOnly,
                                    );
                                  },
                          )
                        : null,
                  ),
                OutlinedButton.icon(
                  onPressed: controller.busy ? null : controller.refresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(context.tr('language.update')),
                ),
              ],
            ),
    );
  }
}

/// The Arabic original is rendered by the existing reader, never replaced.
class ContentTranslationCard extends StatelessWidget {
  const ContentTranslationCard({
    super.key,
    required this.contentId,
    this.originalText,
  });
  final String contentId;
  final String? originalText;
  @override
  Widget build(BuildContext context) {
    final localization = LocalizationScope.maybeOf(context);
    if (localization == null || localization.contentCode == 'ar') {
      return const SizedBox.shrink();
    }
    final translation = localization.content(contentId);
    if (originalText != null &&
        localization.installed[localization.contentCode]?.hadithSource
                ?.forContent(contentId, originalText!) !=
            null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: PublishedHadithCard(
          contentId: contentId,
          originalText: originalText!,
        ),
      );
    }
    final published = localization
        .installed[localization.contentCode]
        ?.quranSource
        ?.forContent(contentId);
    if (translation == null && published != null && published.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: PublishedMeaningCard(contentId: contentId),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Directionality(
            textDirection: localization.contentLanguage.direction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('content.translation'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (translation == null)
                  Text(context.tr('content.missing'))
                else ...[
                  Text(
                    translation['title'] as String,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(translation['text'] as String),
                  if ((translation['summary'] as String? ?? '').isNotEmpty)
                    Text(translation['summary'] as String),
                  const SizedBox(height: 8),
                  Text(translation['source'] as String),
                  SelectableText(
                    translation['sourceUrl'] as String,
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
