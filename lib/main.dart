import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_appearance.dart';
import 'settings_pages.dart';
import 'features/quran/data/quran_controller.dart';
import 'features/quran/presentation/quran_host.dart';
import 'startup/startup_flow.dart';

part 'home_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(HaqApp(appearance: AppAppearance(preferences)));
}

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
  const HaqApp({
    super.key,
    this.appearance,
    this.quranController,
    this.showStartup = true,
  });
  final AppAppearance? appearance;
  final QuranController? quranController;
  final bool showStartup;

  @override
  State<HaqApp> createState() => _HaqAppState();
}

class _HaqAppState extends State<HaqApp> {
  AppAppearance? _appearance;

  @override
  void initState() {
    super.initState();
    if (widget.appearance != null) {
      _appearance = widget.appearance;
    } else {
      SharedPreferences.getInstance().then((preferences) {
        if (mounted) setState(() => _appearance = AppAppearance(preferences));
      });
    }
  }

  void _toggleTheme() {
    final appearance = _appearance!;
    appearance.setMode(
      appearance.mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }

  @override
  void dispose() {
    if (widget.appearance == null) _appearance?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appearance = _appearance;
    if (appearance == null) return SizedBox.shrink();
    return AppearanceScope(
      controller: appearance,
      child: ListenableBuilder(
        listenable: appearance,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'حق',
          themeMode: appearance.mode,
          locale: Locale('ar'),
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                MediaQuery.textScalerOf(context).scale(1) *
                    appearance.fontScale,
              ),
            ),
            child: child!,
          ),
          home: widget.showStartup
              ? StartupFlow(
                  preferences: appearance.preferences,
                  child: HomePage(
                    onToggleTheme: _toggleTheme,
                    quranController: widget.quranController,
                  ),
                )
              : HomePage(
                  onToggleTheme: _toggleTheme,
                  quranController: widget.quranController,
                ),
        ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.teal,
      brightness: brightness,
      primary: AppColors.teal,
      secondary: AppColors.gold,
      surface: isDark ? Color(0xFF132331) : Color(0xFFFFFCF7),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? Color(0xFF081722) : Color(0xFFFFFCF7),
      fontFamily: _appearance!.font.family,
      navigationBarTheme: NavigationBarThemeData(
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 26,
            color: states.contains(WidgetState.selected)
                ? _homeTeal
                : isDark
                ? const Color(0xFFB8DFE5)
                : AppColors.navy,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: _appearance!.font.family,
            fontSize: 10,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? _homeTeal
                : isDark
                ? const Color(0xFFC6D6DE)
                : const Color(0xFF71869A),
          ),
        ),
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        fontFamily: _appearance!.font.family,
        bodyColor: isDark ? Color(0xFFF1F5F9) : AppColors.text,
        displayColor: isDark ? Color(0xFFF1F5F9) : AppColors.navy,
      ),
      cardTheme: CardThemeData(
        color: isDark ? Color(0xFF132331) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.onToggleTheme,
    this.quranController,
  });

  final VoidCallback onToggleTheme;
  final QuranController? quranController;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  bool _quranFullscreen = false;
  late final QuranController _quran;
  final _quranKey = GlobalKey<QuranHostState>();

  @override
  void initState() {
    super.initState();
    _quran = widget.quranController ?? QuranController();
    if (_quran.repository == null) _quran.load();
  }

  @override
  void dispose() {
    if (widget.quranController == null) _quran.dispose();
    super.dispose();
  }

  void _openQuran({bool resume = false}) {
    setState(() => _currentIndex = 1);
    if (resume) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _quranKey.currentState?.openLastReading();
      });
    }
  }

  void _openQuranSettings() {
    _openQuran();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _quranKey.currentState?.openSettings();
    });
  }

  void _openQuranAccount() {
    _openQuran();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _quranKey.currentState?.openAccount();
    });
  }

  void _openQuranDownloads() {
    _openQuran();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _quranKey.currentState?.openDownloads();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex == 1 ? 1 : 0,
          children: [
            _currentIndex == 4
                ? MorePage(
                    onQuranTap: () => _openQuran(),
                    onQuranSettings: _openQuranSettings,
                    onQuranAccount: _openQuranAccount,
                    onQuranDownloads: _openQuranDownloads,
                  )
                : CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _HeroHeader()),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(16, 14, 16, 116),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate.fixed([
                            PrayerCard(),
                            SizedBox(height: 14),
                            QuickServices(
                              onQuranTap: () => _openQuran(),
                              onMoreTap: () =>
                                  setState(() => _currentIndex = 4),
                            ),
                            SizedBox(height: 18),
                            DhikrCard(),
                            SizedBox(height: 14),
                            ReadingCard(
                              controller: _quran,
                              onContinue: () => _openQuran(resume: true),
                            ),
                            SizedBox(height: 14),
                            DailyVerseCard(),
                            SizedBox(height: 20),
                            SectionHeader(
                              title: 'رحلتك اليوم',
                              action: 'عرض الكل',
                            ),
                            SizedBox(height: 10),
                            JourneyCards(),
                            SizedBox(height: 20),
                            FridayCard(),
                            SizedBox(height: 20),
                            SectionHeader(
                              title: 'مقالات ومعلومات',
                              action: 'عرض الكل',
                            ),
                            SizedBox(height: 10),
                            ArticlesRow(),
                          ]),
                        ),
                      ),
                    ],
                  ),
            TickerMode(
              enabled: _currentIndex == 1,
              child: QuranHost(
                key: _quranKey,
                controller: _quran,
                active: _currentIndex == 1,
                onFullscreenChanged: (value) {
                  if (mounted && value != _quranFullscreen) {
                    setState(() => _quranFullscreen = value);
                  }
                },
              ),
            ),
          ],
        ),
        extendBody: true,
        bottomNavigationBar: _quranFullscreen
            ? null
            : ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                child: NavigationBar(
                  selectedIndex: _currentIndex,
                  height: 72,
                  backgroundColor: dark ? Color(0xF2132331) : Color(0xF9FFFFFF),
                  indicatorColor: Colors.transparent,
                  onDestinationSelected: (value) =>
                      setState(() => _currentIndex = value),
                  destinations: [
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
      ),
    );
  }
}

