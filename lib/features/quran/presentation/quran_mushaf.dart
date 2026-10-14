import 'package:flutter/material.dart';

import '../data/quran_content.dart';
import '../data/quran_repository.dart';
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
  });
  final QuranContent content;
  final QuranRepository repository;
  final int page;
  final String selected;
  final ValueChanged<int> onPage;
  final ValueChanged<QuranVerse> onSelect, onOptions;
  final Color paper, ink;
  @override
  State<QuranMushaf> createState() => _QuranMushafState();
}

class _QuranMushafState extends State<QuranMushaf> {
  late final PageController pages;
  late int current;
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
      if (pages.hasClients) pages.jumpToPage(current - 1);
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
    pages.animateToPage(
      next - 1,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: PageView.builder(
          controller: pages,
          reverse: true,
          itemCount: 604,
          onPageChanged: (index) {
            current = index + 1;
            widget.onPage(current);
          },
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: FutureBuilder<MushafPageData>(
              future: widget.content.page(index + 1, widget.repository),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_outlined,
                            color: qTeal,
                            size: 34,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'تعذّر فتح صفحة المصحف',
                            style: qText(context, size: 16),
                          ),
                          Text(
                            'تحتاج صفحة التجويد اتصالًا بالإنترنت. القراءة المتصلة والآيات متاحتان بدون اتصال.',
                            textAlign: TextAlign.center,
                            style: qText(context, size: 12),
                          ),
                          const SizedBox(height: 12),
                          QPrimaryButton(
                            label: 'إعادة المحاولة',
                            onTap: () => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: qTeal),
                  );
                }
                final data = snapshot.data!;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth.clamp(0.0, 560.0);
                    final height = width * 1.5;
                    // Keep the page at readable phone width. When controls take
                    // space, its lower part scrolls instead of shrinking the text.
                    return SingleChildScrollView(
                      key: PageStorageKey('mushaf-scroll-${index + 1}'),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          child: InteractiveViewer(
                            minScale: 1,
                            maxScale: 5,
                            child: SizedBox(
                              width: width,
                              height: height,
                              child: FittedBox(
                                fit: BoxFit.fill,
                                child: MushafCanvas(
                                  data: data,
                                  repository: widget.repository,
                                  selected: widget.selected,
                                  paper: widget.paper,
                                  ink: widget.ink,
                                  onSelect: widget.onSelect,
                                  onOptions: widget.onOptions,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
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
              tooltip: 'الصفحة السابقة',
              padding: EdgeInsets.zero,
              onPressed: current == 1 ? null : () => move(-1),
              icon: Icon(Icons.chevron_right, color: widget.ink),
            ),
            Text(
              'الصفحة $current من 604',
              style: qText(context, size: 12, color: widget.ink),
            ),
            IconButton(
              tooltip: 'الصفحة التالية',
              padding: EdgeInsets.zero,
              onPressed: current == 604 ? null : () => move(1),
              icon: Icon(Icons.chevron_left, color: widget.ink),
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
  });
  final MushafPageData data;
  final QuranRepository repository;
  final String selected;
  final Color paper, ink;
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
      style: const TextStyle(
        fontFamily: 'AmiriQuran',
        color: Color(0xFF17150F),
        fontSize: 26,
      ),
    ),
  );

  Widget _line(BuildContext context, List<MushafWord> words, double fontSize) {
    if (words.isEmpty) return const SizedBox();
    final naturalWidths = words.map((word) {
      final painter = TextPainter(
        text: TextSpan(
          text: word.glyph,
          style: TextStyle(fontFamily: data.fontFamily, fontSize: fontSize),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      return painter.width;
    }).toList();
    final sum = naturalWidths.fold<double>(0, (a, b) => a + b);
    final factor = (444 / sum).clamp(.1, 1.0);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        mainAxisAlignment: data.page <= 2
            ? MainAxisAlignment.center
            : MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < words.length; i++)
            GestureDetector(
              onTap: () => onSelect(repository.byKey[words[i].key]!),
              onLongPress: () => onOptions(repository.byKey[words[i].key]!),
              child: Semantics(
                label:
                    '${words[i].text}، الآية ${repository.byKey[words[i].key]!.ayah}',
                button: true,
                child: Container(
                  decoration: BoxDecoration(
                    color: words[i].key == selected
                        ? const Color(0x20C7A45A)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    words[i].glyph,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontFamily: data.fontFamily,
                      fontSize: fontSize * factor,
                      height: 1.3,
                      color: const Color(0xFF17150F),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
