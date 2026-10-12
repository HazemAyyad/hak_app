import 'package:flutter/material.dart';

void main() => runApp(const HaqApp());

class AppColors {
  static const navy = Color(0xFF102A43);
  static const teal = Color(0xFF2A8C82);
  static const deepTeal = Color(0xFF08675F);
  static const gold = Color(0xFFC7A45A);
  static const ivory = Color(0xFFF7F2E0);
  static const text = Color(0xFF1B2530);
  static const muted = Color(0xFF6B7280);
}

class HaqApp extends StatefulWidget {
  const HaqApp({super.key});

  @override
  State<HaqApp> createState() => _HaqAppState();
}

class _HaqAppState extends State<HaqApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'حق',
      themeMode: _themeMode,
      locale: const Locale('ar'),
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: HomePage(onToggleTheme: _toggleTheme),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.teal,
      brightness: brightness,
      primary: AppColors.teal,
      secondary: AppColors.gold,
      surface: isDark ? const Color(0xFF132331) : const Color(0xFFFFFCF7),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF081722)
          : const Color(0xFFFFFCF7),
      fontFamily: 'Arial',
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: isDark ? const Color(0xFFF1F5F9) : AppColors.text,
        displayColor: isDark ? const Color(0xFFF1F5F9) : AppColors.navy,
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF132331) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onToggleTheme});

  final VoidCallback onToggleTheme;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _HeroHeader()),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 116),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  PrayerCard(),
                  SizedBox(height: 14),
                  QuickServices(),
                  SizedBox(height: 18),
                  DhikrCard(),
                  SizedBox(height: 14),
                  ReadingCard(),
                  SizedBox(height: 14),
                  DailyVerseCard(),
                  SizedBox(height: 20),
                  SectionHeader(title: 'رحلتك اليوم', action: 'عرض الكل'),
                  SizedBox(height: 10),
                  JourneyCards(),
                  SizedBox(height: 20),
                  FridayCard(),
                  SizedBox(height: 20),
                  SectionHeader(title: 'مقالات ومعلومات', action: 'عرض الكل'),
                  SizedBox(height: 10),
                  ArticlesRow(),
                  SizedBox(height: 24),
                  SocialMediaSection(),
                ]),
              ),
            ),
          ],
        ),
        extendBody: true,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          height: 72,
          backgroundColor: dark
              ? const Color(0xF2132331)
              : const Color(0xF9FFFFFF),
          indicatorColor: AppColors.teal.withValues(alpha: .16),
          onDestinationSelected: (value) =>
              setState(() => _currentIndex = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'الرئيسية',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'القرآن',
            ),
            NavigationDestination(
              icon: Icon(Icons.eco_outlined),
              selectedIcon: Icon(Icons.eco),
              label: 'الأذكار',
            ),
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'القبلة',
            ),
            NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: 'المزيد',
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        18,
        MediaQuery.paddingOf(context).top + 12,
        18,
        28,
      ),
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/home_header.png'),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _RoundButton(icon: Icons.person_outline, onTap: () {}),
              const Spacer(),
              _RoundButton(icon: Icons.search, onTap: () {}),
              const SizedBox(width: 8),
              _RoundButton(icon: Icons.notifications_none, onTap: () {}),
            ],
          ),
          const SizedBox(height: 10),
          Image.asset(
            'assets/branding/haq_logo_transparent.png',
            width: 92,
            height: 92,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 10),
          const Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مرحبًا بك',
                  style: TextStyle(color: AppColors.navy, fontSize: 14),
                ),
                Text(
                  'أحمد محمد',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'تقبّل الله طاعاتك، وجعلنا وإياك من أهل القرآن',
                  style: TextStyle(color: AppColors.navy, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .90),
    shape: const CircleBorder(),
    child: IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: AppColors.navy),
    ),
  );
}

