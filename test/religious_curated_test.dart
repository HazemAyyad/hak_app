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
import 'package:haq_app/core/localization/app_localization.dart';
import 'package:haq_app/features/adhkar/data/adhkar_repository.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/religious_activity/data/activity_controller.dart';
import 'package:haq_app/features/religious_activity/data/activity_models.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'package:haq_app/features/religious_content/data/religious_catalog.dart';
import 'package:haq_app/features/religious_content/data/religious_controller.dart';
import 'package:haq_app/features/religious_content/presentation/religious_host.dart';
import 'package:haq_app/features/religious_content/presentation/religious_widgets.dart'
    show ReligiousHeader;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/visual_audit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late QuranRepository quranData;
  late ReligiousCatalog catalog;
  late AdhkarRepository adhkar;
  late QuranController quran;
  late ReligiousController religious;
  late ReligiousActivityStore store;
  late ReligiousActivityController activity;
  late AppAppearance appearance;
  final host = GlobalKey<ReligiousHostState>(), preview = GlobalKey();
  setUpAll(() async {
    await loadVisualAuditFonts();
    quranData = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    catalog = await ReligiousCatalog.load();
    adhkar = await AdhkarRepository.load(quranData);
    for (final image in [
      'header-moods',
      'mood-happy',
      'mood-sad',
      'mood-anxiety',
      'mood-rest',
      'mood-love',
      'mood-contentment',
    ]) {
      final ready = Completer<void>();
      final stream = AssetImage(
        'assets/navigation/$image.png',
      ).resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener((_, _) {
        if (!ready.isCompleted) ready.complete();
      });
      stream.addListener(listener);
      await ready.future;
      stream.removeListener(listener);
    }
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
  });
  setUp(() async {
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
      initialAdhkarCatalog: adhkar,
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
    WidgetTester tester,
    String category, {
    bool dark = false,
    double width = 426,
    AppLocalization? localization,
  }) async {
    tester.view.physicalSize = visualSize(Size(width, 1100));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final screen = AppearanceScope(
      controller: appearance,
      child: RepaintBoundary(
        key: preview,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: 'QuranUI',
            colorScheme: visualAudit
                ? ColorScheme.fromSeed(
                    seedColor: const Color(0xFF2A8C82),
                    primary: const Color(0xFF2A8C82),
                    secondary: const Color(0xFFC7A45A),
                    brightness: dark ? Brightness.dark : Brightness.light,
                  )
                : null,
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                visualScale(width == 320 ? 1.2 : 1),
              ),
            ),
            child: Directionality(
              textDirection:
                  localization?.language.direction ?? TextDirection.rtl,
              child: child!,
            ),
          ),
          home: Scaffold(
            body: ReligiousHost(
              key: host,
              controller: religious,
              onClose: () {},
              initialCategory: category,
              initialCategoryAsRoot: true,
            ),
          ),
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
    await tester.pump();
    await tester.runAsync(() async {
      final boundary =
          preview.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File(visualPath('build/content-preview/$name.png'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    });
    await captureAuditContinuation(
      tester,
      preview,
      visualPath('build/content-preview/$name.png'),
    );
  }

  test(
    '17 moods and 30 suggested days contain explicit valid IDs and canonical Quran',
    () {
      expect(catalog.moods, hasLength(17));
      expect(catalog.ramadanDays, hasLength(30));
      for (final mood in catalog.moods) {
        expect(mood.itemIds, isNotEmpty);
        for (final id in mood.itemIds) {
          expect(catalog.byId[id]!.categories, contains('mood-${mood.id}'));
        }
      }
      for (final item in catalog.items.where((item) => item.type == 'quran')) {
        expect(
          item.text,
          item.verseKeys.map((key) => quranData.byKey[key]!.text).join('\n'),
        );
      }
      expect(catalog.ramadanDaysNote, contains('لا تثبت'));
      expect(catalog.search(category: 'hadith'), hasLength(46));
    },
  );
  test(
    'old cache preserves editorial changes and hidden records while receiving bundled additions',
    () {
      final bundled =
              jsonDecode(
                    File('assets/religious/catalog.json').readAsStringSync(),
                  )
                  as Map<String, dynamic>,
          extensions = bundled['bundled_extensions'] as Map;
      final newCategories = Set<String>.from(
            extensions['category_ids'] as List,
          ),
          newItems = Set<String>.from(extensions['item_ids'] as List);
      final legacy = <String, dynamic>{
        'version': 'old-admin',
        'categories': (bundled['categories'] as List)
            .where((c) => !newCategories.contains(c['id']))
            .toList(),
        'items': [
          for (final item in bundled['items'] as List)
            if (!newItems.contains(item['id']) && item['id'] != 'hisn-034')
              {
                ...Map<String, dynamic>.from(item as Map),
                'categories': (item['categories'] as List)
                    .where((id) => !newCategories.contains(id))
                    .toList(),
                if (item['id'] == 'hisn-035') 'title': 'تحرير إدارة قديم',
              },
        ],
      };
      final result = catalog.extendLegacy(legacy);
      expect(result.moods, hasLength(17));
      expect(result.byId.containsKey('hisn-034'), false);
      expect(result.byId['hisn-035']!.title, 'تحرير إدارة قديم');
      expect(
        result.moods.firstWhere((m) => m.id == 'sad').itemIds,
        isNot(contains('hisn-034')),
      );
      expect(result.sourceVersion, 'old-admin');
      expect(result.ramadanDays, hasLength(30));
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'all 17 mood cards fit enlarged narrow ${dark ? 'dark' : 'light'}',
      (tester) async {
        await pump(tester, 'feelings', dark: dark, width: 320);
        await capture(tester, 'moods-${dark ? 'dark' : 'light'}');
        for (final mood in catalog.moods) {
          await tester.scrollUntilVisible(
            find.byKey(ValueKey('mood-${mood.id}')),
            180,
            scrollable: find.byType(Scrollable).last,
          );
          await settle(tester);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'English mood controls preserve Arabic scripture and daily counts through locale changes',
    (tester) async {
      final localization = AppLocalization(
        await SharedPreferences.getInstance(),
      );
      await localization.select('en');
      addTearDown(localization.dispose);
      await pump(tester, 'feelings', width: 320, localization: localization);
      expect(find.text('How are you feeling?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mood-happy')));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byType(ReligiousHeader),
          matching: find.text('Happiness'),
        ),
        findsOneWidget,
      );
      final original = catalog.byId['qdua-thankfulness']!.text;
      final scripture = find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == original,
      );
      expect(scripture, findsOneWidget);
      expect(
        tester.widget<SelectableText>(scripture).textDirection,
        TextDirection.rtl,
      );
      final count = find.byKey(const ValueKey('mood-count-qdua-thankfulness'));
      await tester.ensureVisible(count);
      await tester.tap(count);
      await settle(tester);
      expect(
        find.descendant(of: count, matching: find.text('0')),
        findsOneWidget,
      );
      final before = (await store.entities(
        activity.scope,
      )).map((entity) => entity.toJson()).toList();
      await localization.select('ar');
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byType(ReligiousHeader),
        -180,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('mood-reader-happy')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await settle(tester);
      expect(
        find.descendant(
          of: find.byType(ReligiousHeader),
          matching: find.text('السعادة'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(count);
      await settle(tester);
      expect(
        find.descendant(of: count, matching: find.text('0')),
        findsOneWidget,
      );
      expect(catalog.byId['qdua-thankfulness']!.text, original);
      expect(
        (await store.entities(
          activity.scope,
        )).map((entity) => entity.toJson()).toList(),
        before,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'mood count stays red at zero, undoes its own card and keeps account history separate',
    (tester) async {
      await pump(tester, 'feelings');
      await tester.tap(find.byKey(const ValueKey('mood-happy')));
      await settle(tester);
      final first = find.byKey(const ValueKey('mood-count-qdua-thankfulness'));
      await tester.ensureVisible(first);
      await tester.tap(first);
      await settle(tester);
      expect(
        find.descendant(of: first, matching: find.text('0')),
        findsOneWidget,
      );
      await tester.tap(first);
      await settle(tester);
      final events = await tester.runAsync(() => store.events('guest'));
      expect(events!.where((e) => e.kind == ActivityKind.count), hasLength(1));
      await tester.tap(find.byTooltip('تراجع').first);
      await settle(tester);
      expect(
        find.descendant(of: first, matching: find.text('1')),
        findsOneWidget,
      );
      await capture(tester, 'mood-count');
      quran.account.profile = {'id': 7};
      activity.changed('account.7');
      await settle(tester);
      expect(
        find.byKey(const ValueKey('mood-count-qdua-thankfulness')),
        findsNothing,
      );
      expect(await tester.runAsync(() => store.events('account.7')), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'praise route uses sourced counters and clamp without replacing the old detail reader',
    (tester) async {
      await pump(tester, 'praise');
      // Resolve by the actual reviewed chapter membership, not a guessed amount.
      final source = adhkar.items.values.firstWhere(
        (entry) => entry.haqContentId == 'hisn-070',
      );
      final target = find.byKey(ValueKey('mood-count-${source.id}'));
      await tester.scrollUntilVisible(
        target,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(target);
      await settle(tester);
      expect(
        find.descendant(
          of: target,
          matching: find.text('${source.target - 1}'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Ramadan has thirty selectable days and hadith reading separates matn from explanation',
    (tester) async {
      await pump(tester, 'ramadan-duas');
      expect(find.text('اليوم 1'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('اليوم 30'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await capture(tester, 'ramadan-days');
      await tester.pumpWidget(const SizedBox());
      await pump(tester, 'hadith');
      await tester.tap(find.text(catalog.byId['nawawi-01']!.title));
      await settle(tester);
      expect(find.byType(SegmentedButton<bool>), findsOneWidget);
      await tester.tap(find.text('الشرح'));
      await settle(tester);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data == catalog.byId['nawawi-01']!.text,
        ),
        findsNothing,
      );
      expect(
        find.text(catalog.byId['nawawi-01']!.sections.first.text),
        findsOneWidget,
      );
      await capture(tester, 'hadith-explanation');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'English hadith controls copy the original narration and preserve favorites through locale changes',
    (tester) async {
      final localization = AppLocalization(
        await SharedPreferences.getInstance(),
      );
      await localization.select('en');
      addTearDown(localization.dispose);
      final item = catalog.byId['nawawi-01']!;
      final copied = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await pump(tester, 'hadith', width: 320, localization: localization);
      await tester.tap(find.text(item.title));
      await settle(tester);
      expect(find.text('Narration'), findsOneWidget);
      expect(find.text('Explanation'), findsOneWidget);
      final readerScroll = find
          .descendant(
            of: find.byKey(const PageStorageKey('religious-details-nawawi-01')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byTooltip('Copy'),
        180,
        scrollable: readerScroll,
      );
      await settle(tester);
      await tester.tap(find.byTooltip('Copy'));
      await settle(tester);
      expect(copied.single, item.copyText);
      await tester.tap(find.byTooltip('Favorites').last);
      await settle(tester);
      expect(religious.favorites, contains(item.id));
      await tester.tap(find.byTooltip('Font size'));
      await settle(tester);
      expect(find.text('Reading font size'), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(40, 0));
      await settle(tester);
      expect(
        quran.preferences!.getDouble('religious.fontSize.hadith'),
        isNotNull,
      );
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Explanation'),
        -180,
        scrollable: readerScroll,
      );
      await settle(tester);
      await tester.tap(find.text('Explanation'));
      await settle(tester);
      expect(find.text(item.sections.first.text), findsOneWidget);
      await localization.select('ar');
      await settle(tester);
      expect(religious.favorites, contains(item.id));
      expect(catalog.byId[item.id]!.text, item.text);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  if (visualAudit) {
    testWidgets('Ramadan entry and its real daily content at normal size', (
      tester,
    ) async {
      for (final dark in [false, true]) {
        for (final category in ['ramadan', 'ramadan-duas']) {
          await pump(tester, category, dark: dark);
          await capture(tester, '$category-${dark ? 'dark' : 'light'}');
          await tester.pumpWidget(const SizedBox());
        }
      }
    });
  }
}
