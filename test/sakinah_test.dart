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
import 'package:haq_app/features/sakinah/data/breathing_session.dart';
import 'package:haq_app/features/sakinah/data/sakinah_record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  var now = Duration.zero;
  BreathingSession engine(BreathingPattern pattern, {int minutes = 1}) =>
      BreathingSession(
        pattern: pattern,
        duration: Duration(minutes: minutes),
        monotonicClock: () => now,
      );
  setUp(() => now = Duration.zero);
  test(
    'patterns reject invalid custom holds and durations, and all reference phases are exact',
    () {
      expect(() => BreathingPattern(0, 0, 4, 0), throwsFormatException);
      expect(() => BreathingPattern(4, -1, 4, 0), throwsFormatException);
      expect(() => BreathingPattern(4, 0, 21, 0), throwsFormatException);
      expect(
        () => engine(BreathingPattern.box, minutes: 2),
        throwsFormatException,
      );
      final s = engine(BreathingPattern.relaxing)..start();
      now = const Duration(milliseconds: 2999);
      s.tick();
      expect(s.status, BreathingStatus.preparing);
      expect(s.elapsed, Duration.zero);
      now = const Duration(seconds: 3);
      s.tick();
      expect(s.current.phase, BreathingPhase.inhale);
      now = const Duration(seconds: 7);
      s.tick();
      expect(s.current.phase, BreathingPhase.holdIn);
      now = const Duration(seconds: 14);
      s.tick();
      expect(s.current.phase, BreathingPhase.exhale);
      now = const Duration(seconds: 22);
      s.tick();
      expect(s.current.phase, BreathingPhase.inhale);
      expect(s.cycles, 1);
      s.dispose();
    },
  );
  for (final minutes in [1, 3, 5]) {
    test(
      '$minutes minute session excludes preparation, skipped frames and paused background time',
      () {
        final s = engine(BreathingPattern.box, minutes: minutes)..start();
        now = const Duration(seconds: 13);
        s.tick();
        expect(s.elapsed.inSeconds, 10);
        s.pause();
        final progress = s.progress, phase = s.current;
        now += const Duration(hours: 2);
        s.tick();
        expect(s.progress, progress);
        expect(s.current, phase);
        s.resume();
        now += Duration(seconds: minutes * 60 - 11);
        s.tick();
        expect(s.status, BreathingStatus.running);
        expect(s.remainingSeconds, 1);
        now += const Duration(seconds: 1);
        s.tick();
        expect(s.status, BreathingStatus.completed);
        expect(s.elapsed, Duration(minutes: minutes));
        expect(s.progress, 1);
        s.cancel();
        s.start();
        s.resume();
        expect(s.status, BreathingStatus.completed);
        s.dispose();
      },
    );
  }
  test(
    'zero holds are skipped and preparation pause resumes the exact remaining fraction',
    () {
      final s = engine(BreathingPattern.coherent)..start();
      now = const Duration(milliseconds: 1500);
      s.pause();
      now += const Duration(hours: 1);
      s.tick();
      expect(s.elapsed, Duration.zero);
      s.resume();
      now += const Duration(milliseconds: 1499);
      s.tick();
      expect(s.status, BreathingStatus.preparing);
      now += const Duration(milliseconds: 1);
      s.tick();
      expect(s.status, BreathingStatus.running);
      now += const Duration(seconds: 5);
      s.tick();
      expect(s.current.phase, BreathingPhase.exhale);
      now += const Duration(seconds: 5);
      s.tick();
      expect(s.current.phase, BreathingPhase.inhale);
      expect(s.cycles, 1);
      s.cancel();
      expect(s.status, BreathingStatus.cancelled);
      expect(s.elapsed.inSeconds, 10);
      now += const Duration(minutes: 5);
      s.tick();
      expect(s.elapsed.inSeconds, 10);
      s.dispose();
    },
  );
  test(
    'completed and cancelled records retry with fixed IDs, aggregate actual seconds and keep scopes',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final repo = QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final quran = QuranController(
        initialRepository: repo,
        preferences: await SharedPreferences.getInstance(),
      );
      await quran.load();
      final store = await ReligiousActivityStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      final activity = await ReligiousActivityController.open(
        quran,
        store: store,
        enableSync: false,
      );
      final complete = engine(BreathingPattern.box)..start();
      now = const Duration(seconds: 63);
      complete.tick();
      final record = await SakinahRecord.create(
        activity,
        'guest',
        operationId(),
        'peace',
        complete,
      );
      // A previous local transaction committed, but its caller lost the result.
      await store.apply('guest', events: record.events);
      expect(await record.save(), true);
      expect(await record.save(), true);
      var events = await store.events('guest');
      expect(events.length, 2);
      expect(
        events.where((e) => e.kind == ActivityKind.breathing).single.amount,
        60,
      );
      final partial = engine(BreathingPattern.coherent)..start();
      now += const Duration(seconds: 8);
      partial.cancel();
      final cancelled = await SakinahRecord.create(
        activity,
        'guest',
        operationId(),
        'gratitude',
        partial,
      );
      await cancelled.save();
      events = await store.events('guest');
      expect(events.length, 3);
      expect(events.last.amount, 5);
      expect(events.where((e) => e.kind == ActivityKind.complete).length, 1);
      final progress = await ProgressController.open(activity, repo);
      expect(progress.totals().breathingSeconds, 65);
      final pending = await SakinahRecord.create(
        activity,
        'guest',
        operationId(),
        'trust',
        partial,
      );
      quran.account.profile = {'id': 7};
      expect(await pending.save(), false);
      expect(await store.events('account.7'), isEmpty);
      expect((await store.events('guest')).length, 3);
      progress.dispose();
      complete.dispose();
      partial.dispose();
      activity.dispose();
      quran.dispose();
      await store.close();
    },
  );
  test(
    'all five closing selections use existing complete canonical Quran verses',
    () {
      final repo = QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      expect(sakinahPaths.length, 5);
      expect(sakinahNames.length, 5);
      for (final keys in sakinahVerses) {
        for (final key in keys) {
          expect(repo.byKey[key]?.text, isNotEmpty);
        }
      }
      expect(sakinahVerses[1], ['13:28']);
      expect(sakinahVerses[2], ['14:7', '27:19']);
    },
  );
}
