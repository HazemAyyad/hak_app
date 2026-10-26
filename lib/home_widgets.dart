part of 'main.dart';

const _homeTeal = Color(0xFF00818B);
const _homeGold = Color(0xFFCAA15D);

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
  const _HeroHeader();
  @override
  Widget build(BuildContext context) {
    final dark = AppPalette.of(context).dark;
    final top = MediaQuery.paddingOf(context).top;
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
              _RoundButton(icon: Icons.person_outline, onTap: () {}),
              const Spacer(),
              _RoundButton(icon: Icons.search, onTap: () {}),
              const SizedBox(width: 10),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _RoundButton(icon: Icons.notifications_none, onTap: () {}),
                  Positioned(
                    right: 1,
                    top: 1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF15B59),
                        shape: BoxShape.circle,
                      ),
                    ),
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
                dimension: 100,
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
            alignment: Alignment.bottomRight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('مرحبًا بك', style: _homeText(context, 13)),
                Text(
                  'أحمد محمد',
                  style: _homeText(context, 21, weight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'تقبّل الله طاعاتك.. وجعلنا وإياك من أهل القرآن',
                  style: _homeText(context, 10, weight: FontWeight.w500),
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
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: AppPalette.of(context).dark
        ? const Color(0xBB24414D)
        : const Color(0xEEFFFFFF),
    shape: const CircleBorder(),
    child: IconButton(
      onPressed: onTap,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 25, color: AppPalette.of(context).heading),
    ),
  );
}

