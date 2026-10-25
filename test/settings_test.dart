import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/features/adhkar/data/adhkar_repository.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/data/quran_sync.dart';
import 'package:haq_app/features/religious_activity/data/activity_controller.dart';
import 'package:haq_app/features/religious_activity/data/activity_models.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'package:haq_app/features/settings/data/app_settings.dart';
import 'package:haq_app/features/settings/data/reminder_controller.dart';
import 'package:haq_app/features/settings/data/reminder_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late SharedPreferences prefs;
  late AppSettings settings;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    settings = AppSettings(prefs, 'guest');
  });
  tearDown(() => settings.dispose());
  test('fresh install never enables or requests notifications implicitly', () {
    expect(settings.flag('enabled'), false);
    expect(settings.flag('smart'), false);
    expect(reminderPlan(settings, [], []), isEmpty);
  });
  test(
    'accepted writes finish in their original scope even if the page or account closes immediately',
    () async {
      final closing = AppSettings(prefs, 'account.91');
      final pending = [
        closing.set('morning', true),
        closing.set('morning.time', 500),
      ];
      closing.dispose();
      await Future.wait(pending);
      final reopened = AppSettings(prefs, 'account.91');
      expect(reopened.flag('morning'), true);
      expect(reopened.time('morning'), 500);
      expect(settings.flag('morning'), false);
      reopened.dispose();
    },
  );
  test(
    'concurrent changes serialize durably and reopen without losing other preferences',
    () async {
      await prefs.setString('quran.settings', 'preserve');
      await prefs.setString('sakinah.settings.guest', 'preserve');
      await Future.wait([
        settings.set('morning', true),
        settings.set('morning.time', 371),
        settings.set('snooze', 30),
      ]);
      await prefs.reload();
      final reopened = AppSettings(prefs, 'guest');
      expect(reopened.flag('morning'), true);
      expect(reopened.time('morning'), 371);
      expect(reopened.number('snooze', 10), 30);
      expect(prefs.getString('quran.settings'), 'preserve');
      expect(prefs.getString('sakinah.settings.guest'), 'preserve');
      reopened.dispose();
    },
  );
  test(
    'guest and accounts have isolated settings; reset preserves religious data',
    () async {
      await settings.set('enabled', true);
      final account = AppSettings(prefs, 'account.42');
      expect(account.flag('enabled'), false);
      await account.set('hijriOffset', 3);
      await prefs.setString('religious.state.v1.guest', 'retained');
      await settings.reset();
      expect(settings.flag('enabled'), false);
      expect(account.number('hijriOffset', 0), 3);
      expect(prefs.getString('religious.state.v1.guest'), 'retained');
      account.dispose();
    },
  );
  test(
    'invalid values are rejected; damaged persisted values do not leak into native plan',
    () async {
      for (final (key, value) in [
        ('morning.time', 1440),
        ('hijriOffset', 4),
        ('frequency', 0),
        ('snooze', 5),
        ('fontSize', 100),
        ('content', ['bad/id']),
        ('type', 'fake'),
      ]) {
        expect(() => settings.set(key, value), throwsArgumentError);
      }
      await prefs.setString(
        'app.settings.v1.account.1',
        '{"frequency":-30,"type":"fake","content":["dhikr:1"],"sound":"yes"}',
      );
      final repaired = AppSettings(prefs, 'account.1');
      expect(repaired.number('frequency', 5), 5);
      expect(repaired.text('type', 'center'), 'center');
      expect(repaired.content, ['dhikr:1']);
      expect(repaired.flag('sound'), true);
      repaired.dispose();
    },
  );
  test('malformed JSON is retained until explicit reset', () async {
    await prefs.setString('app.settings.v1.account.2', '{broken');
    final corrupt = AppSettings(prefs, 'account.2');
    await corrupt.set('enabled', true);
    expect(corrupt.error, isNotNull);
    expect(prefs.getString('app.settings.v1.account.2'), '{broken');
    await corrupt.reset();
    expect(corrupt.error, isNull);
    await corrupt.set('enabled', true);
    expect(corrupt.flag('enabled'), true);
    corrupt.dispose();
  });
  test(
    'daily weekly and smart jobs retain stable identities across edits and toggles',
    () async {
      await settings.set('enabled', true);
      await settings.set('morning', true);
      await settings.set('friday', true);
      await settings.set('smart', true);
      expect(
        reminderPlan(settings, [], []).length,
        2,
      ); // No selected smart text.
      final before = reminderPlan(settings, [], []).map((e) => e.id).toList();
      await settings.set('morning.time', 720);
      final plan = reminderPlan(settings, [], []);
      expect(plan.map((e) => e.id), before);
      expect(plan.firstWhere((e) => e.title == 'أذكار الصباح').minute, 720);
      expect(plan.firstWhere((e) => e.weekday != null).weekday, 5);
      await settings.set('content', ['dhikr:1']);
      expect(
        reminderPlan(settings, [], []).where((e) => e.interval != null).length,
        1,
      );
      await settings.set('enabled', false);
      expect(reminderPlan(settings, [], []), isEmpty);
    },
  );
  test(
    'khatma schedule expires, archives and completes by cycle, and can be cancelled',
    () async {
      await settings.set('enabled', true);
      final id = operationId(), epoch = operationId();
      QuranKhatma khatma({bool? archived, int? time = 480}) => QuranKhatma(
        id: id,
        title: 'ختمتي',
        startDate: '2026-10-26',
        endDate: '2026-11-26',
        epoch: epoch,
        archived: archived,
        reminderMinutes: time,
      );
      final plan = reminderPlan(settings, [khatma()], []);
      expect(plan.single.start, '2026-10-26');
      expect(plan.single.end, '2026-11-26');
      expect(reminderPlan(settings, [khatma(archived: true)], []), isEmpty);
      expect(reminderPlan(settings, [khatma(time: null)], []), isEmpty);
      final event = ReligiousActivityEvent(
        id: operationId(),
        deviceId: operationId(),
        sessionId: id,
        subjectId: 'khatma:complete',
        epoch: epoch,
        kind: ActivityKind.complete,
        amount: 0,
        occurredAt: DateTime.utc(2026, 10, 26),
        day: '2026-10-26',
        utcOffsetMinutes: 120,
      );
      expect(reminderPlan(settings, [khatma()], [event]), isEmpty);
      final restarted = QuranKhatma(
        id: id,
        title: 'دورة جديدة',
        startDate: '2026-10-26',
        endDate: '2026-11-26',
        epoch: operationId(),
        reminderMinutes: 480,
      );
      expect(
        reminderPlan(settings, [restarted], [event]).single.id,
        isNot(plan.single.id),
      );
    },
  );
  test(
    'time appearance persists, crosses midnight, and manual mode overrides schedule',
    () async {
      var now = DateTime(2026, 10, 26, 5, 59);
      final appearance = AppAppearance(prefs, clock: () => now);
      await appearance.setTimed(true);
      expect(appearance.effectiveMode, ThemeMode.dark);
      now = DateTime(2026, 10, 26, 6);
      expect(appearance.effectiveMode, ThemeMode.light);
      await appearance.setSchedule(day: 1200, night: 360);
      expect(appearance.effectiveMode, ThemeMode.dark);
      now = DateTime(2026, 10, 26, 23);
      expect(appearance.effectiveMode, ThemeMode.light);
      final reopened = AppAppearance(prefs, clock: () => now);
      expect(reopened.timed, true);
      expect(reopened.dayStart, 1200);
      await reopened.setMode(ThemeMode.system);
      expect(reopened.timed, false);
      expect(reopened.effectiveMode, ThemeMode.system);
      expect(
        () => appearance.setSchedule(day: 500, night: 500),
        throwsArgumentError,
      );
      appearance.dispose();
      reopened.dispose();
    },
  );

  group('native-channel reconciliation using real account-scoped SQLite', () {
    const channel = MethodChannel('test.haq.reminders');
    late QuranController quran;
    late ReligiousActivityStore store;
    late ReligiousActivityController activity;
    late ReminderController c;
    late List<MethodCall> calls;
    late bool reject;
    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      final repo = QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      quran = QuranController(initialRepository: repo, preferences: prefs);
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
      calls = [];
      reject = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'replace' && reject) {
              throw PlatformException(code: 'schedule');
            }
            if (call.method == 'status') {
              return {
                'platform': 'android',
                'allowed': false,
                'overlay': false,
                'pending': 0,
              };
            }
            return null;
          });
      final catalog = AdhkarRepository.fromJson(
        jsonDecode(File('assets/religious/adhkar.json').readAsStringSync())
            as Map<String, dynamic>,
        repo,
      );
      c = ReminderController(activity, catalog, channel: channel);
      await c.initialize();
    });
    tearDown(() async {
      await c.flush();
      c.dispose();
      activity.dispose();
      quran.dispose();
      await store.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    test(
      'startup never prompts; denial remains real and repeated refresh is idempotent',
      () async {
        expect(calls.any((e) => e.method == 'requestPermission'), false);
        expect(c.device.allowed, false);
        final before = calls.where((e) => e.method == 'replace').length;
        await c.reconcile();
        await c.reconcile();
        expect(calls.where((e) => e.method == 'replace').length, before);
        expect(c.content.length, greaterThan(200));
      },
    );
    test(
      'saving settings and active khatma produces a replacement, archive cancels it',
      () async {
        await c.settings.set('enabled', true);
        final k = QuranKhatma(
          id: operationId(),
          title: 'ختمتي',
          startDate: '2026-10-26',
          endDate: '2026-10-30',
          reminderMinutes: 480,
        );
        await activity.save(k);
        await c.reconcile();
        final payload =
            calls.lastWhere((e) => e.method == 'replace').arguments as Map;
        expect((payload['jobs'] as List).single['title'], 'ورد الختمة');
        await activity.save(
          QuranKhatma(
            id: k.id,
            title: k.title,
            startDate: k.startDate,
            endDate: k.endDate,
            archived: true,
          ),
        );
        await c.reconcile();
        expect(
          (calls.lastWhere((e) => e.method == 'replace').arguments
              as Map)['jobs'],
          isEmpty,
        );
      },
    );
    test(
      'native failure preserves durable settings and retries rather than claiming success',
      () async {
        reject = true;
        await c.settings.set('enabled', true);
        await c.settings.set('morning', true);
        await c.reconcile();
        expect(c.error, isNotNull);
        expect(c.settings.flag('morning'), true);
        reject = false;
        await c.reconcile();
        expect(c.error, isNull);
      },
    );
    test(
      'switch account clears old scope before replacing private content',
      () async {
        final personal = PersonalDhikr(
          id: operationId(),
          text: 'نص شخصي للاختبار',
          target: 1,
        );
        await activity.save(personal);
        await c.settings.set('enabled', true);
        await c.settings.set('smart', true);
        await c.settings.set('content', [personal.id]);
        await c.reconcile();
        expect(
          (calls.lastWhere((e) => e.method == 'replace').arguments
              as Map)['smartItems'],
          [personal.text],
        );
        quran.account.profile = {'id': 42};
        activity.changed(activity.scope);
        await c.reconcile();
        expect(c.settings.scope, 'account.42');
        expect(c.settings.flag('enabled'), false);
        final latest =
            calls.lastWhere((e) => e.method == 'replace').arguments as Map;
        expect(latest['scope'], 'account.42');
        expect(latest['smartItems'], isEmpty);
        expect(latest['jobs'], isEmpty);
        expect(c.content.containsKey(personal.id), false);
      },
    );
    test(
      'unsupported native platform reports unavailable without losing configuration',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await c.settings.set('enabled', true);
        await c.reconcile();
        expect(c.device.supported, false);
        expect(c.settings.flag('enabled'), true);
      },
    );
  });
}