class PrayerCard extends StatelessWidget {
  const PrayerCard({super.key});
  @override
  Widget build(BuildContext context) {
    const prayers = [
      ('الفجر', '04:32', Icons.wb_twilight),
      ('الظهر', '12:07', Icons.light_mode),
      ('العصر', '15:34', Icons.wb_sunny_outlined),
      ('المغرب', '18:21', Icons.wb_twilight),
      ('العشاء', '19:45', Icons.dark_mode),
    ];
    return _Surface(
      child: Column(
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Color(0x142A8C82),
                child: Icon(Icons.mosque, color: AppColors.teal, size: 30),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الصلاة القادمة',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'الظهر',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '02:35:42',
                    style: TextStyle(
                      fontSize: 24,
                      color: AppColors.gold,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'نابلس، فلسطين',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: prayers
                .map(
                  (p) => Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: p.$1 == 'الظهر'
                          ? BoxDecoration(
                              color: AppColors.teal,
                              borderRadius: BorderRadius.circular(14),
                            )
                          : null,
                      child: Column(
                        children: [
                          Icon(
                            p.$3,
                            size: 20,
                            color: p.$1 == 'الظهر'
                                ? Colors.white
                                : AppColors.gold,
                          ),
                          Text(
                            p.$1,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: p.$1 == 'الظهر' ? Colors.white : null,
                            ),
                          ),
                          Text(
                            p.$2,
                            style: TextStyle(
                              fontSize: 12,
                              color: p.$1 == 'الظهر'
                                  ? Colors.white70
                                  : AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class QuickServices extends StatelessWidget {
  const QuickServices({super.key});
  @override
  Widget build(BuildContext context) {
    const items = [
      ('القرآن الكريم', Icons.menu_book),
      ('الأذكار اليومية', Icons.eco),
      ('الختمة', Icons.auto_stories),
      ('العداد والتسبيح', Icons.radio_button_checked),
      ('الأدعية', Icons.volunteer_activism),
      ('ماذا تشعر؟', Icons.favorite),
      ('القبلة', Icons.explore),
      ('المزيد', Icons.grid_view_rounded),
    ];
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: .92,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => Container(
        decoration: BoxDecoration(
          color: index == 0
              ? AppColors.navy
              : AppColors.teal.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              items[index].$2,
              color: index == 0 ? Colors.white : AppColors.teal,
              size: 28,
            ),
            const SizedBox(height: 7),
            Text(
              items[index].$1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: index == 0 ? Colors.white : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DhikrCard extends StatelessWidget {
  const DhikrCard({super.key});
  @override
  Widget build(BuildContext context) => _PhotoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Row(
          children: [
            Icon(Icons.wb_sunny_outlined, color: AppColors.gold, size: 34),
            Spacer(),
            Text(
              'أذكار الصباح',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const Text(
          'ابدأ يومك بذكر الله',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        const Text(
          'مجموعة من الأذكار الصحيحة لبدء يومك\nبالبركة والطمأنينة.',
          textAlign: TextAlign.right,
          style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
        ),
        const Spacer(),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: AppColors.navy,
          ),
          onPressed: () {},
          child: const Text('عرض الأذكار'),
        ),
      ],
    ),
  );
}

class ReadingCard extends StatelessWidget {
  const ReadingCard({super.key});
  @override
  Widget build(BuildContext context) => _PhotoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            CircleAvatar(
              backgroundColor: Color(0xDDFFFFFF),
              child: Icon(Icons.menu_book, color: AppColors.teal),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'أكمل من حيث توقفت',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'سورة البقرة • الآية 255',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const LinearProgressIndicator(
          value: .38,
          minHeight: 7,
          borderRadius: BorderRadius.all(Radius.circular(8)),
          color: AppColors.teal,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () {},
            icon: Icon(Icons.arrow_back_ios_new, size: 14),
            label: Text('متابعة القراءة'),
          ),
        ),
      ],
    ),
  );
}

class DailyVerseCard extends StatelessWidget {
  const DailyVerseCard({super.key});
  @override
  Widget build(BuildContext context) => _Surface(
    color: AppColors.gold.withValues(alpha: .10),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, color: AppColors.gold),
            SizedBox(width: 8),
            Text(
              'آية اليوم',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.gold,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Text(
          '﴿ وَمَن يَتَّقِ اللَّهَ يَجْعَل لَّهُ مَخْرَجًا ﴾',
          style: TextStyle(
            fontSize: 19,
            height: 1.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          'سورة الطلاق • الآية 2',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    ),
  );
}

class JourneyCards extends StatelessWidget {
  const JourneyCards({super.key});
  @override
  Widget build(BuildContext context) {
    const items = [
      ('الختمة', 'الجزء الثاني', Icons.menu_book, .18),
      ('الأذكار', 'أذكار الصباح', Icons.radio_button_checked, .62),
      ('العادات', 'تم اليوم', Icons.eco, .84),
    ];
    return Row(
      children: items
          .map(
            (item) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _Surface(
                  child: Column(
                    children: [
                      Icon(item.$3, color: AppColors.teal),
                      const SizedBox(height: 7),
                      Text(
                        item.$1,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        item.$2,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 9),
                      LinearProgressIndicator(
                        value: item.$4,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(6),
                        color: AppColors.teal,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class FridayCard extends StatelessWidget {
  const FridayCard({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      image: const DecorationImage(
        image: AssetImage('assets/images/mosque_sunrise.png'),
        fit: BoxFit.cover,
        colorFilter: ColorFilter.mode(Color(0xAA0A5260), BlendMode.darken),
      ),
      borderRadius: BorderRadius.circular(22),
    ),
    child: const Row(
      children: [
        Icon(Icons.mosque, size: 48, color: AppColors.gold),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('محتوى خاص', style: TextStyle(color: Colors.white60)),
              Text(
                'يوم الجمعة',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 21,
                ),
              ),
              Text(
                'سورة الكهف • الصلاة على النبي ﷺ',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        Icon(Icons.arrow_back_ios_new, color: Colors.white),
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
          icon: Icons.groups_rounded,
        ),
      ),
      SizedBox(width: 10),
      Expanded(
        child: _ArticleCard(
          title: 'فضل الصدقة في الإسلام',
          icon: Icons.volunteer_activism,
        ),
      ),
    ],
  );
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.title, required this.icon});
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    height: 112,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      image: const DecorationImage(
        image: AssetImage('assets/images/mosque_sunrise.png'),
        fit: BoxFit.cover,
        colorFilter: ColorFilter.mode(Color(0xAA102A43), BlendMode.darken),
      ),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(icon, color: AppColors.gold),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class SocialMediaSection extends StatelessWidget {
  const SocialMediaSection({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'تواصل معنا',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        const Text(
          'تابع حسابات حق وشارك الخير مع من تحب',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF132331) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: dark ? Colors.white10 : const Color(0xFFE8EDF0),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SocialButton(
                label: 'فيسبوك',
                child: Text(
                  'f',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                ),
              ),
              _SocialButton(
                label: 'إنستغرام',
                child: Icon(Icons.camera_alt_outlined, size: 29),
              ),
              _SocialButton(
                label: 'يوتيوب',
                child: Icon(Icons.play_arrow_rounded, size: 34),
              ),
              _SocialButton(
                label: 'مشاركة',
                child: Icon(Icons.share_outlined, size: 28),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: AppColors.teal,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: null,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 17),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Color(0x22FFFFFF),
                    child: Icon(Icons.verified_outlined, color: Colors.white),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'شارك تطبيق حق',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'ساهم في نشر الخير',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        'مشاركة',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.teal.withValues(alpha: .11),
                shape: BoxShape.circle,
              ),
              child: IconTheme(
                data: const IconThemeData(color: AppColors.teal),
                child: DefaultTextStyle(
                  style: const TextStyle(color: AppColors.teal),
                  child: child,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, required this.action});
  final String title;
  final String action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
      ),
      Text(
        action,
        style: const TextStyle(
          color: AppColors.teal,
          fontWeight: FontWeight.w700,
        ),
      ),
      const Icon(Icons.chevron_left, color: AppColors.teal),
    ],
  );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.color});
  final Widget child;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? (dark ? const Color(0xFF132331) : Colors.white),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: dark ? Colors.white10 : const Color(0xFFE8EDF0),
        ),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: .05),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: child,
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    height: 180,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      image: const DecorationImage(
        image: AssetImage('assets/images/mosque_sunrise.png'),
        fit: BoxFit.cover,
        colorFilter: ColorFilter.mode(Color(0x8A102A43), BlendMode.darken),
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppColors.gold),
    ),
    child: child,
  );
}
