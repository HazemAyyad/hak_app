import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/main.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/visual_audit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranRepository repository;
  late AppAppearance appearance;
  late QuranController quran;
  setUpAll(() async {
    await loadVisualAuditFonts();
    repository = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'app.language.v1': 'en'});
    final preferences = await SharedPreferences.getInstance();
    appearance = AppAppearance(preferences);
    quran = QuranController(
      initialRepository: repository,
      preferences: preferences,
    );
    await quran.load();
    quran.remember(repository.byKey['2:255']!);
  });
  tearDown(() {
    appearance.dispose();
    quran.dispose();
  });

  Future<void> pumpHome(WidgetTester tester, {double scale = 1.2}) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await appearance.setFontScale(scale);
    await tester.pumpWidget(
      HaqApp(
        showStartup: false,
        appearance: appearance,
        quranController: quran,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'home language icon switches available interfaces without changing the saved verse',
    (tester) async {
      await pumpHome(tester);
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.byTooltip('App language'), findsOneWidget);
      await tester.tap(find.byTooltip('App language'));
      await tester.pumpAndSettle();
      expect(find.text('Choose your language'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('haq-bottom-navigation')),
        findsOneWidget,
      );
      final arabic = find.byKey(const ValueKey('language-interface-ar'));
      await tester.scrollUntilVisible(
        arabic,
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(arabic);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('مرحبًا بك'), findsOneWidget);
      await tester.tap(find.byTooltip('لغة التطبيق'));
      await tester.pumpAndSettle();
      final english = find.byKey(const ValueKey('language-interface-en'));
      await tester.scrollUntilVisible(
        english,
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(english);
      await tester.pumpAndSettle();
      expect(appearance.preferences.getString('app.language.v1'), 'en');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Welcome'), findsOneWidget);
      expect(quran.lastVerse?.key, '2:255');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'English home search finds translated services and chapter names in both languages',
    (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byTooltip('Search Haq'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('haq-global-search'));
      await tester.enterText(field, 'Quran');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('search-feature-quran')),
        findsOneWidget,
      );
      await tester.enterText(field, 'Baqarah');
      await tester.pumpAndSettle();
      expect(find.text('Surah Al-Baqarah'), findsOneWidget);
      await tester.enterText(field, 'البقرة');
      await tester.pumpAndSettle();
      expect(find.text('Surah Al-Baqarah'), findsOneWidget);
      expect(quran.lastVerse!.text, repository.byKey['2:255']!.text);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('English home cards fit narrow enlarged light and dark screens', (
    tester,
  ) async {
    final report = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint(details.toDiagnosticsNode().toStringDeep());
      report?.call(details);
    };
    addTearDown(() => FlutterError.onError = report);
    for (final scale in [1.0, 1.2]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await appearance.setMode(mode);
        await pumpHome(tester, scale: scale);
        final scroll = find.byKey(const PageStorageKey('home-feed'));
        for (var i = 0; i < 9; i++) {
          expect(tester.takeException(), isNull);
          await tester.drag(scroll, const Offset(0, -280));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
  });
}
