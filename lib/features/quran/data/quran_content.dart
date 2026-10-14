import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import 'package:path_provider/path_provider.dart';

import 'quran_repository.dart';
import 'haq_api.dart';

const tafsirSources = <int, String>{
  91: 'تفسير السعدي',
  15: 'تفسير الطبري',
  14: 'تفسير ابن كثير',
  90: 'تفسير القرطبي',
};

class MushafWord {
  MushafWord({
    required this.key,
    required this.position,
    required this.line,
    required this.glyph,
    required this.text,
    this.audio,
  });
  final String key, glyph, text;
  final int position, line;
  final String? audio;
}

class MushafPageData {
  MushafPageData(this.page, this.words);
  final int page;
  final List<MushafWord> words;
  String get fontFamily => 'QuranTajweedPage$page';
  static MushafPageData parse(
    int page,
    Map<String, dynamic> data,
    QuranRepository repo,
  ) {
    final words = <MushafWord>[];
    for (final verse in data['verses'] as List) {
      final key = verse['verse_key'] as String;
      if (!repo.byKey.containsKey(key)) {
        throw const FormatException('Unknown verse in page source');
      }
      for (final word in verse['words'] as List) {
        if (word['page_number'] != page) continue;
        final line = word['line_number'] as int;
        if (line < 1 ||
            line > 15 ||
            (word['code_v2'] as String? ?? '').isEmpty) {
          throw const FormatException('Invalid fixed page glyph or line');
        }
        words.add(
          MushafWord(
            key: key,
            position: word['position'] as int,
            line: line,
            glyph: word['code_v2'] as String,
            text: word['text_qpc_hafs'] as String? ?? '',
            audio: word['audio_url'] as String?,
          ),
        );
      }
    }
    if (words.isEmpty) throw const FormatException('Empty page');
    return MushafPageData(page, words);
  }
}

class TafsirText {
  TafsirText(this.sourceId, this.title, this.originalHtml, this.keys);
  final int sourceId;
  final String title, originalHtml;
  final List<String> keys;
  String get text {
    final doc = html.parse(originalHtml);
    for (final node in doc.querySelectorAll('script,style')) {
      node.remove();
    }
    for (final node in doc.querySelectorAll('br')) {
      node.replaceWith(html.parseFragment('\n'));
    }
    for (final node in doc.querySelectorAll('p,div,h2,h3')) {
      node.append(html.parseFragment('\n\n'));
    }
    return doc.body?.text.trim() ?? '';
  }
}

class WordMeaning {
  WordMeaning(this.word, this.meaning);
  final String word, meaning;
}

class VerseMeanings {
  VerseMeanings(this.original, this.footnotes);
  final String original;
  final String? footnotes;
  List<WordMeaning> get entries => original
      .split(RegExp(r'[\r\n]+'))
      .where((line) => line.trim().isNotEmpty)
      .map((line) {
        final colon = line.indexOf(':');
        return colon < 0
            ? WordMeaning('', line)
            : WordMeaning(
                line.substring(0, colon).trim(),
                line.substring(colon + 1).trim(),
              );
      })
      .toList();
}

