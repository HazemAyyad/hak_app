import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_experience.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/features/quran/data/quran_audio.dart';
import 'package:haq_app/features/quran/data/quran_audio_models.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/presentation/quran_audio_widgets.dart';

class NavigationTestMedia extends QuranMedia {
  NavigationTestMedia()
    : super(
        repository: () => QuranRepository.fromJson(
          jsonDecode(File('assets/quran/quran.json').readAsStringSync())
              as Map<String, dynamic>,
        ),
        preferences: () => throw UnimplementedError(),
      );
  bool started = false, paused = false;
  int serial = 0, stops = 0;
  Duration elapsed = Duration.zero;
  @override
  QuranAudioTrack? get current => started
      ? QuranAudioTrack(
          id: 'test-$serial',
          recitation: 'test',
          reciter: 'قارئ الاختبار',
          title: 'المقطع الجاري',
          surah: 1,
          url: 'https://example.com/test.mp3',
          version: '1',
          quality: 'test',
        )
      : null;
  @override
  bool get playing => started && !paused;
  @override
  bool get buffering => false;
  @override
  int get playbackSession => serial;
  @override
  Duration get position => elapsed;
  @override
  Duration? get duration => const Duration(seconds: 100);
  void begin() {
    started = true;
    paused = false;
    serial++;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stops++;
    started = false;
    notifyListeners();
  }

