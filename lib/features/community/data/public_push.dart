import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../quran/data/haq_api.dart';

const publicMessagesTopic = 'haq_public_messages_v1';

abstract class PublicPushDevice {
  bool get supported;
  Future<void> initialize();
  Future<bool> permission({required bool request});
  Future<void> subscribe();
  Future<void> unsubscribe();
  Future<Map<String, dynamic>?> initialOpen();
  Stream<Map<String, dynamic>> get opened;
  Future<void> dispose();
}

class FirebasePublicPushDevice implements PublicPushDevice {
  FirebaseMessaging? _messaging;
  @override
  bool get supported => Platform.isAndroid || Platform.isIOS;
  @override
  Future<void> initialize() async {
    if (!supported) throw UnsupportedError('Public push is mobile only');
    // Native configuration is required for terminated-process delivery. It is
    // deliberately absent until the final service activation step.
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    _messaging = FirebaseMessaging.instance;
    await _messaging!.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
    if (Platform.isAndroid) {
      await const MethodChannel(
        'com.haqfoundation.haq_app/reminders',
      ).invokeMethod<void>('preparePublicPush');
    }
  }

  @override
  Future<bool> permission({required bool request}) async {
    final settings = request
        ? await _messaging!.requestPermission(
            alert: true,
            badge: true,
            sound: false,
          )
        : await _messaging!.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<void> subscribe() async {
    await _messaging!.setAutoInitEnabled(true);
    if (Platform.isIOS && await _messaging!.getAPNSToken() == null) {
      throw StateError('APNs registration pending');
    }
    await _messaging!.subscribeToTopic(publicMessagesTopic);
  }

  @override
  Future<void> unsubscribe() async {
    await _messaging!.unsubscribeFromTopic(publicMessagesTopic);
    await _messaging!.setAutoInitEnabled(false);
  }

  Map<String, dynamic> _data(RemoteMessage message) => {
    ...message.data,
    'message_id': message.messageId,
  };
  @override
  Future<Map<String, dynamic>?> initialOpen() async {
    final message = await _messaging!.getInitialMessage();
    return message == null ? null : _data(message);
  }

  @override
  Stream<Map<String, dynamic>> get opened =>
      FirebaseMessaging.onMessageOpenedApp.map(_data);
  @override
  Future<void> dispose() async {}
}

/// App-wide public-content preference, independent of private account identity.
/// OS notification payloads render while Flutter is absent; no Dart poller is
/// claimed as a background delivery mechanism.
class PublicPushController extends ChangeNotifier {
  PublicPushController(
    this.preferences, {
    PublicPushDevice? device,
    Dio? dio,
    this.onOpen,
    this.configured = const bool.fromEnvironment('HAQ_PUBLIC_PUSH_ENABLED'),
  }) : device = device ?? FirebasePublicPushDevice(),
       dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: '$haqApiBase/v1/religious/community',
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 12),
             ),
           ) {
    wanted = preferences.getBool('community.push.enabled.v1') ?? false;
    _openedIds.addAll(
      preferences.getStringList('community.push.opened.v1') ?? [],
    );
  }
  final SharedPreferences preferences;
  final PublicPushDevice device;
  final Dio dio;
  final bool configured;
  final VoidCallback? onOpen;
  late bool wanted;
  bool active = false,
      busy = false,
      _disposed = false,
      _ready = false,
      _initialChecked = false;
  String? error;
  Future<void> _queue = Future.value();
  StreamSubscription<Map<String, dynamic>>? _opened;
  final _openedIds = <String>[];
  bool get available => configured && device.supported;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (wanted || preferences.getBool('community.push.ever.v1') == true) {
      await reconcile();
    }
  }

  Future<bool> setEnabled(bool value) async {
    try {
      if (value && !await preferences.setBool('community.push.ever.v1', true)) {
        throw StateError('storage');
      }
      if (!await preferences.setBool('community.push.enabled.v1', value)) {
        throw StateError('storage');
      }
      wanted = value;
    } catch (_) {
      error = 'تعذّر حفظ اختيار الإشعارات على الجهاز. أعد المحاولة.';
      _emit();
      return false;
    }
    _emit();
    await reconcile(requestPermission: value);
    return error == null && (value ? active : !active);
  }

  Future<void> reconcile({bool requestPermission = false}) {
    final job = _queue.then((_) async {
      if (_disposed) return;
      busy = true;
      error = null;
      _emit();
      try {
        if (!available) {
          active = false;
          if (wanted) {
            error = 'إشعارات الخلفية بانتظار تهيئة الخدمة على هذا الإصدار.';
          }
          return;
        }
        if (_disposed) return;
        if (!_ready) {
          await device.initialize();
          if (_disposed) return;
          _ready = true;
          _opened = device.opened.listen(
            (data) => unawaited(open(data)),
            onError: (_) {
              error = 'تعذّر قراءة فتح الإشعار. افتح رسائل حق من التطبيق.';
              _emit();
            },
          );
        }
        if (!wanted) {
          await device.unsubscribe();
          active = false;
          return;
        }
        if (!_initialChecked) {
          final initial = await device.initialOpen();
          _initialChecked = true;
          if (initial != null) await open(initial);
        }
        final response = await dio.get<Map<String, dynamic>>('/capabilities');
        if (response.data?['data'] is! Map ||
            response.data!['data']['push'] != true) {
          throw StateError('server_disabled');
        }
        if (!await device.permission(request: requestPermission)) {
          active = false;
          error =
              'إذن الإشعارات غير متاح. اسمح به من إعدادات الجهاز ثم أعد المحاولة.';
          return;
        }
        if (_disposed || !wanted) return;
        await device.subscribe();
        if (_disposed) return;
        active = true;
      } catch (_) {
        // A failed unsubscribe must not be represented as a confirmed disable.
        error = wanted
            ? 'تعذّر تفعيل إشعارات الخلفية. تحقق من إذن الجهاز والاتصال وتهيئة الخدمة ثم أعد المحاولة.'
            : 'حُفظ طلب الإيقاف، لكن تعذّر تأكيد إلغاء الاشتراك. أعد المحاولة عند الاتصال.';
      } finally {
        busy = false;
        _emit();
      }
    });
    _queue = job;
    return job;
  }

  Future<void> open(Map<String, dynamic> data) async {
    if (_disposed ||
        !wanted ||
        !available ||
        data['kind'] != 'haq.publication.v1' ||
        data['route'] != 'messages') {
      return;
    }
    final id = data['publication_id'];
    if (id is! String || !RegExp(r'^[1-9][0-9]{0,11}$').hasMatch(id)) return;
    final key = 'publication.$id';
    if (_openedIds.contains(key)) return;
    _openedIds.add(key);
    if (_openedIds.length > 32) _openedIds.removeAt(0);
    try {
      if (!await preferences.setStringList(
        'community.push.opened.v1',
        _openedIds,
      )) {
        throw StateError('storage');
      }
    } catch (_) {
      _openedIds.remove(key);
      error = 'تعذّر حفظ فتح الإشعار. افتح رسائل حق من التطبيق.';
      _emit();
      return;
    }
    if (!_disposed && wanted) onOpen?.call();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_opened?.cancel());
    unawaited(device.dispose());
    super.dispose();
  }
}
