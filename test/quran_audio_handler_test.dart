import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/features/quran/data/quran_audio.dart';
import 'package:haq_app/features/quran/data/quran_audio_models.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/presentation/quran_audio_widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Exercise the actual handler against player events, without native services,
// network audio, or invented recording durations in the application catalog.
class TestAudioPlayer implements AudioPlayer {
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final sequences = StreamController<SequenceState>.broadcast(sync: true);
  final errors = StreamController<PlayerException>.broadcast(sync: true);
  PlaybackEvent event = PlaybackEvent();
  bool isPlaying = false;
  Completer<void>? loadGate, loadEntered;
  @override
  LoopMode loopMode = LoopMode.off;
  final seeks = <(Duration, int?)>[];
  @override
  List<IndexedAudioSource> sequence = [];
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<SequenceState> get sequenceStateStream => sequences.stream;
  @override
  Stream<PlayerException> get errorStream => errors.stream;
  @override
  PlaybackEvent get playbackEvent => event;
  @override
  bool get playing => isPlaying;
  @override
  ProcessingState get processingState => event.processingState;
  @override
  int? get currentIndex => event.currentIndex;
  @override
  Duration? get duration => event.duration;
  @override
  Duration get position => event.updatePosition;
  @override
  Duration get bufferedPosition => event.bufferedPosition;
  @override
  double get speed => 1;
  @override
  bool get hasNext =>
      currentIndex != null &&
      (currentIndex! + 1 < sequence.length || loopMode == LoopMode.all);
  @override
  bool get hasPrevious =>
      currentIndex != null && (currentIndex! > 0 || loopMode == LoopMode.all);

  void emit({
    required int index,
    Duration? duration,
    Duration position = Duration.zero,
    ProcessingState state = ProcessingState.ready,
  }) {
    event = PlaybackEvent(
      currentIndex: index,
      duration: duration,
      updatePosition: position,
      bufferedPosition: duration ?? Duration.zero,
      processingState: state,
    );
    events.add(event);
  }

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    loadEntered?.complete();
    await loadGate?.future;
    sequence = sources.cast<IndexedAudioSource>();
    emit(index: initialIndex ?? 0);
    return null;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async => loopMode = mode;
  @override
  Future<void> play() async {
    isPlaying = true;
    states.add(PlayerState(isPlaying, processingState));
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    states.add(PlayerState(isPlaying, processingState));
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
    event = PlaybackEvent();
    events.add(event);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seeks.add((position ?? Duration.zero, index));
    emit(
      index: index ?? currentIndex ?? 0,
      duration: duration,
      position: position ?? Duration.zero,
    );
  }

