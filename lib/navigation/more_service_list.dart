import 'package:flutter/material.dart';

import '../app_appearance.dart';
import 'feature_routes.dart';

/// Every destination has local artwork, including settings in search results.
String moreServiceImage(AppFeature feature) =>
    feature.imageAsset ??
    switch (feature) {
      AppFeature.dailyDuas => 'assets/religious/daily.png',
      AppFeature.savedContent ||
      AppFeature.hadith ||
      AppFeature.assistant => 'assets/religious/books.png',
      AppFeature.duaTogether ||
      AppFeature.praise ||
      AppFeature.prophets => 'assets/religious/prayer.png',
      AppFeature.circles => 'assets/religious/hall.png',
      AppFeature.settings ||
      AppFeature.appearance ||
      AppFeature.ourApps => 'assets/branding/haq_app_icon.png',
      AppFeature.statistics => 'assets/religious/open_quran.png',
      AppFeature.personalAdhkar ||
      AppFeature.istighfar ||
      AppFeature.glorification => 'assets/religious/beads.png',
      AppFeature.qibla ||
      AppFeature.subscription => 'assets/religious/kaaba.png',
      AppFeature.habits => 'assets/religious/prayer.png',
      AppFeature.ramadan => 'assets/religious/lantern.png',
      AppFeature.mosques => 'assets/religious/mosque.png',
      AppFeature.messages => 'assets/religious/hands.png',
      AppFeature.stories => 'assets/religious/madina.png',
      // These services already declare their artwork in AppFeature.
      AppFeature.tasbih ||
      AppFeature.names ||
      AppFeature.feelings ||
      AppFeature.adhkar ||
      AppFeature.quran ||
      AppFeature.ruqya ||
      AppFeature.nawawi ||
      AppFeature.propheticDuas ||
      AppFeature.quranDuas ||
      AppFeature.khatma ||
      AppFeature.friday ||
      AppFeature.sunnah ||
      AppFeature.sakinah => feature.imageAsset!,
    };

String _description(AppFeature feature) =>
    feature.subtitle ??
    switch (feature) {
      AppFeature.dailyDuas => 'أدعية وآداب لمواقف يومك',
      AppFeature.savedContent => 'الأدعية والمحتوى الذي حفظته',
      AppFeature.duaTogether => 'شارك الدعاء وتفاعل مع المجتمع',
      AppFeature.circles => 'ذكر مشترك ومتابعة المساهمات',
      AppFeature.settings => 'خصص تجربتك في حق',
      AppFeature.statistics => 'تابع نشاطك وإنجازاتك المسجلة',
      AppFeature.personalAdhkar => 'أذكارك ومجموعاتك الخاصة',
      AppFeature.names => 'أسماء الله الحسنى ومعانيها',
      AppFeature.qibla => 'اعرف اتجاه القبلة',
      AppFeature.habits => 'نظم عاداتك وتابع التزامك',
      AppFeature.ruqya => 'آيات وأدعية الرقية الشرعية',
      AppFeature.istighfar => 'صيغ الاستغفار وفضله',
      AppFeature.praise => 'أذكار الحمد والثناء',
      AppFeature.glorification => 'سبح الله وداوم على ذكره',
      AppFeature.prophets => 'أدعية الأنبياء من القرآن والسنة',
      AppFeature.propheticDuas => 'أدعية مأثورة عن النبي ﷺ',
      AppFeature.quranDuas => 'أدعية من آيات القرآن الكريم',
      AppFeature.ramadan => 'ورد وأدعية وأعمال رمضان',
      AppFeature.sunnah || AppFeature.friday => 'سنن وآداب من الهدي النبوي',
      AppFeature.hadith || AppFeature.nawawi => 'أحاديث نبوية مع الشرح والمصدر',
      AppFeature.appearance => 'الألوان والخط وحجم النص',
      AppFeature.mosques => 'ابحث عن المساجد القريبة منك',
      AppFeature.messages || AppFeature.stories => 'محتوى إيماني من حق',
      AppFeature.assistant => 'افتح المساعد وسجل محادثاتك',
      AppFeature.subscription => 'تفاصيل الباكج وإدارة الاشتراك',
      AppFeature.ourApps => 'تعرف على تطبيقات حق',
      _ => '',
    };

class MoreServiceList extends StatelessWidget {
  const MoreServiceList({
    super.key,
    required this.features,
    required this.onFeature,
  });

  final List<AppFeature> features;
  final ValueChanged<AppFeature> onFeature;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    sliver: SliverList.builder(
      itemCount: features.length,
      itemBuilder: (context, index) {
        final feature = features[index];
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == features.length - 1 ? 0 : 10,
          ),
          child: _ServiceCard(
            feature: feature,
            onTap: () => onFeature(feature),
          ),
        );
      },
    ),
  );
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.feature, required this.onTap});

  final AppFeature feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final title = switch (feature) {
      AppFeature.adhkar => 'الأذكار',
      AppFeature.tasbih => 'المسبحة',
      _ => feature.title,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('feature-${feature.name}'),
          onTap: onTap,
          child: Semantics(
            button: true,
            child: Stack(
              children: [
                Positioned.directional(
                  textDirection: Directionality.of(context),
                  top: 0,
                  bottom: 0,
                  start: 0,
                  width: 128,
                  child: ExcludeSemantics(
                    child: Image.asset(
                      moreServiceImage(feature),
                      fit: BoxFit.cover,
                      alignment: feature == AppFeature.sakinah
                          ? Alignment.bottomLeft
                          : Alignment.center,
                    ),
                  ),
                ),
                Positioned.directional(
                  textDirection: Directionality.of(context),
                  top: 0,
                  bottom: 0,
                  start: 0,
                  width: 146,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: AlignmentDirectional.centerStart,
                        end: AlignmentDirectional.centerEnd,
                        colors: [
                          palette.surface.withValues(alpha: 0),
                          palette.surface,
                        ],
                        stops: const [.3, .7],
                      ),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 100),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      104,
                      14,
                      12,
                      14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  color: palette.heading,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _description(feature),
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 11,
                                  height: 1.55,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_left,
                          textDirection: TextDirection.ltr,
                          color: palette.tealHeading,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
