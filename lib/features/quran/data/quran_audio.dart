import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quran_audio_models.dart';
import 'quran_downloads.dart';
import 'quran_repository.dart';

class QuranAudioHandler extends BaseAudioHandler with SeekHandler {
  QuranAudioHandler() {
    player.playbackEventStream.listen((_) => _broadcast());
    player.currentIndexStream.listen((index) {
      if (index != null && index < queue.value.length) {
        mediaItem.add(queue.value[index]);
      }
      _broadcast();
    });
    player.durationStream.listen((duration) {
      final current = mediaItem.value;
      if (current != null && duration != null) {
        mediaItem.add(current.copyWith(duration: duration));
      }
    });
    player.errorStream.listen((error) {
      playbackState.add(
        playbackState.value.copyWith(
          errorCode: error.code,
          errorMessage:
              'تعذّر تشغيل التلاوة؛ تحقق من الاتصال أو أعد تنزيل الملف',
        ),
      );
    });
  }
  final player = AudioPlayer(useProxyForRequestHeaders: false);
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  void _broadcast() => playbackState.add(
    PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: player.currentIndex,
      repeatMode: _repeatMode,
    ),
  );
  Future<void> load(
    List<QuranAudioTrack> tracks,
    List<Uri> uris, {
    int start = 0,
  }) async {
    await player.stop();
    queue.add(
      tracks
          .map(
            (track) => MediaItem(
              id: track.id,
              title: track.title,
              artist: track.reciter,
              album: 'القرآن الكريم • ${track.quality}',
              extras: track.toJson(),
            ),
          )
          .toList(),
    );
    mediaItem.add(queue.value[start]);
    await player.setLoopMode(LoopMode.off);
    _repeatMode = AudioServiceRepeatMode.none;
    await player.setAudioSources(
      uris.map(AudioSource.uri).toList(),
      initialIndex: start,
      initialPosition: Duration.zero,
    );
    unawaited(
      play().catchError((Object error) {
        playbackState.add(
          playbackState.value.copyWith(
            errorCode: 1,
            errorMessage: 'تعذّر تشغيل التلاوة',
          ),
        );
      }),
    );
  }

  @override
  Future<void> play() async {
    if (player.processingState == ProcessingState.completed) {
      await player.seek(Duration.zero, index: 0);
    }
    await player.play();
  }

  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> skipToNext() => player.seekToNext();
  @override
  Future<void> skipToPrevious() => player.seekToPrevious();
  @override
  Future<void> skipToQueueItem(int index) =>
      player.seek(Duration.zero, index: index);
  @override
  Future<void> setSpeed(double speed) => player.setSpeed(speed);
  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    await player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => LoopMode.all,
      _ => LoopMode.off,
    });
    _broadcast();
  }

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }
}

class QuranMedia extends ChangeNotifier {
  QuranMedia({
    required this.repository,
    required this.preferences,
    QuranDownloads? downloads,
  }) : downloads = downloads ?? QuranDownloads() {
    this.downloads.addListener(_notify);
  }
  final QuranRepository Function() repository;
  final SharedPreferences Function() preferences;
  final QuranDownloads downloads;
  QuranAudioCatalog? catalog;
  QuranAudioHandler? handler;
  static Future<QuranAudioHandler>? _sharedHandler;
  Future<void>? _initialization;
  final subscriptions = <StreamSubscription<dynamic>>[];
  final favorites = <String>{};
  String selectedChapter = 'mp3quran:123', selectedVerse = 'everyayah:alafasy';
  String? error;
  bool loading = false, _disposed = false;
  int _generation = 0;
  Timer? _timer;
  DateTime? stopAt;
  AudioServiceRepeatMode repeat = AudioServiceRepeatMode.none;
  double _preferredSpeed = 1;
  List<QuranAudioTrack> playingTracks = [];
  QuranAudioTrack? get current {
    final id = handler?.mediaItem.value?.id;
    final found = playingTracks.where((track) => track.id == id);
    return found.isEmpty ? null : found.first;
  }

