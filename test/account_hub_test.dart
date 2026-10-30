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
import 'package:haq_app/core/localization/app_localization.dart';
import 'support/visual_audit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late QuranController quran;
  late ReligiousController content;
  late ReligiousActivityStore store;
  late AppAppearance appearance;
  final capture = GlobalKey();
  setUpAll(() async {
    await loadVisualAuditFonts();
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
    AppLocalization? localization,
  }) async {
    await tester.binding.setSurfaceSize(visualSize(size));
    final screen = MaterialApp(
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
          size: visualSize(size),
          textScaler: TextScaler.linear(visualScale(scale)),
        ),
        child: Directionality(
          textDirection: localization?.language.direction ?? TextDirection.rtl,
          child: RepaintBoundary(
            key: capture,
            child: AppearanceScope(
              controller: appearance,
              child: Scaffold(body: AccountHubPage(controller: content)),
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
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 8)),
      );
    }
  }

  testWidgets(
    'English account forms preserve typed Arabic names and credentials on a narrow screen',
    (tester) async {
      final localization = AppLocalization(
        await SharedPreferences.getInstance(),
      );
      await localization.select('en');
      addTearDown(localization.dispose);
      await mount(
        tester,
        size: const Size(320, 760),
        scale: 1.2,
        localization: localization,
      );
      expect(find.text('Account and sync'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      await tester.ensureVisible(find.text('Create a new account'));
      await tester.tap(find.text('Create a new account'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'حفظ');
      await tester.enterText(fields.at(1), 'reader@example.test');
      await tester.enterText(fields.at(2), 'Private-value-123');
      expect(
        tester.widget<TextFormField>(fields.at(0)).controller!.text,
        'حفظ',
      );
      expect(
        tester.widget<TextFormField>(fields.at(1)).controller!.text,
        'reader@example.test',
      );
      expect(
        tester.widget<TextFormField>(fields.at(2)).controller!.text,
        'Private-value-123',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

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
    final folder = Directory(visualPath('build/p10-account-preview'))
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
      if (visualAudit) {
        await captureAuditContinuation(
          tester,
          capture,
          '${folder.path}/${dark ? 'dark' : 'light'}.png',
        );
        final register = find.text('إنشاء حساب جديد');
        await tester.ensureVisible(register);
        await tester.tap(register);
        await tester.pumpAndSettle();
        final firstScroll = find.byType(Scrollable).first;
        final scrollState = tester.state<ScrollableState>(firstScroll);
        scrollState.position.jumpTo(0);
        await tester.pump();
        await tester.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await File(
            '${folder.path}/register-${dark ? 'dark' : 'light'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
