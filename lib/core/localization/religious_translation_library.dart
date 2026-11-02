import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bundled_content_catalog.dart';

Map<String, dynamic> _decodeSource(Map<String, dynamic> input) {
  final bytes = input['bytes'] as Uint8List;
  final meta = input['meta'] as Map;
  if (bytes.length != meta['bytes'] ||
      sha256.convert(bytes).toString() != meta['sha256']) {
    throw const FormatException('Invalid bundled source archive');
  }
  final raw = gzip.decode(bytes);
  if (raw.length != meta['json_bytes'] ||
      raw.length > 32 * 1024 * 1024 ||
      sha256.convert(raw).toString() != meta['json_sha256']) {
    throw const FormatException('Invalid bundled source text');
  }
  final data = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
  if (data['schema'] != 1 ||
      data['format'] != 'haq.bundled-source' ||
      data['locale'] != input['locale'] ||
      data['kind'] != input['kind']) {
    throw const FormatException('Incompatible bundled source');
  }
  final records = data['verses'] ?? data['entries'];
  if (records is! Map || records.length != meta['records']) {
    throw const FormatException('Incomplete bundled source');
  }
  return data;
}

/// These publisher snapshots ship inside the signed application. Downloaded
/// language releases still follow their independent signature/review workflow.
class ReligiousTranslationLibrary {
  ReligiousTranslationLibrary({AssetBundle? bundle})
    : bundle = bundle ?? rootBundle;

  static final shared = ReligiousTranslationLibrary();
  static final Map<String, dynamic> catalog =
      jsonDecode(bundledContentCatalogJson) as Map<String, dynamic>;
  static bool supports(String locale) =>
      (catalog['locales'] as Map).containsKey(locale);
  static String? kindForContent(String id) =>
      (catalog['content_kinds'] as Map)[id] as String?;
  static Map<String, dynamic> metadata(String locale) =>
      Map<String, dynamic>.from((catalog['locales'] as Map)[locale] as Map);

  final AssetBundle bundle;
  final _cache = <String, Future<SourceCollection>>{};

  Future<SourceCollection> load(String locale, String kind) {
    if (!supports(locale) || !metadata(locale).containsKey(kind)) {
      return Future.error(const FormatException('Source is unavailable'));
    }
    return _cache.putIfAbsent('$locale/$kind', () async {
      try {
        final meta = Map<String, dynamic>.from(metadata(locale)[kind] as Map);
        final data = await bundle.load(
          'assets/localization/content/${meta['file']}',
        );
        final decoded = await compute(_decodeSource, {
          'bytes': data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          ),
          'meta': meta,
          'locale': locale,
          'kind': kind,
        });
        return SourceCollection(decoded);
      } catch (_) {
        _cache.remove('$locale/$kind');
        rethrow;
      }
    });
  }
}

class SourceCollection {
  SourceCollection(this.data);
  final Map<String, dynamic> data;
  Map<String, dynamic> get source =>
      Map<String, dynamic>.from(data['source'] as Map);

  List<Map<String, dynamic>> forVerse(String key) {
    if (data['kind'] == 'quran') {
      final row = (data['verses'] as Map)[key];
      return row == null
          ? const []
          : [
              {'title': key, ...Map<String, dynamic>.from(row as Map)},
            ];
    }
    final ids = (data['verses'] as Map)[key] as List? ?? const [];
    return [
      for (final id in ids)
        Map<String, dynamic>.from((data['blocks'] as Map)[id] as Map),
    ];
  }

  List<Map<String, dynamic>> forChapter(int chapter) => [
    for (final row in (data['blocks'] as Map).values)
      if (row['sura'] == chapter && (row['text'] as String).trim().isNotEmpty)
        Map<String, dynamic>.from(row as Map),
  ];

  List<Map<String, dynamic>> forContent(String id, String original) {
    if (data['kind'] == 'quran') {
      if (original.isNotEmpty &&
          (data['reference_hashes'] as Map?)?[id] !=
              sha256.convert(utf8.encode(original)).toString()) {
        return const [];
      }
      final keys = (data['references'] as Map)[id] as List? ?? const [];
      return [for (final key in keys) ...forVerse(key as String)];
    }
    final entries = data['entries'] as Map;
    final additional = (data['additional_content'] as Map?)?[id] as Map?;
    if (additional != null) {
      return _matches(additional, original)
          ? [Map<String, dynamic>.from(additional)]
          : const [];
    }
    final alias = (data['aliases'] as Map?)?[id] as Map?;
    if (alias != null) {
      return _matches(alias, original)
          ? [Map<String, dynamic>.from(entries[alias['entry']] as Map)]
          : const [];
    }
    final chapter = (data['chapters'] as Map?)?[id] as Map?;
    if (chapter != null) {
      if (!_matches(chapter, original)) return const [];
      return [
        for (final key in chapter['entries'] as List)
          Map<String, dynamic>.from(entries[key] as Map),
      ];
    }
    final row = entries[id] as Map?;
    return row != null && _matches(row, original)
        ? [Map<String, dynamic>.from(row)]
        : const [];
  }

  static bool _matches(Map row, String original) =>
      row['original_sha256'] ==
      sha256.convert(utf8.encode(original)).toString();
}
