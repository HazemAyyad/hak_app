import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/core/localization/app_localization.dart';
import 'package:haq_app/core/localization/bundled_source_card.dart';
import 'package:haq_app/core/localization/language_page.dart';
import 'package:haq_app/core/localization/published_hadith_card.dart';
import 'package:haq_app/core/localization/religious_translation_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originals = {
    for (final row
        in jsonDecode(
              File('assets/religious/catalog.json').readAsStringSync(),
            )['items']
            as List)
      row['id'] as String: row['text'] as String,
  };
  final library = ReligiousTranslationLibrary.shared;

  test(
    'Arabic startup ignores a legacy translation override without changing reading progress',
    () async {
      SharedPreferences.setMockInitialValues({
        'app.language.v1': 'ar',
        'app.content.language.v1': 'en',
        'saved-verse-test': '2:255',
      });
      final prefs = await SharedPreferences.getInstance();
      final localization = AppLocalization(prefs);
      expect(localization.code, 'ar');
      expect(localization.contentCode, 'ar');
      expect(localization.contentSelection, isNull);
      expect(prefs.getString('saved-verse-test'), '2:255');
      localization.dispose();
    },
  );

  test(
    'primary language selection including reselecting Arabic resets a separate content choice',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final localization = AppLocalization(prefs);
      await localization.selectContent('tr');
      expect(localization.contentCode, 'tr');
      await localization.select('ar');
      expect(localization.contentCode, 'ar');
      expect(localization.contentSelection, isNull);
      await localization.selectContent('tr');
      await localization.select('en');
      expect(localization.contentCode, 'en');
      final restored = AppLocalization(prefs);
      expect(restored.contentCode, 'en');
      expect(restored.contentSelection, isNull);
      restored.dispose();
      localization.dispose();
    },
  );

  Future<void> settleSources(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'choosing Arabic removes an already visible name translation and keeps the Arabic name',
    (tester) async {
      SharedPreferences.setMockInitialValues({'app.language.v1': 'en'});
      final localization = AppLocalization(
        await SharedPreferences.getInstance(),
      );
      await tester.runAsync(() => library.load('en', 'names'));
      await tester.pumpWidget(
        LocalizationScope(
          controller: localization,
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  Text(originals['name-01']!),
                  ContentTranslationCard(
                    contentId: 'name-01',
                    originalText: originals['name-01'],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await settleSources(tester);
      expect(find.text('Ar Rahmaan'), findsOneWidget);
      await localization.selectContent('tr');
      await localization.select('ar');
      await settleSources(tester);
      expect(find.text('Ar Rahmaan'), findsNothing);
      expect(find.byType(BundledSourceCard), findsNothing);
      expect(find.text(originals['name-01']!), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      localization.dispose();
    },
  );

  testWidgets(
    'source expansion states do not share a stored double scroll offset or each others state',
    (tester) async {
      SharedPreferences.setMockInitialValues({'app.language.v1': 'en'});
      final localization = AppLocalization(
        await SharedPreferences.getInstance(),
      );
      final hadith = await tester.runAsync(() => library.load('en', 'hadith'));
      await tester.runAsync(() => library.load('en', 'tafsir'));
      final bucket = PageStorageBucket();
      final visible = ValueNotifier(false);
      final scroll = ScrollController();
      late BuildContext readingContext;
      await tester.pumpWidget(
        LocalizationScope(
          controller: localization,
          child: MaterialApp(
            home: Scaffold(
              body: PageStorage(
                bucket: bucket,
                child: SingleChildScrollView(
                  key: const PageStorageKey('reading-scroll'),
                  controller: scroll,
                  child: Builder(
                    builder: (context) {
                      readingContext = context;
                      return ValueListenableBuilder<bool>(
                        valueListenable: visible,
                        builder: (context, show, _) => Column(
                          children: [
                            if (show) ...[
                              BundledSourceCard(
                                kind: 'hadith',
                                contentId: 'nawawi-01',
                                originalText: originals['nawawi-01']!,
                              ),
                              const BundledSourceCard(
                                kind: 'tafsir',
                                verseKey: '1:1',
                              ),
                              PublishedHadithRecord(
                                record: Map<String, String>.from(
                                  (hadith!.data['entries']
                                          as Map)['nawawi-01']['fields']
                                      as Map,
                                ),
                                source: {
                                  ...hadith.source,
                                  'update_url':
                                      'https://hadeethenc.com/en/check/en/v1.25.0',
                                },
                                direction: 'ltr',
                              ),
                            ],
                            const SizedBox(height: 2000),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      scroll.jumpTo(120);
      await tester.pumpAndSettle();
      bucket.writeState(readingContext, 120.0);
      visible.value = true;
      await settleSources(tester);
      expect(tester.takeException(), isNull);
      final tiles = tester
          .widgetList<ExpansionTile>(find.byType(ExpansionTile))
          .toList();
      expect(tiles.length, greaterThan(5));
      expect(tiles.every((tile) => tile.key is PageStorageKey<String>), true);
      expect(tiles.map((tile) => tile.key).toSet().length, tiles.length);
      final first = find.byType(ExpansionTile).first;
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(bucket.readState(readingContext), isA<double>());
      expect(tester.takeException(), isNull);
      visible.value = false;
      await tester.pumpAndSettle();
      visible.value = true;
      await settleSources(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
      visible.dispose();
      localization.dispose();
    },
  );
}
