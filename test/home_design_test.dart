import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/main.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranRepository repository;
  late AppAppearance appearance;
  late QuranController quran;
  setUpAll(() async {
    repository = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    for (final font in [
      ('QuranUI', 'assets/fonts/Cairo.ttf'),
      ('Tajawal', 'assets/fonts/Tajawal-Regular.ttf'),
      ('AmiriQuran', 'assets/fonts/AmiriQuran.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter';
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
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
    appearance = AppAppearance(preferences);
    quran = QuranController(
      initialRepository: repository,
      preferences: preferences,
    );
    await quran.load();
  });
  tearDown(() {
    appearance.dispose();
    quran.dispose();
  });

  testWidgets(
    'Friday card keeps content and action visible at reduced text scale',
    (tester) async {
      var taps = 0;
      for (final font in [AppFont.cairo, AppFont.tajawal]) {
        await appearance.setFont(font);
        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: MaterialApp(
              theme: ThemeData(fontFamily: font.family),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(392.7, 800),
                  textScaler: TextScaler.linear(.85),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: 360.7,
                        child: FridayCard(onTap: () => taps++),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: font.id);
        await tester.tap(find.text('عرض المحتوى'));
      }
      expect(taps, 2);
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('home reference preview ${mode.name}', (tester) async {
      tester.view.physicalSize = const Size(412, 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await appearance.setMode(mode);
      // A real saved reading fixture; the app still starts empty for new users.
      quran.remember(repository.byKey['2:255']!);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: HaqApp(
            showStartup: false,
            appearance: appearance,
            quranController: quran,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        for (final asset in [
          'assets/home/header_light.png',
          'assets/home/header_dark.png',
          'assets/home/reading.png',
          'assets/home/dawn.png',
          'assets/home/lantern.png',
          'assets/branding/haq_logo_transparent.png',
        ]) {
          await precacheImage(
            AssetImage(asset),
            key.currentContext!,
          ).timeout(const Duration(seconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('الآية 255'), findsOneWidget);
      expect(find.text('محتوى اليوم'), findsOneWidget);
      expect(find.text('سورة الطلاق - الآية 4'), findsOneWidget);
      expect(find.text('مقالة'), findsNWidgets(2));
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary
            .toImage(pixelRatio: 1.5)
            .timeout(const Duration(seconds: 10));
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('build/home-preview');
        await directory.create(recursive: true);
        await File(
          '${directory.path}/${mode.name}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });

    for (final font in [AppFont.cairo, AppFont.tajawal]) {
      testWidgets('home narrow enlarged text ${mode.name} ${font.id}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await appearance.setMode(mode);
        await appearance.setFont(font);
        await appearance.setFontScale(1.2);
        await tester.pumpWidget(
          HaqApp(
            showStartup: false,
            appearance: appearance,
            quranController: quran,
          ),
        );
        await tester.pumpAndSettle();
        final scroll = find.byType(CustomScrollView).first;
        for (var i = 0; i < 6; i++) {
          expect(tester.takeException(), isNull);
          await tester.drag(scroll, const Offset(0, -350));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
