import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/core/localization/app_localization.dart';
import 'package:haq_app/core/localization/bundled_source_card.dart';
import 'package:haq_app/core/localization/religious_translation_library.dart';
import 'quran_media_test.dart' show StubHttp;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'publisher links default hidden and follow server settings with stale update protection',
    (tester) async {
      SharedPreferences.setMockInitialValues({'app.language.v1': 'en'});
      var visible = true;
      var revision = 3;
      final dio = Dio(BaseOptions(baseUrl: 'https://backend.test'));
      dio.httpClientAdapter = StubHttp(
        (_) => ResponseBody.fromString(
          jsonEncode({
            'data': {
              'schema': 1,
              'languages': [],
              'settings': {
                'show_translation_source_links': visible,
                'revision': revision,
              },
            },
          }),
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
      final preferences = await SharedPreferences.getInstance();
      final localization = AppLocalization(preferences, dio: dio);
      final catalog =
          jsonDecode(File('assets/religious/catalog.json').readAsStringSync())
              as Map;
      final original =
          (catalog['items'] as List).firstWhere(
                (row) => row['id'] == 'nawawi-01',
              )['text']
              as String;
      await tester.runAsync(
        () => ReligiousTranslationLibrary.shared.load('en', 'hadith'),
      );
      await tester.pumpWidget(
        LocalizationScope(
          controller: localization,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: BundledSourceCard(
                  kind: 'hadith',
                  contentId: 'nawawi-01',
                  originalText: original,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(localization.showSourceLinks, false);
      expect(find.text('Open this publisher record'), findsNothing);
      expect(find.text('Publisher and source information'), findsNothing);
      await localization.applyPublicSettings({
        'show_translation_source_links': true,
        'revision': 1,
      });
      expect(localization.showSourceLinks, true);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      expect(find.text('Open this publisher record'), findsOneWidget);
      expect(find.text('Publisher and source information'), findsOneWidget);
      await localization.applyPublicSettings({
        'show_translation_source_links': false,
        'revision': 2,
      });
      await localization.applyPublicSettings({
        'show_translation_source_links': true,
        'revision': 1,
      });
      await tester.pumpAndSettle();
      expect(localization.showSourceLinks, false);
      expect(find.text('Open this publisher record'), findsNothing);
      await tester.runAsync(localization.refresh);
      await tester.pumpAndSettle();
      expect(localization.showSourceLinks, true);
      visible = false;
      revision = 4;
      await tester.runAsync(localization.refresh);
      await tester.pumpAndSettle();
      expect(find.text('Publisher and source information'), findsNothing);
      final restored = AppLocalization(preferences);
      expect(restored.showSourceLinks, false);
      restored.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      localization.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
