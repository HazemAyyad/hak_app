import 'package:flutter/material.dart';

import '../app_appearance.dart';
import 'feature_routes.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.onFeature});
  final ValueChanged<AppFeature> onFeature;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final secondary = AppFeature.values
        .where(
          (feature) =>
              !AppFeature.featured.contains(feature) &&
              feature != AppFeature.settings &&
              feature != AppFeature.appearance,
        )
        .toList();
    return ColoredBox(
      color: palette.background,
      child: CustomScrollView(
        key: const PageStorageKey('more-directory'),
        slivers: [
          SliverToBoxAdapter(
            child: DirectoryHeader(
              title: 'المزيد',
              subtitle: 'خدمات ومحتوى إيماني\nيصل بك إلى الله في كل وقت',
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 110),
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      children: [
                        for (final feature in [
                          AppFeature.settings,
                          AppFeature.appearance,
                        ])
                          ActionChip(
                            key: ValueKey('feature-${feature.name}'),
                            avatar: Icon(
                              feature.icon,
                              size: 17,
                              color: palette.tealHeading,
                            ),
                            label: Text(feature.title),
                            onPressed: () => onFeature(feature),
                            backgroundColor: palette.surface,
                            side: BorderSide(color: palette.border),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final feature in AppFeature.featured)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _FeaturedService(
                          feature: feature,
                          onTap: () => onFeature(feature),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'اكتشف المزيد',
                      style: TextStyle(
                        color: palette.heading,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      primary: false,
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 160,
                        mainAxisExtent:
                            112 *
                            MediaQuery.textScalerOf(
                              context,
                            ).scale(1).clamp(1.0, 1.8),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: secondary.length,
                      itemBuilder: (context, index) {
                        final feature = secondary[index];
                        return Material(
                          color: palette.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(color: palette.border),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: ValueKey('feature-${feature.name}'),
                            onTap: () => onFeature(feature),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    feature.icon,
                                    color: palette.tealHeading,
                                    size: 28,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    feature.title,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: palette.heading,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (!feature.ready)
                                    Text(
                                      'قريبًا',
                                      style: TextStyle(
                                        color: palette.muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DirectoryHeader extends StatelessWidget {
  const DirectoryHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });
  final String title, subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      height: 218 + MediaQuery.paddingOf(context).top,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/navigation/more_header.png', fit: BoxFit.cover),
          if (palette.dark)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    palette.background,
                    palette.background.withValues(alpha: .85),
                    Colors.transparent,
                  ],
                  stops: const [0, .4, 1],
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              MediaQuery.paddingOf(context).top + 25,
              20,
              24,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width * .53,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: palette.heading,
                        fontSize: 29,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: palette.dark
                            ? palette.muted
                            : const Color(0xFF285571),
                        fontSize: 13,
                        height: 1.7,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedService extends StatelessWidget {
  const _FeaturedService({required this.feature, required this.onTap});
  final AppFeature feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border.withValues(alpha: .7)),
        boxShadow: palette.dark
            ? []
            : const [
                BoxShadow(
                  color: Color(0x08664D24),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('feature-${feature.name}'),
          onTap: onTap,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: 143,
                child: ClipRect(
                  child: Transform.scale(
                    scale: feature == AppFeature.sakinah ? 2.2 : 1,
                    alignment: Alignment.bottomLeft,
                    child: Image.asset(
                      feature.imageAsset!,
                      fit: BoxFit.cover,
                      alignment: feature == AppFeature.sakinah
                          ? Alignment.bottomLeft
                          : Alignment.center,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: 165,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        palette.surface.withValues(alpha: 0),
                        palette.surface,
                      ],
                      stops: const [.1, .92],
                    ),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 78),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 85, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              feature == AppFeature.adhkar
                                  ? 'الأذكار'
                                  : feature == AppFeature.tasbih
                                  ? 'المسبحة'
                                  : feature.title,
                              style: TextStyle(
                                color: palette.heading,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              feature.subtitle!,
                              style: TextStyle(
                                color: palette.muted,
                                fontSize: 11,
                                height: 1.55,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        feature.icon,
                        color:
                            feature == AppFeature.quran ||
                                feature == AppFeature.khatma
                            ? palette.gold
                            : palette.tealHeading,
                        size: 29,
                      ),
                      const SizedBox(width: 9),
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: palette.neutral,
                        child: Icon(
                          Icons.chevron_left,
                          textDirection: TextDirection.ltr,
                          color: palette.heading,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
