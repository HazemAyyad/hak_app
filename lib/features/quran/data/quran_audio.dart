import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quran_audio_models.dart';
import 'quran_downloads.dart';
import 'quran_repository.dart';
import 'quran_playback_ownership.dart';

class QuranAudioHandler extends BaseAudioHandler with SeekHandler {
  QuranAudioHandler({AudioPlayer? player})
    : player = player ?? AudioPlayer(useProxyForRequestHeaders: false) {
    this.player.playbackEventStream.listen(_broadcast);
    this.player.playerStateStream.listen((_) => _broadcast());
    this.player.sequenceStateStream.listen((_) => _broadcast());
    this.player.errorStream.listen((error) {
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          errorCode: error.code,
          errorMessage:
              'تعذّر تشغيل التلاوة؛ تحقق من الاتصال أو أعد تنزيل الملف',
        ),
      );
    });
  }
  final AudioPlayer player;
  final ownership = QuranPlaybackOwnership();
  int _loadGeneration = 0;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  void _broadcast([PlaybackEvent? event]) {
    final currentEvent = event ?? player.playbackEvent;
    final index = currentEvent.currentIndex;
    if (index != null && index >= 0 && index < queue.value.length) {
      final queued = queue.value[index];
      final source = index < player.sequence.length
          ? player.sequence[index].tag
          : null;
      // The duration and index must come from the same playback event. Keeping
      // it in the queue also preserves it when returning to a loaded recording.
      if (source is MediaItem && source.id == queued.id) {
        final duration = currentEvent.duration;
        final current = duration != null && duration > Duration.zero
            ? queued.copyWith(duration: duration)
            : queued;
        if (current.duration != queued.duration) {
          final items = List<MediaItem>.of(queue.value)..[index] = current;
          queue.add(items);
        }
        if (mediaItem.value?.id != current.id ||
            mediaItem.value?.duration != current.duration) {
          mediaItem.add(current);
        }
      }
    }
    final hasTrack = index != null && index >= 0 && index < queue.value.length;
    final isPlaying =
        player.playing && player.processingState != ProcessingState.completed;
    final controls = [
      if (hasTrack && player.hasPrevious) MediaControl.skipToPrevious,
      if (hasTrack) isPlaying ? MediaControl.pause : MediaControl.play,
      if (hasTrack && player.hasNext) MediaControl.skipToNext,
    ];
    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: {
          if (hasTrack) ...{
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
        },
        androidCompactActionIndices: List.generate(controls.length, (i) => i),
        processingState: switch (player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: isPlaying,
        updatePosition: player.position,
        bufferedPosition: currentEvent.bufferedPosition,
        speed: player.speed,
        queueIndex: player.currentIndex,
        repeatMode: _repeatMode,
      ),
    );
  }

  Future<void> load(
    List<QuranAudioTrack> tracks,
    List<Uri> uris, {
    int start = 0,
    bool Function()? isCurrent,
  }) async {
    if (tracks.isEmpty || tracks.length != uris.length) {
      throw ArgumentError('A recording URI is required for every track');
    }
    RangeError.checkValidIndex(start, tracks, 'start');
    final generation = ++_loadGeneration;
    bool valid() =>
        generation == _loadGeneration && (isCurrent?.call() ?? true);
    await player.stop();
    if (!valid()) return;
    queue.add(
      tracks.asMap().entries.map((entry) {
        final track = entry.value;
        final portrait = reciterPortrait(track.reciter);
        return MediaItem(
          id: '${track.id}#queue-${entry.key}',
          title: track.title,
          artist: track.reciter,
          displayTitle: track.title,
          displaySubtitle: track.reciter,
          artUri: portrait == null ? null : Uri.parse(portrait),
          isLive: false,
          extras: {
            for (final value in track.toJson().entries)
              if (value.value != null) value.key: value.value,
            'trackId': track.id,
          },
        );
      }).toList(),
    );
    mediaItem.add(queue.value[start]);
    await player.setLoopMode(LoopMode.off);
    if (!valid()) return;
    _repeatMode = AudioServiceRepeatMode.none;
    await player.setAudioSources(
      [
        for (var index = 0; index < uris.length; index++)
          AudioSource.uri(uris[index], tag: queue.value[index]),
      ],
      initialIndex: start,
      initialPosition: Duration.zero,
    );
    if (!valid()) return;
    _broadcast();
    unawaited(
      play().catchError((Object error) {
        if (!valid()) return;
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
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
      await player.seek(Duration.zero, index: player.currentIndex);
    }
    await player.play();
  }

  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> seek(Duration position) => player.seek(
    Duration(
      milliseconds: position.inMilliseconds.clamp(
        0,
        player.duration?.inMilliseconds ??
            mediaItem.value?.duration?.inMilliseconds ??
            (position.isNegative ? 0 : position.inMilliseconds),
      ),
    ),
  );
  @override
  Future<void> fastForward() =>
      seek(player.position + const Duration(seconds: 10));
  @override
  Future<void> rewind() => seek(player.position - const Duration(seconds: 10));
  @override
  Future<void> skipToNext() async {
    if (player.hasNext) await player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (player.hasPrevious) await player.seekToPrevious();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < queue.value.length) {
      await player.seek(Duration.zero, index: index);
    }
  }

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
    await seekForward(false);
    await player.stop();
    await super.stop();
  }
}

