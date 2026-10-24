import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/quran/data/quran_audio.dart';
import 'package:haq_app/features/quran/data/quran_audio_models.dart';
import 'package:haq_app/features/quran/data/quran_downloads.dart';
import 'package:haq_app/features/quran/data/quran_playback_ownership.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quran_audio_handler_test.dart' as fixture;

class OwnershipPlayer extends fixture.TestAudioPlayer {
  double rate = 1;
  final played = <String>[];
  Completer<void>? loadingGate, loadStarted, playLifetime;
  bool indefinitePlay = false;
  @override
  double get speed => rate;
  @override
  Future<void> setSpeed(double value) async {
    rate = value;
  }

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    final gate = loadingGate;
    if (gate != null) {
      loadingGate = null;
      loadStarted!.complete();
      await gate.future;
    }
    return super.setAudioSources(
      sources,
      preload: preload,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      shuffleOrder: shuffleOrder,
    );
  }

  @override
  Future<void> play() async {
    await super.play();
    played.add(
      (sequence[currentIndex!].tag as MediaItem).extras!['trackId'] as String,
    );
    if (indefinitePlay) {
      playLifetime = Completer<void>();
      await playLifetime!.future;
    }
  }

  @override
  Future<void> pause() async {
    await super.pause();
    if (playLifetime?.isCompleted == false) playLifetime!.complete();
  }

  @override
  Future<void> stop() async {
    await super.stop();
    if (playLifetime?.isCompleted == false) playLifetime!.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late OwnershipPlayer player;
  late QuranAudioHandler handler;
  late QuranMedia quran, religious;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'haq_playback_ownership_',
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final catalog = QuranAudioCatalog.fromJson(
      jsonDecode(File('assets/quran/audio_catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    player = OwnershipPlayer();
    handler = QuranAudioHandler(player: player);
    QuranMedia media(String key) => QuranMedia(
      repository: () => repository,
      preferences: () => prefs,
      storageKey: key,
      handlerFactory: () async => handler,
      downloads: QuranDownloads(directory: Directory('${directory.path}/$key')),
    )..catalog = catalog;
    quran = media('quran');
    religious = media('religious');
    await Future.wait([quran.initialize(), religious.initialize()]);
  });
  tearDown(() async {
    quran.dispose();
    religious.dispose();
    await Future.wait([quran.downloads.flush(), religious.downloads.flush()]);
    await player.stop();
    await player.dispose();
    expect(
      directory.absolute.path,
      startsWith(Directory.systemTemp.absolute.path),
    );
    await directory.delete(recursive: true);
  });

  test(
    'only current owner exposes playback or controls the shared native queue',
    () async {
      await quran.playTracks([fixture.recording('quran')]);
      quran.setTimer(const Duration(minutes: 10));
      await religious.playTracks([fixture.recording('religious')]);
      expect(quran.current, isNull);
      expect(quran.playing, isFalse);
      expect(quran.stopAt, isNull);
      expect(religious.current!.id, 'religious');
      expect(religious.playing, isTrue);
      await quran.seek(const Duration(seconds: 7));
      await quran.skip(1);
      await quran.stop();
      await quran.setSpeed(1.7);
      await quran.setRepeat(AudioServiceRepeatMode.one);
      expect(player.seeks, isEmpty);
      expect(player.rate, 1);
      expect(player.loopMode, LoopMode.off);
      expect(religious.playing, isTrue);
      await quran.playTracks([fixture.recording('quran-again')]);
      expect(quran.current!.id, 'quran-again');
      expect(religious.current, isNull);
      expect(player.rate, 1.7);
    },
  );

  test(
    'old sleep timer is cancelled when a different section takes ownership',
    () async {
      await quran.playTracks([fixture.recording('quran')]);
      quran.setTimer(const Duration(milliseconds: 100));
      await religious.playTracks([fixture.recording('religious')]);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(religious.playing, isTrue);
      expect(quran.stopAt, isNull);
      handler.ownership.release(religious);
      // A retired facade cannot regain control just because the lease is empty.
      expect(quran.ownsPlayback, isFalse);
    },
  );

  test(
    'slow previous load never starts stale playback after the next owner claims',
    () async {
      final gate = Completer<void>();
      player.loadingGate = gate;
      player.loadStarted = Completer<void>();
      final first = quran.playTracks([fixture.recording('slow-quran')]);
      await player.loadStarted!.future;
      final second = religious.playTracks([fixture.recording('religious')]);
      while (!handler.ownership.owns(religious)) {
        await Future<void>.delayed(Duration.zero);
      }
      gate.complete();
      await Future.wait([first, second]);
      expect(player.played, ['religious']);
      expect(religious.current!.id, 'religious');
      expect(quran.current, isNull);
      expect(quran.loading, isFalse);
    },
  );

  test(
    'play future lasting until pause cannot deadlock the serial command lane',
    () async {
      player.indefinitePlay = true;
      await quran.playTracks([fixture.recording('quran')]);
      await quran.toggle().timeout(const Duration(seconds: 2));
      expect(quran.playing, isFalse);
      await quran.toggle().timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(quran.playing, isTrue);
      await quran.toggle().timeout(const Duration(seconds: 2));
      expect(quran.playing, isFalse);
    },
  );

  test(
    'disposing during handler initialization cannot start a recording later',
    () async {
      final gate = Completer<QuranAudioHandler>(), started = Completer<void>();
      final lateMedia = QuranMedia(
        repository: quran.repository,
        preferences: quran.preferences,
        handlerFactory: () {
          started.complete();
          return gate.future;
        },
        downloads: QuranDownloads(
          directory: Directory('${directory.path}/late'),
        ),
      )..catalog = quran.catalog;
      final pending = lateMedia.playTracks([fixture.recording('late')]);
      await started.future;
      lateMedia.dispose();
      gate.complete(handler);
      await pending;
      await lateMedia.downloads.flush();
      expect(player.played, isEmpty);
      expect(handler.ownership.unclaimed, isTrue);
      expect(lateMedia.ownsPlayback, isFalse);
    },
  );

  test(
    'queued commands from a retired lease are skipped and failures do not block later loads',
    () async {
      final leases = QuranPlaybackOwnership();
      final first = Object(), second = Object(), gate = Completer<void>();
      leases.claim(first, () {});
      final pending = leases.run(first, () => gate.future);
      await Future<void>.delayed(Duration.zero);
      var stale = false, next = false;
      final retired = leases.run(first, () async {
        stale = true;
      });
      leases.claim(second, () {});
      final current = leases.run(second, () async {
        next = true;
      });
      gate.complete();
      await Future.wait([pending, retired, current]);
      expect(stale, isFalse);
      expect(next, isTrue);
      await expectLater(
        leases.run(second, () async {
          throw StateError('player error');
        }),
        throwsStateError,
      );
      expect(await leases.run(second, () async {}), isTrue);
    },
  );
}
