import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/features/adhkar/data/adhkar_repository.dart';
import 'package:haq_app/features/religious_activity/data/activity_controller.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/religious_content/data/religious_catalog.dart';
import 'package:haq_app/features/religious_content/data/religious_controller.dart';
import 'package:haq_app/features/religious_content/presentation/religious_host.dart';
import 'package:haq_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late QuranRepository quranData;
  late ReligiousCatalog catalog;
  late AdhkarRepository adhkar;
  late ReligiousActivityStore activityStore;
  late ReligiousActivityController activity;
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
    adhkar = await AdhkarRepository.load(quranData);
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
    activityStore = await ReligiousActivityStore.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    activity = await ReligiousActivityController.open(
      quran,
      store: activityStore,
      enableSync: false,
    );
    controller = ReligiousController(
      quran: quran,
      initialCatalog: catalog,
      initialAdhkarCatalog: adhkar,
      activityFactory: () async => activity,
    );
    await controller.load();
  });
  tearDown(() async {
    controller.dispose();
    quran.dispose();
    appearance.dispose();
    await Future<void>.delayed(Duration.zero);
    if (!activity.syncClient.disposed) activity.dispose();
    await activityStore.close();
  });

  test(
    'audio availability comes from actual catalog sources before player initialization',
    () async {
      for (final id in ['nawawi-01', 'name-01', 'sunnah-hands']) {
        expect(controller.hasAudio(catalog.byId[id]!), isFalse, reason: id);
      }
      for (final id in ['qdua-goodness', 'hisn-001', 'ruqya-complete']) {
        expect(controller.hasAudio(catalog.byId[id]!), isTrue, reason: id);
      }
      final item = catalog.byId['nawawi-01']!;
      await controller.play(item);
      await controller.download(item);
      await controller.toggleQueue(item.id);
      expect(controller.listeningQueue, isEmpty);
      expect(controller.media.catalog, isNull);
      expect(controller.media.handler, isNull);
      expect(controller.error, isNotNull);
      // Old saved queues can still remove entries that have no recording now.
      controller.listeningQueue.add(item.id);
      await controller.toggleQueue(item.id);
      expect(controller.listeningQueue, isEmpty);
    },
  );

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
      expect(catalog.children(null).length, 14);
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
  testWidgets('playback controls appear only for content with recordings', (
    tester,
  ) async {
    await pump(tester);
    for (final id in [
      'hisn-002',
      'nawawi-01',
      'name-01',
      'sunnah-hands',
      'hisn-001',
      'qdua-goodness',
      'ruqya-kursi',
    ]) {
      final item = catalog.byId[id]!;
      final playable = [
        'hisn-001',
        'qdua-goodness',
        'ruqya-kursi',
      ].contains(id);
      expect(controller.hasAudio(item), playable, reason: id);
      hostKey.currentState!.openItem(item);
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('استماع'),
        playable ? findsOneWidget : findsNothing,
        reason: id,
      );
      expect(
        find.byIcon(Icons.play_arrow),
        playable ? findsOneWidget : findsNothing,
        reason: id,
      );
      hostKey.currentState!.back();
      await tester.pumpAndSettle();
    }
    final silent = ReligiousItem({
      'id': 'silent-list',
      'type': 'playlist',
      'title': 'قائمة بلا صوت',
      'text': 'قراءة فقط',
      'source': 'مصدر',
      'sourceUrl': 'https://example.com',
      'categories': ['ruqya'],
      'related': ['nawawi-01'],
    });
    expect(controller.hasAudio(silent), isFalse);
    expect(controller.hasAudio(catalog.byId['ruqya-complete']!), isTrue);
    hostKey.currentState!.openItem(silent);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.text('تحميل الرقية كاملة'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'copy actions omit source metadata for every content type',
    (tester) async {
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pump(tester);
      for (final id in [
        'qdua-goodness',
        'hisn-001',
        'nawawi-02',
        'name-01',
        'sunnah-hands',
      ]) {
        final item = catalog.byId[id]!;
        hostKey.currentState!.openItem(item);
        await tester.pumpAndSettle();
        final button = find.byTooltip('نسخ');
        await Scrollable.ensureVisible(tester.element(button), alignment: .3);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(clipboardText, item.copyText);
        expect(clipboardText, isNot(contains(item.sourceUrl)));
        expect(clipboardText, isNot(contains(item.source)));
        if (item.type == 'hadith') {
          expect(clipboardText, isNot(contains('(رواه')));
        }
        hostKey.currentState!.back();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(seconds: 45)),
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
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 8)),
          );
        }
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