class MorePage extends StatelessWidget {
  const MorePage({
    super.key,
    this.onQuranTap,
    this.onQuranSettings,
    this.onQuranAccount,
    this.onQuranDownloads,
  });
  final VoidCallback? onQuranTap;
  final VoidCallback? onQuranSettings;
  final VoidCallback? onQuranAccount, onQuranDownloads;

  static const _items = [
    ('ادعُ معي', Icons.people_alt_outlined),
    ('حلقات الذكر', Icons.auto_awesome_outlined),
    ('الإعدادات', Icons.settings_outlined),
    ('المسبحة الإلكترونية', Icons.mosque_outlined),
    ('أسماء الله الحسنى', Icons.brightness_7_outlined),
    ('بماذا تشعر؟', Icons.emoji_emotions_outlined),
    ('أذكار المسلم', Icons.volunteer_activism_outlined),
    ('إحصائيات', Icons.query_stats_outlined),
    ('أذكاري', Icons.edit_note_outlined),
    ('قرآن', Icons.menu_book_outlined),
    ('بوصلة القبلة', Icons.explore_outlined),
    ('متعقب العادة', Icons.fact_check_outlined),
    ('الرقية الشرعية', Icons.health_and_safety_outlined),
    ('استغفار', Icons.self_improvement_outlined),
    ('الحمد', Icons.front_hand_outlined),
    ('تسبيح', Icons.radio_button_checked),
    ('الأربعون النووية', Icons.book_outlined),
    ('أدعية الأنبياء', Icons.self_improvement_outlined),
    ('أدعية نبوية', Icons.volunteer_activism_outlined),
    ('أدعية قرآنية', Icons.auto_stories_outlined),
    ('ختمة', Icons.menu_book_rounded),
    ('سنن الجمعة', Icons.groups_outlined),
    ('رمضان', Icons.nightlight_outlined),
    ('سنن النبي ﷺ', Icons.import_contacts_outlined),
    ('مظهر التطبيق', Icons.palette_outlined),
    ('سكينة', Icons.air_outlined),
    ('الأحاديث النبوية', Icons.menu_book_outlined),
    ('أقرب المساجد', Icons.mosque_outlined),
    ('تطبيقاتنا', Icons.account_balance_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            height: 265,
            padding: EdgeInsets.fromLTRB(
              18,
              MediaQuery.paddingOf(context).top + 12,
              18,
              18,
            ),
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/home_header.png'),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                colorFilter: dark
                    ? ColorFilter.mode(Color(0xB3102A43), BlendMode.darken)
                    : null,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            child: Column(
              children: [
                Image.asset(
                  'assets/branding/haq_logo_transparent.png',
                  color: dark ? AppPalette.of(context).heading : null,
                  width: 90,
                  height: 90,
                ),
                SizedBox(height: 5),
                Text(
                  'المزيد',
                  style: TextStyle(
                    color: AppPalette.of(context).heading,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'كل ما تحتاجه في مكان واحد',
                  style: TextStyle(
                    color: AppPalette.of(context).heading,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 24),
          sliver: SliverGrid.builder(
            itemCount: _items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 18,
              crossAxisSpacing: 10,
              childAspectRatio: .72,
            ),
            itemBuilder: (context, index) {
              final item = _items[index];
              return _MoreItem(
                title: item.$1,
                icon: item.$2,
                onTap: item.$1 == 'الإعدادات'
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SettingsPage(
                            onQuranAccount: onQuranAccount == null
                                ? null
                                : () {
                                    Navigator.of(context).pop();
                                    onQuranAccount?.call();
                                  },
                            onQuranDownloads: onQuranDownloads == null
                                ? null
                                : () {
                                    Navigator.of(context).pop();
                                    onQuranDownloads?.call();
                                  },
                            onQuranSettings: () {
                              Navigator.of(context).pop();
                              onQuranSettings?.call();
                            },
                          ),
                        ),
                      )
                    : item.$1 == 'مظهر التطبيق'
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsDetailPage(
                            kind: SettingKind.appearance,
                          ),
                        ),
                      )
                    : item.$1 == 'قرآن'
                    ? onQuranTap
                    : null,
              );
            },
          ),
        ),
        SliverToBoxAdapter(child: _MoreSocialLinks()),
        SliverToBoxAdapter(child: SizedBox(height: 108)),
      ],
    );
  }
}

