import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/quran_content.dart';
import '../data/quran_repository.dart';

/// A complete physical line scales together; words never wrap or get clipped.
/// Glyph measurement is reused when only the selected ayah changes.
class QuranMushafLine extends StatefulWidget {
  const QuranMushafLine({
    super.key,
    required this.words,
    required this.fontFamily,
    required this.fontSize,
    required this.centered,
    required this.selected,
    required this.repository,
    required this.onSelect,
    required this.onOptions,
  });
  final List<MushafWord> words;
  final String fontFamily, selected;
  final double fontSize;
  final bool centered;
  final QuranRepository repository;
  final ValueChanged<QuranVerse> onSelect, onOptions;

  @override
  State<QuranMushafLine> createState() => _QuranMushafLineState();
}

class _QuranMushafLineState extends State<QuranMushafLine> {
  List<String>? glyphs;
  String? family;
  double? fontSize;
  double naturalWidth = 0;

  TextStyle get style => TextStyle(
    inherit: false,
    fontFamily: widget.fontFamily,
    fontSize: widget.fontSize,
    letterSpacing: 0,
    height: 1.3,
    color: const Color(0xFF17150F),
  );

  void _measure() {
    final current = widget.words.map((word) => word.glyph).toList();
    if (family == widget.fontFamily &&
        fontSize == widget.fontSize &&
        listEquals(glyphs, current)) {
      return;
    }
    glyphs = current;
    family = widget.fontFamily;
    fontSize = widget.fontSize;
    naturalWidth = 0;
    for (final glyph in current) {
      final painter = TextPainter(
        text: TextSpan(text: glyph, style: style),
        textDirection: TextDirection.rtl,
        textScaler: TextScaler.noScaling,
      )..layout();
      naturalWidth += painter.width;
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    _measure();
    return LayoutBuilder(
      builder: (context, constraints) {
        // Font advances quantize at fractional font sizes. Giving the natural
        // row a small margin and scaling that whole row avoids even subpixel
        // RenderFlex overflow, including long lines at enlarged phone sizes.
        final width = math.max(constraints.maxWidth, naturalWidth + 1);
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            width: width,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                mainAxisAlignment: widget.centered
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.spaceBetween,
                children: [
                  for (final word in widget.words)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        final verse = widget.repository.byKey[word.key]!;
                        widget.onSelect(verse);
                        widget.onOptions(verse);
                      },
                      onLongPress: () {
                        final verse = widget.repository.byKey[word.key]!;
                        widget.onSelect(verse);
                        widget.onOptions(verse);
                      },
                      child: Semantics(
                        label:
                            '${word.text}، الآية ${widget.repository.byKey[word.key]!.ayah}',
                        button: true,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: word.key == widget.selected
                                ? const Color(0x20C7A45A)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            word.glyph,
                            textDirection: TextDirection.rtl,
                            textScaler: TextScaler.noScaling,
                            style: style,
                          ),
                        ),
                      ),
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
