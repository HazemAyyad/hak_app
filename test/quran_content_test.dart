import 'dart:convert';
import 'dart:io';
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
}
