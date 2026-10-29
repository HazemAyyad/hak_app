import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'prayer_alert.dart';

abstract class AdhanPreviewAudio {
  Future<void> play(Uri uri);
  Future<void> stop();
  Future<void> dispose();
}

class NativeAdhanPreview implements AdhanPreviewAudio {
  AudioPlayer? _player;
  int _generation = 0;
  @override
  Future<void> play(Uri uri) async {
    final generation = ++_generation;
    final player = _player ??= AudioPlayer(useProxyForRequestHeaders: false);
    await player.stop();
    if (generation != _generation) return;
    await player.setUrl(uri.toString());
    if (generation != _generation) return;
    // play() completes when playback ends, not when it starts.
    await player.play();
  }

  @override
  Future<void> stop() async {
    ++_generation;
    await _player?.stop();
  }

  @override
  Future<void> dispose() async {
    ++_generation;
    await _player?.dispose();
  }
}

class AdhanLibrary extends ChangeNotifier {
  AdhanLibrary({
    Dio? dio,
    this.directory,
    AdhanPreviewAudio? audio,
    this.prepare,
    this.preparePair,
    this.assetLoader,
    Iterable<AdhanVoice>? catalog,
    this.beforePlay,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 40),
             ),
           ),
       audio = audio ?? NativeAdhanPreview(),
       catalog = List.unmodifiable(catalog ?? allAdhanVoices);
  final Dio dio;
  final Future<Directory> Function()? directory;
  final AdhanPreviewAudio audio;
  final Future<bool> Function(String id, String path)? prepare;
  final Future<bool> Function(String id, String path, String? shortPath)?
  preparePair;
  final Future<ByteData> Function(String asset)? assetLoader;
  final List<AdhanVoice> catalog;
  AdhanVoice? _voice(String id) => catalog.where((v) => v.id == id).firstOrNull;
  final Future<void> Function()? beforePlay;
  final downloaded = <String>{};
  String? downloading, playing, error;
  double? progress;
  bool _disposed = false;
  int _session = 0;
  CancelToken? _cancel;
  Future<void>? _initializing;
  Directory? _root;
  static const maxBytes = 20 * 1024 * 1024;
  static const bridge = MethodChannel('com.haqfoundation.haq_app/reminders');
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<Directory> _folder() async {
    if (_root != null) return _root!;
    final support =
        await (directory?.call() ?? getApplicationSupportDirectory());
    final root = Directory('${support.path}/adhans');
    await root.create(recursive: true);
    return _root = root;
  }

  Future<void> initialize() => _initializing ??= _restore();
  File _audioFile(Directory root, String id, bool short) =>
      File('${root.path}/$id${short ? '-takbeer' : ''}.mp3');
  File _receipt(Directory root, String id, bool short) =>
      File('${root.path}/$id${short ? '-takbeer' : ''}.json');
  Uri _uri(AdhanVoice voice, bool short) => short ? voice.shortUri! : voice.uri;
  void _verify(List<int> bytes, AdhanVoice voice, bool short) {
    final expectedBytes = short ? voice.shortBytes : voice.bytes;
    final expectedHash = short ? voice.shortSha256 : voice.sha256;
    final signature =
        bytes.length > 3 &&
        ((bytes[0] == 73 && bytes[1] == 68 && bytes[2] == 51) ||
            (bytes[0] == 255 && bytes[1] & 224 == 224));
    if (bytes.length < 1000 ||
        bytes.length > maxBytes ||
        !signature ||
        (expectedBytes != null && bytes.length != expectedBytes) ||
        (expectedHash != null &&
            sha256.convert(bytes).toString() != expectedHash)) {
      throw const FormatException('Recording integrity mismatch');
    }
  }

  Future<bool> _cached(Directory root, AdhanVoice voice, bool short) async {
    try {
      final file = _audioFile(root, voice.id, short);
      final meta =
          jsonDecode(await _receipt(root, voice.id, short).readAsString())
              as Map;
      final size = await file.length();
      if (size < 1000 || size > maxBytes) return false;
      final bytes = await file.readAsBytes();
      _verify(bytes, voice, short);
      return meta['source'] == _uri(voice, short).toString() &&
          meta['bytes'] == size &&
          meta['sha256'] == sha256.convert(bytes).toString();
    } catch (_) {
      return false;
    }
  }

  Future<void> _store(
    Directory root,
    AdhanVoice voice,
    bool short,
    List<int> bytes,
  ) async {
    _verify(bytes, voice, short);
    final file = _audioFile(root, voice.id, short);
    final temporary = File('${file.path}.part');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
      await _receipt(root, voice.id, short).writeAsString(
        jsonEncode({
          'source': _uri(voice, short).toString(),
          'bytes': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        }),
        flush: true,
      );
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _restore() async {
    try {
      final root = await _folder();
      for (final voice in catalog) {
        try {
          var valid =
              await _cached(root, voice, false) &&
              (!voice.hasShort || await _cached(root, voice, true));
          if (!valid && voice.bundled) {
            // Only the two bundled voices are installed at startup. No HTTP.
            final full =
                await (assetLoader?.call(voice.asset!) ??
                    rootBundle.load(voice.asset!));
            final short =
                await (assetLoader?.call(voice.shortAsset!) ??
                    rootBundle.load(voice.shortAsset!));
            final fullBytes = full.buffer.asUint8List(
              full.offsetInBytes,
              full.lengthInBytes,
            );
            final shortBytes = short.buffer.asUint8List(
              short.offsetInBytes,
              short.lengthInBytes,
            );
            _verify(fullBytes, voice, false);
            _verify(shortBytes, voice, true);
            await _store(root, voice, false, fullBytes);
            await _store(root, voice, true, shortBytes);
            valid = true;
          }
          if (valid) downloaded.add(voice.id);
        } catch (_) {
          error = 'تعذّر تجهيز أحد أصوات الأذان المرفقة. أعد المحاولة.';
        }
      }
    } catch (_) {
      error = 'تعذّر فحص أصوات الأذان المحفوظة. أعد المحاولة.';
    }
    _emit();
  }

  Future<bool> prepareVoice(String id) async {
    final voice = _voice(id);
    if (voice == null) return false;
    await initialize();
    if (!downloaded.contains(id)) {
      error = 'نزّل صوت المؤذن أولًا ليعمل التنبيه دون اتصال.';
      _emit();
      return false;
    }
    try {
      final root = await _folder();
      final path = '${root.path}/$id.mp3';
      final shortPath = voice.hasShort ? '${root.path}/$id-takbeer.mp3' : null;
      final ok =
          await (preparePair?.call(id, path, shortPath) ??
              prepare?.call(id, path) ??
              bridge
                  .invokeMethod<bool>('prepareAdhan', {
                    'id': id,
                    'path': path,
                    'shortPath': shortPath,
                  })
                  .then((v) => v == true));
      if (!ok) throw StateError('prepare');
      return true;
    } catch (_) {
      error = 'الصوت محفوظ، لكن تعذّر تهيئته لتنبيه الجهاز. أعد المحاولة.';
      _emit();
      return false;
    }
  }

  Future<bool> download(AdhanVoice voice) async {
    if (_voice(voice.id)?.sameRecording(voice) != true) {
      return false;
    }
    if (_disposed || downloading != null) return false;
    await initialize();
    if (_disposed || downloading != null) return false;
    if (downloaded.contains(voice.id)) return prepareVoice(voice.id);
    downloading = voice.id;
    progress = null;
    error = null;
    final cancel = _cancel = CancelToken();
    _emit();
    try {
      final variants = <bool, List<int>>{};
      for (final short in [false, if (voice.hasShort) true]) {
        final response = await dio.get<List<int>>(
          _uri(voice, short).toString(),
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: false,
          ),
          onReceiveProgress: (received, total) {
            if (received > maxBytes || total > maxBytes) cancel.cancel('size');
            progress = total > 0 ? (received / total).clamp(0, 1) : null;
            _emit();
          },
        );
        final bytes = response.data!;
        if (_disposed || cancel.isCancelled) return false;
        final mime = response.headers.value('content-type')?.split(';').first;
        if (response.statusCode != 200 ||
            !{
              'audio/mpeg',
              'audio/mp3',
              'application/octet-stream',
            }.contains(mime)) {
          throw const FormatException('Invalid audio download');
        }
        _verify(bytes, voice, short);
        variants[short] = bytes;
      }
      final root = await _folder();
      if (_disposed || cancel.isCancelled) return false;
      for (final entry in variants.entries) {
        await _store(root, voice, entry.key, entry.value);
      }
      downloaded.add(voice.id);
      return await prepareVoice(voice.id);
    } catch (_) {
      if (!_disposed) {
        error = cancel.isCancelled
            ? 'أُلغي التنزيل أو تجاوز حجم الملف المسموح.'
            : 'تعذّر تنزيل الصوت؛ تحقق من الاتصال وأعد المحاولة.';
      }
      return false;
    } finally {
      downloading = null;
      progress = null;
      _cancel = null;
      _emit();
    }
  }

  Future<void> preview(AdhanVoice voice) async {
    if (_voice(voice.id)?.sameRecording(voice) != true) return;
    if (_disposed) return;
    if (playing == voice.id) {
      await stop();
      return;
    }
    final session = ++_session;
    playing = voice.id;
    error = null;
    _emit();
    try {
      await audio.stop();
      await beforePlay?.call();
      await initialize();
      if (_disposed || session != _session) return;
      final root = await _folder();
      if (_disposed || session != _session) return;
      final uri = downloaded.contains(voice.id)
          ? Uri.file('${root.path}/${voice.id}.mp3')
          : voice.uri;
      await audio.play(uri);
    } catch (_) {
      if (session == _session) {
        error = 'تعذّر تشغيل معاينة الصوت على هذا الجهاز.';
      }
    } finally {
      if (session == _session) playing = null;
      _emit();
    }
  }

  Future<void> stop() async {
    ++_session;
    playing = null;
    await audio.stop();
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_session;
    _cancel?.cancel('dispose');
    unawaited(audio.dispose());
    super.dispose();
  }
}
