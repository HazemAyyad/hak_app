import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/features/community/data/community_controller.dart';
import 'package:haq_app/features/community/presentation/community_media.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/data/quran_sync.dart';

Map<String, dynamic> circleFixture({int id = 1, int total = 0}) => {
  'id': id,
  'title': 'حلقة اختبار',
  'goal': 100,
  'total': total,
  'mine': total,
  'participants': 1,
  'joined': true,
  'content': {'id': 'fixture', 'text': 'نص اختبار', 'source': 'مصدر الاختبار'},
};
Map<String, dynamic> prayerFixture({int id = 1, int? parent}) => {
  'id': id,
  'account_id': 1,
  'author': 'readerone',
  'parent_id': parent,
  'body': 'مشاركة شخصية للاختبار',
  'status': 'approved',
  'mine': true,
  'liked': false,
  'likes': 0,
  'comments': 0,
};
Map<String, dynamic> publicationFixture({
  int id = 1,
  String kind = 'dua',
  String channel = 'message',
}) => {
  'id': id,
  'title': 'رسالة اختبار',
  'channel': channel,
  'kind': kind,
  'body': null,
  'content': {
    'id': 'fixture',
    'text': 'محتوى اختبار',
    'source': 'مصدر الاختبار',
  },
  'media_url': null,
  'youtube_id': null,
  'link': null,
  'published_at': '2026-10-26T08:00:00Z',
};

