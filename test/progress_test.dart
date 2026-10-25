import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:haq_app/features/progress/data/progress_controller.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/data/quran_sync.dart';
import 'package:haq_app/features/religious_activity/data/activity_controller.dart';
import 'package:haq_app/features/religious_activity/data/activity_models.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final repo = QuranRepository.fromJson(
    jsonDecode(File('assets/quran/quran.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  late QuranController quran;
  late ReligiousActivityStore store;
  late ReligiousActivityController activity;
  late ProgressController c;
  late DateTime now;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    quran = QuranController(
      initialRepository: repo,
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
    now = DateTime(2026, 10, 25, 12);
    c = await ProgressController.open(activity, repo, clock: () => now);
  });
  tearDown(() async {
    await c.flush();
    c.dispose();
    activity.dispose();
    quran.dispose();
    await store.close();
  });
  QuranKhatma khatma() => QuranKhatma(
    id: operationId(),
    title: 'ختمتي',
    startDate: c.day,
    endDate: '2026-11-23',
    epoch: operationId(),
  );
  ReligiousHabit habit({int target = 1}) => ReligiousHabit(
    id: operationId(),
    title: 'عادة',
    weekdays: [1, 2, 3, 4, 5, 6, 7],
    target: target,
    icon: 'book',
    epoch: operationId(),
  );

  test(
    'daily partitions cover every page once through 604 including leap and DST dates',
    () {
      for (final days in [1, 10, 15, 30, 40, 60, 120, 605]) {
        final start = civilDate('2028-02-28');
        final plan = khatmaPlan(
          QuranKhatma(
            id: operationId(),
            title: 'ختمة',
            startDate: '2028-02-28',
            endDate: progressDay(start.add(Duration(days: days - 1))),
          ),
        );
        final pages = [
          for (final p in plan)
            for (var n = p.first; n <= p.last; n++) n,
        ];
        expect(pages, List.generate(604, (i) => i + 1));
        expect(plan.length, days);
        expect(plan.last.last, 604);
      }
      expect(
        civilDate('2026-10-25').difference(civilDate('2026-10-24')).inDays,
        1,
      );
    },
  );
  test(
    'legacy entity JSON remains byte-shape compatible and new icon epoch are typed',
    () {
      final h = ReligiousHabit(
        id: operationId(),
        title: 'سابق',
        weekdays: [1],
        target: 1,
      );
      expect(h.toJson().keys, ['id', 'title', 'weekdays', 'target', 'enabled']);
      expect(ReligiousHabit.fromJson(h.toJson()).toJson(), h.toJson());
      final k = QuranKhatma(
        id: operationId(),
        title: 'سابق',
        startDate: c.day,
        endDate: c.day,
      );
      expect(k.toJson().length, 6);
      expect(QuranKhatma.fromJson(k.toJson()).activeEpoch, k.id);
      expect(
        () => ReligiousHabit(
          id: h.id,
          title: 'خاطئ',
          weekdays: [1],
          icon: 'invalid',
        ),
        throwsFormatException,
      );
      expect(
        () => ReligiousHabit(
          id: h.id,
          title: 'خاطئ',
          weekdays: [1],
          epoch: 'invalid',
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'rapid habit taps cap, undo is once, new civil day starts at zero and deletion keeps statistics',
    () async {
      final h = habit(target: 3);
      await c.saveHabit(h);
      await Future.wait(List.generate(10, (_) => c.countHabit(h.id)));
      expect(c.habitCount(h), 3);
      await c.undoHabit(h.id);
      expect(c.habitCount(h), 2);
      expect(c.totals(date: c.day).habits, 2);
      now = now.add(const Duration(days: 1));
      expect(c.habitCount(h), 0);
      await c.countHabit(h.id);
      expect(c.habitCount(h), 1);
      expect(c.totals().habits, 3);
      await c.deleteHabit(h);
      expect(c.habits, isEmpty);
      expect(c.totals().habits, 3);
    },
  );
  test(
    'khatma counts only explicit confirmed whole pages, resumes next verse and never regresses',
    () async {
      final k = khatma();
      await c.saveKhatma(k);
      expect(c.fraction(k), 0);
      await c.confirmRead(k.id, repo.byKey['1:1']!);
      expect(c.readPages(k), isEmpty);
      expect(c.lastRead(k)!.key, '1:1');
      await c.confirmRead(k.id, repo.byKey['1:7']!);
      expect(c.readPages(k), {1});
      expect(c.resume(k).key, '2:1');
      await c.confirmRead(k.id, repo.byKey['1:2']!);
      expect(c.lastRead(k)!.key, '1:7');
      expect(c.totals().pages, 1);
      final count = (await store.events(c.scope)).length;
      await c.confirmRead(k.id, repo.byKey['1:7']!);
      expect((await store.events(c.scope)).length, count);
    },
  );
  test(
    'completion reaches Quran end; reset retains visible past cycle and starts new epoch',
    () async {
      final k = khatma();
      await c.saveKhatma(k);
      await c.confirmRead(k.id, repo.verses.last);
      expect(c.readPages(k).length, 604);
      expect(c.completed(k), true);
      await c.resetKhatma(k);
      final next = c.khatmas.single;
      expect(c.fraction(next), 0);
      expect(c.completed(next), false);
      expect(c.previousCycles(next).single.pages, 604);
      expect(c.previousCycles(next).single.complete, true);
      expect(c.totals().pages, 604);
      await c.confirmRead(k.id, repo.byKey['1:7']!);
      expect(c.totals().pages, 605);
    },
  );
  test(
    'two offline observations of same page converge once and belong to earliest confirmed day',
    () async {
      final k = khatma();
      await c.saveKhatma(k);
      await c.confirmRead(k.id, repo.byKey['1:7']!);
      final original = c.history.firstWhere(
        (e) => e.subjectId == 'quran-page:1',
      );
      now = now.add(const Duration(days: 1));
      final duplicate = ReligiousActivityEvent.fromJson({
        ...original.toJson(),
        'id': operationId(),
        'device_id': operationId(),
        'occurred_at': now.toUtc().toIso8601String(),
        'day': c.day,
      });
      await store.append(c.scope, duplicate);
      await c.refresh();
      expect(c.totals().pages, 1);
      expect(c.totals(date: c.day).pages, 0);
      expect(c.readPages(k), {1});
    },
  );
  test(
    'statistics reset preserves all khatma and habit progress and cannot delete history',
    () async {
      final k = khatma(), h = habit();
      await c.saveKhatma(k);
      await c.saveHabit(h);
      await c.confirmRead(k.id, repo.byKey['1:7']!);
      await c.countHabit(h.id);
      await c.resetStatistics();
      expect(c.totals().pages, 0);
      expect(c.totals().habits, 0);
      expect(c.habitCount(h), 1);
      expect(c.readPages(k), {1});
      expect(c.history.where((e) => e.kind == ActivityKind.reset).length, 1);
    },
  );
  test(
    'offline habit observations cap per day and old reader cannot mark a restarted khatma',
    () async {
      final h = habit(), k = khatma();
      await c.saveHabit(h);
      await c.saveKhatma(k);
      await c.countHabit(h.id);
      final tap = c.history.firstWhere((e) => e.kind == ActivityKind.habit);
      await store.append(
        c.scope,
        ReligiousActivityEvent.fromJson({
          ...tap.toJson(),
          'id': operationId(),
          'device_id': operationId(),
        }),
      );
      await c.refresh();
      expect(c.habitCount(h), 1);
      expect(c.totals().habits, 1);
      await c.resetKhatma(k);
      await c.confirmRead(k.id, repo.verses.last, expectedEpoch: k.activeEpoch);
      expect(c.readPages(c.khatmas.single), isEmpty);
      expect(c.lastRead(c.khatmas.single), isNull);
    },
  );
  test(
    'future plan and unscheduled habit never record; captured account cannot receive a late write',
    () async {
      final h = ReligiousHabit(
        id: operationId(),
        title: 'غدًا',
        weekdays: [DateTime.monday],
      );
      await c.saveHabit(h);
      await c.countHabit(h.id);
      expect(c.habitCount(h), 0);
      final k = QuranKhatma(
        id: operationId(),
        title: 'مستقبل',
        startDate: '2026-11-01',
        endDate: '2026-11-30',
      );
      await c.saveKhatma(k);
      await c.confirmRead(k.id, repo.byKey['1:7']!);
      expect(c.readPages(k), isEmpty);
      final before = c.history.length;
      quran.account.profile = {'id': 7};
      await c.saveHabit(habit());
      await c.confirmRead(k.id, repo.verses.last);
      expect(c.available, false);
      expect((await store.events('guest')).length, before);
      expect(await store.entities('account.7'), isEmpty);
    },
  );
  test(
    'reopening a real local file retains typed plans, icons, reminders, counters and original guest scope',
    () async {
      final folder = Directory.systemTemp.createTempSync('haq-progress-');
      final path = '${folder.path}/progress.sqlite';
      final h = habit(),
          k = QuranKhatma(
            id: operationId(),
            title: 'ختمة محفوظة',
            startDate: c.day,
            endDate: '2026-11-23',
            epoch: operationId(),
            archived: false,
            reminderMinutes: 1245,
          );
      var disk = await ReligiousActivityStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
      );
      var owner = await ReligiousActivityController.open(
        quran,
        store: disk,
        enableSync: false,
      );
      var progress = await ProgressController.open(
        owner,
        repo,
        clock: () => now,
      );
      await progress.saveHabit(h);
      await progress.saveKhatma(k);
      await progress.countHabit(h.id);
      await progress.confirmRead(k.id, repo.byKey['1:7']!);
      final device = await disk.deviceId;
      await progress.flush();
      progress.dispose();
      owner.dispose();
      await disk.close();
      disk = await ReligiousActivityStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
      );
      owner = await ReligiousActivityController.open(
        quran,
        store: disk,
        enableSync: false,
      );
      progress = await ProgressController.open(owner, repo, clock: () => now);
      expect(progress.habits.single.toJson(), h.toJson());
      expect(progress.khatmas.single.toJson(), k.toJson());
      expect(progress.habitCount(h), 1);
      expect(progress.readPages(k), {1});
      expect(await disk.deviceId, device);
      expect(await disk.entities('account.7'), isEmpty);
      progress.dispose();
      owner.dispose();
      await disk.close();
      // Only remove the freshly created, fixed-prefix temporary directory.
      final resolved = folder.absolute.path;
      expect(resolved.startsWith(Directory.systemTemp.absolute.path), true);
      await folder.delete(recursive: true);
    },
  );
}
