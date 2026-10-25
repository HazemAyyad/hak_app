import 'package:dio/dio.dart';

import '../../quran/data/haq_api.dart';
import 'activity_store.dart';

class ActivityAccountSession {
  const ActivityAccountSession(
    this.owner,
    this.token, {
    this.mergeGuest = false,
  });
  final String owner, token;
  final bool mergeGuest;
  String get scope => religiousActivityScope(owner);
}

/// Captures the account and token for every exchange. Late responses from a
/// previous login cannot mutate the newly selected account's local records.
class ReligiousActivitySync {
  ReligiousActivitySync({required this.store, required this.session, Dio? dio})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: '$haqApiBase/v1/religious',
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );
  final ReligiousActivityStore store;
  final ActivityAccountSession? Function() session;
  final Dio dio;
  final _running = <String, Future<bool>>{};
  final errors = <String, String>{};
  final lastSync = <String, DateTime>{};
  bool disposed = false;

  bool _current(ActivityAccountSession captured) {
    final now = session();
    return !disposed &&
        now?.owner == captured.owner &&
        now?.token == captured.token;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
    ActivityAccountSession captured,
  ) async {
    final response = await dio.post<Map<String, dynamic>>(
      path,
      data: payload,
      options: Options(headers: {'Authorization': 'Bearer ${captured.token}'}),
    );
    return Map<String, dynamic>.from(response.data!['data'] as Map);
  }

  Future<bool> sync() async {
    final captured = session();
    if (captured == null || disposed) return false;
    final existing = _running[captured.scope];
    if (existing != null) return existing;
    final job = _exchange(captured);
    _running[captured.scope] = job;
    try {
      return await job;
    } finally {
      _running.remove(captured.scope);
    }
  }

  Future<bool> _exchange(ActivityAccountSession captured) async {
    final scope = captured.scope;
    try {
      final capabilities =
          (await dio.get<Map<String, dynamic>>('/capabilities')).data!['data']
              as Map;
      if (!_current(captured)) return false;
      if (capabilities['schema_version'] != 3 ||
          capabilities['personal_sync'] != true ||
          capabilities['activity_sync'] != true) {
        errors[scope] =
            'بياناتك محفوظة على الجهاز؛ مزامنة الأقسام الجديدة غير مفعّلة على الخدمة بعد';
        return false;
      }
      // Pull first: server tombstones must precede a selected guest import.
      final initial = await _post('/personal/sync', {
        'operations': <Object>[],
      }, captured);
      if (!_current(captured)) return false;
      await store.acceptPersonal(scope, initial, []);
      Future<void> personal() async {
        while (_current(captured)) {
          final sent = await store.pendingPersonal(scope);
          if (sent.isEmpty) return;
          final response = await _post('/personal/sync', {
            'operations': sent,
          }, captured);
          if (!_current(captured)) return;
          await store.acceptPersonal(scope, response, sent);
          if ((response['acknowledged'] as List).isEmpty) {
            throw StateError('Personal sync made no progress');
          }
        }
      }

      Future<void> pullActivity() async {
        while (_current(captured)) {
          final previous = await store.activityCursor(scope);
          final response = await _post('/activity/sync', {
            'events': <Object>[],
            'cursor': previous,
          }, captured);
          if (!_current(captured)) return;
          await store.acceptActivity(scope, response);
          if (response['has_more'] != true) return;
          if ((response['cursor'] as int) <= previous) {
            throw StateError('Activity sync made no progress');
          }
        }
      }

      await personal();
      await pullActivity();
      if (!_current(captured)) return false;
      if (captured.mergeGuest) await store.mergeGuestOnce(scope);
      await personal();
      while (_current(captured)) {
        final pending = await store.events(
          scope,
          pendingOnly: true,
          limit: 250,
        );
        if (pending.isEmpty) break;
        final response = await _post('/activity/sync', {
          'events': pending.map((e) => e.toJson()).toList(),
          'cursor': await store.activityCursor(scope),
        }, captured);
        if (!_current(captured)) return false;
        await store.acceptActivity(scope, response);
        if ((response['acknowledged'] as List).isEmpty) {
          throw StateError('Activity sync made no progress');
        }
        if (response['has_more'] == true) await pullActivity();
      }
      if (!_current(captured)) return false;
      errors.remove(scope);
      lastSync[scope] = DateTime.now();
      return true;
    } catch (_) {
      if (_current(captured)) {
        errors[scope] =
            'التغييرات محفوظة على الجهاز؛ تعذّرت المزامنة وستُعاد المحاولة';
      }
      return false;
    }
  }
}
