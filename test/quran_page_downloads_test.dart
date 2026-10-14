import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/quran/data/quran_page_downloads.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';

class PageHttp implements HttpClientAdapter {
  PageHttp(this.reply);
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

const pageSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 200"><path d="M0 0L100 0L100 200L0 200Z" fill="#111111" /></svg>';
const pageJson =
    '[{"surahNumber":1,"ayahNumber":1,"polygon":"0,0 100,0 100,40 0,40"}]';

String blob(String text) {
  final bytes = utf8.encode(text);
  return sha1.convert([
    ...utf8.encode('blob ${bytes.length}\u0000'),
    ...bytes,
  ]).toString();
}

QuranPageAssetSpec spec(int page) => QuranPageAssetSpec(
  page: page,
  svgLength: utf8.encode(pageSvg).length,
  svgBlob: blob(pageSvg),
  jsonLength: utf8.encode(pageJson).length,
  jsonBlob: blob(pageJson),
);

ResponseBody fullPage(RequestOptions options) => ResponseBody.fromString(
  options.uri.path.endsWith('.svg') ? pageSvg : pageJson,
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final stores = <QuranPageDownloads>[];
  QuranPageDownloads create({
    Dio? dio,
    Map<int, QuranPageAssetSpec>? manifest,
  }) {
    final store = QuranPageDownloads(
      directory: directory,
      dio: dio,
      manifest: manifest ?? {1: spec(1), 2: spec(2)},
    );
    stores.add(store);
    return store;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('quran_pages_test_');
  });
  tearDown(() async {
    for (final store in stores) {
      store.dispose();
      await store.flush();
    }
    stores.clear();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'verified page and ayah map survive restart with no network; corruption is rejected',
    () async {
      var requests = 0;
      final dio = Dio()
        ..httpClientAdapter = PageHttp((options) {
          requests++;
          return fullPage(options);
        });
      final store = create(dio: dio);
      await store.enqueue([1]);
      await store.flush();
      expect(store.hasPage(1), isTrue);
      expect(requests, 2);
      expect(store.progress, 1);
      expect(
        (await store.offlinePage(1))!.verseAt(const Offset(20, 20)),
        '1:1',
      );
      final index =
          jsonDecode(await File('${directory.path}/index.json').readAsString())
              as Map;
      expect(
        (index['entries'] as List).first['svgSha256'],
        sha256.convert(utf8.encode(pageSvg)).toString(),
      );
      final offline = Dio()
        ..httpClientAdapter = PageHttp(
          (_) => throw StateError('Offline read attempted network'),
        );
      final restored = create(dio: offline);
      await restored.initialize();
      expect(restored.hasPage(1), isTrue);
      expect((await restored.offlinePage(1))!.regions.single.key, '1:1');
      await File(
        '${directory.path}/001.svg',
      ).writeAsString(pageSvg.replaceFirst('#111111', '#222222'));
      expect(await restored.offlinePage(1), isNull);
      expect(restored.hasPage(1), isFalse);
      expect(restored.entries[1]!.state, QuranPageDownloadState.failed);
    },
  );

  test(
    'partial files resume from confirmed offset and ignored Range safely restarts',
    () async {
      final bytes = utf8.encode(pageSvg);
      await File(
        '${directory.path}/001.svg.part',
      ).writeAsBytes(bytes.take(25).toList());
      final dio = Dio()
        ..httpClientAdapter = PageHttp((options) {
          if (options.uri.path.endsWith('.svg')) {
            expect(options.headers['Range'], 'bytes=25-');
            return ResponseBody.fromBytes(
              bytes.skip(25).toList(),
              206,
              headers: {
                'content-range': [
                  'bytes 25-${bytes.length - 1}/${bytes.length}',
                ],
              },
            );
          }
          return fullPage(options);
        });
      final store = create(dio: dio);
      await store.enqueue([1]);
      await store.flush();
      expect(store.hasPage(1), isTrue);
      await File(
        '${directory.path}/002.svg.part',
      ).writeAsBytes(bytes.take(25).toList());
      dio.httpClientAdapter = PageHttp(fullPage);
      await store.enqueue([2]);
      await store.flush();
      expect(store.hasPage(2), isTrue);
      expect(await File('${directory.path}/002.svg').readAsString(), pageSvg);
    },
  );

  test(
    'pause all cancels current transfer, retains partial bytes and prevents queued starts',
    () async {
      final started = Completer<void>();
      final continueTransfer = Completer<void>();
      final requests = <String>[];
      Stream<Uint8List> slow() async* {
        yield Uint8List.fromList(utf8.encode(pageSvg).take(25).toList());
        started.complete();
        await continueTransfer.future;
        yield Uint8List.fromList(utf8.encode(pageSvg).skip(25).toList());
      }

      final dio = Dio()
        ..httpClientAdapter = PageHttp((options) {
          requests.add(options.uri.path);
          return ResponseBody(slow(), 200);
        });
      final store = create(dio: dio);
      await store.enqueue([1, 2]);
      await started.future;
      // The network producing a chunk does not mean the device writer has
      // consumed it yet. Pause only after the actual saved-byte counter moves.
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (store.entries[1]!.received < 25) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('The page writer did not receive the chunk');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final pausing = store.pauseAll();
      continueTransfer.complete();
      await pausing;
      expect(store.isActive, isFalse);
      expect(
        store.entries.values.every(
          (entry) => entry.state == QuranPageDownloadState.paused,
        ),
        isTrue,
      );
      expect(requests.length, 1);
      expect(await File('${directory.path}/001.svg.part').length(), 25);
      dio.httpClientAdapter = PageHttp(fullPage);
      await store.resumeAll();
      await store.flush();
      expect(store.completed, 2);
      expect(store.isActive, isFalse);
    },
  );

  test(
    'incorrect upstream payload never becomes an offline Quran page',
    () async {
      final dio = Dio()
        ..httpClientAdapter = PageHttp(
          (options) => ResponseBody.fromString(
            options.uri.path.endsWith('.svg')
                ? pageSvg.replaceFirst('#111111', '#222222')
                : pageJson,
            200,
          ),
        );
      final store = create(dio: dio);
      await store.enqueue([1, 2]);
      await store.flush();
      expect(store.completed, 0);
      expect(store.entries[1]!.state, QuranPageDownloadState.failed);
      expect(store.entries[2]!.state, QuranPageDownloadState.paused);
      expect(await store.offlinePage(1), isNull);
    },
  );

  test(
    'pinned manifest has all 604 pages and surah scope follows canonical page metadata',
    () {
      final store = QuranPageDownloads(directory: directory);
      stores.add(store);
      expect(store.manifest.length, 604);
      expect(store.manifest[1]!.svgBlob, matches(RegExp(r'^[a-f0-9]{40}$')));
      expect(store.manifest[604]!.jsonLength, greaterThan(0));
      final repo = QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      expect(store.pagesForSurah(repo, 1), [1]);
      expect(
        store.pagesForSurah(repo, 2),
        List.generate(48, (index) => index + 2),
      );
      expect(store.pagesForSurah(repo, 114), [604]);
    },
  );

  test(
    'ayah geometry handles negative-origin opening page and separate line polygons',
    () {
      final page = QuranOfflinePageData.parse(3, pageSvg, [
        {
          'surahNumber': 2,
          'ayahNumber': 6,
          'polygon':
              'M 0 0 L 100 0 L 100 20 L 0 20 Z M 50 40 L 100 40 L 100 60 L 50 60 Z',
        },
        {'surahNumber': 2, 'ayahNumber': 7, 'polygon': '0,20 50,20 50,40 0,40'},
      ]);
      expect(page.verseAt(const Offset(20, 10)), '2:6');
      expect(page.verseAt(const Offset(75, 50)), '2:6');
      expect(page.verseAt(const Offset(20, 30)), '2:7');
      expect(page.verseAt(const Offset(20, 50)), isNull);
      final opening = QuranOfflinePageData.parse(
        1,
        pageSvg.replaceFirst('0 0 100 200', '-53 -198 345 550'),
        jsonDecode(pageJson),
      );
      expect(opening.viewBox.left, -53);
      expect(opening.displayBox, const Rect.fromLTRB(-9, -9, 109, 49));
      expect(opening.displaySvg, contains('viewBox="-9.0 -9.0 118.0 58.0"'));
    },
  );
}