  bool get playing => handler?.player.playing ?? false;
  double get speed => handler?.player.speed ?? _preferredSpeed;
  Duration get position => handler?.player.position ?? Duration.zero;
  Duration? get duration => handler?.player.duration;
  bool get buffering =>
      loading ||
      handler?.player.processingState == ProcessingState.loading ||
      handler?.player.processingState == ProcessingState.buffering;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initialization ??= _load();
  Future<void> _load() async {
    try {
      catalog ??= await QuranAudioCatalog.load();
      await downloads.initialize();
      final raw = preferences().getString('quran.audio.v1');
      if (raw != null) {
        try {
          final state = jsonDecode(raw) as Map<String, dynamic>;
          selectedChapter = state['chapter'] as String? ?? selectedChapter;
          selectedVerse = state['verse'] as String? ?? selectedVerse;
          _preferredSpeed = ((state['speed'] as num?)?.toDouble() ?? 1).clamp(
            .5,
            2,
          );
          favorites.addAll(
            (state['favorites'] as List? ?? []).whereType<String>(),
          );
        } catch (_) {
          /* Keep available defaults. */
        }
      }
    } catch (_) {
      error = 'تعذّر تحميل قائمة التلاوات';
      _initialization = null;
      rethrow;
    } finally {
      _notify();
    }
  }

  QuranRecitation selection({bool verse = false}) =>
      catalog!.recitations.firstWhere(
        (r) => r.id == (verse ? selectedVerse : selectedChapter),
        orElse: () =>
            catalog!.recitations.firstWhere((r) => r.verseAudio == verse),
      );
  Future<void> select(QuranRecitation recitation) async {
    if (recitation.verseAudio) {
      selectedVerse = recitation.id;
    } else {
      selectedChapter = recitation.id;
    }
    await _persist();
    _notify();
  }

  Future<void> toggleFavorite(String id) async {
    if (!favorites.remove(id)) favorites.add(id);
    await _persist();
    _notify();
  }

  Future<void> _persist() async {
    await preferences().setString(
      'quran.audio.v1',
      jsonEncode({
        'chapter': selectedChapter,
        'verse': selectedVerse,
        'favorites': favorites.toList(),
        'speed': _preferredSpeed,
      }),
    );
  }

