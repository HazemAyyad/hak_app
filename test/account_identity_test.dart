import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/data/quran_sync.dart';
import 'quran_media_test.dart' show StubHttp;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranController controller;
  late SharedPreferences prefs;
  var owner = 1, expired = false, failGoogle = false, failDelete = false;
  final requests = <RequestOptions>[];
  final server = <String, dynamic>{};
  setUp(() async {
    owner = 1;
    expired = false;
    failGoogle = false;
    failDelete = false;
    requests.clear();
    server.clear();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final dio = Dio(BaseOptions(baseUrl: 'https://backend.test/api/v1'))
      ..httpClientAdapter = StubHttp((request) {
        requests.add(request);
        Object data;
        var status = 200;
        if (request.path.endsWith('/login') ||
            request.path.endsWith('/google')) {
          if (failGoogle) {
            status = 503;
            data = {'message': 'unavailable'};
          } else {
            data = {
              'data': {
                'account': {
                  'id': owner,
                  'name': 'قارئ',
                  'email': 'reader$owner@example.test',
                  'username': 'reader$owner',
                },
                'token': 'token-$owner',
              },
            };
          }
        } else if (request.path == '/quran/sync') {
          if (expired) {
            status = 401;
            data = {'message': 'Unauthenticated'};
          } else {
            final operations = (request.data as Map)['operations'] as List;
            for (final op in operations) {
              server[op['key'] as String] = {
                'value': op['value'],
                'deleted': op['deleted'],
                'revision': 1,
              };
            }
            data = {
              'data': {
                'entities': server,
                'acknowledged': [for (final op in operations) op['id']],
                'conflicts': [],
                'revision': 0,
              },
            };
          }
        } else if (request.method == 'DELETE') {
          status = failDelete ? 422 : 200;
          data = {
            'data': {'deleted': true},
          };
        } else {
          data = {'data': {}};
        }
        return ResponseBody.fromString(
          jsonEncode(data),
          status,
          headers: {
            'content-type': ['application/json'],
          },
        );
      });
    controller = QuranController(
      initialRepository: QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
      preferences: prefs,
      accountFactory: (c) => QuranAccount(c, dio: dio),
    );
    await controller.load();
  });
  tearDown(() => controller.dispose());
  Future<void> login() => controller.account.authenticate(
    register: false,
    email: 'reader$owner@example.test',
    password: 'test-password',
    mergeGuest: false,
  );
  test(
    'expired token retains private scope and data; same account can authenticate again',
    () async {
      await login();
      controller.toggleFavorite('2:3');
      await controller.flushReading();
      expired = true;
      expect(await controller.account.sync(), false);
      expect(controller.account.sessionExpired, true);
      expect(controller.account.profile!['id'], 1);
      expect(controller.account.token, isNull);
      expect(controller.favorites.keys, ['2:3']);
      expect(
        await const FlutterSecureStorage().read(key: 'quran.account.token'),
        isNull,
      );
      expired = false;
      await login();
      expect(controller.account.sessionExpired, false);
      expect(controller.account.token, 'token-1');
    },
  );
  test(
    'reauthentication cannot replace a retained private scope with another account',
    () async {
      await login();
      await controller.account.expireSession();
      owner = 2;
      await login();
      expect(controller.account.profile!['id'], 1);
      expect(controller.account.token, isNull);
      expect(controller.account.sessionExpired, true);
      expect(
        prefs.getString('quran.account.profile'),
        contains('reader1@example.test'),
      );
    },
  );
  test(
    'failed Google verification creates no local session and does not store an ID token',
    () async {
      failGoogle = true;
      expect(
        await controller.account.google(
          'google-id-token',
          username: 'hazemayad',
        ),
        false,
      );
      expect(controller.account.profile, isNull);
      expect(controller.account.token, isNull);
      expect(
        await const FlutterSecureStorage().read(key: 'quran.account.token'),
        isNull,
      );
      expect(
        jsonEncode({for (final k in prefs.getKeys()) k: prefs.get(k)}),
        isNot(contains('google-id-token')),
      );
    },
  );
  test(
    'deletion failure retains account; successful deletion returns to original guest state',
    () async {
      controller.toggleBookmark('2:5');
      await controller.flushReading();
      await login();
      failDelete = true;
      expect(await controller.account.deleteAccount(password: 'wrong'), false);
      expect(controller.account.profile!['id'], 1);
      failDelete = false;
      expect(
        await controller.account.deleteAccount(password: 'test-password'),
        true,
      );
      expect(controller.account.profile, isNull);
      expect(controller.bookmarks.keys, ['2:5']);
      expect(
        await const FlutterSecureStorage().read(key: 'quran.account.token'),
        isNull,
      );
    },
  );
}
