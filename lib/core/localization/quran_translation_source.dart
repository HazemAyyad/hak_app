import 'dart:convert';
import 'package:crypto/crypto.dart';

class PublishedVerseMeaning {
  const PublishedVerseMeaning(this.key, this.translation, this.footnotes);
  final String key, translation, footnotes;
}

/// Retains provider data; its Arabic fields never replace the bundled Quran.
class QuranTranslationSource {
  QuranTranslationSource._(
    this.title,
    this.version,
    this.attribution,
    this.direction,
    this.verses,
    this.references,
  );
  final String title, version, attribution, direction;
  final Map<String, PublishedVerseMeaning> verses;
  final Map<String, List<String>> references;

  factory QuranTranslationSource.verify(Map envelope, String expectedLocale) {
    final artifact = envelope['artifact'] as String;
    if (utf8.encode(artifact).length > 8 * 1024 * 1024 ||
        sha256.convert(utf8.encode(artifact)).toString() !=
            envelope['sha256']) {
      throw const FormatException('Invalid Quran source bytes');
    }
    final data = jsonDecode(artifact) as Map;
    final metadata = data['source'] as Map;
    final providerLocale =
        {'fil': 'tl', 'zh-Hans': 'zh', 'ckb': 'ku'}[expectedLocale] ??
        expectedLocale;
    if (data['format'] != 'haq.source.review' ||
        data['schema'] != 1 ||
        data['provider'] != 'QuranEnc.com' ||
        data['locale'] != expectedLocale ||
        metadata['language_iso_code'] != providerLocale ||
        !RegExp(r'^[a-z0-9_]{1,80}$').hasMatch(metadata['key'] as String) ||
        !RegExp(r'^[0-9.]{1,30}$').hasMatch(metadata['version'] as String) ||
        !['ltr', 'rtl'].contains(metadata['direction']) ||
        metadata['title'] is! String ||
        data['policy_url'] != 'https://quranenc.com/en/home' ||
        data['attribution'] is! String) {
      throw const FormatException('Invalid Quran source metadata');
    }
    final verses = <String, PublishedVerseMeaning>{};
    for (final entry in (data['surahs'] as Map).entries) {
      final response = entry.value as Map;
      final raw = response['raw_json'] as String;
      if (sha256.convert(utf8.encode(raw)).toString() != response['sha256']) {
        throw const FormatException('Invalid source response');
      }
      final rows = (jsonDecode(raw) as Map)['result'] as List;
      for (final row in rows) {
        final surah = int.tryParse(row['sura'].toString());
        final ayah = int.tryParse(row['aya'].toString());
        if (surah == null ||
            surah < 1 ||
            surah > 114 ||
            ayah == null ||
            ayah < 1 ||
            ayah > 286 ||
            surah.toString() != entry.key.toString() ||
            row['translation'] is! String ||
            (row['translation'] as String).isEmpty ||
            row['footnotes'] is! String) {
          throw const FormatException('Invalid source verse');
        }
        final key = '$surah:$ayah';
        if (verses.containsKey(key)) {
          throw const FormatException('Duplicate source verse');
        }
        verses[key] = PublishedVerseMeaning(
          key,
          row['translation'] as String,
          row['footnotes'] as String,
        );
      }
    }
    final references = <String, List<String>>{};
    for (final entry in (data['references'] as Map).entries) {
      final keys = List<String>.from(entry.value as List);
      if (keys.isEmpty || !keys.every(verses.containsKey)) {
        throw const FormatException('Invalid source references');
      }
      references[entry.key as String] = keys;
    }
    if (verses.isEmpty || references.isEmpty) {
      throw const FormatException('Empty Quran source');
    }
    return QuranTranslationSource._(
      metadata['title'] as String,
      metadata['version'] as String,
      data['attribution'] as String,
      metadata['direction'] as String,
      verses,
      references,
    );
  }

  List<PublishedVerseMeaning> forContent(String id) => [
    for (final key in references[id] ?? <String>[]) verses[key]!,
  ];
}