  Future<QuranAudioHandler> _audioHandler() async {
    if (handler != null) return handler!;
    _sharedHandler ??= AudioService.init<QuranAudioHandler>(
      builder: QuranAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.haqfoundation.haq_app.quran',
        androidNotificationChannelName: 'تلاوة القرآن الكريم',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
      ),
    );
    try {
      handler = await _sharedHandler;
    } catch (_) {
      _sharedHandler = null;
      rethrow;
    }
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    subscriptions.add(
      handler!.playbackState.listen((state) {
        error = state.errorMessage;
        _notify();
      }),
    );
    subscriptions.add(handler!.mediaItem.listen((_) => _notify()));
    subscriptions.add(handler!.player.positionStream.listen((_) => _notify()));
    subscriptions.add(handler!.player.durationStream.listen((_) => _notify()));
    subscriptions.add(handler!.player.speedStream.listen((_) => _notify()));
    return handler!;
  }

  Future<void> playTracks(List<QuranAudioTrack> tracks, {int start = 0}) async {
    final generation = ++_generation;
    loading = true;
    error = null;
    _notify();
    try {
      await initialize();
      final audio = await _audioHandler();
      final uris = <Uri>[];
      for (var index = 0; index < tracks.length; index++) {
        final track = tracks[index];
        final file = await downloads.localFile(track, verify: index == start);
        uris.add(file?.uri ?? Uri.parse(track.url));
      }
      if (generation != _generation || _disposed) return;
      playingTracks = tracks;
      repeat = AudioServiceRepeatMode.none;
      await audio.load(tracks, uris, start: start);
      await audio.setSpeed(_preferredSpeed);
    } catch (_) {
      if (generation == _generation) {
        error = 'تعذّر تشغيل التلاوة؛ تحقق من الاتصال وأعد المحاولة';
      }
    } finally {
      if (generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> playChapter(int surah) async {
    try {
      await initialize();
    } catch (_) {
      return;
    }
    final recitation = selection();
    final ids = recitation.chapters.toList()..sort();
    if (!ids.contains(surah)) {
      error = 'هذه السورة غير متاحة في التلاوة المختارة';
      _notify();
      return;
    }
    await playTracks(
      ids.map((id) => recitation.track(repository(), id)).toList(),
      start: ids.indexOf(surah),
    );
  }

  Future<void> playVerse(
    QuranVerse verse, {
    int? endAyah,
    int repeats = 1,
  }) async {
    try {
      await initialize();
    } catch (_) {
      return;
    }
    final recitation = selection(verse: true);
    final end = (endAyah ?? verse.ayah).clamp(
      verse.ayah,
      repository().surah(verse.surah).ayahCount,
    );
    final tracks = [
      for (var count = 0; count < repeats.clamp(1, 10); count++)
        for (var ayah = verse.ayah; ayah <= end; ayah++)
          recitation.track(repository(), verse.surah, ayah: ayah),
    ];
    await playTracks(tracks);
  }

  Future<void> playWord(String key, int position, String audioUrl) async {
    final uri = Uri.parse('https://audio.qurancdn.com/').resolve(audioUrl);
    if (uri.host != 'audio.qurancdn.com' || !audioUrl.startsWith('wbw/')) {
      throw ArgumentError('Invalid word recording');
    }
    final verse = repository().byKey[key]!;
    await playTracks([
      QuranAudioTrack(
        id: 'word:$key:$position',
        recitation: 'qurancom:word',
        reciter: 'نطق الكلمة • Quran.com',
        title:
            'سورة ${repository().surah(verse.surah).name} • الآية ${verse.ayah}',
        surah: verse.surah,
        ayah: verse.ayah,
        url: uri.toString(),
        version: 'wbw-v1',
        quality: 'نطق الكلمة',
      ),
    ]);
  }

  Future<void> toggle() async {
    if (handler == null) return;
    try {
      if (playing) {
        await handler!.pause();
      } else {
        unawaited(
          handler!.play().catchError((Object _) {
            error = 'تعذّر استئناف التشغيل';
            _notify();
          }),
        );
      }
    } catch (_) {
      error = 'تعذّر تغيير حالة التشغيل';
      _notify();
    }
  }

  Future<void> seek(Duration value) async {
    if (handler != null) {
      await handler!.seek(
        Duration(
          milliseconds: value.inMilliseconds.clamp(
            0,
            duration?.inMilliseconds ?? value.inMilliseconds,
          ),
        ),
      );
    }
  }

  Future<void> skip(int delta) async {
    if (handler != null) {
      if (delta > 0) {
        await handler!.skipToNext();
      } else {
        await handler!.skipToPrevious();
      }
    }
  }

  Future<void> setSpeed(double value) async {
    _preferredSpeed = value.clamp(.5, 2);
    await handler?.setSpeed(_preferredSpeed);
    await _persist();
    _notify();
  }

  Future<void> setRepeat(AudioServiceRepeatMode value) async {
    repeat = value;
    await handler?.setRepeatMode(value);
    _notify();
  }

  void setTimer(Duration? duration) {
    _timer?.cancel();
    stopAt = duration == null ? null : DateTime.now().add(duration);
    if (duration != null) {
      _timer = Timer(duration, () {
        unawaited(handler?.pause() ?? Future.value());
        stopAt = null;
        _notify();
      });
    }
    _notify();
  }

  Future<void> stop() async {
    ++_generation;
    loading = false;
    _timer?.cancel();
    stopAt = null;
    await handler?.stop();
    playingTracks = [];
    error = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    downloads.removeListener(_notify);
    downloads.dispose();
    _timer?.cancel();
    super.dispose();
  }
}
