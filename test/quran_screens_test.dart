import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/data/quran_content.dart';
import 'package:haq_app/features/quran/data/quran_downloads.dart';
import 'package:haq_app/features/quran/data/quran_page_downloads.dart';
import 'package:haq_app/features/quran/data/quran_audio_models.dart';
import 'package:haq_app/features/quran/presentation/quran_host.dart';
import 'package:haq_app/features/quran/presentation/quran_download_pages.dart';
import 'package:haq_app/features/quran/presentation/quran_tafsir.dart';
import 'package:haq_app/features/quran/presentation/quran_home_sections.dart';
import 'package:haq_app/main.dart';

class PreviewContent extends QuranContent {
  @override
  Future<MushafPageData> page(int page, QuranRepository repo) async {
    if (page != 2) throw StateError('Not cached');
    return MushafPageData.parse(
      2,
      jsonDecode(File('test/fixtures/quran/page2.json').readAsStringSync())
          as Map<String, dynamic>,
      repo,
    );
  }

  @override
  Future<TafsirText> tafsir(String key, int source) async {
    final file = File('build/quran-fixtures/tafsir.json');
    final data = file.existsSync()
        ? jsonDecode(file.readAsStringSync())['tafsir'] as Map
        : {'text': '<p>نص المصدر في الاختبار</p>'};
    return TafsirText(source, tafsirSources[source]!, data['text'] as String, [
      key,
    ]);
  }

  @override
  Future<VerseMeanings> meanings(String key) async {
    final file = File('build/quran-fixtures/meanings.json');
    final data = file.existsSync()
        ? jsonDecode(file.readAsStringSync())['result'] as Map
        : {'translation': 'كلمة: معنى في الاختبار'};
    return VerseMeanings(data['translation'] as String, null);
  }
}

class ScreenDownloads extends QuranDownloads {
  ScreenDownloads(this.folder) : super(directory: folder);
  final Directory folder;
  @override
  Future<void> initialize() async {}
  @override
  Future<int> diskUsage() async => folder
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.mp3'))
      .fold<int>(0, (n, f) => n + f.lengthSync());
  @override
  Future<void> remove(String id) async {
    final entry = entries.remove(id);
    if (entry != null) {
      final file = File('${folder.path}/${entry.track.storageKey}.mp3');
      if (file.existsSync()) file.deleteSync();
    }
    notifyListeners();
  }
}

