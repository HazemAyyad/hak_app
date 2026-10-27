import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/community/data/public_push.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PushDeviceFake implements PublicPushDevice {
  bool mobile = true, allowed = true, failUnsubscribe = false;
  final calls = <String>[];
  final events = StreamController<Map<String, dynamic>>.broadcast();
  Completer<void>? subscription;
  Map<String, dynamic>? initial;
  @override
  bool get supported => mobile;
  @override
  Future<void> initialize() async {
    calls.add('initialize');
  }

  @override
  Future<bool> permission({required bool request}) async {
    calls.add('permission:$request');
    return allowed;
  }

  @override
  Future<void> subscribe() async {
    calls.add('subscribe');
    await subscription?.future;
  }

  @override
  Future<void> unsubscribe() async {
    calls.add('unsubscribe');
    if (failUnsubscribe) throw StateError('offline');
  }

  @override
  Future<Map<String, dynamic>?> initialOpen() async => initial;
  @override
  Stream<Map<String, dynamic>> get opened => events.stream;
  @override
  Future<void> dispose() async {
    await events.close();
  }
}

Map<String, dynamic> publicNotice(String id) => {
  'kind': 'haq.publication.v1',
  'route': 'messages',
  'publication_id': id,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late PushDeviceFake device;
  late PublicPushController c;
  late Dio dio;
  var serverEnabled = true, offline = false, opens = 0;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    device = PushDeviceFake();
    serverEnabled = true;
    offline = false;
    opens = 0;
    dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          if (offline) {
            h.reject(DioException(requestOptions: o));
            return;
          }
          h.resolve(
            Response(
              requestOptions: o,
              statusCode: 200,
              data: {
                'data': {'push': serverEnabled},
              },
            ),
          );
        },
      ),
    );
    c = PublicPushController(
      prefs,
      device: device,
      dio: dio,
      configured: true,
      onOpen: () => opens++,
    );
  });
  tearDown(() {
    c.dispose();
  });
  test(
    'a fresh installation never initializes Firebase or requests permission',
    () async {
      await c.initialize();
      expect(device.calls, isEmpty);
      expect(c.wanted, false);
      expect(c.active, false);
    },
  );
  test('missing activation is explicit and never calls a native SDK', () async {
    final disabled = PublicPushController(
      prefs,
      device: device,
      dio: dio,
      configured: false,
    );
    expect(await disabled.setEnabled(true), false);
    expect(disabled.error, contains('تهيئة'));
    expect(device.calls, isEmpty);
    disabled.dispose();
  });
  test(
    'permission denial cannot become an active subscription and explicit retry can succeed',
    () async {
      device.allowed = false;
      expect(await c.setEnabled(true), false);
      expect(c.active, false);
      expect(device.calls, contains('permission:true'));
      expect(device.calls, isNot(contains('subscribe')));
      device.allowed = true;
      expect(await c.setEnabled(true), true);
      expect(c.active, true);
      expect(prefs.getBool('community.push.enabled.v1'), true);
    },
  );
  test('server capability gates subscription even with permission', () async {
    serverEnabled = false;
    expect(await c.setEnabled(true), false);
    expect(c.active, false);
    expect(device.calls, isNot(contains('subscribe')));
    expect(c.error, isNotNull);
  });
  test(
    'failed unsubscribe reports failure and retries the saved off preference',
    () async {
      await c.setEnabled(true);
      device.failUnsubscribe = true;
      expect(await c.setEnabled(false), false);
      expect(c.wanted, false);
      expect(c.active, true);
      expect(c.error, contains('إلغاء الاشتراك'));
      expect(prefs.getBool('community.push.enabled.v1'), false);
      device.failUnsubscribe = false;
      expect(await c.setEnabled(false), true);
      expect(c.active, false);
    },
  );
  test(
    'off queued during a slow subscription runs last and removes registration',
    () async {
      device.subscription = Completer<void>();
      final on = c.setEnabled(true);
      for (var i = 0; i < 20 && !device.calls.contains('subscribe'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      final off = c.setEnabled(false);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      device.subscription!.complete();
      await Future.wait([on, off]);
      expect(c.active, false);
      expect(c.wanted, false);
      expect(device.calls.last, 'unsubscribe');
    },
  );
  test(
    'only a valid publication can open and duplicates survive controller restart',
    () async {
      await c.setEnabled(true);
      await c.open({...publicNotice('3'), 'route': 'https://example.test'});
      await c.open(publicNotice('-1'));
      await c.open({...publicNotice('3'), 'kind': 'private'});
      expect(opens, 0);
      await c.open(publicNotice('3'));
      await c.open(publicNotice('3'));
      expect(opens, 1);
      final otherDevice = PushDeviceFake();
      final restored = PublicPushController(
        prefs,
        device: otherDevice,
        dio: dio,
        configured: true,
        onOpen: () => opens++,
      );
      await restored.initialize();
      expect(otherDevice.calls, contains('permission:false'));
      await restored.open(publicNotice('3'));
      expect(opens, 1);
      restored.dispose();
      await c.setEnabled(false);
      await c.open(publicNotice('4'));
      expect(opens, 1);
    },
  );
  test(
    'a terminated notification opens the directory even while the API is offline',
    () async {
      device.initial = publicNotice('20');
      offline = true;
      expect(await c.setEnabled(true), false);
      expect(opens, 1);
      expect(c.error, isNotNull);
      expect(device.calls, isNot(contains('subscribe')));
    },
  );
}
