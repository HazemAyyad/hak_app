import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_appearance.dart';
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
              'التفسير • السعدي',
              style: qText(context, size: 16, weight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            FutureBuilder<TafsirText>(
              future: tafsir,
              builder: (context, snapshot) => Text(
                snapshot.data?.text ??
                    (snapshot.hasError
                        ? 'التفسير غير محمّل؛ افتح التفاصيل لإعادة المحاولة'
                        : 'جارٍ تحميل التفسير…'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: qText(context, size: 13),
              ),
            ),
            Text(
              'عرض التفسير الكامل',
              style: qText(context, size: 11, color: qTeal),
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
              'معاني الكلمات',
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
                            'لا توجد كلمات غريبة مشروحة لهذه الآية في المصدر',
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
                  : Text(
                      snapshot.hasError
                          ? 'المعاني غير محمّلة؛ افتح التفاصيل لإعادة المحاولة'
                          : 'جارٍ تحميل المعاني…',
                      style: qText(context, size: 12),
                    ),
            ),
            Text(
              'المصدر: السراج • QuranEnc',
              style: qText(context, size: 10, color: qTeal),
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
          title: meanings ? 'معاني الكلمات' : 'تفسير الآية',
          subtitle:
              'سورة ${repo.surah(verse.surah).name} • الآية ${verse.ayah}',
          height: 150,
          onBack: () => Navigator.pop(context),
          actions: [
            QCircleButton(
              icon: Icons.bookmark_outline,
              label: 'علامة مرجعية',
              onTap: () => widget.controller.toggleBookmark(verse.key),
            ),
            QCircleButton(
              icon: Icons.menu_book_outlined,
              label: meanings ? 'تفسير الآية' : 'معاني الكلمات',
              onTap: () => setState(() {
                meanings = !meanings;
                _load();
              }),
            ),
            QCircleButton(
              icon: Icons.settings_outlined,
              label: 'إعدادات القراءة',
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
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontFamily: 'AmiriQuran',
                          fontSize: 24,
                          height: 1.8,
                        ),
                      ),
                    ),
                    if (widget.onPlay != null)
                      QCircleButton(
                        icon: Icons.play_arrow,
                        label: 'استماع إلى الآية',
                        color: qTeal,
                        onTap: () => widget.onPlay!(verse),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (!meanings)
                QSegments(
                  labels: tafsirSources.values.toList(),
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
                    'معاني الكلمات • السراج في بيان غريب القرآن',
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
                          const Icon(Icons.cloud_off_outlined, color: qTeal),
                          const SizedBox(height: 8),
                          Text(
                            'تعذّر تحميل المحتوى',
                            style: qText(context, size: 17),
                          ),
                          Text(
                            'المحتوى الذي سبق فتحه يبقى متاحًا دون إنترنت.',
                            style: qText(context, size: 11),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          QPrimaryButton(
                            label: 'إعادة المحاولة',
                            onTap: () => setState(_load),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(28),
                      child: CircularProgressIndicator(color: qTeal),
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
                              const Icon(
                                Icons.menu_book_outlined,
                                color: qTeal,
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
                              'يشمل هذا النص الآيات: ${text.keys.join('، ')}',
                              style: qText(
                                context,
                                size: 10,
                                color: AppPalette.of(context).muted,
                              ),
                            ),
                          const SizedBox(height: 14),
                          SelectableText(
                            text.text,
                            style: qText(
                              context,
                              size: 17,
                              weight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'المصدر: Quran.com • ${text.title}\nالنص كما ورد من المصدر؛ يُحفظ للقراءة دون إنترنت بعد فتحه.',
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
                            'لم يورد المصدر معاني كلمات لهذه الآية.',
                            style: qText(context),
                          ),
                        ),
                      for (final entry in data.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: QCard(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                if (entry.word.isNotEmpty)
                                  Container(
                                    width: 85,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppPalette.of(context).paleTeal,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      entry.word,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontFamily: 'AmiriQuran',
                                        fontSize: 23,
                                        height: 1.7,
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SelectableText(
                                    entry.meaning,
                                    style: qText(context, size: 14),
                                  ),
                                ),
                                Column(
                                  children: [
                                    IconButton(
                                      tooltip: 'نسخ المعنى',
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(
                                            text:
                                                '${entry.word}: ${entry.meaning}\nالسراج في بيان غريب القرآن • QuranEnc.com',
                                          ),
                                        );
                                        if (context.mounted) {
                                          qNotice(context, 'تم نسخ المعنى');
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
                                        tooltip: 'استماع إلى الكلمة',
                                        onPressed: () =>
                                            _listenWord(entry.word),
                                        icon: const Icon(
                                          Icons.volume_up_outlined,
                                          size: 21,
                                          color: qTeal,
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
                            style: qText(context, size: 12),
                          ),
                        ),
                      Text(
                        'المصدر: السراج في بيان غريب القرآن • QuranEnc.com\nتُعرض المعاني التي أوردها المصدر لهذه الآية.',
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
              Row(
                children: [
                  Expanded(
                    child: QCard(
                      onTap: () => _step(1),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.chevron_right, color: qTeal),
                          Text(
                            'الآية التالية',
                            style: qText(context, size: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: QCard(
                      onTap: () => _step(-1),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'الآية السابقة',
                            style: qText(context, size: 12),
                          ),
                          const Icon(Icons.chevron_left, color: qTeal),
                        ],
                      ),
                    ),
                  ),
                ],
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
        if (mounted) qNotice(context, 'لا يتوفر تسجيل منفصل لهذه الكلمة');
        return;
      }
      await widget.onWordPlay!(matches.first);
    } catch (_) {
      if (mounted) qNotice(context, 'تعذّر تحميل نطق الكلمة');
    }
  }
}
