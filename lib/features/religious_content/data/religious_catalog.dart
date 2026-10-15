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
}

/// Versioned content with stable IDs; displayed scripture is never normalized.
class ReligiousCatalog {
  ReligiousCatalog.fromJson(Map<String, dynamic> data)
    : version = data['version'] as String,
      categories = (data['categories'] as List)
          .map((v) => ReligiousCategory(Map<String, dynamic>.from(v as Map)))
          .toList(),
      items = (data['items'] as List)
          .map((v) => ReligiousItem(Map<String, dynamic>.from(v as Map)))
          .toList() {
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
  final List<ReligiousCategory> categories;
  final List<ReligiousItem> items;
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
