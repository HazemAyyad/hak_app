import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/core/localization/app_localization.dart';
import 'package:haq_app/features/prayer/data/prayer_controller.dart';
import 'package:haq_app/features/prayer/data/prayer_models.dart';
import 'package:haq_app/features/prayer/data/place_catalog.dart';
import 'package:haq_app/features/prayer/data/prayer_alert.dart';
import 'package:haq_app/features/prayer/data/heading_controller.dart';
import 'package:haq_app/features/prayer/data/mosque_repository.dart';
import 'package:haq_app/features/prayer/data/adhan_library.dart';
import 'package:haq_app/features/prayer/presentation/prayer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/visual_audit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PrayerController c;
  late AppAppearance appearance;
  late ValueNotifier<String> owner;
  const channel = MethodChannel('test.haq.prayer.screens');
  final preview = GlobalKey();
  final calls = <MethodCall>[];
  setUpAll(() async {
    await loadVisualAuditFonts();
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
    AppLocalization? localization,
  }) async {
    tester.view.physicalSize = visualSize(const Size(320, 1000));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final screen = AppearanceScope(
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
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(visualScale(scale)),
            ),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    await tester.pumpWidget(
      localization == null
          ? screen
          : LocalizationScope(controller: localization, child: screen),
    );
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await prepareVisualAuditCapture(tester, preview);
    await tester.runAsync(() async {
      final image =
          await (preview.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final dir = Directory(visualPath('build/qibla-video-previews'))
        ..createSync(recursive: true);
      File(
        '${dir.path}/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final matches = find.text(label);
    if (matches.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        matches,
        350,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
    }
    final target = matches.first;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await settle(tester);
  }

  testWidgets(
    'granted permission hides the request; live settings persist and preview fits the viewport',
    (tester) async {
      var allowed = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AdhanLibrary.bridge, (call) async {
            if (call.method == 'requestPermission') {
              allowed = true;
              return null;
            }
            if (call.method == 'status') return {'allowed': allowed};
            if (call.method == 'adhanStatus') {
              return {'platform': 'android', 'exact': true, 'fullScreen': true};
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AdhanLibrary.bridge, null),
      );
      await pump(tester, PrayerAdhanSettingsPage(controller: c));
      await tester.tap(
        find.byKey(const ValueKey('adhan-notification-permission')),
      );
      await settle(tester);
      expect(
        find.byKey(const ValueKey('adhan-notification-permission')),
        findsNothing,
      );
      expect(find.text('إذن الإشعارات مفعّل'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('adhan-master')));
      await settle(tester);
      expect(c.config.notifications, true);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('adhan-enabled-fajr')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('adhan-enabled-fajr')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('adhan-enabled-fajr')));
      await settle(tester);
      expect(c.config.enabledPrayers, isNot(contains('fajr')));
      final saved = PrayerConfig.fromJson(c.config.toJson());
      expect(saved.enabledPrayers, c.config.enabledPrayers);
      await capture(tester, 'adhan-global-settings');
      await pump(tester, AdhanScreenPreview(controller: c));
      await tester.pump(const Duration(seconds: 11));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsNothing);
      expect(find.text('أذكار بعد الصلاة'), findsOneWidget);
      await capture(tester, 'adhan-screen-preview');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'animated adhan title has no scrolling and preview buttons return precise destinations',
    (tester) async {
      for (final entry in {
        'أذكار بعد الصلاة': 'adhkar-after-prayer',
        'القرآن': 'quran',
        'القبلة': 'qibla',
        'إعدادات الأذان': 'prayer-settings',
      }.entries) {
        String? destination;
        await pump(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('فتح المعاينة'),
                onPressed: () async {
                  destination = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdhanScreenPreview(controller: c),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('فتح المعاينة'));
        await settle(tester);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await settle(tester);
        expect(
          find.byKey(const ValueKey('adhan-animated-title')),
          findsOneWidget,
        );
        expect(find.text('الله أكبر'), findsOneWidget);
        expect(find.byType(Scrollable), findsNothing);
        if (entry.key == 'إعدادات الأذان') {
          await tester.tap(find.byTooltip(entry.key));
        } else {
          await tester.ensureVisible(find.text(entry.key));
          await tester.pumpAndSettle();
          await tester.tap(find.text(entry.key));
        }
        await settle(tester);
        expect(destination, entry.value);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'all five bundled synthetic reminder choices stay readable with large Arabic text',
    (tester) async {
      await pump(tester, PrayerReminderRecordingsPage(controller: c));
      expect(find.textContaining('مولّد اصطناعيًا'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('قرب وقت صلاة العشاء'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'bundled-reminder-voices');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reminder picker offers three Arabic dialects and a single English voice',
    (tester) async {
      await pump(tester, PrayerReminderRecordingsPage(controller: c));
      await tester.ensureVisible(
        find.byKey(const ValueKey('reminder-dialect-palestinian')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('reminder-dialect-palestinian')),
      );
      await settle(tester);
      expect(find.text('مصرية'), findsOneWidget);
      expect(find.text('خليجية'), findsOneWidget);
      await tester.tap(find.text('مصرية'));
      await settle(tester);
      expect(c.config.reminderDialect, PrayerReminderDialect.egyptian);
      await tester.ensureVisible(
        find.byKey(const ValueKey('reminder-language-auto')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-language-auto')));
      await settle(tester);
      await tester.tap(find.text('English').last);
      await settle(tester);
      expect(c.config.reminderLanguage, 'en');
      expect(c.reminderVariant, 'en');
      expect(find.text('English uses one voice.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reminder-dialect-egyptian')),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.text('It is almost time for Isha prayer'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'english-reminder-voice');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Qibla top settings icon opens the shared adhan settings', (
    tester,
  ) async {
    await pump(tester, QiblaPage(controller: c));
    await tester.tap(find.byKey(const ValueKey('qibla-adhan-settings')));
    await settle(tester);
    expect(find.byType(PrayerAdhanSettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'adhan screen has no scrolling at phone height and enlarged text',
    (tester) async {
      await pump(tester, AdhanScreenPreview(controller: c), scale: 1.5);
      tester.view.physicalSize = const Size(320, 568);
      await settle(tester);
      expect(find.byType(Scrollable), findsNothing);
      expect(
        find.byKey(const ValueKey('adhan-animated-title')),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.text('أذكار بعد الصلاة')).bottom,
        lessThan(568),
      );
      expect(tester.getRect(find.text('إغلاق المعاينة')).bottom, lessThan(568));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  PrayerLocation place() => PrayerLocation(
    latitude: 31.53,
    longitude: 35.1,
    zone: 'Asia/Hebron',
    label: 'موقع يدوي للاختبار',
  );
  testWidgets(
    'English prayer page preserves times and stored Arabic location',
    (tester) async {
      final localization = AppLocalization(
        await SharedPreferences.getInstance(),
      );
      await localization.select('en');
      addTearDown(localization.dispose);
      await tester.runAsync(() => c.save(PrayerConfig(location: place())));
      final originalTimes = c.today!.moments.map((p) => p.time).toList();
      await pump(tester, PrayerPage(controller: c), localization: localization);
      expect(find.text('Prayer times'), findsWidgets);
      expect(find.text('موقع يدوي للاختبار'), findsOneWidget);
      expect(find.textContaining(' AH'), findsOneWidget);
      expect(find.text('Fajr'), findsOneWidget);
      expect(find.text('Muslim World League'), findsNothing);
      expect(c.today!.moments.map((p) => p.time).toList(), originalTimes);
      expect(calls.where((call) => call.method == 'requestLocation'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'video compass and per-prayer alert preserve identity ${dark ? 'dark' : 'light'}',
      (tester) async {
        await tester.runAsync(
          () => c.save(PrayerConfig(location: place(), beforeMinutes: 15)),
        );
        final stream = StreamController<dynamic>.broadcast();
        final heading = HeadingController(readings: (_) => stream.stream);
        await pump(
          tester,
          QiblaPage(controller: c, heading: heading),
          dark: dark,
          scale: 1,
        );
        tester.view.physicalSize = visualSize(const Size(390, 1800));
        stream.add({'degrees': 100.0, 'accuracy': 3, 'trueNorth': true});
        await settle(tester);
        await capture(tester, 'video-qibla-${dark ? 'dark' : 'light'}');
        stream.add({'degrees': 150.0, 'accuracy': 3, 'trueNorth': true});
        await tester.pump(const Duration(milliseconds: 80));
        await capture(tester, 'video-motion-${dark ? 'dark' : 'light'}');
        await tester.pumpWidget(const SizedBox());
        heading.dispose();
        await stream.close();
        final temp = await tester.runAsync(
          () => Directory.systemTemp.createTemp('haq-alert-screen-'),
        );
        final library = AdhanLibrary(
          directory: () async => temp!,
          prepare: (_, _) async => true,
        );
        await tester.runAsync(library.initialize);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AdhanLibrary.bridge, (call) async {
              if (call.method == 'adhanStatus') {
                return {
                  'platform': 'android',
                  'exact': true,
                  'fullScreen': true,
                };
              }
              return null;
            });
        await pump(
          tester,
          PrayerAlertPage(
            controller: c,
            prayer: PrayerName.fajr,
            library: library,
          ),
          dark: dark,
        );
        await tester.tap(find.byType(Switch).first);
        await tester.pump();
        await tap(tester, 'صوت الأذان');
        await capture(tester, 'video-alert-${dark ? 'dark' : 'light'}');
        expect(find.text('الأذان الكامل'), findsOneWidget);
        // An unbundled choice must still be downloaded explicitly before saving.
        await tester.enterText(find.byType(TextField).last, 'كاتب');
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('adhan-voice-nusuk-49')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('adhan-voice-nusuk-49')));
        await tester.pump();
        await tap(tester, 'احفظ التغييرات');
        expect(
          c.config.notifications,
          false,
        ); // No downloaded sound: no false success.
        expect(library.error, contains('نزّل'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        library.dispose();
        await tester.runAsync(() => temp!.delete(recursive: true));
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AdhanLibrary.bridge, null);
      },
    );
  }
  testWidgets(
    'large adhan catalog is a compact bounded list with searchable selection and independent scrolling',
    (tester) async {
      await tester.runAsync(() => c.save(PrayerConfig(location: place())));
      final temp = await tester.runAsync(
        () => Directory.systemTemp.createTemp('haq-voices-'),
      );
      final library = AdhanLibrary(
        directory: () async => temp!,
        preparePair: (_, _, _) async => true,
      );
      await tester.runAsync(library.initialize);
      await pump(
        tester,
        PrayerAlertPage(
          controller: c,
          prayer: PrayerName.fajr,
          library: library,
        ),
        scale: 1,
      );
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tap(tester, 'صوت الأذان');
      final list = find.byKey(const ValueKey('compact-adhan-voices'));
      await tester.ensureVisible(list);
      await settle(tester);
      expect(tester.getSize(list).height, lessThanOrEqualTo(360));
      expect(
        find.byKey(ValueKey('adhan-voice-${adhanVoices.last.id}')),
        findsNothing,
      );
      await tester.enterText(find.byType(TextField).last, 'ملا');
      await tester.pump();
      final voice = adhanVoices.firstWhere((v) => v.name.contains('ملا'));
      await tester.tap(find.byKey(ValueKey('adhan-voice-${voice.id}')));
      await tester.pump();
      expect(find.text('المختار: ${voice.name}'), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      tester.view.physicalSize = visualSize(const Size(390, 844));
      await tester.pumpAndSettle();
      await capture(tester, 'compact-voices-default');
      await tap(tester, 'احفظ التغييرات');
      expect(c.config.alert(PrayerName.fajr).voice, 'nusuk-1');
      expect(c.config.alert(PrayerName.fajr).mode, PrayerAlertMode.adhan);
      expect(c.config.notifications, true);
      expect(library.error, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
      await tester.runAsync(() => temp!.delete(recursive: true));
    },
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
    'city search returns draft to prayer settings and persists with final save without GPS permission',
    (tester) async {
      await tester.runAsync(PlaceCatalog.load);
      await pump(tester, PrayerSettingsPage(controller: c));
      await tap(tester, 'بحث عن دولة أو مدينة');
      await tester.enterText(
        find.byKey(const ValueKey('prayer-place-query')),
        'نابلس',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('نابلس').last);
      await settle(tester);
      await tester.tap(find.text('اعتماد هذا الموقع'));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(c.config.location, isNull);
      expect(find.text('نابلس، فلسطين'), findsOneWidget);
      await tap(tester, 'حفظ إعدادات الصلاة');
      expect(c.config.location?.label, 'نابلس، فلسطين');
      expect(c.config.location?.zone, 'Asia/Hebron');
      expect(c.today, isNotNull);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'manual form saves verified coordinates and timezone, independent of location permission',
    (tester) async {
      await pump(tester, PrayerSettingsPage(controller: c));
      await tap(tester, 'ضبط الإحداثيات والمنطقة الزمنية يدويًا');
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
      await tap(tester, 'إعدادات الأذان');
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
