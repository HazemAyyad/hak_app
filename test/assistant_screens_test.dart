import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/features/assistant/data/assistant_controller.dart';
import 'package:haq_app/features/assistant/data/billing_store.dart';
import 'package:haq_app/features/assistant/presentation/assistant_page.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/data/quran_sync.dart';
import 'package:haq_app/features/religious_content/data/religious_catalog.dart';
import 'package:haq_app/features/religious_content/data/religious_controller.dart';
import 'assistant_test.dart'
    show AssistantCloud, TestBillingStore, assistantReceipt;
import 'support/visual_audit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranController quran;
  late ReligiousController religious;
  late AssistantController c;
  late AssistantCloud cloud;
  late TestBillingStore store;
  late AppAppearance appearance;
  late QuranRepository repo;
  late ReligiousCatalog catalog;
  final capture = GlobalKey();
  setUpAll(() async {
    await loadVisualAuditFonts();
    repo = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    catalog = ReligiousCatalog.fromJson(
      jsonDecode(File('assets/religious/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    await (FontLoader(
      'QuranUI',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
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
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    appearance = AppAppearance(prefs);
    cloud = AssistantCloud();
    store = TestBillingStore();
    quran = QuranController(
      preferences: prefs,
      initialRepository: repo,
      accountFactory: (q) => QuranAccount(
        q,
        dio: Dio(BaseOptions(baseUrl: 'https://backend.test'))
          ..httpClientAdapter = cloud,
      ),
    );
    await quran.load();
    quran.account.profile = {
      'id': 1,
      'name': 'Reader',
      'email': 'reader@example.test',
    };
    quran.account.token = 'token-1';
    religious = ReligiousController(quran: quran, initialCatalog: catalog)
      ..catalog = catalog
      ..loading = false;
    c = AssistantController(
      quran,
      dio: Dio(BaseOptions(baseUrl: 'https://backend.test'))
        ..httpClientAdapter = cloud,
      store: store,
    );
  });
  tearDown(() {
    c.dispose();
    religious.dispose();
    quran.dispose();
    appearance.dispose();
    store.events.close();
  });
  Future<void> pump(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 8)),
      );
    }
  }

  Future<void> mount(
    WidgetTester tester, {
    bool dark = false,
    bool subscription = false,
    double scale = 1,
    Size size = const Size(360, 1100),
  }) async {
    await tester.binding.setSurfaceSize(visualSize(size));
    await tester.pumpWidget(
      AppearanceScope(
        controller: appearance,
        child: MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            fontFamily: 'QuranUI',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2A8C82),
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
          ),
          home: MediaQuery(
            data: MediaQueryData(
              size: visualSize(size),
              textScaler: TextScaler.linear(visualScale(scale)),
            ),
            child: RepaintBoundary(
              key: capture,
              child: AssistantPage(
                religious: religious,
                controller: c,
                subscription: subscription,
              ),
            ),
          ),
        ),
      ),
    );
    await pump(tester);
  }

  Future<void> tap(WidgetTester tester, String title) async {
    final found = find.text(title).last;
    await tester.ensureVisible(found);
    await tester.pump();
    await tester.tap(found);
    await pump(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pump(tester);
  }

  testWidgets('guest cannot buy or see a private conversation', (tester) async {
    await tester.runAsync(() => quran.account.logout());
    await mount(tester);
    expect(find.text('سجّل الدخول للمتابعة'), findsOneWidget);
    expect(find.text(r'$5.00'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(store.bought, 0);
    await unmount(tester);
  });
  testWidgets(
    'unconfigured assistant displays retry without a fake price or purchase success',
    (tester) async {
      cloud.enabled = false;
      await mount(tester);
      expect(find.text('المساعد غير متاح حاليًا'), findsOneWidget);
      expect(find.text('الاشتراك من المتجر'), findsNothing);
      expect(find.text(r'$5.00'), findsNothing);
      await tap(tester, 'إعادة المحاولة');
      expect(store.bought, 0);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
  testWidgets(
    'paywall uses actual store detail fixture and cancellation never unlocks questions',
    (tester) async {
      cloud.active = false;
      await mount(tester);
      expect(find.text(r'$5.00'), findsOneWidget);
      await tap(tester, 'الاشتراك من المتجر');
      store.emit(BillingState.canceled, owner: cloud.token(1));
      await pump(tester);
      expect(c.active, false);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('أُلغي الشراء؛ لم يتفعّل اشتراك'), findsOneWidget);
      expect(store.bought, 1);
      await unmount(tester);
    },
  );
  testWidgets(
    'question requires consent then renders server explanation separately from canonical sources',
    (tester) async {
      await mount(tester);
      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'سؤال اختبار');
      await pump(tester);
      final send = find.widgetWithText(FilledButton, 'إرسال السؤال');
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      final consent = find.byType(CheckboxListTile);
      await tester.ensureVisible(consent);
      await tester.tap(consent);
      await pump(tester);
      await tap(tester, 'إرسال السؤال');
      expect(cloud.generations, 1);
      expect(find.text('شرح آلي • قد يخطئ'), findsOneWidget);
      expect(find.text('النصوص الأصلية ومصادرها'), findsOneWidget);
      expect(find.text('مصدر الاختبار'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
  testWidgets(
    'changing account removes private draft field and source cards immediately',
    (tester) async {
      await mount(tester);
      await tester.enterText(find.byType(TextField), 'سؤال خاص قبل الخروج');
      await tester.runAsync(() => quran.account.logout());
      await pump(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('سجّل الدخول للمتابعة'), findsOneWidget);
      expect(find.text('سؤال خاص قبل الخروج'), findsNothing);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'paywall conversation and confirmation fit 320px at 150 percent ${dark ? 'dark' : 'light'}',
      (tester) async {
        cloud.active = false;
        await mount(
          tester,
          dark: dark,
          subscription: true,
          size: const Size(320, 780),
          scale: 1.5,
        );
        await tester.drag(find.byType(ListView).first, const Offset(0, -1100));
        await pump(tester);
        expect(tester.takeException(), isNull);
        await unmount(tester);
        cloud.active = true;
        cloud.receipts['fixture'] = assistantReceipt();
        await mount(tester, dark: dark, size: const Size(320, 780), scale: 1.5);
        await tester.ensureVisible(find.byTooltip('حذف السؤال'));
        await tester.pump();
        await tester.tap(find.byTooltip('حذف السؤال'));
        await pump(tester);
        await tap(tester, 'إلغاء');
        expect(cloud.receipts.length, 1);
        await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
        await pump(tester);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      },
    );
  }
  testWidgets(
    'assistant subscription chat and unavailable previews in approved light and dark identity',
    (tester) async {
      final folder = Directory(visualPath('build/p12-previews'));
      await tester.runAsync(() => folder.create(recursive: true));
      final canonical = catalog.items.firstWhere(
        (e) => e.text.isNotEmpty && e.source.isNotEmpty,
      );
      for (final dark in [false, true]) {
        for (final mode in ['gate', 'subscription', 'chat', 'unavailable']) {
          cloud.enabled = mode != 'unavailable';
          cloud.active = mode == 'chat';
          cloud.receipts.clear();
          if (mode == 'chat') {
            cloud.receipts['fixture'] = {
              ...assistantReceipt(),
              'sources': [
                {
                  'id': canonical.id,
                  'text': canonical.text,
                  'source': canonical.source,
                },
              ],
            };
          }
          await mount(
            tester,
            dark: dark,
            subscription: mode == 'subscription',
            size: const Size(390, 1900),
          );
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '${folder.path}/$mode-${dark ? 'dark' : 'light'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
          expect(tester.takeException(), isNull);
          await unmount(tester);
        }
      }
    },
  );
}
