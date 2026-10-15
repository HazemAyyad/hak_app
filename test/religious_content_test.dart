import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/religious_content/data/religious_catalog.dart';
import 'package:haq_app/features/religious_content/data/religious_controller.dart';
import 'package:haq_app/features/religious_content/presentation/religious_host.dart';
import 'package:haq_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranRepository quranData;
  late ReligiousCatalog catalog;
  late QuranController quran;
  late ReligiousController controller;
  late AppAppearance appearance;
  final hostKey = GlobalKey<ReligiousHostState>();
  final previewKey = GlobalKey();
  setUpAll(() async {
    quranData = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    catalog = ReligiousCatalog.fromJson(
      jsonDecode(File('assets/religious/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    for (final (name, path) in [
      ('QuranUI', 'assets/fonts/Cairo.ttf'),
      ('Tajawal', 'assets/fonts/Tajawal-Regular.ttf'),
      ('AmiriQuran', 'assets/fonts/AmiriQuran.ttf'),
    ]) {
      await (FontLoader(name)..addFont(rootBundle.load(path))).load();
    }
    final font = File(
      'C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    if (font.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(font.readAsBytesSync())),
          ))
          .load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    appearance = AppAppearance(prefs);
    quran = QuranController(initialRepository: quranData, preferences: prefs);
    await quran.load();
    controller = ReligiousController(quran: quran, initialCatalog: catalog);
    await controller.load();
  });
  tearDown(() {
    controller.dispose();
    quran.dispose();
    appearance.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    double width = 426,
    double scale = 1,
    ThemeMode mode = ThemeMode.light,
  }) async {
    tester.view.physicalSize = Size(width, 922);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await appearance.setMode(mode);
    await tester.pumpWidget(
      AppearanceScope(
        controller: appearance,
        child: RepaintBoundary(
          key: previewKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'QuranUI',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF075158),
                primary: const Color(0xFF075158),
                brightness: mode == ThemeMode.dark
                    ? Brightness.dark
                    : Brightness.light,
              ),
              brightness: mode == ThemeMode.dark
                  ? Brightness.dark
                  : Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: ReligiousHost(
                  key: hostKey,
                  controller: controller,
                  onClose: () {},
                ),
                bottomNavigationBar: ReligiousNavigationBar(onSelected: (_) {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull, reason: name);
    if (!const bool.fromEnvironment('RELIGIOUS_PREVIEWS')) return;
    await tester.runAsync(() async {
      final context = previewKey.currentContext!;
      for (final image in Directory(
        'assets/religious',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.png'))) {
        await precacheImage(
          AssetImage(image.path.replaceAll('\\', '/')),
          context,
        );
      }
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          previewKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/religious-preview');
      await dir.create(recursive: true);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  void reset() {
    hostKey.currentState!.navigator.currentState!.popUntil((r) => r.isFirst);
  }

  test(
    'canonical catalog, references, complete collections and nested search',
    () {
      expect(catalog.children(null).length, 7);
      expect(catalog.search(category: 'names').length, 99);
      expect(catalog.search(category: 'nawawi').length, 42);
      expect(
        catalog.search(category: 'quran-duas', query: 'ربنا اتنا').single.id,
        'qdua-goodness',
      );
      for (final item in catalog.items.where((i) => i.type == 'quran')) {
        expect(
          item.text,
          item.verseKeys.map((key) => quranData.byKey[key]!.text).join('\n'),
        );
      }
      expect(
        catalog.search(category: 'sunnah').any((i) => i.id == 'sunnah-hands'),
        isTrue,
      );
      expect(catalog.byId['sunnah-hands']!.source, contains('735'));
    },
  );
  test(
    'favorites and personal adhkar persist and share one content identity',
    () async {
      await controller.toggleFavorite('sunnah-wash');
      await controller.toggleAdhkar('qdua-goodness');
      await controller.toggleQueue('ruqya-complete');
      final restored = ReligiousController(
        quran: quran,
        initialCatalog: catalog,
      );
      await restored.load();
      expect(restored.favorites, contains('sunnah-wash'));
      expect(restored.customAdhkar, contains('qdua-goodness'));
      expect(restored.listeningQueue, contains('ruqya-complete'));
      expect(
        catalog
            .search(category: 'friday', favorites: restored.favorites)
            .single
            .id,
        'sunnah-wash',
      );
      expect(
        catalog
            .search(category: 'sunnah-prayer', favorites: restored.favorites)
            .single
            .id,
        'sunnah-wash',
      );
      await restored.toggleFavorite('sunnah-wash');
      expect(restored.favorites, isEmpty);
      restored.dispose();
    },
  );
  testWidgets(
    'disposing while local catalog is loading leaves no background timer',
    (tester) async {
      await tester.runAsync(() async {
        final delayed = ReligiousController(quran: quran);
        final pending = delayed.load();
        delayed.dispose();
        await pending;
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
  testWidgets('all reference screens render and navigate', (tester) async {
    await pump(tester);
    await capture(tester, 'D07-home');
    for (final (id, code) in [
      ('quran-duas', 'D04'),
      ('prophetic-duas', 'D05'),
      ('nawawi', 'D06'),
      ('names', 'D03'),
      ('ruqya', 'D09'),
      ('sunnah', 'D19'),
      ('sunnah-prayer', 'D18'),
      ('friday', 'D17'),
      ('ruqya-protection', 'D02'),
    ]) {
      reset();
      await tester.pumpAndSettle();
      hostKey.currentState!.openCategory(id);
      await tester.pumpAndSettle();
      await capture(tester, '$code-$id');
    }
    final host = hostKey.currentState!;
    await tester.ensureVisible(find.text('من العين والحسد').first);
    await tester.tap(find.text('من العين والحسد').first);
    await tester.pumpAndSettle();
    await capture(tester, 'D01-eye-filter');
    for (final (id, code) in [
      ('qdua-goodness', 'D14'),
      ('hisn-001', 'D13'),
      ('nawawi-01', 'D12'),
      ('name-01', 'D11'),
      ('sunnah-hands', 'D15'),
      ('sunnah-wash', 'D16'),
      ('ruqya-kursi', 'D10'),
      ('ruqya-complete', 'D08'),
    ]) {
      reset();
      await tester.pumpAndSettle();
      host.openItem(catalog.byId[id]!);
      await tester.pumpAndSettle();
      await capture(tester, '$code-$id');
    }
    await tester.tap(find.text('القراءة'));
    await tester.pumpAndSettle();
    expect(find.text('سورة الفاتحة'), findsOneWidget);
    await tester.tap(find.text('معلومات'));
    await tester.pumpAndSettle();
    expect(find.text('مصدر المحتوى'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'search and back preserve the list query; favorite updates saved list',
    (tester) async {
      await pump(tester);
      final host = hostKey.currentState!;
      host.openCategory('quran-duas');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ربنا اتنا');
      await tester.pumpAndSettle();
      await tester.tap(find.text(catalog.byId['qdua-goodness']!.title).first);
      await tester.pumpAndSettle();
      await tester.runAsync(() => controller.toggleFavorite('qdua-goodness'));
      host.back();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'ربنا اتنا',
      );
      host.openSaved();
      await tester.pumpAndSettle();
      expect(find.text(catalog.byId['qdua-goodness']!.title), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('all categories and details fit 320px enlarged ${mode.name}', (
      tester,
    ) async {
      await pump(tester, width: 320, scale: 1.3, mode: mode);
      await capture(tester, 'narrow-${mode.name}-home');
      final host = hostKey.currentState!;
      for (final category in catalog.children(null)) {
        reset();
        await tester.pumpAndSettle();
        host.openCategory(category.id);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: category.id);
      }
      for (final id in [
        'qdua-goodness',
        'hisn-001',
        'sunnah-hands',
        'name-01',
        'nawawi-01',
        'ruqya-complete',
      ]) {
        reset();
        await tester.pumpAndSettle();
        host.openItem(catalog.byId[id]!);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: id);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'actual home prayer shortcut opens section and system back returns to More',
    (tester) async {
      tester.view.physicalSize = const Size(426, 922);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        HaqApp(
          showStartup: false,
          appearance: appearance,
          quranController: quran,
          religiousController: controller,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('الأدعية'));
      await tester.tap(find.text('الأدعية'));
      await tester.pumpAndSettle();
      expect(find.byType(ReligiousHost), findsOneWidget);
      expect(find.text('الأدعية والمحتوى الديني'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReligiousHost), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
