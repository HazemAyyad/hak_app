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
import 'package:haq_app/features/progress/data/progress_controller.dart';
import 'package:haq_app/features/progress/presentation/progress_page.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/data/quran_sync.dart';
import 'package:haq_app/features/religious_activity/data/activity_controller.dart';
import 'package:haq_app/features/religious_activity/data/activity_models.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'package:haq_app/features/religious_content/data/religious_catalog.dart';
import 'package:haq_app/features/religious_content/data/religious_controller.dart';
import 'package:haq_app/main.dart';
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
  late ProgressController c;
  late AppAppearance appearance;
  late ReligiousHabit habit;
  late QuranKhatma khatma;
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
      ('Tajawal', 'assets/fonts/Tajawal-Regular.ttf'),
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
      'assets/navigation/more_header.png',
    ).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((_, _) {
      if (!ready.isCompleted) ready.complete();
    });
    stream.addListener(listener);
    await ready.future;
    stream.removeListener(listener);
  });
  setUp(() async {
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
    c = await ProgressController.open(activity, repo);
    habit = ReligiousHabit(
      id: operationId(),
      title: 'قراءة القرآن',
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      target: 1,
      icon: 'book',
      epoch: operationId(),
    );
    khatma = QuranKhatma(
      id: operationId(),
      title: 'رحلتي مع القرآن',
      startDate: c.day,
      endDate: progressDay(civilDate(c.day).add(const Duration(days: 29))),
      epoch: operationId(),
    );
    await c.saveHabit(habit);
    await c.saveKhatma(khatma);
  });
  tearDown(() async {
    c.dispose();
    religious.dispose();
    quran.dispose();
    appearance.dispose();
    await Future<void>.delayed(Duration.zero);
    if (!activity.syncClient.disposed) activity.dispose();
    await store.close();
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 8)),
      );
    }
  }

  Future<void> pump(
    WidgetTester tester,
    ProgressSection section, {
    bool dark = false,
    bool app = false,
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
          child: app
              ? HaqApp(
                  showStartup: false,
                  appearance: appearance,
                  quranController: quran,
                  religiousController: religious,
                )
              : MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(
                    fontFamily: 'QuranUI',
                    brightness: dark ? Brightness.dark : Brightness.light,
                    colorSchemeSeed: const Color(0xFF2A8C82),
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(1.3)),
                    child: child!,
                  ),
                  home: ProgressPage(controller: religious, section: section),
                ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull, reason: name);
    await tester.runAsync(() async {
      final boundary =
          preview.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/progress-preview/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
      'khatma, habits and statistics fit 320px and 130 percent ${dark ? 'dark' : 'light'}',
      (tester) async {
        for (final section in ProgressSection.values) {
          await pump(tester, section, dark: dark);
          await capture(tester, '${section.name}-${dark ? 'dark' : 'light'}');
          await tester.pumpWidget(const SizedBox());
          await settle(tester);
        }
      },
    );
  }
  testWidgets(
    'habit counts once at goal, undo works and form persists custom Arabic target and icon',
    (tester) async {
      await pump(tester, ProgressSection.habits);
      final count = find.byKey(ValueKey('habit-count-${habit.id}'));
      await tester.ensureVisible(count);
      await tester.tap(count);
      await settle(tester);
      await tester.runAsync(c.refresh);
      expect(c.habitCount(habit), 1);
      expect(tester.widget<FilledButton>(count).onPressed, isNull);
      await tester.tap(find.byTooltip('تراجع'));
      await settle(tester);
      await tester.runAsync(c.refresh);
      expect(c.habitCount(habit), 0);
      await tester.ensureVisible(find.text('إضافة عادة'));
      await tester.tap(find.text('إضافة عادة'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('habit-title')),
        'ذكر يومي',
      );
      await tester.enterText(find.byKey(const ValueKey('habit-target')), '٣٣');
      await tester.ensureVisible(find.text('مسبحة'));
      await settle(tester);
      await tester.tap(find.text('مسبحة'));
      await settle(tester);
      await tester.ensureVisible(find.text('حفظ العادة'));
      await settle(tester);
      await tester.tap(find.text('حفظ العادة'));
      await settle(tester);
      await tester.runAsync(c.refresh);
      expect(c.habits.where((h) => h.title == 'ذكر يومي').single.target, 33);
      expect(c.habits.where((h) => h.title == 'ذكر يومي').single.icon, 'beads');
      await capture(tester, 'habits-saved');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'reader exit does not count a page and explicit last ayah confirmation survives return',
    (tester) async {
      await pump(tester, ProgressSection.khatma);
      await tester.tap(find.text(khatma.title));
      await settle(tester);
      await tester.ensureVisible(find.text('متابعة وردي'));
      await tester.tap(find.text('متابعة وردي'));
      await settle(tester);
      expect(find.text('ورد الختمة'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('قبل مغادرة الورد'), findsOneWidget);
      await tester.tap(find.text('تأكيد'));
      await settle(tester);
      await tester.runAsync(c.refresh);
      expect(c.readPages(khatma), isEmpty);
      await tester.ensureVisible(find.text('متابعة وردي'));
      await tester.tap(find.text('متابعة وردي'));
      await settle(tester);
      await tester.tap(find.text('تحديد آخر آية قرأتها'));
      await settle(tester);
      expect(find.text('قرأت حتى هذه الآية؟'), findsOneWidget);
      await tester.tap(find.text('تأكيد'));
      await settle(tester);
      await tester.runAsync(c.refresh);
      expect(c.lastRead(khatma), isNotNull);
      await capture(tester, 'khatma-reader-confirmed');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'home journey reads real progress and opens habit route without changing card structure',
    (tester) async {
      await tester.runAsync(() async {
        await c.countHabit(habit.id);
        await c.confirmRead(khatma.id, repo.byKey['1:7']!);
      });
      await pump(tester, ProgressSection.habits, app: true);
      await tester.scrollUntilVisible(
        find.text('رحلتك اليوم'),
        450,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      expect(find.text('اليوم: 1 من 1'), findsOneWidget);
      await tester.ensureVisible(find.text('العادات'));
      await tester.tap(find.text('العادات'));
      await settle(tester);
      expect(find.byType(ProgressPage), findsOneWidget);
      expect(find.text('عاداتي'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'new khatma form, plan editing and statistics detail remain usable on enlarged phone',
    (tester) async {
      await pump(tester, ProgressSection.khatma);
      await tester.tap(find.text('إنشاء ختمة جديدة'));
      await settle(tester);
      await tester.enterText(
        find.byType(TextFormField).first,
        'ختمة عشرة أيام',
      );
      await tester.ensureVisible(find.text('عشرة أيام'));
      await settle(tester);
      await tester.tap(find.text('عشرة أيام'));
      await settle(tester);
      await capture(tester, 'khatma-create');
      await tester.ensureVisible(find.text('حفظ الخطة'));
      await settle(tester);
      await tester.tap(find.text('حفظ الخطة'));
      await settle(tester);
      await tester.runAsync(c.refresh);
      final created = c.khatmas
          .where((k) => k.title == 'ختمة عشرة أيام')
          .single;
      expect(khatmaPlan(created).length, 10);
      await tester.ensureVisible(find.text(created.title));
      await settle(tester);
      await tester.tap(find.text(created.title));
      await settle(tester);
      await capture(tester, 'khatma-details');
      await tester.scrollUntilVisible(
        find.text('تعديل الخطة'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('تعديل الخطة'));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField).last, '١٥');
      await tester.ensureVisible(find.text('حفظ الخطة'));
      await settle(tester);
      await tester.tap(find.text('حفظ الخطة'));
      await settle(tester);
      await tester.runAsync(c.refresh);
      expect(
        khatmaPlan(c.khatmas.where((k) => k.id == created.id).single).length,
        15,
      );
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      await pump(tester, ProgressSection.statistics);
      await tester.tap(find.text('الأذكار'));
      await settle(tester);
      expect(find.text('تفاصيل الأذكار'), findsOneWidget);
      expect(find.textContaining('أذكار الصباح: 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'switching account closes private habit editor and its confirmation dialog',
    (tester) async {
      await pump(tester, ProgressSection.habits);
      await tester.ensureVisible(find.byTooltip('تعديل العادة'));
      await settle(tester);
      await tester.tap(find.byTooltip('تعديل العادة'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('habit-title')),
        'اسم خاص لم يحفظ',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester);
      await tester.ensureVisible(find.text('حذف العادة'));
      await settle(tester);
      await tester.tap(find.text('حذف العادة'));
      await settle(tester);
      expect(find.text('حذف العادة؟'), findsOneWidget);
      quran.account.profile = {'id': 7};
      activity.changed('account.7');
      await settle(tester);
      expect(find.text('حذف العادة؟'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('اسم خاص لم يحفظ'), findsNothing);
      expect(find.text(habit.title), findsNothing);
      final values = await tester.runAsync(() => store.entities('account.7'));
      expect(values, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
