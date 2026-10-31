import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'features/sharing/share_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_appearance.dart';
import 'app_experience.dart';
import 'app_refresh.dart';
import 'settings_pages.dart';
import 'features/quran/data/quran_controller.dart';
import 'features/quran/data/quran_sync.dart' show QuranAccount;
import 'features/quran/data/quran_repository.dart';
import 'features/religious_content/data/religious_catalog.dart';
import 'features/quran/presentation/quran_host.dart';
import 'features/religious_content/data/religious_controller.dart';
import 'features/religious_content/presentation/religious_host.dart';
import 'features/tasbih/presentation/tasbih_page.dart';
import 'features/progress/presentation/progress_page.dart';
import 'features/progress/presentation/progress_summary.dart';
import 'features/progress/data/progress_controller.dart';
import 'features/sakinah/presentation/sakinah_page.dart';
import 'features/adhkar/data/adhkar_repository.dart';
import 'features/settings/data/reminder_controller.dart';
import 'features/prayer/data/prayer_controller.dart';
import 'features/prayer/data/prayer_models.dart';
import 'features/prayer/presentation/prayer_page.dart';
import 'features/account/presentation/account_hub.dart';
import 'features/account/data/app_session.dart';
import 'features/admin/presentation/admin_page.dart';
import 'core/localization/app_localization.dart';
import 'core/localization/interface_messages.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'features/community/data/community_controller.dart';
import 'features/community/data/public_push.dart';
import 'features/community/presentation/community_page.dart';
import 'features/assistant/data/assistant_controller.dart';
import 'features/assistant/presentation/assistant_page.dart';
import 'startup/startup_flow.dart';

import 'navigation/app_section.dart';
import 'navigation/app_bottom_navigation.dart';
import 'navigation/feature_routes.dart';
import 'navigation/more_page.dart';
import 'navigation/section_entry_page.dart';

part 'home_widgets.dart';
part 'home_search.dart';

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
    this.appSessionFactory,
  });
  final AppAppearance? appearance;
  final QuranController? quranController;
  final ReligiousController? religiousController;
  final bool showStartup;
  final AppSession Function(QuranAccount)? appSessionFactory;

  @override
  State<HaqApp> createState() => _HaqAppState();
}

class _HaqAppState extends State<HaqApp> {
  AppAppearance? _appearance;
  AppLocalization? _localization;
  final _experience = AppExperienceController();
  late final _navigationObserver = _experience.observer('root');

  @override
  void initState() {
    super.initState();
    if (widget.appearance != null) {
      _appearance = widget.appearance;
      unawaited(_loadLocalization(_appearance!.preferences));
    } else {
      SharedPreferences.getInstance().then((preferences) {
        if (mounted) {
          setState(() => _appearance = AppAppearance(preferences));
          unawaited(_loadLocalization(preferences));
        }
      });
    }
  }

  Future<void> _loadLocalization(SharedPreferences preferences) async {
    final localization = AppLocalization(preferences);
    _localization = localization;
    await localization.initialize();
  }

  void _toggleTheme() {
    final appearance = _appearance!;
    appearance.setMode(
      appearance.effectiveMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark,
    );
  }

