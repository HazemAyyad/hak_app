import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'bundled_localization.dart';

const hadithSourceColumns = [
  'id',
  'title_ar',
  'title',
  'hadith_text_ar',
  'hadith_text',
  'explanation_ar',
  'explanation',
  'benefits_ar',
  'benefits',
  'grade_ar',
  'takhrij_ar',
  'grade',
  'takhrij',
  'lang',
  'link',
];

/// One RFC 4180 record, with doubled quotes and embedded newlines preserved.
/// Multiple records and malformed quoting cannot become one publisher record.
List<String> _record(String raw) {
  if (raw.isEmpty) throw const FormatException('Empty source CSV record');
  final fields = <String>[];
  var i = 0;
  while (true) {
    final value = StringBuffer();
    if (i < raw.length && raw[i] == '"') {
      i++;
      var closed = false;
      while (i < raw.length) {
        if (raw[i] == '"') {
          if (i + 1 < raw.length && raw[i + 1] == '"') {
            value.write('"');
            i += 2;
          } else {
            i++;
            closed = true;
            break;
          }
        } else {
          value.write(raw[i++]);
        }
      }
      if (!closed) throw const FormatException('Unclosed source CSV quote');
    } else {
      while (i < raw.length && ![',', '\r', '\n'].contains(raw[i])) {
        if (raw[i] == '"') throw const FormatException('Invalid CSV quote');
        value.write(raw[i++]);
      }
    }
    fields.add(value.toString());
    if (fields.length > hadithSourceColumns.length) {
      throw const FormatException('Too many source CSV fields');
    }
    if (i == raw.length) break;
    if (raw[i] == ',') {
      i++;
      continue;
    }
    if (raw[i] == '\r' || raw[i] == '\n') {
      if (raw[i++] == '\r' && i < raw.length && raw[i] == '\n') i++;
      if (i == raw.length) break;
    }
    throw const FormatException('Extra source CSV content');
  }
  return fields;
}

class HadithTranslationSource {
  HadithTranslationSource._(
    this.locale,
    this.direction,
    this.attribution,
    this.source,
    this.records,
    this.references,
  );
  final String locale, direction, attribution;
  final Map<String, dynamic> source;
  final Map<String, Map<String, String>> records;
  final Map<String, Map<String, String>> references;

  factory HadithTranslationSource.verify(Map envelope, String expectedLocale) {
    final artifact = envelope['artifact'] as String;
    final bytes = utf8.encode(artifact);
    if (bytes.length > 8 * 1024 * 1024 ||
        sha256.convert(bytes).toString() != envelope['sha256']) {
      throw const FormatException('Invalid hadith source bytes');
    }
    final data = jsonDecode(artifact) as Map;
    final source = Map<String, dynamic>.from(data['source'] as Map);
    final sourceLocale =
        {'fil': 'tl', 'zh-Hans': 'zh', 'ckb': 'ku'}[expectedLocale] ??
        expectedLocale;
    final language = (jsonDecode(bundledLanguagesJson) as List)
        .where((value) => value['locale'] == expectedLocale)
        .firstOrNull;
    final version = source['version'];
    final document = source['document'];
    final update = Uri.tryParse(source['update_url'] as String? ?? '');
    if (data['format'] != 'haq.hadith.source.review' ||
        data['schema'] != 1 ||
        data['provider'] != 'HadeethEnc.com' ||
        data['locale'] != expectedLocale ||
        data['source_locale'] != sourceLocale ||
        language == null ||
        data['direction'] != language['direction'] ||
        data['policy_url'] != 'https://hadeethenc.com/en/home' ||
        version is! String ||
        !RegExp(r'^[0-9.]{1,30}$').hasMatch(version) ||
        data['attribution'] != 'HadeethEnc.com — v$version' ||
        source['header_csv'] is! String ||
        document is! String ||
        !document.contains('# Source: https://hadeethenc.com/$sourceLocale') ||
        !document.contains('(v$version)') ||
        source['update_timezone'] != 'unspecified' ||
        source['last_update'] is! String ||
        source['archive_bytes'] is! int ||
        (source['archive_bytes'] as int) < 1 ||
        (source['archive_bytes'] as int) > 32 * 1024 * 1024 ||
        source['archive_records'] is! int ||
        (source['archive_records'] as int) < 1 ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(source['archive_sha256'] as String? ?? '') ||
        update?.scheme != 'https' ||
        update?.host != 'hadeethenc.com' ||
        !RegExp(
          '^/[a-z]{2,3}/check/$sourceLocale/v${RegExp.escape(version)}\$',
        ).hasMatch(update!.path)) {
      throw const FormatException('Invalid hadith source metadata');
    }
    final records = <String, Map<String, String>>{};
    for (final entry in (data['records'] as Map).entries) {
      final id = entry.key as String;
      final raw = entry.value['raw_csv'] as String;
      final fields = Map<String, String>.from(entry.value['fields'] as Map);
      final parsed = _record(raw);
      if (!RegExp(r'^[1-9][0-9]{0,9}$').hasMatch(id) ||
          utf8.encode(raw).length > 1024 * 1024 ||
          sha256.convert(utf8.encode(raw)).toString() !=
              entry.value['sha256'] ||
          parsed.length != hadithSourceColumns.length ||
          fields.length != hadithSourceColumns.length ||
          fields['id'] != id ||
          fields['lang'] != sourceLocale ||
          fields['link'] !=
              'https://hadeethenc.com/$sourceLocale/browse/hadith/$id') {
        throw const FormatException('Invalid hadith record identity');
      }
      for (var i = 0; i < hadithSourceColumns.length; i++) {
        if (fields[hadithSourceColumns[i]] != parsed[i]) {
          throw const FormatException('Changed hadith source fields');
        }
      }
      if ([
        'title',
        'hadith_text',
        'hadith_text_ar',
      ].any((key) => fields[key]!.trim().isEmpty)) {
        throw const FormatException('Missing hadith source text');
      }
      records[id] = Map.unmodifiable(fields);
    }
    final references = <String, Map<String, String>>{};
    for (final entry in (data['references'] as Map).entries) {
      final reference = Map<String, String>.from(entry.value as Map);
      if (!records.containsKey(reference['source_id']) ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(reference['original_sha256'] ?? '') ||
          Uri.tryParse(reference['original_source_url'] ?? '')?.scheme !=
              'https') {
        throw const FormatException('Invalid hadith source reference');
      }
      references[entry.key as String] = Map.unmodifiable(reference);
    }
    if (references.isEmpty ||
        records.isEmpty ||
        records.length > references.length ||
        references.values.map((value) => value['source_id']).toSet().length !=
            records.length) {
      throw const FormatException('Incomplete hadith source references');
    }
    return HadithTranslationSource._(
      expectedLocale,
      data['direction'] as String,
      data['attribution'] as String,
      Map.unmodifiable(source),
      Map.unmodifiable(records),
      Map.unmodifiable(references),
    );
  }

  Map<String, String>? forContent(String id, String originalText) {
    final reference = references[id];
    if (reference == null ||
        sha256.convert(utf8.encode(originalText)).toString() !=
            reference['original_sha256']) {
      return null;
    }
    return records[reference['source_id']];
  }
}
