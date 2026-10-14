import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/quran_page_downloads.dart';
import 'quran_widgets.dart';

/// One actual downloaded SVG with its matching ayah geometry. No font request,
/// provider API response, or network image is needed to read or select an ayah.
class QuranOfflinePage extends StatelessWidget {
  const QuranOfflinePage({
    super.key,
    required this.data,
    required this.selected,
    required this.onSelect,
    this.paper = const Color(0xFFFFFCF5),
    this.ink = const Color(0xFF231F20),
  });
  final QuranOfflinePageData data;
  final String selected;
  final ValueChanged<String> onSelect;
  final Color paper, ink;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.clamp(0.0, 560.0);
      final box = data.displayBox;
      final artHeight = (width - 54) * box.height / box.width;
      return SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: paper,
            border: Border.all(color: qGold.withValues(alpha: .6)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 16, 26, 20),
            child: Column(
              children: [
                Text(
                  'الصفحة ${data.page}',
                  style: qText(context, size: 12, color: ink),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  key: ValueKey('offline-mushaf-image-${data.page}'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final local = details.localPosition;
                    final point = Offset(
                      box.left + local.dx / (width - 54) * box.width,
                      box.top + local.dy / artHeight * box.height,
                    );
                    final key = data.verseAt(point);
                    if (key != null) onSelect(key);
                  },
                  child: SizedBox(
                    width: width - 54,
                    height: artHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(painter: _SelectedAyah(data, selected)),
                        IgnorePointer(
                          child: SvgPicture.string(
                            data.displaySvg,
                            fit: BoxFit.fill,
                            colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
                            semanticsLabel:
                                'صفحة ${data.page} من مصحف المدينة، محفوظة بدون إنترنت',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.offline_pin_outlined,
                      size: 13,
                      color: qTeal,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'متاحة بدون إنترنت',
                        style: qText(context, size: 10, color: ink),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SelectedAyah extends CustomPainter {
  _SelectedAyah(this.data, this.selected);
  final QuranOfflinePageData data;
  final String selected;
  @override
  void paint(Canvas canvas, Size size) {
    final box = data.displayBox;
    canvas.save();
    canvas.scale(size.width / box.width, size.height / box.height);
    canvas.translate(-box.left, -box.top);
    final paint = Paint()..color = qTeal.withValues(alpha: .13);
    for (final region in data.regions) {
      if (region.key == selected) canvas.drawPath(region.path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SelectedAyah oldDelegate) =>
      oldDelegate.data != data || oldDelegate.selected != selected;
}
