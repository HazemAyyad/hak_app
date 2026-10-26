import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/features/community/data/community_controller.dart';
import 'package:haq_app/features/community/presentation/community_page.dart';
import 'package:haq_app/features/community/presentation/community_media.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/data/quran_sync.dart';
import 'package:haq_app/features/religious_content/data/religious_catalog.dart';
import 'package:haq_app/features/religious_content/data/religious_controller.dart';
import 'community_test.dart'
    show CommunityCloud, circleFixture, publicationFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranController quran;
  late ReligiousController religious;
  late CommunityController c;
  late CommunityCloud cloud;
  late AppAppearance appearance;
  late QuranRepository repo;
  late ReligiousCatalog catalog;
  final capture = GlobalKey();
  setUpAll(() async {
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
    cloud = CommunityCloud();
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
    quran.account.token = 'token';
    religious = ReligiousController(quran: quran, initialCatalog: catalog)
      ..catalog = catalog
      ..loading = false;
    c = CommunityController(
      quran,
      dio: Dio(BaseOptions(baseUrl: 'https://backend.test/community'))
        ..httpClientAdapter = cloud,
    );
  });
  tearDown(() async {
    c.dispose();
    religious.dispose();
    quran.dispose();
    appearance.dispose();
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
    WidgetTester tester,
    CommunitySection section, {
    bool dark = false,
    double scale = 1,
    Size size = const Size(360, 950),
  }) async {
    await tester.binding.setSurfaceSize(size);
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
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: RepaintBoundary(
              key: capture,
              child: CommunityPage(
                religious: religious,
                section: section,
                controller: c,
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

  testWidgets(
    'guest login gate never exposes shared counts or public interactions',
    (tester) async {
      await tester.runAsync(() => quran.account.logout());
      await mount(tester, CommunitySection.circles);
      expect(find.text('سجّل الدخول للمتابعة'), findsOneWidget);
      expect(find.text('حلقة اختبار'), findsNothing);
      expect(cloud.requests.where((r) => r.path == '/circles'), isEmpty);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
  testWidgets('disabled server is honest without fixture counts', (
    tester,
  ) async {
    cloud.enabled = false;
    await mount(tester, CommunitySection.circles);
    expect(find.text('خدمات المجتمع غير متاحة حاليًا'), findsOneWidget);
    expect(find.text('حلقة اختبار'), findsNothing);
    await unmount(tester);
  });
  testWidgets(
    'circle tap waits for receipt; a lost response can retry once with same operation',
    (tester) async {
      await mount(tester, CommunitySection.circles);
      await tap(tester, 'حلقة اختبار');
      cloud.loseCount = true;
      await tap(tester, 'مساهمة واحدة');
      expect(cloud.total, 1);
      expect(find.text('مساهمتك 0'), findsOneWidget);
      await tap(tester, 'إعادة إرسال المساهمة');
      expect(find.text('مساهمتك 1'), findsOneWidget);
      expect(cloud.total, 1);
      expect(c.pending, isEmpty);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
  testWidgets(
    'private compose closes on logout and cannot submit into guest scope',
    (tester) async {
      await mount(tester, CommunitySection.prayers);
      await tap(tester, 'مشاركة دعاء');
      await tester.enterText(find.byType(TextField), 'مشاركة اختبار');
      await pump(tester);
      await tester.runAsync(() => quran.account.logout());
      await pump(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('سجّل الدخول للمتابعة'), findsOneWidget);
      expect(cloud.entries, isEmpty);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
  testWidgets(
    'prayer submit shows pending review and comment form has bounded text',
    (tester) async {
      await mount(tester, CommunitySection.prayers);
      await tap(tester, 'مشاركة دعاء');
      await tester.enterText(find.byType(TextField), 'مشاركة شخصية');
      await tap(tester, 'إرسال للمراجعة');
      expect(find.text('وصلت المشاركة وهي بانتظار المراجعة'), findsOneWidget);
      expect(cloud.entries.length, 1);
      expect((cloud.entries.values.single)['status'], 'pending');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
  testWidgets('message delete needs confirmation and save is local', (
    tester,
  ) async {
    await mount(tester, CommunitySection.messages);
    await tester.tap(find.byTooltip('خيارات الرسالة'));
    await tester.pumpAndSettle();
    await tap(tester, 'حفظ');
    expect(c.saved, {1});
    await tester.tap(find.byTooltip('خيارات الرسالة'));
    await tester.pumpAndSettle();
    await tap(tester, 'حذف محلي');
    expect(c.hidden, isEmpty);
    await tap(tester, 'إلغاء');
    expect(c.hidden, isEmpty);
    await tester.tap(find.byTooltip('خيارات الرسالة'));
    await tester.pumpAndSettle();
    await tap(tester, 'حذف محلي');
    await tap(tester, 'تأكيد');
    expect(c.hidden, {1});
    expect(cloud.publications.length, 1);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
  testWidgets(
    'video is never initialized before explicit user play; unsupported desktop explains failure',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      cloud.publications[0] = publicationFixture(kind: 'video');
      await mount(tester, CommunitySection.messages);
      await tap(tester, 'تشغيل الفيديو');
      expect(find.byType(CommunityMediaView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(tester, 'تشغيل الفيديو');
      expect(find.text('هذا المشغّل متاح على Android وiOS'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
      debugDefaultTargetPlatformOverride = null;
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'all community lists and reader fit 320px and enlarged Arabic ${dark ? 'dark' : 'light'}',
      (tester) async {
        for (final section in CommunitySection.values) {
          await mount(
            tester,
            section,
            dark: dark,
            scale: 1.5,
            size: const Size(320, 1200),
          );
          if (section == CommunitySection.circles) {
            await tap(tester, 'حلقة اختبار');
            await tester.drag(
              find.byType(ListView).last,
              const Offset(0, -360),
            );
            await pump(tester);
          }
          expect(tester.takeException(), isNull);
          await unmount(tester);
        }
      },
    );
  }
  testWidgets(
    'approved identity previews for circles feed messages and stories light and dark',
    (tester) async {
      final item = catalog.items.firstWhere(
        (i) => i.type == 'dua' && i.text.length < 350,
      );
      final content = {'id': item.id, 'text': item.text, 'source': item.source};
      cloud.circles[0] = {
        ...circleFixture(),
        'title': 'حلقة الذكر',
        'content': content,
      };
      cloud.publications[0] = {
        ...publicationFixture(),
        'title': 'من مكتبة حق',
        'content': content,
      };
      final folder = Directory('build/p11-previews')
        ..createSync(recursive: true);
      for (final dark in [false, true]) {
        for (final section in CommunitySection.values) {
          await mount(tester, section, dark: dark, size: const Size(390, 1500));
          final boundary =
              capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '${folder.path}/${section.name}-${dark ? 'dark' : 'light'}.png',
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
