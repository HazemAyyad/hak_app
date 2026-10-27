import 'package:flutter/material.dart';

import '../app_appearance.dart';
import 'feature_routes.dart';

class MorePage extends StatefulWidget {
  const MorePage({super.key, required this.onFeature});
  final ValueChanged<AppFeature> onFeature;

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  final _search = TextEditingController();
  String _query = '';

  String _normalized(String value) => value
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .trim();

  bool _matches(AppFeature feature) => _normalized(
    '${feature.title} ${feature.subtitle ?? ''}',
  ).contains(_query);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final secondary = AppFeature.values
        .where(
          (feature) =>
              !AppFeature.featured.contains(feature) &&
              feature != AppFeature.settings &&
              feature != AppFeature.appearance &&
              _matches(feature),
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
                    TextField(
                      key: const ValueKey('more-search'),
                      controller: _search,
                      onChanged: (value) =>
                          setState(() => _query = _normalized(value)),
                      decoration: InputDecoration(
                        hintText: 'ابحث عن خدمة…',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'مسح البحث',
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.close),
                              ),
                        filled: true,
                        fillColor: palette.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: palette.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: palette.border),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      children: [
                        for (final feature in [
                          AppFeature.settings,
                          AppFeature.appearance,
                        ].where(_matches))
                          ActionChip(
                            key: ValueKey('feature-${feature.name}'),
                            avatar: Icon(
                              feature.icon,
                              size: 17,
                              color: palette.tealHeading,
                            ),
                            label: Text(feature.title),
                            onPressed: () => widget.onFeature(feature),
                            backgroundColor: palette.surface,
                            side: BorderSide(color: palette.border),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final feature in AppFeature.featured.where(_matches))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _FeaturedService(
                          feature: feature,
                          onTap: () => widget.onFeature(feature),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      _query.isEmpty ? 'اكتشف المزيد' : 'نتائج البحث',
                      style: TextStyle(
                        color: palette.heading,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!AppFeature.values.any(_matches))
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'لا توجد خدمات تطابق بحثك',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.muted),
                        ),
                      ),
                    for (final feature in secondary)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _FeaturedService(
                          feature: feature,
                          onTap: () => widget.onFeature(feature),
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

class DirectoryHeader extends StatelessWidget {
  const DirectoryHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.maxTitleLines,
    this.onBack,
    this.imageAsset = 'assets/navigation/more_header.png',
  });
  final String title, subtitle;
  final String imageAsset;
  final int? maxTitleLines;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      height:
          218 +
          (onBack == null
              ? 0
              : 60 +
                    (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(
                          0,
                          3,
                        ) *
                        180) +
          MediaQuery.paddingOf(context).top +
          (imageAsset == 'assets/navigation/more_header.png'
              ? 0
              : (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 3) *
                    110),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(imageAsset, fit: BoxFit.cover),
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
                      maxLines: maxTitleLines,
                      overflow: maxTitleLines == null
                          ? null
                          : TextOverflow.ellipsis,
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
          if (onBack != null)
            Positioned(
              left: 16,
              top: MediaQuery.paddingOf(context).top + 18,
              child: Material(
                color: palette.surface,
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: onBack,
                  tooltip: 'رجوع',
                  icon: Icon(Icons.arrow_back_ios_new, color: palette.heading),
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
              if (feature.imageAsset != null)
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
                  padding: EdgeInsets.fromLTRB(
                    8,
                    12,
                    feature.imageAsset == null ? 16 : 85,
                    12,
                  ),
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
                              feature.subtitle ?? _description(feature),
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

String _description(AppFeature feature) => switch (feature) {
  AppFeature.religiousLibrary => 'أدعية وأسماء الله الحسنى ورقية شرعية',
  AppFeature.duaTogether => 'شارك الدعاء وتفاعل مع المجتمع',
  AppFeature.circles => 'ذكر مشترك ومتابعة المساهمات',
  AppFeature.statistics => 'تابع نشاطك وإنجازاتك المسجلة',
  AppFeature.personalAdhkar => 'أذكارك ومجموعاتك الخاصة',
  AppFeature.names => 'أسماء الله الحسنى ومعانيها',
  AppFeature.ramadan => 'ورد وأدعية وأعمال رمضان',
  AppFeature.sunnah || AppFeature.friday => 'سنن وآداب من الهدي النبوي',
  AppFeature.hadith || AppFeature.nawawi => 'أحاديث نبوية مع الشرح والمصدر',
  AppFeature.mosques => 'ابحث عن المساجد القريبة منك',
  AppFeature.messages || AppFeature.stories => 'رسائل ومحتوى إيماني من حق',
  AppFeature.assistant => 'افتح المساعد وسجل محادثاتك',
  AppFeature.subscription => 'تفاصيل الباكج وإدارة الاشتراك',
  AppFeature.ourApps => 'تعرف على تطبيقات حق',
  _ => 'افتح القسم واستكشف محتواه',
};