class ScreenPages extends QuranPageDownloads {
  ScreenPages(Directory folder) : super(directory: folder);
  @override
  Future<void> initialize() async {}
  @override
  Future<QuranOfflinePageData?> offlinePage(int page) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranController controller;
  late AppAppearance appearance;
  late Directory directory;
  final boundary = GlobalKey();
  setUpAll(() async {
    for (final font in [
      ('QuranUI', 'assets/fonts/Cairo.ttf'),
      ('AmiriQuran', 'assets/fonts/AmiriQuran.ttf'),
      ('Arial', 'assets/fonts/Cairo.ttf'),
      ('Roboto', 'assets/fonts/Cairo.ttf'),
      ('Ahem', 'assets/fonts/Cairo.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    for (final font in [
      ('QuranTajweedPage2', 'build/quran-fixtures/v4-p2.ttf'),
      (
        'MaterialIcons',
        'C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      final file = File(font.$2);
      if (file.existsSync()) {
        await (FontLoader(font.$1)..addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())),
            ))
            .load();
      }
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    directory = await Directory.systemTemp.createTemp('quran_screens_test_');
    controller = QuranController(
      initialRepository: QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
      preferences: prefs,
      content: PreviewContent(),
      downloads: ScreenDownloads(directory),
      pageDownloads: ScreenPages(directory),
    );
    await controller.load();
    controller.audio.catalog = QuranAudioCatalog.fromJson(
      jsonDecode(File('assets/quran/audio_catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    appearance = AppAppearance(prefs);
  });
  tearDown(() async {
    controller.dispose();
    appearance.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await directory.delete(recursive: true);
  });
  Future<void> showApp(
    WidgetTester tester, {
    Size size = const Size(430, 932),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/quran/mushaf_frame.png'),
        tester.element(find.byType(Scaffold).first),
      );
      for (final header in ['home', 'light', 'dark']) {
        await precacheImage(
          AssetImage('assets/quran/header_$header.png'),
          tester.element(find.byType(Scaffold).first),
        );
      }
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('القرآن').last);
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final output = Platform.environment['QURAN_CAPTURE_DIR'];
    if (output == null) return;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final png = await render.toImage(pixelRatio: 2);
      final bytes = await png.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      png.dispose();
    });
  }

  testWidgets(
    'daily Quran home card opens its displayed canonical verse in tafsir',
    (tester) async {
      await showApp(tester);
      await capture(tester, 'quran-home-merged');
      final daily = find.byType(QuranDailyVerse);
      await tester.scrollUntilVisible(
        daily,
        250,
        scrollable: find
            .descendant(
              of: find.byType(QuranHomePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final texts = find.descendant(of: daily, matching: find.byType(Text));
      final text = tester.widget<Text>(texts.at(1)).data!;
      final verse = controller.repository!.verses.singleWhere(
        (v) => v.text == text,
      );
      await capture(tester, 'quran-home-daily');
      await tester.tap(
        find.descendant(of: daily, matching: find.text('قراءة التفسير')),
      );
      await tester.pumpAndSettle();
      expect(find.text('تفسير الآية'), findsOneWidget);
      expect(find.text(verse.text), findsOneWidget);
      expect(
        find.text(
          'سورة ${controller.repository!.surah(verse.surah).name} • الآية ${verse.ayah}',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'fixed Mushaf pages select real verses and full screen preserves page',
    (tester) async {
      controller.setMode(QuranReadingMode.pages);
      await showApp(tester);
      final host = tester.state<QuranHostState>(find.byType(QuranHost));
      host.openReader(controller.repository!.byKey['2:2']!);
      await tester.pumpAndSettle();
      expect(find.text('تنزيل صفحات المصحف'), findsOneWidget);
      await tester.tap(find.text('لاحقًا'));
      await tester.pumpAndSettle();
      expect(find.text('الصفحة 2 من 604'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'fixed-page');
      await tester.tap(find.text('تكبير الصفحة'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('الصفحة 2 من 604'), findsOneWidget);
      await capture(tester, 'fixed-page-fullscreen');
      await tester.tap(find.byTooltip('إغلاق التكبير'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(controller.lastPage, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'audio downloads reader picker and account fit a narrow enlarged RTL interface',
    (tester) async {
      await appearance.setFontScale(1.2);
      await showApp(tester, size: const Size(360, 800));
      await controller.audio.initialize();
      await tester.pumpAndSettle();
      final host = tester.state<QuranHostState>(find.byType(QuranHost));
      host.openAudio();
      await tester.pumpAndSettle();
      expect(find.text('القرآن المسموع'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'audio-narrow');
      await tester.tap(find.byTooltip('رجوع').last);
      await tester.pumpAndSettle();
      host.openDownloads();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'downloads-narrow');
      await tester.tap(find.byTooltip('رجوع').last);
      await tester.pumpAndSettle();
      host.openAccount();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'account-narrow');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'ayah preview and four tafsir choices use the same verse and actual source',
    (tester) async {
      controller.setMode(QuranReadingMode.ayah);
      await showApp(tester);
      final host = tester.state<QuranHostState>(find.byType(QuranHost));
      host.openReader(controller.repository!.byKey['2:2']!);
      await tester.pumpAndSettle();
      expect(find.byType(QuranVerseInsight), findsOneWidget);
      expect(find.text('تشغيل الآية'), findsNothing);
      expect(find.byTooltip('تشغيل الآية'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'ayah-insight');
      await tester.tap(find.byTooltip('تفسير الآية'));
      await tester.pumpAndSettle();
      for (final name in tafsirSources.values) {
        expect(find.text(name), findsAtLeastNWidgets(1));
      }
      expect(tester.takeException(), isNull);
      await capture(tester, 'tafsir');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'cancel delete preserves audio and confirmation deletes only that file',
    (tester) async {
      await showApp(tester);
      await controller.audio.initialize();
      final track = controller.audio.selection().track(
        controller.repository!,
        1,
      );
      final file = File('${directory.path}/${track.storageKey}.mp3');
      await tester.runAsync(() => file.writeAsBytes(List.filled(256, 1)));
      controller.audio.downloads.entries[track.id] = QuranDownload(
        track,
        state: QuranDownloadState.complete,
        received: 256,
        total: 256,
      );
      controller.toggleFavorite('2:2');
      controller.toggleBookmark('2:3');
      var finished = false;
      final context = tester.element(find.byType(QuranHost));
      confirmAudioDelete(context, controller.audio, [
        controller.audio.downloads.entries[track.id]!,
      ]).then((_) => finished = true);
      await tester.pumpAndSettle();
      await capture(tester, 'delete-confirmation');
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(file.existsSync(), isTrue);
      expect(finished, isTrue);
      confirmAudioDelete(context, controller.audio, [
        controller.audio.downloads.entries[track.id]!,
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && file.existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(file.existsSync(), isFalse);
      expect(controller.favorites.containsKey('2:2'), isTrue);
      expect(controller.bookmarks.containsKey('2:3'), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'general settings opens the Quran account without changing navigation',
    (tester) async {
      await showApp(tester);
      await tester.tap(find.text('المزيد').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('الإعدادات'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الحساب والمزامنة'));
      await tester.pumpAndSettle();
      expect(find.text('الحساب والمزامنة'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
