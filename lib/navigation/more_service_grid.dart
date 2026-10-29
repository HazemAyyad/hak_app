import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_appearance.dart';
import 'feature_routes.dart';

const moreServiceGroups = <(String, List<AppFeature>)>[
  (
    'العبادات والأذكار',
    [
      AppFeature.adhkar,
      AppFeature.tasbih,
      AppFeature.names,
      AppFeature.dailyDuas,
      AppFeature.ruqya,
      AppFeature.hadith,
    ],
  ),
  (
    'رحلتك الإيمانية',
    [
      AppFeature.sakinah,
      AppFeature.khatma,
      AppFeature.habits,
      AppFeature.statistics,
      AppFeature.feelings,
      AppFeature.savedContent,
    ],
  ),
  (
    'القرآن والأدعية والسنن',
    [
      AppFeature.quran,
      AppFeature.personalAdhkar,
      AppFeature.quranDuas,
      AppFeature.propheticDuas,
      AppFeature.prophets,
      AppFeature.istighfar,
      AppFeature.praise,
      AppFeature.glorification,
      AppFeature.nawawi,
      AppFeature.sunnah,
      AppFeature.friday,
      AppFeature.ramadan,
    ],
  ),
  (
    'مجتمع حق',
    [
      AppFeature.duaTogether,
      AppFeature.circles,
      AppFeature.messages,
      AppFeature.stories,
    ],
  ),
  (
    'خدمات حق',
    [
      AppFeature.qibla,
      AppFeature.mosques,
      AppFeature.assistant,
      AppFeature.subscription,
      AppFeature.ourApps,
    ],
  ),
];

String _title(AppFeature feature) => switch (feature) {
  AppFeature.adhkar => 'الأذكار',
  AppFeature.tasbih => 'المسبحة',
  _ => feature.title,
};

const _titleStyle = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w800,
  height: 1.5,
);

/// Measures full labels to keep both columns readable with enlarged text.
double moreServiceTileHeight(BuildContext context, double width) {
  final style = DefaultTextStyle.of(context).style.merge(_titleStyle);
  final labelWidth = math.max(1.0, (width - 44) / 2 - 24);
  var labelHeight = 0.0;
  for (final feature in AppFeature.values) {
    final painter = TextPainter(
      text: TextSpan(text: _title(feature), style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: labelWidth);
    labelHeight = math.max(labelHeight, painter.height);
    painter.dispose();
  }
  return 24 + 44 + 10 + labelHeight.ceilToDouble();
}

class MoreServiceGrid extends StatelessWidget {
  const MoreServiceGrid({
    super.key,
    required this.features,
    required this.tileHeight,
    required this.onFeature,
  });

  final List<AppFeature> features;
  final double tileHeight;
  final ValueChanged<AppFeature> onFeature;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    sliver: SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: tileHeight,
      ),
      itemCount: features.length,
      itemBuilder: (context, index) {
        final feature = features[index];
        return _ServiceTile(feature: feature, onTap: () => onFeature(feature));
      },
    ),
  );
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.feature, required this.onTap});
  final AppFeature feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: palette.dark
            ? []
            : const [
                BoxShadow(
                  color: Color(0x06664D24),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
      ),
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('feature-${feature.name}'),
          onTap: onTap,
          child: Semantics(
            button: true,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: palette.paleTeal,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        feature.icon,
                        color: palette.tealHeading,
                        size: 27,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _title(feature),
                    textAlign: TextAlign.center,
                    style: _titleStyle.copyWith(color: palette.heading),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
