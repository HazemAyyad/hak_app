import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/quran/data/quran_sync.dart';
import 'package:haq_app/features/religious_activity/data/activity_models.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late ReligiousActivityStore store;
  late String session, epoch, device;
  setUp(() async {
    store = await ReligiousActivityStore.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    session = operationId();
    epoch = operationId();
    device = await store.deviceId;
  });
  tearDown(() => store.close());

  ReligiousActivityEvent tap({
    String? id,
    ActivityKind kind = ActivityKind.count,
    String? reverses,
    int? amount,
  }) => ReligiousActivityEvent(
    id: id ?? operationId(),
    deviceId: device,
    sessionId: session,
    subjectId: 'hisn-001',
    epoch: epoch,
    kind: kind,
    amount: amount ?? (kind == ActivityKind.undo ? 0 : 1),
    occurredAt: DateTime.utc(2026, 10, 24, 8, 30),
    day: '2026-10-24',
    utcOffsetMinutes: 180,
    reverses: reverses,
  );
  Map<String, dynamic> page(
    List<ReligiousActivityEvent> events, {
    int start = 0,
  }) => {
    'revision': start + events.length,
    'cursor': start + events.length,
    'has_more': false,
    'acknowledged': events.map((e) => e.id).toList(),
    'events': [
      for (var i = 0; i < events.length; i++)
        {'revision': start + i + 1, 'event': events[i].toJson()},
    ],
  };

  test(
    'typed records round-trip and reject invalid counters/dates/membership',
    () {
      final values = <PersonalEntity>[
        PersonalDhikrGroup(
          id: operationId(),
          title: 'مجموعة',
          itemIds: ['hisn-001'],
        ),
        PersonalDhikr(id: operationId(), text: 'ذكر شخصي', target: 3),
        DhikrSession(
          id: session,
          groupId: 'daily:morning',
          day: '2026-10-24',
          epoch: epoch,
          targets: {'hisn-001': 3},
          mode: DhikrReadingMode.cards,
          catalogVersion: 'v1',
        ),
        ReligiousHabit(id: operationId(), title: 'عادة', weekdays: [1, 7]),
        QuranKhatma(
          id: operationId(),
          title: 'ختمة',
          startDate: '2026-10-24',
          endDate: '2026-11-24',
        ),
      ];
      for (final entity in values) {
        expect(
          PersonalEntity.fromJson(
            entity.kind,
            jsonDecode(jsonEncode(entity.toJson())) as Map<String, dynamic>,
          ).toJson(),
          entity.toJson(),
        );
      }
      expect(
        () => PersonalDhikr(id: operationId(), text: 'ذكر', target: 0),
        throwsFormatException,
      );
      expect(() => activityDate('2026-02-30'), throwsFormatException);
      expect(
        () => PersonalDhikrGroup(
          id: operationId(),
          title: 'مجموعة',
          itemIds: ['a', 'a'],
        ),
        throwsFormatException,
      );
      expect(
        () =>
            ReligiousActivityEvent.fromJson({...tap().toJson(), 'amount': '1'}),
        throwsFormatException,
      );
      expect(() => tap(kind: ActivityKind.undo), throwsFormatException);
    },
  );

  test(
    'legacy snapshot retains exact old values and checksum without rewriting preferences',
    () async {
      final old = {
        'quran.state.v1': '{"page":17}',
        'religious.state.v1.guest': '{"customAdhkar":["hisn-001"]}',
      };
      SharedPreferences.setMockInitialValues(old);
      final prefs = await SharedPreferences.getInstance();
      await store.snapshotLegacy('guest', prefs);
      final snapshot = (await store.legacySnapshot('guest'))!;
      expect(snapshot['values'], old);
      expect(
        snapshot['sha256'],
        sha256.convert(utf8.encode(jsonEncode(old))).toString(),
      );
      await prefs.setString('quran.state.v1', '{"page":18}');
      await store.snapshotLegacy('guest', prefs);
      expect((await store.legacySnapshot('guest'))!['values'], old);
      expect(
        prefs.getString('religious.state.v1.guest'),
        old['religious.state.v1.guest'],
      );
      expect(await store.entities('guest'), isEmpty);
    },
  );

  test(
    'atomic taps clamp 3 to 0, retries never count twice, undo restores one',
    () async {
      final taps = List.generate(9, (_) => tap());
      final accepted = await Future.wait(
        taps.map((e) => store.appendWithinTarget('guest', e, 3)),
      );
      expect(accepted.where((v) => v).length, 3);
      expect(await store.count('guest', session, 'hisn-001', epoch), 3);
      expect(await store.appendWithinTarget('guest', taps.first, 3), isFalse);
      final undo = tap(kind: ActivityKind.undo, reverses: taps.first.id);
      expect(await store.append('guest', undo), isTrue);
      expect(await store.append('guest', undo), isFalse);
      expect(await store.count('guest', session, 'hisn-001', epoch), 2);
      await expectLater(
        store.append(
          'guest',
          tap(kind: ActivityKind.undo, reverses: taps.first.id),
        ),
        throwsA(anything),
      );
      expect(await store.appendWithinTarget('guest', taps.last, 3), isTrue);
      expect(await store.count('guest', session, 'hisn-001', epoch), 3);
      expect(await store.count('account.1', session, 'hisn-001', epoch), 0);
      expect(await store.count('guest', session, 'hisn-001', operationId()), 0);
    },
  );

  test(
    'persistent restart retains IDs, pending entities, event history and undo',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'haq_activity_restart_',
      );
      final path = '${directory.path}/activity.sqlite';
      var disk = await ReligiousActivityStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
      );
      try {
        final id = await disk.deviceId;
        final entity = PersonalDhikr(id: operationId(), text: 'ذكر', target: 3);
        final event = tap();
        await disk.save('account.1', entity);
        await disk.append('account.1', event);
        await disk.append(
          'account.1',
          tap(kind: ActivityKind.undo, reverses: event.id),
        );
        await disk.close();
        disk = await ReligiousActivityStore.open(
          factory: databaseFactoryFfiNoIsolate,
          path: path,
        );
        expect(await disk.deviceId, id);
        expect(
          (await disk.entities('account.1')).single.toJson(),
          entity.toJson(),
        );
        expect((await disk.pendingPersonal('account.1')).length, 1);
        expect((await disk.events('account.1', pendingOnly: true)).length, 2);
        expect(await disk.count('account.1', session, 'hisn-001', epoch), 0);
      } finally {
        await disk.close();
        // This test-created temporary directory is the only recursive target.
        expect(
          directory.absolute.path,
          startsWith(Directory.systemTemp.absolute.path),
        );
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'ack preserves edits made during flight and accounts stay separate',
    () async {
      final id = operationId();
      final original = PersonalDhikr(id: id, text: 'الأول', target: 3);
      await store.save('account.1', original);
      final sent = await store.pendingPersonal('account.1');
      await store.save(
        'account.1',
        PersonalDhikr(id: id, text: 'الأحدث', target: 3),
      );
      await store.acceptPersonal('account.1', {
        'entities': {
          original.key: {
            'value': original.toJson(),
            'revision': 1,
            'deleted': false,
          },
        },
        'acknowledged': [sent.single['id']],
        'conflicts': [],
      }, sent);
      expect(
        (await store.entities('account.1')).single.toJson()['text'],
        'الأحدث',
      );
      expect(
        (await store.pendingPersonal('account.1')).single['base_revision'],
        1,
      );
      expect(await store.entities('account.2'), isEmpty);
      expect(await store.pendingPersonal('account.2'), isEmpty);
    },
  );

  test(
    'one-time guest import respects remote tombstones and never copies another account',
    () async {
      final removed = PersonalDhikr(
        id: operationId(),
        text: 'محذوف',
        target: 1,
      );
      final guest = PersonalDhikr(id: operationId(), text: 'ضيف', target: 3);
      await store.save('guest', removed);
      await store.save('guest', guest);
      await store.save(
        'account.2',
        PersonalDhikr(id: operationId(), text: 'حساب آخر', target: 5),
      );
      final event = tap();
      await store.append('guest', event);
      await store.acceptPersonal('account.1', {
        'entities': {
          removed.key: {'value': null, 'revision': 1, 'deleted': true},
        },
        'acknowledged': [],
        'conflicts': [],
      }, []);
      await store.mergeGuestOnce('account.1');
      expect((await store.entities('account.1')).map((e) => e.id), [guest.id]);
      expect((await store.events('account.1')).single.id, event.id);
      await store.save(
        'guest',
        PersonalDhikr(id: operationId(), text: 'ضيف لاحق', target: 1),
      );
      await store.mergeGuestOnce('account.1');
      expect((await store.entities('account.1')).length, 1);
      expect((await store.entities('guest')).length, 3);
    },
  );

  test(
    'remote pages are atomic and reject skipped revisions before ack or cursor changes',
    () async {
      final first = tap(), second = tap();
      await store.append('account.1', first);
      final invalid = page([first, second]);
      (invalid['events'] as List).last['revision'] = 3;
      await expectLater(
        store.acceptActivity('account.1', invalid),
        throwsFormatException,
      );
      expect(await store.activityCursor('account.1'), 0);
      expect(
        (await store.events('account.1', pendingOnly: true)).single.id,
        first.id,
      );
      await store.acceptActivity('account.1', page([first, second]));
      expect(await store.activityCursor('account.1'), 2);
      expect(await store.events('account.1', pendingOnly: true), isEmpty);
      expect(await store.count('account.1', session, 'hisn-001', epoch), 2);
      expect(await store.events('account.2'), isEmpty);
    },
  );

  test(
    'remote undo replaces a redundant offline undo without reversing twice',
    () async {
      final event = tap();
      await store.acceptActivity('account.1', page([event]));
      final localUndo = tap(kind: ActivityKind.undo, reverses: event.id);
      await store.append('account.1', localUndo);
      final remoteUndo = tap(kind: ActivityKind.undo, reverses: event.id);
      await store.acceptActivity('account.1', page([remoteUndo], start: 1));
      expect(await store.count('account.1', session, 'hisn-001', epoch), 0);
      expect(await store.events('account.1', pendingOnly: true), isEmpty);
      expect((await store.events('account.1')).map((e) => e.id), [
        event.id,
        remoteUndo.id,
      ]);
    },
  );
}
