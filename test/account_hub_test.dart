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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:haq_app/features/account/presentation/account_hub.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/data/quran_sync.dart';
import 'package:haq_app/features/religious_content/data/religious_catalog.dart';
import 'package:haq_app/features/religious_content/data/religious_controller.dart';
import 'package:haq_app/features/religious_activity/data/activity_controller.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'quran_media_test.dart' show StubHttp;
import 'package:haq_app/app_appearance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late QuranController quran;
  late ReligiousController content;
  late ReligiousActivityStore store;
  late AppAppearance appearance;
  final capture = GlobalKey();
  setUpAll(() async {
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
    final dio = Dio(BaseOptions(baseUrl: 'https://backend.test/api/v1'))
      ..httpClientAdapter = StubHttp(
        (_) => ResponseBody.fromString(
          jsonEncode({
            'data': {'google': false, 'recovery': false},
          }),
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
    quran = QuranController(
      preferences: prefs,
      initialRepository: QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
      accountFactory: (c) => QuranAccount(c, dio: dio),
    );
    await quran.load();
    store = await ReligiousActivityStore.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    final activity = await ReligiousActivityController.open(
      quran,
      store: store,
      enableSync: false,
    );
    content = ReligiousController(
      quran: quran,
      initialCatalog: ReligiousCatalog.fromJson(
        jsonDecode(File('assets/religious/catalog.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
      activityFactory: () async => activity,
    );
    await content.load();
  });
  tearDown(() async {
    content.dispose();
    quran.dispose();
    appearance.dispose();
    await Future<void>.delayed(Duration.zero);
    await store.close();
  });
  Future<void> mount(
    WidgetTester tester, {
    bool dark = false,
    double scale = 1,
    Size size = const Size(360, 1000),
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2A8C82),
            brightness: dark ? Brightness.dark : Brightness.light,
            primary: const Color(0xFF2A8C82),
          ),
          scaffoldBackgroundColor: dark
              ? const Color(0xFF081722)
              : const Color(0xFFFFFCF7),
          fontFamily: 'QuranUI',
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(
              key: capture,
              child: AppearanceScope(
                controller: appearance,
                child: Scaffold(body: AccountHubPage(controller: content)),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 8)),
      );
    }
  }

  testWidgets(
    'guest sees local backup and real section status without unconfigured Google or deletion',
    (tester) async {
      await mount(tester, size: const Size(360, 2600));
      expect(find.text('النسخ الاحتياطي والاستعادة'), findsOneWidget);
      expect(find.text('المحتوى والمفضلة'), findsOneWidget);
      expect(find.text('المتابعة باستخدام Google'), findsNothing);
      expect(find.text('حذف حساب حق'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'narrow account page supports enlarged Arabic text and dark mode',
    (tester) async {
      await mount(tester, dark: true, scale: 1.6, size: const Size(320, 900));
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'account profile exposes username completion and deletion only for signed in account',
    (tester) async {
      quran.account.profile = {
        'id': 1,
        'name': 'قارئ',
        'email': 'reader@example.test',
      };
      await mount(tester, size: const Size(360, 2600));
      expect(find.text('إكمال اسم المستخدم'), findsOneWidget);
      expect(find.text('حذف حساب حق'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => quran.account.logout());
    },
  );
  testWidgets('account preview light and dark', (tester) async {
    final folder = Directory('build/p10-account-preview')
      ..createSync(recursive: true);
    for (final dark in [false, true]) {
      await mount(tester, dark: dark, size: const Size(390, 2300));
      final boundary =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final picture = await boundary.toImage();
        try {
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(
            '${folder.path}/${dark ? 'dark' : 'light'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          picture.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
