import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/core/localization/app_localization.dart';
import 'package:haq_app/core/localization/bundled_source_card.dart';
import 'package:haq_app/core/localization/published_meaning_card.dart';
import 'package:haq_app/core/localization/religious_translation_library.dart';

class CorruptedSources extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final raw = await rootBundle.load(key);
    final bytes = Uint8List.fromList(
      raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
    );
    bytes[bytes.length ~/ 2] ^= 1;
    return ByteData.sublistView(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = ReligiousTranslationLibrary.shared;

  test(
    'real English and Turkish Quran and tafsir cover every canonical ayah',
    () async {
      for (final locale in ['en', 'tr']) {
        final quran = await library.load(locale, 'quran');
        final tafsir = await library.load(locale, 'tafsir');
        expect((quran.data['verses'] as Map).length, 6236);
        expect(
          (tafsir.data['verses'] as Map).keys.toSet(),
          (quran.data['verses'] as Map).keys.toSet(),
        );
        for (final key in (quran.data['verses'] as Map).keys.cast<String>()) {
          expect(
            quran.forVerse(key).single['text'],
            isNotEmpty,
            reason: '$locale $key',
          );
          final paragraphs = tafsir.forVerse(key);
          expect(paragraphs, isNotEmpty, reason: '$locale $key');
          expect(
            paragraphs.every(
              (row) => (row['text'] as String).trim().isNotEmpty,
            ),
            true,
            reason: '$locale $key',
          );
        }
        expect(tafsir.forVerse('20:32'), isNotEmpty);
      }
    },
  );

  test(
    'all names and source dhikrs retain identities and reject changed originals',
    () async {
      final catalog =
          jsonDecode(
                await rootBundle.loadString('assets/religious/catalog.json'),
              )
              as Map;
      final adhkar =
          jsonDecode(
                await rootBundle.loadString('assets/religious/adhkar.json'),
              )
              as Map;
      for (final locale in ['en', 'tr']) {
        final names = await library.load(locale, 'names');
        for (final original in (catalog['items'] as List).where(
          (row) => row['type'] == 'name',
        )) {
          expect(
            names.forContent(
              original['id'] as String,
              original['text'] as String,
            ),
            hasLength(1),
          );
          expect(
            names.forContent(
              original['id'] as String,
              '${original['text']} changed',
            ),
            isEmpty,
          );
        }
        final dhikr = await library.load(locale, 'dhikr');
        for (final original in adhkar['items'] as List) {
          expect(
            dhikr.forContent(
              original['id'] as String,
              original['text'] as String,
            ),
            hasLength(1),
            reason: '$locale ${original['id']}',
          );
        }
        expect(
          dhikr.forContent('personal:user-text', 'A private dhikr'),
          isEmpty,
        );
      }
      final names = await library.load('tr', 'names');
      expect(
        (names.data['entries'] as Map)['name-67']['source']['provider'],
        'IslamHouse.com',
      );
    },
  );

  test(
    'all Nawawi and Ramadan hadiths keep publisher narration and edition',
    () async {
      for (final locale in ['en', 'tr']) {
        final hadith = await library.load(locale, 'hadith');
        final entries = hadith.data['entries'] as Map;
        for (var number = 1; number <= 42; number++) {
          final row =
              entries['nawawi-${number.toString().padLeft(2, '0')}'] as Map;
          expect((row['fields'] as Map).length, 15);
          expect(row['source_arabic'], isNotEmpty);
          expect(row['text'], row['fields']['hadith_text']);
        }
        expect(entries['ramadan-last-ten-hadith']['source_id'], '4944');
        expect(
          hadith.source['document'],
          contains('# Source: https://hadeethenc.com/$locale'),
        );
      }
    },
  );

  test(
    'a changed source byte cannot activate as trusted bundled content',
    () async {
      final corrupt = ReligiousTranslationLibrary(bundle: CorruptedSources());
      await expectLater(corrupt.load('tr', 'names'), throwsFormatException);
    },
  );

  test(
    'Turkish content selection is independent from interface and user progress',
    () async {
      SharedPreferences.setMockInitialValues({
        'app.language.v1': 'en',
        'saved-progress-test': 18,
      });
      final preferences = await SharedPreferences.getInstance();
      final localization = AppLocalization(preferences);
      expect(
        localization.availableContent.any((row) => row.code == 'tr'),
        true,
      );
      expect(localization.localInterface('tr'), false);
      await localization.selectContent('tr');
      expect(localization.contentCode, 'tr');
      expect(localization.code, 'en');
      expect(preferences.getInt('saved-progress-test'), 18);
      localization.dispose();
    },
  );

  test(
    'every existing textual catalog item resolves to its own publisher source in both languages',
    () async {
      final catalog =
          jsonDecode(
                await rootBundle.loadString('assets/religious/catalog.json'),
              )
              as Map;
      for (final locale in ['en', 'tr']) {
        final sources = <String, SourceCollection>{
          for (final kind in ['quran', 'dhikr', 'names', 'hadith'])
            kind: await library.load(locale, kind),
        };
        var covered = 0;
        for (final original in catalog['items'] as List) {
          final id = original['id'] as String;
          final kind = ReligiousTranslationLibrary.kindForContent(id);
          if (kind == null) {
            expect(id, 'ruqya-complete');
            expect(original['type'], 'playlist');
            continue;
          }
          final rows = sources[kind]!.forContent(
            id,
            original['text'] as String,
          );
          expect(rows, isNotEmpty, reason: '$locale $id');
          expect(
            rows.every((row) => (row['text'] as String).trim().isNotEmpty),
            true,
            reason: '$locale $id',
          );
          covered++;
        }
        expect(covered, 332);
      }
    },
  );

  testWidgets(
    'name meanings switch to Turkish beside the intact Arabic original on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'app.language.v1': 'en'});
      final localization = AppLocalization(
        await SharedPreferences.getInstance(),
      );
      final data = await tester.runAsync(
        () async =>
            jsonDecode(
                  await rootBundle.loadString('assets/religious/catalog.json'),
                )
                as Map,
      );
      final original =
          (data!['items'] as List).firstWhere((row) => row['id'] == 'name-01')
              as Map;
      // Preload verification outside fake widget time.
      await tester.runAsync(() async {
        await library.load('en', 'names');
        await library.load('tr', 'names');
      });
      await tester.pumpWidget(
        LocalizationScope(
          controller: localization,
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  Text(
                    original['text'] as String,
                    textDirection: TextDirection.rtl,
                  ),
                  BundledContentCard(
                    contentId: 'name-01',
                    originalText: original['text'] as String,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(find.text(original['text'] as String), findsOneWidget);
      expect(find.text('Ar Rahmaan'), findsOneWidget);
      expect(
        tester
            .widget<PublishedTranslationText>(
              find.byType(PublishedTranslationText),
            )
            .text,
        'The Beneficent',
      );
      await localization.selectContent('tr');
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(find.text('er-Rahmân'), findsOneWidget);
      expect(
        tester
            .widget<PublishedTranslationText>(
              find.byType(PublishedTranslationText),
            )
            .text,
        contains('Sonsuz merhametiyle'),
      );
      expect(find.text('Ar Rahmaan'), findsNothing);
      expect(find.text(original['text'] as String), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      localization.dispose();
    },
  );
}
