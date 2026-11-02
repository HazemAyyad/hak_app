import '../../../core/localization/app_localization.dart';
import '../../../core/localization/ui_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/localization/published_meaning_card.dart';
import '../../../core/localization/bundled_source_card.dart';
import '../../sharing/share_card.dart';

import '../../../app_appearance.dart';
import '../../../app_loading.dart';
import '../data/quran_content.dart';
import '../data/quran_controller.dart';
import '../data/quran_repository.dart';
import 'quran_reader.dart';
import 'quran_widgets.dart';
import 'quran_audio_widgets.dart';

class QuranExplanation extends StatefulWidget {
  const QuranExplanation({
    super.key,
    required this.controller,
    required this.verse,
    this.meanings = false,
    this.onPlay,
    this.onWordPlay,
  });
  final QuranController controller;
  final QuranVerse verse;
  final bool meanings;
  final ValueChanged<QuranVerse>? onPlay;
  final Future<void> Function(MushafWord)? onWordPlay;
  @override
  State<QuranExplanation> createState() => _QuranExplanationState();
}

/// The preview uses the same source as the detail, without generated summaries.
class QuranVerseInsight extends StatefulWidget {
  const QuranVerseInsight({
    super.key,
    required this.controller,
    required this.verse,
    required this.onOpen,
  });
  final QuranController controller;
  final QuranVerse verse;
  final ValueChanged<bool> onOpen;
  @override
  State<QuranVerseInsight> createState() => _QuranVerseInsightState();
}

