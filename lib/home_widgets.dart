part of 'main.dart';

const _homeTeal = Color(0xFF00818B);
const _homeGold = Color(0xFFCAA15D);

String _homePlural(BuildContext context, String key, int count) =>
    LocalizationScope.maybeOf(context)?.pluralText('home.$key', count) ??
    (key == 'pages' ? '$count صفحة' : '$count قراءة اليوم');

String _homeHijri(BuildContext context, PrayerController? controller) {
  if (controller != null) return prayerHijriInterfaceLabel(context, controller);
  final localization = LocalizationScope.maybeOf(context);
  final now = DateTime.now();
  if (localization == null || localization.code == 'ar') {
    return prayerHijriDate(now);
  }
  final parts = prayerHijriParts(now);
  if (parts == null) return prayerHijriDate(now);
  return localization.text(
    'prayer.hijriDate',
    args: {
      'day': localization.formats.integer(parts.day),
      'month': localization.text('prayer.hijriMonth.${parts.month}'),
      'year': localization.formats.integer(parts.year),
    },
  );
}

TextStyle _homeText(
  BuildContext context,
  double size, {
  FontWeight weight = FontWeight.w600,
  Color? color,
}) => TextStyle(
  fontSize: size,
  height: 1.45,
  fontWeight: weight,
  color: color ?? AppPalette.of(context).heading,
);

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.name,
    required this.onAccount,
    required this.onLanguage,
    required this.onSearch,
    required this.onNotifications,
  });
  final String name;
  final VoidCallback onAccount, onLanguage, onSearch, onNotifications;
  @override
  Widget build(BuildContext context) {
    final dark = AppPalette.of(context).dark;
    final top = MediaQuery.paddingOf(context).top;
    final greetingBackground =
        (LocalizationScope.maybeOf(context)?.code ?? 'ar') == 'ar'
        ? null
        : dark
        ? const Color(0xE6102D3A)
        : const Color(0xE6FFFCF7);
    return Container(
      height: 238 + top + (MediaQuery.textScalerOf(context).scale(1) - 1) * 80,
      padding: EdgeInsets.fromLTRB(22, top + 22, 22, 20),
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            'assets/home/header_${dark ? 'dark' : 'light'}.png',
          ),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              _RoundButton(
                icon: Icons.person_outline,
                onTap: onAccount,
                tooltip: context.homeLabel('الحساب'),
              ),
              const SizedBox(width: 10),
              _RoundButton(
                icon: Icons.language,
                onTap: onLanguage,
                tooltip: context.tr('language.title', fallback: 'لغة التطبيق'),
              ),
              const Spacer(),
              _RoundButton(
                icon: Icons.search,
                onTap: onSearch,
                tooltip: context.homeLabel('البحث في حق'),
              ),
              const SizedBox(width: 10),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _RoundButton(
                    icon: Icons.notifications_none,
                    onTap: onNotifications,
                    tooltip: context.homeLabel('رسائل حق'),
                  ),
                ],
              ),
            ],
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SizedBox.square(
                dimension: math.min(
                  100,
                  MediaQuery.sizeOf(context).width - 244,
                ),
                child: Stack(
                  children: [
                    Image.asset(
                      'assets/branding/haq_logo_transparent.png',
                      fit: BoxFit.contain,
                      color: dark ? const Color(0xFFE9F0F2) : null,
                    ),
                    if (dark)
                      ClipPath(
                        clipper: const _LogoAccentsClipper(),
                        child: Image.asset(
                          'assets/branding/haq_logo_transparent.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.bottomStart,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.homeLabel('مرحبًا بك'),
                  style: _homeText(
                    context,
                    13,
                  ).copyWith(backgroundColor: greetingBackground),
                ),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _homeText(
                    context,
                    21,
                    weight: FontWeight.w800,
                  ).copyWith(backgroundColor: greetingBackground),
                ),
                const SizedBox(height: 4),
                Text(
                  context.homeLabel(
                    'تقبّل الله طاعاتك.. وجعلنا وإياك من أهل القرآن',
                  ),
                  style: _homeText(
                    context,
                    10,
                    weight: FontWeight.w500,
                  ).copyWith(backgroundColor: greetingBackground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Preserve the original gold star and teal leaf while whitening the navy mark.
class _LogoAccentsClipper extends CustomClipper<Path> {
  const _LogoAccentsClipper();
  @override
  Path getClip(Size size) {
    final path = Path()
      ..addRect(
        Rect.fromLTRB(
          size.width * .42,
          size.height * .30,
          size.width * .59,
          size.height * .47,
        ),
      );
    path.moveTo(size.width * .287, size.height * .827);
    path.cubicTo(
      size.width * .43,
      size.height * .81,
      size.width * .55,
      size.height * .72,
      size.width * .617,
      size.height * .695,
    );
    path.cubicTo(
      size.width * .68,
      size.height * .695,
      size.width * .76,
      size.height * .705,
      size.width * .805,
      size.height * .718,
    );
    path.cubicTo(
      size.width * .69,
      size.height * .88,
      size.width * .49,
      size.height * .94,
      size.width * .287,
      size.height * .827,
    );
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_LogoAccentsClipper oldClipper) => false;
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, this.tooltip});
  final String? tooltip;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: AppPalette.of(context).dark
        ? const Color(0xBB24414D)
        : const Color(0xEEFFFFFF),
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      icon: Icon(
        icon,
        size: 25,
        color: appAccent(context, AppPalette.of(context).heading),
      ),
    ),
  );
}

class PrayerCard extends StatelessWidget {
  const PrayerCard({super.key, this.controller, this.onTap, this.onPrayerTap});
  final ValueChanged<PrayerName>? onPrayerTap;
  final PrayerController? controller;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller ?? const AlwaysStoppedAnimation(0),
    builder: (context, _) => _content(context),
  );
  Widget _content(BuildContext context) {
    final palette = AppPalette.of(context);
    String time(PrayerName name) {
      final moment = controller?.today?.moments
          .where((m) => m.name == name)
          .firstOrNull;
      return moment == null
          ? '--:--'
          : quranFormats(context).clock24(moment.time);
    }

    final prayers = [
      ('الفجر', time(PrayerName.fajr), Icons.wb_sunny_outlined),
      ('الظهر', time(PrayerName.dhuhr), Icons.light_mode_outlined),
      ('العصر', time(PrayerName.asr), Icons.wb_twilight),
      ('المغرب', time(PrayerName.maghrib), Icons.wb_twilight),
      ('العشاء', time(PrayerName.isha), Icons.dark_mode),
    ];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: _Surface(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 70,
                  height: 76,
                  decoration: BoxDecoration(
                    color: palette.dark
                        ? const Color(0xFF263F4B)
                        : const Color(0xFFF1EEE7),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.mosque,
                    size: 48,
                    color: appAccent(
                      context,
                      palette.dark ? Colors.white : const Color(0xFF07535D),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.homeLabel('الصلاة القادمة'),
                        style: _homeText(context, 10, weight: FontWeight.w800),
                      ),
                      Text(
                        controller?.upcoming?.name.displayLabel(context) ??
                            context.homeLabel('حدد الموقع'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _homeText(context, 18, weight: FontWeight.w800),
                      ),
                      Text(
                        controller?.countdown ?? '--:--:--',
                        textDirection: TextDirection.ltr,
                        style: _homeText(
                          context,
                          20,
                          weight: FontWeight.w700,
                          color: _homeGold,
                        ),
                      ),
                      Text(
                        context.homeLabel('ساعة   دقيقة   ثانية'),
                        style: _homeText(context, 8, color: palette.muted),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _homeHijri(context, controller),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _homeText(context, 10, color: palette.muted),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 13,
                            color: appAccent(context, palette.heading),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              controller?.config.location?.label ??
                                  context.homeLabel('الموقع غير محدد'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _homeText(
                                context,
                                10,
                                color: palette.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: palette.dark
                    ? const Color(0xFF142F3B)
                    : const Color(0xFFF8F5ED),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: prayers.map((prayer) {
                  final selected =
                      prayer.$1 == controller?.upcoming?.name.label;
                  final color = selected ? Colors.white : palette.heading;
                  return Expanded(
                    child: InkWell(
                      key: ValueKey(
                        'home-prayer-${PrayerName.values.firstWhere((p) => p.label == prayer.$1).name}',
                      ),
                      onTap: onPrayerTap == null
                          ? onTap
                          : () => onPrayerTap!(
                              PrayerName.values.firstWhere(
                                (p) => p.label == prayer.$1,
                              ),
                            ),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: selected
                            ? BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    appAccentFill(
                                      context,
                                      const Color(0xFF008C96),
                                    ),
                                    appAccentFill(
                                      context,
                                      const Color(0xFF00616C),
                                    ),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              )
                            : null,
                        child: Column(
                          children: [
                            Icon(
                              prayer.$3,
                              size: 23,
                              color:
                                  palette.accent != null &&
                                      !palette.accent!.original
                                  ? selected
                                        ? Colors.white
                                        : palette.tealHeading
                                  : prayer.$1 == 'العشاء'
                                  ? color
                                  : _homeGold,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.prayerLabel(prayer.$1),
                              style: _homeText(context, 11, color: color),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              prayer.$2,
                              textDirection: TextDirection.ltr,
                              style: _homeText(
                                context,
                                11,
                                weight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QuickServices extends StatelessWidget {
  const QuickServices({
    super.key,
    this.onQuranTap,
    this.onMoreTap,
    this.onDuasTap,
    this.onAdhkarTap,
    this.onKhatmaTap,
    this.onTasbihTap,
    this.onFeelingsTap,
    this.onQiblaTap,
  });
  final VoidCallback? onQuranTap,
      onMoreTap,
      onDuasTap,
      onAdhkarTap,
      onKhatmaTap,
      onTasbihTap,
      onFeelingsTap,
      onQiblaTap;
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    const items = [
      ('القرآن الكريم', Icons.menu_book_outlined, 'book'),
      ('الأذكار اليومية', Icons.eco, 'leaf'),
      ('الختمة', Icons.mosque_outlined, 'kaaba'),
      ('العداد والتسبيح', Icons.radio_button_checked, 'beads'),
      ('المزيد', Icons.grid_view_rounded, 'grid'),
      ('الأدعية', Icons.front_hand, 'hands'),
      ('ماذا تشعر؟', Icons.favorite, 'heart'),
      ('القبلة', Icons.article, 'qibla'),
    ];
    final translated =
        (LocalizationScope.maybeOf(context)?.code ?? 'ar') != 'ar';
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: math.max(
            (constraints.maxWidth - 30) / 4 * scale,
            translated ? 32 + 7 + 29 * scale + 6 : 0,
          ),
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final warm = index == 5 || index == 6;
          final originalBackground = index == 0
              ? (palette.dark
                    ? const Color(0xFF073342)
                    : const Color(0xFF175366))
              : warm
              ? (palette.dark
                    ? const Color(0xFF303A3B)
                    : const Color(0xFFF7F1E4))
              : palette.dark
              ? (index == 2 || index == 7
                    ? const Color(0xFF142E3B)
                    : const Color(0xFF073C45))
              : const Color(0xFFE8F0EC);
          final originalColor = warm
              ? _homeGold
              : index == 0
              ? const Color(0xFFFFF5DD)
              : palette.dark
              ? const Color(0xFFA8D6DD)
              : const Color(0xFF075C69);
          final custom = palette.accent != null && !palette.accent!.original;
          final background = custom
              ? index == 0
                    ? palette.accent!.strong
                    : palette.paleTeal
              : originalBackground;
          final color = custom && index != 0
              ? palette.tealHeading
              : originalColor;
          return Material(
            color: background,
            borderRadius: BorderRadius.circular(15),
            child: InkWell(
              key: ValueKey('home-service-$index'),
              onTap: [
                onQuranTap,
                onAdhkarTap,
                onKhatmaTap,
                onTasbihTap,
                onMoreTap,
                onDuasTap,
                onFeelingsTap,
                onQiblaTap,
              ][index],
              borderRadius: BorderRadius.circular(15),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _HomeGlyph(
                    kind: items[index].$3,
                    fallback: items[index].$2,
                    color: color,
                    size: 32,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    context.homeLabel(items[index].$1),
                    maxLines: translated ? 2 : 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: _homeText(
                      context,
                      10,
                      color: index == 0 ? Colors.white : palette.heading,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class DhikrCard extends StatelessWidget {
  const DhikrCard({super.key, this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final day = AppearanceScope.of(context).isDaytime;
    final title = day
        ? context.homeLabel('أذكار الصباح')
        : context.homeLabel('أذكار المساء');
    final invitation = day
        ? context.homeLabel('ابدأ يومك بذكر الله')
        : context.homeLabel('اختم يومك بذكر الله');
    return _PhotoCard(
      image: day ? 'assets/home/dawn.png' : 'assets/home/lantern.png',
      height: 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      day
                          ? Icons.wb_sunny_outlined
                          : Icons.nights_stay_outlined,
                      color: appAccent(context, _homeGold),
                      size: 35,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: _homeText(context, 18, weight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                Text(invitation, style: _homeText(context, 11)),
                const SizedBox(height: 9),
                Text(
                  day
                      ? context.homeLabel(
                          'مجموعة من الأذكار الصحيحة لبدء يومك بالبركة والطمأنينة.',
                        )
                      : context.homeLabel(
                          'مجموعة من الأذكار الصحيحة لمساء يملؤه الذكر والطمأنينة.',
                        ),
                  style: _homeText(context, 10, weight: FontWeight.w500),
                ),
                const Spacer(),
                _HomeButton(
                  label: context.homeLabel('عرض الأذكار'),
                  gold: true,
                  onPressed: onTap,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.bottomRight,
              child: _ShareButton(text: '$invitation — $title'),
            ),
          ),
        ],
      ),
    );
  }
}

class ReadingCard extends StatelessWidget {
  const ReadingCard({super.key, this.controller, this.onContinue});
  final QuranController? controller;
  final VoidCallback? onContinue;
  @override
  Widget build(BuildContext context) => controller == null
      ? _card(context)
      : ListenableBuilder(
          listenable: controller!,
          builder: (context, _) => _card(context),
        );
  Widget _card(BuildContext context) {
    final verse = controller?.lastVerse;
    final surah = verse == null
        ? null
        : controller!.repository!.surah(verse.surah);
    return _PhotoCard(
      image: 'assets/home/reading.png',
      height: 170,
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.homeLabel('أكمل من حيث توقفت'),
                  style: _homeText(context, 14, weight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  surah == null
                      ? context.homeLabel('ابدأ رحلتك مع القرآن')
                      : surah.localizedTitle(context),
                  style: _homeText(context, 14, weight: FontWeight.w800),
                ),
                Text(
                  verse == null
                      ? context.homeLabel('سيُحفظ موضع قراءتك هنا')
                      : context.tr(
                          'home.ayah',
                          args: {'number': quranNumber(context, verse.ayah)},
                        ),
                  style: _homeText(
                    context,
                    11,
                    color: AppPalette.of(context).muted,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: verse == null ? 0 : verse.ayah / surah!.ayahCount,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(6),
                  color: appAccent(context, _homeTeal),
                  backgroundColor: AppPalette.of(context).dark
                      ? const Color(0xFF29404A)
                      : const Color(0xFFE4E1DB),
                ),
                const SizedBox(height: 12),
                _HomeButton(
                  label: context.homeLabel('متابعة القراءة'),
                  onPressed: onContinue,
                  arrow: true,
                ),
              ],
            ),
          ),
          const Spacer(flex: 4),
        ],
      ),
    );
  }
}

class DailyVerseCard extends StatelessWidget {
  const DailyVerseCard({super.key, this.onTafsir});
  final VoidCallback? onTafsir;
  static const verse =
      'وَمَن يَتَّقِ اللَّهَ يَجْعَل لَّهُ مِنْ أَمْرِهِ يُسْرًا';
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return _Surface(
      padding: const EdgeInsets.all(9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.homeLabel('محتوى اليوم'),
                  style: _homeText(context, 14, weight: FontWeight.w800),
                ),
                const SizedBox(height: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: palette.dark
                        ? const Color(0xFF06525A)
                        : const Color(0xFFF8EBCB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    context.homeLabel('آية اليوم'),
                    style: _homeText(
                      context,
                      10,
                      color: palette.dark
                          ? Colors.white
                          : const Color(0xFFB18A43),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '$verse ﴿٤﴾',
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: 'AmiriQuran',
                    fontSize: 18,
                    height: 1.65,
                    color: palette.heading,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.homeLabel('سورة الطلاق - الآية 4'),
                  style: _homeText(context, 10, color: palette.tealHeading),
                ),
                const SizedBox(height: 9),
                OutlinedButton(
                  onPressed:
                      onTafsir ??
                      () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(context.homeLabel('آية اليوم')),
                          content: Text(
                            context.homeLabel(
                              'سورة الطلاق — الآية 4\n\nالتفسير غير متاح حاليًا دون مصدر تفسير معتمد.',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(context.homeLabel('إغلاق')),
                            ),
                          ],
                        ),
                      ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.heading,
                    backgroundColor: palette.neutral,
                    side: BorderSide(color: palette.border),
                    minimumSize: const Size(120, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    context.homeLabel('عرض التفسير'),
                    style: _homeText(context, 10, weight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 100,
            height: 168,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/home/header_${palette.dark ? 'dark' : 'light'}.png',
                  fit: BoxFit.cover,
                  alignment: const Alignment(-.65, 0),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _ShareButton(text: verse),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class JourneyCards extends StatelessWidget {
  const JourneyCards({super.key, this.controller, this.onFeature});
  final ReligiousController? controller;
  final ValueChanged<AppFeature>? onFeature;
  @override
  Widget build(BuildContext context) => ProgressSummary(
    controller: controller,
    builder: (context, c, failed) => _content(context, c, failed),
  );
  Widget _content(BuildContext context, ProgressController? c, bool failed) {
    final palette = AppPalette.of(context);
    final habits = c?.habits.where((h) => c.due(h)).toList() ?? [];
    final goal = habits.fold<int>(0, (sum, h) => sum + h.target);
    final done = habits.fold<int>(0, (sum, h) => sum + c!.habitCount(h));
    final totals = c?.totals(date: c.day);
    final active = c?.khatmas
        .where((k) => k.archived != true && !c.completed(k))
        .firstOrNull;
    final adhkarGoal =
        c?.sessions.values
            .where((s) => s.day == c.day)
            .fold<int>(
              0,
              (sum, s) => sum + s.targets.values.fold<int>(0, (a, b) => a + b),
            ) ??
        0;
    final unavailable = failed ? context.homeLabel('تعذّر التحميل') : '—';
    final items = [
      (
        context.homeLabel('العادات'),
        c == null
            ? unavailable
            : context.tr(
                'home.habitsToday',
                args: {
                  'done': quranNumber(context, done),
                  'goal': quranNumber(context, goal),
                },
              ),
        Icons.spa_outlined,
        'leaf',
        goal == 0 ? 0.0 : done / goal,
      ),
      (
        context.homeLabel('الأذكار'),
        c == null
            ? unavailable
            : _homePlural(context, 'readingsToday', totals!.adhkar),
        Icons.radio_button_checked,
        'beads',
        adhkarGoal == 0 ? 0.0 : (totals!.adhkar / adhkarGoal).clamp(0.0, 1.0),
      ),
      (
        context.homeLabel('الختمة'),
        c == null
            ? unavailable
            : active == null
            ? context.homeLabel('لم تبدأ بعد')
            : _homePlural(context, 'pages', c.readPages(active).length),
        Icons.menu_book_outlined,
        'book',
        active == null ? 0.0 : c!.fraction(active),
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => onFeature?.call(
                [AppFeature.habits, AppFeature.adhkar, AppFeature.khatma][i],
              ),
              child: _Surface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                child: Column(
                  children: [
                    _HomeGlyph(
                      kind: items[i].$4,
                      fallback: items[i].$3,
                      color: appAccent(
                        context,
                        palette.dark ? const Color(0xFF9ED9DF) : _homeTeal,
                      ),
                      size: 29,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      items[i].$1,
                      style: _homeText(context, 11, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 9),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: LinearProgressIndicator(
                        value: items[i].$5,
                        minHeight: 7,
                        borderRadius: BorderRadius.circular(8),
                        color: appAccent(context, _homeTeal),
                        backgroundColor: palette.dark
                            ? const Color(0xFF263F4C)
                            : const Color(0xFFEAE7E1),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      items[i].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _homeText(context, 10, color: palette.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class FridayCard extends StatelessWidget {
  const FridayCard({super.key, this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => _PhotoCard(
    image:
        'assets/home/header_${AppPalette.of(context).dark ? 'dark' : 'light'}.png',
    height: 146,
    minimumHeight: 146,
    imageAlignment: Alignment.bottomLeft,
    child: Row(
      children: [
        Expanded(
          flex: 7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_month,
                    size: 16,
                    color: appAccent(context, AppPalette.of(context).heading),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      context.homeLabel('محتوى خاص'),
                      style: _homeText(context, 10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                context.homeLabel('يوم الجمعة'),
                style: _homeText(context, 16, weight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                context.homeLabel('سورة الكهف . الصلاة على النبي ﷺ'),
                style: _homeText(context, 10),
              ),
              const Spacer(),
              _HomeButton(
                label: context.homeLabel('عرض المحتوى'),
                gold: true,
                onPressed: onTap ?? () {},
              ),
            ],
          ),
        ),
        const Spacer(flex: 3),
      ],
    ),
  );
}

class ArticlesRow extends StatelessWidget {
  const ArticlesRow({super.key, this.onCongregation, this.onCharity});
  final VoidCallback? onCongregation, onCharity;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _ArticleCard(
          onTap: onCongregation,
          title: context.homeLabel('فضل صلاة الجماعة'),
          image: 'assets/home/header_dark.png',
        ),
      ),
      SizedBox(width: 8),
      Expanded(
        child: _ArticleCard(
          onTap: onCharity,
          title: context.homeLabel('فضل الصدقة في الإسلام'),
          image: 'assets/home/lantern.png',
        ),
      ),
    ],
  );
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.title, required this.image, this.onTap});
  final VoidCallback? onTap;
  final String title, image;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      constraints: BoxConstraints(
        minHeight: 104 * MediaQuery.textScalerOf(context).scale(1),
      ),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        image: DecorationImage(image: AssetImage(image), fit: BoxFit.cover),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppPalette.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              color: _homeGold,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              context.homeLabel('مقالة'),
              style: _homeText(context, 10, color: Colors.white),
            ),
          ),
          Text(
            title,
            style: _homeText(
              context,
              11,
              color: Colors.white,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Surface extends StatelessWidget {
  const _Surface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final dark = AppPalette.of(context).dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF102D3A) : const Color(0xFFFEFCF8),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: dark ? const Color(0xFF173A47) : const Color(0xFFF0EDE7),
        ),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: .05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: child,
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.child,
    required this.image,
    required this.height,
    this.minimumHeight = 0,
    this.imageAlignment = Alignment.center,
  });
  final Widget child;
  final String image;
  final double height, minimumHeight;
  final Alignment imageAlignment;
  @override
  Widget build(BuildContext context) {
    final dark = AppPalette.of(context).dark;
    return Container(
      constraints: BoxConstraints(
        minHeight: math.max(
          minimumHeight,
          height * MediaQuery.textScalerOf(context).scale(1),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dark ? const Color(0xFF284652) : const Color(0xFFECE9E2),
        ),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: .06),
                  blurRadius: 8,
                ),
              ],
      ),
      child: IntrinsicHeight(
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: Image.asset(
                image,
                fit: BoxFit.cover,
                alignment: imageAlignment,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerEnd,
                    end: AlignmentDirectional.centerStart,
                    stops: const [0, .44, .68, 1],
                    colors: dark
                        ? const [
                            Color(0x00102D3A),
                            Color(0x20102D3A),
                            Color(0xED102D3A),
                            Color(0xFF102D3A),
                          ]
                        : const [
                            Color(0x00FFFCF7),
                            Color(0x99FFFCF7),
                            Color(0xF5FFFCF7),
                            Color(0xFFFFFCF7),
                          ],
                  ),
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.all(13), child: child),
          ],
        ),
      ),
    );
  }
}

class _HomeButton extends StatelessWidget {
  const _HomeButton({
    required this.label,
    required this.onPressed,
    this.gold = false,
    this.arrow = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool gold, arrow;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: gold ? _homeGold : appAccentFill(context, _homeTeal),
        foregroundColor: gold && AppPalette.of(context).dark
            ? AppColors.navy
            : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 11,
                height: 1.1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (arrow) ...[
            const SizedBox(width: 10),
            Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_left
                  : Icons.chevron_right,
              size: 18,
              textDirection: TextDirection.ltr,
            ),
          ],
        ],
      ),
    ),
  );
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xEEFFFFFF),
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: context.homeLabel('مشاركة'),
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.share_outlined,
        size: 17,
        color: appAccentFill(context, AppColors.navy),
      ),
      onPressed: () =>
          chooseContentShare(context, ShareCardContent.message(text)),
    ),
  );
}

class _HomeGlyph extends StatelessWidget {
  const _HomeGlyph({
    required this.kind,
    required this.fallback,
    required this.color,
    required this.size,
  });
  final String kind;
  final IconData fallback;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => kind == 'beads' || kind == 'kaaba'
      ? CustomPaint(
          size: Size.square(size),
          painter: _HomeGlyphPainter(kind, color),
        )
      : Icon(fallback, size: size, color: color);
}

class _HomeGlyphPainter extends CustomPainter {
  const _HomeGlyphPainter(this.kind, this.color);
  final String kind;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    final paint = Paint()..color = color;
    if (kind == 'beads') {
      for (var i = 0; i < 19; i++) {
        final angle = i * 2 * math.pi / 20;
        canvas.drawCircle(
          Offset(14 + 9 * math.cos(angle), 14 + 11 * math.sin(angle)),
          1.9,
          paint,
        );
      }
      canvas.drawLine(
        const Offset(22, 21),
        const Offset(25, 27),
        paint..strokeWidth = 2,
      );
      canvas.drawOval(const Rect.fromLTWH(23, 26, 6, 5), paint);
    } else {
      final cube = Path()
        ..moveTo(3, 8)
        ..lineTo(16, 3)
        ..lineTo(29, 8)
        ..lineTo(29, 25)
        ..lineTo(16, 30)
        ..lineTo(3, 25)
        ..close();
      canvas.drawPath(cube, paint);
      final line = Paint()
        ..color = const Color(0xFFF8F0DC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawPath(
        Path()
          ..moveTo(3, 8)
          ..lineTo(16, 13)
          ..lineTo(29, 8)
          ..moveTo(16, 13)
          ..lineTo(16, 30),
        line,
      );
      canvas.drawPath(
        Path()
          ..moveTo(3, 12)
          ..lineTo(16, 17)
          ..lineTo(29, 12),
        line..strokeWidth = 3,
      );
      canvas.drawRect(
        const Rect.fromLTWH(21, 20, 3, 6),
        Paint()..color = const Color(0xFFF8F0DC),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HomeGlyphPainter oldDelegate) =>
      kind != oldDelegate.kind || color != oldDelegate.color;
}
