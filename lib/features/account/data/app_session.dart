import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../quran/data/haq_api.dart';
import '../../quran/data/quran_sync.dart';

/// Aggregate session. Personal Quran synchronization keeps its original owner/token.
class AppSession extends ChangeNotifier {
  AppSession(this.religious, {Dio? dio, FlutterSecureStorage? storage})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: '$haqApiBase/v2',
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
            ),
          ),
      storage = storage ?? const FlutterSecureStorage();
  static const storageKey = 'haq.app.session.v1';
  final QuranAccount religious;
  final Dio dio;
  final FlutterSecureStorage storage;
  String? _token, _adminToken, _observedReligiousToken;
  Map<String, dynamic>? profile;
  bool verified = false,
      busy = false,
      _disposed = false,
      _listening = false,
      _handlingReligious = false;
  int _generation = 0;
  int sessionRevision = 0;
  DateTime? _adminExpires;
  String? error;
  Future<void> _writes = Future.value();
  Future<void>? _openingAdmin;
  final permissions = <String>{};
  bool get admin =>
      verified &&
      profile?['admin_access'] == true &&
      permissions.contains('admin.enter');
  List<String> get areas => List<String>.from(profile?['areas'] as List? ?? []);
  bool can(String permission) => admin && permissions.contains(permission);

  Future<void> _store(String? value) {
    final next = _writes
        .catchError((Object _) {})
        .then(
          (_) => value == null
              ? storage.delete(key: storageKey)
              : storage.write(key: storageKey, value: value),
        );
    _writes = next;
    return next;
  }

  Future<void> initialize() async {
    if (_listening) return;
    _listening = true;
    religious.addListener(_religiousChanged);
    final generation = _generation;
    try {
      final saved = await storage.read(key: storageKey);
      if (_disposed || generation != _generation) return;
      if (saved != null) {
        final data = jsonDecode(saved) as Map;
        _token = data['token'] as String;
        profile = Map<String, dynamic>.from(data['account'] as Map);
        await refresh();
      }
    } catch (_) {
      /* Offline public/local content remains available. */
    }
    if (_disposed || generation != _generation) return;
    _religiousChanged();
  }

  void _religiousChanged() {
    if (_disposed || _handlingReligious || busy) return;
    final token = religious.token;
    if (token == _observedReligiousToken) return;
    final old = _observedReligiousToken;
    _observedReligiousToken = token;
    if (token == null &&
        old != null &&
        profile?['religious_account_id'] != null) {
      unawaited(logout(includeReligious: false));
    } else if (token != null && profile == null) {
      unawaited(_exchange(token));
    }
  }

  Future<void> _exchange(String religiousToken) async {
    final generation = _generation;
    try {
      final data = await _request(
        'POST',
        '/account/exchange',
        token: religiousToken,
      );
      if (_disposed ||
          generation != _generation ||
          religious.token != religiousToken) {
        return;
      }
      await _accept(data, generation);
    } catch (_) {
      /* Existing v1 accounts keep working against an older server. */
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? token,
    Object? data,
  }) async {
    final response = await dio.request<Map<String, dynamic>>(
      path,
      data: data,
      options: Options(
        method: method,
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      ),
    );
    final result = response.data!['data'];
    return result is List
        ? {'items': result}
        : Map<String, dynamic>.from(result as Map);
  }

  Future<void> _accept(Map<String, dynamic> data, int generation) async {
    final token = data['token'] as String;
    final account = Map<String, dynamic>.from(data['account'] as Map);
    await _store(jsonEncode({'token': token, 'account': account}));
    if (_disposed || generation != _generation) return;
    _token = token;
    profile = account;
    verified = true;
    permissions
      ..clear()
      ..addAll(List<String>.from(account['permissions'] as List? ?? []));
    sessionRevision++;
    _emit();
  }

  Future<bool> login(
    String provider,
    String email,
    String password, {
    bool mergeGuest = false,
  }) async {
    if (busy || profile != null || religious.profile != null) return false;
    busy = true;
    error = null;
    final generation = ++_generation;
    _emit();
    try {
      final data = await _request(
        'POST',
        '/account/login',
        data: {
          'provider': provider,
          'email': email.trim(),
          'password': password,
        },
      );
      if (_disposed || generation != _generation) return false;
      _handlingReligious = true;
      try {
        if (data['religious_session'] case final Map session) {
          await religious.acceptSession(
            Map<String, dynamic>.from(session),
            guest: religious.entities(),
            mergeGuest: mergeGuest,
          );
        }
        _observedReligiousToken = religious.token;
      } finally {
        _handlingReligious = false;
      }
      if (_disposed || generation != _generation) return false;
      await _accept(data, generation);
      return true;
    } catch (_) {
      error = 'account.failed';
      return false;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> refresh() async {
    final token = _token, generation = _generation;
    if (token == null) return;
    try {
      final data = await _request('GET', '/account/session', token: token);
      if (_disposed || token != _token || generation != _generation) return;
      profile = data;
      verified = true;
      permissions
        ..clear()
        ..addAll(List<String>.from(data['permissions'] as List? ?? []));
    } catch (e) {
      if (_disposed || token != _token || generation != _generation) return;
      verified = false;
      permissions.clear();
      _adminToken = null;
      if (e is DioException && [401, 403].contains(e.response?.statusCode)) {
        _token = null;
        error = 'account.expired';
        await _store(null);
      }
    }
    _emit();
  }

  Future<bool> link(
    String provider,
    String email,
    String password,
    String currentPassword, {
    String? currentGoogleToken,
  }) async {
    if (busy || !verified || _token == null || areas.length != 1) return false;
    busy = true;
    error = null;
    final generation = ++_generation;
    final token = _token;
    _emit();
    try {
      final data = await _request(
        'POST',
        '/account/link',
        token: token,
        data: {
          'provider': provider,
          'email': email.trim(),
          'password': password,
          'current_password': currentPassword,
          'current_id_token': ?currentGoogleToken,
        },
      );
      if (_disposed || generation != _generation) return false;
      _handlingReligious = true;
      try {
        if (data['religious_session'] case final Map personal) {
          await religious.acceptSession(
            Map<String, dynamic>.from(personal),
            guest: religious.entities(),
            mergeGuest: false,
          );
        }
        _observedReligiousToken = religious.token;
      } finally {
        _handlingReligious = false;
      }
      _adminToken = null;
      await _accept(data, generation);
      return true;
    } catch (_) {
      error = 'account.failed';
      return false;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<Map<String, dynamic>> adminRequest(
    String method,
    String path, {
    Object? data,
  }) async {
    if (!admin || _token == null) {
      throw StateError('No verified administration session');
    }
    final generation = _generation, token = _token;
    try {
      if (_adminToken == null ||
          _adminExpires == null ||
          DateTime.now()
              .add(const Duration(seconds: 10))
              .isAfter(_adminExpires!)) {
        await (_openingAdmin ??= (() async {
          final session = await _request(
            'POST',
            '/admin/session',
            token: token,
          );
          if (_disposed || generation != _generation || token != _token) {
            throw StateError('Session changed');
          }
          _adminToken = session['token'] as String;
          _adminExpires = DateTime.parse(session['expires_at'] as String);
          permissions
            ..clear()
            ..addAll(List<String>.from(session['permissions'] as List));
        })().whenComplete(() => _openingAdmin = null));
      }
      final result = await _request(
        method,
        '/admin/$path',
        token: _adminToken,
        data: data,
      );
      if (_disposed || generation != _generation || token != _token) {
        throw StateError('Session changed');
      }
      return result;
    } on DioException catch (e) {
      if ([401, 403].contains(e.response?.statusCode) &&
          generation == _generation) {
        _adminToken = null;
        verified = false;
        permissions.clear();
        error = 'admin.denied';
        _emit();
      }
      rethrow;
    }
  }

  Future<void> logout({bool includeReligious = true}) async {
    if (busy || (includeReligious && religious.busy)) return;
    busy = true;
    final token = _token;
    ++_generation;
    _token = null;
    _adminToken = null;
    _adminExpires = null;
    profile = null;
    permissions.clear();
    verified = false;
    _observedReligiousToken = null;
    _handlingReligious = true;
    _emit();
    try {
      await _store(null);
      if (token != null) {
        try {
          await _request('POST', '/account/logout', token: token);
        } catch (_) {
          /* Local logout works offline. */
        }
      }
      if (includeReligious) await religious.logout();
    } finally {
      busy = false;
      _handlingReligious = false;
      _emit();
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    if (_listening) religious.removeListener(_religiousChanged);
    dio.close(force: true);
    super.dispose();
  }
}
