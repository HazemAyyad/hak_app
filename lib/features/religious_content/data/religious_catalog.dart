import 'dart:convert';
import 'package:flutter/services.dart';
import '../../quran/data/quran_repository.dart';

class ReligiousCategory {
  ReligiousCategory(Map<String, dynamic> data)
    : id = data['id'] as String,
      parent = data['parent'] as String?,
      title = data['title'] as String,
      description = data['description'] as String? ?? '',
      image = data['image'] as String? ?? 'quran',
      header = data['header'] as String? ?? 'sunnah',
      kind = data['kind'] as String? ?? 'list';
  final String id, title, description, image, header, kind;
  final String? parent;
}

class ReligiousSection {
  ReligiousSection(Map<String, dynamic> data)
    : title = data['title'] as String,
      text = data['text'] as String,
      source = data['source'] as String?;
  final String title, text;
  final String? source;
}

class ReligiousMood {
  ReligiousMood(Map<String, dynamic> data)
    : id = data['id'] as String,
      title = data['title'] as String,
      image = data['image'] as String,
      icon = data['icon'] as String,
      itemIds = List<String>.from(data['item_ids'] as List);
  final String id, title, image, icon;
  final List<String> itemIds;
}

class ReligiousItem {
  ReligiousItem(Map<String, dynamic> data)
    : id = data['id'] as String,
      type = data['type'] as String,
      title = data['title'] as String,
      text = data['text'] as String,
      summary = data['summary'] as String? ?? '',
      source = data['source'] as String,
      sourceUrl = data['sourceUrl'] as String,
      image = data['image'] as String? ?? 'quran',
      categories = List<String>.from(data['categories'] as List),
      tags = List<String>.from(data['tags'] as List? ?? []),
      verseKeys = List<String>.from(data['verseKeys'] as List? ?? []),
      number = data['number'] as int? ?? 0,
      audioUrl = data['audioUrl'] as String?,
      reciter = data['reciter'] as String? ?? '',
      transliteration = data['transliteration'] as String? ?? '',
      related = List<String>.from(data['related'] as List? ?? []),
      sections = (data['sections'] as List? ?? [])
          .map((s) => ReligiousSection(Map<String, dynamic>.from(s as Map)))
          .toList();
  final String id, type, title, text, summary, source, sourceUrl, image;
  final String reciter, transliteration;
  final String? audioUrl;
  final int number;
  final List<String> categories, tags, verseKeys, related;
  final List<ReligiousSection> sections;
  String get searchable =>
      normalizeQuranSearch('$title $text $summary $source ${tags.join(' ')}');
  String get shareText => '$title\n\n$text\n\n$source\n$sourceUrl';
  String get copyText {
    if (type == 'name' && summary.isNotEmpty) return '$text\n$summary';
    // A few source files put the collection reference at the end of the body.
    // Keep the narration intact; omit only that trailing bibliographic note.
    if (type == 'hadith') {
      return text.replaceFirst(RegExp(r'\s*\(رواه[\s\S]*\)\.?\s*$'), '').trim();
    }
    return text;
  }
}

/// Versioned content with stable IDs; displayed scripture is never normalized.
class ReligiousCatalog {
  ReligiousCatalog.fromJson(Map<String, dynamic> data)
    : _raw = Map<String, dynamic>.from(data),
      version = data['version'] as String,
      sourceVersion =
          data['upstream_version'] as String? ?? data['version'] as String,
      categories = (data['categories'] as List)
          .map((v) => ReligiousCategory(Map<String, dynamic>.from(v as Map)))
          .toList(),
      items = (data['items'] as List)
          .map((v) => ReligiousItem(Map<String, dynamic>.from(v as Map)))
          .toList(),
      moods = (data['moods'] as List? ?? [])
          .map((v) => ReligiousMood(Map<String, dynamic>.from(v as Map)))
          .toList(),
      ramadanDays = {
        for (final value in data['ramadan_days'] as List? ?? [])
          value['day'] as int: value['item_id'] as String,
      },
      ramadanDaysNote = data['ramadan_days_note'] as String? ?? '' {
    byId = {for (final item in items) item.id: item};
    byCategory = {for (final category in categories) category.id: category};
    if (byId.length != items.length ||
        byCategory.length != categories.length ||
        ![
          'quran-duas',
          'prophetic-duas',
          'sunnah',
          'friday',
          'nawawi',
          'ruqya',
          'names',
        ].every(byCategory.containsKey)) {
      throw const FormatException('Invalid religious catalog identities');
    }
    for (final item in items) {
      if (item.text.isEmpty ||
          item.source.isEmpty ||
          !item.categories.every(byCategory.containsKey)) {
        throw const FormatException(
          'Religious content has no valid source/category',
        );
      }
      if (!item.related.every(byId.containsKey)) {
        throw const FormatException('Invalid related religious content');
      }
    }
    if (moods.map((mood) => mood.id).toSet().length != moods.length ||
        moods.any(
          (mood) =>
              ![
                'happy',
                'sad',
                'anxiety',
                'rest',
                'love',
                'contentment',
              ].contains(mood.image) ||
              !byCategory.containsKey('mood-${mood.id}') ||
              !mood.itemIds.every(byId.containsKey),
        ) ||
        ramadanDays.entries.any(
          (entry) =>
              entry.key < 1 || entry.key > 30 || !byId.containsKey(entry.value),
        )) {
      throw const FormatException('Invalid curated content');
    }
    for (final category in categories) {
      final visited = <String>{category.id};
      var parent = category.parent;
      while (parent != null) {
        if (!visited.add(parent) || !byCategory.containsKey(parent)) {
          throw const FormatException('Invalid category hierarchy');
        }
        parent = byCategory[parent]!.parent;
      }
    }
  }
  static Future<ReligiousCatalog> load() async => ReligiousCatalog.fromJson(
    jsonDecode(await rootBundle.loadString('assets/religious/catalog.json'))
        as Map<String, dynamic>,
  );
  final String version;
  final String sourceVersion;
  final Map<String, dynamic> _raw;

