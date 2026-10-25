import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/quran/data/quran_sync.dart';
import 'package:haq_app/features/religious_activity/data/activity_models.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'package:haq_app/features/religious_activity/data/activity_sync.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ModuleCloud implements HttpClientAdapter {
  bool enabled = true, loseNextEventResponse = false;
  int schemaVersion = 3;
  Completer<void>? gate;
  final requests = <RequestOptions>[];
  final entities = <String, dynamic>{};
  final history = <Map<String, dynamic>>[];
  final receipts = <String>{};
  int revision = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final data = options.data as Map? ?? {};
    Map<String, dynamic> body;
    if (options.path == '/capabilities') {
      body = {
        'schema_version': schemaVersion,
        'personal_sync': enabled,
        'activity_sync': enabled,
      };
    } else if (options.path == '/personal/sync') {
      for (final op in data['operations'] as List) {
        if (receipts.add(op['id'] as String)) {
          entities[op['key'] as String] = {
            'value': op['value'],
            'deleted': op['deleted'],
            'revision': ++revision,
          };
        }
      }
      body = {
        'entities': entities,
        'acknowledged': [for (final op in data['operations'] as List) op['id']],
        'conflicts': [],
        'revision': revision,
      };
      if (gate != null) await gate!.future;
    } else {
      final events = List<Map<String, dynamic>>.from(data['events'] as List);
      for (final event in events) {
        if (!history.any((e) => e['id'] == event['id'])) history.add(event);
      }
      if (loseNextEventResponse && events.isNotEmpty) {
        loseNextEventResponse = false;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      final cursor = data['cursor'] as int;
      final page = history.skip(cursor).take(2).toList();
      body = {
        'revision': history.length,
        'cursor': cursor + page.length,
        'has_more': cursor + page.length < history.length,
        'acknowledged': events.map((e) => e['id']).toList(),
        'events': [
          for (var i = 0; i < page.length; i++)
            {'revision': cursor + i + 1, 'event': page[i]},
        ],
      };
    }
    return ResponseBody.fromString(
      jsonEncode({'data': body}),
      200,
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
  sqfliteFfiInit();
  late ReligiousActivityStore store;
  late ReligiousActivitySync client;
  late ModuleCloud cloud;
  ActivityAccountSession? current;
  setUp(() async {
    store = await ReligiousActivityStore.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    cloud = ModuleCloud();
    current = const ActivityAccountSession('1', 'token-one', mergeGuest: true);
    client = ReligiousActivitySync(
      store: store,
      session: () => current,
      dio: Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = cloud,
    );
  });
  tearDown(() async {
    client.disposed = true;
    await store.close();
  });
  ReligiousActivityEvent event() => ReligiousActivityEvent(
    id: operationId(),
    deviceId: operationId(),
    sessionId: operationId(),
    subjectId: 'hisn-001',
    epoch: operationId(),
    kind: ActivityKind.count,
    amount: 1,
    occurredAt: DateTime.utc(2026, 10, 24),
    day: '2026-10-24',
    utcOffsetMinutes: 180,
  );

  test(
    'disabled backend retains local changes and reports no sync success',
    () async {
      cloud.enabled = false;
      await store.save(
        'account.1',
        PersonalDhikr(id: operationId(), text: 'ذكر', target: 3),
      );
      await store.append('account.1', event());
      expect(await client.sync(), isFalse);
      expect(cloud.requests.map((r) => r.path), ['/capabilities']);
      expect((await store.pendingPersonal('account.1')).length, 1);
      expect((await store.events('account.1', pendingOnly: true)).length, 1);
      expect(client.lastSync, isEmpty);
      expect(client.errors['account.1'], contains('غير مفعّلة'));
    },
  );

  test(
    'pulls all remote pages before selected guest merge, retaining tombstones',
    () async {
      final removed = PersonalDhikr(
        id: operationId(),
        text: 'محذوف',
        target: 1,
      );
      final guest = PersonalDhikr(id: operationId(), text: 'ضيف', target: 3);
      await store.save('guest', removed);
      await store.save('guest', guest);
      final localEvent = event();
      await store.append('guest', localEvent);
      cloud.entities[removed.key] = {
        'value': null,
        'deleted': true,
        'revision': 1,
      };
      cloud.revision = 1;
      cloud.history.addAll(List.generate(3, (_) => event().toJson()));
      expect(await client.sync(), isTrue);
      expect((await store.entities('account.1')).map((e) => e.id), [guest.id]);
      expect(cloud.entities[removed.key]['deleted'], isTrue);
      expect(cloud.history.length, 4);
      expect(await store.activityCursor('account.1'), 4);
      expect(await store.events('account.1', pendingOnly: true), isEmpty);
      expect(await store.pendingPersonal('account.1'), isEmpty);
      expect(
        cloud.requests
            .where((r) => r.path.endsWith('/sync'))
            .every((r) => r.headers['Authorization'] == 'Bearer token-one'),
        isTrue,
      );
    },
  );

  test(
    'lost response retries immutable events without duplicating server history',
    () async {
      final local = event();
      await store.append('account.1', local);
      cloud.loseNextEventResponse = true;
      expect(await client.sync(), isFalse);
      expect(cloud.history.length, 1);
      expect((await store.events('account.1', pendingOnly: true)).length, 1);
      expect(await client.sync(), isTrue);
      expect(cloud.history.length, 1);
      expect(await store.events('account.1', pendingOnly: true), isEmpty);
      expect(client.errors, isEmpty);
    },
  );

  test(
    'schema2 server keeps extended progress local and schema3 synchronizes typed definitions and history',
    () async {
      final h = ReligiousHabit(
        id: operationId(),
        title: 'عادة',
        weekdays: [1, 7],
        icon: 'beads',
        target: 33,
        epoch: operationId(),
      );
      final k = QuranKhatma(
        id: operationId(),
        title: 'ختمة',
        startDate: '2026-10-25',
        endDate: '2026-11-23',
        epoch: operationId(),
        archived: false,
        reminderMinutes: 1245,
      );
      await store.save('account.1', h);
      await store.save('account.1', k);
      final page = ReligiousActivityEvent.fromJson({
        ...event().toJson(),
        'session_id': k.id,
        'epoch': k.activeEpoch,
        'subject_id': 'quran-page:1',
        'kind': 'quranPage',
      });
      await store.append('account.1', page);
      cloud.schemaVersion = 2;
      expect(await client.sync(), isFalse);
      expect(cloud.entities, isEmpty);
      expect(cloud.history, isEmpty);
      expect((await store.pendingPersonal('account.1')).length, 2);
      cloud.schemaVersion = 3;
      cloud.loseNextEventResponse = true;
      expect(await client.sync(), isFalse);
      expect(await client.sync(), isTrue);
      expect(cloud.entities[h.key]['value'], h.toJson());
      expect(cloud.entities[k.key]['value'], k.toJson());
      expect(cloud.history.single['id'], page.id);
      expect(await store.pendingPersonal('account.1'), isEmpty);
      expect(await store.events('account.1', pendingOnly: true), isEmpty);
      final replica = await ReligiousActivityStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      final otherClient = ReligiousActivitySync(
        store: replica,
        session: () => current,
        dio: Dio(BaseOptions(baseUrl: 'https://example.test'))
          ..httpClientAdapter = cloud,
      );
      expect(await otherClient.sync(), isTrue);
      expect(
        (await replica.entities('account.1')).map((e) => e.toJson()),
        containsAll([h.toJson(), k.toJson()]),
      );
      expect(
        (await replica.events('account.1')).single.toJson(),
        page.toJson(),
      );
      otherClient.disposed = true;
      await replica.close();
    },
  );

  test(
    'late account response cannot write another account or import guest state',
    () async {
      final guest = PersonalDhikr(id: operationId(), text: 'ضيف', target: 1);
      await store.save('guest', guest);
      cloud.gate = Completer<void>();
      final pending = client.sync();
      while (!cloud.requests.any((r) => r.path == '/personal/sync')) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      current = const ActivityAccountSession('2', 'token-two');
      cloud.gate!.complete();
      expect(await pending, isFalse);
      expect(await store.entities('account.1'), isEmpty);
      expect(await store.entities('account.2'), isEmpty);
      expect(await store.events('account.2'), isEmpty);
      expect(client.lastSync, isEmpty);
      expect(await client.sync(), isTrue);
      expect(
        await store.entities('account.2'),
        isEmpty,
      ); // mergeGuest=false is respected.
    },
  );
}
