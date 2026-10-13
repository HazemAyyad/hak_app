import 'dart:convert';
import 'package:flutter/services.dart';
import 'quran_repository.dart';

String? reciterPortrait(String name) {
  const root = 'https://static.qurancdn.com/images/reciters';
  if (name.contains('مشاري')) {
    return '$root/6/mishary-rashid-alafasy-profile.jpeg?v=1';
  }
  if (name.contains('السديس')) {
    return '$root/2/abdul-rahman-al-sudais-profile.jpeg?v=1';
  }
  if (name.contains('عبد الباسط')) {
    return '$root/1/abdelbasset-profile.jpeg?v=1';
  }
  if (name.contains('سعد الغامدي')) {
    return '$root/16/saad-al-ghamdi-profile.png?v=1';
  }
  return null;
}

class QuranRecitation {
  QuranRecitation({
    required this.id,
    required this.name,
    required this.style,
    required this.server,
    required this.chapters,
    this.quality,
    this.updated = '',
  });
  final String id, name, style, server, updated;
  final String? quality;
  final Set<int> chapters;
  bool get verseAudio => id.startsWith('everyayah:');
  QuranAudioTrack track(QuranRepository repo, int surah, {int? ayah}) {
    if (!chapters.contains(surah)) throw ArgumentError('Unavailable chapter');
    if (verseAudio &&
        (ayah == null || ayah < 1 || ayah > repo.surah(surah).ayahCount)) {
      throw ArgumentError('Invalid verse');
    }
    final filename = verseAudio
        ? '${surah.toString().padLeft(3, '0')}${ayah!.toString().padLeft(3, '0')}.mp3'
        : '${surah.toString().padLeft(3, '0')}.mp3';
    return QuranAudioTrack(
      id: '$id:$surah${verseAudio ? ':$ayah' : ''}',
      recitation: id,
      reciter: name,
      title:
          'سورة ${repo.surah(surah).name}${verseAudio ? ' • الآية $ayah' : ''}',
      surah: surah,
      ayah: verseAudio ? ayah : null,
      url: Uri.parse(server).resolve(filename).toString(),
      version: updated.isEmpty ? 'catalog-2026-10-13' : updated,
      quality: quality ?? style,
    );
  }
}

class QuranAudioTrack {
  QuranAudioTrack({
    required this.id,
    required this.recitation,
    required this.reciter,
    required this.title,
    required this.surah,
    required this.url,
    required this.version,
    required this.quality,
    this.ayah,
  });
  final String id, recitation, reciter, title, url, version, quality;
  final int surah;
  final int? ayah;
  String get storageKey =>
      '${id}_$version'.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  Map<String, dynamic> toJson() => {
    'id': id,
    'recitation': recitation,
    'reciter': reciter,
    'title': title,
    'surah': surah,
    'ayah': ayah,
    'url': url,
    'version': version,
    'quality': quality,
  };
  factory QuranAudioTrack.fromJson(Map<String, dynamic> data) =>
      QuranAudioTrack(
        id: data['id'] as String,
        recitation: data['recitation'] as String,
        reciter: data['reciter'] as String,
        title: data['title'] as String,
        surah: data['surah'] as int,
        ayah: data['ayah'] as int?,
        url: data['url'] as String,
        version: data['version'] as String,
        quality: data['quality'] as String,
      );
}

class QuranAudioCatalog {
  QuranAudioCatalog(this.recitations);
  final List<QuranRecitation> recitations;
  static Future<QuranAudioCatalog> load() async => QuranAudioCatalog.fromJson(
    jsonDecode(await rootBundle.loadString('assets/quran/audio_catalog.json'))
        as Map<String, dynamic>,
  );
  factory QuranAudioCatalog.fromJson(Map<String, dynamic> data) {
    final entries = <QuranRecitation>[];
    for (final reciter in data['reciters'] as List) {
      for (final moshaf in reciter['moshaf'] as List) {
        if (moshaf['rewaya_id'] != 1) continue;
        final server = Uri.parse(moshaf['server'] as String);
        if (server.scheme != 'https' ||
            !(server.host == 'mp3quran.net' ||
                server.host.endsWith('.mp3quran.net'))) {
          continue;
        }
        entries.add(
          QuranRecitation(
            id: 'mp3quran:${moshaf['id']}',
            name: reciter['name'] as String,
            style: moshaf['name'] as String,
            server: server.toString(),
            updated: reciter['date'] as String? ?? '',
            chapters: (moshaf['surah_list'] as String)
                .split(',')
                .map(int.parse)
                .where((id) => id >= 1 && id <= 114)
                .toSet(),
          ),
        );
      }
    }
    for (final entry in data['everyAyah'] as List) {
      final folder = entry['folder'] as String;
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(folder)) {
        throw const FormatException('Unsafe recitation folder');
      }
      entries.add(
        QuranRecitation(
          id: 'everyayah:${entry['id']}',
          name: entry['name'] as String,
          style: 'حفص عن عاصم • ملفات الآيات',
          server: 'https://everyayah.com/data/$folder/',
          quality: entry['quality'] as String,
          chapters: Set.of(List.generate(114, (i) => i + 1)),
        ),
      );
    }
    return QuranAudioCatalog(entries);
  }
}