class _MoreItem extends StatelessWidget {
  const _MoreItem({required this.title, required this.icon, this.onTap});
  final String title;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.deepTeal,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 34),
        ),
        SizedBox(height: 8),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppPalette.of(context).heading,
            fontSize: 12,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _MoreSocialLinks extends StatelessWidget {
  const _MoreSocialLinks();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(24, 6, 24, 18),
    child: Column(
      children: [
        Divider(color: AppPalette.of(context).border),
        SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Icon(
              Icons.edit_outlined,
              color: AppPalette.of(context).heading,
              size: 30,
            ),
            Icon(
              Icons.share_outlined,
              color: AppPalette.of(context).heading,
              size: 30,
            ),
            Icon(
              Icons.play_circle_outline,
              color: AppPalette.of(context).heading,
              size: 34,
            ),
            Icon(
              Icons.camera_alt_outlined,
              color: AppPalette.of(context).heading,
              size: 31,
            ),
            Text(
              'f',
              style: TextStyle(
                color: AppPalette.of(context).heading,
                fontSize: 34,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
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
        Text(
          'تواصل معنا',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 5),
        Text(
          'تابع حسابات حق وشارك الخير مع من تحب',
          style: TextStyle(color: AppPalette.of(context).muted, fontSize: 13),
        ),
        SizedBox(height: 14),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            color: dark ? Color(0xFF132331) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: dark ? Colors.white10 : Color(0xFFE8EDF0),
            ),
          ),
          child: Row(
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
        SizedBox(height: 12),
        Material(
          color: AppColors.teal,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: null,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
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
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                data: IconThemeData(color: AppColors.teal),
                child: DefaultTextStyle(
                  style: TextStyle(color: AppColors.teal),
                  child: child,
                ),
              ),
            ),
            SizedBox(height: 7),
            Text(label, style: TextStyle(fontSize: 11)),
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
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
      ),
      Text(
        action,
        style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700),
      ),
      Icon(
        Icons.chevron_left,
        color: AppColors.teal,
        textDirection: TextDirection.ltr,
      ),
    ],
  );
}