  /// Keep new bundled features with an old server/cache, preserving editorial
  /// changes and never resurrecting unpublished legacy item IDs.
  ReligiousCatalog extendLegacy(Map<String, dynamic> candidate) {
    if ((candidate['schema_version'] as int? ?? 1) >= 2 ||
        _raw['bundled_extensions'] == null) {
      return ReligiousCatalog.fromJson(candidate);
    }
    final extensions = _raw['bundled_extensions'] as Map;
    final newCategories = Set<String>.from(extensions['category_ids'] as List);
    final newItems = Set<String>.from(extensions['item_ids'] as List);
    final categories = {
      for (final record in candidate['categories'] as List)
        record['id'] as String: Map<String, dynamic>.from(record as Map),
    };
    for (final category in _raw['categories'] as List) {
      if (newCategories.contains(category['id'])) {
        categories.putIfAbsent(
          category['id'] as String,
          () => Map<String, dynamic>.from(category as Map),
        );
      }
    }
    final fresh = {
      for (final record in _raw['items'] as List)
        record['id'] as String: record as Map,
    };
    final records = {
      for (final record in candidate['items'] as List)
        record['id'] as String: Map<String, dynamic>.from(record as Map),
    };
    for (final record in records.values) {
      record['categories'] = {
        ...List<String>.from(record['categories'] as List),
        ...List<String>.from(
          fresh[record['id']]?['categories'] as List? ?? [],
        ).where(newCategories.contains),
      }.where(categories.containsKey).toList();
    }
    for (final id in newItems) {
      records.putIfAbsent(id, () => Map<String, dynamic>.from(fresh[id]!));
    }
    return ReligiousCatalog.fromJson({
      ...candidate,
      'schema_version': 2,
      'version': '${candidate['version']}+bundle:$version',
      'upstream_version': candidate['version'],
      'categories': categories.values.toList(),
      'items': records.values.toList(),
      'moods': [
        for (final mood in _raw['moods'] as List)
          if (categories.containsKey('mood-${mood['id']}'))
            {
              ...Map<String, dynamic>.from(mood as Map),
              'item_ids': List<String>.from(
                mood['item_ids'] as List,
              ).where(records.containsKey).toList(),
            },
      ],
      'ramadan_days': [
        for (final day in _raw['ramadan_days'] as List)
          if (records.containsKey(day['item_id'])) day,
      ],
      'ramadan_days_note': _raw['ramadan_days_note'],
    });
  }

  final List<ReligiousCategory> categories;
  final List<ReligiousItem> items;
  final List<ReligiousMood> moods;
  final Map<int, String> ramadanDays;
  final String ramadanDaysNote;
  late final Map<String, ReligiousItem> byId;
  late final Map<String, ReligiousCategory> byCategory;
  List<ReligiousCategory> children(String? parent) =>
      categories.where((c) => c.parent == parent).toList();
  List<ReligiousItem> search({
    String? category,
    String query = '',
    String? tag,
    Set<String>? favorites,
  }) {
    final needle = normalizeQuranSearch(query);
    final categoryIds = <String>{?category};
    void descendants(String id) {
      for (final child in children(id)) {
        categoryIds.add(child.id);
        descendants(child.id);
      }
    }

    if (category != null) descendants(category);
    return items
        .where(
          (item) =>
              (category == null || item.categories.any(categoryIds.contains)) &&
              (needle.isEmpty || item.searchable.contains(needle)) &&
              (tag == null || item.tags.contains(tag)) &&
              (favorites == null || favorites.contains(item.id)),
        )
        .toList();
  }
}