  @override
  void dispose() {
    _experience.dispose();
    _localization?.dispose();
    if (widget.appearance == null) _appearance?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appearance = _appearance;
    final localization = _localization;
    if (appearance == null || localization == null) return SizedBox.shrink();
    return LocalizationScope(
      controller: localization,
      child: AppearanceScope(
        controller: appearance,
        child: ListenableBuilder(
          listenable: Listenable.merge([appearance, localization]),
          builder: (context, _) => MaterialApp(
            navigatorKey: _experience.navigatorKey,
            navigatorObservers: [_navigationObserver, prayerRoutes],
            debugShowCheckedModeBanner: false,
            title: 'حق',
            themeMode: appearance.effectiveMode,
            locale: localization.language.locale,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: localization.languages
                .where(
                  (language) =>
                      GlobalMaterialLocalizations.delegate.isSupported(
                        language.locale,
                      ) &&
                      GlobalCupertinoLocalizations.delegate.isSupported(
                        language.locale,
                      ),
                )
                .map((language) => language.locale)
                .toList(),
            theme: _theme(Brightness.light),
            darkTheme: _theme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  MediaQuery.textScalerOf(context).scale(1) *
                      appearance.fontScale,
                ),
              ),
              child: AppRefreshHost(
                onRefresh: () =>
                    _experience.refreshCurrent?.call() ?? Future<void>.value(),
                child: AppExperienceOverlay(
                  controller: _experience,
                  child: child!,
                ),
              ),
            ),
            home: widget.showStartup
                ? StartupFlow(
                    preferences: appearance.preferences,
                    child: HomePage(
                      onToggleTheme: _toggleTheme,
                      quranController: widget.quranController,
                      religiousController: widget.religiousController,
                      appSessionFactory: widget.appSessionFactory,
                    ),
                  )
                : HomePage(
                    onToggleTheme: _toggleTheme,
                    quranController: widget.quranController,
                    religiousController: widget.religiousController,
                    appSessionFactory: widget.appSessionFactory,
                  ),
          ),
        ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final accent = AppAccent(_appearance!.color, brightness);
    final scheme = ColorScheme.fromSeed(
      seedColor: _appearance!.color.seed,
      brightness: brightness,
      primary: accent.original ? AppColors.teal : accent.primary,
      onPrimary: accent.original
          ? null
          : isDark
          ? AppColors.navy
          : Colors.white,
      secondary: AppColors.gold,
      surface: isDark ? Color(0xFF132331) : Color(0xFFFFFCF7),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [accent],
      scaffoldBackgroundColor: isDark ? Color(0xFF081722) : Color(0xFFFFFCF7),
      fontFamily: _appearance!.font.family,
      navigationBarTheme: NavigationBarThemeData(
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 26,
            color: states.contains(WidgetState.selected)
                ? (accent.original ? _homeTeal : accent.primary)
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
                ? (accent.original ? _homeTeal : accent.primary)
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
    this.appSessionFactory,
  });

  final VoidCallback onToggleTheme;
  final QuranController? quranController;
  final ReligiousController? religiousController;
  final AppSession Function(QuranAccount)? appSessionFactory;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  AppSection _section = AppSection.home;
  final _visited = <AppSection>{AppSection.home, AppSection.quran};
  final _openFeatureRoutes = <String>{};
  bool _quranFullscreen = false;
  late final QuranController _quran;
  final _quranKey = GlobalKey<QuranHostState>();
  final _religiousKey = GlobalKey<ReligiousHostState>();
  final _adhkarKey = GlobalKey<AdhkarSectionPageState>();
  late final ReligiousController _religious;
  ReminderController? _reminders;
  PrayerController? _prayer;
  Future<ReminderController?>? _preparingReminders;
  bool _religiousOpen = false;
  String? _religiousInitialCategory;
  AppExperienceController? _experience;
  late final AssistantController _assistant;
  PublicPushController? _publicPush;
  late final AppSession _appSession;
  int _adminRedirectedRevision = -1;

  void _accountSessionChanged() {
    if (!mounted ||
        !_appSession.admin ||
        _adminRedirectedRevision == _appSession.sessionRevision) {
      return;
    }
    _adminRedirectedRevision = _appSession.sessionRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_appSession.admin) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/admin'),
          builder: (_) => AdminPage(session: _appSession),
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final publishedArabic =
        LocalizationScope.maybeOf(context)?.installed['ar']?.content ??
        const <String, dynamic>{};
    _religious.setEditorialUpdates(publishedArabic);
    final messages = _interfaceMessages;
    _prayer?.setInterfaceMessages(messages);
    _reminders?.setInterfaceMessages(messages);
    final next = AppExperienceScope.maybeOf(context);
    if (next != _experience) {
      if (_experience?.refreshCurrent == _refreshCurrent) {
        _experience?.refreshCurrent = null;
      }
      _experience?.unregister(_quran.audio);
      _experience?.unregister(_religious.media);
      _experience = next;
      next?.refreshCurrent = _refreshCurrent;
      next?.register(_quran.audio);
      next?.register(_religious.media);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _quran = widget.quranController ?? QuranController();
    _appSession =
        (widget.appSessionFactory?.call(_quran.account) ??
              AppSession(_quran.account))
          ..addListener(_accountSessionChanged);
    _religious =
        widget.religiousController ?? ReligiousController(quran: _quran);
    _assistant = AssistantController(_quran);
    if (_quran.repository == null) {
      _quran.load().then((_) {
        if (mounted) unawaited(_appSession.initialize());
        if (mounted && _religious.catalog == null) _religious.load();
        if (mounted) unawaited(_prepareReminders());
        if (mounted) _preparePublicPush();
      });
    } else if (_religious.catalog == null) {
      unawaited(_appSession.initialize());
      _religious.load();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_prepareReminders());
      });
      _preparePublicPush();
    } else {
      unawaited(_appSession.initialize());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_prepareReminders());
      });
      _preparePublicPush();
    }
  }

  Future<ReminderController?> _prepareReminders() {
    if (_reminders != null) return Future.value(_reminders);
    return _preparingReminders ??= _loadReminders().whenComplete(
      () => _preparingReminders = null,
    );
  }

  void _preparePublicPush() {
    if (_publicPush != null || _quran.preferences == null) return;
    final controller = PublicPushController(
      _quran.preferences!,
      onOpen: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openFeature(AppFeature.messages);
        });
      },
    );
    _publicPush = controller;
    unawaited(controller.initialize());
  }

  Future<ReminderController?> _loadReminders() async {
    try {
      if (_quran.repository == null || _quran.preferences == null) return null;
      _preparePrayer();
      final activity = await _religious.activity;
      final catalog =
          _religious.initialAdhkarCatalog ??
          await AdhkarRepository.load(_quran.repository!);
      if (!mounted) return null;
      final reminders = ReminderController(
        activity,
        catalog,
        onOpen: _openReminder,
        prayer: _prayer,
      );
      reminders.setInterfaceMessages(_interfaceMessages);
      setState(() => _reminders = reminders);
      await reminders.initialize();
      return mounted ? reminders : null;
    } catch (_) {
      /* Feature pages offer a retry when initialization fails. */
    }
    return null;
  }

  void _openReminder(String route) {
    if (!mounted) return;
    if (route.startsWith('adhkar-')) {
      Navigator.of(context).popUntil((page) => page.isFirst);
    }
    switch (route) {
      case 'messages':
        _openFeature(AppFeature.messages);
      case 'prayer':
        _openPrayer();
      case 'prayer-settings':
        _openPrayer(settings: true);
      case 'adhkar-morning':
      case 'adhkar-evening':
      case 'adhkar-sleep':
      case 'adhkar-after-prayer':
        _selectSection(AppSection.adhkar);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _adhkarKey.currentState?.navigator.currentState?.popUntil(
              (route) => route.isFirst,
            );
            _adhkarKey.currentState?.openGroup(
              'daily:${route.substring('adhkar-'.length)}',
            );
          }
        });
      case 'qibla':
        _selectSection(AppSection.qibla);
      case 'quran':
        _openQuran();
      case 'khatma':
        _openFeature(AppFeature.khatma);
      case 'library':
        _selectSection(AppSection.more);
      case 'friday':
        _openFeature(AppFeature.friday);
      case 'settings':
        _openFeature(AppFeature.settings);
      default:
        _selectSection(AppSection.adhkar);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _prayer?.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      unawaited(_appSession.refresh());
      AppearanceScope.of(context).refreshTime();
      unawaited(_reminders?.reconcile(force: true) ?? Future.value());
      if (_publicPush?.wanted == true) unawaited(_publicPush!.reconcile());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appSession.removeListener(_accountSessionChanged);
    _appSession.dispose();
    _assistant.dispose();
    _publicPush?.dispose();
    _reminders?.dispose();
    _prayer?.dispose();
    if (_experience?.refreshCurrent == _refreshCurrent) {
      _experience?.refreshCurrent = null;
    }
    _experience?.unregister(_quran.audio);
    _experience?.unregister(_religious.media);
    if (widget.religiousController == null) _religious.dispose();
    if (widget.quranController == null) _quran.dispose();
    super.dispose();
  }

  void _selectSection(AppSection section) {
    if (section != AppSection.quran && _quranFullscreen) {
      _quranFullscreen = false;
      _experience?.setBottomBarVisible(true);
    }
    _experience?.changeSurface(
      section == AppSection.quran
          ? 'quran'
          : section == AppSection.more && _religiousOpen
          ? 'religious'
          : section == AppSection.more
          ? 'more'
          : 'home-${section.index}',
    );
    setState(() {
      _section = section;
      _visited.add(section);
    });
  }

  void _selectBottomDestination(int index) {
    final section = AppSection.values[index];
    if (section == _section) {
      if (section == AppSection.quran) {
        _quranKey.currentState?.navigator.currentState?.popUntil(
          (route) => route.isFirst,
        );
      } else if (section == AppSection.adhkar) {
        _adhkarKey.currentState?.showRoot();
      } else if (section == AppSection.more && _religiousOpen) {
        _religiousOpen = false;
      }
    }
    _selectSection(section);
  }

  void _selectDestinationFromSettings(int index) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _selectBottomDestination(index);
  }

  Future<void> _refreshCurrent() async {
    await _quran.flushReading();
    await _religious.settle();
    await _reminders?.flush();
    await _quran.preferences?.reload();
    if (!mounted) return;
    _quran.refreshReading();
    _prayer?.reloadBackup();
    AppearanceScope.of(context).refreshTime();
    await _reminders?.reconcile();
    final activity = await _religious.activity;
    await activity.sync();
    if (_section == AppSection.more && _religiousOpen) {
      await _religious.refresh();
    }
  }

  void _pushFeature(
    AppFeature feature,
    WidgetBuilder builder, {
    bool withBottomNavigation = false,
  }) {
    if (!_openFeatureRoutes.add(feature.routeName)) return;
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            settings: withBottomNavigation
                ? BottomNavigationRouteSettings(name: feature.routeName)
                : RouteSettings(name: feature.routeName),
            builder: builder,
          ),
        )
        .whenComplete(() => _openFeatureRoutes.remove(feature.routeName));
  }

  void _preparePrayer() {
    if (_prayer != null || _quran.preferences == null) return;
    _prayer = PrayerController(
      _quran.preferences!,
      scopeOf: () => _quran.account.profile == null
          ? 'guest'
          : 'account.${_quran.account.profile!['id']}',
      account: _quran.account,
    );
    _prayer!.setInterfaceMessages(_interfaceMessages);
    if (mounted) setState(() {});
  }

  Future<void> _beforePrayerAudio() async {
    await _quran.audio.stop();
    await _religious.media.stop();
  }

  InterfaceMessages get _interfaceMessages =>
      LocalizationScope.maybeOf(context)?.messages ??
      InterfaceMessages.bundled(Localizations.localeOf(context).languageCode);

  Future<bool> _enablePrayerReminders() async {
    final reminders = await _prepareReminders();
    if (reminders == null) return false;
    await reminders.settings.set('enabled', true);
    await reminders.reconcile();
    return reminders.settings.error == null &&
        reminders.settings.flag('enabled');
  }

  Future<void> _openHomeSearch({String initialQuery = ''}) async {
    final result = await Navigator.push<Object>(
      context,
      MaterialPageRoute(
        builder: (_) => _HomeSearchPage(
          quran: _quran,
          religious: _religious,
          initialQuery: initialQuery,
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result is AppFeature) {
      _openFeature(result);
    } else if (result is QuranVerse) {
      _selectSection(AppSection.quran);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _quranKey.currentState?.openReader(result);
      });
    } else if (result is ReligiousItem) {
      _openReligious(
        result.categories
                .where((id) => _religious.catalog!.byCategory.containsKey(id))
                .firstOrNull ??
            'prophetic-duas',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _religiousKey.currentState?.openItem(result);
      });
    }
  }

  Future<void> _openHomeArticle(String title, String key) async {
    final verse = _quran.repository?.byKey[key];
    if (verse == null) return;
    final explain = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _HomeArticlePage(
          title: title,
          verse: verse,
          surah: _quran.repository!.surah(verse.surah).name,
        ),
      ),
    );
    if (!mounted || explain != true) return;
    _openQuran();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _quranKey.currentState?.openExplanation(verse: verse);
    });
  }

  void _openDailyTafsir() {
    final verse = _quran.repository?.byKey['65:4'];
    if (verse == null) return;
    _openQuran();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _quranKey.currentState?.openExplanation(verse: verse);
      }
    });
  }

  void _openPrayerAlert(PrayerName prayer) {
    _preparePrayer();
    if (_prayer == null) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PrayerAlertPage(
          controller: _prayer!,
          prayer: prayer,
          beforeAudio: _beforePrayerAudio,
          enableReminders: _enablePrayerReminders,
        ),
      ),
    );
  }

  void _openPrayer({bool settings = false}) {
    _preparePrayer();
    final c = _prayer;
    if (c == null) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => settings
            ? PrayerAdhanSettingsPage(
                controller: c,
                onOpenRoute: _openReminder,
                beforeAudio: _beforePrayerAudio,
                enableReminders: _enablePrayerReminders,
              )
            : PrayerPage(
                controller: c,
                onOpenRoute: _openReminder,
                beforeAudio: _beforePrayerAudio,
                enableReminders: _enablePrayerReminders,
              ),
      ),
    );
  }

  void _openQuran({bool resume = false}) {
    _selectSection(AppSection.quran);
    if (resume) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _quranKey.currentState?.openLastReading();
      });
    }
  }

  void _openDailyAdhkar() {
    final group = AppearanceScope.of(context).dailyAdhkarGroup;
    _selectSection(AppSection.adhkar);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final host = _adhkarKey.currentState;
      host?.navigator.currentState?.popUntil((route) => route.isFirst);
      unawaited(host?.openGroup(group) ?? Future.value());
    });
  }

  void _openReligious(String category) {
    _experience?.changeSurface('religious');
    if (_religiousOpen && _religiousKey.currentState != null) {
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

  Widget _accountHub() => AccountHubPage(
    controller: _religious,
    appSession: _appSession,
    beforeBackup: () async {
      await _reminders?.settings.flush();
      await _prayer?.flush();
    },
    onRestored: () async {
      await _reminders?.reloadBackup();
    },
  );

  void _openQuranDownloads() {
    _openQuran();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _quranKey.currentState?.openDownloads();
    });
  }

  void _openFeature(AppFeature feature) {
    switch (feature) {
      case AppFeature.assistant:
      case AppFeature.subscription:
        _pushFeature(
          feature,
          (_) => AssistantPage(
            religious: _religious,
            controller: _assistant,
            subscription: feature == AppFeature.subscription,
          ),
        );
      case AppFeature.circles:
      case AppFeature.duaTogether:
      case AppFeature.messages:
      case AppFeature.stories:
        _pushFeature(
          feature,
          (_) => CommunityPage(
            religious: _religious,
            push: _publicPush,
            section: switch (feature) {
              AppFeature.circles => CommunitySection.circles,
              AppFeature.duaTogether => CommunitySection.prayers,
              AppFeature.messages => CommunitySection.messages,
              _ => CommunitySection.stories,
            },
          ),
        );
      case AppFeature.sakinah:
        _pushFeature(feature, (_) => SakinahPage(controller: _religious));
      case AppFeature.khatma:
      case AppFeature.habits:
      case AppFeature.statistics:
        _pushFeature(
          feature,
          (_) => ProgressPage(
            controller: _religious,
            section: switch (feature) {
              AppFeature.khatma => ProgressSection.khatma,
              AppFeature.habits => ProgressSection.habits,
              _ => ProgressSection.statistics,
            },
          ),
        );
      case AppFeature.tasbih:
        _pushFeature(feature, (_) => TasbihPage(controller: _religious));
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
      case AppFeature.mosques:
        _preparePrayer();
        if (_prayer != null) {
          _pushFeature(feature, (_) => MosquesPage(controller: _prayer!));
        }
      case AppFeature.settings:
        _pushFeature(
          feature,
          (_) => SettingsPage(
            section: _section,
            onDestinationSelected: _selectDestinationFromSettings,
            reminders: _reminders,
            loadReminders: _prepareReminders,
            onPrayerSettings: () {
              Navigator.of(context).pop();
              _openPrayer(settings: true);
            },
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
          withBottomNavigation: true,
        );
      case AppFeature.appearance:
        _pushFeature(
          feature,
          (_) => SettingsDetailPage(
            kind: SettingKind.appearance,
            section: _section,
            onDestinationSelected: _selectDestinationFromSettings,
          ),
          withBottomNavigation: true,
        );
      default:
        if (feature.category != null) {
          if (_section == AppSection.adhkar) {
            _pushFeature(
              feature,
              (routeContext) => Directionality(
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
            );
          } else {
            _openReligious(feature.category!);
          }
        } else {
          _pushFeature(
            feature,
            (_) => FeaturePreparationPage(feature: feature),
          );
        }
    }
  }

  Widget _buildHome() => CustomScrollView(
    key: const PageStorageKey('home-feed'),
    slivers: [
      SliverToBoxAdapter(
        child: ListenableBuilder(
          listenable: _quran.account,
          builder: (context, _) => _HeroHeader(
            name:
                (_quran.account.profile?['name'] as String?)
                        ?.trim()
                        .isNotEmpty ==
                    true
                ? (_quran.account.profile!['name'] as String).trim()
                : 'ضيف حق',
            onAccount: _openQuranAccount,
            onSearch: _openHomeSearch,
            onNotifications: () => _openFeature(AppFeature.messages),
          ),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 116),
        sliver: SliverList(
          delegate: SliverChildListDelegate.fixed([
            PrayerCard(
              controller: _prayer,
              onTap: _openPrayer,
              onPrayerTap: _openPrayerAlert,
            ),
            SizedBox(height: 14),
            QuickServices(
              onDuasTap: () => _selectSection(AppSection.more),
              onAdhkarTap: () => _selectSection(AppSection.adhkar),
              onKhatmaTap: () => _openFeature(AppFeature.khatma),
              onTasbihTap: () => _openFeature(AppFeature.tasbih),
              onFeelingsTap: () => _openFeature(AppFeature.feelings),
              onQiblaTap: () => _selectSection(AppSection.qibla),
              onQuranTap: () => _openQuran(),
              onMoreTap: () => _selectSection(AppSection.more),
            ),
            SizedBox(height: 18),
            DhikrCard(onTap: _openDailyAdhkar),
            SizedBox(height: 14),
            ReadingCard(
              controller: _quran,
              onContinue: () => _openQuran(resume: true),
            ),
            SizedBox(height: 14),
            DailyVerseCard(onTafsir: _openDailyTafsir),
            SizedBox(height: 20),
            SectionHeader(
              title: 'رحلتك اليوم',
              action: 'عرض الكل',
              onTap: () => _openFeature(AppFeature.statistics),
            ),
            SizedBox(height: 10),
            JourneyCards(controller: _religious, onFeature: _openFeature),
            SizedBox(height: 20),
            FridayCard(onTap: () => _openReligious('friday')),
            SizedBox(height: 20),
            SectionHeader(
              title: 'مقالات ومعلومات',
              action: 'عرض الكل',
              onTap: () => _selectSection(AppSection.more),
            ),
            SizedBox(height: 10),
            ArticlesRow(
              onCongregation: () =>
                  _openHomeArticle('فضل صلاة الجماعة', '2:43'),
              onCharity: () =>
                  _openHomeArticle('فضل الصدقة في الإسلام', '2:261'),
            ),
          ]),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final religiousHandlesBack = _section == AppSection.more && _religiousOpen;
    return Directionality(
      textDirection:
          LocalizationScope.maybeOf(context)?.language.direction ??
          TextDirection.rtl,
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
                  accountBuilder: _accountHub,
                  active: _section == AppSection.quran,
                  onExit: () => _selectSection(AppSection.home),
                  onFullscreenChanged: (value) {
                    _experience?.setBottomBarVisible(!value);
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
                  ? _prayer != null
                        ? QiblaPage(
                            controller: _prayer!,
                            onOpenRoute: _openReminder,
                            active: _section == AppSection.qibla,
                            beforeAudio: _beforePrayerAudio,
                            enableReminders: _enablePrayerReminders,
                          )
                        : const FeaturePreparationPage(
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
                      initialCategoryAsRoot: true,
                      onClose: () {
                        _experience?.changeSurface('more');
                        setState(() => _religiousOpen = false);
                      },
                    )
                  : MorePage(onFeature: _openFeature),
            ],
          ),
          extendBody: true,
          bottomNavigationBar: _quranFullscreen && _section == AppSection.quran
              ? null
              : AppBottomNavigation(
                  section: _section,
                  onSelected: _selectBottomDestination,
                ),
        ),
      ),
    );
  }
}

class SocialMediaSection extends StatelessWidget {
  const SocialMediaSection({super.key});

  static Future<void> shareApp(BuildContext context) => chooseContentShare(
    context,
    ShareCardContent.message('شارك الخير مع من تحب عبر تطبيق حق'),
  );

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
                onTap: () => shareApp(context),
                child: Icon(Icons.share_outlined, size: 28),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        Material(
          color: appAccent(context, AppColors.teal),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: () => shareApp(context),
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
  const _SocialButton({required this.label, required this.child, this.onTap});
  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      onTap: onTap ?? () {},
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
                color: appAccent(
                  context,
                  AppColors.teal,
                ).withValues(alpha: .11),
                shape: BoxShape.circle,
              ),
              child: IconTheme(
                data: IconThemeData(color: appAccent(context, AppColors.teal)),
                child: DefaultTextStyle(
                  style: TextStyle(color: appAccent(context, AppColors.teal)),
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
  const SectionHeader({
    super.key,
    required this.title,
    required this.action,
    this.onTap,
  });
  final VoidCallback? onTap;
  final String title;
  final String action;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          action,
          style: TextStyle(
            color: appAccent(context, AppColors.teal),
            fontWeight: FontWeight.w700,
          ),
        ),
        Icon(
          Icons.chevron_left,
          color: appAccent(context, AppColors.teal),
          textDirection: TextDirection.ltr,
        ),
      ],
    ),
  );
}
