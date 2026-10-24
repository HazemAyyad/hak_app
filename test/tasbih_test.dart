import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/data/quran_sync.dart';
import 'package:haq_app/features/religious_activity/data/activity_controller.dart';
import 'package:haq_app/features/religious_activity/data/activity_models.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'package:haq_app/features/tasbih/data/tasbih_controller.dart';
import 'package:haq_app/features/tasbih/data/tasbih_preferences.dart';
import 'package:haq_app/features/tasbih/data/tasbih_voice.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeSpeech implements TasbihSpeech {
  void Function(String)? result;
  void Function(bool, String?)? status;
  String? failure;
  Object? owner;
  Completer<void>? gate;
  int starts = 0;
  @override
  Future<String?> start(
    Object value, {
    required void Function(String) onFinal,
    required void Function(bool, String?) onStatus,
  }) async {
    starts++;
    owner = value;
    result = onFinal;
    status = onStatus;
    if (gate != null) await gate!.future;
    if (failure == null && owner == value) onStatus(true, null);
    return failure;
  }

  @override
  Future<void> cancel(Object value) async {
    if (owner == value) owner = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final repository = QuranRepository.fromJson(
    jsonDecode(File('assets/quran/quran.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  late QuranController quran;
  late ReligiousActivityStore store;
  late ReligiousActivityController activity;
  final counters = <TasbihController>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    quran = QuranController(
      initialRepository: repository,
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
  });
  tearDown(() async {
    for (final c in counters) {
      await c.flush();
      c.dispose();
    }
    counters.clear();
    activity.dispose();
    quran.dispose();
    await store.close();
  });
  Future<TasbihController> open([PersonalTasbih? definition]) async {
    final c = await TasbihController.open(
      activity,
      definition ?? (await TasbihController.library(activity)).first,
      clock: () => DateTime.utc(2026, 10, 24, 8),
    );
    counters.add(c);
    return c;
  }

  test(
    'ascending counts, six skins, undo and both resets survive reopening independently',
    () async {
      final c = await open();
      await Future.wait(List.generate(110, (_) => c.increment()));
      expect([c.total, c.rounds, c.current], [110, 3, 11]);
      for (final skin in TasbihStyle.values) {
        await c.style(skin);
        expect([c.total, c.rounds, c.current], [110, 3, 11]);
      }
      final reopened = await open(c.definition);
      expect([reopened.total, reopened.rounds, reopened.current], [110, 3, 11]);
      await c.resetCurrent();
      expect([c.total, c.rounds, c.current], [110, 3, 0]);
      expect(c.canUndo, false);
      await c.undo();
      expect(c.total, 110);
      for (var i = 0; i < 33; i++) {
        await c.increment();
      }
      expect([c.total, c.rounds, c.current], [143, 4, 0]);
      await c.undo();
      expect([c.total, c.rounds, c.current], [142, 3, 32]);
      await c.refresh();
      expect([c.total, c.rounds, c.current], [142, 3, 32]);
      await c.resetAll();
      expect([c.total, c.rounds, c.current], [0, 0, 0]);
      await c.increment();
      await c.refresh();
      expect(c.total, 1);
      expect(
        (await store.events(
          'guest',
          sessionId: c.definition.id,
        )).where((e) => e.kind == ActivityKind.count).length,
        144,
      );
    },
  );
  test(
    'goal edits preserve past rounds/total, new sessions start at zero; text changes preserve current',
    () async {
      final c = await open();
      for (var i = 0; i < 36; i++) {
        await c.increment();
      }
      await c.edit(text: 'الحمد لله', benefit: 'ملاحظة شخصية', goal: 10);
      expect([c.total, c.rounds, c.current], [36, 1, 0]);
      await c.increment();
      await c.edit(text: 'الله أكبر', benefit: '', goal: 10);
      expect([c.total, c.rounds, c.current], [37, 1, 1]);
      await c.refresh();
      expect([c.total, c.rounds, c.current], [37, 1, 1]);
      expect(
        (await store.entities('guest', kind: PersonalEntityKind.dhikr)),
        isEmpty,
      );
    },
  );
  test(
    'defaults respect deletion, account boundary blocks old counter writes, preferences are scoped',
    () async {
      final c = await open();
      final id = c.definition.id;
      await store.remove('guest', PersonalEntityKind.tasbih, id);
      expect(
        (await TasbihController.library(activity)).any((e) => e.id == id),
        false,
      );
      final prefs = TasbihPreferences(quran.preferences!, 'guest');
      await prefs.set('auto', true);
      expect(prefs.autoCount, true);
      await prefs.set('haptic', false);
      expect(prefs.autoCount, false);
      expect(TasbihPreferences(quran.preferences!, 'account.7').haptic, true);
      quran.account.profile = {'id': 7};
      await c.increment();
      expect(await store.events('guest', sessionId: id), isEmpty);
      expect(await store.events('account.7'), isEmpty);
    },
  );
  test(
    'server reset is ordered before a pending local count even if inserted later on disk',
    () async {
      final c = await open();
      final reset = ReligiousActivityEvent(
        id: operationId(),
        deviceId: operationId(),
        sessionId: c.definition.id,
        subjectId: c.subject,
        epoch: c.definition.epoch,
        kind: ActivityKind.reset,
        amount: 0,
        occurredAt: DateTime.utc(2026, 10, 24, 7),
        day: '2026-10-24',
        utcOffsetMinutes: 0,
      );
      await c.increment();
      await store.acceptActivity('guest', {
        'cursor': 1,
        'revision': 1,
        'has_more': false,
        'acknowledged': <String>[],
        'events': [
          {'revision': 1, 'event': reset.toJson()},
        ],
      });
      await c.refresh();
      expect([c.total, c.current], [1, 1]);
      final pending = (await store.events('guest', pendingOnly: true)).single;
      await store.acceptActivity('guest', {
        'cursor': 2,
        'revision': 2,
        'has_more': false,
        'acknowledged': [pending.id],
        'events': [
          {'revision': 2, 'event': pending.toJson()},
        ],
      });
      await c.refresh();
      expect([c.total, c.current], [1, 1]);
    },
  );
  test('duplicate immutable count ID does not count twice', () async {
    final c = await open(), id = operationId();
    await c.increment(eventId: id);
    await c.increment(eventId: id);
    expect(c.total, 1);
    expect(
      await store.events('guest', sessionId: c.definition.id),
      hasLength(1),
    );
  });
  test(
    'voice counts final matching phrases once and ignores duplicate, unrelated and stale callbacks',
    () async {
      final fake = FakeSpeech(), voice = TasbihVoice(FakeSpeech());
      voice.dispose();
      final v = TasbihVoice(fake);
      var count = 0;
      await v.start('سُبْحَانَ اللَّهِ وَبِحَمْدِهِ', () async {
        count++;
      });
      fake.result!('سبحان الله وبحمده سبحان الله وبحمده');
      fake.result!('سبحان الله وبحمده سبحان الله وبحمده');
      await Future<void>.delayed(Duration.zero);
      expect(count, 2);
      await v.start('الله أكبر', () async {
        count++;
      });
      fake.result!('كلام آخر');
      expect(count, 2);
      final old = fake.result!;
      await v.stop();
      old('الله أكبر');
      expect(count, 2);
      v.dispose();
    },
  );
  test(
    'voice denial and pending initialization cancellation leave manual counter usable',
    () async {
      final fake = FakeSpeech()..failure = 'الإذن مرفوض';
      final voice = TasbihVoice(fake), c = await open();
      await voice.start(c.definition.text, c.increment);
      expect(voice.message, 'الإذن مرفوض');
      expect(voice.active, false);
      await c.increment();
      expect(c.total, 1);
      fake.failure = null;
      fake.gate = Completer<void>();
      final starting = voice.start(c.definition.text, c.increment);
      await Future<void>.delayed(Duration.zero);
      final lateResult = fake.result!;
      await voice.stop();
      fake.gate!.complete();
      await starting;
      lateResult(c.definition.text);
      await Future<void>.delayed(Duration.zero);
      expect(c.total, 1);
      voice.dispose();
    },
  );
}
