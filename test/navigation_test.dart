import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/features/adhkar/data/adhkar_repository.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/religious_content/data/religious_catalog.dart';
import 'package:haq_app/features/religious_content/data/religious_controller.dart';
import 'package:haq_app/features/religious_content/presentation/religious_host.dart';
import 'package:haq_app/main.dart';
import 'package:haq_app/settings_pages.dart';
import 'package:haq_app/features/quran/presentation/quran_host.dart';
import 'package:haq_app/navigation/app_section.dart';
import 'package:haq_app/navigation/feature_routes.dart';
import 'package:haq_app/navigation/more_page.dart';
import 'package:haq_app/navigation/more_service_grid.dart';
import 'package:haq_app/navigation/section_entry_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/visual_audit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranRepository repository;
  late ReligiousCatalog catalog;
  late AdhkarRepository adhkar;
  late QuranController quran;
  late ReligiousController religious;
  late AppAppearance appearance;
  final previewKey = GlobalKey();

  setUpAll(() async {
    await loadVisualAuditFonts();
    repository = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    catalog = ReligiousCatalog.fromJson(
      jsonDecode(File('assets/religious/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    adhkar = AdhkarRepository.fromJson(
      jsonDecode(File('assets/religious/adhkar.json').readAsStringSync())
          as Map<String, dynamic>,
      repository,
    );
    for (final (family, asset) in [
      ('QuranUI', 'assets/fonts/Cairo.ttf'),
      ('AmiriQuran', 'assets/fonts/AmiriQuran.ttf'),
      ('Tajawal', 'assets/fonts/Tajawal-Regular.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
    final icons = File(
      'C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(icons.readAsBytesSync())),
          ))
          .load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    appearance = AppAppearance(preferences);
    quran = QuranController(
      initialRepository: repository,
      preferences: preferences,
    );
    await quran.load();
    religious = ReligiousController(
      quran: quran,
      initialCatalog: catalog,
      initialAdhkarCatalog: adhkar,
    );
    await religious.load();
  });
  tearDown(() {
    religious.dispose();
    quran.dispose();
    appearance.dispose();
  });

  Future<void> pumpApp(WidgetTester tester, {double width = 426}) async {
    tester.view.physicalSize = visualSize(Size(width, 922));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: previewKey,
        child: HaqApp(
          showStartup: false,
          appearance: appearance,
          quranController: quran,
          religiousController: religious,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, AppSection section) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(section.label),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseLayout(
    WidgetTester tester,
    MoreDirectoryLayout layout,
  ) async {
    await tester.tap(find.byTooltip('طريقة العرض'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(layout == MoreDirectoryLayout.grid ? 'شبكة' : 'قائمة مصوّرة'),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await prepareVisualAuditCapture(tester, previewKey);
    if (!visualAudit && !const bool.fromEnvironment('NAVIGATION_PREVIEWS')) {
      return;
    }
    await tester.runAsync(() async {
      final boundary =
          previewKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(visualPath('build/navigation-preview'));
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await captureAuditContinuation(
      tester,
      previewKey,
      visualPath('build/navigation-preview/$name.png'),
    );
  }

  testWidgets('one bottom bar reselects the Quran root in one tap', (
    tester,
  ) async {
    await pumpApp(tester);
    await tab(tester, AppSection.quran);
    final host = tester.state<QuranHostState>(find.byType(QuranHost));
    host.openIndex();
    host.openIndex();
    await tester.pumpAndSettle();
    expect(find.byType(QuranIndexPage), findsOneWidget);
    expect(find.byType(QuranIndexPage, skipOffstage: false), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tab(tester, AppSection.quran);
    expect(find.byType(QuranIndexPage), findsNothing);
    expect(find.byKey(const ValueKey('haq-bottom-navigation')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'rapid repeated service taps create one route and need one back',
    (tester) async {
      await pumpApp(tester);
      await tab(tester, AppSection.more);
      final open = tester.widget<MorePage>(find.byType(MorePage)).onFeature;
      open(AppFeature.settings);
      open(AppFeature.settings);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage, skipOffstage: false), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MorePage), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'More uses the same bar and one reselect closes its content section',
    (tester) async {
      await pumpApp(tester);
      await tab(tester, AppSection.more);
      final open = tester.widget<MorePage>(find.byType(MorePage)).onFeature;
      open(AppFeature.quranDuas);
      await tester.pumpAndSettle();
      expect(find.byType(ReligiousHost), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tab(tester, AppSection.more);
      expect(find.byType(MorePage), findsOneWidget);
      expect(find.byType(ReligiousHost), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'home reflects the current account and search opens a real surah',
    (tester) async {
      await pumpApp(tester);
      expect(find.text('ضيف حق'), findsOneWidget);
      quran.account.profile = {'id': 77, 'name': 'حازم عياد'};
      await tester.runAsync(() => quran.account.expireSession());
      await tester.pumpAndSettle();
      expect(find.text('حازم عياد'), findsOneWidget);
      expect(find.text('أحمد محمد'), findsNothing);
      for (var i = 0; i < 8; i++) {
        expect(
          tester.widget<InkWell>(find.byKey(ValueKey('home-service-$i'))).onTap,
          isNotNull,
        );
      }
      await tester.tap(find.byTooltip('البحث في حق'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('haq-global-search')),
        'الفاتحة',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('سورة الفاتحة').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('haq-global-search')), findsNothing);
      expect(find.text('الصلاة القادمة'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets('top account and messages actions open their real destinations', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('رسائل حق'));
    await tester.pumpAndSettle();
    expect(find.text('الصلاة القادمة'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('الحساب'));
    await tester.pumpAndSettle();
    expect(find.text('الصلاة القادمة'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'five tabs have their own destination; system back returns to home including Quran root',
    (tester) async {
      await pumpApp(tester);
      for (final section in AppSection.values.skip(1)) {
        await tab(tester, section);
        expect(find.text('الصلاة القادمة'), findsNothing, reason: section.name);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          section.index,
        );
        if (section == AppSection.adhkar) {
          expect(find.byType(AdhkarSectionPage), findsOneWidget);
        }
        if (section == AppSection.qibla) {
          expect(find.text('الموقع غير متاح'), findsOneWidget);
          expect(find.byType(AdhkarSectionPage), findsNothing);
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          AppSection.home.index,
          reason: section.name,
        );
        expect(find.text('الصلاة القادمة'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'home dhikr shortcut keeps scroll position and saved content returns to the adhkar tab',
    (tester) async {
      await pumpApp(tester);
      await tester.ensureVisible(find.text('عرض الأذكار'));
      await tester.pumpAndSettle();
      final home = find.byKey(const PageStorageKey('home-feed'));
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: home, matching: find.byType(Scrollable)).first,
      );
      final offset = scroll.position.pixels;
      await tester.tap(find.text('عرض الأذكار'));
      await tester.pumpAndSettle();
      expect(find.byType(AdhkarSectionPage), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('adhkar-personalAdhkar')));
      await tester.pumpAndSettle();
      expect(find.byType(ReligiousHost), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AdhkarSectionPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, offset);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'inactive religious navigator cannot consume another tab back; its stack survives switching',
    (tester) async {
      await pumpApp(tester);
      await tab(tester, AppSection.more);
      final library = find.byKey(const ValueKey('feature-quranDuas'));
      await tester.enterText(
        find.byKey(const ValueKey('more-search')),
        AppFeature.quranDuas.title,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(library);
      await tester.pumpAndSettle();
      await tester.tap(library);
      await tester.pumpAndSettle();
      expect(find.byType(ReligiousHost), findsOneWidget);
      await tester.tap(find.text('القرآن').last);
      await tester.pumpAndSettle();
      expect(find.byType(ReligiousHost), findsNothing);
      expect(find.byType(ReligiousHost, skipOffstage: false), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('الصلاة القادمة'), findsOneWidget);
      await tab(tester, AppSection.more);
      expect(find.byType(ReligiousHost), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MorePage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'content sections open directly and back returns to More without a library hub',
    (tester) async {
      await pumpApp(tester);
      await tab(tester, AppSection.more);
      expect(find.text('الأدعية والمحتوى الديني'), findsNothing);
      for (final feature in [
        AppFeature.quranDuas,
        AppFeature.ruqya,
        AppFeature.names,
        AppFeature.propheticDuas,
        AppFeature.prophets,
        AppFeature.friday,
        AppFeature.sunnah,
        AppFeature.ramadan,
        AppFeature.nawawi,
        AppFeature.dailyDuas,
        AppFeature.savedContent,
      ]) {
        await tester.enterText(
          find.byKey(const ValueKey('more-search')),
          feature.title,
        );
        await tester.pumpAndSettle();
        final tile = find.byKey(ValueKey('feature-${feature.name}'));
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(
          find.byType(ReligiousHost),
          findsOneWidget,
          reason: feature.name,
        );
        expect(
          find.byKey(const PageStorageKey('religious-home')),
          findsNothing,
          reason: feature.name,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MorePage), findsOneWidget, reason: feature.name);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'directory keeps every service and each control dispatches its own destination',
    (tester) async {
      final selected = <AppFeature>[];
      await tester.pumpWidget(
        AppearanceScope(
          controller: appearance,
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: MorePage(onFeature: selected.add)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        AppFeature.values.map((feature) => feature.routeName).toSet().length,
        AppFeature.values.length,
      );
      final grouped = moreServiceGroups.expand((group) => group.$2).toList();
      final services = AppFeature.values.where(
        (feature) =>
            feature != AppFeature.settings && feature != AppFeature.appearance,
      );
      expect(grouped, unorderedEquals(services));
      final first = tester.getRect(
        find.byKey(const ValueKey('feature-adhkar')),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey('feature-tasbih')),
      );
      expect(first.top, second.top);
      expect(first.width, second.width);
      expect(first.left, greaterThan(second.left));
      expect(find.byType(DirectoryHeader), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(ActionChip), findsNothing);
      expect(find.byKey(const ValueKey('feature-appearance')), findsNothing);
      await tester.tap(find.byTooltip('الإعدادات'));
      expect(selected.removeLast(), AppFeature.settings);
      for (final layout in MoreDirectoryLayout.values) {
        await chooseLayout(tester, layout);
        for (final feature in AppFeature.values) {
          await tester.enterText(
            find.byKey(const ValueKey('more-search')),
            feature.title,
          );
          await tester.pumpAndSettle();
          final control = find.byKey(ValueKey('feature-${feature.name}'));
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: control, matching: find.byType(Image)),
            layout == MoreDirectoryLayout.list ? findsOneWidget : findsNothing,
            reason: feature.name,
          );
          await tester.tap(control);
          await tester.pumpAndSettle();
          expect(selected.last, feature);
          expect(tester.takeException(), isNull, reason: feature.name);
        }
      }
      expect(
        selected.length,
        AppFeature.values.length * MoreDirectoryLayout.values.length,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('layout choice preserves search and persists after reopening', (
    tester,
  ) async {
    await pumpApp(tester, width: 320);
    await tab(tester, AppSection.more);
    final search = find.byKey(const ValueKey('more-search'));
    await tester.enterText(search, 'قُرْآن');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('طريقة العرض'));
    await tester.pumpAndSettle();
    await capture(tester, 'more-layout-menu');
    await tester.tap(find.text('قائمة مصوّرة'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, 'قُرْآن');
    expect(find.byKey(const ValueKey('feature-quran')), findsOneWidget);
    expect(find.byKey(const ValueKey('feature-tasbih')), findsNothing);
    expect(appearance.preferences.getString('appearance.moreLayout'), 'list');

    await tester.pumpWidget(const SizedBox());
    final preferences = appearance.preferences;
    appearance.dispose();
    appearance = AppAppearance(preferences);
    expect(appearance.moreDirectoryLayout, MoreDirectoryLayout.list);
    await pumpApp(tester, width: 320);
    await tab(tester, AppSection.more);
    expect(find.byType(SliverGrid), findsNothing);
    expect(find.byType(Image), findsWidgets);
    await chooseLayout(tester, MoreDirectoryLayout.grid);
    expect(appearance.preferences.getString('appearance.moreLayout'), 'grid');
    final restored = AppAppearance(preferences);
    expect(restored.moreDirectoryLayout, MoreDirectoryLayout.grid);
    restored.dispose();
    await preferences.setString('appearance.moreLayout', 'unknown');
    final fallback = AppAppearance(preferences);
    expect(fallback.moreDirectoryLayout, MoreDirectoryLayout.grid);
    fallback.dispose();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'directory search normalizes Arabic and clear restores destinations',
    (tester) async {
      await pumpApp(tester);
      await tab(tester, AppSection.more);
      final search = find.byKey(const ValueKey('more-search'));
      await tester.enterText(search, 'قُرْآن');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('feature-quran')), findsOneWidget);
      expect(find.byKey(const ValueKey('feature-tasbih')), findsNothing);
      await capture(tester, 'more-search');
      await tester.enterText(search, 'عبارة غير موجودة');
      await tester.pumpAndSettle();
      expect(find.text('لا توجد خدمات تطابق بحثك'), findsOneWidget);
      await capture(tester, 'more-no-results');
      await tester.tap(find.byTooltip('مسح البحث'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('feature-tasbih')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('More reference preview ${mode.name}', (tester) async {
      await appearance.setMode(mode);
      await pumpApp(tester, width: 390);
      await tab(tester, AppSection.more);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'more-${mode.name}');
      await chooseLayout(tester, MoreDirectoryLayout.list);
      await tester.runAsync(() async {
        for (final image in find.byType(Image).evaluate()) {
          await precacheImage(
            (image.widget as Image).image,
            previewKey.currentContext!,
          );
        }
      });
      await tester.pumpAndSettle();
      await capture(tester, 'more-list-${mode.name}');
      if (visualAudit) {
        final secondary = find.byKey(const ValueKey('feature-quranDuas'));
        await tester.scrollUntilVisible(
          secondary,
          300,
          scrollable: find
              .descendant(
                of: find.byKey(const PageStorageKey('more-directory')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await capture(tester, 'more-secondary-${mode.name}');
      }
      final planned = find.byKey(const ValueKey('feature-ourApps'));
      await tester.scrollUntilVisible(
        planned,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('more-directory')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(planned);
      await tester.pumpAndSettle();
      expect(find.byType(FeaturePreparationPage), findsOneWidget);
      expect(find.text('قريبًا في حق'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MorePage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'More and section entries fit narrow enlarged RTL ${mode.name}',
      (tester) async {
        await appearance.setMode(mode);
        await appearance.setFontScale(1.2);
        await pumpApp(tester, width: 320);
        await tab(tester, AppSection.more);
        await capture(tester, 'more-narrow-${mode.name}');
        await chooseLayout(tester, MoreDirectoryLayout.list);
        await capture(tester, 'more-list-narrow-${mode.name}');
        final view = find.byKey(const PageStorageKey('more-directory'));
        for (var index = 0; index < 18; index++) {
          expect(tester.takeException(), isNull);
          await tester.drag(view, const Offset(0, -400));
          await tester.pumpAndSettle();
        }
        expect(find.byTooltip('الإعدادات').hitTestable(), findsOneWidget);
        await tab(tester, AppSection.adhkar);
        expect(tester.takeException(), isNull);
        await tab(tester, AppSection.qibla);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
