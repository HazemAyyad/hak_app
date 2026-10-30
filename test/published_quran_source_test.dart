import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/core/localization/app_localization.dart';
import 'package:haq_app/core/localization/language_page.dart';
import 'package:haq_app/core/localization/published_meaning_card.dart';
import 'package:haq_app/core/localization/quran_translation_source.dart';
import 'quran_media_test.dart' show StubHttp;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocalization localization;
  late Directory directory;
  late Map<String, dynamic> artifact;
  late String contentId, verseKey;
  late SimpleKeyPair keyPair;
  late Map<String, String> publicKeys;
  late Map<String, dynamic> envelope;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('haq-source-package-');
    keyPair = await Ed25519().newKeyPair();
    publicKeys = {
      'test': base64Encode((await keyPair.extractPublicKey()).bytes),
    };
    final dio = Dio(
      BaseOptions(baseUrl: 'https://backend.test/api/v2/app-content'),
    );
    localization = AppLocalization(
      await SharedPreferences.getInstance(),
      directory: directory,
      publicKeys: publicKeys,
      dio: dio,
    );
    await localization.initialize();
    final catalog =
        jsonDecode(File('assets/religious/catalog.json').readAsStringSync())
            as Map;
    final item =
        (catalog['items'] as List).firstWhere((row) => row['type'] == 'quran')
            as Map;
    contentId = item['id'] as String;
    verseKey = (item['verseKeys'] as List).first as String;
    final surah = verseKey.split(':').first;
    final quran =
        jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map;
    final raw = jsonEncode({
      'result': [
        for (final verse in quran['verses'] as List)
          if ((verse['key'] as String).startsWith('$surah:'))
            {
              'sura': surah,
              'aya': (verse['key'] as String).split(':')[1],
              'translation': verse['key'] == verseKey
                  ? 'Meaning <b>published</b><sup>1</sup>'
                  : 'Translation ${verse['key']}',
              'footnotes': '<p>(1) Source note.</p>',
              'arabic_text': verse['text'],
            },
      ],
    });
    artifact = {
      'format': 'haq.source.review',
      'schema': 1,
      'provider': 'QuranEnc.com',
      'locale': 'en',
      'source': {
        'key': 'english_rwwad',
        'language_iso_code': 'en',
        'version': '1.0.20',
        'title': 'Published source',
        'direction': 'ltr',
      },
      'attribution': 'QuranEnc.com — Published source — v1.0.20',
      'policy_url': 'https://quranenc.com/en/home',
      'references': {
        contentId: [verseKey],
      },
      'surahs': {
        surah: {
          'raw_json': raw,
          'sha256': hash.sha256.convert(utf8.encode(raw)).toString(),
        },
      },
    };
    final sourceJson = jsonEncode(artifact);
    final payload = jsonEncode({
      'schema': 1,
      'locale': 'en',
      'version': 2,
      'strings': {
        for (final entry in localization.registry.entries)
          entry.key: entry.value['en']!,
      },
      'content': <String, Object>{},
      'quran_source': {
        'artifact': sourceJson,
        'sha256': hash.sha256.convert(utf8.encode(sourceJson)).toString(),
      },
    });
    final bytes = utf8.encode(payload);
    envelope = {
      'release_id': 5,
      'payload': payload,
      'bytes': bytes.length,
      'sha256': hash.sha256.convert(bytes).toString(),
      'key_id': 'test',
      'signature': base64Encode(
        (await Ed25519().sign(bytes, keyPair: keyPair)).bytes,
      ),
    };
    dio.httpClientAdapter = StubHttp(
      (request) => ResponseBody.fromString(
        jsonEncode({'data': envelope}),
        200,
        headers: {
          'content-type': ['application/json'],
        },
      ),
    );
    localization.published['en'] = 5;
  });
  tearDown(() async {
    localization.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'signed source preserves exact text, footnotes, edition and restores offline',
    () async {
      expect(await localization.install('en'), true);
      await localization.select('en');
      final source = localization.installed['en']!.quranSource!;
      expect(source.version, '1.0.20');
      expect(
        source.forContent(contentId).single.translation,
        'Meaning <b>published</b><sup>1</sup>',
      );
      expect(
        source.forContent(contentId).single.footnotes,
        '<p>(1) Source note.</p>',
      );
      final restored = AppLocalization(
        localization.preferences,
        directory: directory,
        publicKeys: publicKeys,
      );
      await restored.initialize();
      expect(
        restored.installed['en']!.quranSource!.forContent(contentId).single.key,
        verseKey,
      );
      restored.dispose();
    },
  );

  test(
    'source integrity, wrong language and missing references are rejected',
    () {
      final json = jsonEncode(artifact);
      final sourceEnvelope = {
        'artifact': json,
        'sha256': hash.sha256.convert(utf8.encode(json)).toString(),
      };
      expect(
        () => QuranTranslationSource.verify({
          ...sourceEnvelope,
          'sha256': 'bad',
        }, 'en'),
        throwsFormatException,
      );
      expect(
        () => QuranTranslationSource.verify(sourceEnvelope, 'fr'),
        throwsFormatException,
      );
      artifact['references'] = {
        'missing': ['114:200'],
      };
      final invalid = jsonEncode(artifact);
      expect(
        () => QuranTranslationSource.verify({
          'artifact': invalid,
          'sha256': hash.sha256.convert(utf8.encode(invalid)).toString(),
        }, 'en'),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'published meanings and footnotes render beside Arabic content with source attribution',
    (tester) async {
      await tester.runAsync(() => localization.install('en'));
      await localization.select('en');
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        LocalizationScope(
          controller: localization,
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [ContentTranslationCard(contentId: contentId)],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('QuranEnc.com — Published source — v1.0.20'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              (widget.textSpan?.toPlainText().contains('Meaning published1') ??
                  false),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              (widget.textSpan?.toPlainText().contains('(1) Source note.') ??
                  false),
        ),
        findsOneWidget,
      );
      expect(find.text(localization.text('content.missing')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('provider markup cannot load images or execute scripts', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PublishedTranslationText(
            '<img src="https://untrusted.test/image"><script>bad()</script><b>Safe text</b>',
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
    final text = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!
        .toPlainText();
    expect(text, 'Safe text');
  });
}
