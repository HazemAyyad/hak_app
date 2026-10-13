import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../data/quran_content.dart';
import '../data/quran_repository.dart';
import 'quran_widgets.dart';

/// Fifteen physical lines are rendered on one fixed canvas. Accessibility text
/// scaling and zoom never change word placement or wrap a Mushaf line.
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
                    child: Padding(
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
                            'هذه الصفحة لم تُحمّل بعد',
                            style: qText(context, size: 16),
                          ),
                          Text(
                            'اتصل بالإنترنت لفتحها؛ تبقى محفوظة للقراءة لاحقًا.',
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
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
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
                );
              },
            ),
          ),
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'الصفحة السابقة',
            onPressed: current == 1 ? null : () => move(-1),
            icon: Icon(Icons.chevron_right, color: widget.ink),
          ),
          Text(
            'الصفحة $current من 604',
            style: qText(context, size: 12, color: widget.ink),
          ),
          IconButton(
            tooltip: 'الصفحة التالية',
            onPressed: current == 604 ? null : () => move(1),
            icon: Icon(Icons.chevron_left, color: widget.ink),
          ),
        ],
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
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        width: 560,
        height: 820,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: paper,
            boxShadow: const [
              BoxShadow(color: Color(0x18000000), blurRadius: 8),
            ],
          ),
          child: CustomPaint(
            painter: MushafBorder(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 25, 28, 22),
              child: Column(
                children: [
                  for (int line = 1; line <= 15; line++)
                    Expanded(
                      child: headings.containsKey(line)
                          ? _heading(context, headings[line]!)
                          : basmala.contains(line)
                          ? Center(
                              child: Text(
                                'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                                style: TextStyle(
                                  fontFamily: 'AmiriQuran',
                                  fontSize: 29,
                                  color: ink,
                                ),
                              ),
                            )
                          : _line(context, lines[line] ?? []),
                    ),
                  Text(
                    '${data.page}',
                    style: TextStyle(
                      fontFamily: 'QuranUI',
                      fontSize: 13,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, QuranSurah chapter) => Container(
    margin: const EdgeInsets.symmetric(vertical: 3),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0x15B38C42),
      border: Border.all(color: qGold),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        const Icon(Icons.filter_vintage_outlined, size: 26, color: qGold),
        Text(
          'سورة ${chapter.name}',
          style: const TextStyle(
            fontFamily: 'QuranUI',
            color: qNavy,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Icon(Icons.filter_vintage_outlined, size: 26, color: qGold),
      ],
    ),
  );
  Widget _line(BuildContext context, List<MushafWord> words) {
    if (words.isEmpty) return const SizedBox();
    final naturalWidths = words.map((word) {
      final painter = TextPainter(
        text: TextSpan(
          text: word.glyph,
          style: TextStyle(fontFamily: data.fontFamily, fontSize: 35),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      return painter.width;
    }).toList();
    final sum = naturalWidths.fold<double>(0, (a, b) => a + b);
    final factor = (490 / sum).clamp(.1, 1.0);
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
                        ? const Color(0x30C7A45A)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    words[i].glyph,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontFamily: data.fontFamily,
                      fontSize: 35 * factor,
                      height: 1.4,
                      color: ink,
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

class MushafBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gold = Paint()
      ..color = qGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final inset in [4.0, 8.0, 21.0, 24.0]) {
      canvas.drawRect(
        Rect.fromLTWH(
          inset,
          inset,
          size.width - 2 * inset,
          size.height - 2 * inset,
        ),
        gold,
      );
    }
    final green = Paint()..color = const Color(0xFF275D3B);
    for (final vertical in [false, true]) {
      final length = vertical ? size.height : size.width;
      for (double t = 17; t < length - 12; t += 18) {
        for (final far in [false, true]) {
          final center = vertical
              ? Offset(far ? size.width - 14 : 14, t)
              : Offset(t, far ? size.height - 14 : 14);
          final petal = Path();
          for (var k = 0; k < 8; k++) {
            final angle = k * math.pi / 4;
            final point =
                center +
                Offset(math.cos(angle), math.sin(angle)) * (k.isEven ? 6 : 3);
            if (k == 0) {
              petal.moveTo(point.dx, point.dy);
            } else {
              petal.lineTo(point.dx, point.dy);
            }
          }
          petal.close();
          canvas.drawPath(petal, green);
          canvas.drawPath(petal, gold);
          canvas.drawCircle(center, 1.6, Paint()..color = qGold);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