class QuranMedia extends ChangeNotifier {
  QuranMedia({
    required this.repository,
    required this.preferences,
    QuranDownloads? downloads,
    this.storageKey = 'quran.audio.v1',
    this.handlerFactory,
  }) : downloads = downloads ?? QuranDownloads() {
    this.downloads.addListener(_notify);
  }
  final QuranRepository Function() repository;
  final SharedPreferences Function() preferences;
  final String storageKey;
  final QuranDownloads downloads;
  final Future<QuranAudioHandler> Function()? handlerFactory;
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
  bool _lostOwnership = false;
  Timer? _timer;
  DateTime? stopAt;
  AudioServiceRepeatMode repeat = AudioServiceRepeatMode.none;
  double _preferredSpeed = 1;
  List<QuranAudioTrack> playingTracks = [];
  bool get ownsPlayback =>
      !_disposed &&
      handler != null &&
      (handler!.ownership.owns(this) ||
          !_lostOwnership && handler!.ownership.unclaimed);
  QuranAudioTrack? get current {
    if (!ownsPlayback) return null;
    final item = handler?.mediaItem.value;
    final id = item?.extras?['trackId'] ?? item?.id;
    final found = playingTracks.where((track) => track.id == id);
    return found.isEmpty ? null : found.first;
  }

  bool get playing =>
      ownsPlayback && (handler?.playbackState.value.playing ?? false);
  double get speed => ownsPlayback ? handler!.player.speed : _preferredSpeed;
  Duration get position =>
      ownsPlayback ? handler!.player.position : Duration.zero;
  Duration? get duration => ownsPlayback
      ? handler?.player.duration ?? handler?.mediaItem.value?.duration
      : null;
  bool get buffering =>
      loading ||
      (ownsPlayback &&
          (handler?.player.processingState == ProcessingState.loading ||
              handler?.player.processingState == ProcessingState.buffering));
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initialization ??= _load();
  Future<void> _load() async {
    try {
      catalog ??= await QuranAudioCatalog.load();
      await downloads.initialize();
      final raw = preferences().getString(storageKey);
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
      storageKey,
      jsonEncode({
        'chapter': selectedChapter,
        'verse': selectedVerse,
        'favorites': favorites.toList(),
        'speed': _preferredSpeed,
      }),
    );
  }

