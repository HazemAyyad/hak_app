import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/core/localization/interface_messages.dart';
import 'package:haq_app/features/quran/data/quran_audio.dart';
import 'package:haq_app/features/quran/data/bundled_mushaf.dart';
import 'package:haq_app/features/quran/data/quran_audio_models.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/presentation/quran_host.dart';
import 'package:haq_app/features/quran/presentation/quran_mushaf.dart';
import 'package:haq_app/main.dart';
import 'quran_reader_interaction_test.dart' show ReaderContent, ReaderPages;

// Platform track changes are emitted independently of scrolling and selection.
class FollowingMedia extends QuranMedia {
  FollowingMedia(QuranRepository repo, SharedPreferences prefs)
    : super(repository: () => repo, preferences: () => prefs);
  QuranAudioTrack? track;
  int starts = 0;
  bool running = false;
  bool following = false;
  @override
  QuranAudioTrack? get current => track;
  @override
  bool get playing => running;
  @override
  bool get buffering => false;
  @override
  Duration get position => Duration.zero;
  @override
  bool get readingSession => following && track != null;
  @override
  void setInterfaceMessages(InterfaceMessages messages) {}
  @override
  Future<void> playReadingFrom(QuranVerse verse) async {
    starts++;
    following = true;
    running = true;
    advance(verse.key);
  }

  void advance(String key) {
    final verse = repository().byKey[key]!;
    track = QuranAudioTrack(
      id: 'everyayah:alafasy:$key',
      recitation: 'everyayah:alafasy',
      reciter: 'مشاري العفاسي',
      title: key,
      surah: verse.surah,
      ayah: verse.ayah,
      url: 'https://example.test/$key.mp3',
      version: '1',
      quality: 'test',
    );
    notifyListeners();
  }

  @override
  Future<void> toggle() async {
    running = !running;
    notifyListeners();
  }
}

class FollowingController extends QuranController {
  FollowingController(
    QuranRepository repo,
    SharedPreferences prefs,
    this.testAudio,
  ) : super(
        initialRepository: repo,
        preferences: prefs,
        content: ReaderContent(),
        pageDownloads: ReaderPages(),
      );
  final FollowingMedia testAudio;
  @override
  QuranMedia get audio => testAudio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranRepository repo;
  setUpAll(() async {
    repo = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync()),
    );
    for (final family in ['QuranUI', 'Ahem', 'Roboto', 'Arial']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    }
    await (FontLoader(
      'AmiriQuran',
    )..addFont(rootBundle.load('assets/fonts/AmiriQuran.ttf'))).load();
    await (FontLoader('QuranTajweedPage2')..addFont(
          Future.value(ByteData.sublistView(await BundledMushaf().font(2))),
        ))
        .load();
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                'C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        ))
        .load();
  });

  test('Quran settings have bundled text in Arabic, English and Turkish', () {
    final source = File(
      'lib/features/quran/presentation/quran_reader.dart',
    ).readAsStringSync();
    final keys = RegExp(
      r"context\.tr\(\s*'(quran\.[^']+)'",
    ).allMatches(source).map((m) => m[1]!);
    for (final language in ['ar', 'en', 'tr']) {
      final messages = InterfaceMessages.bundled(language);
      for (final key in keys) {
        expect(messages.text(key), isNot(key), reason: '$language: $key');
      }
    }
  });

  for (final mode in QuranReadingMode.values) {
    testWidgets(
      'following audio advances ${mode.name} while player is hidden',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final audio = FollowingMedia(repo, prefs);
        final controller = FollowingController(repo, prefs, audio);
        await controller.load();
        controller.setMode(mode);
        final appearance = AppAppearance(prefs);
        final boundary = GlobalKey();
        tester.view.physicalSize = const Size(320, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: HaqApp(
              showStartup: false,
              appearance: appearance,
              quranController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('القرآن').last);
        await tester.pumpAndSettle();
        tester
            .state<QuranHostState>(find.byType(QuranHost))
            .openReader(repo.byKey['2:1']!);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('quran-reader-follow-play')),
        );
        await tester.pumpAndSettle();
        expect(audio.starts, 1);
        audio.advance('2:12');
        await tester.pumpAndSettle();
        if (mode == QuranReadingMode.pages) {
          final mushaf = tester.widget<QuranMushaf>(find.byType(QuranMushaf));
          expect(mushaf.playing, '2:12');
          expect(mushaf.page, repo.byKey['2:12']!.page);
          expect(
            mushaf.selected,
            isNull,
            reason: 'Playback must not become a manual selection',
          );
        } else if (mode == QuranReadingMode.ayah) {
          expect(find.byKey(const ValueKey('quran-ayah-2:12')), findsOneWidget);
        } else {
          final ink = tester.widget<InkWell>(
            find.byKey(const ValueKey('quran-select-2:12')),
          );
          expect((ink.child as Container).color, isNotNull);
          expect(
            tester.getRect(find.byKey(const ValueKey('quran-select-2:12'))).top,
            inInclusiveRange(0, 600),
          );
        }
        await tester.tap(
          find.byKey(const ValueKey('quran-reader-hide-player')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('quran-reader-player')), findsNothing);
        expect(
          find.byKey(const ValueKey('quran-player-bubble')),
          findsOneWidget,
        );
        expect(audio.playing, isTrue);
        audio.advance('2:13');
        await tester.pumpAndSettle();
        expect(controller.lastKey, '2:13');
        await tester.tap(find.byKey(const ValueKey('quran-player-bubble')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('quran-reader-player')),
          findsOneWidget,
        );
        expect(
          audio.starts,
          1,
          reason: 'Restoring the player must not restart audio',
        );
        await tester.tap(find.byTooltip('تكبير السورة'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('quran-player-bubble')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('quran-player-bubble')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('quran-reader-player')),
          findsOneWidget,
        );
        expect(audio.starts, 1);

        final output = Platform.environment['QURAN_CAPTURE_DIR'];
        if (output != null) {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            await Directory(output).create(recursive: true);
            await File(
              '$output/following-${mode.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
        await tester.tap(find.byTooltip('إغلاق التكبير'));
        await tester.pumpAndSettle();
        audio.following = false;
        audio.running = false;
        await tester.tap(
          find.byKey(const ValueKey('quran-reader-follow-play')),
        );
        await tester.pumpAndSettle();
        expect(
          audio.starts,
          2,
          reason: 'Top play starts a reading queue after single-ayah playback',
        );
        expect(audio.readingSession, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        controller.dispose();
        audio.dispose();
        appearance.dispose();
      },
    );
  }
}