class CommunityCloud implements HttpClientAdapter {
  bool enabled = true,
      loseCount = false,
      loseEntry = false,
      unauthorized = false;
  int total = 0, nextEntry = 1;
  final counts = <String>{}, entries = <String, Map<String, dynamic>>{};
  final requests = <RequestOptions>[];
  final circles = [circleFixture()];
  final posts = [prayerFixture()];
  final publications = [publicationFixture()];
  Completer<void>? gate;
  Completer<void>? publicationGate;
  SharedPreferences? preferences;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path;
    Map<String, dynamic> data;
    var status = 200;
    if (path.endsWith('/capabilities')) {
      data = {'enabled': enabled, 'schema': 1};
    } else if (unauthorized) {
      status = 401;
      data = {};
    } else if (path.endsWith('/counts')) {
      final input = options.data as Map, id = input['operation_id'] as String;
      if (preferences != null) {
        expect(
          preferences!.getString('community.pending.v1.account.1'),
          contains(id),
        );
      }
      if (counts.add(id)) total += input['amount'] as int;
      if (loseCount) {
        loseCount = false;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      data = circleFixture(total: total);
    } else if (path == '/entries' && options.method == 'POST') {
      final input = Map<String, dynamic>.from(options.data as Map),
          id = input['operation_id'] as String;
      data = entries.putIfAbsent(
        id,
        () => {
          ...prayerFixture(id: nextEntry++),
          'body': input['body'],
          'status': 'pending',
        },
      );
      if (loseEntry) {
        loseEntry = false;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
    } else if (path == '/circles') {
      data = {'items': circles, 'next_cursor': null};
      if (gate != null) await gate!.future;
    } else if (path == '/entries') {
      data = {'items': posts, 'next_cursor': null};
    } else if (path == '/publications' || path == '/publications/query') {
      data = {
        'items': publications
            .where(
              (e) =>
                  options.queryParameters['kind'] == null ||
                  e['kind'] == options.queryParameters['kind'],
            )
            .where(
              (e) =>
                  path != '/publications/query' ||
                  ((options.data as Map)['ids'] as List).contains(e['id']),
            )
            .toList(),
        'next_cursor': null,
      };
      if (options.queryParameters['kind'] == 'dua' && publicationGate != null) {
        await publicationGate!.future;
      }
    } else if (path == '/blocks') {
      data = {'items': [], 'next_cursor': null};
    } else if (path.startsWith('/circles/')) {
      data = circleFixture(total: total);
    } else if (path == '/quran/sync') {
      data = {'entities': {}, 'acknowledged': [], 'conflicts': []};
    } else {
      data = {};
    }
    return ResponseBody.fromString(
      jsonEncode({'data': data}),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranController quran;
  late CommunityController c;
  late CommunityCloud cloud;
  late SharedPreferences prefs;
  CommunityController open() => CommunityController(
    quran,
    dio: Dio(
      BaseOptions(baseUrl: 'https://backend.test/api/v1/religious/community'),
    )..httpClientAdapter = cloud,
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    cloud = CommunityCloud()..preferences = prefs;
    quran = QuranController(
      preferences: prefs,
      initialRepository: QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
      accountFactory: (q) => QuranAccount(
        q,
        dio: Dio(BaseOptions(baseUrl: 'https://backend.test'))
          ..httpClientAdapter = cloud,
      ),
    );
    await quran.load();
    quran.account.profile = {
      'id': 1,
      'name': 'One',
      'email': 'one@example.test',
    };
    quran.account.token = 'token-1';
    c = open();
  });
  tearDown(() async {
    await c.flush();
    c.dispose();
    quran.dispose();
  });
  test(
    'disabled capability has no fabricated entries and makes no protected list request',
    () async {
      cloud.enabled = false;
      await c.load(CommunitySection.circles);
      expect(c.enabled, false);
      expect(c.items, isEmpty);
      expect(cloud.requests.where((r) => r.path == '/circles'), isEmpty);
    },
  );
  test(
    'lost count response is durable before HTTP and retry after reopen never doubles aggregate',
    () async {
      cloud.loseCount = true;
      expect(await c.count(1), isNull);
      expect(cloud.total, 1);
      expect(c.pending.length, 1);
      final operation = c.pending.values.single['operation_id'];
      c.dispose();
      c = open();
      final result = await c.count(1);
      expect(result!['total'], 1);
      expect(cloud.total, 1);
      expect(c.pending, isEmpty);
      expect(
        (cloud.requests.where((r) => r.path.endsWith('/counts')).last.data
            as Map)['operation_id'],
        operation,
      );
    },
  );
  test(
    'lost post response retains one immutable draft and pending approval after retry',
    () async {
      cloud.loseEntry = true;
      expect(await c.publish('دعاء شخصي'), isNull);
      expect(await c.publish('نص مختلف'), isNull);
      expect(cloud.entries.length, 1);
      final result = await c.publish('دعاء شخصي');
      expect(result!['status'], 'pending');
      expect(c.pending, isEmpty);
      expect(cloud.entries.length, 1);
    },
  );
  test(
    'late old-account page never mutates the newly selected scope',
    () async {
      cloud.gate = Completer<void>();
      final request = c.load(CommunitySection.circles);
      for (
        var i = 0;
        i < 30 && !cloud.requests.any((r) => r.path == '/circles');
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      quran.account.profile = {
        'id': 2,
        'name': 'Two',
        'email': 'two@example.test',
      };
      quran.account.token = 'token-2';
      await quran.account.capabilities();
      cloud.gate!.complete();
      await request;
      expect(c.scope, 'account.2');
      expect(c.items, isEmpty);
      expect(c.loading, false);
      expect(prefs.getString('community.local.v1.account.2'), isNull);
    },
  );
  test(
    'local saved hidden read and sound state persist per account without altering server publications',
    () async {
      await c.load(CommunitySection.messages);
      expect(c.unread(c.items.single), true);
      await c.markRead();
      expect(c.unread(c.items.single), false);
      await c.toggleSave(1);
      await c.setSound(true);
      c.dispose();
      c = open();
      expect(c.saved, {1});
      expect(c.readThrough, 1);
      expect(c.messageSound, true);
      await c.load(CommunitySection.messages);
      await c.hideAll();
      expect(c.visible(c.items.single), false);
      expect(cloud.publications.length, 1);
      quran.account.profile = {'id': 2};
      quran.account.token = 'token-2';
      await quran.account.capabilities();
      expect(c.saved, isEmpty);
      expect(c.hiddenThrough, 0);
      expect(c.readThrough, 0);
      expect(c.messageSound, false);
    },
  );
  test('filters use real API query and pagination deduplicates IDs', () async {
    cloud.publications.add(publicationFixture(id: 2, kind: 'video'));
    await c.load(CommunitySection.messages, filter: 'video');
    expect(c.items.single['id'], 2);
    expect(cloud.requests.last.queryParameters['kind'], 'video');
    await c.load(CommunitySection.messages, more: true, filter: 'video');
    expect(c.items.length, 1);
  });
  test(
    'saved filter queries all saved IDs on server rather than one loaded page',
    () async {
      cloud.publications.add(publicationFixture(id: 88));
      await c.toggleSave(88);
      await c.load(CommunitySection.messages, savedOnly: true);
      expect(c.items.single['id'], 88);
      expect(cloud.requests.last.path, '/publications/query');
      expect(cloud.requests.last.data, {
        'ids': [88],
      });
    },
  );
  test(
    'late previous filter never replaces the selected publication page',
    () async {
      cloud.publications.add(publicationFixture(id: 2, kind: 'video'));
      cloud.publicationGate = Completer<void>();
      final previous = c.load(CommunitySection.messages, filter: 'dua');
      for (
        var i = 0;
        i < 50 &&
            !cloud.requests.any((r) => r.queryParameters['kind'] == 'dua');
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await c.load(CommunitySection.messages, filter: 'video');
      expect(c.items.single['id'], 2);
      cloud.publicationGate!.complete();
      await previous;
      expect(c.items.single['id'], 2);
    },
  );
  test(
    'failure to persist before sending prevents HTTP and retains operation ID',
    () async {
      c.dispose();
      var writable = false;
      c = CommunityController(
        quran,
        dio: Dio(BaseOptions(baseUrl: 'https://backend.test'))
          ..httpClientAdapter = cloud,
        writePreference: (key, value) async =>
            writable ? prefs.setString(key, value) : false,
      );
      expect(await c.count(1), isNull);
      expect(cloud.counts, isEmpty);
      final operation = c.pending.values.single['operation_id'];
      writable = true;
      expect((await c.count(1))!['total'], 1);
      expect(cloud.counts, {operation});
    },
  );
  test(
    'failure clearing a confirmed receipt retries the same operation without double count',
    () async {
      c.dispose();
      var writes = 0;
      c = CommunityController(
        quran,
        dio: Dio(BaseOptions(baseUrl: 'https://backend.test'))
          ..httpClientAdapter = cloud,
        writePreference: (key, value) async =>
            ++writes == 2 ? false : prefs.setString(key, value),
      );
      expect(await c.count(1), isNull);
      final operation = c.pending.values.single['operation_id'];
      expect(cloud.total, 1);
      expect((await c.count(1))!['total'], 1);
      expect(cloud.counts, {operation});
      expect(c.pending, isEmpty);
    },
  );
  test(
    'HTTP401 expires credential but keeps private account and pending operation',
    () async {
      cloud.unauthorized = true;
      expect(await c.count(1), isNull);
      expect(quran.account.sessionExpired, true);
      expect(quran.account.profile!['id'], 1);
      expect(c.scope, 'account.1');
      expect(c.pending.length, 1);
    },
  );
  test(
    'native message notice is gated by explicit reminder settings and forwards no private content',
    () async {
      const channel = MethodChannel('com.haqfoundation.haq_app/reminders');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
      expect(await c.notifyNewMessage(7), false);
      expect(calls, isEmpty);
      await prefs.setString(
        'app.settings.v1.account.1',
        jsonEncode({'enabled': true, 'messages': true}),
      );
      await c.setSound(true);
      expect(await c.notifyNewMessage(7), true);
      expect(calls.single.arguments, {
        'scope': 'account.1',
        'id': 7,
        'sound': true,
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
  test(
    'remote item and link validation reject unsupported data before rendering or launch',
    () {
      expect(
        () => validateCommunityItem(CommunitySection.circles, {
          ...circleFixture(),
          'goal': 0,
        }),
        throwsFormatException,
      );
      expect(
        () => validateCommunityItem(CommunitySection.messages, {
          ...publicationFixture(),
          'link': 'http://unsafe.test',
        }),
        throwsFormatException,
      );
      expect(safeCommunityUrl('https://trusted.test/path'), true);
      for (final value in [
        'http://x.test',
        'javascript:alert(1)',
        'https://user:pass@x.test',
      ]) {
        expect(safeCommunityUrl(value), false);
      }
    },
  );
}
