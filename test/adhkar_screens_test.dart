import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/main.dart';
import 'package:haq_app/features/adhkar/data/adhkar_repository.dart';
import 'package:haq_app/features/adhkar/data/personal_adhkar.dart';
import 'package:haq_app/features/adhkar/data/adhkar_volume_controls.dart';
import 'package:haq_app/features/adhkar/presentation/adhkar_host.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/religious_activity/data/activity_controller.dart';
import 'package:haq_app/features/religious_activity/data/activity_models.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'package:haq_app/features/religious_content/data/religious_catalog.dart';
import 'package:haq_app/features/religious_content/data/religious_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late QuranRepository quranData;
  late AdhkarRepository source;
  late ReligiousCatalog catalog;
  late QuranController quran;
  late ReligiousController religious;
  late ReligiousActivityController activity;
  late ReligiousActivityStore store;
  late AppAppearance appearance;
  final host = GlobalKey<AdhkarSectionPageState>(), preview = GlobalKey();
  late ValueNotifier<bool> visible;
  setUpAll(() async {
    quranData = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    // Exercise the actual bundled asset loader outside the widget fake clock.
    source = await AdhkarRepository.load(quranData);
    final imageStream = const AssetImage(
      'assets/navigation/more_header.png',
    ).resolve(ImageConfiguration.empty);
    final ready = Completer<void>();
    final listener = ImageStreamListener((_, _) {
      if (!ready.isCompleted) ready.complete();
    }, onError: (Object e, StackTrace? s) => ready.completeError(e, s));
    imageStream.addListener(listener);
    await ready.future;
    imageStream.removeListener(listener);
    catalog = ReligiousCatalog.fromJson(
      jsonDecode(File('assets/religious/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    for (final (family, path) in [
      ('QuranUI', 'assets/fonts/Cairo.ttf'),
      ('Tajawal', 'assets/fonts/Tajawal-Regular.ttf'),
      ('AmiriQuran', 'assets/fonts/AmiriQuran.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
    final icons = File(
      'C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(icons.readAsBytesSync())),
          ))
          .load();
    }
  });
  setUp(() async {
    visible = ValueNotifier(true);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    appearance = AppAppearance(prefs);
    quran = QuranController(initialRepository: quranData, preferences: prefs);
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
      initialAdhkarCatalog: source,
      activityFactory: () async => activity,
    );
    await religious.load();
  });
  tearDown(() async {
    visible.dispose();
    religious.dispose();
    quran.dispose();
    appearance.dispose();
    // ReligiousController disposes its lazy controller after the completed future.
    await Future<void>.delayed(Duration.zero);
    if (!activity.syncClient.disposed) activity.dispose();
    await store.close();
  });
  Future<void> pump(
    WidgetTester tester, {
    double width = 426,
    double scale = 1,
    ThemeMode mode = ThemeMode.light,
    bool fullApp = false,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await appearance.setMode(mode);
    await tester.pumpWidget(
      AppearanceScope(
        controller: appearance,
        child: RepaintBoundary(
          key: preview,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'QuranUI',
              brightness: mode == ThemeMode.dark
                  ? Brightness.dark
                  : Brightness.light,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF278B83),
                brightness: mode == ThemeMode.dark
                    ? Brightness.dark
                    : Brightness.light,
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: fullApp
                ? HomePage(
                    onToggleTheme: () {},
                    quranController: quran,
                    religiousController: religious,
                  )
                : Directionality(
                    textDirection: TextDirection.rtl,
                    child: Scaffold(
                      body: ValueListenableBuilder<bool>(
                        valueListenable: visible,
                        builder: (context, active, _) => AdhkarSectionPage(
                          key: host,
                          controller: religious,
                          onFeature: (_) {},
                          onExit: () {},
                          initialRepository: source,
                          active: active,
                        ),
                      ),
                      bottomNavigationBar: NavigationBar(
                        selectedIndex: 2,
                        destinations: const [
                          NavigationDestination(
                            icon: Icon(Icons.home_outlined),
                            label: 'الرئيسية',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.menu_book_outlined),
                            label: 'القرآن',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.eco_outlined),
                            label: 'الأذكار',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.explore_outlined),
                            label: 'القبلة',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.more_horiz),
                            label: 'المزيد',
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> until(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      if (condition()) {
        await tester.pumpAndSettle();
        return;
      }
    }
    throw TestFailure('UI did not reach the expected state');
  }

  Future<void> tap(
    WidgetTester tester,
    Finder finder, {
    bool Function()? done,
  }) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await until(
      tester,
      done ?? () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (!const bool.fromEnvironment('ADHKAR_PREVIEWS')) return;
    await tester.runAsync(() async {
      final boundary =
          preview.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5),
          folder = Directory('build/adhkar-preview');
      await folder.create(recursive: true);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${folder.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<String> fixture() async {
    await PersonalAdhkar(
      activity,
    ).saveDhikr(text: 'ذكر شخصي للاختبار', target: '٣');
    return (await store.entities(
      'guest',
      kind: PersonalEntityKind.dhikr,
    )).single.key;
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('daily index and no-results ${mode.name}', (tester) async {
      await pump(tester, mode: mode);
      expect(find.byKey(const ValueKey('daily:morning')), findsOneWidget);
      await capture(tester, 'index-${mode.name}');
      await tester.enterText(
        find.byKey(const ValueKey('adhkar-search')),
        'عبارة غير موجودة',
      );
      await tester.pumpAndSettle();
      expect(find.text('لا توجد مجموعات تطابق بحثك'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('reader counter 3 to red zero, undo and exit ${mode.name}', (
      tester,
    ) async {
      final id = await fixture();
      await pump(tester, mode: mode);
      unawaitedForTest(host.currentState!.openGroup('personal:all'));
      final button = find.byKey(ValueKey('count-$id'));
      await until(tester, () => button.evaluate().isNotEmpty);
      await capture(tester, 'reader-3-${mode.name}');
      for (final value in [2, 1, 0]) {
        await tap(
          tester,
          button,
          done: () => find
              .descendant(of: button, matching: find.text('$value'))
              .evaluate()
              .isNotEmpty,
        );
        if (value == 0) {
          await until(
            tester,
            () => find.text('تقبّل الله منك').evaluate().isNotEmpty,
          );
          await tap(tester, find.widgetWithText(FilledButton, 'تم'));
        }
      }
      // The counter itself retains its completed color and cannot become negative.
      expect(
        tester.element(button).findAncestorWidgetOfExactType<Material>()!.color,
        const Color(0xFFB84949),
      );
      await tap(tester, button);
      expect(
        find.descendant(of: button, matching: find.text('0')),
        findsOneWidget,
      );
      await capture(tester, 'reader-0-${mode.name}');
      await tap(
        tester,
        find.widgetWithText(ActionChip, 'تراجع'),
        done: () => find
            .descendant(of: button, matching: find.text('1'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('مغادرة الأذكار؟'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'مغادرة'));
      expect(find.byKey(const ValueKey('adhkar-search')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'personal editor normalizes digits; groups and empty group fit narrow enlarged RTL',
    (tester) async {
      await pump(tester, width: 320, scale: 1.2);
      unawaitedForTest(host.currentState!.openPersonal());
      await until(
        tester,
        () => find
            .byKey(const ValueKey('add-personal-dhikr'))
            .evaluate()
            .isNotEmpty,
      );
      await tap(tester, find.byKey(const ValueKey('add-personal-dhikr')));
      await tester.enterText(
        find.byKey(const ValueKey('dhikr-text')),
        'ذكر من إدخال المستخدم',
      );
      await tester.enterText(find.byKey(const ValueKey('dhikr-target')), '٣');
      await tap(
        tester,
        find.byKey(const ValueKey('save-dhikr')),
        done: () => find.byKey(const ValueKey('save-dhikr')).evaluate().isEmpty,
      );
      expect(find.text('ذكر من إدخال المستخدم'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('add-personal-group')));
      await tester.enterText(
        find.byKey(const ValueKey('group-title')),
        'مجموعة خالية',
      );
      await capture(tester, 'group-editor-narrow');
      await tap(
        tester,
        find.byKey(const ValueKey('save-group')),
        done: () => find.byKey(const ValueKey('save-group')).evaluate().isEmpty,
      );
      await tap(tester, find.widgetWithText(ChoiceChip, 'مجموعاتي'));
      expect(find.text('مجموعة خالية'), findsOneWidget);
      await tap(
        tester,
        find.text('مجموعة خالية'),
        done: () => find.text('هذه المجموعة خالية').evaluate().isNotEmpty,
      );
      await capture(tester, 'empty-group-narrow');
      await tap(tester, find.widgetWithText(FilledButton, 'إضافة ذكر'));
      await tap(tester, find.byType(CheckboxListTile).first);
      await tap(
        tester,
        find.byKey(const ValueKey('save-group')),
        done: () => find
            .byKey(const ValueKey('count-hisn-api-075'))
            .evaluate()
            .isNotEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'official reader modes, long titles and maximum font fit narrow enlarged RTL',
    (tester) async {
      await quran.preferences!.setString(
        'adhkar.display.v1.guest',
        jsonEncode({'size': 42, 'confirm_exit': false}),
      );
      await pump(tester, width: 320, scale: 1.2, mode: ThemeMode.dark);
      unawaitedForTest(host.currentState!.openGroup('daily:morning'));
      await until(
        tester,
        () => find
            .byKey(const ValueKey('count-hisn-api-075'))
            .evaluate()
            .isNotEmpty,
      );
      await capture(tester, 'official-reader-narrow-dark');
      await tap(tester, find.byKey(const ValueKey('adhkar-mode-list')));
      expect(find.byKey(const ValueKey('count-hisn-api-075')), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('adhkar-mode-focus')));
      await tap(tester, find.widgetWithText(ActionChip, 'العرض'));
      expect(find.text('عرض الأذكار والجلسة'), findsOneWidget);
      await capture(tester, 'settings-narrow-dark');
      await tap(tester, find.widgetWithText(FilledButton, 'تم'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('adhkar-search')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('volume bridge counts only in visible resumed focus route', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger,
        calls = <bool>[];
    messenger.setMockMethodCallHandler(AdhkarVolumeControls.channel, (
      call,
    ) async {
      calls.add(call.arguments as bool);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        AdhkarVolumeControls.channel,
        null,
      ),
    );
    final id = await fixture();
    await quran.preferences!.setString(
      'adhkar.display.v1.guest',
      jsonEncode({'mode': 'focus', 'volume_keys': true, 'confirm_exit': false}),
    );
    await pump(tester);
    unawaitedForTest(host.currentState!.openGroup('personal:all'));
    final counter = find.byKey(ValueKey('count-$id'));
    await until(tester, () => counter.evaluate().isNotEmpty);
    expect(calls.last, isTrue);
    await messenger.handlePlatformMessage(
      AdhkarVolumeControls.channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('count')),
      null,
    );
    await until(
      tester,
      () => find
          .descendant(of: counter, matching: find.text('2'))
          .evaluate()
          .isNotEmpty,
    );
    visible.value = false;
    await tester.pumpAndSettle();
    expect(calls.last, isFalse);
    visible.value = true;
    await tester.pumpAndSettle();
    expect(calls.last, isTrue);
    unawaitedForTest(host.currentState!.openPersonal());
    await until(
      tester,
      () => find
          .byKey(const ValueKey('add-personal-dhikr'))
          .evaluate()
          .isNotEmpty,
    );
    expect(calls.last, isFalse);
    await tap(tester, find.byTooltip('العودة للأذكار'));
    expect(calls.last, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(calls.last, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls.last, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('switching account removes private reader and editor routes', (
    tester,
  ) async {
    final id = await fixture();
    await pump(tester);
    unawaitedForTest(host.currentState!.openGroup('personal:all'));
    await until(
      tester,
      () => find.byKey(ValueKey('count-$id')).evaluate().isNotEmpty,
    );
    expect(find.text('ذكر شخصي للاختبار'), findsOneWidget);
    quran.account.profile = {'id': 2};
    activity.changed('account.2');
    await until(
      tester,
      () => find.byKey(const ValueKey('adhkar-search')).evaluate().isNotEmpty,
    );
    expect(find.text('ذكر شخصي للاختبار'), findsNothing);
    final records = await tester.runAsync(() => store.entities('account.2'));
    expect(records, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'main app back confirms reader exit and More opens personal management',
    (tester) async {
      final id = await fixture();
      await pump(tester, fullApp: true);
      await tap(tester, find.widgetWithText(NavigationDestination, 'الأذكار'));
      final section = tester.state<AdhkarSectionPageState>(
        find.byType(AdhkarSectionPage),
      );
      unawaitedForTest(section.openGroup('personal:all'));
      await until(
        tester,
        () => find.byKey(ValueKey('count-$id')).evaluate().isNotEmpty,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('مغادرة الأذكار؟'), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      await tap(tester, find.widgetWithText(TextButton, 'إلغاء'));
      expect(find.byKey(ValueKey('count-$id')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(FilledButton, 'مغادرة'));
      expect(find.byKey(const ValueKey('adhkar-search')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await tap(tester, find.widgetWithText(NavigationDestination, 'المزيد'));
      await tester.drag(
        find.byKey(const PageStorageKey('more-directory')),
        const Offset(0, -450),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feature-personalAdhkar')));
      await until(
        tester,
        () => find
            .byKey(const ValueKey('add-personal-dhikr'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('ذكر شخصي للاختبار'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

// Navigation futures complete only after the route is popped; the assertions
// below drive the route while it is open.
void unawaitedForTest(Future<void> value) {
  value.catchError((Object error) {
    throw error;
  });
}
