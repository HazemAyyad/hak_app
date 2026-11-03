import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/bundled_mushaf.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/data/quran_content.dart';
import 'package:haq_app/features/quran/presentation/quran_reader.dart';
import 'package:haq_app/features/quran/presentation/quran_mushaf_line.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'quran_media_test.dart' show StubHttp;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranRepository repo;
  late QuranController c;
  late AppAppearance appearance;
  final boundary = GlobalKey();
  setUpAll(() async {
    repo = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    for (final (family, file) in [
      ('QuranUI', 'Cairo.ttf'),
      ...QuranScriptFont.values.map((f) => (f.family, '${f.family}.ttf')),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/$file').readAsBytesSync(),
              ),
            ),
          ))
          .load();
    }
    final icons = File(
      'C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(icons.readAsBytesSync())),
          ))
          .load();
    }
    await (FontLoader('QuranTajweedPage2')..addFont(
          Future.value(ByteData.sublistView(await BundledMushaf().font(2))),
        ))
        .load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    c = QuranController(initialRepository: repo, preferences: prefs);
    await c.load();
    appearance = AppAppearance(prefs);
  });
  tearDown(() {
    c.dispose();
    appearance.dispose();
  });

  test(
    'page font persists independently and legacy or unknown choices retain the original colored face',
    () async {
      c.setPageFont(QuranScriptFont.lateef);
      await c.flushReading();
      final saved =
          jsonDecode(c.preferences!.getString('quran.state.v1')!)
              as Map<String, dynamic>;
      expect(saved['pageFont'], 'lateef');
      c.restoreState(saved);
      expect(c.pageFont, QuranScriptFont.lateef);
      expect(c.scriptFont, QuranScriptFont.amiri);
      expect(c.showTajweed, true);
      c.restoreState({'pageFont': 'unknown'});
      expect(c.pageFont, isNull);
      c.restoreState({});
      expect(c.pageFont, isNull);
    },
  );

  testWidgets(
    'page settings select five bundled faces and restore the original Tajweed choice',
    (tester) async {
      c.setMode(QuranReadingMode.pages);
      await tester.pumpWidget(
        AppearanceScope(
          controller: appearance,
          child: MaterialApp(
            home: Scaffold(body: QuranReadingSettings(controller: c)),
          ),
        ),
      );
      for (final font in QuranScriptFont.values) {
        final dropdown = find.byType(DropdownButtonFormField<String>);
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text(font.label).last);
        await tester.pumpAndSettle();
        expect(c.pageFont, font);
        expect(
          c.showTajweed,
          true,
          reason: 'Changing a face must retain the original Tajweed preference',
        );
        expect(
          tester
              .widget<Text>(find.text(repo.verses.first.text))
              .style!
              .fontFamily,
          font.family,
        );
      }
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('خط المصحف الأصلي — التجويد').last);
      await tester.pumpAndSettle();
      expect(c.pageFont, isNull);
      expect(c.showTajweed, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'legacy preferences retain original face/color defaults and unknown fields do not select an invalid font',
    () {
      c.restoreState({'mode': 'continuous', 'fontSize': 24, 'paper': 'light'});
      expect(c.scriptFont, QuranScriptFont.amiri);
      expect(c.showTajweed, true);
      c.restoreState({'font': 'unknown', 'tajweed': 'false'});
      expect(c.scriptFont, QuranScriptFont.amiri);
      expect(c.showTajweed, true);
    },
  );

  test(
    'email registration uses the verified public API prefix and needs no Google configuration',
    () async {
      final paths = <String>[];
      c.account.dio.httpClientAdapter = StubHttp((request) {
        paths.add(request.uri.path);
        Map<String, dynamic> data;
        if (request.uri.path.endsWith('/register')) {
          expect(request.uri.path, '/public/api/v1/religious/account/register');
          expect((request.data as Map)['name'], 'قارئ');
          data = {
            'account': {
              'id': 1,
              'name': 'قارئ',
              'email': 'reader@example.test',
            },
            'token': 'test-token',
          };
        } else {
          expect(request.uri.path, '/public/api/v1/quran/sync');
          data = {
            'revision': 0,
            'acknowledged': [],
            'conflicts': [],
            'entities': {},
          };
        }
        return ResponseBody.fromString(
          jsonEncode({'data': data}),
          request.uri.path.endsWith('/register') ? 201 : 200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      });
      await c.account.authenticate(
        register: true,
        email: 'reader@example.test',
        password: 'test-password-long',
        name: 'قارئ',
        mergeGuest: false,
      );
      expect(c.account.error, isNull);
      expect(c.account.profile?['id'], 1);
      expect(paths.any((p) => p.endsWith('/google')), false);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'five usable font choices, live preview and Tajweed toggle fit the settings ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  fontFamily: 'QuranUI',
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
                home: Scaffold(
                  body: Directionality(
                    textDirection: TextDirection.rtl,
                    child: QuranReadingSettings(controller: c),
                  ),
                ),
              ),
            ),
          ),
        );
        for (final font in QuranScriptFont.values) {
          final dropdown = find.byType(
            DropdownButtonFormField<QuranScriptFont>,
          );
          await tester.ensureVisible(dropdown);
          await tester.tap(dropdown);
          await tester.pumpAndSettle();
          await tester.tap(find.text(font.label).last);
          await tester.pumpAndSettle();
          expect(c.scriptFont, font);
          final sample = find.text(repo.verses.first.text);
          expect(tester.widget<Text>(sample).style?.fontFamily, font.family);
        }
        final toggle = find.byKey(const ValueKey('quran-show-tajweed'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(c.showTajweed, false);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final dir = Directory('build/quran-appearance-preview')
            ..createSync(recursive: true);
          File(
            '${dir.path}/settings-${dark ? 'dark' : 'light'}-default.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('monochrome glyphs preserve verse taps and selection geometry', (
    tester,
  ) async {
    final verse = repo.byKey['2:2']!;
    final words = [
      MushafWord(
        key: verse.key,
        position: 1,
        line: 1,
        glyph: verse.text,
        text: verse.text,
      ),
    ];
    String? selected;
    for (final show in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 80,
              child: QuranMushafLine(
                words: words,
                fontFamily: 'AmiriQuran',
                fontSize: 25,
                centered: true,
                selected: '',
                repository: repo,
                showTajweed: show,
                onSelect: (v) => selected = v.key,
                onOptions: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ColorFiltered), show ? findsNothing : findsOneWidget);
      await tester.tap(find.text(verse.text));
      await tester.pump();
      expect(selected, verse.key);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'real QCF V4 palette disappears while glyphs remain when Tajweed is disabled',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final page = MushafPageData.parse(
        2,
        jsonDecode(File('test/fixtures/quran/page2.json').readAsStringSync())
            as Map<String, dynamic>,
        repo,
      );
      final groups = <int, List<MushafWord>>{};
      for (final w in page.words) {
        groups.putIfAbsent(w.line, () => []).add(w);
      }
      final counts = <int>[];
      for (final show in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: Colors.white,
                child: Column(
                  children: [
                    for (final line in groups.values)
                      SizedBox(
                        width: 560,
                        height: 60,
                        child: QuranMushafLine(
                          words: line,
                          fontFamily: page.fontFamily,
                          fontSize: 36,
                          centered: true,
                          selected: '',
                          repository: repo,
                          showTajweed: show,
                          onSelect: (_) {},
                          onOptions: (_) {},
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          var count = 0;
          final bytes = data!.buffer.asUint8List();
          for (var i = 0; i < bytes.length; i += 4) {
            final channels = [bytes[i], bytes[i + 1], bytes[i + 2]]..sort();
            if (channels.last - channels.first > 25) count++;
          }
          counts.add(count);
          final dir = Directory('build/quran-appearance-preview')
            ..createSync(recursive: true);
          File(
            '${dir.path}/tajweed-${show ? 'color' : 'monochrome'}.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        });
        expect(tester.takeException(), isNull);
      }
      expect(counts.first, greaterThan(100));
      expect(counts.last, 0);
    },
  );
  testWidgets(
    'monochrome ayah medallion retains a light interior behind its number',
    (tester) async {
      tester.view.physicalSize = const Size(160, 180);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final page = MushafPageData.parse(
        2,
        jsonDecode(File('test/fixtures/quran/page2.json').readAsStringSync()),
        repo,
      );
      final marker = page.words.firstWhere((word) => word.text == '١');
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: Colors.transparent,
              child: Center(
                child: SizedBox(
                  width: 140,
                  height: 150,
                  child: QuranMushafLine(
                    words: [marker],
                    fontFamily: page.fontFamily,
                    fontSize: 100,
                    centered: true,
                    selected: null,
                    repository: repo,
                    showTajweed: false,
                    onSelect: (_) {},
                    onOptions: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final rgba = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        var lightInterior = 0, darkInk = 0;
        for (var i = 0; i < rgba.length; i += 4) {
          if (rgba[i + 3] < 250) continue;
          if (rgba[i] > 100 && rgba[i] < 240) lightInterior++;
          if (rgba[i] < 65) darkInk++;
        }
        image.dispose();
        expect(
          lightInterior,
          greaterThan(500),
          reason:
              'An opaque ink mask fills this light COLR background and hides the number',
        );
        expect(darkInk, greaterThan(50));
      });
      await tester.pumpWidget(const SizedBox());
    },
  );
}
