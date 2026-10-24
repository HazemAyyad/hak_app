import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'haq_api.dart';
import 'quran_controller.dart';

String operationId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// One ledger per account. Deleted server entries remain visible as tombstones.
class QuranSyncLedger {
  QuranSyncLedger({Map<String, dynamic>? stored}) {
    server.addAll(Map<String, dynamic>.from(stored?['server'] as Map? ?? {}));
    pending.addAll(Map<String, dynamic>.from(stored?['pending'] as Map? ?? {}));
  }
  final server = <String, dynamic>{};
  final pending = <String, dynamic>{};
  Map<String, dynamic> get visible {
    final entries = <String, dynamic>{...server};
    for (final op in pending.values) {
      entries[op['key'] as String] = op;
    }
    return {
      for (final item in entries.entries)
        if (item.value['deleted'] != true) item.key: item.value['value'],
    };
  }

  Map<String, dynamic> toJson() => {'server': server, 'pending': pending};
  void change(String key, dynamic value, {bool deleted = false}) {
    pending[key] = {
      'id': operationId(),
      'key': key,
      'base_revision': server[key]?['revision'] ?? 0,
      'deleted': deleted,
      'value': deleted ? null : value,
    };
  }

  void record(Map<String, dynamic> values) {
    final before = visible;
    for (final key in {...before.keys, ...values.keys}) {
      if (jsonEncode(before[key]) != jsonEncode(values[key])) {
        change(key, values[key], deleted: !values.containsKey(key));
      }
    }
  }

  void mergeGuest(Map<String, dynamic> values) {
    for (final item in values.entries) {
      if (!server.containsKey(item.key) && !pending.containsKey(item.key)) {
        change(item.key, item.value);
      }
    }
  }

  void accept(Map<String, dynamic> response, List<Map<String, dynamic>> sent) {
    final acknowledged = Set<String>.from(response['acknowledged'] as List);
    final conflicts = Set<String>.from(response['conflicts'] as List);
    server
      ..clear()
      ..addAll(Map<String, dynamic>.from(response['entities'] as Map));
    for (final op in sent) {
      if (!acknowledged.contains(op['id'])) continue;
      final key = op['key'] as String;
      if (pending[key]?['id'] == op['id']) {
        pending.remove(key);
      } else if (pending.containsKey(key) && !conflicts.contains(key)) {
        // A newer local edit made while this same entity was being uploaded.
        pending[key]['base_revision'] = server[key]?['revision'] ?? 0;
      }
    }
  }
}

