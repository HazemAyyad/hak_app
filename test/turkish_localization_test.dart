import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/core/localization/app_localization.dart';
import 'package:haq_app/core/localization/bundled_localization.dart';
import 'package:haq_app/core/localization/interface_messages.dart';
import 'package:haq_app/core/localization/language_page.dart';

import 'quran_media_test.dart' show StubHttp;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every bundled interface key has Turkish text and identical arguments',
    () {
      final registry = jsonDecode(bundledUiJson) as Map;
      final asset = jsonDecode(
        File('assets/localization/ui.json').readAsStringSync(),
      );
      expect(registry, asset);
      final placeholder = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');
      final unsafe = RegExp(r'[<>\x00-\x08\x0b\x0c\x0e-\x1f]');
      for (final entry in registry.entries) {
        final text = entry.value['tr'] as String?;
        expect(text, isNotNull, reason: entry.key as String);
        expect(text!.trim(), isNotEmpty, reason: entry.key as String);
        List<String> arguments(String value) =>
            placeholder.allMatches(value).map((match) => match[0]!).toList()
              ..sort();
        expect(
          arguments(text),
          arguments(entry.value['ar'] as String),
          reason: entry.key as String,
        );
        expect(unsafe.hasMatch(text), false, reason: entry.key as String);
        expect(
          RegExp(r'[\u0600-\u06ff]').hasMatch(text),
          false,
          reason: entry.key as String,
        );
      }
    },
  );

  test(
    'Turkish is available offline, persists and resets content overrides',
    () async {
      SharedPreferences.setMockInitialValues({
        'app.language.v1': 'ar',
        'app.content.language.v1': 'en',
        'saved-verse-test': '2:255',
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = AppLocalization(prefs);
      addTearDown(controller.dispose);
      expect(
        controller.available.map((language) => language.code),
        contains('tr'),
      );
      expect(controller.localInterface('tr'), true);
      expect(controller.local('tr'), true);
      expect(controller.language.direction, TextDirection.rtl);
      await controller.selectContent('en');
      await controller.select('tr');
      expect(controller.code, 'tr');
      expect(controller.contentCode, 'tr');
      expect(controller.contentSelection, isNull);
      expect(controller.chosen, true);
      expect(controller.language.direction, TextDirection.ltr);
      expect(controller.text('nav.home'), 'Ana sayfa');
      expect(controller.text('feature.names'), 'Esmâ-i Hüsnâ');
      expect(controller.text('prayer.name.dhuhr'), 'Öğle');
      expect(controller.text('prayer.name.asr'), 'İkindi');
      expect(controller.text('quran.surah.2'), 'Bakara');
      expect(controller.text('source.meanings'), 'Meal');
      expect(prefs.getString('saved-verse-test'), '2:255');
      final directory = await Directory.systemTemp.createTemp(
        'haq-turkish-ui-',
      );
      final restored = AppLocalization(prefs, directory: directory);
      try {
        expect(restored.code, 'tr');
        await restored.initialize();
        expect(restored.code, 'tr');
        expect(restored.contentCode, 'tr');
        await restored.select('ar');
        expect(restored.contentCode, 'ar');
        expect(restored.language.direction, TextDirection.rtl);
      } finally {
        restored.dispose();
        await directory.delete();
      }
    },
  );

  test(
    'Turkish background notification messages preserve localized arguments',
    () {
      final messages = InterfaceMessages.bundled('tr');
      expect(messages.nativePayload['locale'], 'tr');
      expect(messages.nativePayload['direction'], 'ltr');
      expect(messages.text('native.stop'), 'Durdur');
      expect(
        messages.text('native.iqama', args: {'time': '05:00'}),
        'Kamete kalan süre\n05:00',
      );
      expect(
        messages.text('prayer.next', args: {'prayer': 'İkindi'}),
        'Sonraki namaz: İkindi',
      );
    },
  );

  testWidgets(
    'primary picker activates Turkish interface and content offline',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final dio = Dio(BaseOptions(baseUrl: 'https://offline.test'));
      dio.httpClientAdapter = StubHttp((_) => ResponseBody.fromString('', 503));
      final controller = AppLocalization(
        await SharedPreferences.getInstance(),
        dio: dio,
      );
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        LocalizationScope(
          controller: controller,
          child: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => MaterialApp(
              locale: controller.language.locale,
              supportedLocales: const [
                Locale('ar'),
                Locale('en'),
                Locale('tr'),
              ],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: const LanguagePage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final turkish = find.byKey(const ValueKey('language-interface-tr'));
      await tester.scrollUntilVisible(turkish, 150);
      await tester.tap(turkish);
      await tester.pumpAndSettle();
      expect(controller.code, 'tr');
      expect(controller.contentCode, 'tr');
      expect(find.text('Uygulama dili'), findsOneWidget);
      expect(find.text('Dilinizi seçin'), findsOneWidget);
      await tester.scrollUntilVisible(turkish, 150);
      expect(Directionality.of(tester.element(turkish)), TextDirection.ltr);
      expect(
        find.descendant(of: turkish, matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
      final arabic = find.byKey(const ValueKey('language-interface-ar'));
      await tester.ensureVisible(arabic);
      await tester.tap(arabic);
      await tester.pumpAndSettle();
      expect(controller.contentCode, 'ar');
      expect(controller.code, 'ar');
      expect(find.text('لغة التطبيق'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
