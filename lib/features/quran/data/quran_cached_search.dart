import 'dart:convert';
import 'dart:io';
import 'quran_content.dart';
import 'quran_repository.dart';

class QuranContentMatch {
  QuranContentMatch(this.verse, this.text, this.source);
  final QuranVerse verse;
  final String text, source;
}

/// Searches downloaded provider responses only; never implies a full tafsir index.
Future<List<QuranContentMatch>> searchQuranCache(
  QuranContent content,
  QuranRepository repo,
  String query, {
  bool meanings = false,
  int? surah,
  int? juz,
}) async {
  final needle = normalizeQuranSearch(query);
  if (needle.isEmpty) return [];
  final matches = <String, QuranContentMatch>{};
  await for (final file in (await content.cacheDirectory()).list()) {
    if (file is! File || !file.path.endsWith('.json')) continue;
    try {
      final record = jsonDecode(await file.readAsString()) as Map;
      if (!content.isCacheRecordFresh(record)) {
        await file.delete();
        continue;
      }
      final url = record['url'] as String;
      final data = record['payload'] as Map;
      late String text, source;
      late Iterable<String> keys;
      if (meanings && url.contains('arabic_seraj')) {
        final result = data['result'] as Map;
        text = result['translation'] as String;
        source = 'السراج • QuranEnc';
        keys = ['${result['sura']}:${result['aya']}'];
      } else if (!meanings && url.contains('/tafsirs/')) {
        final result = data['tafsir'] as Map;
        final id = result['resource_id'] as int;
        if (!tafsirSources.containsKey(id)) continue;
        source = tafsirSources[id]!;
        keys = (result['verses'] as Map).keys.cast<String>();
        text = TafsirText(
          id,
          source,
          result['text'] as String,
          keys.toList(),
        ).text;
      } else {
        continue;
      }
      if (!normalizeQuranSearch(text).contains(needle)) continue;
      for (final key in keys) {
        final verse = repo.byKey[key];
        if (verse == null ||
            surah != null && verse.surah != surah ||
            juz != null && verse.juz != juz) {
          continue;
        }
        matches.putIfAbsent(key, () => QuranContentMatch(verse, text, source));
      }
    } catch (_) {
      /* Isolate one damaged or unrelated cached response. */
    }
  }
  final sorted = matches.values.toList()
    ..sort(
      (a, b) =>
          repo.verses.indexOf(a.verse).compareTo(repo.verses.indexOf(b.verse)),
    );
  return sorted;
}
