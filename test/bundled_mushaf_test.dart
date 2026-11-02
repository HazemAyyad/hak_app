import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/quran/data/bundled_mushaf.dart';
import 'package:haq_app/features/quran/data/quran_content.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/presentation/quran_mushaf.dart';
import 'package:haq_app/features/quran/presentation/quran_mushaf_line.dart';

class _DiskMushaf extends CachingAssetBundle {
  _DiskMushaf({this.corruptFont = false});
  final bool corruptFont;
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    if (corruptFont && key.endsWith('.qbr')) {
      bytes[bytes.length ~/ 2] ^= 255;
    }
    return ByteData.sublistView(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranRepository repo;
  setUpAll(() async {
    repo = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync()),
    );
    for (final font in QuranScriptFont.values) {
      await (FontLoader(font.family)..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/${font.family}.ttf').readAsBytesSync(),
              ),
            ),
          ))
          .load();
    }
    await (FontLoader('QuranUI')..addFont(
          Future.value(
            ByteData.sublistView(
              File('assets/fonts/Cairo.ttf').readAsBytesSync(),
            ),
          ),
        ))
        .load();
  });

  test(
    'fresh offline bundle covers all 604 pages and every verse exactly',
    () async {
      final store = BundledMushaf(assets: _DiskMushaf());
      final verses = <String>{}, locations = <String>{};
      var wordCount = 0;
      for (var page = 1; page <= 604; page++) {
        final words = await store.page(page);
        expect(words, isNotEmpty);
        for (final word in words) {
          final key = word[0] as String;
          expect(repo.byKey.containsKey(key), true);
          expect(locations.add('$key:${word[1]}'), true);
          expect(word[2], inInclusiveRange(1, 15));
          expect(word[3], isNotEmpty);
          expect(word[4], isNotEmpty);
          verses.add(key);
          wordCount++;
        }
      }
      expect(verses, repo.byKey.keys.toSet());
      expect(wordCount, 83668);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'Dart restores original color-font bytes for samples across the Mushaf',
    () async {
      final store = BundledMushaf(assets: _DiskMushaf());
      final receipts =
          (jsonDecode(
                File('tool/quran_sources/mushaf-fonts.json').readAsStringSync(),
              )
              as List);
      final elapsed = Stopwatch()..start();
      // Both opening pages, long-page samples, middle and final pages exercise
      // independent Brotli streams, COLR palettes and distinct word sets.
      for (final page in [1, 2, 42, 100, 300, 500, 604]) {
        final raw = await store.font(page);
        expect(
          sha256.convert(raw).toString(),
          (receipts[page - 1] as Map)['sha256'],
        );
      }
      elapsed.stop();
      debugPrint(
        'Restored 7 original Mushaf fonts in ${elapsed.elapsedMilliseconds} ms',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'damaged bundled font fails visibly instead of falling back to HTTP or SVG',
    () async {
      final store = BundledMushaf(assets: _DiskMushaf(corruptFont: true));
      await expectLater(store.font(2), throwsA(anything));
      await expectLater(store.font(0), throwsRangeError);
      await expectLater(store.page(605), throwsRangeError);
    },
  );

  testWidgets(
    'original page and five alternative fonts keep line groups and verse taps',
    (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = BundledMushaf(assets: _DiskMushaf());
      final content = QuranContent(mushaf: store);
      late MushafPageData page;
      await tester.runAsync(() async {
        page = await content.page(2, repo);
      });
      final boundary = GlobalKey();
      for (final font in [null, ...QuranScriptFont.values]) {
        String? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: FittedBox(
                  child: MushafCanvas(
                    data: page,
                    repository: repo,
                    selected: null,
                    paper: const Color(0xFFFFFCF5),
                    ink: const Color(0xFF231F20),
                    fontFamily: font?.family,
                    onSelect: (verse) => selected = verse.key,
                    onOptions: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/quran/mushaf_frame.png'),
            boundary.currentContext!,
          ),
        );
        await tester.pumpAndSettle();
        final lines = tester
            .widgetList<QuranMushafLine>(find.byType(QuranMushafLine))
            .toList();
        expect(
          lines.expand((line) => line.words).map((word) => word.key),
          page.words.map((word) => word.key),
        );
        expect(
          lines.every(
            (line) => line.fontFamily == (font?.family ?? page.fontFamily),
          ),
          true,
        );
        expect(lines.every((line) => line.useUnicode == (font != null)), true);
        final first = page.words.first;
        await tester.tap(
          find.text(font == null ? first.glyph : first.text).first,
        );
        await tester.pump();
        expect(selected, first.key);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final out = Directory('build/bundled-mushaf-preview')
            ..createSync(recursive: true);
          File(
            '${out.path}/page2-${font?.name ?? 'original'}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
