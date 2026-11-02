import 'dart:convert';
import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/presentation/quran_widgets.dart';
import 'package:haq_app/main.dart';
import 'package:haq_app/settings_pages.dart';
import 'package:haq_app/startup/onboarding_screen.dart';
import 'package:haq_app/startup/splash_screen.dart';
import 'package:haq_app/startup/startup_flow.dart';
import 'package:haq_app/core/localization/language_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppAppearance appearance;
  late QuranController quran;
  late QuranRepository repository;

  setUpAll(() async {
    repository = QuranRepository.fromJson(
      jsonDecode(io.File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    await (FontLoader(
      'QuranUI',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    final icons = io.File(
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
    'splash shows the transparent logo in full color and finishes once',
    (tester) async {
      var completions = 0;
      await tester.pumpWidget(
        MaterialApp(home: SplashScreen(onFinished: () => completions++)),
      );
      await _loadSplash(tester);
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        'assets/branding/haq_splash_logo.png',
      );
      expect(image.color, isNull);
      final bundled = await rootBundle.load(
        'assets/branding/haq_splash_logo.png',
      );
      expect(
        bundled.buffer.asUint8List(
          bundled.offsetInBytes,
          bundled.lengthInBytes,
        ),
        io.File('assets/branding/haq_splash_logo.png').readAsBytesSync(),
        reason:
            'The rendered bundle must contain the current approved artwork.',
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(completions, 0);
      await tester.pump(const Duration(milliseconds: 1900));
      expect(completions, 1);
      await tester.pump(const Duration(seconds: 3));
      expect(completions, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'first launch selects a language before onboarding; completion survives restart',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: HaqApp(appearance: appearance, quranController: quran),
        ),
      );
      await _loadSplash(tester);
      expect(find.byType(SplashScreen), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await _capture(tester, key, 'splash');
      await tester.pump(const Duration(milliseconds: 2700));
      await tester.pumpAndSettle();
      expect(find.byType(LanguagePage), findsOneWidget);
      await tester.tap(find.text('العربية'));
      await tester.pumpAndSettle();
      expect(find.text('1 من 3'), findsOneWidget);
      expect(
        appearance.preferences.getBool(StartupFlow.onboardingKey),
        isNot(true),
      );
      await _capture(tester, key, 'onboarding-1');
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();
      expect(find.text('2 من 3'), findsOneWidget);
      expect(
        tester.getCenter(find.byTooltip('رجوع')).dx,
        greaterThan(tester.getCenter(find.text('تخطي')).dx),
      );
      await _capture(tester, key, 'onboarding-2');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('1 من 3'), findsOneWidget);
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();
      expect(find.text('3 من 3'), findsOneWidget);
      await _capture(tester, key, 'onboarding-3');
      await tester.tap(find.text('ابدأ الآن'));
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
      expect(appearance.preferences.getBool(StartupFlow.onboardingKey), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final restored = AppAppearance(appearance.preferences);
      await tester.pumpWidget(
        HaqApp(appearance: restored, quranController: quran),
      );
      await _loadSplash(tester);
      await tester.pump(const Duration(milliseconds: 2700));
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      restored.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'skip persists completion and reduced motion keeps startup usable',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        HaqApp(appearance: appearance, quranController: quran),
      );
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await tester.tap(find.text('العربية'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تخطي'));
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
      expect(appearance.preferences.getBool(StartupFlow.onboardingKey), isTrue);
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('onboarding fits narrow enlarged RTL ${mode.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await appearance.setMode(mode);
      await appearance.setFontScale(1.2);
      await tester.pumpWidget(
        AppearanceScope(
          controller: appearance,
          child: MaterialApp(
            theme: ThemeData(
              brightness: mode == ThemeMode.dark
                  ? Brightness.dark
                  : Brightness.light,
              fontFamily: 'QuranUI',
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.2)),
              child: child!,
            ),
            home: OnboardingScreen(onComplete: () async {}),
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (i < 2) await tester.tap(find.text('التالي'));
      }
    });
  }

  testWidgets('Quran and settings back controls are on the right', (
    tester,
  ) async {
    await tester.pumpWidget(
      AppearanceScope(
        controller: appearance,
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: QuranHeader(
              title: 'اختبار',
              subtitle: '',
              onBack: () {},
              actions: [
                QCircleButton(icon: Icons.search, label: 'بحث', onTap: () {}),
                QCircleButton(
                  icon: Icons.settings_outlined,
                  label: 'إعدادات',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getCenter(find.byTooltip('رجوع')).dx,
      greaterThan(tester.getCenter(find.byTooltip('بحث')).dx),
    );
    expect(
      tester.getCenter(find.byTooltip('رجوع')).dx,
      greaterThan(tester.getCenter(find.byTooltip('إعدادات')).dx),
    );
    expect(
      Directionality.of(tester.element(find.byIcon(Icons.arrow_back_ios_new))),
      TextDirection.rtl,
    );
    await tester.pumpWidget(
      HaqApp(
        showStartup: false,
        appearance: appearance,
        quranController: quran,
      ),
    );
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const SettingsDetailPage(kind: SettingKind.appearance),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byIcon(Icons.arrow_back_ios_new)).dx,
      greaterThan(
        tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
      ),
    );
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDetailPage), findsNothing);
  });
}

Future<void> _loadSplash(WidgetTester tester) async {
  final image = find.descendant(
    of: find.byType(SplashScreen),
    matching: find.byType(Image),
  );
  expect(image, findsOneWidget);
  await tester.runAsync(
    () =>
        precacheImage(tester.widget<Image>(image).image, tester.element(image)),
  );
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    for (final asset in [
      'assets/branding/haq_splash_logo.png',
      'assets/quran/quran_cover.png',
    ]) {
      await precacheImage(AssetImage(asset), key.currentContext!);
    }
  });
  await tester.pump();
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = io.Directory('build/startup-preview');
    await directory.create(recursive: true);
    await io.File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
