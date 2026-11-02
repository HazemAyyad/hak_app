import '../../../core/localization/app_localization.dart';
import '../../../core/localization/ui_text.dart';
import 'package:flutter/material.dart';

import '../../../app_loading.dart';
import '../data/quran_content.dart';
import '../data/quran_repository.dart';
import '../data/quran_page_downloads.dart';
import 'quran_page_viewport.dart';
import 'quran_mushaf_line.dart';
import 'quran_widgets.dart';

/// Page glyphs keep their source line grouping at every zoom/text scale.
class QuranMushaf extends StatefulWidget {
  const QuranMushaf({
    super.key,
    required this.content,
    required this.repository,
    required this.page,
    required this.selected,
    required this.onPage,
    required this.onSelect,
    required this.onOptions,
    required this.paper,
    required this.ink,
    this.downloads,
    this.fontFamily,
    this.showTajweed = true,
  });
  final QuranContent content;
  final QuranRepository repository;
  final int page;
  final String? selected;
  final ValueChanged<int> onPage;
  final ValueChanged<QuranVerse> onSelect, onOptions;
  final Color paper, ink;
  final QuranPageDownloads? downloads;
  final String? fontFamily;
  final bool showTajweed;
  @override
  State<QuranMushaf> createState() => _QuranMushafState();
}

class _QuranMushafState extends State<QuranMushaf> {
  late final PageController pages;
  late int current;
  final views = <(int, bool), Future<MushafPageData>>{};
  bool zoomed = false;
  @override
  void initState() {
    super.initState();
    current = widget.page;
    pages = PageController(initialPage: current - 1, viewportFraction: .94);
  }