class PrayerCard extends StatelessWidget {
  const PrayerCard({super.key, this.controller, this.onTap});
  final PrayerController? controller;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller ?? const AlwaysStoppedAnimation(0),
    builder: (context, _) => _content(context),
  );
  Widget _content(BuildContext context) {
    final palette = AppPalette.of(context);
    String time(PrayerName name) =>
        controller?.today?.moments
            .where((m) => m.name == name)
            .firstOrNull
            ?.label ??
        '--:--';
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
                    color: palette.dark
                        ? Colors.white
                        : const Color(0xFF07535D),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الصلاة القادمة',
                        style: _homeText(context, 10, weight: FontWeight.w800),
                      ),
                      Text(
                        controller?.upcoming?.name.label ?? 'حدد الموقع',
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
                        'ساعة   دقيقة   ثانية',
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
                        controller?.hijriLabel ??
                            prayerHijriDate(DateTime.now()),
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
                            color: palette.heading,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              controller?.config.location?.label ??
                                  'الموقع غير محدد',
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
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: selected
                          ? BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF008C96), Color(0xFF00616C)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            )
                          : null,
                      child: Column(
                        children: [
                          Icon(
                            prayer.$3,
                            size: 23,
                            color: prayer.$1 == 'العشاء' ? color : _homeGold,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            prayer.$1,
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
  });
  final VoidCallback? onQuranTap, onMoreTap, onDuasTap;
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
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent:
              (constraints.maxWidth - 30) /
              4 *
              MediaQuery.textScalerOf(context).scale(1),
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final warm = index == 5 || index == 6;
          final background = index == 0
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
          final color = warm
              ? _homeGold
              : index == 0
              ? const Color(0xFFFFF5DD)
              : palette.dark
              ? const Color(0xFFA8D6DD)
              : const Color(0xFF075C69);
          return Material(
            color: background,
            borderRadius: BorderRadius.circular(15),
            child: InkWell(
              onTap: index == 0
                  ? onQuranTap
                  : index == 4
                  ? onMoreTap
                  : index == 5
                  ? onDuasTap
                  : null,
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
                    items[index].$1,
                    maxLines: 1,
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
  Widget build(BuildContext context) => _PhotoCard(
    image: 'assets/home/dawn.png',
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
                  Icon(Icons.wb_sunny_outlined, color: _homeGold, size: 35),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'أذكار الصباح',
                      style: _homeText(context, 18, weight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              Text('ابدأ يومك بذكر الله', style: _homeText(context, 11)),
              const SizedBox(height: 9),
              Text(
                'مجموعة من الأذكار الصحيحة لبدء يومك بالبركة والطمأنينة.',
                style: _homeText(context, 10, weight: FontWeight.w500),
              ),
              const Spacer(),
              _HomeButton(label: 'عرض الأذكار', gold: true, onPressed: onTap),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: Align(
            alignment: Alignment.bottomRight,
            child: _ShareButton(text: 'ابدأ يومك بذكر الله — أذكار الصباح'),
          ),
        ),
      ],
    ),
  );
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
                  'أكمل من حيث توقفت',
                  style: _homeText(context, 14, weight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  surah == null ? 'ابدأ رحلتك مع القرآن' : 'سورة ${surah.name}',
                  style: _homeText(context, 14, weight: FontWeight.w800),
                ),
                Text(
                  verse == null
                      ? 'سيُحفظ موضع قراءتك هنا'
                      : 'الآية ${verse.ayah}',
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
                  color: _homeTeal,
                  backgroundColor: AppPalette.of(context).dark
                      ? const Color(0xFF29404A)
                      : const Color(0xFFE4E1DB),
                ),
                const SizedBox(height: 12),
                _HomeButton(
                  label: 'متابعة القراءة',
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
  const DailyVerseCard({super.key});
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
                  'محتوى اليوم',
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
                    'آية اليوم',
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
                  'سورة الطلاق - الآية 4',
                  style: _homeText(context, 10, color: palette.tealHeading),
                ),
                const SizedBox(height: 9),
                OutlinedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('آية اليوم'),
                      content: const Text(
                        'سورة الطلاق — الآية 4\n\nالتفسير غير متاح حاليًا دون مصدر تفسير معتمد.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('إغلاق'),
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
                    'عرض التفسير',
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
                    child: _ShareButton(text: '$verse\nسورة الطلاق — الآية 4'),
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
    final unavailable = failed ? 'تعذّر التحميل' : '—';
    final items = [
      (
        'العادات',
        c == null ? unavailable : 'اليوم: $done من $goal',
        Icons.spa_outlined,
        'leaf',
        goal == 0 ? 0.0 : done / goal,
      ),
      (
        'الأذكار',
        c == null ? unavailable : '${totals!.adhkar} قراءة اليوم',
        Icons.radio_button_checked,
        'beads',
        adhkarGoal == 0 ? 0.0 : (totals!.adhkar / adhkarGoal).clamp(0.0, 1.0),
      ),
      (
        'الختمة',
        c == null
            ? unavailable
            : active == null
            ? 'لم تبدأ بعد'
            : '${c.readPages(active).length} صفحة',
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
                      color: palette.dark ? const Color(0xFF9ED9DF) : _homeTeal,
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
                        color: _homeTeal,
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
                    color: AppPalette.of(context).heading,
                  ),
                  const SizedBox(width: 8),
                  Text('محتوى خاص', style: _homeText(context, 10)),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                'يوم الجمعة',
                style: _homeText(context, 16, weight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'سورة الكهف . الصلاة على النبي ﷺ',
                style: _homeText(context, 10),
              ),
              const Spacer(),
              _HomeButton(
                label: 'عرض المحتوى',
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
  const ArticlesRow({super.key});
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(
        child: _ArticleCard(
          title: 'فضل صلاة الجماعة',
          image: 'assets/home/header_dark.png',
        ),
      ),
      SizedBox(width: 8),
      Expanded(
        child: _ArticleCard(
          title: 'فضل الصدقة في الإسلام',
          image: 'assets/home/lantern.png',
        ),
      ),
    ],
  );
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.title, required this.image});
  final String title, image;
  @override
  Widget build(BuildContext context) => Container(
    height: 104 * MediaQuery.textScalerOf(context).scale(1),
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
            'مقالة',
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
      height: math.max(
        minimumHeight,
        height * MediaQuery.textScalerOf(context).scale(1),
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
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(image, fit: BoxFit.cover, alignment: imageAlignment),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
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
          Padding(padding: const EdgeInsets.all(13), child: child),
        ],
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
        backgroundColor: gold ? _homeGold : _homeTeal,
        foregroundColor: gold && AppPalette.of(context).dark
            ? AppColors.navy
            : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          if (arrow) ...[
            const SizedBox(width: 10),
            const Icon(
              Icons.chevron_left,
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
      tooltip: 'مشاركة',
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.share_outlined, size: 17, color: AppColors.navy),
      onPressed: () => SharePlus.instance.share(ShareParams(text: text)),
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
