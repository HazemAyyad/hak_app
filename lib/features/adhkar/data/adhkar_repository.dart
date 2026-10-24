import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../../quran/data/quran_repository.dart';
import '../../religious_activity/data/activity_models.dart';
import '../../religious_activity/data/activity_store.dart';

/// RFC 4122 name UUIDs let offline devices identify the same daily session.
/// Account separation belongs to the store/API scope, never to a leaked token.
String adhkarIdentity(String name) {
  const namespace = [
    0x6b,
    0xa7,
    0xb8,
    0x10,
    0x9d,
    0xad,
    0x11,
    0xd1,
    0x80,
    0xb4,
    0x00,
    0xc0,
    0x4f,
    0xd4,
    0x30,
    0xc8,
  ];
  final bytes = sha1
      .convert([...namespace, ...utf8.encode('haq:adhkar:$name')])
      .bytes
      .take(16)
      .toList();
  bytes[6] = (bytes[6] & 15) | 0x50;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class DhikrEntry {
  const DhikrEntry({
    required this.id,
    required this.title,
    required this.text,
    required this.target,
    required this.source,
    this.sourceUrl,
    this.audioUrl,
    this.haqContentId,
    this.personal = false,
    this.preface = '',
  });
  final String id, title, text, source, preface;
  final int target;
  final String? sourceUrl, audioUrl, haqContentId;
  final bool personal;
}

class DhikrGroup {
  const DhikrGroup({
    required this.id,
    required this.title,
    required this.itemIds,
    this.icon = 'leaf',
    this.personal,
  });
  final String id, title, icon;
  final List<String> itemIds;
  final PersonalDhikrGroup? personal;
}

class AdhkarRepository {
  static const savedGroupId = 'f80bc18e-2026-4000-8000-000000000001';
  AdhkarRepository._(this.version, this.groups, this.items);
  final String version;
  final List<DhikrGroup> groups;
  final Map<String, DhikrEntry> items;
  static Future<AdhkarRepository> load(QuranRepository quran) async => fromJson(
    jsonDecode(await rootBundle.loadString('assets/religious/adhkar.json'))
        as Map<String, dynamic>,
    quran,
  );
  static AdhkarRepository fromJson(
    Map<String, dynamic> data,
    QuranRepository quran,
  ) {
    if (data['schema_version'] != 1) {
      throw const FormatException('Unsupported dhikr schema');
    }
    final items = <String, DhikrEntry>{};
    for (final raw in data['items'] as List) {
      final item = raw as Map;
      final id = activitySubject(item['id'] as String);
      if (items.containsKey(id) ||
          item['target'] is! int ||
          (item['target'] as int) < 1 ||
          (item['text'] as String).trim().isEmpty) {
        throw const FormatException('Invalid dhikr source');
      }
      for (final part in item['scripture'] as List) {
        final canonical = (part['keys'] as List)
            .map((key) => quran.byKey[key]!.text)
            .join(' ');
        if (!canonical.contains(part['text'] as String) ||
            !(item['text'] as String).contains('﴿${part['text']}﴾')) {
          throw const FormatException('Scripture mismatch');
        }
      }
      final audio = item['audio_url'] as String?;
      if (audio != null &&
          !RegExp(
            r'^https://www\.hisnmuslim\.com/audio/ar/[0-9]+\.mp3$',
          ).hasMatch(audio)) {
        throw const FormatException('Invalid recording');
      }
      items[id] = DhikrEntry(
        id: id,
        title: item['title'] as String,
        text: item['text'] as String,
        target: item['target'] as int,
        source: item['source'] as String,
        sourceUrl: item['source_url'] as String,
        audioUrl: audio,
        haqContentId: item['haq_content_id'] as String,
      );
    }
    final groups = <DhikrGroup>[];
    for (final raw in data['groups'] as List) {
      final ids = List<String>.from(raw['item_ids'] as List);
      if (ids.toSet().length != ids.length ||
          ids.any((id) => !items.containsKey(id))) {
        throw const FormatException('Invalid group members');
      }
      groups.add(
        DhikrGroup(
          id: activitySubject(raw['id'] as String),
          title: raw['title'] as String,
          icon: raw['icon'] as String,
          itemIds: List.unmodifiable(ids),
        ),
      );
    }
    return AdhkarRepository._(
      data['version'] as String,
      List.unmodifiable(groups),
      Map.unmodifiable(items),
    );
  }

  Future<AdhkarLibrary> library(
    ReligiousActivityStore store,
    String scope,
  ) async {
    final personal = await store.entities(scope);
    final entries = <String, DhikrEntry>{...items};
    for (final entity in personal.whereType<PersonalDhikr>()) {
      entries[entity.key] = DhikrEntry(
        id: entity.key,
        title: 'ذكر شخصي',
        text: entity.text,
        target: entity.target,
        source: entity.source,
        preface: entity.preface,
        personal: true,
      );
    }
    final custom = personal.whereType<PersonalDhikrGroup>().toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final saved = custom.where((g) => g.id == savedGroupId).firstOrNull;
    final overrides = {
      for (final g in groups) adhkarIdentity('override:${g.id}'): g.id,
    };
    final all = [
      for (final base in groups) _effectiveGroup(base, custom, entries),
      DhikrGroup(
        id: 'group:$savedGroupId',
        title: 'الأذكار المحفوظة',
        itemIds: saved?.itemIds.where(entries.containsKey).toList() ?? [],
      ),
      DhikrGroup(
        id: 'personal:all',
        title: 'كل أذكاري الشخصية',
        itemIds: [for (final e in personal.whereType<PersonalDhikr>()) e.key],
      ),
      for (final group in custom.where(
        (g) => g.id != savedGroupId && !overrides.containsKey(g.id),
      ))
        DhikrGroup(
          id: group.key,
          title: group.title,
          itemIds: group.itemIds.where(entries.containsKey).toList(),
          personal: group,
        ),
    ];
    return AdhkarLibrary(List.unmodifiable(all), Map.unmodifiable(entries));
  }

  DhikrGroup _effectiveGroup(
    DhikrGroup base,
    List<PersonalDhikrGroup> groups,
    Map<String, DhikrEntry> entries,
  ) {
    final override = groups
        .where((g) => g.id == adhkarIdentity('override:${base.id}'))
        .firstOrNull;
    if (override == null) return base;
    return DhikrGroup(
      id: base.id,
      title: override.title,
      itemIds: override.itemIds.where(entries.containsKey).toList(),
      icon: base.icon,
      personal: override,
    );
  }
}

class AdhkarLibrary {
  const AdhkarLibrary(this.groups, this.entries);
  final List<DhikrGroup> groups;
  final Map<String, DhikrEntry> entries;
}