  Future<QuranAudioHandler> _audioHandler() async {
    if (_disposed) throw StateError('Audio facade disposed');
    if (handler != null) return handler!;
    if (handlerFactory != null) {
      handler = await handlerFactory!();
      if (_disposed) throw StateError('Audio facade disposed');
      return handler!;
    }
    _sharedHandler ??= AudioService.init<QuranAudioHandler>(
      builder: QuranAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.haqfoundation.haq_app.quran',
        androidNotificationChannelName: 'تلاوة القرآن الكريم',
        androidNotificationIcon: 'drawable/ic_quran_notification',
        notificationColor: Color(0xFF006570),
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
    if (_disposed) throw StateError('Audio facade disposed');
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    if (_disposed) throw StateError('Audio facade disposed');
    subscriptions.add(
      handler!.playbackState.listen((state) {
        if (ownsPlayback) error = state.errorMessage;
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
    if (tracks.isEmpty || start < 0 || start >= tracks.length) {
      throw ArgumentError('A valid nonempty recording queue is required');
    }
    final generation = ++_generation;
    loading = true;
    error = null;
    _notify();
    try {
      await initialize();
      final audio = await _audioHandler();
      if (generation != _generation || _disposed) return;
      audio.ownership.claim(this, _lostPlayback);
      _lostOwnership = false;
      final uris = <Uri>[];
      for (var index = 0; index < tracks.length; index++) {
        final track = tracks[index];
        final file = await downloads.localFile(track, verify: index == start);
        uris.add(file?.uri ?? Uri.parse(track.url));
      }
      if (generation != _generation || _disposed || !ownsPlayback) return;
      await audio.ownership.run(this, () async {
        if (generation != _generation || _disposed) return;
        playingTracks = List.unmodifiable(tracks);
        repeat = AudioServiceRepeatMode.none;
        await audio.load(
          tracks,
          uris,
          start: start,
          isCurrent: () =>
              generation == _generation && !_disposed && ownsPlayback,
        );
        if (ownsPlayback) await audio.setSpeed(_preferredSpeed);
      });
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
    if (!ownsPlayback) return;
    try {
      if (playing) {
        await _control(handler!.pause);
      } else {
        unawaited(
          _control(() async {
            unawaited(
              handler!.play().catchError((Object _) {
                if (!ownsPlayback || _disposed) return;
                error = 'تعذّر استئناف التشغيل';
                _notify();
              }),
            );
          }),
        );
      }
    } catch (_) {
      error = 'تعذّر تغيير حالة التشغيل';
      _notify();
    }
  }

  Future<void> seek(Duration value) async {
    if (ownsPlayback) {
      await _control(() => handler!.seek(value));
    }
  }

  Future<void> skip(int delta) async {
    if (ownsPlayback) {
      if (delta > 0) {
        await _control(handler!.skipToNext);
      } else {
        await _control(handler!.skipToPrevious);
      }
    }
  }

  Future<void> setSpeed(double value) async {
    _preferredSpeed = value.clamp(.5, 2);
    await _control(() => handler!.setSpeed(_preferredSpeed));
    await _persist();
    _notify();
  }

  Future<void> setRepeat(AudioServiceRepeatMode value) async {
    repeat = value;
    await _control(() => handler!.setRepeatMode(value));
    _notify();
  }

  void setTimer(Duration? duration) {
    _timer?.cancel();
    if (!ownsPlayback || duration != null && duration <= Duration.zero) {
      duration = null;
    }
    stopAt = duration == null ? null : DateTime.now().add(duration);
    if (duration != null) {
      _timer = Timer(duration, () {
        unawaited(
          _control(() => handler!.pause()).catchError((Object _) {
            if (!ownsPlayback || _disposed) return;
            error = 'تعذّر إيقاف التشغيل';
            _notify();
          }),
        );
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
    await _control(() => handler!.stop());
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
    handler?.ownership.release(this);
    super.dispose();
  }

  void _lostPlayback() {
    _lostOwnership = true;
    ++_generation;
    _timer?.cancel();
    stopAt = null;
    loading = false;
    playingTracks = [];
    error = null;
    _notify();
  }

  Future<void> _control(Future<void> Function() command) async {
    if (!ownsPlayback || _disposed) return;
    final audio = handler!;
    if (audio.ownership.unclaimed) audio.ownership.claim(this, _lostPlayback);
    await audio.ownership.run(this, command);
  }
}
