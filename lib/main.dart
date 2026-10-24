import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_appearance.dart';
import 'settings_pages.dart';
import 'features/quran/data/quran_controller.dart';
import 'features/quran/presentation/quran_host.dart';
import 'features/religious_content/data/religious_controller.dart';
import 'features/religious_content/presentation/religious_host.dart';
import 'startup/startup_flow.dart';

import 'navigation/app_section.dart';
import 'navigation/feature_routes.dart';
import 'navigation/more_page.dart';
import 'navigation/section_entry_page.dart';

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
    this.religiousController,
    this.showStartup = true,
  });
  final AppAppearance? appearance;
  final QuranController? quranController;
  final ReligiousController? religiousController;
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
                    religiousController: widget.religiousController,
                  ),
                )
              : HomePage(
                  onToggleTheme: _toggleTheme,
                  quranController: widget.quranController,
                  religiousController: widget.religiousController,
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
    this.religiousController,
  });

  final VoidCallback onToggleTheme;
  final QuranController? quranController;
  final ReligiousController? religiousController;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppSection _section = AppSection.home;
  final _visited = <AppSection>{AppSection.home, AppSection.quran};
  bool _quranFullscreen = false;
  late final QuranController _quran;
  final _quranKey = GlobalKey<QuranHostState>();
  final _religiousKey = GlobalKey<ReligiousHostState>();
  final _adhkarKey = GlobalKey<AdhkarSectionPageState>();
  late final ReligiousController _religious;
  bool _religiousOpen = false;
  String? _religiousInitialCategory;

  @override
  void initState() {
    super.initState();
    _quran = widget.quranController ?? QuranController();
    _religious =
        widget.religiousController ?? ReligiousController(quran: _quran);
    if (_quran.repository == null) {
      _quran.load().then((_) {
        if (mounted && _religious.catalog == null) _religious.load();
      });
    } else if (_religious.catalog == null) {
      _religious.load();
    }
  }

  @override
  void dispose() {
    if (widget.religiousController == null) _religious.dispose();
    if (widget.quranController == null) _quran.dispose();
    super.dispose();
  }

  void _selectSection(AppSection section) => setState(() {
    _section = section;
    _visited.add(section);
  });

  void _openQuran({bool resume = false}) {
    _selectSection(AppSection.quran);
    if (resume) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _quranKey.currentState?.openLastReading();
      });
    }
  }

  void _openReligious([String? category]) {
    if (_religiousOpen &&
        _religiousKey.currentState != null &&
        category != null) {
      _religiousKey.currentState!.openCategory(category);
    }
    setState(() {
      _religiousInitialCategory = category;
      _religiousOpen = true;
      _section = AppSection.more;
      _visited.add(AppSection.more);
    });
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

  void _openFeature(AppFeature feature) {
    switch (feature) {
      case AppFeature.quran:
        _openQuran();
      case AppFeature.adhkar:
        _selectSection(AppSection.adhkar);
      case AppFeature.personalAdhkar when _section != AppSection.adhkar:
        _selectSection(AppSection.adhkar);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _adhkarKey.currentState?.openPersonal();
        });
      case AppFeature.qibla:
        _selectSection(AppSection.qibla);
      case AppFeature.settings:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsPage(
              onQuranSettings: () {
                Navigator.of(context).pop();
                _openQuranSettings();
              },
              onQuranAccount: () {
                Navigator.of(context).pop();
                _openQuranAccount();
              },
              onQuranDownloads: () {
                Navigator.of(context).pop();
                _openQuranDownloads();
              },
            ),
          ),
        );
      case AppFeature.appearance:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const SettingsDetailPage(kind: SettingKind.appearance),
          ),
        );
      default:
        if (feature.category != null ||
            feature == AppFeature.religiousLibrary) {
          if (_section == AppSection.adhkar) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: RouteSettings(name: feature.routeName),
                builder: (routeContext) => Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                    body: ReligiousHost(
                      controller: _religious,
                      initialCategory: feature.category,
                      initialCategoryAsRoot: true,
                      onClose: () => Navigator.of(routeContext).pop(),
                    ),
                  ),
                ),
              ),
            );
          } else {
            _openReligious(feature.category);
          }
        } else {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              settings: RouteSettings(name: feature.routeName),
              builder: (_) => FeaturePreparationPage(feature: feature),
            ),
          );
        }
    }
  }

  Widget _buildHome() => CustomScrollView(
    key: const PageStorageKey('home-feed'),
    slivers: [
      SliverToBoxAdapter(child: _HeroHeader()),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 116),
        sliver: SliverList(
          delegate: SliverChildListDelegate.fixed([
            PrayerCard(),
            SizedBox(height: 14),
            QuickServices(
              onDuasTap: () => _openReligious(),
              onQuranTap: () => _openQuran(),
              onMoreTap: () => _selectSection(AppSection.more),
            ),
            SizedBox(height: 18),
            DhikrCard(onTap: () => _selectSection(AppSection.adhkar)),
            SizedBox(height: 14),
            ReadingCard(
              controller: _quran,
              onContinue: () => _openQuran(resume: true),
            ),
            SizedBox(height: 14),
            DailyVerseCard(),
            SizedBox(height: 20),
            SectionHeader(title: 'رحلتك اليوم', action: 'عرض الكل'),
            SizedBox(height: 10),
            JourneyCards(),
            SizedBox(height: 20),
            FridayCard(onTap: () => _openReligious('friday')),
            SizedBox(height: 20),
            SectionHeader(title: 'مقالات ومعلومات', action: 'عرض الكل'),
            SizedBox(height: 10),
            ArticlesRow(),
          ]),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final religiousHandlesBack = _section == AppSection.more && _religiousOpen;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope<Object?>(
        canPop:
            _section == AppSection.home ||
            _section == AppSection.quran ||
            _section == AppSection.adhkar ||
            religiousHandlesBack,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop &&
              !religiousHandlesBack &&
              _section != AppSection.quran &&
              _section != AppSection.adhkar &&
              _section != AppSection.home) {
            _selectSection(AppSection.home);
          }
        },
        child: Scaffold(
          body: IndexedStack(
            index: _section.index,
            children: [
              _buildHome(),
              TickerMode(
                enabled: _section == AppSection.quran,
                child: QuranHost(
                  key: _quranKey,
                  controller: _quran,
                  active: _section == AppSection.quran,
                  onExit: () => _selectSection(AppSection.home),
                  onFullscreenChanged: (value) {
                    if (mounted && value != _quranFullscreen) {
                      setState(() => _quranFullscreen = value);
                    }
                  },
                ),
              ),
              _visited.contains(AppSection.adhkar)
                  ? AdhkarSectionPage(
                      key: _adhkarKey,
                      controller: _religious,
                      onFeature: _openFeature,
                      active: _section == AppSection.adhkar,
                      onExit: () => _selectSection(AppSection.home),
                    )
                  : const SizedBox.shrink(),
              _visited.contains(AppSection.qibla)
                  ? const FeaturePreparationPage(
                      feature: AppFeature.qibla,
                      embedded: true,
                    )
                  : const SizedBox.shrink(),
              !_visited.contains(AppSection.more)
                  ? const SizedBox.shrink()
                  : _religiousOpen
                  ? ReligiousHost(
                      key: _religiousKey,
                      controller: _religious,
                      active: _section == AppSection.more,
                      initialCategory: _religiousInitialCategory,
                      onClose: () => setState(() => _religiousOpen = false),
                    )
                  : MorePage(onFeature: _openFeature),
            ],
          ),
          extendBody: true,
          bottomNavigationBar: _quranFullscreen && _section == AppSection.quran
              ? null
              : religiousHandlesBack
              ? ReligiousNavigationBar(
                  onSelected: (index) {
                    setState(() {
                      _section = AppSection.values[index];
                      _visited.add(_section);
                      if (_section == AppSection.more) _religiousOpen = false;
                    });
                  },
                )
              : ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                  child: NavigationBar(
                    selectedIndex: _section.index,
                    height: 72,
                    backgroundColor: dark
                        ? const Color(0xF2132331)
                        : const Color(0xF9FFFFFF),
                    indicatorColor: Colors.transparent,
                    onDestinationSelected: (index) =>
                        _selectSection(AppSection.values[index]),
                    destinations: [
                      for (final section in AppSection.values)
                        NavigationDestination(
                          icon: Icon(section.icon),
                          selectedIcon: Icon(section.selectedIcon),
                          label: section.label,
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
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
