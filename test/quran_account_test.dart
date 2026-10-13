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
  test(
    'login merges guests once, honors server deletion and isolates logout/other accounts',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final server = <int, Map<String, dynamic>>{
        1: {
          'favorite:2:2': {'deleted': true, 'value': null, 'revision': 2},
          'preferences': {
            'deleted': false,
            'value': {'mode': 'pages', 'paper': 'ivory', 'fontSize': 26},
            'revision': 1,
          },
        },
        2: {},
      };
      var owner = 1, revision = 2;
      final dio = Dio(BaseOptions(baseUrl: 'https://backend.test/api/v1'))
        ..httpClientAdapter = StubHttp((request) {
          Map<String, dynamic> data;
          expect(request.uri.path, startsWith('/api/v1/'));
          if (request.uri.path.endsWith('/login')) {
            owner = (request.data as Map)['email'] == 'one@example.test'
                ? 1
                : 2;
            data = {
              'account': {
                'id': owner,
                'name': 'قارئ $owner',
                'email': 'reader$owner@example.test',
              },
              'token': 'token-$owner',
            };
          } else if (request.uri.path.endsWith('/logout')) {
            data = {'logged_out': true};
          } else {
            expect(request.headers['Authorization'], 'Bearer token-$owner');
            final ops = (request.data as Map)['operations'] as List;
            for (final op in ops) {
              server[owner]![op['key'] as String] = {
                'value': op['value'],
                'deleted': op['deleted'],
                'revision': ++revision,
              };
            }
            data = {
              'revision': revision,
              'entities': server[owner],
              'acknowledged': [for (final op in ops) op['id']],
              'conflicts': [],
            };
          }
          return ResponseBody.fromString(
            jsonEncode({'data': data}),
            200,
            headers: {
              'content-type': ['application/json'],
            },
          );
        });
      final repo = QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final controller = QuranController(
        initialRepository: repo,
        preferences: prefs,
        accountFactory: (c) => QuranAccount(c, dio: dio),
      );
      await controller.load();
      controller.toggleFavorite('2:2');
      controller.toggleFavorite('2:4');
      await controller.persist();
      await controller.account.authenticate(
        register: false,
        email: 'one@example.test',
        password: 'long-password',
      );
      expect(controller.account.error, isNull);
      expect(controller.mode, QuranReadingMode.pages);
      expect(controller.favorites.keys, ['2:4']);
      expect(prefs.getString('quran.state.v1'), contains('2:2'));
      controller.toggleBookmark('2:5');
      await controller.account.sync();
      expect(server[1]!['bookmark:2:5']['deleted'], isFalse);
      await controller.account.logout();
      expect(controller.favorites.keys, ['2:2', '2:4']);
      expect(controller.bookmarks, isEmpty);
      await controller.account.authenticate(
        register: false,
        email: 'two@example.test',
        password: 'long-password',
        mergeGuest: false,
      );
      expect(controller.favorites, isEmpty);
      expect(controller.bookmarks, isEmpty);
      expect(prefs.getString('quran.state.v1.account.1'), contains('2:5'));
      controller.dispose();
    },
  );
}