  @override
  void didUpdateWidget(covariant QuranMushaf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.page != current) {
      current = widget.page;
      zoomed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !pages.hasClients) return;
        pages.jumpToPage(widget.page - 1);
      });
    }
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void move(int delta) {
    final next = current + delta;
    if (next < 1 || next > 604) return;
    if (zoomed) setState(() => zoomed = false);
    pages.animateToPage(
      next - 1,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Widget _viewport(int page, Widget child) => QuranPageViewport(
    key: ValueKey('mushaf-viewport-$page'),
    page: page,
    onSwipe: move,
    onZoomChanged: (value) {
      if (mounted && page == current && zoomed != value) {
        setState(() => zoomed = value);
      }
    },
    child: child,
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: PageView.builder(
          controller: pages,
          key: const ValueKey('quran-mushaf-pages'),
          reverse: false,
          physics: zoomed ? const NeverScrollableScrollPhysics() : null,
          itemCount: 604,
          onPageChanged: (index) {
            // Parent-driven jumps already selected this page and verse.
            if (index + 1 == current) return;
            current = index + 1;
            zoomed = false;
            views.removeWhere((key, _) => (key.$1 - current).abs() > 2);
            widget.onPage(current);
          },
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: FutureBuilder<MushafPageData>(
              future: views.putIfAbsent(
                (index + 1, widget.fontFamily == null),
                () => widget.content.page(
                  index + 1,
                  widget.repository,
                  originalFont: widget.fontFamily == null,
                ),
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.quranLabel('تعذّر فتح صفحة المصحف'),
                          style: qText(context, size: 16),
                        ),
                        QPrimaryButton(
                          label: context.quranLabel('إعادة المحاولة'),
                          onTap: () => setState(() {
                            views.remove((
                              index + 1,
                              widget.fontFamily == null,
                            ));
                          }),
                        ),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return AppLoadingSkeleton(
                    label: context.quranLabel('جارٍ تحميل صفحة المصحف'),
                    lines: 10,
                  );
                }
                return _viewport(
                  index + 1,
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth.clamp(0.0, 560.0);
                      return SizedBox(
                        width: width,
                        height: width * 1.5,
                        child: FittedBox(
                          fit: BoxFit.fill,
                          child: MushafCanvas(
                            data: snapshot.data!,
                            repository: widget.repository,
                            selected: widget.selected,
                            paper: widget.paper,
                            ink: widget.ink,
                            fontFamily: widget.fontFamily,
                            showTajweed: widget.showTajweed,
                            onSelect: widget.onSelect,
                            onOptions: widget.onOptions,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
      SizedBox(
        height: 34,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: context.quranLabel('الصفحة السابقة'),
              padding: EdgeInsets.zero,
              onPressed: current == 1 ? null : () => move(-1),
              icon: Icon(
                Icons.chevron_right,
                color: widget.ink,
                textDirection: TextDirection.ltr,
              ),
            ),
            Text(
              context.tr(
                'quran.mushafPageProgress',
                args: {
                  'page': quranNumber(context, current),
                  'total': quranNumber(context, 604),
                },
              ),
              style: qText(context, size: 12, color: widget.ink),
            ),
            IconButton(
              tooltip: context.quranLabel('الصفحة التالية'),
              padding: EdgeInsets.zero,
              onPressed: current == 604 ? null : () => move(1),
              icon: Icon(
                Icons.chevron_left,
                color: widget.ink,
                textDirection: TextDirection.ltr,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class MushafCanvas extends StatelessWidget {
  const MushafCanvas({
    super.key,
    required this.data,
    required this.repository,
    required this.selected,
    required this.paper,
    required this.ink,
    required this.onSelect,
    required this.onOptions,
    this.showTajweed = true,
    this.fontFamily,
  });
  final MushafPageData data;
  final QuranRepository repository;
  final String? selected;
  final Color paper, ink;
  final bool showTajweed;
  final String? fontFamily;
  final ValueChanged<QuranVerse> onSelect, onOptions;

  @override
  Widget build(BuildContext context) {
    final lines = <int, List<MushafWord>>{};
    final headings = <int, QuranSurah>{};
    final basmala = <int>{};
    final firstChapter = repository.surah(
      repository.byKey[data.words.first.key]!.surah,
    );
    for (final word in data.words) {
      lines.putIfAbsent(word.line, () => []).add(word);
      final verse = repository.byKey[word.key]!;
      if (verse.ayah == 1 && word.position == 1 && word.line > 1) {
        final chapter = repository.surah(verse.surah);
        final headerLine = chapter.id == 1 || chapter.id == 9
            ? word.line - 1
            : word.line - 2;
        if (headerLine > 0) headings[headerLine] = chapter;
        if (chapter.id != 1 && chapter.id != 9) basmala.add(word.line - 1);
      }
    }
    final opening = data.page <= 2;
    // The opening pages have a centered shorter block in the source layout.
    final lastLine = opening ? lines.keys.reduce((a, b) => a > b ? a : b) : 15;
    // The first source heading lives in the frame's top cartouche.
    final firstLine = headings[1]?.id == firstChapter.id ? 2 : 1;
    // QCF V4 stores explicit colors, including black, in its own palette.
    // A light sheet keeps every glyph legible without recoloring Tajweed.
    final sheet = paper.computeLuminance() < .2
        ? const Color(0xFFFFF9E9)
        : paper;
    final textInk = const Color(0xFF17150F);
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        width: 560,
        height: 840,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: sheet,
            gradient: LinearGradient(
              colors: [sheet, Color.lerp(sheet, qGold, .055)!],
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x18000000), blurRadius: 8),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/quran/mushaf_frame.png',
                fit: BoxFit.fill,
                excludeFromSemantics: true,
              ),
              Positioned(
                top: 65,
                height: 65,
                left: 130,
                right: 130,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'سُورَةُ ${firstChapter.name}',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontFamily: 'AmiriQuran',
                        fontSize: 33,
                        color: textInk,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 143,
                bottom: 61,
                left: 58,
                right: 58,
                child: Column(
                  children: [
                    for (int line = firstLine; line <= lastLine; line++)
                      Expanded(
                        child: headings.containsKey(line)
                            ? _heading(context, headings[line]!)
                            : basmala.contains(line)
                            ? Center(
                                child: Text(
                                  'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(
                                    fontFamily: 'AmiriQuran',
                                    fontSize: opening ? 36 : 29,
                                    color: textInk,
                                  ),
                                ),
                              )
                            : _line(
                                context,
                                lines[line] ?? [],
                                opening ? 44 : 35,
                              ),
                      ),
                  ],
                ),
              ),
              Positioned(
                bottom: 28,
                left: 0,
                right: 0,
                child: Text(
                  '${data.page}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'QuranUI',
                    fontSize: 13,
                    color: textInk,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, QuranSurah chapter) => Container(
    margin: const EdgeInsets.symmetric(vertical: 2),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0x15B38C42),
      border: Border.all(color: qGold),
    ),
    child: Text(
      'سُورَةُ ${chapter.name}',
      textDirection: TextDirection.rtl,
      style: const TextStyle(
        fontFamily: 'AmiriQuran',
        color: Color(0xFF17150F),
        fontSize: 26,
      ),
    ),
  );

  Widget _line(BuildContext context, List<MushafWord> words, double fontSize) {
    if (words.isEmpty) return const SizedBox();
    return QuranMushafLine(
      key: ValueKey('mushaf-line-${data.page}-${words.first.line}'),
      words: words,
      fontFamily: fontFamily ?? data.fontFamily,
      useUnicode: fontFamily != null,
      fontSize: fontSize,
      centered: data.page <= 2,
      selected: selected,
      repository: repository,
      onSelect: onSelect,
      onOptions: onOptions,
      showTajweed: showTajweed,
    );
  }
}