  @override
  Future<void> seekToNext() =>
      seek(Duration.zero, index: (currentIndex! + 1) % sequence.length);
  @override
  Future<void> seekToPrevious() =>
      seek(Duration.zero, index: currentIndex! - 1);
  @override
  Future<void> dispose() async {
    await events.close();
    await states.close();
    await sequences.close();
    await errors.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

QuranAudioTrack recording(String id) => QuranAudioTrack(
  id: id,
  recitation: 'test',
  reciter: 'قارئ الاختبار',
  title: 'سورة الفاتحة • الآية 1',
  surah: 1,
  ayah: 1,
  url: 'https://example.test/$id.mp3',
  version: 'test',
  quality: '128kbps',
);

class PreparingMedia extends QuranMedia {
  PreparingMedia()
    : super(
        repository: () => throw UnimplementedError(),
        preferences: () => throw UnimplementedError(),
      );
  final ready = Completer<void>();
  @override
  Future<void> initialize() => ready.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestAudioPlayer player;
  late QuranAudioHandler handler;
  setUp(() {
    player = TestAudioPlayer();
    handler = QuranAudioHandler(player: player);
  });
  tearDown(() async => player.dispose());

  Future<void> load(List<QuranAudioTrack> tracks) =>
      handler.load(tracks, tracks.map((t) => Uri.parse(t.url)).toList());

  test(
    'chapter taps show loading before catalog initialization and can be cancelled',
    () async {
      final media = PreparingMedia();
      addTearDown(media.dispose);
      final pending = media.playChapter(1);
      expect(media.loading, isTrue);
      expect(media.buffering, isTrue);
      await media.stop();
      media.ready.complete();
      await pending;
      expect(media.loading, isFalse);
      expect(media.handler, isNull);
      expect(media.current, isNull);
      expect(media.error, isNull);
    },
  );

  test(
    'pending track metadata appears immediately and clears when cancelled',
    () async {
      final media = PreparingMedia();
      addTearDown(media.dispose);
      final pending = media.playTracks([recording('pending')]);
      expect(media.current?.id, 'pending');
      expect(media.loading, isTrue);
      await media.stop();
      expect(media.current, isNull);
      media.ready.complete();
      await pending;
      expect(media.handler, isNull);
      expect(media.loading, isFalse);
    },
  );

  test(
    'stop while loading prevents late source completion from restarting audio',
    () async {
      player.loadGate = Completer<void>();
      player.loadEntered = Completer<void>();
      final pending = load([recording('loading')]);
      await player.loadEntered!.future;
      await handler.stop();
      player.loadGate!.complete();
      await pending;
      expect(player.playing, isFalse);
      expect(handler.playbackState.value.playing, isFalse);
    },
  );

  test(
    'notification duration stays attached to its queue item across changes',
    () async {
      await load([recording('first'), recording('second')]);
      player.emit(index: 0, duration: const Duration(seconds: 45));
      expect(handler.mediaItem.value!.duration, const Duration(seconds: 45));
      expect(handler.queue.value[0].duration, const Duration(seconds: 45));
      player.emit(index: 1, duration: const Duration(seconds: 45));
      expect(handler.mediaItem.value!.id, handler.queue.value[1].id);
      expect(handler.mediaItem.value!.duration, const Duration(seconds: 45));
      player.emit(index: 0);
      expect(handler.mediaItem.value!.duration, const Duration(seconds: 45));
      expect(handler.mediaItem.value!.album, isNull);
      expect(handler.mediaItem.value!.displaySubtitle, 'قارئ الاختبار');
      expect(handler.mediaItem.value!.title, isNot(contains('128')));
    },
  );

  test(
    'notification exposes only available queue controls and no stop square',
    () async {
      await load([recording('first'), recording('second')]);
      expect(handler.playbackState.value.controls.map((c) => c.action), [
        MediaAction.pause,
        MediaAction.skipToNext,
      ]);
      expect(handler.playbackState.value.androidCompactActionIndices, [0, 1]);
      await handler.skipToPrevious();
      expect(player.seeks, isEmpty);
      player.emit(index: 1);
      expect(handler.playbackState.value.controls.map((c) => c.action), [
        MediaAction.skipToPrevious,
        MediaAction.pause,
      ]);
      await handler.skipToNext();
      await handler.skipToQueueItem(99);
      expect(player.seeks, isEmpty);
      await handler.pause();
      expect(handler.playbackState.value.playing, isFalse);
      expect(
        handler.playbackState.value.controls.last.action,
        MediaAction.play,
      );
    },
  );

  test(
    'all seek entry points clamp real duration and preserve unknown lengths',
    () async {
      await load([recording('first')]);
      player.emit(
        index: 0,
        duration: const Duration(seconds: 15),
        position: const Duration(seconds: 9),
      );
      await handler.fastForward();
      expect(player.seeks.last.$1, const Duration(seconds: 15));
      await handler.rewind();
      expect(player.seeks.last.$1, const Duration(seconds: 5));
      await handler.rewind();
      expect(player.seeks.last.$1, Duration.zero);
      await handler.seek(const Duration(seconds: -1));
      expect(player.seeks.last.$1, Duration.zero);
      await load([recording('unknown')]);
      await handler.fastForward();
      expect(player.seeks.last.$1, const Duration(seconds: 10));
      expect(handler.mediaItem.value!.duration, isNull);
    },
  );

  test(
    'repeated verse queue has unique identities and completion can replay current item',
    () async {
      await load([recording('verse'), recording('verse')]);
      expect(handler.queue.value[0].id, isNot(handler.queue.value[1].id));
      expect(handler.queue.value[1].extras!['trackId'], 'verse');
      player.emit(
        index: 1,
        duration: const Duration(seconds: 10),
        state: ProcessingState.completed,
      );
      expect(handler.playbackState.value.playing, isFalse);
      expect(
        handler.playbackState.value.controls.last.action,
        MediaAction.play,
      );
      await handler.play();
      expect(player.seeks.last, (Duration.zero, 1));
    },
  );

  testWidgets(
    'Arabic player uses RTL timeline and controls with reciter arrow adjacent',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final media =
          QuranMedia(repository: () => repository, preferences: () => prefs)
            ..handler = handler
            ..playingTracks = [recording('first')];
      final appearance = AppAppearance(prefs);
      addTearDown(media.dispose);
      addTearDown(appearance.dispose);
      await load(media.playingTracks);
      player.emit(
        index: 0,
        duration: const Duration(seconds: 30),
        position: const Duration(seconds: 15),
      );
      Future<void> show({required bool compact}) => tester.pumpWidget(
        AppearanceScope(
          controller: appearance,
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    child: QuranPlayerPanel(
                      media: media,
                      repository: repository,
                      compact: compact,
                      onReciter: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await show(compact: false);
      expect(
        tester.getCenter(find.byTooltip('إرجاع 10 ثوانٍ')).dx,
        greaterThan(tester.getCenter(find.byTooltip('تقديم 10 ثوانٍ')).dx),
      );
      expect(
        Directionality.of(tester.element(find.byType(Slider))),
        TextDirection.rtl,
      );
      await tester.tap(find.byTooltip('تقديم 10 ثوانٍ'));
      expect(player.seeks.last.$1, const Duration(seconds: 25));
      await tester.tap(find.byTooltip('إرجاع 10 ثوانٍ'));
      expect(player.seeks.last.$1, const Duration(seconds: 15));
      await show(compact: true);
      final name = tester.getRect(find.text('قارئ الاختبار'));
      final arrow = tester.getRect(find.byIcon(Icons.expand_more));
      expect((name.left - arrow.right).abs(), lessThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
    },
  );
}
