import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/features/prayer/data/prayer_controller.dart';
import 'package:haq_app/features/prayer/data/prayer_models.dart';
import 'package:haq_app/features/prayer/data/heading_controller.dart';
import 'package:haq_app/features/prayer/data/mosque_repository.dart';
import 'package:haq_app/features/prayer/presentation/prayer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PrayerController c;
  late AppAppearance appearance;
  late ValueNotifier<String> owner;
  const channel = MethodChannel('test.haq.prayer.screens');
  final preview = GlobalKey();
  final calls = <MethodCall>[];
  setUpAll(() async {
    initializePrayerZones();
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
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    owner = ValueNotifier('guest');
    appearance = AppAppearance(prefs);
    c = PrayerController(
      prefs,
      scopeOf: () => owner.value,
      account: owner,
      autoTick: false,
      channel: channel,
      clock: () => DateTime.utc(2026, 10, 26, 10),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'requestLocation') {
            throw PlatformException(code: 'denied');
          }
          return null;
        });
  });
  tearDown(() {
    c.dispose();
    appearance.dispose();
    owner.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
  }

  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    double scale = 1.3,
  }) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppearanceScope(
        controller: appearance,
        child: RepaintBoundary(
          key: preview,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorObservers: [prayerRoutes],
            theme: ThemeData(
              fontFamily: 'QuranUI',
              brightness: dark ? Brightness.dark : Brightness.light,
              colorSchemeSeed: const Color(0xFF2A8C82),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: page,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final image =
          await (preview.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final dir = Directory('build/p09-previews')..createSync(recursive: true);
      File(
        '${dir.path}/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.text(label).first;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await settle(tester);
  }

  PrayerLocation place() => PrayerLocation(
    latitude: 31.53,
    longitude: 35.1,
    zone: 'Asia/Hebron',
    label: 'موقع يدوي للاختبار',
  );
  testWidgets(
    'unknown compass does not request permission until explicit tap and denial shows no fake direction',
    (tester) async {
      await pump(tester, QiblaPage(controller: c));
      expect(calls, isEmpty);
      expect(find.text('الموقع غير متاح'), findsOneWidget);
      await tap(tester, 'السماح بالموقع / إعادة المحاولة');
      expect(calls.where((e) => e.method == 'requestLocation').length, 1);
      expect(c.config.location, isNull);
      expect(find.textContaining('لم يُسمح'), findsOneWidget);
      expect(
        find.bySemanticsLabel('اتجاه القبلة من قراءة الحساس'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'manual form saves verified coordinates and timezone, independent of location permission',
    (tester) async {
      await pump(tester, PrayerSettingsPage(controller: c));
      await tester.enterText(find.byType(TextFormField).at(0), 'موقعي اليدوي');
      await tester.enterText(find.byType(TextFormField).at(1), '31.53');
      await tester.enterText(find.byType(TextFormField).at(2), '35.1');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tap(tester, 'المنطقة الزمنية للموقع');
      await tester.enterText(find.byType(TextField).last, 'Asia/Hebron');
      await tester.pump();
      await tester.tap(find.text('Asia/Hebron').last);
      await settle(tester);
      await tap(tester, 'حفظ إعدادات الصلاة');
      expect(c.config.location?.zone, 'Asia/Hebron');
      expect(c.config.location?.latitude, 31.53);
      expect(c.today, isNotNull);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'real heading rotates only when reliable, then hides after stale sample and inactive tab',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.runAsync(() => c.save(PrayerConfig(location: place())));
      final stream = StreamController<dynamic>.broadcast();
      final heading = HeadingController(readings: (_) => stream.stream);
      await pump(
        tester,
        QiblaPage(controller: c, heading: heading),
        dark: true,
      );
      stream.add({'degrees': 160.0, 'accuracy': 3, 'trueNorth': true});
      await settle(tester);
      expect(heading.usable, true);
      expect(
        find.bySemanticsLabel('اتجاه القبلة من قراءة الحساس'),
        findsOneWidget,
      );
      await capture(tester, 'qibla-reading');
      await tap(tester, 'تحديد الموقع يدوياً وإعدادات الصلاة');
      expect(heading.degrees, isNull);
      await tester.tap(find.byTooltip('رجوع').last);
      await settle(tester);
      stream.add({'degrees': 160.0, 'accuracy': 3, 'trueNorth': true});
      await settle(tester);
      expect(heading.usable, true);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(heading.usable, false);
      expect(
        find.bySemanticsLabel('اتجاه القبلة من قراءة الحساس'),
        findsNothing,
      );
      await pump(
        tester,
        QiblaPage(controller: c, heading: heading, active: false),
      );
      expect(heading.degrees, isNull);
      await tester.pumpWidget(const SizedBox());
      heading.dispose();
      await stream.close();
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'mosque search is explicit, empty results are honest and account change clears results',
    (tester) async {
      await tester.runAsync(() => c.save(PrayerConfig(location: place())));
      var requests = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.resolve(
              Response(requestOptions: options, data: '{"elements":[]}'),
            );
          },
        ),
      );
      final repository = MosqueRepository(dio: dio);
      await pump(tester, MosquesPage(controller: c, repository: repository));
      expect(requests, 0);
      await tap(tester, 'البحث في OpenStreetMap');
      expect(requests, 1);
      expect(find.textContaining('لا يعني عدم وجود'), findsOneWidget);
      owner.value = 'account.2';
      await settle(tester);
      expect(find.textContaining('لا يعني عدم وجود'), findsNothing);
      expect(c.config.location, isNull);
      await tester.pumpWidget(const SizedBox());
      repository.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'prayer location and mosque pages fit narrow enlarged ${dark ? 'dark' : 'light'}',
      (tester) async {
        for (final (name, page) in [
          ('qibla-empty', QiblaPage(controller: c)),
          ('settings', PrayerSettingsPage(controller: c)),
          ('prayer', PrayerPage(controller: c)),
          ('mosques', MosquesPage(controller: c)),
        ]) {
          await pump(tester, page, dark: dark);
          await capture(tester, '$name-${dark ? 'dark' : 'light'}');
          for (var i = 0; i < 12; i++) {
            await tester.drag(
              find.byType(CustomScrollView),
              const Offset(0, -650),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$name $i');
          }
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }
}
