import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/core/localization/app_localization.dart';
import 'package:haq_app/core/localization/hadith_translation_source.dart';
import 'package:haq_app/core/localization/language_page.dart';
import 'package:haq_app/features/account/data/app_session.dart';
import 'package:haq_app/features/admin/presentation/admin_hadith_sources_page.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'quran_media_test.dart' show StubHttp;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> artifact;
  late String original;
  late Directory directory;
  late AppLocalization localization;
  late SimpleKeyPair key;
  late Map<String, String> publicKeys;
  late Map<String, dynamic> response;

  Map<String, dynamic> sourceEnvelope(Map value) {
    final raw = jsonEncode(value);
    return {
      'artifact': raw,
      'sha256': hash.sha256.convert(utf8.encode(raw)).toString(),
    };
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    artifact = Map<String, dynamic>.from(
      jsonDecode(
            File(
              'test/fixtures/published_hadith_fixture.json',
            ).readAsStringSync(),
          )
          as Map,
    );
    final catalog =
        jsonDecode(File('assets/religious/catalog.json').readAsStringSync())
            as Map;
    original =
        (catalog['items'] as List).firstWhere(
              (item) => item['id'] == 'nawawi-01',
            )['text']
            as String;
    directory = await Directory.systemTemp.createTemp('haq-hadith-client-');
    key = await Ed25519().newKeyPair();
    publicKeys = {'test': base64Encode((await key.extractPublicKey()).bytes)};
    final dio =
        Dio(BaseOptions(baseUrl: 'https://backend.test/api/v2/app-content'))
          ..httpClientAdapter = StubHttp(
            (_) => ResponseBody.fromString(
              jsonEncode({'data': response}),
              200,
              headers: {
                'content-type': ['application/json'],
              },
            ),
          );
    localization = AppLocalization(
      await SharedPreferences.getInstance(),
      dio: dio,
      publicKeys: publicKeys,
      directory: directory,
    );
    await localization.initialize();
    final payload = jsonEncode({
      'schema': 1,
      'locale': 'en',
      'version': 1,
      'strings': {
        for (final entry in localization.registry.entries)
          entry.key: entry.value['en']!,
      },
      'content': {},
      'hadith_source': sourceEnvelope(artifact),
    });
    final bytes = utf8.encode(payload);
    response = {
      'release_id': 1,
      'payload': payload,
      'bytes': bytes.length,
      'sha256': hash.sha256.convert(bytes).toString(),
      'key_id': 'test',
      'signature': base64Encode(
        (await Ed25519().sign(bytes, keyPair: key)).bytes,
      ),
    };
  });
  tearDown(() async {
    localization.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'PHP fixture retains quoted multiline CSV fields, full source information and original identity',
    () {
      final source = HadithTranslationSource.verify(
        sourceEnvelope(artifact),
        'en',
      );
      expect(source.source['version'], '1.25.0');
      expect(source.source['update_timezone'], 'unspecified');
      final row = source.forContent('nawawi-01', original)!;
      expect(row.length, 15);
      expect(
        row['hadith_text'],
        '  Fixture text with "quoted" words, comma\nand a new line  ',
      );
      expect(row['explanation'], '<p>Exact explanation &amp; formatting</p>');
      expect(row['benefits'], 'Original benefits');
      expect(source.forContent('nawawi-01', '$original changed'), isNull);
      expect(source.forContent('unknown', original), isNull);
      expect(() => row['hadith_text'] = 'modified', throwsUnsupportedError);
    },
  );

  test(
    'changed fields, raw CSV, extra records and wrong locales cannot pass the source validator',
    () {
      final changed = jsonDecode(jsonEncode(artifact)) as Map;
      changed['records']['123']['fields']['hadith_text'] = 'Altered text';
      expect(
        () => HadithTranslationSource.verify(sourceEnvelope(changed), 'en'),
        throwsFormatException,
      );
      changed['records']['123']['raw_csv'] += 'extra record';
      expect(
        () => HadithTranslationSource.verify(sourceEnvelope(changed), 'en'),
        throwsFormatException,
      );
      final malformed = jsonDecode(jsonEncode(artifact)) as Map;
      final raw = '${malformed['records']['123']['raw_csv']}\nsecond record';
      malformed['records']['123']['raw_csv'] = raw;
      malformed['records']['123']['sha256'] = hash.sha256
          .convert(utf8.encode(raw))
          .toString();
      expect(
        () => HadithTranslationSource.verify(sourceEnvelope(malformed), 'en'),
        throwsFormatException,
      );
      expect(
        () => HadithTranslationSource.verify(sourceEnvelope(artifact), 'fr'),
        throwsFormatException,
      );
      final reference = jsonDecode(jsonEncode(artifact)) as Map;
      reference['references']['nawawi-01']['source_id'] = '999';
      expect(
        () => HadithTranslationSource.verify(sourceEnvelope(reference), 'en'),
        throwsFormatException,
      );
      final metadata = jsonDecode(jsonEncode(artifact)) as Map;
      metadata['source']['update_url'] =
          'https://untrusted.test/en/check/en/v1.25.0';
      expect(
        () => HadithTranslationSource.verify(sourceEnvelope(metadata), 'en'),
        throwsFormatException,
      );
    },
  );

  test(
    'signed hadith packages install as content, restore offline and keep the last valid source after a bad update',
    () async {
      localization.published['en'] = 1;
      await LanguagePackage.verify(
        response,
        publicKeys,
        localization.registry,
        'en',
      );
      expect(await localization.install('en', contentOnly: true), isTrue);
      await localization.selectContent('en');
      expect(localization.code, 'ar');
      expect(
        localization.installed['en']!.hadithSource!.forContent(
          'nawawi-01',
          original,
        ),
        isNotNull,
      );
      final offline = AppLocalization(
        localization.preferences,
        directory: directory,
        publicKeys: publicKeys,
      );
      await offline.initialize();
      expect(offline.contentCode, 'en');
      expect(
        offline.installed['en']!.hadithSource!.source['version'],
        '1.25.0',
      );
      offline.dispose();
      response = {
        ...response,
        'release_id': 2,
        'signature': base64Encode(List.filled(64, 0)),
      };
      localization.published['en'] = 2;
      expect(await localization.install('en', contentOnly: true), isFalse);
      expect(
        localization.installed['en']!.hadithSource!.forContent(
          'nawawi-01',
          original,
        )!['benefits'],
        'Original benefits',
      );
    },
  );

  testWidgets(
    'narrow reader shows the attributed source in its own direction and retains the local Arabic original',
    (tester) async {
      localization.installed['en'] = LanguagePackage(
        'en',
        1,
        {},
        {},
        hadithSource: HadithTranslationSource.verify(
          sourceEnvelope(artifact),
          'en',
        ),
      );
      await localization.selectContent('en');
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        LocalizationScope(
          controller: localization,
          child: MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(original, textDirection: TextDirection.rtl),
                      ContentTranslationCard(
                        contentId: 'nawawi-01',
                        originalText: original,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(original), findsOneWidget);
      expect(find.text('Publisher fixture title'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('Publisher fixture title'))),
        TextDirection.ltr,
      );
      expect(find.text('HadeethEnc.com — v1.25.0'), findsOneWidget);
      await tester.ensureVisible(
        find.text(localization.text('hadith.publisherArabic')),
      );
      await tester.tap(find.text(localization.text('hadith.publisherArabic')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'نص المصدر العربي للاختبار فقط',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reviewer must confirm each mapped narration before approval on a narrow phone',
    (tester) async {
      final requests = <RequestOptions>[];
      const permissions = ['admin.enter', 'content.edit', 'review', 'publish'];
      final profile = {
        'id': 12,
        'name': 'Fixture reviewer',
        'areas': ['association'],
        'admin_access': true,
        'permissions': permissions,
      };
      final record = artifact['records']['123']['fields'];
      // Construct asynchronous clients in the real clock before driving widgets.
      final ready = await tester.runAsync(() async {
        final dio = Dio(BaseOptions(baseUrl: 'https://backend.test/api/v2'))
          ..httpClientAdapter = StubHttp((request) {
            requests.add(request);
            final Object data;
            if (request.path == '/account/login') {
              data = {'token': 'fictional-session', 'account': profile};
            } else if (request.path == '/admin/session') {
              data = {
                'token': 'fictional-admin',
                'permissions': permissions,
                'expires_at': DateTime.now()
                    .add(const Duration(minutes: 30))
                    .toIso8601String(),
              };
            } else if (request.method == 'POST') {
              data = {'reviewed': true};
            } else {
              final id =
                  request.uri.queryParameters['content_id'] ?? 'nawawi-01';
              data = {
                'id': 9,
                'status': 'ready',
                'revision': 1,
                'source': artifact['source'],
                'direction': 'ltr',
                'content_ids': ['nawawi-01', 'nawawi-02'],
                'content_id': id,
                'original': {
                  'id': id,
                  'title': 'Local fixture',
                  'text': 'أصل عربي للاختبار فقط',
                  'sourceUrl': 'https://example.test/fixture',
                },
                'record': record,
                'mapping_review_required': false,
              };
            }
            return ResponseBody.fromString(
              jsonEncode({'data': data}),
              200,
              headers: {
                'content-type': ['application/json'],
              },
            );
          });
        final quran = QuranController(
          preferences: await SharedPreferences.getInstance(),
          initialRepository: QuranRepository.fromJson(
            jsonDecode(File('assets/quran/quran.json').readAsStringSync())
                as Map<String, dynamic>,
          ),
        );
        await quran.load();
        final session = AppSession(quran.account, dio: dio);
        await session.initialize();
        if (!await session.login(
          'association',
          'reviewer@example.test',
          'fictional-value',
        )) {
          throw StateError(session.error ?? 'Fixture login failed');
        }
        await session.adminRequest('GET', 'languages/en/hadith-sources/9');
        return (session: session, quran: quran);
      });
      final session = ready!.session;
      addTearDown(() {
        session.dispose();
        ready.quran.dispose();
      });
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        LocalizationScope(
          controller: localization,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => AdminHadithReviewPage(
                        session: session,
                        locale: 'en',
                        importId: 9,
                      ),
                    ),
                  ),
                  child: const Text('Review fixture'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Review fixture'));
      await tester.pumpAndSettle();
      Finder approve() => find.byKey(const ValueKey('approve-hadith-source'));
      Future<void> confirm() async {
        final checkbox = find.byKey(const ValueKey('confirm-hadith-reference'));
        await tester.scrollUntilVisible(
          checkbox,
          400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
      }

      await tester.scrollUntilVisible(
        approve(),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<FilledButton>(approve()).onPressed, isNull);
      await confirm();
      expect(tester.widget<FilledButton>(approve()).onPressed, isNull);
      final selector = find.byKey(const ValueKey('review-hadith-reference'));
      await tester.scrollUntilVisible(
        selector,
        -400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('nawawi-02').last);
      await tester.pumpAndSettle();
      await confirm();
      await tester.ensureVisible(approve());
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(approve()).onPressed, isNotNull);
      await tester.tap(approve());
      await tester.pumpAndSettle();
      final review = requests.singleWhere(
        (request) => request.path.endsWith('/9/review'),
      );
      expect((review.data as Map)['references_confirmed'], [
        'nawawi-01',
        'nawawi-02',
      ]);
      expect(
        requests.where((request) => request.path.endsWith('/publish')),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
