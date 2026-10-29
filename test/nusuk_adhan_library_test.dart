import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/prayer/data/adhan_library.dart';
import 'package:haq_app/features/prayer/data/prayer_alert.dart';

class _Audio implements AdhanPreviewAudio {
  final calls = <Uri>[];
  @override
  Future<void> play(Uri uri) async {
    calls.add(uri);
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('haq-nusuk-');
  });
  tearDown(() async {
    await folder.delete(recursive: true);
  });

  test(
    'exactly two bundled pairs install without any network request and repair damaged cache',
    () async {
      final dio = Dio();
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );
      final prepared = <String?>[];
      final library = AdhanLibrary(
        dio: dio,
        directory: () async => folder,
        audio: _Audio(),
        preparePair: (id, full, short) async {
          prepared.addAll([id, full, short]);
          return File(full).existsSync() &&
              short != null &&
              File(short).existsSync();
        },
      );
      await library.initialize();
      expect(library.error, isNull);
      expect(library.downloaded, {'nusuk-1', 'nusuk-2'});
      expect(requests, 0);
      expect(await library.download(adhanVoices.first), true);
      expect(prepared.first, 'nusuk-1');
      expect(prepared.last, endsWith('/nusuk-1-takbeer.mp3'));
      for (final voice in adhanVoices.where((v) => v.bundled)) {
        final full = File('${folder.path}/adhans/${voice.id}.mp3');
        final short = File('${folder.path}/adhans/${voice.id}-takbeer.mp3');
        expect(
          sha256.convert(await full.readAsBytes()).toString(),
          voice.sha256,
        );
        expect(
          sha256.convert(await short.readAsBytes()).toString(),
          voice.shortSha256,
        );
      }
      await File(
        '${folder.path}/adhans/nusuk-1-takbeer.mp3',
      ).writeAsBytes([1, 2, 3]);
      library.dispose();
      final restored = AdhanLibrary(
        dio: dio,
        directory: () async => folder,
        audio: _Audio(),
      );
      await restored.initialize();
      expect(restored.downloaded, {'nusuk-1', 'nusuk-2'});
      expect(restored.error, isNull);
      expect(requests, 0);
      restored.dispose();
    },
  );

  final full = List<int>.filled(1200, 4)..setRange(0, 3, [73, 68, 51]);
  final short = List<int>.filled(1300, 5)..setRange(0, 3, [73, 68, 51]);
  final voice = AdhanVoice(
    'nusuk-900',
    'Test',
    '',
    backend: true,
    bytes: full.length,
    sha256: sha256.convert(full).toString(),
    shortBytes: short.length,
    shortSha256: sha256.convert(short).toString(),
  );

  test(
    'on-demand download verifies both variants, prepares both paths and restores offline',
    () async {
      final dio = Dio();
      final urls = <String>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            urls.add(options.uri.toString());
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: options.path.endsWith('/takbeer') ? short : full,
                headers: Headers.fromMap({
                  'content-type': ['audio/mpeg'],
                }),
              ),
            );
          },
        ),
      );
      final audio = _Audio();
      var prepared = false;
      final library = AdhanLibrary(
        dio: dio,
        catalog: [voice],
        directory: () async => folder,
        audio: audio,
        preparePair: (id, path, shortPath) async {
          prepared =
              id == voice.id &&
              File(path).existsSync() &&
              File(shortPath!).existsSync();
          return prepared;
        },
      );
      await library.initialize();
      expect(urls, isEmpty);
      expect(library.downloaded, isEmpty);
      expect(await library.download(voice), true);
      expect(urls, [voice.uri.toString(), voice.shortUri.toString()]);
      expect(prepared, true);
      await library.preview(voice);
      expect(audio.calls.single.scheme, 'file');
      library.dispose();
      final restored = AdhanLibrary(
        catalog: [voice],
        directory: () async => folder,
        audio: _Audio(),
      );
      await restored.initialize();
      expect(restored.downloaded, {voice.id});
      restored.dispose();
      // Rewriting the receipt does not bypass the pinned catalogue hash.
      final corrupted = [...short]..[10] = 9;
      await File(
        '${folder.path}/adhans/${voice.id}-takbeer.mp3',
      ).writeAsBytes(corrupted);
      await File(
        '${folder.path}/adhans/${voice.id}-takbeer.json',
      ).writeAsString(
        jsonEncode({
          'bytes': corrupted.length,
          'sha256': sha256.convert(corrupted).toString(),
          'source': voice.shortUri.toString(),
        }),
      );
      final corrupt = AdhanLibrary(
        catalog: [voice],
        directory: () async => folder,
        audio: _Audio(),
      );
      await corrupt.initialize();
      expect(corrupt.downloaded, isEmpty);
      corrupt.dispose();
    },
  );

  test(
    'bad second variant never marks a pair ready or prepares a partial download',
    () async {
      final dio = Dio();
      var prepared = false;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: full,
                headers: Headers.fromMap({
                  'content-type': ['audio/mpeg'],
                }),
              ),
            );
          },
        ),
      );
      final library = AdhanLibrary(
        dio: dio,
        catalog: [voice],
        directory: () async => folder,
        audio: _Audio(),
        preparePair: (_, _, _) async {
          prepared = true;
          return true;
        },
      );
      expect(await library.download(voice), false);
      expect(library.downloaded, isEmpty);
      expect(prepared, false);
      expect(File('${folder.path}/adhans/${voice.id}.mp3').existsSync(), false);
      expect(
        await library.download(
          AdhanVoice(
            voice.id,
            'Forged',
            '',
            backend: true,
            bytes: full.length,
            sha256: '0' * 64,
            shortBytes: short.length,
            shortSha256: voice.shortSha256,
          ),
        ),
        false,
      );
      library.dispose();
    },
  );
}
