import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'quran_audio_models.dart';

enum QuranDownloadState { queued, downloading, paused, failed, complete }

class QuranDownload {
  QuranDownload(
    this.track, {
    this.state = QuranDownloadState.queued,
    this.received = 0,
    this.total = 0,
    this.digest,
    this.error,
    String? created,
  }) : created = created ?? DateTime.now().toUtc().toIso8601String();
  final QuranAudioTrack track;
  final String created;
  QuranDownloadState state;
  int received, total;
  String? digest, error;
  Map<String, dynamic> toJson() => {
    'track': track.toJson(),
    'state': state.name,
    'received': received,
    'total': total,
    'digest': digest,
    'created': created,
  };
  factory QuranDownload.fromJson(Map<String, dynamic> json) => QuranDownload(
    QuranAudioTrack.fromJson(json['track'] as Map<String, dynamic>),
    state: QuranDownloadState.values.byName(json['state'] as String),
    received: json['received'] as int,
    total: json['total'] as int,
    digest: json['digest'] as String?,
    created: json['created'] as String,
  );
}

class QuranDownloads extends ChangeNotifier {
  QuranDownloads({
    Directory? directory,
    Dio? dio,
    this.storageFolder = 'quran_audio_v1',
  }) : _directory = directory,
       dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 25),
               receiveTimeout: const Duration(seconds: 40),
             ),
           );
  final Dio dio;
  final String storageFolder;
  Directory? _directory;
  final entries = <String, QuranDownload>{};
  Future<void>? _initialization, _worker;
  Future<void> _writes = Future.value();
  CancelToken? _cancel;
  String? _active;
  Completer<void>? _activeDone;
  bool _disposed = false;
  String? storageError;
  Future<int>? _usage;
  DateTime? _usageTime;
  Future<Directory> directory() async {
    _directory ??= await getApplicationSupportDirectory().then(
      (dir) => Directory('${dir.path}/$storageFolder').create(recursive: true),
    );
    await _directory!.create(recursive: true);
    return _directory!;
  }

  Future<File> _file(
    QuranAudioTrack track, {
    bool partial = false,
  }) async => File(
    '${(await directory()).path}/${track.storageKey}.mp3${partial ? '.part' : ''}',
  );
  Future<void> initialize() => _initialization ??= _read();
  Future<void> _read() async {
    final index = File('${(await directory()).path}/index.json');
    if (await index.exists()) {
      try {
        for (final raw in jsonDecode(await index.readAsString()) as List) {
          try {
            final entry = QuranDownload.fromJson(raw as Map<String, dynamic>);
            final file = await _file(entry.track);
            if (entry.state == QuranDownloadState.complete) {
              if (!await file.exists() ||
                  await file.length() != entry.total ||
                  entry.digest == null) {
                entry.state = QuranDownloadState.failed;
                entry.error = 'الملف غير مكتمل؛ أعد تنزيله';
              }
            } else {
              final partial = await _file(entry.track, partial: true);
              entry.received = await partial.exists()
                  ? await partial.length()
                  : 0;
              if (entry.state == QuranDownloadState.downloading ||
                  entry.state == QuranDownloadState.queued) {
                entry.state = QuranDownloadState.paused;
              }
            }
            entries[entry.track.id] = entry;
          } catch (_) {
            /* Isolate one damaged record from the rest of the downloads. */
          }
        }
      } catch (_) {
        storageError = 'تعذّر استعادة قائمة التحميل';
      }
    }
    _emit();
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _persist() {
    final snapshot = jsonEncode(
      entries.values.map((entry) => entry.toJson()).toList(),
    );
    _writes = _writes.catchError((Object _) {}).then((_) async {
      final target = File('${(await directory()).path}/index.json');
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(snapshot, flush: true);
      await temporary.rename(target.path);
    });
    return _writes;
  }

  /// Wait for already queued manifest writes, including the final dispose save.
  Future<void> flush() => _writes;

  void _save() {
    unawaited(
      _persist().catchError((Object _) {
        storageError = 'تعذّر حفظ حالة التحميل؛ تحقق من مساحة الجهاز';
        _emit();
      }),
    );
  }

  Future<void> enqueue(QuranAudioTrack track) async {
    await initialize();
    await _waitForCancelledActive({track.id});
    final existing = entries[track.id];
    if (existing?.state == QuranDownloadState.complete &&
        existing!.track.version == track.version) {
      return;
    }
    if (existing?.state == QuranDownloadState.downloading) return;
    final entry = existing != null && existing.track.version == track.version
        ? existing
        : QuranDownload(track);
    entry.state = QuranDownloadState.queued;
    entry.error = null;
    entries[track.id] = entry;
    _save();
    _emit();
    _start();
  }

  Future<void> enqueueAll(Iterable<QuranAudioTrack> tracks) async {
    await initialize();
    final requested = tracks.toList();
    await _waitForCancelledActive(requested.map((track) => track.id).toSet());
    for (final track in requested) {
      final existing = entries[track.id];
      if (existing?.state == QuranDownloadState.downloading ||
          existing?.state == QuranDownloadState.complete &&
              existing!.track.version == track.version) {
        continue;
      }
      final entry = existing != null && existing.track.version == track.version
          ? existing
          : QuranDownload(track);
      entry.state = QuranDownloadState.queued;
      entry.error = null;
      entries[track.id] = entry;
    }
    _save();
    _emit();
    _start();
  }

  Future<void> _waitForCancelledActive(Set<String> ids) async {
    if (ids.contains(_active) && _cancel?.isCancelled == true) {
      // Do not requeue the same mutable entry until its old transfer has closed.
      // Otherwise cancellation can mark the resumed request paused again.
      await _activeDone?.future;
    }
  }

  void _start() {
    if (_worker != null || _disposed) return;
    _worker = _work().whenComplete(() {
      _worker = null;
      if (!_disposed &&
          entries.values.any(
            (entry) => entry.state == QuranDownloadState.queued,
          )) {
        _start();
      }
    });
  }

  Future<void> _work() async {
    while (!_disposed) {
      final waiting = entries.values
          .where((entry) => entry.state == QuranDownloadState.queued)
          .toList();
      if (waiting.isEmpty) return;
      final entry = waiting.first;
      _active = entry.track.id;
      _activeDone = Completer<void>();
      _cancel = CancelToken();
      entry.state = QuranDownloadState.downloading;
      _save();
      _emit();
      RandomAccessFile? sink;
      try {
        final partial = await _file(entry.track, partial: true);
        var offset = await partial.exists() ? await partial.length() : 0;
        final response = await dio.get<ResponseBody>(
          entry.track.url,
          cancelToken: _cancel,
          options: Options(
            responseType: ResponseType.stream,
            headers: offset > 0 ? {'Range': 'bytes=$offset-'} : {},
            validateStatus: (status) => status == 200 || status == 206,
          ),
        );
        if (response.statusCode == 206) {
          final range = response.headers.value('content-range') ?? '';
          if (!range.startsWith('bytes $offset-')) {
            throw const FormatException('Invalid resume range');
          }
        } else {
          offset = 0;
        }
        final length =
            int.tryParse(response.headers.value('content-length') ?? '') ?? 0;
        entry.total = length == 0 ? 0 : offset + length;
        entry.received = offset;
        sink = await partial.open(
          mode: offset > 0 ? FileMode.append : FileMode.write,
        );
        var lastNotify = DateTime.now();
        await for (final bytes in response.data!.stream) {
          if (_disposed || _cancel!.isCancelled) {
            throw DioException(
              requestOptions: response.requestOptions,
              type: DioExceptionType.cancel,
            );
          }
          await sink.writeFrom(bytes);
          entry.received += bytes.length;
          if (DateTime.now().difference(lastNotify).inMilliseconds >= 180) {
            _emit();
            lastNotify = DateTime.now();
          }
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (_cancel!.isCancelled || _disposed) {
          throw DioException(
            requestOptions: response.requestOptions,
            type: DioExceptionType.cancel,
          );
        }
        final actual = await partial.length();
        if (actual < 128 || entry.total > 0 && actual != entry.total) {
          throw const FormatException('Incomplete audio file');
        }
        final header = await partial.open();
        final bytes = await header.read(3);
        await header.close();
        if (!(bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33 ||
            bytes[0] == 0xFF && bytes[1] & 0xE0 == 0xE0)) {
          throw const FormatException('Response is not MP3 audio');
        }
        entry.digest = (await sha256.bind(partial.openRead()).first).toString();
        if (_cancel!.isCancelled || _disposed) {
          throw DioException(
            requestOptions: response.requestOptions,
            type: DioExceptionType.cancel,
          );
        }
        await partial.rename((await _file(entry.track)).path);
        entry.total = actual;
        entry.received = actual;
        entry.state = QuranDownloadState.complete;
        _usage = null;
        entry.error = null;
        await _persist();
      } catch (error) {
        if (error is FormatException) {
          final invalid = await _file(entry.track, partial: true);
          if (await invalid.exists()) await invalid.delete();
          entry.received = 0;
        }
        if (entry.state == QuranDownloadState.downloading ||
            entry.state == QuranDownloadState.complete) {
          entry.state =
              error is DioException && error.type == DioExceptionType.cancel
              ? QuranDownloadState.paused
              : QuranDownloadState.failed;
          entry.error = entry.state == QuranDownloadState.failed
              ? 'فشل التنزيل؛ تحقق من الاتصال ومساحة الجهاز وأعد المحاولة'
              : null;
        }
        _save();
      } finally {
        await sink?.close();
        _active = null;
        _cancel = null;
        _activeDone?.complete();
        _activeDone = null;
        _emit();
      }
    }
  }

  Future<void> pause(String id) => pauseAll([id]);

  /// Pauses the selected tasks atomically before cancelling the active stream.
  /// Omitting [ids] pauses every pending download, while completed files remain.
  Future<void> pauseAll([Iterable<String>? ids]) async {
    await initialize();
    final selected = ids?.toSet();
    Completer<void>? cancelled;
    for (final entry in entries.values) {
      if (selected != null && !selected.contains(entry.track.id)) continue;
      if (entry.state != QuranDownloadState.downloading &&
          entry.state != QuranDownloadState.queued) {
        continue;
      }
      entry.state = QuranDownloadState.paused;
      entry.error = null;
      if (_active == entry.track.id) {
        cancelled = _activeDone;
        _cancel?.cancel('Download paused');
      }
    }
    _emit();
    // Wait until the partial file is closed so an immediate resume uses its
    // final on-disk offset rather than racing the cancelled transfer.
    await cancelled?.future;
    await _persist();
  }

  Future<void> remove(String id) async {
    final entry = entries[id];
    if (entry == null) return;
    if (_active == id) {
      final done = _activeDone;
      await pause(id);
      await done?.future;
    }
    if (entry.state != QuranDownloadState.complete) await pause(id);
    for (final partial in [false, true]) {
      final file = await _file(entry.track, partial: partial);
      if (await file.exists()) await file.delete();
    }
    entries.remove(id);
    _usage = null;
    await _persist();
    _emit();
  }

  Future<File?> localFile(QuranAudioTrack track, {bool verify = false}) async {
    await initialize();
    final entry = entries[track.id];
    if (entry == null ||
        entry.track.version != track.version ||
        entry.state != QuranDownloadState.complete) {
      return null;
    }
    final file = await _file(track);
    if (!await file.exists() ||
        await file.length() != entry.total ||
        verify &&
            (await sha256.bind(file.openRead()).first).toString() !=
                entry.digest) {
      entry.state = QuranDownloadState.failed;
      entry.error = 'الملف تالف؛ أعد تنزيله';
      _save();
      _emit();
      return null;
    }
    return file;
  }

  Future<int> diskUsage() {
    if (_usage != null &&
        DateTime.now().difference(_usageTime!).inSeconds < 2) {
      return _usage!;
    }
    _usageTime = DateTime.now();
    return _usage = _diskUsage();
  }

  Future<int> _diskUsage() async {
    var bytes = 0;
    await for (final file in (await directory()).list()) {
      if (file is File &&
          (file.path.endsWith('.mp3') || file.path.endsWith('.part'))) {
        bytes += await file.length();
      }
    }
    return bytes;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    if (_initialization != null) _save();
    super.dispose();
  }
}
