import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/presentation/quran_host.dart';
import 'package:haq_app/features/quran/presentation/quran_reader.dart';
import 'package:haq_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranRepository repo;
  late QuranController controller;
  late AppAppearance appearance;

  setUpAll(() async {
    repo = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    for (final font in [
      ('QuranUI', 'assets/fonts/Cairo.ttf'),
      ('AmiriQuran', 'assets/fonts/AmiriQuran.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    await (FontLoader(
      'Arial',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    // Replace the widget test's rectangle-only fallback during visual exports.
    if (Platform.environment.containsKey('QURAN_CAPTURE_DIR')) {
      await (FontLoader(
        'Ahem',
      )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
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
    final preferences = await SharedPreferences.getInstance();
    controller = QuranController(
      initialRepository: repo,
      preferences: preferences,
    );
    await controller.load();
    appearance = AppAppearance(preferences);
  });
  tearDown(() {
    controller.dispose();
    appearance.dispose();
  });

  test('verified juz/page mapping and orthographic search', () {
    expect(repo.verses.length, 6236);
    expect(repo.juzs[6].startKey, '5:82');
    expect(repo.byKey['2:1']!.page, 2);
    expect(repo.byKey['114:6']!.page, 604);
    expect(repo.search('بسم الله', surahId: 1).single.key, '1:1');
    expect(
      repo.search('الصلاة', surahId: 2).any((v) => v.key == '2:3'),
      isTrue,
    );
    expect(repo.search('الله', juzId: 7).every((v) => v.juz == 7), isTrue);
    expect(repo.search('     '), isEmpty);
  });

  test(
    'reading and distinct saved collections survive restart without duplicates',
    () async {
      controller.remember(repo.byKey['2:255']!, alignment: .2);
      controller.toggleFavorite('2:255');
      controller.toggleBookmark('2:255');
      controller.toggleSurah(2);
      controller.setMode(QuranReadingMode.ayah);
      controller.setFontSize(29);
      controller.setPaper('ivory');
      await controller.persist();
      final restored = QuranController(
        initialRepository: repo,
        preferences: controller.preferences,
      );
      await restored.load();
      expect(restored.lastVerse!.key, '2:255');
      expect(restored.lastAlignment, .2);
      expect(restored.favorites.keys, ['2:255']);
      expect(restored.bookmarks.keys, ['2:255']);
      expect(restored.savedSurahs, {2});
      expect(restored.mode, QuranReadingMode.ayah);
      expect(restored.fontSize, 29);
      restored.toggleFavorite('2:255');
      expect(restored.favorites, isEmpty);
      expect(restored.bookmarks.keys, ['2:255']);
      restored.dispose();
    },
  );

  testWidgets(
    'Quran navigation keeps original destinations and full screen returns to verse',
    (tester) async {
      tester.view.physicalSize = const Size(400, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: HaqApp(
            showStartup: false,
            appearance: appearance,
            quranController: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('القرآن').last);
      await tester.pumpAndSettle();
      final labels = tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .destinations
          .cast<NavigationDestination>()
          .map((d) => d.label)
          .toList();
      expect(labels, ['الرئيسية', 'القرآن', 'الأذكار', 'القبلة', 'المزيد']);
      await _capture(tester, boundary, '01-quran-home');
      final host = tester.state<QuranHostState>(find.byType(QuranHost));
      host.openIndex();
      await tester.pumpAndSettle();
      expect(find.text('سورة البقرة'), findsOneWidget);
      await _capture(tester, boundary, '02-surahs');
      await tester.tap(find.text('سورة البقرة'));
      await tester.pumpAndSettle();
      expect(find.byType(QuranReader), findsOneWidget);
      expect(controller.lastVerse!.surah, 2);
      await _capture(tester, boundary, '03-reader');
      await tester.tap(find.text('تكبير السورة'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byTooltip('إغلاق التكبير'), findsOneWidget);
      await tester.tap(find.byTooltip('إغلاق التكبير'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(controller.lastVerse!.surah, 2);
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(QuranReader), findsNothing);
      expect(find.byType(QuranIndexPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'juz seven opens canonical start and verse mode crosses surah boundary correctly',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: HaqApp(
            showStartup: false,
            appearance: appearance,
            quranController: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('القرآن').last);
      await tester.pumpAndSettle();
      final host = tester.state<QuranHostState>(find.byType(QuranHost));
      host.openIndex(juz: true);
      await tester.pumpAndSettle();
      await _capture(tester, boundary, '06-juz-index');
      await tester.scrollUntilVisible(
        find.text('الجزء السابع'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('الجزء السابع')),
        alignment: .4,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('الجزء السابع'));
      await tester.pumpAndSettle();
      await _capture(tester, boundary, '07-juz-details');
      await tester.tap(find.text('بدء قراءة الجزء السابع'));
      await tester.pumpAndSettle();
      expect(controller.lastKey, '5:82');
      controller.setMode(QuranReadingMode.ayah);
      host.openReader(repo.byKey['1:7']!);
      await tester.pumpAndSettle();
      await tester.tap(find.text('الآية التالية'));
      await tester.pumpAndSettle();
      expect(controller.lastKey, '2:1');
      await _capture(tester, boundary, '08-verse-mode');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'search reader back preserves query filters and saved verse opens',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: HaqApp(
            showStartup: false,
            appearance: appearance,
            quranController: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('القرآن').last);
      await tester.pumpAndSettle();
      final host = tester.state<QuranHostState>(find.byType(QuranHost));
      host.openSearch(query: 'بسم الله');
      await tester.pumpAndSettle();
      expect(find.textContaining('نتائج البحث:'), findsOneWidget);
      await _capture(tester, boundary, '04-search');
      await tester.tap(find.text('سورة الفاتحة • الآية 1'));
      await tester.pumpAndSettle();
      expect(controller.lastKey, '1:1');
      await tester.tap(find.text('العودة إلى النتائج'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'بسم الله',
      );
      await tester.tap(find.byTooltip('تصفية نتائج البحث'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('سورة محددة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('عرض النتائج'));
      await tester.pumpAndSettle();
      expect(find.text('نتائج البحث: 1'), findsOneWidget);
      await tester.tap(find.text('سورة الفاتحة • الآية 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('العودة إلى النتائج'));
      await tester.pumpAndSettle();
      expect(find.text('نتائج البحث: 1'), findsOneWidget);
      controller.toggleFavorite('2:255');
      host.openSaved();
      await tester.pumpAndSettle();
      expect(find.text('سورة البقرة'), findsOneWidget);
      await _capture(tester, boundary, '05-favorites');
      await tester.tap(find.text('سورة البقرة'));
      await tester.pumpAndSettle();
      expect(controller.lastKey, '2:255');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'reading and settings fit narrow RTL screens with enlarged interface text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await appearance.setFontScale(1.2);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: HaqApp(
            showStartup: false,
            appearance: appearance,
            quranController: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('القرآن').last);
      await tester.pumpAndSettle();
      final host = tester.state<QuranHostState>(find.byType(QuranHost));
      host.openReader(repo.byKey['2:255']!);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('إعدادات القراءة'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, boundary, '09-settings-narrow');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final output = Platform.environment['QURAN_CAPTURE_DIR'];
  if (output == null) return;
  await tester.runAsync(() async {
    for (final asset in [
      'assets/quran/header_light.png',
      'assets/quran/header_dark.png',
      'assets/quran/header_home.png',
      'assets/quran/quran_cover.png',
      'assets/images/home_header.png',
      'assets/images/mosque_sunrise.png',
    ]) {
      await precacheImage(AssetImage(asset), key.currentContext!);
    }
  });
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(output);
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
