import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/sharing/share_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranRepository repository;
  setUpAll(() async {
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
    'square/story PNGs render complete canonical text and source with adaptive fitting',
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
}