class QuranAccount extends ChangeNotifier with WidgetsBindingObserver {
  QuranAccount(this.controller, {Dio? dio, FlutterSecureStorage? storage})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: '$haqApiBase/v1',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
            ),
          ),
      storage = storage ?? const FlutterSecureStorage();
  final QuranController controller;
  final Dio dio;
  final FlutterSecureStorage storage;
  Map<String, dynamic>? profile;
  QuranSyncLedger ledger = QuranSyncLedger();
  String? token, error, lastSync;
  bool busy = false, syncing = false, _applying = false, _disposed = false;
  Timer? _timer, _retry;
  Future<void> _writes = Future.value();
  Future<void>? _sync;
  String get stateKey => profile == null
      ? 'quran.state.v1'
      : 'quran.state.v1.account.${profile!['id']}';
  String get ledgerKey => 'quran.sync.v1.account.${profile!['id']}';
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    _retry = Timer.periodic(const Duration(minutes: 1), (_) {
      if (profile != null && ledger.pending.isNotEmpty) unawaited(sync());
    });
    try {
      token = await storage.read(key: 'quran.account.token');
      if (_disposed) return;
      final cached = controller.preferences!.getString('quran.account.profile');
      if (token != null && cached != null) {
        profile = Map<String, dynamic>.from(jsonDecode(cached) as Map);
        _loadLedger();
        controller.restoreState(
          jsonDecode(controller.preferences!.getString(stateKey) ?? '{}')
              as Map<String, dynamic>,
        );
        unawaited(sync());
      }
    } on MissingPluginException {
      /* Headless tests without a platform vault. */
    } catch (_) {
      error = 'تعذّر استعادة الحساب؛ يمكنك متابعة القراءة دون اتصال';
    }
  }

  void _loadLedger() {
    try {
      ledger = QuranSyncLedger(
        stored:
            jsonDecode(controller.preferences!.getString(ledgerKey) ?? '{}')
                as Map<String, dynamic>,
      );
    } catch (_) {
      ledger = QuranSyncLedger();
    }
  }

  Map<String, dynamic> entities() => {
    for (final e in controller.favorites.entries) 'favorite:${e.key}': e.value,
    for (final e in controller.bookmarks.entries) 'bookmark:${e.key}': e.value,
    for (final id in controller.savedSurahs) 'surah:$id': true,
    for (final id in controller.readJuzs) 'juz:$id': true,
    if (controller.lastKey != null)
      'reading': {
        'lastKey': controller.lastKey,
        'alignment': controller.lastAlignment,
        'page': controller.lastPage ?? controller.lastVerse!.page,
      },
    'preferences': {
      'mode': controller.mode.name,
      'fontSize': controller.fontSize,
      'paper': controller.paper,
    },
  };
  void changed() {
    if (_applying || profile == null || _disposed) return;
    ledger.record(entities());
    unawaited(_saveLedger());
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () => unawaited(sync()));
  }

  Future<void> _saveLedger() {
    final key = ledgerKey, snapshot = jsonEncode(ledger.toJson());
    _writes = _writes.catchError((Object _) {}).then((_) async {
      await controller.preferences!.setString(key, snapshot);
    });
    return _writes;
  }

  Future<void> authenticate({
    required bool register,
    required String email,
    required String password,
    String? name,
    bool mergeGuest = true,
  }) async {
    if (busy || profile != null) return;
    busy = true;
    error = null;
    _emit();
    final guest = entities();
    try {
      final data =
          (await dio.post<Map<String, dynamic>>(
                '/religious/account/${register ? 'register' : 'login'}',
                data: {
                  'email': email.trim(),
                  'password': password,
                  if (register) 'name': name?.trim(),
                },
              )).data!['data']
              as Map<String, dynamic>;
      final newToken = data['token'] as String;
      await storage.write(key: 'quran.account.token', value: newToken);
      await controller.flushReading();
      token = newToken;
      profile = Map<String, dynamic>.from(data['account'] as Map);
      await controller.preferences!.setBool(
        'religious.activity.mergeGuest.${profile!['id']}',
        mergeGuest,
      );
      await controller.preferences!.setString(
        'quran.account.profile',
        jsonEncode(profile),
      );
      _loadLedger();
      _apply();
      // Pull tombstones before the one-time, explicitly selected guest merge.
      final pulled = await sync();
      if (mergeGuest) {
        if (pulled) {
          ledger.mergeGuest(guest);
          await _saveLedger();
          _apply();
          await sync();
        } else {
          await controller.preferences!.setString(
            'quran.guest.merge.${profile!['id']}',
            jsonEncode(guest),
          );
        }
      }
    } catch (e) {
      error = _message(e);
    } finally {
      busy = false;
      _emit();
    }
  }

  String _message(Object e) {
    if (e is DioException) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 503) {
        return 'خدمة الحساب غير متاحة على السيرفر حاليًا؛ يمكنك الاستمرار كضيف';
      }
      if (e.response?.statusCode == 401) {
        return 'انتهت جلسة الحساب؛ سجل الخروج ثم ادخل مجددًا';
      }
      if (e.response?.statusCode == 422) {
        final errors = e.response?.data is Map
            ? e.response?.data['errors'] as Map?
            : null;
        if (errors != null && errors.isNotEmpty) {
          return (errors.values.first as List).first.toString();
        }
      }
    }
    return 'تعذّر الاتصال؛ تغييرات القراءة محفوظة على هذا الجهاز وستُزامن عند عودة الاتصال';
  }

  Future<bool> sync() async {
    if (profile == null || token == null || _disposed) return false;
    if (_sync != null) {
      await _sync;
      return error == null;
    }
    var success = false;
    final ownerId = profile!['id'], sessionToken = token;
    _sync = (() async {
      syncing = true;
      error = null;
      _emit();
      try {
        do {
          final sent = ledger.pending.values
              .take(250)
              .map((v) => Map<String, dynamic>.from(v as Map))
              .toList();
          final response =
              (await dio.post<Map<String, dynamic>>(
                    '/quran/sync',
                    data: {'operations': sent},
                    options: Options(
                      headers: {'Authorization': 'Bearer $token'},
                    ),
                  )).data!['data']
                  as Map<String, dynamic>;
          if (_disposed || profile?['id'] != ownerId || token != sessionToken) {
            return;
          }
          ledger.accept(response, sent);
          final guestKey = 'quran.guest.merge.${profile!['id']}';
          final guest = controller.preferences!.getString(guestKey);
          if (guest != null) {
            ledger.mergeGuest(jsonDecode(guest) as Map<String, dynamic>);
            await controller.preferences!.remove(guestKey);
          }
          await _saveLedger();
          _apply();
          if ((response['conflicts'] as List).isNotEmpty) {
            error =
                'وصل تعديل أحدث من جهاز آخر؛ تم اعتماد النسخة الموجودة على الحساب';
          }
        } while (ledger.pending.isNotEmpty && !_disposed);
        lastSync = DateTime.now().toLocal().toIso8601String();
        success = true;
      } catch (e) {
        error = _message(e);
      } finally {
        syncing = false;
        _emit();
      }
    })();
    await _sync;
    _sync = null;
    return success;
  }

  void _apply() {
    final values = ledger.visible;
    final reading = values['reading'] as Map? ?? {};
    final preferences = values['preferences'] as Map? ?? {};
    _applying = true;
    controller.restoreState({
      ...reading,
      ...preferences,
      'favorites': {
        for (final e in values.entries)
          if (e.key.startsWith('favorite:')) e.key.substring(9): e.value,
      },
      'bookmarks': {
        for (final e in values.entries)
          if (e.key.startsWith('bookmark:')) e.key.substring(9): e.value,
      },
      'savedSurahs': [
        for (final key in values.keys)
          if (key.startsWith('surah:')) int.parse(key.substring(6)),
      ],
      'readJuzs': [
        for (final key in values.keys)
          if (key.startsWith('juz:')) int.parse(key.substring(4)),
      ],
    });
    unawaited(controller.persist());
    controller.refreshReading();
    _applying = false;
  }

  Future<void> logout() async {
    if (busy || profile == null) return;
    busy = true;
    _emit();
    if (_sync != null) await _sync;
    await controller.flushReading();
    try {
      await dio.post(
        '/religious/account/logout',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (_) {
      /* Local logout is available offline too. */
    }
    await storage.delete(key: 'quran.account.token');
    await controller.preferences!.remove('quran.account.profile');
    token = null;
    profile = null;
    ledger = QuranSyncLedger();
    error = null;
    controller.restoreState(
      jsonDecode(controller.preferences!.getString('quran.state.v1') ?? '{}')
          as Map<String, dynamic>,
    );
    controller.refreshReading();
    busy = false;
    _emit();
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _retry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
