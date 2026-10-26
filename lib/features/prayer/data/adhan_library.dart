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
    this.beforePlay,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 40),
             ),
           ),
       audio = audio ?? NativeAdhanPreview();
  final Dio dio;
  final Future<Directory> Function()? directory;
  final AdhanPreviewAudio audio;
  final Future<bool> Function(String id, String path)? prepare;
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
  Future<void> _restore() async {
    try {
      final root = await _folder();
      for (final voice in adhanVoices) {
        final file = File('${root.path}/${voice.id}.mp3');
        final receipt = File('${root.path}/${voice.id}.json');
        if (await file.exists() && await receipt.exists()) {
          final meta = jsonDecode(await receipt.readAsString()) as Map;
          final size = await file.length();
          if (size > 1000 &&
              size <= maxBytes &&
              meta['bytes'] == size &&
              meta['sha256'] ==
                  (await sha256.bind(file.openRead()).first).toString()) {
            downloaded.add(voice.id);
          }
        }
      }
    } catch (_) {
      error = 'تعذّر فحص أصوات الأذان المحفوظة. أعد المحاولة.';
    }
    _emit();
  }

  Future<bool> prepareVoice(String id) async {
    if (!adhanVoices.any((v) => v.id == id)) return false;
    if (!downloaded.contains(id)) {
      error = 'نزّل صوت المؤذن أولًا ليعمل التنبيه دون اتصال.';
      _emit();
      return false;
    }
    try {
      final root = await _folder();
      final path = '${root.path}/$id.mp3';
      final ok =
          await (prepare?.call(id, path) ??
              bridge
                  .invokeMethod<bool>('prepareAdhan', {'id': id, 'path': path})
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
    if (!adhanVoices.any((v) => v.id == voice.id && v.uri == voice.uri)) {
      return false;
    }
    if (_disposed || downloading != null) return false;
    if (downloaded.contains(voice.id)) return prepareVoice(voice.id);
    downloading = voice.id;
    progress = null;
    error = null;
    final cancel = _cancel = CancelToken();
    File? temporary;
    _emit();
    try {
      final response = await dio.get<List<int>>(
        voice.uri.toString(),
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
      final signature =
          bytes.length > 3 &&
          ((bytes[0] == 73 && bytes[1] == 68 && bytes[2] == 51) ||
              (bytes[0] == 255 && bytes[1] & 224 == 224));
      if (response.statusCode != 200 ||
          bytes.length < 1000 ||
          bytes.length > maxBytes ||
          !signature ||
          !{
            'audio/mpeg',
            'audio/mp3',
            'application/octet-stream',
          }.contains(mime)) {
        throw const FormatException('Invalid audio download');
      }
      final root = await _folder();
      temporary = File('${root.path}/${voice.id}.part');
      await temporary.writeAsBytes(bytes, flush: true);
      if (_disposed || cancel.isCancelled) return false;
      await temporary.rename('${root.path}/${voice.id}.mp3');
      await File('${root.path}/${voice.id}.json').writeAsString(
        jsonEncode({
          'bytes': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
          'source': voice.uri.toString(),
        }),
        flush: true,
      );
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
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      downloading = null;
      progress = null;
      _cancel = null;
      _emit();
    }
  }

  Future<void> preview(AdhanVoice voice) async {
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
