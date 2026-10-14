import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quran_repository.dart';

enum QuranReadingMode { continuous, ayah }

class QuranController extends ChangeNotifier {
  QuranController({this.initialRepository, this.preferences});
  final QuranRepository? initialRepository;
  SharedPreferences? preferences;
  QuranRepository? repository;
  Object? loadError;
  bool loading = true;
  bool _disposed = false;
  Timer? _readingSaveTimer;
  Future<void> _writes = Future.value();

  String? lastKey;
  double lastAlignment = 0;
  QuranReadingMode mode = QuranReadingMode.continuous;
  double fontSize = 24;
  String paper = 'light';
  final Map<String, String> favorites = {};
  final Map<String, String> bookmarks = {};
  final Set<int> savedSurahs = {};
  final Set<int> readJuzs = {};

  QuranVerse? get lastVerse => repository?.byKey[lastKey];

  Future<void> load() async {
    loading = true;
    loadError = null;
    _emit();
    try {
      final repo = initialRepository ?? await QuranRepository.load();
      final prefs = preferences ?? await SharedPreferences.getInstance();
      if (_disposed) return;
      repository = repo;
      preferences = prefs;
      final raw = prefs.getString('quran.state.v1');
      if (raw != null) {
        try {
          final state = jsonDecode(raw) as Map<String, dynamic>;
          final key = state['lastKey'] as String?;
          lastKey = repo.byKey.containsKey(key) ? key : null;
          lastAlignment = ((state['alignment'] as num?)?.toDouble() ?? 0).clamp(
            0,
            .9,
          );
          mode = state['mode'] == 'ayah'
              ? QuranReadingMode.ayah
              : QuranReadingMode.continuous;
          fontSize = ((state['fontSize'] as num?)?.toDouble() ?? 24).clamp(
            18,
            36,
          );
          paper = ['light', 'ivory', 'green', 'dark'].contains(state['paper'])
              ? state['paper'] as String
              : 'light';
          for (final pair in [
            ('favorites', favorites),
            ('bookmarks', bookmarks),
          ]) {
            final entries = (state[pair.$1] as Map?) ?? {};
            for (final entry in entries.entries) {
              if (repo.byKey.containsKey(entry.key) && entry.value is String) {
                pair.$2[entry.key as String] = entry.value as String;
              }
            }
          }
          savedSurahs.addAll(
            (state['savedSurahs'] as List? ?? []).whereType<int>().where(
              (n) => n >= 1 && n <= 114,
            ),
          );
          readJuzs.addAll(
            (state['readJuzs'] as List? ?? []).whereType<int>().where(
              (n) => n >= 1 && n <= 30,
            ),
          );
        } on FormatException {
          // A damaged preference must never prevent opening the local Quran.
        } on TypeError {
          // Retain safe defaults if a previous app version stored another shape.
        }
      }
    } catch (error) {
      if (!_disposed) loadError = error;
    } finally {
      if (!_disposed) {
        loading = false;
        _emit();
      }
    }
  }

  void remember(QuranVerse verse, {double alignment = 0}) {
    if (lastKey == verse.key && (lastAlignment - alignment).abs() < .01) return;
    lastKey = verse.key;
    lastAlignment = alignment.clamp(0, .9);
    // Do not rebuild the entire reading list on every visible-position event.
    _readingSaveTimer?.cancel();
    _readingSaveTimer = Timer(const Duration(milliseconds: 300), () {
      persist();
      _emit();
    });
  }

  void toggleFavorite(String key) => _toggle(favorites, key);
  void toggleBookmark(String key) => _toggle(bookmarks, key);
  void _toggle(Map<String, String> collection, String key) {
    if (repository?.byKey.containsKey(key) != true) return;
    if (collection.containsKey(key)) {
      collection.remove(key);
    } else {
      collection[key] = DateTime.now().toUtc().toIso8601String();
    }
    persist();
    _emit();
  }

  void toggleSurah(int id) {
    if (!savedSurahs.remove(id)) savedSurahs.add(id);
    persist();
    _emit();
  }

  void setMode(QuranReadingMode value) {
    mode = value;
    persist();
    _emit();
  }

  void setFontSize(double value) {
    fontSize = value.clamp(18, 36);
    persist();
    _emit();
  }

  void setPaper(String value) {
    paper = value;
    persist();
    _emit();
  }

  Future<void> persist() {
    final prefs = preferences;
    if (prefs == null) return Future.value();
    final snapshot = jsonEncode({
      'lastKey': lastKey,
      'alignment': lastAlignment,
      'mode': mode.name,
      'fontSize': fontSize,
      'paper': paper,
      'favorites': favorites,
      'bookmarks': bookmarks,
      'savedSurahs': savedSurahs.toList(),
      'readJuzs': readJuzs.toList(),
    });
    _writes = _writes.then((_) async {
      await prefs.setString('quran.state.v1', snapshot);
    });
    return _writes;
  }

  Future<void> flushReading() {
    _readingSaveTimer?.cancel();
    _readingSaveTimer = null;
    return persist();
  }

  void refreshReading() => _emit();

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _readingSaveTimer?.cancel();
    persist();
    _disposed = true;
    super.dispose();
  }
}
