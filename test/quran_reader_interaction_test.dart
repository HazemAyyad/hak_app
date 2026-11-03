import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/core/localization/app_localization.dart';
import 'package:haq_app/main.dart';
import 'package:haq_app/features/quran/data/quran_content.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_page_downloads.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/presentation/quran_host.dart';
import 'package:haq_app/features/quran/presentation/quran_mushaf.dart';
import 'package:haq_app/features/quran/presentation/quran_mushaf_line.dart';
import 'package:haq_app/features/quran/presentation/quran_offline_page.dart';
import 'package:haq_app/features/quran/presentation/quran_page_viewport.dart';
import 'package:haq_app/features/quran/presentation/quran_reader_player.dart';
import 'package:haq_app/features/quran/presentation/quran_reader.dart';
import 'package:haq_app/features/quran/presentation/quran_widgets.dart';

class ReaderContent extends QuranContent {
  final pageRequests = <int>[];
  @override
  Future<MushafPageData> page(
    int page,
    QuranRepository repository, {
    bool originalFont = true,
  }) async {
    pageRequests.add(page);
    if (page == 2) {
      return MushafPageData.parse(
        2,
        jsonDecode(File('test/fixtures/quran/page2.json').readAsStringSync())
            as Map<String, dynamic>,
        repository,
      );
    }
    final verse = repository.verses.firstWhere((v) => v.page == page);
    return MushafPageData(page, [
      for (var i = 1; i <= 15; i++)
        MushafWord(
          key: verse.key,
          position: i,
          line: i,
          glyph: verse.text,
          text: verse.text,
        ),
    ]);
  }

  @override
  Future<TafsirText> tafsir(String key, int source) async => TafsirText(
    source,
    tafsirSources[source]!,
    '<p>تفسير الاختبار</p>',
    [key],
  );
  @override
  Future<VerseMeanings> meanings(String key) async => VerseMeanings('', null);
}

class ReaderPages extends QuranPageDownloads {
  ReaderPages() : super(directory: Directory.systemTemp);
  final saved = <int, QuranOfflinePageData>{};
  final requested = <Set<int>>[];
  @override
  Future<void> enqueue(Iterable<int> pages) async {
    final selected = pages.toSet();
    requested.add(selected);
    for (final page in selected) {
      entries[page] = QuranPageDownload(
        page,
        state: QuranPageDownloadState.paused,
      );
    }
    notifyListeners();
  }

  @override
  Future<void> initialize() async {}
  @override
  bool hasPage(int page) => saved.containsKey(page);
  @override
  Future<QuranOfflinePageData?> offlinePage(int page) async => saved[page];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranRepository repository;
  late QuranController controller;
  late AppAppearance appearance;
  late ReaderPages pages;
  final boundary = GlobalKey();

  setUpAll(() async {
    repository = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    await (FontLoader(
      'QuranUI',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    final icons = File(
      'C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(icons.readAsBytesSync())),
          ))
          .load();
    }
    for (final family in [
      'AmiriQuran',
      'QuranTajweedPage1',
      'QuranTajweedPage3',
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/AmiriQuran.ttf'))).load();
    }
    await (FontLoader(
      'QuranTajweedPage2',
    )..addFont(rootBundle.load('assets/fonts/AmiriQuran.ttf'))).load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    pages = ReaderPages();
    controller = QuranController(
      initialRepository: repository,
      preferences: prefs,
      content: ReaderContent(),
      pageDownloads: pages,
    );
    await controller.load();
    appearance = AppAppearance(prefs);
  });
  tearDown(() {
    controller.dispose();
    appearance.dispose();
  });

  Future<void> open(
    WidgetTester tester,
    String key,
    QuranReadingMode mode, {
    String language = 'ar',
    double width = 430,
  }) async {
    tester.view.physicalSize = Size(width, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    controller.setMode(mode);
    await controller.preferences!.setString('app.language.v1', language);
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
    await tester.tap(find.text(language == 'en' ? 'Quran' : 'القرآن').last);
    await tester.pumpAndSettle();
    tester
        .state<QuranHostState>(find.byType(QuranHost))
        .openReader(repository.byKey[key]!);
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final output = Platform.environment['QURAN_CAPTURE_DIR'];
    if (output == null) return;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final screenshot = await render.toImage(pixelRatio: 2);
      final bytes = await screenshot.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      screenshot.dispose();
    });
  }

