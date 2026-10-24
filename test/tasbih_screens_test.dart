import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/religious_activity/data/activity_controller.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'package:haq_app/features/religious_activity/data/activity_models.dart';
import 'package:haq_app/features/tasbih/data/tasbih_controller.dart';
import 'package:haq_app/features/tasbih/presentation/tasbih_page.dart';
import 'package:haq_app/features/religious_content/data/religious_catalog.dart';
import 'package:haq_app/features/religious_content/data/religious_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'tasbih_test.dart' show FakeSpeech;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late QuranRepository repository;
  late QuranController quran;
  late ReligiousActivityStore store;
  late ReligiousActivityController activity;
  late TasbihController counter;
  late FakeSpeech speech;
  final boundary = GlobalKey();
  setUpAll(() async {
    repository = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
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
    for (final (family, path) in [
      ('QuranUI', 'assets/fonts/Cairo.ttf'),
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
  });
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
    counter = await TasbihController.open(
      activity,
      (await TasbihController.library(activity)).first,
    );
    speech = FakeSpeech();
  });
  tearDown(() async {
    if (!activity.syncClient.disposed) activity.dispose();
    quran.dispose();
    await store.close();
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    bool dark = false,
    double width = 426,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: 'QuranUI',
            brightness: dark ? Brightness.dark : Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2A8C82),
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.2 : 1)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: TasbihReaderPage(
            counter: counter,
            routes: RouteObserver<ModalRoute<dynamic>>(),
            speech: speech,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pump();
    await tester.runAsync(() async {
      final node =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await node.toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      final file = File('build/tasbih-preview/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
      'six styles preserve live counter and render ${dark ? 'dark' : 'light'} without overflow',
      (tester) async {
        await pump(tester, dark: dark);
        for (var i = 0; i < 44; i++) {
          unawaited(counter.increment());
          await settle(tester);
        }
        for (final style in TasbihStyle.values) {
          unawaited(counter.style(style));
          await settle(tester);
          expect(find.text('11'), findsOneWidget);
          expect(counter.total, 44);
          await capture(tester, '${style.name}-${dark ? 'dark' : 'light'}');
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'touch, long press undo, swipes and buttons update exactly once at narrow width',
    (tester) async {
      await pump(tester, width: 320);
      await tester.tap(find.byKey(const ValueKey('tasbih-face')));
      await settle(tester);
      expect(counter.total, 1);
      await tester.longPress(find.byKey(const ValueKey('tasbih-face')));
      await settle(tester);
      expect(counter.total, 0);
      unawaited(counter.style(TasbihStyle.horizontal));
      await settle(tester);
      await tester.fling(
        find.byKey(const ValueKey('tasbih-face')),
        const Offset(140, 0),
        600,
      );
      await settle(tester);
      expect(counter.total, 1);
      await tester.fling(
        find.byKey(const ValueKey('tasbih-face')),
        const Offset(-140, 0),
        600,
      );
      await settle(tester);
      expect(counter.total, 0);
      unawaited(counter.style(TasbihStyle.buttons));
      await settle(tester);
      await tester.tap(find.byTooltip('زيادة'));
      await settle(tester);
      expect(counter.total, 1);
      await tester.tap(find.byTooltip('نقصان'));
      await settle(tester);
      expect(counter.total, 0);
      await capture(tester, 'buttons-narrow');
      expect(tester.takeException(), isNull);
      for (final style in TasbihStyle.values) {
        unawaited(counter.style(style));
        await settle(tester);
        await capture(tester, '${style.name}-narrow');
        expect(tester.takeException(), isNull);
      }
      unawaited(counter.increment());
      await settle(tester);
      await tester.tap(find.byTooltip('تصفير الحالي'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'تصفير'));
      await settle(tester);
      expect([counter.total, counter.current], [1, 0]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'auto hold counts until release and is canceled when the application becomes inactive',
    (tester) async {
      await quran.preferences!.setBool('tasbih.settings.v1.guest.auto', true);
      await pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tasbih-face'))),
      );
      await tester.pump(const Duration(milliseconds: 800));
      await settle(tester);
      expect(counter.total, greaterThan(0));
      await gesture.up();
      await settle(tester);
      final after = counter.total;
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(counter.total, after);
      final second = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tasbih-face'))),
      );
      await tester.pump(const Duration(milliseconds: 800));
      await settle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      final paused = counter.total;
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(counter.total, paused);
      await second.up();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'reset confirmation separates total and current; settings and max-length edit remain scrollable',
    (tester) async {
      await pump(tester, width: 320, dark: true);
      for (var i = 0; i < 44; i++) {
        unawaited(counter.increment());
        await settle(tester);
      }
      await tester.ensureVisible(find.text('تصفير الحالي'));
      await tester.tap(find.text('تصفير الحالي'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'تصفير'));
      await settle(tester);
      expect([counter.total, counter.current, counter.rounds], [44, 0, 1]);
      await tester.ensureVisible(find.text('الإعدادات'));
      await tester.tap(find.text('الإعدادات'));
      await settle(tester);
      await capture(tester, 'settings-narrow-dark');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('تم'));
      await settle(tester);
      await tester.ensureVisible(find.text('تعديل'));
      await tester.tap(find.text('تعديل'));
      await settle(tester);
      await tester.enterText(
        find.byType(TextFormField).first,
        List.filled(70, 'ذكر ').join(),
      );
      await capture(tester, 'edit-narrow-dark');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('إلغاء'));
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'microphone final result counts once and background cancellation blocks a late result',
    (tester) async {
      await pump(tester);
      final mic = find.byKey(const ValueKey('tasbih-mic'));
      await tester.ensureVisible(mic);
      await tester.tap(mic);
      await settle(tester);
      expect(speech.starts, 1);
      speech.result!(counter.definition.text);
      await settle(tester);
      expect(counter.total, 1);
      speech.result!(counter.definition.text);
      await settle(tester);
      expect(counter.total, 1);
      await tester.tap(mic);
      await settle(tester);
      final stale = speech.result!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      stale(counter.definition.text);
      await settle(tester);
      expect(counter.total, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'goal completion is visible and continuation counts in the next round',
    (tester) async {
      await pump(tester);
      unawaited(
        counter.edit(text: counter.definition.text, benefit: '', goal: 2),
      );
      await settle(tester);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const ValueKey('tasbih-face')));
        await settle(tester);
      }
      expect(find.text('اكتملت الجولة 1'), findsOneWidget);
      await tester.ensureVisible(find.text('متابعة التسبيح'));
      await tester.tap(find.text('متابعة التسبيح'));
      await settle(tester);
      expect([counter.total, counter.rounds, counter.current], [3, 1, 1]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'account change closes private counter/editor and does not leak its library or writes',
    (tester) async {
      tester.view.physicalSize = const Size(426, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final private = counter.definition.copyWith(
        text: 'ذكر خاص لا يظهر للحساب الآخر',
      );
      await store.save('guest', private);
      final religious = ReligiousController(
        quran: quran,
        activityFactory: () async => activity,
        initialCatalog: ReligiousCatalog.fromJson(
          jsonDecode(File('assets/religious/catalog.json').readAsStringSync())
              as Map<String, dynamic>,
        ),
      );
      await religious.load();
      await tester.pumpWidget(
        MaterialApp(
          home: TasbihPage(controller: religious, speech: speech),
        ),
      );
      await settle(tester);
      await tester.tap(find.text(private.text));
      await settle(tester);
      await tester.ensureVisible(find.text('تعديل'));
      await tester.tap(find.text('تعديل'));
      await settle(tester);
      expect(find.byType(TextFormField), findsNWidgets(3));
      quran.account.profile = {'id': 7};
      activity.changed('account.7');
      await settle(tester);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text(private.text), findsNothing);
      final other = await tester.runAsync(
        () => store.entities('account.7', kind: PersonalEntityKind.tasbih),
      );
      expect(
        other!.cast<PersonalTasbih>().any((e) => e.text == private.text),
        false,
      );
      await tester.pumpWidget(const SizedBox());
      religious.dispose();
      await settle(tester);
      // This counter was created in setUp and never owned by the page above.
      counter.dispose();
    },
  );
}
