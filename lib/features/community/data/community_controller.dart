import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../quran/data/haq_api.dart';
import '../../quran/data/quran_controller.dart';
import '../../quran/data/quran_sync.dart';
import '../../settings/data/app_settings.dart';

enum CommunitySection { circles, prayers, messages, stories }

String communityScope(QuranController quran) => quran.account.profile == null
    ? 'guest'
    : 'account.${quran.account.profile!['id']}';

class CommunityPageData {
  CommunityPageData(this.items, this.next);
  final List<Map<String, dynamic>> items;
  final int? next;
  factory CommunityPageData.parse(Map data) {
    final items = List<Map<String, dynamic>>.from(
      (data['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    if (items.length > 50 ||
        items.any((e) => e['id'] is! int || (e['id'] as int) <= 0) ||
        (data['next_cursor'] != null && data['next_cursor'] is! int)) {
      throw const FormatException('Invalid community page');
    }
    return CommunityPageData(items, data['next_cursor'] as int?);
  }
}

/// One scope per controller. Requests capture both owner and token; no response
/// can replace data of a different login. Public counts are server receipts.
class CommunityController extends ChangeNotifier {
  CommunityController(this.quran, {Dio? dio, this.writePreference})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: '$haqApiBase/v1/religious/community',
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
            ),
          ) {
    scope = communityScope(quran);
    _token = quran.account.token;
    _restore();
    quran.account.addListener(_accountChanged);
  }
  final QuranController quran;
  final Dio dio;
  final Future<bool> Function(String key, String value)? writePreference;
  Future<bool> _write(String key, String value) =>
      writePreference?.call(key, value) ?? preferences.setString(key, value);
  SharedPreferences get preferences => quran.preferences!;
  late String scope;
  String? _token, error;
  bool? enabled;
  bool loading = false, working = false, disposed = false;
  int _generation = 0;
  int _loadVersion = 0;
  String? _selection;
  Future<void> _writes = Future.value();
  final items = <Map<String, dynamic>>[];
  int? next;
  final pending = <String, Map<String, dynamic>>{};
  final saved = <int>{}, hidden = <int>{};
  int hiddenThrough = 0, readThrough = 0;
  bool messageSound = false;
  String? localError;
  bool get signedIn =>
      quran.account.profile != null && quran.account.token != null;
  String get _stateKey => 'community.local.v1.$scope';
  String get _pendingKey => 'community.pending.v1.$scope';
  void _restore() {
    localError = null;
    pending.clear();
    saved.clear();
    hidden.clear();
    hiddenThrough = readThrough = 0;
    messageSound = false;
    try {
      final state = jsonDecode(preferences.getString(_stateKey) ?? '{}') as Map;
      saved.addAll(List<int>.from(state['saved'] as List? ?? []));
      hidden.addAll(List<int>.from(state['hidden'] as List? ?? []));
      hiddenThrough = state['hiddenThrough'] as int? ?? 0;
      readThrough = state['readThrough'] as int? ?? 0;
      messageSound = state['sound'] as bool? ?? false;
      final queued =
          jsonDecode(preferences.getString(_pendingKey) ?? '{}') as Map;
      for (final e in queued.entries) {
        final value = Map<String, dynamic>.from(e.value as Map);
        if (value['operation_id'] is! String ||
            !{'count', 'entry'}.contains(value['kind'])) {
          throw const FormatException('Pending');
        }
        pending[e.key as String] = value;
      }
    } catch (_) {
      localError =
          'تعذّر قراءة بيانات المجتمع المحلية؛ أعد المحاولة دون حذف البيانات.';
    }
  }

  void _accountChanged() {
    final owner = communityScope(quran), token = quran.account.token;
    if (owner == scope && token == _token) return;
    scope = owner;
    _token = token;
    ++_generation;
    items.clear();
    next = null;
    loading = working = false;
    error = null;
    enabled = null;
    _restore();
    _emit();
  }

