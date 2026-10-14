import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/quran/data/quran_content.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/data/quran_cached_search.dart';
import 'quran_media_test.dart' show StubHttp;

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('quran_content_test_');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  ResponseBody reply(Map<String, dynamic> json) => ResponseBody.fromString(
    jsonEncode(json),
    200,
    headers: {
      'content-type': ['application/json'],
    },
  );
  test('physical page groups each word by its actual page and line', () {
    final repo = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final data =
        jsonDecode(File('test/fixtures/quran/page2.json').readAsStringSync())
            as Map<String, dynamic>;
    final page = MushafPageData.parse(2, data, repo);
    expect(page.words.first.key, '2:1');
    expect(page.fontFamily, 'QuranTajweedPage2');
    expect(page.words.last.key, '2:5');
    expect(
      page.words.every(
        (w) => w.line >= 1 && w.line <= 15 && w.glyph.isNotEmpty,
      ),
      isTrue,
    );
    final foreign = Map<String, dynamic>.from(data);
    foreign['verses'] = [
      {
        'verse_key': '2:1',
        'words': [
          {'page_number': 3, 'line_number': 4, 'code_v2': 'x', 'position': 1},
        ],
      },
    ];
    expect(() => MushafPageData.parse(2, foreign, repo), throwsFormatException);
  });
  test(
    'backend proxy falls back to the official provider and original payload remains cached offline',
    () async {
      var calls = 0;
      final urls = <String>[];
      final data = {
        'tafsir': {
          'resource_id': 91,
          'verses': {'2:2': {}},
          'text': '<p>فقرة أولى</p><script>hidden</script><p>فقرة ثانية</p>',
        },
      };
      final dio = Dio()
        ..httpClientAdapter = StubHttp((request) {
          urls.add(request.uri.toString());
          calls++;
          return request.uri.host == 'backend.test'
              ? ResponseBody.fromString('{}', 404)
              : reply(data);
        });
      final content = QuranContent(
        directory: directory,
        dio: dio,
        apiBase: 'https://backend.test/api',
      );
      final result = await content.tafsir('2:2', 91);
      expect(
        urls.first,
        'https://backend.test/api/v1/quran/content/tafsirs/91/2/2',
      );
      expect(result.originalHtml, data['tafsir']!['text']);
      expect(result.text, contains('فقرة ثانية'));
      expect(result.text, isNot(contains('hidden')));
      dio.httpClientAdapter = StubHttp((_) => throw StateError('offline'));
      expect(
        (await content.tafsir('2:2', 91)).originalHtml,
        result.originalHtml,
      );
      expect(calls, 2);
      final repo = QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final matches = await searchQuranCache(content, repo, 'فقرة');
      expect(matches.single.verse.key, '2:2');
      expect(matches.single.source, 'تفسير السعدي');
      expect(await searchQuranCache(content, repo, 'فقرة', surah: 1), isEmpty);
    },
  );
  test(
    'reference mismatch invalidates cache so retry can fetch corrected data',
    () async {
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = StubHttp((_) {
          calls++;
          return reply({
            'result': {
              'sura': '2',
              'aya': calls == 1 ? '3' : '2',
              'translation': 'لِلْمُتَّقِينَ: معنى من المصدر',
              'footnotes': '',
            },
          });
        });
      final content = QuranContent(
        directory: directory,
        dio: dio,
        apiBase: null,
      );
      await expectLater(content.meanings('2:2'), throwsFormatException);
      expect(
        (await content.meanings('2:2')).entries.single.word,
        'لِلْمُتَّقِينَ',
      );
      expect(calls, 2);
    },
  );
  test(
    'fresh JSON calls deduplicate and expiration never serves stale data offline',
    () async {
      var now = DateTime.utc(2026, 10, 14);
      var calls = 0;
      final response = Completer<ResponseBody>();
      final dio = Dio()
        ..httpClientAdapter = StubHttp((_) {
          calls++;
          return response.future;
        });
      final content = QuranContent(
        directory: directory,
        dio: dio,
        apiBase: null,
        now: () => now,
      );
      const url = 'https://api.quran.com/api/v4/test-cache';
      final first = content.json(url), second = content.json(url);
      expect(identical(first, second), isTrue);
      response.complete(reply({'original': 'source'}));
      expect(await first, {'original': 'source'});
      expect(await second, {'original': 'source'});
      expect(calls, 1);
      now = now.add(const Duration(days: 6, hours: 23));
      expect(await content.json(url), {'original': 'source'});
      expect(calls, 1);
      now = now.add(const Duration(hours: 1));
      dio.httpClientAdapter = StubHttp((_) => throw StateError('offline'));
      await expectLater(content.json(url), throwsA(isA<DioException>()));
      expect(
        await directory
            .list()
            .where((file) => file.path.endsWith('.json'))
            .toList(),
        isEmpty,
      );
    },
  );

  test(
    'old, unversioned and future response records are purged before cache search',
    () async {
      final now = DateTime.utc(2026, 10, 14);
      final content = QuranContent(
        directory: directory,
        now: () => now,
        apiBase: null,
      );
      expect(
        content.isCacheRecordFresh({'fetchedAt': now.toIso8601String()}),
        isTrue,
      );
      expect(
        content.isCacheRecordFresh({
          'fetchedAt': now.add(const Duration(seconds: 1)).toIso8601String(),
        }),
        isFalse,
      );
      expect(
        content.isCacheRecordFresh({
          'fetchedAt': now.subtract(const Duration(days: 7)).toIso8601String(),
        }),
        isFalse,
      );
      expect(content.isCacheRecordFresh({}), isFalse);
      expect(content.isCacheRecordFresh({'fetchedAt': 42}), isFalse);
      await File('${directory.path}/old.json').writeAsString(
        jsonEncode({
          'fetchedAt': now.subtract(const Duration(days: 8)).toIso8601String(),
          'payload': {},
        }),
      );
      await File(
        '${directory.path}/undated.json',
      ).writeAsString(jsonEncode({'payload': {}}));
      await File('${directory.path}/qcf-v2-2.ttf').writeAsBytes([1, 2, 3]);
      await content.cacheDirectory();
      expect(await directory.list().toList(), isEmpty);
      // A stale file appearing later must not bypass expiry through cache search.
      await File('${directory.path}/later.json').writeAsString(
        jsonEncode({
          'url': 'https://api.quran.com/api/v4/tafsirs/91/by_ayah/2:2',
          'fetchedAt': now.subtract(const Duration(days: 8)).toIso8601String(),
          'payload': {
            'tafsir': {
              'resource_id': 91,
              'verses': {'2:2': {}},
              'text': '<p>نص قديم</p>',
            },
          },
        }),
      );
      final repo = QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      expect(await searchQuranCache(content, repo, 'قديم'), isEmpty);
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'page request uses V4 layout, rejects monochrome fonts and retries without persistent font files',
    () async {
      final repo = QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final page =
          jsonDecode(File('test/fixtures/quran/page2.json').readAsStringSync())
              as Map<String, dynamic>;
      final requests = <String>[];
      final bytes = Uint8List(1024);
      ByteData.sublistView(bytes).setUint32(0, 0x00010000);
      final dio = Dio()
        ..httpClientAdapter = StubHttp((request) {
          requests.add(request.uri.toString());
          if (request.uri.path.endsWith('.ttf')) {
            return ResponseBody.fromBytes(bytes, 200);
          }
          return reply({'data': page});
        });
      final content = QuranContent(
        directory: directory,
        dio: dio,
        apiBase: 'https://backend.test/api',
      );
      await expectLater(content.page(2, repo), throwsFormatException);
      expect(
        requests.first,
        'https://backend.test/api/v1/quran/content/pages/2',
      );
      expect(
        requests.last,
        'https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/ttf/p2.ttf',
      );
      await expectLater(content.page(2, repo), throwsFormatException);
      expect(requests.where((url) => url.endsWith('.ttf')).length, 2);
      expect(
        await directory
            .list()
            .where((file) => file.path.endsWith('.ttf'))
            .toList(),
        isEmpty,
      );
      final recorded =
          jsonDecode(
                await (await directory
                            .list()
                            .where((file) => file.path.endsWith('.json'))
                            .single
                        as File)
                    .readAsString(),
              )
              as Map;
      expect(recorded['url'], contains('mushaf=19'));
    },
  );
}
