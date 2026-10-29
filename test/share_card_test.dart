import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'support/visual_audit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/sharing/share_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranRepository repository;
  setUpAll(() async {
    await loadVisualAuditFonts();
    repository = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    for (final (family, path) in [
      ('AmiriQuran', 'assets/fonts/AmiriQuran.ttf'),
      ('QuranUI', 'assets/fonts/Cairo.ttf'),
      ('Tajawal', 'assets/fonts/Tajawal-Regular.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });
  test(
    'adhkar export has Haq identity and actual logo in all themes without reference-source metadata',
    () async {
      final content = ShareCardContent.adhkar('سُبْحَانَ اللَّهِ وَبِحَمْدِهِ');
      expect(content.text, 'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ');
      expect(content.haqBranding, true);
      expect(
        '${content.source} ${content.attribution}',
        isNot(contains('حصن المسلم')),
      );
      expect(content.attribution, isNot(contains('http')));
      final folder = Directory('build/haq-adhkar-share-preview')
        ..createSync(recursive: true);
      for (final theme in ShareCardTheme.values) {
        final result = await ShareCardRenderer.render(
          content,
          ShareCardStyle(theme: theme),
        );
        expect(result.bytes.length, greaterThan(10000));
        File('${folder.path}/${theme.name}.png').writeAsBytesSync(result.bytes);
        final codec = await ui.instantiateImageCodec(result.bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1080);
        frame.image.dispose();
        codec.dispose();
      }
    },
  );
  test(
    'all content types share the unchanged text and Haq identity without source metadata',
    () {
      final verse = ShareCardContent.quran(repository, ['1:2']);
      final message = ShareCardContent.message('رسالة من حق');
      final religious = ShareCardContent(
        text: 'نص المحتوى',
        source: 'المصدر الأصلي',
        attribution: 'https://example.com/source',
      );
      final dhikr = ShareCardContent.adhkar('سبحان الله');
      for (final content in [verse, message, religious, dhikr]) {
        expect(content.haqBranding, isTrue);
        expect(content.shareText, startsWith(content.text));
        expect(content.shareText, endsWith(ShareCardContent.signature));
        expect('تطبيق حق'.allMatches(content.shareText).length, 1);
      }
      expect(verse.shareText, isNot(contains(verse.source)));
      expect(verse.shareText, isNot(contains(verse.attribution)));
      expect(religious.shareText, isNot(contains(religious.source)));
      expect(religious.shareText, isNot(contains(religious.attribution)));
      expect(dhikr.shareText, 'سبحان الله\n\n${ShareCardContent.signature}');
    },
  );
  test(
    'image export omits source names and URLs from the rendered pixels',
    () async {
      final original = await ShareCardRenderer.render(
        const ShareCardContent(
          text: 'نص المشاركة',
          source: 'مصدر خاص',
          attribution: 'https://example.com/source',
        ),
        const ShareCardStyle(),
      );
      final withoutSource = await ShareCardRenderer.render(
        const ShareCardContent(
          text: 'نص المشاركة',
          source: '',
          attribution: '',
        ),
        const ShareCardStyle(),
      );
      expect(original.bytes, orderedEquals(withoutSource.bytes));
    },
  );
  test(
    'canonical verse selection rejects reordered, repeated and cross-surah inputs without normalizing text',
    () {
      final content = ShareCardContent.quran(repository, ['1:1', '1:2']);
      expect(
        content.text,
        '${repository.byKey['1:1']!.text}\n${repository.byKey['1:2']!.text}',
      );
      expect(content.source, contains('1–2'));
      expect(content.attribution, contains('Tanzil'));
      for (final keys in [
        <String>[],
        ['1:1', '1:1'],
        ['1:2', '1:1'],
        ['1:1', '1:3'],
        ['1:1', '2:1'],
        ['unknown'],
      ]) {
        expect(
          () => ShareCardContent.quran(repository, keys),
          throwsArgumentError,
        );
      }
    },
  );
  test(
    'square/story PNGs render complete canonical text with adaptive fitting',
    () async {
      final content = ShareCardContent.quran(repository, ['2:282']);
      for (final format in ShareCardFormat.values) {
        final result = await ShareCardRenderer.render(
          content,
          ShareCardStyle(
            format: format,
            fontSize: 100,
            theme: ShareCardTheme.navy,
          ),
        );
        expect(result.content.text, repository.byKey['2:282']!.text);
        expect(result.actualFontSize, greaterThanOrEqualTo(18));
        final codec = await ui.instantiateImageCodec(result.bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1080);
        expect(
          frame.image.height,
          format == ShareCardFormat.square ? 1080 : 1920,
        );
        frame.image.dispose();
        codec.dispose();
        final file = File('build/content-preview/ayah-282-${format.name}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(result.bytes);
      }
      await expectLater(
        ShareCardRenderer.render(
          ShareCardContent(
            text: List.filled(10000, 'كلمة').join(' '),
            source: 'مصدر',
            attribution: '',
          ),
          const ShareCardStyle(),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'saving delegates the exact exported PNG bytes and preserves cancellation/permission errors',
    () async {
      final result = await ShareCardRenderer.render(
        ShareCardContent.quran(repository, ['1:2']),
        const ShareCardStyle(),
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ShareCardExporter.channel, (call) async {
            calls.add(call);
            return true;
          });
      expect(await ShareCardExporter.save(result.bytes), true);
      expect(calls.single.method, 'saveImage');
      expect(calls.single.arguments['bytes'], result.bytes);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            ShareCardExporter.channel,
            (_) async => false,
          );
      expect(await ShareCardExporter.save(result.bytes), false);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            ShareCardExporter.channel,
            (_) async => throw PlatformException(code: 'permission'),
          );
      await expectLater(
        ShareCardExporter.save(result.bytes),
        throwsA(isA<PlatformException>()),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ShareCardExporter.channel, null);
    },
  );
  testWidgets(
    'image editor changes size, theme, font and selected range without editing scripture at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final content = ShareCardContent.quran(repository, ['1:2']);
      Future<ShareCardImage?>? pendingRender;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: ShareCardEditor(
            content: content,
            repository: repository,
            renderer: (content, style) async {
              pendingRender = tester.runAsync(
                () => ShareCardRenderer.render(content, style),
              );
              return (await pendingRender)!;
            },
          ),
        ),
      );
      Future<void> waitImage() async {
        await pendingRender;
        await tester.pump();
        expect(
          find.byKey(const ValueKey('share-card-preview')),
          findsOneWidget,
        );
      }

      await waitImage();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('قصة'));
      await waitImage();
      await tester.tap(find.text('كحلي'));
      await waitImage();
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4').last);
      await tester.pump(const Duration(milliseconds: 350));
      await waitImage();
      await tester.pumpAndSettle();
      final image =
          tester
                  .widget<Image>(
                    find.byKey(const ValueKey('share-card-preview')),
                  )
                  .image
              as MemoryImage;
      await tester.runAsync(() async {
        final file = File('build/content-preview/share-editor-story.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(image.bytes);
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  if (visualAudit) {
    testWidgets(
      'visual review share editor in both appearances at normal text size',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        for (final dark in [false, true]) {
          Future<ShareCardImage?>? pending;
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  fontFamily: 'QuranUI',
                  brightness: dark ? Brightness.dark : Brightness.light,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xFF2A8C82),
                    primary: const Color(0xFF2A8C82),
                    secondary: const Color(0xFFC7A45A),
                    brightness: dark ? Brightness.dark : Brightness.light,
                  ),
                  scaffoldBackgroundColor: dark
                      ? const Color(0xFF081722)
                      : const Color(0xFFFFFCF7),
                ),
                home: ShareCardEditor(
                  content: ShareCardContent.quran(repository, ['1:2']),
                  repository: repository,
                  renderer: (content, style) async {
                    pending = tester.runAsync(
                      () => ShareCardRenderer.render(content, style),
                    );
                    return (await pending)!;
                  },
                ),
              ),
            ),
          );
          await pending;
          await tester.pumpAndSettle();
          await prepareVisualAuditCapture(tester, boundary);
          expect(
            find.byKey(const ValueKey('share-card-preview')),
            findsOneWidget,
          );
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            final file = File(
              visualPath(
                'build/content-preview/editor-${dark ? 'dark' : 'light'}.png',
              ),
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          });
          await captureAuditContinuation(
            tester,
            boundary,
            visualPath(
              'build/content-preview/editor-${dark ? 'dark' : 'light'}.png',
            ),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }
}
