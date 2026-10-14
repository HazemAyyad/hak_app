import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/quran/data/quran_audio_models.dart';
import 'package:haq_app/features/quran/data/quran_downloads.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';

class StubHttp implements HttpClientAdapter {
  StubHttp(this.reply);
  final FutureOr<ResponseBody> Function(RequestOptions) reply;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async => reply(options);
  @override
  void close({bool force = false}) {}
}

Future<void> waitState(
  QuranDownloads store,
  String id,
  QuranDownloadState state,
) async {
  final limit = DateTime.now().add(const Duration(seconds: 5));
  while (store.entries[id]?.state != state) {
    if (DateTime.now().isAfter(limit)) {
      throw StateError(
        'Expected $state, got ${store.entries[id]?.state}: ${store.entries[id]?.error}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

QuranAudioTrack track({String id = 'test:1', String version = 'v1'}) =>
    QuranAudioTrack(
      id: id,
      recitation: 'test',
      reciter: 'قارئ',
      title: 'الفاتحة',
      surah: 1,
      url: 'https://example.test/$id.mp3',
      version: version,
      quality: '128 kbps',
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late QuranDownloads downloads;
  final audio = Uint8List.fromList([0xff, 0xfb, ...List.filled(1022, 42)]);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('quran_download_test_');
  });
  tearDown(() async {
    downloads.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'catalog validates availability and distinguishes chapter/verse versions',
    () async {
      downloads = QuranDownloads(directory: directory);
      final repo = QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final catalog = QuranAudioCatalog.fromJson(
        jsonDecode(File('assets/quran/audio_catalog.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      expect(catalog.recitations.length, greaterThan(200));
      final verse = catalog.recitations.firstWhere(
        (r) => r.id == 'everyayah:alafasy',
      );
      final chapter = catalog.recitations.firstWhere(
        (r) => r.id == 'mp3quran:123',
      );
      expect(verse.track(repo, 2, ayah: 3).url, endsWith('002003.mp3'));
      expect(chapter.track(repo, 2).url, endsWith('/002.mp3'));
      expect(() => verse.track(repo, 1, ayah: 8), throwsArgumentError);
      expect(
        verse.track(repo, 1, ayah: 1).storageKey,
        isNot(chapter.track(repo, 1).storageKey),
      );
      expect(track().storageKey, isNot(track(version: 'v2').storageKey));
    },
  );
  test(
    'completed file survives restart, verifies digest and updates real disk size after delete',
    () async {
      final dio = Dio()
        ..httpClientAdapter = StubHttp(
          (_) => ResponseBody.fromBytes(
            audio,
            200,
            headers: {
              'content-length': ['${audio.length}'],
            },
          ),
        );
      downloads = QuranDownloads(directory: directory, dio: dio);
      await downloads.enqueue(track());
      await waitState(downloads, track().id, QuranDownloadState.complete);
      final file = await downloads.localFile(track(), verify: true);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), audio);
      expect(await downloads.diskUsage(), audio.length);
      // Wait for the atomic completion manifest before emulating a restart.
      while (!File('${directory.path}/index.json').existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final restored = QuranDownloads(directory: directory);
      await restored.initialize();
      expect(await restored.localFile(track(), verify: true), isNotNull);
      await file.writeAsBytes([0xff, 0xfb, ...List.filled(1022, 11)]);
      expect(await restored.localFile(track(), verify: true), isNull);
      expect(restored.entries[track().id]!.state, QuranDownloadState.failed);
      await restored.remove(track().id);
      expect(await restored.diskUsage(), 0);
      restored.dispose();
    },
  );
  test(
    'range resumes only from the acknowledged offset; ignored range restarts',
    () async {
      final partial = File('${directory.path}/${track().storageKey}.mp3.part');
      await partial.writeAsBytes(audio.take(200).toList());
      var call = 0;
      final dio = Dio()
        ..httpClientAdapter = StubHttp((options) {
          expect(options.headers['Range'], 'bytes=200-');
          call++;
          return ResponseBody.fromBytes(
            audio.skip(200).toList(),
            206,
            headers: {
              'content-length': ['824'],
              'content-range': ['bytes 200-1023/1024'],
            },
          );
        });
      downloads = QuranDownloads(directory: directory, dio: dio);
      await downloads.enqueue(track());
      await waitState(downloads, track().id, QuranDownloadState.complete);
      expect(await (await downloads.localFile(track()))!.readAsBytes(), audio);
      expect(call, 1);
      await downloads.remove(track().id);
      await partial.writeAsBytes(audio.take(200).toList());
      dio.httpClientAdapter = StubHttp(
        (_) => ResponseBody.fromBytes(
          audio,
          200,
          headers: {
            'content-length': ['1024'],
          },
        ),
      );
      await downloads.enqueue(track());
      await waitState(downloads, track().id, QuranDownloadState.complete);
      expect(await (await downloads.localFile(track()))!.readAsBytes(), audio);
    },
  );
  test(
    'partial or HTML responses cannot become playable; retry succeeds',
    () async {
      var valid = false;
      final dio = Dio()
        ..httpClientAdapter = StubHttp(
          (_) => ResponseBody.fromBytes(
            valid ? audio : List.filled(1024, 60),
            200,
            headers: {
              'content-length': ['1024'],
            },
          ),
        );
      downloads = QuranDownloads(directory: directory, dio: dio);
      await downloads.enqueue(track());
      await waitState(downloads, track().id, QuranDownloadState.failed);
      expect(await downloads.localFile(track()), isNull);
      expect(await downloads.diskUsage(), 0);
      valid = true;
      await downloads.enqueue(track());
      await waitState(downloads, track().id, QuranDownloadState.complete);
      expect(await downloads.localFile(track()), isNotNull);
    },
  );
  test(
    'pause/remove an active task leaves other queued downloads intact',
    () async {
      final chunks = StreamController<Uint8List>();
      final dio = Dio()
        ..httpClientAdapter = StubHttp(
          (options) => options.uri.path.contains('test:1')
              ? ResponseBody(
                  chunks.stream,
                  200,
                  headers: {
                    'content-length': ['1024'],
                  },
                )
              : ResponseBody.fromBytes(
                  audio,
                  200,
                  headers: {
                    'content-length': ['1024'],
                  },
                ),
        );
      downloads = QuranDownloads(directory: directory, dio: dio);
      await downloads.enqueueAll([track(), track(id: 'test:2')]);
      await waitState(downloads, track().id, QuranDownloadState.downloading);
      chunks.add(Uint8List.fromList(audio.take(200).toList()));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final removed = downloads.remove(track().id);
      await chunks.close();
      await removed;
      await waitState(downloads, 'test:2', QuranDownloadState.complete);
      expect(downloads.entries.containsKey(track().id), isFalse);
      expect(await downloads.diskUsage(), 1024);
    },
  );
}