  testWidgets(
    'English narrow reader keeps Arabic scripture and the selected verse across language changes',
    (tester) async {
      await open(
        tester,
        '1:1',
        QuranReadingMode.continuous,
        language: 'en',
        width: 320,
      );
      expect(find.text('Surah Al-Fatihah in full'), findsOneWidget);
      expect(find.byTooltip('Hide header'), findsOneWidget);
      final original = repository.byKey['1:1']!.text;
      expect(
        tester.widget<Text>(find.text(original)).textDirection,
        TextDirection.rtl,
      );
      await tester.tap(find.byKey(const ValueKey('quran-select-1:3')));
      await tester.pumpAndSettle();
      expect(find.text('Verse 3'), findsOneWidget);
      expect(find.text('Surah Al-Fatihah • verse 3'), findsOneWidget);
      final localization = LocalizationScope.maybeOf(
        tester.element(find.byType(QuranReader)),
      )!;
      await localization.select('ar');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<QuranReaderPlayer>(find.byType(QuranReaderPlayer))
            .selected
            ?.key,
        '1:3',
      );
      expect(find.text(original), findsOneWidget);
      expect(find.byTooltip('إخفاء الهيدر'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('English pages open directly without a page download choice', (
    tester,
  ) async {
    await open(
      tester,
      '2:2',
      QuranReadingMode.pages,
      language: 'en',
      width: 320,
    );
    expect(find.text('Download mushaf pages'), findsNothing);
    expect(pages.requested, isEmpty);
    expect(find.byType(QuranMushaf), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'English reading settings change only the selected layout and font',
    (tester) async {
      await open(
        tester,
        '1:1',
        QuranReadingMode.continuous,
        language: 'en',
        width: 320,
      );
      final original = repository.byKey['1:1']!.text;
      await tester.tap(find.byTooltip('Go to'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reading settings'));
      await tester.pumpAndSettle();
      expect(find.text('Continuous text'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Amiri Quran'),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Amiri Quran'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Naskh — Noto').last);
      await tester.pumpAndSettle();
      expect(controller.scriptFont, QuranScriptFont.noto);
      expect(controller.mode, QuranReadingMode.continuous);
      expect(controller.repository!.byKey['1:1']!.text, original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'surah starts unselected and header can be hidden without losing navigation',
    (tester) async {
      await open(tester, '1:1', QuranReadingMode.continuous);
      expect(
        tester
            .widget<QuranReaderPlayer>(find.byType(QuranReaderPlayer))
            .selected,
        isNull,
      );
      expect(find.text('سورة الفاتحة كاملة'), findsOneWidget);
      expect(find.byType(QuranHeader), findsOneWidget);
      await capture(tester, 'fatiha-implemented');
      final ayah = find.byKey(const ValueKey('quran-select-1:3'));
      await tester.tap(ayah);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<QuranReaderPlayer>(find.byType(QuranReaderPlayer))
            .selected
            ?.key,
        '1:3',
      );
      expect(find.text('نسخ الآية'), findsNothing);
      await tester.tap(ayah);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<QuranReaderPlayer>(find.byType(QuranReaderPlayer))
            .selected,
        isNull,
      );
      await tester.tap(find.byTooltip('إخفاء الهيدر'));
      await tester.pumpAndSettle();
      expect(find.byType(QuranHeader), findsNothing);
      expect(find.byTooltip('رجوع'), findsOneWidget);
      await capture(tester, 'fatiha-header-hidden');
      await tester.tap(find.text('انتقال'));
      await tester.pumpAndSettle();
      expect(find.text('إعدادات القراءة'), findsOneWidget);
      expect(find.byType(DropdownButton<int>), findsNWidgets(3));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('إظهار الهيدر'));
      await tester.pumpAndSettle();
      expect(find.byType(QuranHeader), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'ayah taps toggle selection, long press opens options, and swipes cross surahs',
    (tester) async {
      await open(tester, '1:7', QuranReadingMode.ayah);
      await tester.tap(find.text(repository.byKey['1:7']!.text));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<QuranReaderPlayer>(find.byType(QuranReaderPlayer))
            .selected
            ?.key,
        '1:7',
      );
      expect(find.text('نسخ الآية'), findsNothing);
      await tester.tap(find.text(repository.byKey['1:7']!.text));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<QuranReaderPlayer>(find.byType(QuranReaderPlayer))
            .selected,
        isNull,
      );
      await tester.longPress(find.text(repository.byKey['1:7']!.text));
      await tester.pumpAndSettle();
      expect(find.text('نسخ الآية'), findsOneWidget);
      expect(find.text('سورة الفاتحة • الآية 7'), findsNWidgets(2));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('quran-ayah-swipe')),
        const Offset(240, 0),
      );
      await tester.pumpAndSettle();
      expect(controller.lastKey, '2:1');
      await tester.drag(
        find.byKey(const ValueKey('quran-ayah-swipe')),
        const Offset(-240, 0),
      );
      await tester.pumpAndSettle();
      expect(controller.lastKey, '1:7');
      await tester.scrollUntilVisible(
        find.text('الآية التالية'),
        250,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('quran-ayah-swipe')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        tester.getCenter(find.text('الآية السابقة')).dx,
        greaterThan(tester.getCenter(find.text('الآية التالية')).dx),
      );
      await tester.tap(find.text('الآية التالية'));
      await tester.pumpAndSettle();
      expect(controller.lastKey, '2:1');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'parent page changes do not notify the reader during build or reset its verse',
    (tester) async {
      var page = 2;
      var selected = '2:3';
      final notifications = <int>[];
      late StateSetter update;
      await tester.pumpWidget(
        AppearanceScope(
          controller: appearance,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return QuranMushaf(
                    content: controller.content,
                    repository: repository,
                    page: page,
                    selected: selected,
                    paper: Colors.white,
                    ink: Colors.black,
                    downloads: pages,
                    onPage: (value) => setState(() {
                      notifications.add(value);
                      page = value;
                      selected = repository.verses
                          .firstWhere((verse) => verse.page == value)
                          .key;
                    }),
                    onSelect: (_) {},
                    onOptions: (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      update(() {
        page = 3;
        selected = '2:17';
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(notifications, isEmpty);
      expect(selected, '2:17');
      await tester.drag(
        find.byKey(const ValueKey('quran-mushaf-pages')),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();
      expect(notifications, isNotEmpty);
      expect(page, greaterThan(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'page taps toggle exact ayahs, options remain available, and page swipes agree',
    (tester) async {
      await open(tester, '2:2', QuranReadingMode.pages);
      expect(find.text('تنزيل صفحات المصحف'), findsNothing);
      expect(pages.requested, isEmpty);
      final back = find.byTooltip('رجوع').last;
      expect(tester.getCenter(back).dx, greaterThan(370));
      expect(tester.getCenter(find.byIcon(Icons.fullscreen)).dx, lessThan(100));
      final data = await controller.content.page(2, repository);
      final word = data.words.firstWhere((w) => w.key == '2:2');
      await tester.tap(find.text(word.glyph));
      await tester.pumpAndSettle();
      expect(
        tester.widget<QuranMushaf>(find.byType(QuranMushaf)).selected,
        '2:2',
      );
      await tester.tap(find.text(word.glyph));
      await tester.pumpAndSettle();
      expect(
        tester.widget<QuranMushaf>(find.byType(QuranMushaf)).selected,
        isNull,
      );
      await tester.longPress(find.text(word.glyph));
      await tester.pumpAndSettle();
      expect(find.text('سورة البقرة • الآية 2'), findsNWidgets(2));
      expect(find.text('نسخ الآية'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('mushaf-viewport-2')),
        const Offset(250, 0),
      );
      await tester.pumpAndSettle();
      expect(controller.lastPage, 3);
      await tester.drag(
        find.byKey(const ValueKey('mushaf-viewport-3')),
        const Offset(-250, 0),
      );
      await tester.pumpAndSettle();
      expect(controller.lastPage, 2);
      await tester.tap(find.byTooltip('الصفحة السابقة'));
      await tester.pumpAndSettle();
      expect(controller.lastPage, 1);
      await tester.tap(find.byTooltip('الصفحة التالية'));
      await tester.pumpAndSettle();
      expect(controller.lastPage, 2);
      expect(find.byType(QuranMushaf), findsOneWidget);
      final viewport = find.byKey(const ValueKey('mushaf-viewport-2'));
      expect(tester.widget<QuranPageViewport>(viewport).page, 2);
      final focus = tester.getRect(viewport).topCenter + const Offset(0, 100);
      final first = await tester.startGesture(
        focus - const Offset(30, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        focus + const Offset(30, 0),
        pointer: 2,
      );
      await first.moveTo(focus - const Offset(80, 0));
      await second.moveTo(focus + const Offset(80, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      final viewer = find.descendant(
        of: viewport,
        matching: find.byType(InteractiveViewer),
      );
      expect(
        tester
            .widget<InteractiveViewer>(viewer)
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        greaterThan(1),
      );
      await tester.drag(viewport, const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(
        controller.lastPage,
        2,
        reason: 'Panning a magnified page must not flip it',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'legacy monochrome SVG cannot replace the bundled colored Mushaf',
    (tester) async {
      pages.saved[1] = QuranOfflinePageData.parse(
        1,
        File('test/fixtures/quran/offline001.svg').readAsStringSync(),
        jsonDecode(
          File('test/fixtures/quran/offline001.json').readAsStringSync(),
        ),
      );
      await open(tester, '1:7', QuranReadingMode.pages);
      expect(find.byType(QuranOfflinePage), findsNothing);
      expect(find.byType(MushafCanvas), findsWidgets);
      expect((controller.content as ReaderContent).pageRequests, contains(1));
      expect(find.text('تنزيل صفحات المصحف'), findsNothing);
      final word = (await controller.content.page(1, repository)).words.first;
      await tester.tap(find.text(word.glyph).first);
      await tester.pumpAndSettle();
      expect(controller.lastKey, word.key);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'long physical Mushaf lines fit at fractional sizes without overflow and direct taps select exact ayahs',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final verse = repository.byKey['2:2']!;
      final words = [
        for (var i = 1; i < 24; i++)
          MushafWord(
            key: verse.key,
            position: i,
            line: 14,
            glyph: verse.text.split(' ')[i % verse.text.split(' ').length],
            text: verse.text,
          ),
      ];
      String? chosen, options;
      for (final size in [35.0, 34.9997, 35.0003, 44.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 443.99776,
                    height: 42.4,
                    child: QuranMushafLine(
                      words: words,
                      fontFamily: 'AmiriQuran',
                      fontSize: size,
                      centered: false,
                      selected: '2:1',
                      repository: repository,
                      onSelect: (v) => chosen = v.key,
                      onOptions: (v) => options = v.key,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(words.first.glyph).first);
        await tester.pump();
        expect(chosen, '2:2');
        expect(options, isNull);
        await tester.longPress(find.text(words.first.glyph).first);
        expect(options, '2:2');
        options = null;
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
