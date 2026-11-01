import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:haq_app/core/localization/app_localization.dart';
import 'package:flutter/rendering.dart';
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
import 'package:haq_app/features/settings/data/reminder_controller.dart';
import 'package:haq_app/settings_pages.dart';
import 'package:haq_app/navigation/app_section.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/visual_audit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late QuranRepository repo;
  late AdhkarRepository catalog;
  late QuranController quran;
  late ReligiousActivityStore store;
  late ReligiousActivityController activity;
  late ReminderController c;
  late AppAppearance appearance;
  final calls = <MethodCall>[];
  const channel = MethodChannel('test.haq.settings.screens');
  final preview = GlobalKey();
  setUpAll(() async {
    await loadVisualAuditFonts();
    repo = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    catalog = AdhkarRepository.fromJson(
      jsonDecode(File('assets/religious/adhkar.json').readAsStringSync())
          as Map<String, dynamic>,
      repo,
    );
    for (final (family, path) in [
      ('QuranUI', 'assets/fonts/Cairo.ttf'),
      ('Tajawal', 'assets/fonts/Tajawal-Regular.ttf'),
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
      'assets/images/home_header.png',
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'status') {
            return {
              'platform': 'android',
              'allowed': false,
              'overlay': false,
              'overlayRunning': false,
              'pending': 0,
            };
          }
          return null;
        });
    c = ReminderController(activity, catalog, channel: channel);
    await c.initialize();
  });
  tearDown(() async {
    c.dispose();
    activity.dispose();
    quran.dispose();
    appearance.dispose();
    await store.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
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
    SettingKind kind, {
    bool dark = false,
    double scale = 1.3,
    bool root = false,
    AppLocalization? localization,
  }) async {
    Widget localized(Widget child) => localization == null
        ? child
        : LocalizationScope(controller: localization, child: child);
    tester.view.physicalSize = visualSize(const Size(360, 1000));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppearanceScope(
        controller: appearance,
        child: RepaintBoundary(
          key: preview,
          child: localized(
            MaterialApp(
              locale: localization?.language.locale,
              supportedLocales: const [Locale('ar'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                fontFamily: 'QuranUI',
                brightness: dark ? Brightness.dark : Brightness.light,
                colorSchemeSeed: const Color(0xFF2A8C82),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(visualScale(scale))),
                child: child!,
              ),
              home: root
                  ? SettingsPage(reminders: c)
                  : SettingsDetailPage(
                      key: ValueKey('${kind.name}.$dark'),
                      kind: kind,
                      reminders: c,
                    ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.text(label).first;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
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
      final dir = Directory(visualPath('build/p08-previews'))
        ..createSync(recursive: true);
      File(
        '${dir.path}/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await captureAuditContinuation(
      tester,
      preview,
      visualPath('build/p08-previews/$name.png'),
    );
  }

  testWidgets(
    'English reminder settings and picker retain schedule and original dhikr content',
    (tester) async {
      final localization = AppLocalization(quran.preferences!);
      await localization.select('en');
      addTearDown(localization.dispose);
      final morning = c.settings.time('morning');
      await pump(tester, SettingKind.appearance, localization: localization);
      expect(find.text('Cairo'), findsOneWidget);
      await pump(tester, SettingKind.reminders, localization: localization);
      expect(find.text('Allow notifications'), findsOneWidget);
      await tap(tester, 'Morning adhkar time');
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await settle(tester);
      expect(c.settings.time('morning'), morning);
      await pump(tester, SettingKind.notifications, localization: localization);
      await tap(tester, 'Reminder content');
      expect(find.text('Search adhkar'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);
      final text = c.content.values.first;
      expect(find.text(text), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await settle(tester);
      expect(c.content.values.first, text);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );

  for (final loaded in [false, true]) {
    testWidgets(
      'settings bar works while loading and after ${loaded ? 'success' : 'failure'}',
      (tester) async {
        final selected = <int>[];
        final loading = Completer<ReminderController?>();
        await tester.pumpWidget(
          AppearanceScope(
            controller: appearance,
            child: MaterialApp(
              home: SettingsPage(
                loadReminders: () => loading.future,
                onDestinationSelected: selected.add,
              ),
            ),
          ),
        );
        await tester.ensureVisible(find.text('الصلاحيات والخصوصية'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('الصلاحيات والخصوصية'));
        await settle(tester);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byType(NavigationBar), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('القرآن'),
          ),
        );
        expect(selected.last, AppSection.quran.index);
        loading.complete(loaded ? c : null);
        await settle(tester);
        if (loaded) {
          expect(find.byType(SettingsDetailPage), findsOneWidget);
        } else {
          expect(find.text('تعذّر تجهيز الإعدادات'), findsOneWidget);
        }
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('الرئيسية'),
          ),
        );
        expect(selected.last, AppSection.home.index);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'reminder switches survive reopening and time picker cancellation changes nothing',
    (tester) async {
      await pump(tester, SettingKind.reminders);
      expect(calls.any((e) => e.method == 'requestPermission'), false);
      await tester.tap(find.byType(Switch).first);
      await settle(tester);
      expect(c.settings.flag('enabled'), true);
      await tap(tester, 'موعد أذكار الصباح');
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(
        find.text(
          MaterialLocalizations.of(
            tester.element(find.byType(TimePickerDialog)),
          ).cancelButtonLabel,
        ),
      );
      await settle(tester);
      expect(c.settings.time('morning'), 300);
      await pump(tester, SettingKind.hijri);
      await pump(tester, SettingKind.reminders);
      expect(tester.widget<Switch>(find.byType(Switch).first).value, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'frequency and snooze options persist; denial stays denied after explicit request',
    (tester) async {
      await pump(tester, SettingKind.notifications);
      await tap(tester, 'تكرار ظهور الذكر');
      await tester.tap(find.text('كل 15 دقيقة'));
      await settle(tester);
      expect(c.settings.number('frequency', 5), 15);
      await tap(tester, 'الصوت والتفاعل');
      await tap(tester, 'التأجيل السريع');
      await tester.tap(find.text('45 دقيقة'));
      await settle(tester);
      expect(c.settings.number('snooze', 10), 45);
      await tap(tester, 'حالة الجهاز والأذونات');
      await tap(tester, 'طلب إذن الإشعارات');
      expect(calls.where((e) => e.method == 'requestPermission').length, 1);
      expect(c.device.allowed, false);
      expect(
        find.text('الإشعارات غير مسموحة. امنح الإذن من الزر أدناه.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'large content picker selects all, searches Arabic, cancels and commits explicitly',
    (tester) async {
      await pump(tester, SettingKind.notifications, scale: 1);
      await tap(tester, 'محتوى التنبيهات');
      final dialog = find.byKey(const ValueKey('dhikr-content-dialog'));
      expect(tester.getSize(dialog).width, greaterThan(320));
      expect(tester.getSize(dialog).height, greaterThan(750));
      await tester.tap(find.byKey(const ValueKey('dhikr-select-all')));
      await tester.pumpAndSettle();
      expect(c.settings.content, isEmpty);
      expect(
        find.text('${c.content.length} محدد من ${c.content.length}'),
        findsOneWidget,
      );
      await tester.tap(find.text('إلغاء'));
      await settle(tester);
      expect(c.settings.content, isEmpty);
      await tap(tester, 'محتوى التنبيهات');
      await tester.enterText(
        find.byKey(const ValueKey('dhikr-content-search')),
        'سبحان',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dhikr-select-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('مسح البحث'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dhikr-select-all')));
      await tester.pumpAndSettle();
      await capture(tester, 'p25-content-picker-all');
      await tester.tap(find.byKey(const ValueKey('save-dhikr-content')));
      await settle(tester);
      expect(c.settings.content.toSet(), c.content.keys.toSet());
      expect(c.settings.content.length, greaterThan(50));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'center mode hides overlay details and overlay styling is collapsed',
    (tester) async {
      await pump(tester, SettingKind.notifications, scale: 1);
      expect(find.text('موضع التنبيه العائم'), findsNothing);
      expect(find.text('خيارات إشعار التشغيل في الجهاز'), findsNothing);
      await capture(tester, 'p25-smart-center');
      await tap(tester, 'مكان التنبيه');
      await tester.tap(find.text('فوق التطبيقات • Android'));
      await settle(tester);
      expect(find.text('مظهر الذكر العائم'), findsOneWidget);
      expect(find.text('لون الخلفية'), findsNothing);
      await tap(tester, 'مظهر الذكر العائم');
      expect(find.text('لون الخلفية'), findsOneWidget);
      await tap(tester, 'خيارات إشعار التشغيل في الجهاز');
      expect(
        calls.any((call) => call.method == 'overlayNotificationSettings'),
        true,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'content picker stays usable on a narrow enlarged screen with keyboard',
    (tester) async {
      await pump(tester, SettingKind.notifications, scale: 1.4);
      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpAndSettle();
      await tap(tester, 'محتوى التنبيهات');
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 210);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('dhikr-content-search')),
        'سبحان',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('save-dhikr-content')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('إلغاء'));
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account switch dismisses content picker and prevents private selections leaking',
    (tester) async {
      final personal = PersonalDhikr(
        id: operationId(),
        text: 'نص شخصي للاختبار',
        target: 1,
      );
      await tester.runAsync(() async {
        await activity.save(personal);
        await c.reconcile();
      });
      await pump(tester, SettingKind.notifications);
      await tap(tester, 'محتوى التنبيهات');
      expect(
        find.byKey(const ValueKey('dhikr-content-dialog')),
        findsOneWidget,
      );
      quran.account.profile = {'id': 42};
      activity.changed(activity.scope);
      await settle(tester);
      expect(find.byKey(const ValueKey('dhikr-content-dialog')), findsNothing);
      expect(c.settings.scope, 'account.42');
      expect(c.settings.content, isEmpty);
      expect(c.content.containsKey(personal.id), false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'settings surfaces scroll without overflow at large text ${dark ? 'dark' : 'light'}',
      (tester) async {
        for (final kind in [
          SettingKind.reminders,
          SettingKind.notifications,
          SettingKind.privacy,
          SettingKind.hijri,
        ]) {
          await pump(tester, kind, dark: dark, scale: 1.4);
          await capture(tester, '${kind.name}-${dark ? 'dark' : 'light'}');
          for (var i = 0; i < 22; i++) {
            await tester.drag(
              find.byType(CustomScrollView),
              const Offset(0, -550),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '${kind.name} scroll $i',
            );
          }
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  if (visualAudit) {
    testWidgets(
      'visual review root settings and preserved appearance at normal size',
      (tester) async {
        for (final dark in [false, true]) {
          await appearance.setMode(dark ? ThemeMode.dark : ThemeMode.light);
          await pump(tester, SettingKind.appearance, dark: dark, root: true);
          await capture(tester, 'root-${dark ? 'dark' : 'light'}');
          await tester.pumpWidget(const SizedBox());
          await pump(tester, SettingKind.appearance, dark: dark);
          await capture(tester, 'appearance-${dark ? 'dark' : 'light'}');
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }
}
