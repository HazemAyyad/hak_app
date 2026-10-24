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
import 'package:haq_app/navigation/app_section.dart';
import 'package:haq_app/navigation/feature_routes.dart';
import 'package:haq_app/navigation/more_page.dart';
import 'package:haq_app/navigation/section_entry_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    tester.view.physicalSize = Size(width, 922);
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

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('NAVIGATION_PREVIEWS')) return;
    await tester.runAsync(() async {
      final boundary =
          previewKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/navigation-preview');
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

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
          expect(find.text('قريبًا في حق'), findsOneWidget);
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
      final library = find.byKey(const ValueKey('feature-religiousLibrary'));
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
      for (final feature in AppFeature.values) {
        final control = find.byKey(ValueKey('feature-${feature.name}'));
        await tester.ensureVisible(control);
        await tester.pumpAndSettle();
        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(selected.last, feature);
      }
      expect(selected.length, 30);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('More reference preview ${mode.name}', (tester) async {
      await appearance.setMode(mode);
      await pumpApp(tester);
      await tab(tester, AppSection.more);
      await tester.runAsync(() async {
        for (final asset in [
          'assets/navigation/more_header.png',
          'assets/navigation/sakinah.png',
          'assets/religious/quran.png',
          'assets/religious/beads.png',
          'assets/religious/kaaba.png',
          'assets/religious/hands.png',
        ]) {
          await precacheImage(AssetImage(asset), previewKey.currentContext!);
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'more-${mode.name}');
      final planned = find.byKey(const ValueKey('feature-khatma'));
      await tester.ensureVisible(planned);
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
        final view = find.byKey(const PageStorageKey('more-directory'));
        for (var index = 0; index < 18; index++) {
          expect(tester.takeException(), isNull);
          await tester.drag(view, const Offset(0, -400));
          await tester.pumpAndSettle();
        }
        await tab(tester, AppSection.adhkar);
        expect(tester.takeException(), isNull);
        await tab(tester, AppSection.qibla);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
