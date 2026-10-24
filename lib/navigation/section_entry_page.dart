import 'package:flutter/material.dart';

import '../app_appearance.dart';
import '../features/religious_content/data/religious_controller.dart';
import 'feature_routes.dart';
import 'more_page.dart';

/// Uses today's saved content. Daily counters and sessions belong to P03.
class AdhkarSectionPage extends StatelessWidget {
  const AdhkarSectionPage({
    super.key,
    required this.controller,
    required this.onFeature,
  });
  final ReligiousController controller;
  final ValueChanged<AppFeature> onFeature;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => CustomScrollView(
        key: const PageStorageKey('adhkar-section'),
        slivers: [
          const SliverToBoxAdapter(
            child: DirectoryHeader(
              title: 'الأذكار',
              subtitle: 'أذكارك وأدعيتك\nفي مكان واحد',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
            sliver: SliverList.list(
              children: [
                Text(
                  'المتاح حاليًا',
                  style: TextStyle(
                    color: palette.heading,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                for (final feature in [
                  AppFeature.personalAdhkar,
                  AppFeature.quranDuas,
                  AppFeature.propheticDuas,
                  AppFeature.sunnah,
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: palette.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: palette.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        key: ValueKey('adhkar-${feature.name}'),
                        leading: Icon(feature.icon, color: palette.tealHeading),
                        title: Text(
                          feature.title,
                          style: TextStyle(
                            color: palette.heading,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: feature == AppFeature.personalAdhkar
                            ? Text(
                                '${controller.customAdhkar.length} من المواد المحفوظة',
                              )
                            : null,
                        trailing: Icon(
                          Icons.chevron_left,
                          textDirection: TextDirection.ltr,
                          color: palette.muted,
                        ),
                        onTap: () => onFeature(feature),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  'الأذكار اليومية وجلسات العدّ ستتوفر لاحقًا.',
                  style: TextStyle(color: palette.muted, height: 1.7),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Honest destination for stages that have not shipped yet: no fabricated
/// readings, GPS direction, totals, subscription prices or success states.
class FeaturePreparationPage extends StatelessWidget {
  const FeaturePreparationPage({
    super.key,
    required this.feature,
    this.embedded = false,
  });
  final AppFeature feature;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final content = SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 38, 24, 110),
        child: Column(
          children: [
            Icon(feature.icon, color: palette.tealHeading, size: 64),
            const SizedBox(height: 24),
            Text(
              feature.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.heading,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'قريبًا في حق',
              style: TextStyle(
                color: palette.gold,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              feature == AppFeature.qibla
                  ? 'خدمة تحديد اتجاه القبلة لم تتوفر بعد. لن نعرض اتجاهًا قبل تحديد موقعك والتحقق منه.'
                  : 'نعمل على تجهيز هذه الخدمة. يمكنك الآن الاستفادة من القرآن والأدعية والمحتوى الديني.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, height: 1.8),
            ),
            if (!embedded) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('العودة إلى الخدمات'),
              ),
            ],
          ],
        ),
      ),
    );
    if (embedded) return ColoredBox(color: palette.background, child: content);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(title: Text(feature.title)),
        body: content,
      ),
    );
  }
}
