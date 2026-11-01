import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/core/localization/app_localization.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/religious_activity/data/activity_controller.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'package:haq_app/features/religious_content/data/religious_catalog.dart';
import 'package:haq_app/features/religious_content/data/religious_controller.dart';
import 'package:haq_app/features/sakinah/presentation/sakinah_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/visual_audit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late QuranRepository repository;
  late ReligiousCatalog catalog;
  late QuranController quran;
  late ReligiousController religious;
  late ReligiousActivityStore store;
  late ReligiousActivityController activity;
  late AppAppearance appearance;
  late AppLocalization localization;
  setUpAll(() async {
    await loadVisualAuditFonts();
    repository = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    catalog = await ReligiousCatalog.load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    appearance = AppAppearance(preferences);
    localization = AppLocalization(preferences);
    await localization.select('en');
    quran = QuranController(
      initialRepository: repository,
      preferences: preferences,
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
    localization.dispose();
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

  Future<void> tapVisible(
    WidgetTester tester,
    Finder target, {
    double delta = 180,
  }) async {
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        delta,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await tester.ensureVisible(target);
    await settle(tester);
    await tester.tap(target);
    await settle(tester);
  }

  testWidgets(
    'English Sakinah setup keeps path identities and records no activity while changing interface',
    (tester) async {
      tester.view.physicalSize = const Size(320, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        LocalizationScope(
          controller: localization,
          child: AppearanceScope(
            controller: appearance,
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('ar'), Locale('en')],
              theme: ThemeData(fontFamily: 'QuranUI'),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.2)),
                child: child!,
              ),
              home: SakinahPage(controller: religious),
            ),
          ),
        ),
      );
      await settle(tester);
      await tapVisible(tester, find.text('Gratitude'));
      await tester.scrollUntilVisible(
        find.text('Session duration'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Session duration'), findsOneWidget);
      await tapVisible(tester, find.text('Custom pattern'), delta: -180);
      expect(find.byKey(const ValueKey('breath-plus-0')), findsOneWidget);
      await tapVisible(
        tester,
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is Tooltip &&
                      widget.message?.startsWith('About pattern:') == true ||
                  widget is Text && widget.data == 'About this pattern',
            )
            .first,
        delta: -180,
      );
      expect(find.textContaining('The order is inhale'), findsOneWidget);
      await tester.tap(find.text('Done').last);
      await settle(tester);
      final events = await tester.runAsync(() => store.events(activity.scope));
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
}
