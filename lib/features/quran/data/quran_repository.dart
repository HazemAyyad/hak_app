import 'dart:convert';

import 'package:flutter/services.dart';

String normalizeQuranSearch(String value) => value
    .replaceAll(
      RegExp('[\u0610-\u061a\u064b-\u065f\u0670\u06d6-\u06ed\u0640]'),
      '',
    )
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class QuranVerse {
  QuranVerse(Map<String, dynamic> json)
    : key = json['key'] as String,
      surah = json['surah'] as int,
      ayah = json['ayah'] as int,
      text = json['text'] as String,
      page = json['page'] as int,
      juz = json['juz'] as int,
      searchText = normalizeQuranSearch(
        (json['searchText'] ?? json['text']) as String,
      );

  final String key, text, searchText;
  final int surah, ayah, page, juz;
}

class QuranSurah {
  QuranSurah(Map<String, dynamic> json)
    : id = json['id'] as int,
      name = json['name'] as String,
      ayahCount = json['ayahCount'] as int,
      start = json['start'] as int,
      startPage = json['startPage'] as int,
      meccan = json['revelation'] == 'Meccan',
      basmala = json['basmala'] as String?;

  final int id, ayahCount, start, startPage;
  final String name;
  final String? basmala;
  final bool meccan;
  String get revelation => meccan ? 'مكية' : 'مدنية';
}

class QuranJuz {
  QuranJuz(Map<String, dynamic> json)
    : id = json['id'] as int,
      startKey = json['startKey'] as String,
      endKey = json['endKey'] as String,
      startSurah = json['startSurah'] as int,
      endSurah = json['endSurah'] as int,
      startAyah = json['startAyah'] as int,
      endAyah = json['endAyah'] as int,
      ayahCount = json['ayahCount'] as int;
  final int id, startSurah, endSurah, startAyah, endAyah, ayahCount;
  final String startKey, endKey;
}

class QuranRepository {
  QuranRepository.fromJson(Map<String, dynamic> data)
    : version = data['version'] as String,
      sourceUrl = data['sourceUrl'] as String,
      license = data['textLicense'] as String,
      surahs = (data['surahs'] as List)
          .map((json) => QuranSurah(json as Map<String, dynamic>))
          .toList(),
      juzs = (data['juzs'] as List)
          .map((json) => QuranJuz(json as Map<String, dynamic>))
          .toList(),
      verses = (data['verses'] as List)
          .map((json) => QuranVerse(json as Map<String, dynamic>))
          .toList() {
    if (surahs.length != 114 || verses.length != 6236 || juzs.length != 30) {
      throw const FormatException('Incomplete Quran dataset');
    }
    byKey = {for (final verse in verses) verse.key: verse};
  }

  static Future<QuranRepository> load() async => QuranRepository.fromJson(
    jsonDecode(await rootBundle.loadString('assets/quran/quran.json'))
        as Map<String, dynamic>,
  );

  final String version, sourceUrl, license;
  final List<QuranSurah> surahs;
  final List<QuranJuz> juzs;
  final List<QuranVerse> verses;
  late final Map<String, QuranVerse> byKey;

  QuranSurah surah(int id) => surahs[id - 1];
  List<QuranVerse> surahVerses(int id) {
    final chapter = surah(id);
    return verses.sublist(chapter.start, chapter.start + chapter.ayahCount);
  }

  List<QuranVerse> search(String query, {int? surahId, int? juzId}) {
    final needle = normalizeQuranSearch(query);
    if (needle.isEmpty) return [];
    return verses
        .where(
          (verse) =>
              (surahId == null || verse.surah == surahId) &&
              (juzId == null || verse.juz == juzId) &&
              verse.searchText.contains(needle),
        )
        .toList();
  }
}

String juzName(int id) {
  const names = [
    'الأول',
    'الثاني',
    'الثالث',
    'الرابع',
    'الخامس',
    'السادس',
    'السابع',
    'الثامن',
    'التاسع',
    'العاشر',
    'الحادي عشر',
    'الثاني عشر',
    'الثالث عشر',
    'الرابع عشر',
    'الخامس عشر',
    'السادس عشر',
    'السابع عشر',
    'الثامن عشر',
    'التاسع عشر',
    'العشرون',
    'الحادي والعشرون',
    'الثاني والعشرون',
    'الثالث والعشرون',
    'الرابع والعشرون',
    'الخامس والعشرون',
    'السادس والعشرون',
    'السابع والعشرون',
    'الثامن والعشرون',
    'التاسع والعشرون',
    'الثلاثون',
  ];
  return 'الجزء ${names[id - 1]}';
}
