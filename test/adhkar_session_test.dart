import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:haq_app/features/adhkar/data/adhkar_preferences.dart';
import 'package:haq_app/features/adhkar/data/adhkar_repository.dart';
import 'package:haq_app/features/adhkar/data/adhkar_session_controller.dart';
import 'package:haq_app/features/adhkar/data/personal_adhkar.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/religious_activity/data/activity_controller.dart';
import 'package:haq_app/features/religious_activity/data/activity_models.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final quranData = QuranRepository.fromJson(
    jsonDecode(File('assets/quran/quran.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final repository = AdhkarRepository.fromJson(
    jsonDecode(File('assets/religious/adhkar.json').readAsStringSync())
        as Map<String, dynamic>,
    quranData,
  );
  late QuranController quran;
  late ReligiousActivityController activity;
  late ReligiousActivityStore store;
  late DateTime now;
  final sessions = <AdhkarSessionController>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'quran.state.v1': '{"page":17}',
      'religious.state.v1.guest': '{"customAdhkar":["hisn-001"]}',
    });
    FlutterSecureStorage.setMockInitialValues({});
    quran = QuranController(
      initialRepository: quranData,
      preferences: await SharedPreferences.getInstance(),
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
    now = DateTime.utc(2026, 10, 24, 8);
  });
  tearDown(() async {
    for (final session in sessions) {
      await session.flush();
      session.dispose();
    }
    sessions.clear();
    activity.dispose();
    quran.dispose();
    await store.close();
  });
  Future<AdhkarSessionController> open({String? id}) async {
    final library = await repository.library(store, activity.scope);
    final group = library.groups.firstWhere(
      (g) => g.id == (id ?? 'personal:all'),
    );
    final session = await AdhkarSessionController.open(
      activity: activity,
      group: group,
      library: library,
      catalogVersion: repository.version,
      clock: () => now,
    );
    sessions.add(session);
    return session;
  }

  Future<void> twoEntries() async {
    final editor = PersonalAdhkar(activity);
    await editor.saveDhikr(text: 'الأول', target: '٣');
    await editor.saveDhikr(text: 'الثاني', target: '۱');
  }

  test(
    'official source has 14 complete groups and verified count corrections without changing Quran',
    () {
      expect(repository.groups.length, 14);
      expect(repository.items.length, 267);
      expect(repository.items['hisn-api-083']!.target, 7);
      expect(repository.items['hisn-api-130']!.target, 3);
      expect(repository.items['hisn-api-148']!.target, 7);
      expect(repository.items['hisn-api-153']!.audioUrl, isNull);
      expect(
        repository.items['hisn-api-075']!.text,
        contains(quranData.byKey['2:255']!.text),
      );
      expect(repository.groups.first.itemIds, isNot(contains('hisn-api-097')));
    },
  );
  test(
    'horizontal count clamps at zero, stays on the same item and undo restores last tap',
    () async {
      await twoEntries();
      final c = await open();
      final first = c.current;
      await Future.wait(List.generate(8, (_) => c.count(first.id)));
      expect(c.remaining(first.id), 0);
      expect(c.cursor, 0);
      expect(c.completed, isFalse);
      expect(
        (await store.events(
          'guest',
        )).where((e) => e.kind == ActivityKind.count).length,
        3,
      );
      await c.undo();
      expect(c.remaining(first.id), 1);
      expect(c.cursor, 0);
      await c.count(first.id);
      expect(c.remaining(first.id), 0);
    },
  );
  test(
    'focus auto-advance and undo retain previous item; stale rapid taps never count next item',
    () async {
      await twoEntries();
      final c = await open();
      c.settings.mode = DhikrReadingMode.focus;
      await c.saveSettings();
      final first = c.current.id, second = c.items[1].id;
      await Future.wait(List.generate(9, (_) => c.count(first)));
      expect(c.cursor, 1);
      expect(c.remaining(first), 0);
      expect(c.remaining(second), 1);
      await c.undo();
      expect(c.cursor, 0);
      expect(c.remaining(first), 1);
      await c.count(first);
      await c.count(second);
      expect(c.completed, isTrue);
      await c.undo();
      expect(c.completed, isFalse);
      expect(c.cursor, 1);
      expect(c.remaining(second), 1);
      await c.count(second);
      expect(
        (await store.events(
          'guest',
        )).where((e) => e.kind == ActivityKind.complete).length,
        1,
      );
    },
  );
  test(
    'session reload keeps progress, new day starts separately and restart preserves history',
    () async {
      await twoEntries();
      final first = await open();
      await first.count(first.current.id);
      final resumed = await open();
      expect(resumed.session.id, first.session.id);
      expect(resumed.remaining(resumed.current.id), 2);
      final oldEpoch = resumed.session.epoch;
      await resumed.restart();
      expect(resumed.remaining(resumed.current.id), 3);
      expect(resumed.session.epoch, isNot(oldEpoch));
      expect(
        await store.count(
          'guest',
          first.session.id,
          first.current.id,
          oldEpoch,
        ),
        1,
      );
      now = now.add(const Duration(days: 1));
      await first.count(first.current.id);
      expect(first.error, contains('يوم جديد'));
      final today = await open();
      expect(today.session.id, isNot(first.session.id));
      expect(today.remaining(today.current.id), 3);
    },
  );
  test(
    'bulk completion is one reversible event and display preferences survive reopening',
    () async {
      await twoEntries();
      final c = await open();
      c.settings.mode = DhikrReadingMode.list;
      c.settings.font = 'Tajawal';
      c.settings.size = 31;
      c.settings.hideCompleted = true;
      c.settings.confirmExit = false;
      await c.saveSettings();
      await c.count(c.current.id, complete: true);
      expect(c.remaining(c.items.first.id), 0);
      await c.undo();
      expect(c.remaining(c.items.first.id), 3);
      final saved = AdhkarPreferences.load(quran.preferences!, 'guest');
      expect(saved.mode, DhikrReadingMode.list);
      expect(saved.size, 31);
      expect(saved.font, 'Tajawal');
      expect(saved.hideCompleted, isTrue);
      expect(saved.confirmExit, isFalse);
    },
  );
  test(
    'old account reader and editor cannot write newly selected account',
    () async {
      await twoEntries();
      final c = await open();
      final editor = PersonalAdhkar(activity);
      quran.account.profile = {'id': 2};
      quran.account.token = 'test-token';
      await c.count(c.current.id);
      expect(c.available, isFalse);
      expect(c.error, contains('تغيّر الحساب'));
      await expectLater(
        editor.saveDhikr(text: 'خطأ', target: '1'),
        throwsStateError,
      );
      expect(await store.events('account.2'), isEmpty);
      expect(await store.entities('account.2'), isEmpty);
      expect(await store.events('guest'), isEmpty);
    },
  );
  test(
    'personal membership, deletion and concurrent save toggles preserve old preferences',
    () async {
      final editor = PersonalAdhkar(activity);
      await twoEntries();
      final entries = (await store.entities(
        'guest',
        kind: PersonalEntityKind.dhikr,
      )).whereType<PersonalDhikr>().toList();
      expect(entries.map((e) => e.target), [3, 1]);
      await editor.saveGroup(
        title: 'مجموعة',
        items: [entries[1].key, entries[0].key, 'hisn-api-075'],
      );
      var group = (await store.entities(
        'guest',
        kind: PersonalEntityKind.group,
      )).whereType<PersonalDhikrGroup>().single;
      expect(group.itemIds, [entries[1].key, entries[0].key, 'hisn-api-075']);
      await editor.saveGroup(
        id: group.id,
        title: group.title,
        items: group.itemIds.reversed.toList(),
        order: 0,
      );
      await Future.wait([
        editor.toggleSaved(entries[0].key),
        editor.toggleSaved('hisn-api-075'),
        editor.toggleSaved(entries[0].key),
      ]);
      final library = await repository.library(store, 'guest');
      expect(
        library.groups
            .firstWhere((g) => g.id == 'group:${AdhkarRepository.savedGroupId}')
            .itemIds,
        ['hisn-api-075'],
      );
      await editor.deleteDhikr(entries[0].id);
      group = (await store.entities(
        'guest',
        kind: PersonalEntityKind.group,
      )).whereType<PersonalDhikrGroup>().firstWhere((g) => g.id == group.id);
      expect(group.itemIds, isNot(contains(entries[0].key)));
      expect(
        (await store.entities('guest', kind: PersonalEntityKind.dhikr)).length,
        1,
      );
      expect(
        quran.preferences!.getString('religious.state.v1.guest'),
        '{"customAdhkar":["hisn-001"]}',
      );
      expect(quran.preferences!.getString('quran.state.v1'), contains('17'));
      expect(await store.entities('account.3'), isEmpty);
      await expectLater(
        editor.saveDhikr(text: 'عدد غير صحيح', target: '١.٥'),
        throwsFormatException,
      );
    },
  );

  test(
    'daily group overrides reorder by stable IDs without losing existing counts',
    () async {
      await twoEntries();
      final values = (await store.entities(
        'guest',
        kind: PersonalEntityKind.dhikr,
      )).whereType<PersonalDhikr>().toList();
      final editor = PersonalAdhkar(activity),
          overrideId = adhkarIdentity('override:daily:morning');
      await editor.saveGroup(
        id: overrideId,
        title: 'أذكار الصباح',
        items: values.map((v) => v.key).toList(),
      );
      final first = await open(id: 'daily:morning');
      await first.count(first.current.id);
      await editor.saveGroup(
        id: overrideId,
        title: 'أذكار الصباح',
        items: values.reversed.map((v) => v.key).toList(),
      );
      final reordered = await open(id: 'daily:morning');
      expect(reordered.session.id, first.session.id);
      expect(reordered.current.id, values.first.key);
      expect(reordered.cursor, 1);
      expect(reordered.remaining(values.first.key), 2);
      expect(repository.groups.first.itemIds.first, 'hisn-api-075');
      await editor.saveDhikr(
        id: values.first.id,
        text: values.first.text,
        target: '3',
        preface: 'مقدمة اختيارية',
      );
      expect(
        (await store.entity('guest', values.first.key) as PersonalDhikr)
            .preface,
        'مقدمة اختيارية',
      );
    },
  );

  test(
    'daily identity is stable across devices and scopes while events stay isolated',
    () async {
      expect(
        adhkarIdentity('session:daily:morning:2026-10-24'),
        '9de77423-8be6-5725-aa6f-2456f0d64c88',
      );
      final guest = await open(id: 'daily:morning');
      await guest.count(guest.current.id);
      quran.account.profile = {'id': 2};
      quran.account.token = 'test';
      final account = await open(id: 'daily:morning');
      expect(account.session.id, guest.session.id);
      expect(account.session.epoch, guest.session.epoch);
      expect(account.remaining(account.current.id), 1);
      expect(guest.available, isFalse);
      expect(
        await store.count(
          'guest',
          guest.session.id,
          guest.items.first.id,
          guest.session.epoch,
        ),
        1,
      );
      expect(
        await store.count(
          'account.2',
          account.session.id,
          account.items.first.id,
          account.session.epoch,
        ),
        0,
      );
    },
  );
}
