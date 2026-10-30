import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:haq_app/main.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/core/localization/app_localization.dart';
import 'package:haq_app/features/admin/presentation/admin_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/features/account/data/app_session.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/data/quran_sync.dart';
import 'quran_media_test.dart' show StubHttp;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranController quran;
  late AppSession session;
  var admin = false, deny = false;
  var conflict = false, rootOwnsSession = false;
  final requests = <RequestOptions>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    admin = false;
    deny = false;
    conflict = false;
    rootOwnsSession = false;
    requests.clear();
    final personal = Dio(BaseOptions(baseUrl: 'https://backend.test/api/v1'))
      ..httpClientAdapter = StubHttp(
        (request) => ResponseBody.fromString(
          jsonEncode({
            'data': request.path == '/quran/sync'
                ? {
                    'entities': {},
                    'acknowledged': [],
                    'conflicts': [],
                    'revision': 0,
                  }
                : {},
          }),
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
    quran = QuranController(
      preferences: await SharedPreferences.getInstance(),
      initialRepository: QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
      accountFactory: (c) => QuranAccount(c, dio: personal),
    );
    await quran.load();
    final dio = Dio(BaseOptions(baseUrl: 'https://backend.test/api/v2'))
      ..httpClientAdapter = StubHttp((request) {
        requests.add(request);
        if (conflict && request.method == 'PUT') {
          return ResponseBody.fromString(
            '{}',
            409,
            headers: {
              'content-type': ['application/json'],
            },
          );
        }
        if (deny) {
          return ResponseBody.fromString(
            '{}',
            403,
            headers: {
              'content-type': ['application/json'],
            },
          );
        }
        final account = {
          'id': 4,
          'name': 'Test',
          'areas': ['association'],
          'account_type': 'association',
          'admin_access': admin,
          'permissions': admin ? ['admin.enter', 'translations.edit'] : [],
        };
        final Object data;
        if (request.path == '/account/login') {
          data = {'token': 'root-token', 'account': account};
        } else if (request.path == '/account/session') {
          data = account;
        } else if (request.path == '/admin/session') {
          data = {
            'token': 'admin-token',
            'expires_at': DateTime.now()
                .add(const Duration(minutes: 30))
                .toIso8601String(),
            'permissions': ['admin.enter', 'translations.edit'],
          };
        } else if (request.path == '/admin/languages') {
          data = <Object>[];
        } else {
          data = <String, dynamic>{};
        }
        return ResponseBody.fromString(
          jsonEncode({'data': data}),
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      });
    session = AppSession(quran.account, dio: dio);
    await session.initialize();
  });
  tearDown(() {
    if (!rootOwnsSession) session.dispose();
    quran.dispose();
  });

  test(
    'association-only user does not become a religious sync account or an administrator',
    () async {
      expect(
        await session.login('association', 'test@example.test', 'password'),
        true,
      );
      expect(session.areas, ['association']);
      expect(session.admin, false);
      expect(quran.account.profile, isNull);
      expect(quran.account.token, isNull);
      await expectLater(
        session.adminRequest('GET', 'languages'),
        throwsStateError,
      );
    },
  );

  test(
    'admin receives a separate short session and loses access immediately on rejection',
    () async {
      admin = true;
      expect(
        await session.login('association', 'test@example.test', 'password'),
        true,
      );
      expect(session.admin, true);
      await session.adminRequest('GET', 'languages');
      expect(
        requests
            .firstWhere((r) => r.path == '/admin/session')
            .headers['Authorization'],
        'Bearer root-token',
      );
      expect(
        requests
            .firstWhere((r) => r.path == '/admin/languages')
            .headers['Authorization'],
        'Bearer admin-token',
      );
      deny = true;
      await expectLater(
        session.adminRequest('GET', 'languages'),
        throwsA(isA<DioException>()),
      );
      expect(session.admin, false);
      expect(quran.account.token, isNull);
    },
  );

  test('unverified cached role never authorizes administration', () async {
    admin = true;
    await session.login('association', 'test@example.test', 'password');
    session.verified = false;
    expect(session.admin, false);
    await expectLater(
      session.adminRequest('GET', 'languages'),
      throwsStateError,
    );
  });

  test(
    'simultaneous administrative reads exchange the short session only once',
    () async {
      admin = true;
      await session.login('association', 'test@example.test', 'password');
      await Future.wait([
        session.adminRequest('GET', 'languages'),
        session.adminRequest('GET', 'languages'),
      ]);
      expect(
        requests.where((request) => request.path == '/admin/session').length,
        1,
      );
    },
  );

  test(
    'logout clears aggregate secrets without moving Quran guest data',
    () async {
      quran.toggleFavorite('2:3');
      await session.login('association', 'test@example.test', 'password');
      await session.logout();
      expect(session.profile, isNull);
      expect(session.permissions, isEmpty);
      expect(
        await const FlutterSecureStorage().read(key: AppSession.storageKey),
        isNull,
      );
      expect(quran.favorites.containsKey('2:3'), true);
    },
  );

  testWidgets(
    'administrator enters the in-app dashboard once and can return to the app',
    (tester) async {
      admin = true;
      rootOwnsSession = true;
      final appearance = AppAppearance(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        HaqApp(
          showStartup: false,
          appearance: appearance,
          quranController: quran,
          appSessionFactory: (_) => session,
        ),
      );
      await tester.pumpAndSettle();
      final signedIn = await tester.runAsync(
        () => session.login('association', 'test@example.test', 'password'),
      );
      expect(signedIn, true, reason: session.error);
      expect(session.admin, true);
      await tester.pumpAndSettle();
      expect(find.byType(AdminPage), findsOneWidget);
      await tester.tap(find.byTooltip('عرض التطبيق'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminPage), findsNothing);
      await tester.runAsync(session.refresh);
      await tester.pumpAndSettle();
      expect(find.byType(AdminPage), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      appearance.dispose();
    },
  );

  testWidgets(
    'editor retains a conflicting draft; logout immediately hides private editor content',
    (tester) async {
      admin = true;
      conflict = true;
      await tester.runAsync(
        () => session.login('association', 'test@example.test', 'password'),
      );
      final localization = AppLocalization(
        await SharedPreferences.getInstance(),
      );
      await localization.select('en');
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        LocalizationScope(
          controller: localization,
          child: MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.2)),
              child: child!,
            ),
            home: AdminEditorPage(
              session: session,
              locale: 'en',
              row: {
                'kind': 'ui',
                'key': 'ui/nav.home',
                'original': 'الرئيسية',
                'value': 'Home',
                'revision': 1,
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'My unsaved translation');
      await tester.ensureVisible(find.text('Save draft'));
      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();
      expect(find.text(localization.text('admin.conflict')), findsOneWidget);
      expect(find.text('My unsaved translation'), findsOneWidget);
      await tester.runAsync(() => session.logout());
      await tester.pumpAndSettle();
      expect(find.text('My unsaved translation'), findsNothing);
      expect(find.text(localization.text('admin.denied')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      localization.dispose();
    },
  );
}
