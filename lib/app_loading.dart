import 'package:flutter/material.dart';

/// Placeholders stay visible for the lifetime of the actual content request.
class AppLoadingSkeleton extends StatelessWidget {
  const AppLoadingSkeleton({
    super.key,
    this.label = 'جارٍ تحميل المحتوى',
    this.lines = 5,
    this.page = true,
  });

  final String label;
  final int lines;
  final bool page;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget block(double height, {double width = double.infinity}) => Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
      ),
    );
    final content = Semantics(
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(label)),
              ],
            ),
            const SizedBox(height: 20),
            if (page) ...[block(112), const SizedBox(height: 24)],
            for (var i = 0; i < lines; i++) ...[
              FractionallySizedBox(
                widthFactor: i.isOdd ? .72 : 1,
                alignment: AlignmentDirectional.centerStart,
                child: block(page ? 46 : 14),
              ),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
    return page
        ? SingleChildScrollView(
            key: const ValueKey('app-page-skeleton'),
            padding: const EdgeInsets.all(24),
            child: content,
          )
        : content;
  }
}
