import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/features/quran/data/quran_audio.dart';
import 'package:haq_app/features/quran/data/quran_audio_models.dart';
import 'package:haq_app/features/quran/data/quran_downloads.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/presentation/quran_reader_player.dart';
import 'package:haq_app/features/quran/presentation/quran_audio_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quran_playback_ownership_test.dart' as ownership;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'reader plays full chapters, switches to selected ayah and returns to chapter even with an existing queue',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final folder = Directory.systemTemp.createTempSync('haq_reader_audio_');
      final player = ownership.OwnershipPlayer();
      final handler = QuranAudioHandler(player: player);
      final media =
          QuranMedia(
              repository: () => repo,
              preferences: () => prefs,
              downloads: QuranDownloads(directory: folder),
              handlerFactory: () async => handler,
            )
            ..catalog = QuranAudioCatalog.fromJson(
              jsonDecode(
                    File('assets/quran/audio_catalog.json').readAsStringSync(),
                  )
                  as Map<String, dynamic>,
            );
      final appearance = AppAppearance(prefs);
      QuranVerse? selected;
      var surah = 1;
      var expanded = false;
      late StateSetter update;
      await tester.pumpWidget(
        AppearanceScope(
          controller: appearance,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return QuranReaderPlayer(
                    media: media,
                    repository: repo,
                    surah: surah,
                    selected: selected,
                    expanded: expanded,
                    onToggleExpanded: () => update(() => expanded = !expanded),
                    onReciter: () {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      Future<void> play() async {
        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('quran-reader-play')));
          for (var i = 0; i < 100 && media.loading; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(media.error, isNull);
        expect(media.loading, isFalse);
      }

      await play();
      expect(media.current!.surah, 1);
      expect(media.current!.ayah, isNull);
      expect(media.playing, isTrue);
      await play();
      expect(media.playing, isFalse);
      update(() => selected = repo.byKey['1:3']);
      await tester.pumpAndSettle();
      await play();
      expect(media.current!.ayah, 3);
      expect(media.playingTracks, hasLength(1));
      update(() => selected = null);
      await tester.pumpAndSettle();
      await play();
      expect(media.current!.ayah, isNull);
      expect(media.current!.surah, 1);
      update(() => surah = 2);
      await tester.pumpAndSettle();
      await play();
      expect(media.current!.surah, 2);
      expect(media.current!.ayah, isNull);

      await tester.runAsync(() => media.playReadingFrom(repo.byKey['2:285']!));
      await tester.pumpAndSettle();
      expect(media.playingTracks.map((track) => track.ayah), [285, 286]);
      expect(media.readingSession, isTrue);
      final readingSession = media.playbackSession;
      await play();
      expect(media.playbackSession, readingSession);
      expect(media.playing, isFalse);
      await play();
      expect(media.playing, isTrue);
      expect(media.current!.ayah, 285);

      await tester.tap(find.byKey(const ValueKey('quran-sleep-timer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quran-timer-minutes-10')));
      await tester.pumpAndSettle();
      expect(
        media.stopAt,
        isNull,
        reason: 'Choosing a duration must not start the timer before Set',
      );
      await tester.tap(find.byKey(const ValueKey('quran-timer-apply')));
      await tester.pumpAndSettle();
      expect(media.stopAt, isNotNull);
      expect(
        media.stopAt!.difference(DateTime.now()).inSeconds,
        inInclusiveRange(598, 600),
      );
      await tester.tap(find.byKey(const ValueKey('quran-sleep-timer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quran-timer-cancel')));
      await tester.pumpAndSettle();
      expect(media.sleepTimerActive, isFalse);
      await tester.tap(find.byTooltip('توسيع المشغل'));
      await tester.pumpAndSettle();
      expect(find.byType(QuranPlayerPanel), findsOneWidget);
      expect(find.byKey(const ValueKey('quran-reader-play')), findsNothing);
      expect(find.byType(QuranSleepTimerButton), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      final expandedSession = media.playbackSession;
      await tester.tap(find.byTooltip('طي المشغل'));
      await tester.pumpAndSettle();
      expect(find.byType(QuranPlayerPanel), findsNothing);
      expect(find.byKey(const ValueKey('quran-reader-play')), findsOneWidget);
      expect(media.playbackSession, expandedSession);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      appearance.dispose();
      await tester.runAsync(() async {
        media.dispose();
        await media.downloads.flush();

        expect(
          folder.absolute.path,
          startsWith(Directory.systemTemp.absolute.path),
        );
        await folder.delete(recursive: true);
      });
      await player.dispose();
    },
  );
}