  void _emit() {
    if (!disposed) notifyListeners();
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
    bool private = true,
  }) async {
    final generation = _generation, owner = scope, token = _token;
    if (private && !signedIn) throw StateError('سجّل الدخول للمشاركة');
    try {
      final response = await dio.request<Map<String, dynamic>>(
        path,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {if (private) 'Authorization': 'Bearer $token'},
        ),
      );
      if (disposed ||
          generation != _generation ||
          owner != scope ||
          token != _token) {
        throw StateError('تغير الحساب؛ أعد فتح القسم');
      }
      return Map<String, dynamic>.from(response.data!['data'] as Map);
    } on DioException catch (e) {
      if (!disposed &&
          generation == _generation &&
          private &&
          e.response?.statusCode == 401) {
        await quran.account.expireSession();
      }
      rethrow;
    }
  }

  String message(Object e) {
    if (e is StateError) return e.message.toString();
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 401) return 'انتهت الجلسة؛ جدّد تسجيل الدخول';
      if (code == 403) {
        return 'المشاركة غير متاحة لهذا الحساب أو تحتاج الانضمام أولًا';
      }
      if (code == 409) {
        return 'تغيّر هدف الحلقة أو تعارضت العملية. حدّث البيانات قبل المحاولة';
      }
      if (code == 404 || code == 503) {
        return 'خدمات المجتمع غير متاحة على الخادم حاليًا';
      }
      if (code == 429) return 'وصلت للحد المؤقت للطلبات؛ انتظر قليلًا ثم حاول';
      if (code == 422) {
        final errors = e.response?.data is Map
            ? e.response?.data['errors'] as Map?
            : null;
        if (errors != null && errors.isNotEmpty) {
          return (errors.values.first as List).first.toString();
        }
      }
    }
    return 'تعذّر الاتصال. لم نعرض نجاحًا أو عددًا جماعيًا قبل تأكيد الخادم.';
  }

  Future<void> load(
    CommunitySection section, {
    bool more = false,
    bool mine = false,
    bool savedOnly = false,
    String? filter,
  }) async {
    if (loading && more) return;
    final selection = '${section.name}:$mine:$savedOnly:$filter';
    if (_selection != selection) {
      items.clear();
      next = null;
      _selection = selection;
    }
    final version = ++_loadVersion;
    final generation = _generation;
    loading = true;
    error = null;
    _emit();
    try {
      final cap = await request('GET', '/capabilities', private: false);
      if (version != _loadVersion) return;
      enabled = cap['enabled'] == true && cap['schema'] == 1;
      if (enabled != true) {
        items.clear();
        next = null;
        return;
      }
      final private =
          section == CommunitySection.circles ||
          section == CommunitySection.prayers;
      if (private && !signedIn) {
        items.clear();
        next = null;
        return;
      }
      final path = switch (section) {
        CommunitySection.circles => '/circles',
        CommunitySection.prayers => '/entries',
        _ => '/publications',
      };
      final page = CommunityPageData.parse(
        await request(
          savedOnly ? 'POST' : 'GET',
          savedOnly ? '/publications/query' : path,
          data: savedOnly ? {'ids': saved.toList()} : null,
          private: private,
          query: {
            'limit': 20,
            if (more && next != null) 'cursor': next,
            if (section == CommunitySection.prayers) 'mine': mine ? 1 : 0,
            if (!private)
              'channel': section == CommunitySection.messages
                  ? 'message'
                  : 'story',
            if (!private && filter != null) 'kind': filter,
          },
        ),
      );
      if (version != _loadVersion) return;
      for (final row in page.items) {
        validateCommunityItem(section, row);
      }
      if (!more) items.clear();
      final ids = items.map((e) => e['id']).toSet();
      items.addAll(page.items.where((e) => ids.add(e['id'])));
      next = page.next;
    } catch (e) {
      if (generation == _generation && version == _loadVersion && !disposed) {
        error = message(e);
      }
    } finally {
      if (generation == _generation && version == _loadVersion && !disposed) {
        loading = false;
        _emit();
      }
    }
  }

  Future<void> _savePending() async {
    if (localError != null) throw StateError(localError!);
    final key = _pendingKey, value = jsonEncode(pending);
    final job = _writes.catchError((Object _) {}).then((_) async {
      if (!await _write(key, value)) {
        throw StateError('تعذّر حفظ العملية قبل إرسالها');
      }
    });
    _writes = job;
    await job;
  }

  Future<Map<String, dynamic>?> _mutation(
    Future<Map<String, dynamic>> Function() action,
  ) async {
    if (working) return null;
    final generation = _generation;
    working = true;
    error = null;
    _emit();
    try {
      return await action();
    } catch (e) {
      if (generation == _generation && !disposed) error = message(e);
      return null;
    } finally {
      if (generation == _generation && !disposed) {
        working = false;
        _emit();
      }
    }
  }

  Future<Map<String, dynamic>?> membership(int id, bool joined) => _mutation(
    () => request('PUT', '/circles/$id/membership', data: {'joined': joined}),
  );
  Future<Map<String, dynamic>?> count(int id, {int amount = 1}) =>
      _mutation(() async {
        final key = 'count:$id', generation = _generation;
        final value = pending[key] ??= {
          'kind': 'count',
          'circle': id,
          'operation_id': operationId(),
          'amount': amount,
        };
        pending[key] = value;
        await _savePending();
        if (generation != _generation) throw StateError('تغير الحساب');
        final result = await request(
          'POST',
          '/circles/$id/counts',
          data: {
            'operation_id': value['operation_id'],
            'amount': value['amount'],
          },
        );
        if (generation != _generation) throw StateError('تغير الحساب');
        pending.remove(key);
        try {
          await _savePending();
        } catch (_) {
          if (generation == _generation) pending[key] = value;
          rethrow;
        }
        return result;
      });
  Future<Map<String, dynamic>?> publish(String body, {int? parent}) =>
      _mutation(() async {
        final key = 'entry:${parent ?? 0}', generation = _generation;
        final old = pending[key];
        if (old != null && old['body'] != body.trim()) {
          throw StateError('توجد مشاركة معلقة. أعد إرسالها أو ألغها أولًا');
        }
        final value =
            old ??
            {
              'kind': 'entry',
              'operation_id': operationId(),
              'body': body.trim(),
              'parent_id': parent,
            };
        pending[key] = value;
        await _savePending();
        if (generation != _generation) throw StateError('تغير الحساب');
        final result = await request(
          'POST',
          '/entries',
          data: {
            'operation_id': value['operation_id'],
            'body': value['body'],
            'parent_id': value['parent_id'],
          },
        );
        pending.remove(key);
        try {
          await _savePending();
        } catch (_) {
          if (generation == _generation) pending[key] = value;
          rethrow;
        }
        return result;
      });
  Future<void> discard(String key) async {
    final generation = _generation, previous = pending.remove(key);
    try {
      await _savePending();
    } catch (_) {
      if (generation == _generation && previous != null) {
        pending[key] = previous;
      }
      rethrow;
    }
    _emit();
  }

  Future<Map<String, dynamic>?> mutate(
    String method,
    String path, {
    Map<String, dynamic>? data,
  }) => _mutation(() => request(method, path, data: data));
  Future<void> _saveState() async {
    if (localError != null) throw StateError(localError!);
    final key = _stateKey,
        snapshot = jsonEncode({
          'saved': saved.toList(),
          'hidden': hidden.toList(),
          'hiddenThrough': hiddenThrough,
          'readThrough': readThrough,
          'sound': messageSound,
        });
    final job = _writes.catchError((Object _) {}).then((_) async {
      if (!await _write(key, snapshot)) {
        throw StateError('تعذّر الحفظ المحلي');
      }
    });
    _writes = job;
    try {
      await job;
    } catch (_) {
      _restore();
      _emit();
      rethrow;
    }
    _emit();
  }

  bool visible(Map row) =>
      !hidden.contains(row['id']) && (row['id'] as int) > hiddenThrough;
  bool unread(Map row) => (row['id'] as int) > readThrough && visible(row);
  Future<void> markRead() async {
    for (final item in items) {
      if ((item['id'] as int) > readThrough) readThrough = item['id'] as int;
    }
    await _saveState();
  }

  Future<void> toggleSave(int id) async {
    if (!saved.remove(id)) saved.add(id);
    await _saveState();
  }

  Future<void> hide(int id) async {
    hidden.add(id);
    saved.remove(id);
    await _saveState();
  }

  Future<void> hideAll() async {
    for (final item in items) {
      if ((item['id'] as int) > hiddenThrough) {
        hiddenThrough = item['id'] as int;
      }
    }
    hidden.clear();
    saved.removeWhere((id) => id <= hiddenThrough);
    await _saveState();
  }

  Future<void> setSound(bool sound) async {
    messageSound = sound;
    await _saveState();
  }

  Future<void> flush() => _writes;
  Future<bool> notifyNewMessage(int id) async {
    if (!signedIn && scope != 'guest') return false;
    final settings = AppSettings(preferences, scope);
    final permitted = settings.flag('enabled') && settings.flag('messages');
    settings.dispose();
    if (!permitted) return false;
    try {
      return await const MethodChannel(
            'com.haqfoundation.haq_app/reminders',
          ).invokeMethod<bool>('communityMessage', {
            'scope': scope,
            'id': id,
            'sound': messageSound,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  void dispose() {
    disposed = true;
    quran.account.removeListener(_accountChanged);
    dio.close(force: true);
    super.dispose();
  }
}

void validateCommunityItem(CommunitySection section, Map<String, dynamic> row) {
  bool integer(String key) => row[key] is int && (row[key] as int) >= 0;
  bool text(String key) =>
      row[key] is String && (row[key] as String).length <= 20000;
  bool content(Object? value) =>
      value is Map && value['text'] is String && value['source'] is String;
  final valid = switch (section) {
    CommunitySection.circles =>
      text('title') &&
          integer('goal') &&
          (row['goal'] as int) > 0 &&
          integer('total') &&
          integer('mine') &&
          integer('participants') &&
          row['joined'] is bool &&
          content(row['content']),
    CommunitySection.prayers =>
      text('body') &&
          text('author') &&
          integer('account_id') &&
          integer('likes') &&
          integer('comments') &&
          row['mine'] is bool &&
          row['liked'] is bool &&
          [
            'pending',
            'approved',
            'rejected',
            'deleted',
          ].contains(row['status']),
    _ =>
      text('title') &&
          [
            'quran',
            'hadith',
            'dua',
            'dhikr',
            'tasbih',
            'video',
            'link',
          ].contains(row['kind']) &&
          ['message', 'story'].contains(row['channel']) &&
          (row['body'] == null || text('body')) &&
          (row['content'] == null || content(row['content'])) &&
          (row['youtube_id'] == null ||
              row['youtube_id'] is String &&
                  RegExp(
                    r'^[A-Za-z0-9_-]{11}$',
                  ).hasMatch(row['youtube_id'] as String)) &&
          ['media_url', 'link'].every((key) {
            if (row[key] == null) return true;
            final uri = Uri.tryParse(row[key].toString());
            return uri != null &&
                uri.scheme == 'https' &&
                uri.host.isNotEmpty &&
                uri.userInfo.isEmpty;
          }),
  };
  if (!valid) throw const FormatException('Invalid community record');
}
