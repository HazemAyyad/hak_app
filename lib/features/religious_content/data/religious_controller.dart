import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../quran/data/haq_api.dart';
import '../../quran/data/quran_audio.dart';
import '../../quran/data/quran_audio_models.dart';
import '../../quran/data/quran_controller.dart';
import '../../quran/data/quran_downloads.dart';
import '../../quran/data/quran_sync.dart';
import 'religious_catalog.dart';
import '../../religious_activity/data/activity_controller.dart';
import '../../adhkar/data/adhkar_repository.dart';

class ReligiousController extends ChangeNotifier {
  ReligiousController({
    required this.quran,
    this.initialCatalog,
    this.initialAdhkarCatalog,
    Dio? dio,
    QuranMedia? media,
    this.activityFactory,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: '$haqApiBase/v1/religious',
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 20),
             ),
           ),
       _media = media;
  final QuranController quran;
  final ReligiousCatalog? initialCatalog;
  final AdhkarRepository? initialAdhkarCatalog;
  final Dio dio;
  final Future<ReligiousActivityController> Function()? activityFactory;
  ReligiousCatalog? catalog;
  ReligiousCatalog? _bundledCatalog;
  QuranMedia? _media;
  Future<ReligiousActivityController>? _activity;
  Future<ReligiousActivityController> get activity =>
      _activity ??= _openActivity();
  Future<ReligiousActivityController> _openActivity() async {
    try {
      if (_disposed) throw StateError('Religious section disposed');
      final value =
          await (activityFactory?.call() ??
              ReligiousActivityController.open(quran));
      if (_disposed) {
        value.dispose();
        throw StateError('Religious section disposed');
      }
      return value;
    } catch (_) {
      _activity = null;
      rethrow;
    }
  }

  QuranMedia get media => _media ??= QuranMedia(
    repository: () => quran.repository!,
    preferences: () => quran.preferences!,
    storageKey: 'religious.audio.v1',
    downloads: QuranDownloads(storageFolder: 'religious_audio_v1'),
  );
  final favorites = <String>{};
  final customAdhkar = <String>{};
  final listeningQueue = <String>{};
  final progress = <String, Map<String, dynamic>>{};
  QuranSyncLedger ledger = QuranSyncLedger();
  bool loading = true, refreshing = false, syncing = false;
  bool _disposed = false, _listening = false;
  bool maintenance = false;
  Future<void> settle() async {
    _syncTimer?.cancel();
    await _sync;
    await _writes;
  }

  void reloadBackup() {
    _restore();
    _emit();
  }

  String? error, updateError, syncError, _owner;
  Timer? _syncTimer, _progressTimer, _retryTimer;
  Future<void> _writes = Future.value();
  Future<void>? _sync;
  String get _scope => _owner == null ? 'guest' : 'account.$_owner';
  String get _stateKey => 'religious.state.v1.$_scope';
  String get _ledgerKey => 'religious.sync.v1.$_scope';

  Future<void> load() async {
    loading = true;
    error = null;
    try {
      catalog = initialCatalog ?? await ReligiousCatalog.load();
      _bundledCatalog = catalog;
      if (_disposed) return;
      final cached = quran.preferences!.getString('religious.catalog.v1');
      if (initialCatalog == null && cached != null) {
        try {
          catalog = _bundledCatalog!.extendLegacy(
            jsonDecode(cached) as Map<String, dynamic>,
          );
        } catch (_) {
          /* Bundled catalog remains available. */
        }
      }
      _restore();
      quran.account.addListener(_accountChanged);
      _listening = true;
      await _changeOwner();
    } catch (_) {
      error = 'تعذّر تحميل المحتوى؛ أعد المحاولة';
    }
    loading = false;
    _emit();
  }

  void _restore() {
    favorites.clear();
    customAdhkar.clear();
    listeningQueue.clear();
    progress.clear();
    try {
      final data =
          jsonDecode(quran.preferences!.getString(_stateKey) ?? '{}') as Map;
      favorites.addAll((data['favorites'] as List? ?? []).whereType<String>());
      customAdhkar.addAll(
        (data['customAdhkar'] as List? ?? []).whereType<String>(),
      );
      listeningQueue.addAll((data['queue'] as List? ?? []).whereType<String>());
      for (final entry in (data['progress'] as Map? ?? {}).entries) {
        if (entry.value is Map) {
          progress[entry.key as String] = Map<String, dynamic>.from(
            entry.value as Map,
          );
        }
      }
      ledger = QuranSyncLedger(
        stored:
            jsonDecode(quran.preferences!.getString(_ledgerKey) ?? '{}')
                as Map<String, dynamic>,
      );
    } catch (_) {
      ledger = QuranSyncLedger();
    }
  }

  Map<String, dynamic> get entities => {
    for (final id in favorites) 'favorite:$id': true,
    for (final id in customAdhkar) 'adhkar:$id': true,
    for (final id in listeningQueue) 'queue:$id': true,
    for (final e in progress.entries) 'playback:${e.key}': e.value,
  };
  Future<void> _persist() {
    final key = _stateKey, ledgerKey = _ledgerKey;
    final state = jsonEncode({
      'favorites': favorites.toList(),
      'customAdhkar': customAdhkar.toList(),
      'queue': listeningQueue.toList(),
      'progress': progress,
    });
    final savedLedger = jsonEncode(ledger.toJson());
    _writes = _writes.catchError((Object _) {}).then((_) async {
      await quran.preferences!.setString(key, state);
      await quran.preferences!.setString(ledgerKey, savedLedger);
    });
    return _writes;
  }

  Future<void> toggleFavorite(String id) async {
    if (catalog?.byId.containsKey(id) != true) return;
    if (!favorites.remove(id)) favorites.add(id);
    _changed();
    await _persist();
  }

  Future<void> toggleAdhkar(String id) async {
    if (catalog?.byId.containsKey(id) != true) return;
    if (!customAdhkar.remove(id)) customAdhkar.add(id);
    _changed();
    await _persist();
  }

  Future<void> toggleQueue(String id) async {
    if (catalog?.byId.containsKey(id) != true) return;
    if (!listeningQueue.contains(id) && !hasAudio(catalog!.byId[id]!)) {
      error = 'التسجيل الصوتي لهذا المحتوى غير متاح حاليًا';
      _emit();
      return;
    }
    if (!listeningQueue.remove(id)) listeningQueue.add(id);
    _changed();
    await _persist();
  }

  void _changed() {
    if (_owner != null) ledger.record(entities);
    _emit();
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 2), () {
      unawaited(sync());
    });
  }

  void _accountChanged() {
    final owner = quran.account.profile?['id'].toString();
    if (owner != _owner) unawaited(_changeOwner());
  }

  Future<void> _changeOwner() async {
    final owner = quran.account.profile?['id'].toString();
    if (owner == _owner || _disposed) return;
    // Capture the guest snapshot once; server tombstones take precedence.
    final guest = _owner == null ? entities : <String, dynamic>{};
    _owner = owner;
    _retryTimer?.cancel();
    _retryTimer = owner == null
        ? null
        : Timer.periodic(const Duration(minutes: 1), (_) => unawaited(sync()));
    _progressTimer?.cancel();
    activeItem = null;
    _restore();
    if (owner != null &&
        guest.isNotEmpty &&
        quran.preferences!.getBool('religious.activity.mergeGuest.$owner') ==
            true) {
      await quran.preferences!.setString(
        'religious.merge.$owner',
        jsonEncode(guest),
      );
    }
    _emit();
    if (_sync != null) await _sync;
    if (_owner != owner || _disposed) return;
    await sync();
  }

  Future<void> sync() async {
    if (_owner == null ||
        quran.account.token == null ||
        _disposed ||
        maintenance) {
      return;
    }
    if (_sync != null) return _sync;
    final owner = _owner, token = quran.account.token;
    _sync = (() async {
      syncing = true;
      syncError = null;
      _emit();
      try {
        do {
          final sent = ledger.pending.values
              .take(250)
              .map((v) => Map<String, dynamic>.from(v as Map))
              .toList();
          final data =
              (await dio.post<Map<String, dynamic>>(
                    '/sync',
                    data: {'operations': sent},
                    options: Options(
                      headers: {'Authorization': 'Bearer $token'},
                    ),
                  )).data!['data']
                  as Map<String, dynamic>;
          if (_disposed ||
              maintenance ||
              _owner != owner ||
              quran.account.token != token) {
            return;
          }
          ledger.accept(data, sent);
          if (sent.isNotEmpty && (data['acknowledged'] as List).isEmpty) {
            throw const FormatException('Sync made no progress');
          }
          final guestKey = 'religious.merge.$owner';
          final guest = quran.preferences!.getString(guestKey);
          if (guest != null) {
            ledger.mergeGuest(jsonDecode(guest) as Map<String, dynamic>);
            await quran.preferences!.remove(guestKey);
          }
          favorites.clear();
          customAdhkar.clear();
          listeningQueue.clear();
          progress.clear();
          for (final e in ledger.visible.entries) {
            if (e.key.startsWith('favorite:')) {
              favorites.add(e.key.substring(9));
            }
            if (e.key.startsWith('adhkar:')) {
              customAdhkar.add(e.key.substring(7));
            }
            if (e.key.startsWith('queue:')) {
              listeningQueue.add(e.key.substring(6));
            }
            if (e.key.startsWith('playback:')) {
              progress[e.key.substring(9)] = Map<String, dynamic>.from(
                e.value as Map,
              );
            }
          }
          await _persist();
        } while (ledger.pending.isNotEmpty && !_disposed && _owner == owner);
      } catch (e) {
        if (_owner == owner) {
          syncError = 'المحفوظات على الجهاز؛ ستتوفر المزامنة عند اتصال الخدمة';
          if (e is DioException &&
              e.response?.statusCode == 401 &&
              quran.account.token == token) {
            await quran.account.expireSession();
          }
        }
      } finally {
        syncing = false;
        _emit();
      }
    })();
    await _sync;
    _sync = null;
  }

  Future<void> refresh({bool silent = false}) async {
    if (refreshing || _disposed) return;
    refreshing = true;
    updateError = null;
    _emit();
    try {
      final manifest =
          (await dio.get<Map<String, dynamic>>('/manifest')).data!['data']
              as Map;
      if (manifest['version'] == catalog!.sourceVersion) return;
      final bytes = (await dio.get<List<int>>(
        '/dataset',
        options: Options(responseType: ResponseType.bytes),
      )).data!;
      if (sha256.convert(bytes).toString() != manifest['sha256']) {
        throw const FormatException('Catalog checksum mismatch');
      }
      final decoded = utf8.decode(bytes);
      final next = (_bundledCatalog ?? catalog!).extendLegacy(
        jsonDecode(decoded) as Map<String, dynamic>,
      );
      if (next.sourceVersion != manifest['version']) {
        throw const FormatException('Version mismatch');
      }
      if (_disposed) return;
      await quran.preferences!.setString('religious.catalog.v1', decoded);
      catalog = next;
    } catch (_) {
      if (!silent) {
        updateError = 'تعذّر التحديث؛ المحتوى المحفوظ متاح دون اتصال';
      }
    } finally {
      refreshing = false;
      _emit();
    }
  }

  bool hasAudio(ReligiousItem item, [Set<String>? visited]) {
    final seen = visited ?? <String>{};
    if (!seen.add(item.id)) return false;
    if (item.type == 'playlist') {
      for (final id in item.related) {
        final part = catalog?.byId[id];
        if (part != null && hasAudio(part, seen)) return true;
      }
      return false;
    }
    return item.audioUrl?.trim().isNotEmpty == true ||
        item.verseKeys.any(
          (key) => quran.repository?.byKey.containsKey(key) == true,
        );
  }

  List<QuranAudioTrack> tracks(ReligiousItem item) {
    if (item.type == 'playlist') {
      return [
        for (final id in item.related)
          if (catalog!.byId[id] case final part?) ...tracks(part),
      ];
    }
    if (item.audioUrl != null) {
      return [
        QuranAudioTrack(
          id: 'religious:${item.id}',
          recitation: 'religious',
          reciter: item.reciter,
          title: item.title,
          surah: 0,
          url: item.audioUrl!,
          version: catalog!.version,
          quality: 'المصدر الأصلي',
        ),
      ];
    }
    if (item.verseKeys.isEmpty || media.catalog == null) return [];
    final recitation = media.selection(verse: true);
    return [
      for (final key in item.verseKeys)
        if (quran.repository!.byKey[key] case final verse?)
          _identifiedTrack(
            item,
            recitation.track(quran.repository!, verse.surah, ayah: verse.ayah),
          ),
    ];
  }

  QuranAudioTrack _identifiedTrack(ReligiousItem item, QuranAudioTrack track) =>
      QuranAudioTrack(
        id: 'religious:${item.id}:${track.surah}:${track.ayah}',
        recitation: track.recitation,
        reciter: track.reciter,
        title: track.title,
        surah: track.surah,
        ayah: track.ayah,
        url: track.url,
        version: track.version,
        quality: track.quality,
      );

  String? activeItem;
  Future<void> playExternal(List<QuranAudioTrack> tracks) async {
    _progressTimer?.cancel();
    activeItem = null;
    media.setTimer(null);
    await media.playTracks(tracks);
  }

  Future<void> play(ReligiousItem item, {bool resume = true}) async {
    if (!hasAudio(item)) {
      error = 'التسجيل الصوتي لهذا المحتوى غير متاح حاليًا';
      _emit();
      return;
    }
    try {
      await media.initialize();
      final queue = tracks(item);
      if (queue.isEmpty) {
        error = 'التسجيل الصوتي لهذا المحتوى غير متاح حاليًا';
        _emit();
        return;
      }
      activeItem = item.id;
      error = null;
      final saved = resume ? progress[item.id] : null;
      final index = (saved?['index'] as int? ?? 0).clamp(0, queue.length - 1);
      await media.playTracks(queue, start: index);
      if (saved != null) {
        await media.seek(Duration(seconds: saved['seconds'] as int? ?? 0));
      }
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (maintenance) return;
        final active = catalog?.byId[activeItem];
        final current = media.current;
        if (active == null ||
            current == null ||
            !tracks(active).any((track) => track.id == current.id)) {
          return;
        }
        final next = {
          'seconds': media.position.inSeconds,
          'index': media.handler?.player.currentIndex ?? 0,
        };
        if (mapEquals(progress[active.id], next)) return;
        progress[active.id] = next;
        _changed();
        unawaited(_persist());
      });
    } catch (_) {
      error = 'تعذّر تشغيل الصوت؛ تحقق من الاتصال أو الملف المحمّل';
    }
    _emit();
  }

  Future<void> download(ReligiousItem item) async {
    if (!hasAudio(item)) {
      error = 'لا يوجد تسجيل متاح للتنزيل';
      _emit();
      return;
    }
    try {
      await media.initialize();
      final queue = tracks(item);
      if (queue.isEmpty) {
        error = 'لا يوجد تسجيل متاح للتنزيل';
      } else {
        await media.downloads.enqueueAll(queue);
        error = null;
      }
    } catch (_) {
      error = 'تعذّر بدء التنزيل؛ أعد المحاولة';
    }
    _emit();
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();
    _progressTimer?.cancel();
    _retryTimer?.cancel();
    if (_listening) quran.account.removeListener(_accountChanged);
    _media?.dispose();
    if (_activity != null) {
      unawaited(
        _activity!.then<void>(
          (value) => value.dispose(),
          onError: (Object _) {},
        ),
      );
    }
    dio.close();
    super.dispose();
  }
}
