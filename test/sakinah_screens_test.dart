import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/religious_activity/data/activity_controller.dart';
import 'package:haq_app/features/religious_activity/data/activity_models.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'package:haq_app/features/religious_content/data/religious_catalog.dart';
import 'package:haq_app/features/religious_content/data/religious_controller.dart';
import 'package:haq_app/features/sakinah/presentation/sakinah_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late QuranRepository repo;
  late ReligiousCatalog catalog;
  late QuranController quran;
  late ReligiousController religious;
  late ReligiousActivityStore store;
  late ReligiousActivityController activity;
  late AppAppearance appearance;
  late Duration now;
  final preview = GlobalKey();
  setUpAll(() async {
    repo = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    catalog = await ReligiousCatalog.load();
    for (final (family, path) in [
      ('QuranUI', 'assets/fonts/Cairo.ttf'),
      ('AmiriQuran', 'assets/fonts/AmiriQuran.ttf'),
      (
        'MaterialIcons',
        'C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
    final ready = Completer<void>();
    final stream = const AssetImage(
      'assets/navigation/sakinah.png',
    ).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((_, _) {
      if (!ready.isCompleted) ready.complete();
    });
    stream.addListener(listener);
    await ready.future;
    stream.removeListener(listener);
  });
  setUp(() async {
    now = Duration.zero;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    appearance = AppAppearance(prefs);
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
    religious = ReligiousController(
      quran: quran,
      initialCatalog: catalog,
      activityFactory: () async => activity,
    );
    await religious.load();
  });
  tearDown(() async {
    religious.dispose();
    quran.dispose();
    appearance.dispose();
    await Future<void>.delayed(Duration.zero);
    if (!activity.syncClient.disposed) activity.dispose();
    await store.close();
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 8)),
      );
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    bool dark = false,
    bool reduced = false,
  }) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await appearance.setMode(dark ? ThemeMode.dark : ThemeMode.light);
    await tester.pumpWidget(
      AppearanceScope(
        controller: appearance,
        child: RepaintBoundary(
          key: preview,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'QuranUI',
              brightness: dark ? Brightness.dark : Brightness.light,
              colorSchemeSeed: const Color(0xFF2A8C82),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(1.3),
                disableAnimations: reduced,
              ),
              child: child!,
            ),
            home: SakinahPage(controller: religious, monotonicClock: () => now),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        250,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await tester.ensureVisible(finder);
    await settle(tester);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> setup(WidgetTester tester, String path) async =>
      tapVisible(tester, find.widgetWithText(ListTile, path));
  Future<void> start(WidgetTester tester) async =>
      tapVisible(tester, find.text('ابدأ الجلسة'));
  Future<void> capture(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull, reason: name);
    await tester.runAsync(() async {
      final boundary =
          preview.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await boundary.toImage(pixelRatio: 1.5),
          file = File('build/sakinah-preview/$name.png');
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
      'five paths and custom timings fit narrow enlarged ${dark ? 'dark' : 'light'}',
      (tester) async {
        await pump(tester, dark: dark);
        await capture(tester, 'paths-${dark ? 'dark' : 'light'}');
        for (final path in ['سكينة', 'طمأنينة', 'شكر', 'استغفار', 'توكل']) {
          await setup(tester, path);
          await tapVisible(tester, find.text('نمط مخصص'));
          expect(find.byKey(const ValueKey('breath-minus-0')), findsOneWidget);
          await tapVisible(tester, find.byKey(const ValueKey('breath-plus-0')));
          if (path == 'سكينة') {
            await capture(tester, 'custom-${dark ? 'dark' : 'light'}');
          }
          await tester.binding.handlePopRoute();
          await settle(tester);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'clock survives rebuild; manual and lifecycle pause exclude time, then completion saves once',
    (tester) async {
      await pump(tester, reduced: true);
      await setup(tester, 'طمأنينة');
      await start(tester);
      expect(find.text('استعد بهدوء'), findsOneWidget);
      final vibration = find.byKey(const ValueKey('breathing-haptic'));
      await tapVisible(tester, vibration);
      expect(tester.widget<FilterChip>(vibration).selected, true);
      await tapVisible(tester, vibration);
      expect(tester.widget<FilterChip>(vibration).selected, false);
      now = const Duration(seconds: 7);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('حبس'), findsOneWidget);
      await capture(tester, 'hold-reduced');
      await tapVisible(tester, find.byKey(const ValueKey('breathing-pause')));
      expect(find.text('متوقف مؤقتًا'), findsOneWidget);
      now += const Duration(minutes: 10);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('00:56'), findsOneWidget);
      await capture(tester, 'paused');
      await tapVisible(tester, find.byKey(const ValueKey('breathing-pause')));
      now += const Duration(seconds: 7);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('زفير'), findsOneWidget);
      await capture(tester, 'exhale');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      now += const Duration(minutes: 20);
      await tester.pump(const Duration(milliseconds: 100));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(find.text('متوقف مؤقتًا'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('breathing-pause')));
      now += const Duration(seconds: 49);
      await settle(tester);
      expect(find.text('اكتملت الجلسة'), findsOneWidget);
      final events = await tester.runAsync(() => store.events('guest'));
      expect(
        events!.where((e) => e.kind == ActivityKind.breathing).single.amount,
        60,
      );
      expect(events.where((e) => e.kind == ActivityKind.complete).length, 1);
      await capture(tester, 'completed');
      await tester.pump(const Duration(seconds: 10));
      expect((await tester.runAsync(() => store.events('guest')))!.length, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'back requires confirmation and early end is partial; opting out stores nothing',
    (tester) async {
      await pump(tester);
      await setup(tester, 'شكر');
      await start(tester);
      now = const Duration(seconds: 13);
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('إنهاء الجلسة مبكرًا؟'), findsOneWidget);
      await tester.tap(find.text('متابعة الجلسة'));
      await settle(tester);
      now += const Duration(seconds: 5);
      await settle(tester);
      await tapVisible(tester, find.text('إنهاء الجلسة'));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'إنهاء الجلسة'),
        ),
      );
      await settle(tester);
      expect(find.text('انتهت الجلسة'), findsOneWidget);
      final events = await tester.runAsync(() => store.events('guest'));
      expect(
        events!.where((e) => e.kind == ActivityKind.breathing).single.amount,
        15,
      );
      expect(events.where((e) => e.kind == ActivityKind.complete), isEmpty);
      await capture(tester, 'cancelled');
      await tapVisible(tester, find.widgetWithText(FilledButton, 'تم'));
      await settle(tester);
      await tapVisible(
        tester,
        find.widgetWithText(SwitchListTile, 'حفظ مدة الجلسة في سجلي'),
      );
      await start(tester);
      now += const Duration(seconds: 63);
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('لم تحفظ هذه الجلسة حسب اختيارك.'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('لم تحفظ هذه الجلسة حسب اختيارك.'), findsOneWidget);
      expect((await tester.runAsync(() => store.events('guest')))!.length, 1);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'تم'));
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tapVisible(tester, find.text('سجل الجلسات'));
      expect(find.textContaining('15 ثانية'), findsOneWidget);
      expect(find.textContaining('انتهت مبكرًا'), findsOneWidget);
      await capture(tester, 'history');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'account change closes running session and dialog without recording into new scope',
    (tester) async {
      await pump(tester);
      await setup(tester, 'توكل');
      await start(tester);
      now = const Duration(seconds: 8);
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('إنهاء الجلسة مبكرًا؟'), findsOneWidget);
      quran.account.profile = {'id': 7};
      activity.changed('account.7');
      await settle(tester);
      expect(find.text('إنهاء الجلسة مبكرًا؟'), findsNothing);
      expect(find.byKey(const ValueKey('breathing-pause')), findsNothing);
      expect(await tester.runAsync(() => store.events('account.7')), isEmpty);
      expect(await tester.runAsync(() => store.events('guest')), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'setup information and three-minute coherent choice persist for this account',
    (tester) async {
      await pump(tester, dark: true);
      await setup(tester, 'سكينة');
      await tapVisible(tester, find.text('عن النمط').first);
      expect(
        find.textContaining('تتجاوز الجلسة أي مرحلة مدتها صفر'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'تم'));
      await settle(tester);
      await tapVisible(tester, find.text('التنفّس المتناغم'));
      await tapVisible(tester, find.text('3 دقائق'));
      await tapVisible(
        tester,
        find.widgetWithText(SwitchListTile, 'تقليل الحركة'),
      );
      await start(tester);
      expect(find.text('03:00'), findsOneWidget);
      final settings =
          jsonDecode(quran.preferences!.getString('sakinah.settings.guest')!)
              as Map;
      expect(settings['minutes'], 3);
      expect(settings['pattern'], 2);
      expect(settings['reduced'], true);
      expect(
        quran.preferences!.getString('sakinah.settings.account.7'),
        isNull,
      );
      now = const Duration(seconds: 183);
      await settle(tester);
      expect(find.text('اكتملت الجلسة'), findsOneWidget);
      final events = await tester.runAsync(() => store.events('guest'));
      expect(
        events!.where((e) => e.kind == ActivityKind.breathing).single.amount,
        180,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