  @override
  Future<void> toggle() async {
    paused = !paused;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    elapsed = value;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Tajawal',
    )..addFont(rootBundle.load('assets/fonts/Tajawal-Regular.ttf'))).load();
    await (FontLoader(
      'QuranUI',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    await (FontLoader(
      'AmiriQuran',
    )..addFont(rootBundle.load('assets/fonts/AmiriQuran.ttf'))).load();
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
  late AppExperienceController controller;
  late NavigationTestMedia audio;
  late AppAppearance appearance;
  late NavigatorObserver rootObserver, nestedObserver;
  final nested = GlobalKey<NavigatorState>();
  final previewKey = GlobalKey();
  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('RELIGIOUS_PREVIEWS')) return;
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      void repaint(RenderObject object) {
        object.markNeedsPaint();
        object.visitChildren(repaint);
      }

      repaint(previewKey.currentContext!.findRenderObject()!);
      await tester.pump();
      await tester.runAsync(() async {
        final boundary =
            previewKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/experience-preview').create(recursive: true);
        await File(
          'build/experience-preview/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    } finally {
      debugDisableShadows = previousShadows;
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appearance = AppAppearance(await SharedPreferences.getInstance());
    controller = AppExperienceController();
    audio = NavigationTestMedia();
    rootObserver = controller.observer('root');
    nestedObserver = controller.observer('quran');
    controller.register(audio);
    controller.surface = 'quran';
  });
  tearDown(() {
    controller.dispose();
    audio.dispose();
    appearance.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    double width = 426,
    double scale = 1,
    bool withPlayer = false,
  }) async {
    tester.view.physicalSize = Size(width, 922);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: 'Tajawal',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF075158)),
        ),
        navigatorKey: controller.navigatorKey,
        navigatorObservers: [rootObserver],
        builder: (context, child) => AppearanceScope(
          controller: appearance,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(
              key: previewKey,
              child: AppExperienceOverlay(
                controller: controller,
                child: child!,
              ),
            ),
          ),
        ),
        home: Scaffold(
          body: Navigator(
            key: nested,
            observers: [nestedObserver],
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => SingleChildScrollView(
                child: Column(
                  children: [
                    TextButton(
                      child: const Text('الانتقال'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const Scaffold(
                            body: Center(child: Text('صفحة ثانية')),
                          ),
                        ),
                      ),
                    ),
                    if (withPlayer)
                      QuranPlayerPanel(
                        media: audio,
                        repository: audio.repository(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('nested routes and root settings both show navigation feedback', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('الانتقال'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('app-navigation-loader')), findsOneWidget);
    await capture(tester, 'navigation-loader');
    await tester.pumpAndSettle();
    expect(find.text('صفحة ثانية'), findsOneWidget);
    nested.currentState!.pop();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('app-navigation-loader')), findsOneWidget);
    await tester.pumpAndSettle();
    controller.navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('الإعدادات')),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('app-navigation-loader')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(controller.hasBottomBar, isFalse);
  });

  testWidgets('minimize and leaving share one player and preserve playback', (
    tester,
  ) async {
    await pump(tester, width: 320, scale: 1.3, withPlayer: true);
    audio.begin();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('تصغير المشغل'));
    await tester.pumpAndSettle();
    final dock = find.byKey(const ValueKey('app-playback-dock'));
    expect(dock, findsOneWidget);
    final before = tester.widget<QuranPlayerPanel>(
      find.descendant(of: dock, matching: find.byType(QuranPlayerPanel)),
    );
    expect(before.media, same(audio));
    expect(before.compact, isTrue);
    await audio.seek(const Duration(seconds: 37));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: dock, matching: find.text('المقطع الجاري')),
    );
    await tester.pumpAndSettle();
    expect(dock, findsNothing);
    expect(find.byTooltip('تصغير المشغل'), findsOneWidget);
    await capture(tester, 'audio-full-sheet');
    await tester.tap(find.byTooltip('تصغير المشغل').last);
    await tester.pumpAndSettle();
    expect(dock, findsOneWidget);
    expect(audio.elapsed.inSeconds, 37);
    expect(audio.serial, 1);
    await tester.tap(find.text('الانتقال'));
    await tester.pumpAndSettle();
    expect(find.text('متابعة الاستماع؟'), findsNothing);
    expect(dock, findsOneWidget);
    expect(audio.elapsed.inSeconds, 37);
    expect(tester.takeException(), isNull);
  });

  testWidgets('minimizing on the original page survives navigation and pause', (
    tester,
  ) async {
    await pump(tester);
    audio.begin();
    await tester.pumpAndSettle();
    controller.minimize(audio);
    await tester.pumpAndSettle();
    expect(find.byType(AppPlaybackDock), findsOneWidget);
    await audio.toggle();
    await tester.tap(find.text('الانتقال'));
    await tester.pumpAndSettle();
    expect(find.text('متابعة الاستماع؟'), findsNothing);
    expect(find.byType(AppPlaybackDock), findsOneWidget);
    expect(audio.playing, isFalse);
    nested.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AppPlaybackDock), findsOneWidget);
  });

  testWidgets(
    'leaving audio page asks once and No stops and removes playback',
    (tester) async {
      await pump(tester);
      audio.begin();
      await tester.pumpAndSettle();
      await tester.tap(find.text('الانتقال'));
      await tester.pumpAndSettle();
      expect(find.text('متابعة الاستماع؟'), findsOneWidget);
      await tester.tap(find.text('لا، إيقاف الصوت'));
      await tester.pumpAndSettle();
      expect(audio.stops, 1);
      expect(audio.playing, isFalse);
      expect(find.byKey(const ValueKey('app-playback-dock')), findsNothing);
    },
  );

  testWidgets(
    'Yes keeps one RTL dock across destinations, collapse, seek and stop',
    (tester) async {
      await pump(tester, width: 320, scale: 1.3);
      audio.begin();
      await tester.pumpAndSettle();
      await tester.tap(find.text('الانتقال'));
      await tester.pumpAndSettle();
      await capture(tester, 'audio-leave-confirmation');
      await tester.tap(find.text('نعم، متابعة الاستماع'));
      await tester.pumpAndSettle();
      expect(audio.playing, isTrue);
      await capture(tester, 'audio-expanded-rtl');
      expect(find.byKey(const ValueKey('app-playback-dock')), findsOneWidget);
      final slider = find.byKey(const ValueKey('app-playback-seek'));
      expect(Directionality.of(tester.element(slider)), TextDirection.rtl);
      final bounds = tester.getRect(slider);
      await tester.tapAt(Offset(bounds.left + 20, bounds.center.dy));
      await tester.pumpAndSettle();
      expect(audio.position.inSeconds, greaterThan(50));
      await tester.tap(find.byTooltip('طي المشغل'));
      await tester.pumpAndSettle();
      await capture(tester, 'audio-collapsed');
      expect(slider, findsNothing);
      await tester.tap(find.byTooltip('توسيع المشغل'));
      await tester.pumpAndSettle();
      expect(slider, findsOneWidget);
      controller.changeSurface('more');
      await tester.pumpAndSettle();
      expect(find.text('متابعة الاستماع؟'), findsNothing);
      expect(find.byKey(const ValueKey('app-playback-dock')), findsOneWidget);
      await tester.tap(find.byTooltip('إغلاق المشغل وإيقاف الصوت'));
      await tester.pumpAndSettle();
      expect(audio.stops, 1);
      expect(find.byKey(const ValueKey('app-playback-dock')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'returning to original page hides dock and asks on next departure',
    (tester) async {
      await pump(tester);
      audio.begin();
      await tester.pumpAndSettle();
      await tester.tap(find.text('الانتقال'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('نعم، متابعة الاستماع'));
      await tester.pumpAndSettle();
      nested.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-playback-dock')), findsNothing);
      await tester.tap(find.text('الانتقال'));
      await tester.pumpAndSettle();
      expect(find.text('متابعة الاستماع؟'), findsOneWidget);
      await tester.tap(find.text('لا، إيقاف الصوت'));
      await tester.pumpAndSettle();
      expect(audio.playing, isFalse);
    },
  );

  testWidgets('popup menus do not count as leaving; new audio asks again', (
    tester,
  ) async {
    await pump(tester);
    audio.begin();
    await tester.pumpAndSettle();
    showDialog<void>(
      context: controller.navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text('قائمة'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('متابعة الاستماع؟'), findsNothing);
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الانتقال'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نعم، متابعة الاستماع'));
    await tester.pumpAndSettle();
    audio.begin();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-playback-dock')), findsNothing);
    nested.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('متابعة الاستماع؟'), findsOneWidget);
    await tester.tap(find.text('لا، إيقاف الصوت'));
    await tester.pumpAndSettle();
  });
}
