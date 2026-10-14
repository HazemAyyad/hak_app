import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quran_repository.dart';
import 'quran_content.dart';
import 'quran_audio.dart';
import 'quran_sync.dart';
import 'quran_downloads.dart';

enum QuranReadingMode { continuous, ayah, pages }

class QuranController extends ChangeNotifier {
  QuranController({
    this.initialRepository,
    this.preferences,
    QuranContent? content,
    this.accountFactory,
    this.downloads,
  }) : content = content ?? QuranContent();
  final QuranContent content;
  final QuranAccount Function(QuranController)? accountFactory;
  late final QuranAccount account =
      accountFactory?.call(this) ?? QuranAccount(this);
  bool _accountReady = false;
  late final QuranMedia media = QuranMedia(
    repository: () => repository!,
    preferences: () => preferences!,
    downloads: downloads,
  );
  final QuranDownloads? downloads;
  bool _mediaUsed = false;
  QuranMedia get audio {
    _mediaUsed = true;
    return media;
  }

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
  int? lastPage;
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
      content.attachRepository(repo);
      preferences = prefs;
      final raw = prefs.getString('quran.state.v1');
      if (raw != null) {
        try {
          restoreState(jsonDecode(raw) as Map<String, dynamic>);
        } catch (_) {}
      }
      _accountReady = true;
      await account.initialize();
    } catch (error) {
      if (!_disposed) loadError = error;
    } finally {
      if (!_disposed) {
        loading = false;
        _emit();
      }
    }
  }

  void restoreState(Map<String, dynamic> state) {
    favorites.clear();
    bookmarks.clear();
    savedSurahs.clear();
    readJuzs.clear();
    lastKey = null;
    lastPage = null;
    lastAlignment = 0;
    mode = QuranReadingMode.continuous;
    fontSize = 24;
    paper = 'light';
    final key = state['lastKey'] as String?;
    lastKey = repository!.byKey.containsKey(key) ? key : null;
    lastPage = (state['page'] as int?)?.clamp(1, 604);
    lastAlignment = ((state['alignment'] as num?)?.toDouble() ?? 0).clamp(
      0,
      .9,
    );
    mode = QuranReadingMode.values.firstWhere(
      (value) => value.name == state['mode'],
      orElse: () => QuranReadingMode.continuous,
    );
    fontSize = ((state['fontSize'] as num?)?.toDouble() ?? 24).clamp(18, 36);
    paper = ['light', 'ivory', 'green', 'dark'].contains(state['paper'])
        ? state['paper'] as String
        : 'light';
    for (final pair in [('favorites', favorites), ('bookmarks', bookmarks)]) {
      final entries = (state[pair.$1] as Map?) ?? {};
      for (final entry in entries.entries) {
        if (repository!.byKey.containsKey(entry.key) && entry.value is String) {
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
  }

  void remember(QuranVerse verse, {double alignment = 0, int? page}) {
    final selectedPage = page ?? verse.page;
    if (lastKey == verse.key &&
        lastPage == selectedPage &&
        (lastAlignment - alignment).abs() < .01) {
      return;
    }
    lastKey = verse.key;
    lastPage = selectedPage.clamp(1, 604);
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
    final storageKey = _accountReady ? account.stateKey : 'quran.state.v1';
    if (_accountReady) account.changed();
    final snapshot = jsonEncode({
      'lastKey': lastKey,
      'alignment': lastAlignment,
      'page': lastPage,
      'mode': mode.name,
      'fontSize': fontSize,
      'paper': paper,
      'favorites': favorites,
      'bookmarks': bookmarks,
      'savedSurahs': savedSurahs.toList(),
      'readJuzs': readJuzs.toList(),
    });
    _writes = _writes.catchError((Object _) {}).then((_) async {
      await prefs.setString(storageKey, snapshot);
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
    if (_mediaUsed) media.dispose();
    if (_accountReady) account.dispose();
    super.dispose();
  }
}
