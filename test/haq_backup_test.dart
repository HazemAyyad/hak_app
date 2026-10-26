import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:haq_app/features/account/data/haq_backup.dart';
import 'package:haq_app/features/account/data/restore_journal.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/data/quran_sync.dart';
import 'package:haq_app/features/religious_content/data/religious_catalog.dart';
import 'package:haq_app/features/religious_content/data/religious_controller.dart';
import 'package:haq_app/features/religious_activity/data/activity_controller.dart';
import 'package:haq_app/features/religious_activity/data/activity_models.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'package:haq_app/features/prayer/data/prayer_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late QuranController quran;
  late ReligiousController content;
  late ReligiousActivityController activity;
  late ReligiousActivityStore store;
  late SharedPreferences prefs;
  late HaqBackup backup;
  late PersonalDhikr dhikr;
  late ReligiousActivityEvent event;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    quran = QuranController(
      preferences: prefs,
      initialRepository: QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
    );
    await quran.load();
    store = await ReligiousActivityStore.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    activity = await ReligiousActivityController.open(
      quran,
      store: store,
      enableSync: false,
    );
    content = ReligiousController(
      quran: quran,
      initialCatalog: ReligiousCatalog.fromJson(
        jsonDecode(File('assets/religious/catalog.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
      activityFactory: () async => activity,
    );
    await content.load();
    backup = HaqBackup(activity, content);
    dhikr = PersonalDhikr(id: operationId(), text: 'ذكر شخصي', target: 3);
    await store.save('guest', dhikr);
    event = ReligiousActivityEvent(
      id: operationId(),
      deviceId: await store.deviceId,
      sessionId: operationId(),
      subjectId: dhikr.key,
      epoch: operationId(),
      kind: ActivityKind.count,
      amount: 1,
      occurredAt: DateTime.utc(2026, 10, 26, 8),
      day: '2026-10-26',
      utcOffsetMinutes: 180,
    );
    await store.append('guest', event);
    quran.toggleFavorite('2:3');
    await quran.flushReading();
  });
  tearDown(() async {
    content.dispose();
    activity.dispose();
    quran.dispose();
    await store.close();
  });
  test(
    'roundtrip includes typed data and settings without credentials, other accounts or downloaded bytes',
    () async {
      await prefs.setString(
        'quran.account.profile',
        'private-email@example.test',
      );
      await prefs.setString('quran.account.token', 'secret-token');
      await prefs.setString('quran.state.v1.account.99', 'other-account-data');
      await prefs.setString(
        'prayer.config.v1.guest',
        jsonEncode(PrayerConfig().toJson()),
      );
      await prefs.setString(
        'sakinah.settings.guest',
        jsonEncode({
          'pattern': 1,
          'minutes': 3,
          'custom': [4, 0, 4, 0],
          'reduced': false,
          'haptic': true,
          'record': true,
        }),
      );
      final archive = HaqBackupArchive.decode(
        (await backup.capture()).encode(),
      );
      backup.validate(archive);
      expect(archive.personal.keys, [dhikr.key]);
      expect(archive.events.single.id, event.id);
      final text = archive.encode();
      for (final secret in [
        'private-email',
        'secret-token',
        'other-account-data',
        'password',
        'quran.account.token',
      ]) {
        expect(text, isNot(contains(secret)));
      }
      expect(
        (archive.payload['settings'] as Map).keys,
        containsAll(['prayer', 'sakinah']),
      );
      expect(await store.deviceId, event.deviceId);
    },
  );
  test(
    'damaged checksum unsupported schema and unknown settings fail before any write',
    () async {
      final archive = await backup.capture();
      final original = prefs.getString('quran.state.v1');
      expect(
        () => HaqBackupArchive.decode(
          archive.encode().replaceFirst('haq.backup', 'bad.backup'),
        ),
        throwsFormatException,
      );
      final unknown = HaqBackupArchive.create('guest', {
        ...archive.payload,
        'settings': {'token': 'secret'},
      });
      await expectLater(
        backup.restore(unknown, replace: true),
        throwsFormatException,
      );
      expect(prefs.getString('quran.state.v1'), original);
      expect((await store.events('guest')).length, 1);
      expect(prefs.containsKey(restoreJournalKey), false);
    },
  );
  test(
    'merge keeps current Quran entries and entity edits; replace restores collections; history always deduplicates',
    () async {
      final archive = await backup.capture();
      quran.toggleFavorite('2:4');
      await store.save(
        'guest',
        PersonalDhikr(id: dhikr.id, text: 'تعديل أحدث', target: 5),
      );
      await backup.restore(archive, replace: false);
      expect(quran.favorites.keys, containsAll(['2:3', '2:4']));
      expect(
        (await store.entity('guest', dhikr.key) as PersonalDhikr).target,
        5,
      );
      await backup.restore(archive, replace: true);
      expect(quran.favorites.keys, ['2:3']);
      expect(
        (await store.entity('guest', dhikr.key) as PersonalDhikr).target,
        3,
      );
      await backup.restore(archive, replace: true);
      expect((await store.events('guest')).length, 1);
      expect(
        await store.count(
          'guest',
          event.sessionId,
          event.subjectId,
          event.epoch,
        ),
        1,
      );
    },
  );
  test(
    'a preference failure after a partial write rolls back SQLite and restores old preferences',
    () async {
      final archive = await backup.capture();
      quran.toggleFavorite('2:4');
      await quran.flushReading();
      await store.save(
        'guest',
        PersonalDhikr(id: dhikr.id, text: 'تعديل محفوظ', target: 7),
      );
      final before = prefs.getString('quran.state.v1');
      var writes = 0;
      final failing = HaqBackup(
        activity,
        content,
        writePreference: (key, value) async {
          if (++writes == 2) throw StateError('simulated disk failure');
          await writeBackupPreference(prefs, key, value);
        },
      );
      await expectLater(
        failing.restore(archive, replace: true),
        throwsStateError,
      );
      expect(writes, 2);
      expect(prefs.getString('quran.state.v1'), before);
      expect(
        (await store.entity('guest', dhikr.key) as PersonalDhikr).target,
        7,
      );
      expect(quran.favorites.keys, contains('2:4'));
      expect(prefs.containsKey(restoreJournalKey), false);
      expect(quran.account.maintenance, false);
    },
  );
  test(
    'conflicting immutable event payload aborts the complete restore',
    () async {
      final archive = await backup.capture();
      final invalid = HaqBackupArchive.create('guest', {
        ...archive.payload,
        'events': [
          {...event.toJson(), 'amount': 2},
        ],
      });
      quran.toggleFavorite('2:4');
      await quran.flushReading();
      final before = prefs.getString('quran.state.v1');
      await expectLater(
        backup.restore(invalid, replace: true),
        throwsStateError,
      );
      expect(prefs.getString('quran.state.v1'), before);
      expect((await store.events('guest')).single.amount, 1);
    },
  );
  test(
    'another account or guest archive cannot write into the selected account',
    () async {
      final archive = await backup.capture();
      quran.account.profile = {
        'id': 2,
        'name': 'قارئ',
        'email': 'two@example.test',
      };
      await store.save(
        'account.2',
        PersonalDhikr(id: operationId(), text: 'خاص بالحساب', target: 9),
      );
      await expectLater(
        backup.restore(archive, replace: true),
        throwsFormatException,
      );
      expect((await store.entities('account.2')).length, 1);
      expect((await store.events('account.2')), isEmpty);
      expect((await store.events('guest')).length, 1);
    },
  );
  test(
    'crash recovery restores preferences before an uncommitted transaction and keeps committed data',
    () async {
      const key = 'quran.state.v1';
      final before = prefs.getString(key);
      final id = operationId();
      await prefs.setString(
        restoreJournalKey,
        jsonEncode({
          'id': id,
          'scope': 'guest',
          'before': {key: before},
        }),
      );
      await prefs.setString(key, 'interrupted');
      await recoverHaqRestore(prefs, store: store);
      expect(prefs.getString(key), before);
      final committed = operationId();
      await prefs.setString(
        restoreJournalKey,
        jsonEncode({
          'id': committed,
          'scope': 'guest',
          'before': {key: before},
        }),
      );
      await store.restoreBackup(
        'guest',
        {},
        [],
        replace: false,
        restoreId: committed,
        writePreferences: () async {
          await prefs.setString(key, 'committed');
        },
      );
      await recoverHaqRestore(prefs, store: store);
      expect(prefs.getString(key), 'committed');
      expect(prefs.containsKey(restoreJournalKey), false);
    },
  );
  test(
    'merge preserves server tombstones and replace uses the current server revision',
    () async {
      quran.account.profile = {
        'id': 1,
        'name': 'قارئ',
        'email': 'one@example.test',
      };
      quran.account.ledger = QuranSyncLedger(
        stored: {
          'server': {
            'favorite:2:3': {'value': null, 'deleted': true, 'revision': 8},
          },
          'pending': {},
        },
      );
      final archive = HaqBackupArchive.create('account.1', {
        'quran': {'favorite:2:3': '2026-10-26T08:00:00Z'},
        'content': {},
        'personal': {},
        'events': [],
        'settings': {},
      });
      quran.favorites.clear();
      await backup.restore(archive, replace: false);
      expect(quran.favorites, isEmpty);
      await backup.restore(archive, replace: true);
      expect(quran.favorites.keys, ['2:3']);
      expect(quran.account.ledger.pending['favorite:2:3']['base_revision'], 8);
    },
  );
}