/// Only official public content endpoints are used. Original provider payloads
/// are retained in the device cache, with their URL and retrieval timestamp.
class QuranContent {
  QuranContent({
    Dio? dio,
    this.directory,
    this.apiBase = haqApiBase,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 35),
             ),
           );
  static const cacheMaxAge = Duration(days: 7);
  final DateTime Function() _now;
  final Dio dio;
  final String? apiBase;
  Directory? directory;
  final _pending = <String, Future<Map<String, dynamic>>>{};
  final _loadedFonts = <int, Future<void>>{};
  final _pages = <int, Future<MushafPageData>>{};
  Future<Directory>? _cacheReady;
  Future<Directory> cacheDirectory() =>
      _cacheReady ??= _prepareCacheDirectory().catchError((Object error) {
        _cacheReady = null;
        throw error;
      });

  Future<Directory> _prepareCacheDirectory() async {
    directory ??= await getApplicationSupportDirectory().then(
      (dir) =>
          Directory('${dir.path}/quran_content_v1').create(recursive: true),
    );
    // Purge stale responses on the next app session rather than leaving old,
    // unused provider copies indefinitely. Legacy persisted page fonts are no
    // longer used; the Tajweed renderer loads official font bytes per session.
    await for (final file in directory!.list()) {
      if (file is! File) continue;
      final name = file.uri.pathSegments.last;
      try {
        if (RegExp(r'^qcf-v[24]-[0-9]{1,3}\.ttf(?:\.tmp)?$').hasMatch(name)) {
          await file.delete();
        } else if (name.endsWith('.json')) {
          var remove = false;
          try {
            final record = jsonDecode(await file.readAsString()) as Map;
            remove = !isCacheRecordFresh(record);
          } on FormatException {
            remove = true;
          } on TypeError {
            remove = true;
          }
          if (remove) await file.delete();
        }
      } on FileSystemException {
        // A cache cleanup failure must not hide otherwise readable content.
      }
    }
    return directory!;
  }

  Future<File> _file(String url) async => File(
    '${(await cacheDirectory()).path}/${sha256.convert(utf8.encode(url))}.json',
  );

  Future<Map<String, dynamic>> json(String url, {bool refresh = false}) =>
      _pending.putIfAbsent(
        url,
        () => _readJson(url, refresh).whenComplete(() {
          _pending.remove(url);
        }),
      );
  Future<Map<String, dynamic>> _readJson(String url, bool refresh) async {
    final file = await _file(url);
    Map<String, dynamic>? cached;
    if (await file.exists()) {
      try {
        final record = jsonDecode(await file.readAsString()) as Map;
        if (isCacheRecordFresh(record)) {
          cached = record['payload'] as Map<String, dynamic>;
        }
      } catch (_) {
        /* Refetch a damaged cache. */
      }
      if (cached == null) await file.delete();
    }
    if (!refresh && cached != null) return cached;
    try {
      Map<String, dynamic>? payload;
      final proxy = _proxy(url);
      if (proxy != null) {
        try {
          payload =
              (await dio.get<Map<String, dynamic>>(proxy)).data?['data']
                  as Map<String, dynamic>?;
        } on DioException {
          /* Public source fallback while the backend is being deployed. */
        }
      }
      payload ??= (await dio.get<Map<String, dynamic>>(url)).data;
      if (payload == null) {
        throw const FormatException('Empty content response');
      }
      final data = payload;
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'url': url,
          'fetchedAt': _now().toUtc().toIso8601String(),
          'payload': data,
        }),
        flush: true,
      );
      await temporary.rename(file.path);
      return data;
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Regular provider responses expire after seven days, including during an
  /// outage. A missing or future timestamp cannot make an offline copy fresh.
  bool isCacheRecordFresh(Map record) {
    final timestamp = record['fetchedAt'];
    if (timestamp is! String) return false;
    final fetchedAt = DateTime.tryParse(timestamp);
    if (fetchedAt == null) return false;
    final age = _now().toUtc().difference(fetchedAt.toUtc());
    return !age.isNegative && age < cacheMaxAge;
  }

  String? _proxy(String url) {
    if (apiBase == null || apiBase!.isEmpty) return null;
    final uri = Uri.parse(url), pieces = Uri.parse(url).pathSegments;
    String? route;
    if (uri.host == 'api.quran.com' && uri.path.contains('/verses/by_page/')) {
      route = 'pages/${pieces.last}';
    }
    if (uri.host == 'api.quran.com' && uri.path.contains('/verses/by_key/')) {
      route = 'words/${pieces.last.replaceAll(':', '/')}';
    }
    if (uri.host == 'api.quran.com' &&
        uri.path.contains('/tafsirs/') &&
        pieces.last.contains(':')) {
      route = 'tafsirs/${pieces[3]}/${pieces.last.replaceAll(':', '/')}';
    }
    if (uri.host == 'quranenc.com' && pieces.contains('arabic_seraj')) {
      route = 'meanings/${pieces[pieces.length - 2]}/${pieces.last}';
    }
    return route == null
        ? null
        : '${apiBase!.replaceAll(RegExp(r'/+$'), '')}/v1/quran/content/$route';
  }

  /// Official V4 fonts retain their original per-letter Tajweed palette.
  /// Font bytes stay in the running process only; they are not bundled or
  /// persisted in the application's offline cache.
  Future<void> pageFont(int page) {
    if (page < 1 || page > 604) throw ArgumentError.value(page);
    return _loadedFonts.putIfAbsent(
      page,
      () => _loadPageFont(page).catchError((Object error) {
        _loadedFonts.remove(page);
        throw error;
      }),
    );
  }

  Future<void> _loadPageFont(int page) async {
    final response = await dio.get<List<int>>(
      'https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/ttf/p$page.ttf',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = Uint8List.fromList(response.data ?? const []);
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 1000 ||
        !(data.getUint32(0) == 0x00010000 || data.getUint32(0) == 0x4F54544F)) {
      throw const FormatException('Invalid Quran Tajweed font');
    }
    final count = data.getUint16(4);
    if (12 + count * 16 > bytes.length) {
      throw const FormatException('Invalid Quran font table directory');
    }
    final tags = <int>{};
    for (var i = 0; i < count; i++) {
      final offset = 12 + i * 16;
      final start = data.getUint32(offset + 8);
      final length = data.getUint32(offset + 12);
      if (start + length > bytes.length) {
        throw const FormatException('Incomplete Quran font table');
      }
      tags.add(data.getUint32(offset));
    }
    // Reject a monochrome V2 response instead of claiming it is Tajweed.
    if (!tags.contains(0x434F4C52) || !tags.contains(0x4350414C)) {
      throw const FormatException(
        'Missing original Quran Tajweed color tables',
      );
    }
    await (FontLoader(
      'QuranTajweedPage$page',
    )..addFont(Future.value(data))).load();
  }

  Future<MushafPageData> page(int page, QuranRepository repo) {
    if (page < 1 || page > 604) throw ArgumentError.value(page);
    return _pages.putIfAbsent(
      page,
      () => _loadPage(page, repo).catchError((Object error) {
        _pages.remove(page);
        throw error;
      }),
    );
  }

  Future<MushafPageData> _loadPage(int page, QuranRepository repo) async {
    final url =
        'https://api.quran.com/api/v4/verses/by_page/$page?mushaf=19&words=true&word_fields=code_v2,text_qpc_hafs,page_number,line_number&per_page=50';
    final parsed = await _validated(url, (result) {
      if ((result['pagination'] as Map?)?['next_page'] != null) {
        throw const FormatException('Incomplete page response');
      }
      return MushafPageData.parse(page, result, repo);
    });
    // The provider can paginate; a partial physical page is never displayed.
    await pageFont(page);
    return parsed;
  }

  Future<TafsirText> tafsir(String key, int source) async {
    if (!tafsirSources.containsKey(source)) throw ArgumentError.value(source);
    return _validated(
      'https://api.quran.com/api/v4/tafsirs/$source/by_ayah/$key',
      (payload) {
        final data = payload['tafsir'] as Map<String, dynamic>;
        final keys = (data['verses'] as Map).keys.cast<String>().toList();
        if (!keys.contains(key) ||
            data['resource_id'] != source ||
            (data['text'] as String).trim().isEmpty) {
          throw const FormatException('Tafsir does not cover requested verse');
        }
        return TafsirText(
          source,
          tafsirSources[source]!,
          data['text'] as String,
          keys,
        );
      },
    );
  }

  Future<VerseMeanings> meanings(String key) async {
    final pieces = key.split(':');
    return _validated(
      'https://quranenc.com/api/v1/translation/aya/arabic_seraj/${pieces[0]}/${pieces[1]}',
      (payload) {
        final data = payload['result'] as Map<String, dynamic>;
        if ('${data['sura']}:${data['aya']}' != key) {
          throw const FormatException('Meaning reference mismatch');
        }
        return VerseMeanings(
          data['translation'] as String,
          data['footnotes'] as String?,
        );
      },
    );
  }

  Future<T> _validated<T>(
    String url,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final raw = await json(url);
    try {
      return parse(raw);
    } catch (_) {
      final cached = await _file(url);
      if (await cached.exists()) await cached.delete();
      rethrow;
    }
  }

  Future<List<MushafWord>> words(QuranVerse verse) => _validated(
    'https://api.quran.com/api/v4/verses/by_key/${verse.key}?words=true&word_fields=text_qpc_hafs,page_number,line_number,code_v2',
    (payload) {
      final data = payload['verse'] as Map<String, dynamic>;
      if (data['verse_key'] != verse.key) {
        throw const FormatException('Word verse mismatch');
      }
      return [
        for (final word in data['words'] as List)
          if (word['audio_url'] != null)
            MushafWord(
              key: verse.key,
              position: word['position'] as int,
              line: word['line_number'] as int,
              glyph: word['code_v2'] as String? ?? '',
              text: word['text_qpc_hafs'] as String? ?? '',
              audio: word['audio_url'] as String,
            ),
      ];
    },
  );
  void attachRepository(QuranRepository repository) {}
}
