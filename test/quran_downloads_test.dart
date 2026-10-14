import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/quran/data/quran_audio_models.dart';
import 'package:haq_app/features/quran/data/quran_downloads.dart';

class DownloadHttp implements HttpClientAdapter {
  DownloadHttp(this.reply);
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

QuranAudioTrack downloadTrack(String name) => QuranAudioTrack(
  id: name,
  recitation: 'reader',
  reciter: 'قارئ',
  title: name,
  surah: 1,
  url: 'https://example.test/$name.mp3',
  version: '1',
  quality: '128 kbps',
);

Future<void> until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Download timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late QuranDownloads downloads;
  final audio = Uint8List.fromList([0xff, 0xfb, ...List.filled(1022, 42)]);
  ResponseBody complete() => ResponseBody.fromBytes(
    audio,
    200,
    headers: {
      'content-length': ['${audio.length}'],
    },
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('quran_bulk_download_');
  });
  tearDown(() async {
    downloads.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await directory.delete(recursive: true);
  });

  test(
    'bulk pause cancels active and queued tasks, retains files and resumes',
    () async {
      final active = downloadTrack('active');
      final queued = downloadTrack('queued');
      final done = downloadTrack('done');
      final chunks = StreamController<Uint8List>();
      final calls = <String, int>{};
      var resume = false;
      final dio = Dio()
        ..httpClientAdapter = DownloadHttp((options) {
          final name = options.uri.pathSegments.last.split('.').first;
          calls.update(name, (count) => count + 1, ifAbsent: () => 1);
          if (name != 'active') return complete();
          if (!resume) {
            return ResponseBody(
              chunks.stream,
              200,
              headers: {
                'content-length': ['${audio.length}'],
              },
            );
          }
          expect(options.headers['Range'], 'bytes=200-');
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
      await downloads.enqueue(done);
      await until(
        () => downloads.entries[done.id]?.state == QuranDownloadState.complete,
      );
      final file = (await downloads.localFile(done, verify: true))!;
      final savedBytes = await file.readAsBytes();
      await downloads.enqueueAll([active, queued]);
      await until(() => calls['active'] == 1);
      chunks.add(Uint8List.fromList(audio.take(200).toList()));
      await until(() => downloads.entries[active.id]!.received == 200);

      // No further response chunks arrive: cancellation must unblock the worker.
      await downloads.pauseAll().timeout(const Duration(seconds: 2));
      expect(downloads.entries[active.id]!.state, QuranDownloadState.paused);
      expect(downloads.entries[queued.id]!.state, QuranDownloadState.paused);
      expect(calls['queued'], isNull);
      expect(downloads.entries[done.id]!.state, QuranDownloadState.complete);
      expect(await file.readAsBytes(), savedBytes);
      final partial = File('${directory.path}/${active.storageKey}.mp3.part');
      expect(await partial.length(), 200);

      resume = true;
      await downloads.enqueueAll([active, queued, done]);
      await until(
        () =>
            downloads.entries[queued.id]?.state == QuranDownloadState.complete,
      );
      expect(
        await (await downloads.localFile(active, verify: true))!.readAsBytes(),
        audio,
      );
      expect(calls['active'], 2);
      expect(calls['queued'], 1);
      expect(calls['done'], 1);
      await chunks.close();
    },
  );

  test(
    'scoped pause leaves unrelated queued tasks running and immediate resume succeeds',
    () async {
      final active = downloadTrack('active');
      final queued = downloadTrack('queued');
      final other = downloadTrack('other');
      final chunks = StreamController<Uint8List>();
      var activeCalls = 0;
      final dio = Dio()
        ..httpClientAdapter = DownloadHttp((options) {
          if (!options.uri.path.endsWith('/active.mp3') || activeCalls++ > 0) {
            return complete();
          }
          return ResponseBody(
            chunks.stream,
            200,
            headers: {
              'content-length': ['${audio.length}'],
            },
          );
        });
      downloads = QuranDownloads(directory: directory, dio: dio);
      await downloads.enqueueAll([active, queued, other]);
      await until(() => activeCalls == 1);
      chunks.add(Uint8List.fromList(audio.take(200).toList()));
      await until(() => downloads.entries[active.id]!.received == 200);
      // Request resume before the paused transfer finishes cancelling. The old
      // worker must close its file before the same entry can run again.
      final pausing = downloads.pauseAll([active.id, queued.id]);
      final resuming = downloads.enqueue(active);
      await Future.wait([pausing, resuming]);
      await until(
        () => downloads.entries[other.id]?.state == QuranDownloadState.complete,
      );
      expect(downloads.entries[queued.id]!.state, QuranDownloadState.paused);
      await until(
        () =>
            downloads.entries[active.id]?.state == QuranDownloadState.complete,
      );
      expect(activeCalls, 2);
      expect(await downloads.localFile(other, verify: true), isNotNull);
      await chunks.close();
    },
  );
}