class _QuranVerseInsightState extends State<QuranVerseInsight> {
  late final tafsir = widget.controller.content.tafsir(widget.verse.key, 91);
  late final meanings = widget.controller.content.meanings(widget.verse.key);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      QCard(
        onTap: () => widget.onOpen(false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.quranLabel('التفسير • السعدي'),
              style: qText(context, size: 16, weight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            FutureBuilder<TafsirText>(
              future: tafsir,
              builder: (context, snapshot) =>
                  !snapshot.hasData && !snapshot.hasError
                  ? AppLoadingSkeleton(
                      label: context.quranLabel('جارٍ تحميل التفسير'),
                      page: false,
                      lines: 3,
                    )
                  : Text(
                      snapshot.data?.text ??
                          (snapshot.hasError
                              ? context.quranLabel(
                                  'التفسير غير محمّل؛ افتح التفاصيل لإعادة المحاولة',
                                )
                              : context.quranLabel('جارٍ تحميل التفسير…')),
                      textDirection: snapshot.hasData
                          ? contentTextDirection(snapshot.data!.text)
                          : null,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: qText(context, size: 13),
                    ),
            ),
            Text(
              context.quranLabel('عرض التفسير الكامل'),
              style: qText(context, size: 11, color: qAccent(context)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      QCard(
        onTap: () => widget.onOpen(true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.quranLabel('معاني الكلمات'),
              style: qText(context, size: 16, weight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            FutureBuilder<VerseMeanings>(
              future: meanings,
              builder: (context, snapshot) => snapshot.hasData
                  ? Column(
                      children: [
                        if (snapshot.data!.entries.isEmpty)
                          Text(
                            context.quranLabel(
                              'لا توجد كلمات غريبة مشروحة لهذه الآية في المصدر',
                            ),
                            style: qText(context, size: 12),
                          ),
                        for (final e in snapshot.data!.entries.take(2))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    e.word,
                                    textDirection: TextDirection.rtl,
                                    style: const TextStyle(
                                      fontFamily: 'AmiriQuran',
                                      fontSize: 19,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    e.meaning,
                                    textDirection: contentTextDirection(
                                      e.meaning,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: qText(context, size: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    )
                  : snapshot.hasError
                  ? Text(
                      context.quranLabel(
                        'المعاني غير محمّلة؛ افتح التفاصيل لإعادة المحاولة',
                      ),
                      style: qText(context, size: 12),
                    )
                  : AppLoadingSkeleton(
                      label: context.quranLabel('جارٍ تحميل المعاني'),
                      page: false,
                      lines: 2,
                    ),
            ),
            Text(
              context.quranLabel('المصدر: السراج • QuranEnc'),
              style: qText(context, size: 10, color: qAccent(context)),
            ),
          ],
        ),
      ),
    ],
  );
}

class _QuranExplanationState extends State<QuranExplanation> {
  late QuranVerse verse;
  late bool meanings;
  int source = 91;
  late Future<Object> request;
  final scroll = ScrollController();
  QuranRepository get repo => widget.controller.repository!;
  @override
  void initState() {
    super.initState();
    verse = widget.verse;
    meanings = widget.meanings;
    _load();
  }

  void _load() {
    request = meanings
        ? widget.controller.content.meanings(verse.key)
        : widget.controller.content.tafsir(verse.key, source);
  }

  void _step(int delta) {
    final index = repo.surah(verse.surah).start + verse.ayah - 1 + delta;
    if (index < 0 || index >= repo.verses.length) return;
    setState(() {
      verse = repo.verses[index];
      _load();
    });
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => ListView(
      controller: scroll,
      padding: EdgeInsets.zero,
      children: [
        QuranHeader(
          title: meanings
              ? context.quranLabel('معاني الكلمات')
              : context.quranLabel('تفسير الآية'),
          subtitle: quranVerseTitle(
            context,
            repo.surah(verse.surah),
            verse.ayah,
          ),
          height: 150,
          onBack: () => Navigator.pop(context),
          actions: [
            QCircleButton(
              icon: Icons.bookmark_outline,
              label: context.quranLabel('علامة مرجعية'),
              onTap: () => widget.controller.toggleBookmark(verse.key),
            ),
            QCircleButton(
              icon: Icons.menu_book_outlined,
              label: meanings
                  ? context.quranLabel('تفسير الآية')
                  : context.quranLabel('معاني الكلمات'),
              onTap: () => setState(() {
                meanings = !meanings;
                _load();
              }),
            ),
            QCircleButton(
              icon: Icons.settings_outlined,
              label: context.quranLabel('إعدادات القراءة'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: SafeArea(
                      child: QuranReadingSettings(
                        controller: widget.controller,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        PublishedMeaningCard(verseKey: verse.key),
        if (!meanings) BundledSourceCard(kind: 'tafsir', verseKey: verse.key),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: QuranPlayerPanel(
            media: widget.controller.audio,
            repository: repo,
            compact: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 105),
          child: Column(
            children: [
              QCard(
                child: Row(
                  children: [
                    QMedallion(number: verse.ayah, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        verse.text,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontFamily: 'AmiriQuran',
                          fontSize: 21,
                          height: 1.65,
                        ),
                      ),
                    ),
                    if (widget.onPlay != null)
                      Tooltip(
                        message: context.quranLabel('استماع إلى الآية'),
                        child: Material(
                          color: qAccentFill(context),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => widget.onPlay!(verse),
                            child: const SizedBox(
                              width: 34,
                              height: 34,
                              child: Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () => chooseContentShare(
                    context,
                    ShareCardContent.quran(repo, [verse.key]),
                    repository: repo,
                  ),
                  icon: const Icon(Icons.share_outlined, size: 16),
                  label: Text(
                    context.quranLabel('مشاركة الآية'),
                    style: qText(context, size: 11, color: qAccent(context)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (!meanings)
                QSegments(
                  labels: [
                    for (final entry in tafsirSources.entries)
                      context.tr(
                        'quran.tafsirSource.${entry.key}',
                        fallback: entry.value,
                      ),
                  ],
                  selected: tafsirSources.keys.toList().indexOf(source),
                  onSelect: (value) => setState(() {
                    source = tafsirSources.keys.elementAt(value);
                    _load();
                  }),
                ),
              if (meanings)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    context.quranLabel(
                      'معاني الكلمات • السراج في بيان غريب القرآن',
                    ),
                    style: qText(context, size: 15, weight: FontWeight.w800),
                  ),
                ),
              const SizedBox(height: 12),
              FutureBuilder<Object>(
                future: request,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return QCard(
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_off_outlined,
                            color: qAccent(context),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.quranLabel('تعذّر تحميل المحتوى'),
                            style: qText(context, size: 17),
                          ),
                          Text(
                            context.quranLabel(
                              'المحتوى المحمّل متاح دون إنترنت لمدة سبعة أيام.',
                            ),
                            style: qText(context, size: 11),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          QPrimaryButton(
                            label: context.quranLabel('إعادة المحاولة'),
                            onTap: () => setState(_load),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return AppLoadingSkeleton(
                      label: context.quranLabel('جارٍ تحميل التفسير والمعاني'),
                      page: false,
                    );
                  }
                  if (snapshot.data is TafsirText) {
                    final text = snapshot.data! as TafsirText;
                    return QCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.menu_book_outlined,
                                color: qAccent(context),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  text.title,
                                  style: qText(
                                    context,
                                    size: 18,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (text.keys.length > 1)
                            Text(
                              context.tr(
                                'quran.tafsirCoveredVerses',
                                args: {'verses': text.keys.join(', ')},
                              ),
                              style: qText(
                                context,
                                size: 10,
                                color: AppPalette.of(context).muted,
                              ),
                            ),
                          const SizedBox(height: 14),
                          SelectableText(
                            text.text,
                            textDirection: contentTextDirection(text.text),
                            style: TextStyle(
                              fontFamily: 'AmiriQuran',
                              fontSize: 17,
                              height: 1.85,
                              fontWeight: FontWeight.w400,
                              color: AppPalette.of(context).dark
                                  ? AppPalette.of(context).heading
                                  : const Color(0xFF171D28),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            context.tr(
                              'quran.tafsirSource',
                              args: {'title': text.title},
                            ),
                            style: qText(
                              context,
                              size: 10,
                              color: AppPalette.of(context).muted,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final data = snapshot.data! as VerseMeanings;
                  return Column(
                    children: [
                      if (data.original.trim().isEmpty)
                        QCard(
                          child: Text(
                            context.quranLabel(
                              'لم يورد المصدر معاني كلمات لهذه الآية.',
                            ),
                            style: qText(context),
                          ),
                        ),
                      for (final (entryIndex, entry) in data.entries.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: QCard(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                QMedallion(number: entryIndex + 1, size: 24),
                                const SizedBox(width: 7),
                                if (entry.word.isNotEmpty)
                                  Container(
                                    width:
                                        MediaQuery.sizeOf(context).width < 380
                                        ? 56
                                        : 70,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppPalette.of(context).dark
                                          ? AppPalette.of(context).paleTeal
                                          : const [
                                              Color(0xFFFFF0D2),
                                              Color(0xFFEAF5E7),
                                              Color(0xFFFDE9E6),
                                              Color(0xFFE7F1FA),
                                              Color(0xFFF1E9F8),
                                            ][entryIndex % 5],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      entry.word,
                                      textDirection: TextDirection.rtl,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontFamily: 'AmiriQuran',
                                        fontSize: 20,
                                        height: 1.7,
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SelectableText(
                                    entry.meaning,
                                    textDirection: contentTextDirection(
                                      entry.meaning,
                                    ),
                                    style: TextStyle(
                                      fontFamily: 'AmiriQuran',
                                      fontSize: 15,
                                      height: 1.65,
                                      color: AppPalette.of(context).heading,
                                    ),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: context.quranLabel('نسخ المعنى'),
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 32,
                                      ),
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(
                                            text:
                                                '${entry.word}: ${entry.meaning}',
                                          ),
                                        );
                                        if (context.mounted) {
                                          qNotice(
                                            context,
                                            context.quranLabel('تم نسخ المعنى'),
                                          );
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.copy_outlined,
                                        size: 20,
                                        color: qNavy,
                                      ),
                                    ),
                                    if (widget.onWordPlay != null &&
                                        entry.word.isNotEmpty)
                                      IconButton(
                                        tooltip: context.quranLabel(
                                          'استماع إلى الكلمة',
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 32,
                                        ),
                                        onPressed: () =>
                                            _listenWord(entry.word),
                                        icon: Icon(
                                          Icons.volume_up_outlined,
                                          size: 21,
                                          color: qAccent(context),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (data.footnotes?.isNotEmpty == true)
                        QCard(
                          child: SelectableText(
                            data.footnotes!,
                            textDirection: contentTextDirection(
                              data.footnotes!,
                            ),
                            style: qText(context, size: 12),
                          ),
                        ),
                      Text(
                        context.quranLabel(
                          'المصدر: السراج في بيان غريب القرآن • QuranEnc.com\nتُعرض المعاني التي أوردها المصدر لهذه الآية.',
                        ),
                        style: qText(
                          context,
                          size: 10,
                          color: AppPalette.of(context).muted,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              QuranVerseNavigation(
                onPrevious: verse.key == repo.verses.first.key
                    ? null
                    : () => _step(-1),
                onNext: verse.key == repo.verses.last.key
                    ? null
                    : () => _step(1),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Future<void> _listenWord(String phrase) async {
    try {
      final words = await widget.controller.content.words(verse);
      final target = normalizeQuranSearch(phrase.split(' ').first);
      final matches = words
          .where((w) => normalizeQuranSearch(w.text) == target)
          .toList();
      if (matches.isEmpty) {
        if (mounted) {
          qNotice(
            context,
            context.quranLabel('لا يتوفر تسجيل منفصل لهذه الكلمة'),
          );
        }
        return;
      }
      await widget.onWordPlay!(matches.first);
    } catch (_) {
      if (mounted) {
        qNotice(context, context.quranLabel('تعذّر تحميل نطق الكلمة'));
      }
    }
  }
}
