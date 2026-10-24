import 'package:flutter/material.dart';
import '../app_appearance.dart';
import 'feature_routes.dart';
export '../features/adhkar/presentation/adhkar_host.dart'
    show AdhkarSectionPage, AdhkarSectionPageState;

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
