import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/core/localization/app_localization.dart';
import 'package:haq_app/core/localization/bundled_localization.dart';
import 'package:haq_app/core/localization/language_page.dart';
import 'package:haq_app/features/religious_content/data/religious_catalog.dart';
import 'quran_media_test.dart' show StubHttp;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppLocalization controller;
  late SimpleKeyPair keyPair;
  late Map<String, dynamic> envelope;
  late Map<String, String> keys;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('haq-language-test-');
    keyPair = await Ed25519().newKeyPair();
    keys = {'test': base64Encode((await keyPair.extractPublicKey()).bytes)};
    final dio = Dio(
      BaseOptions(baseUrl: 'https://backend.test/api/v2/app-content'),
    );
    controller = AppLocalization(
      await SharedPreferences.getInstance(),
      dio: dio,
      directory: directory,
      publicKeys: keys,
    );
    final strings = {
      for (final entry in controller.registry.entries)
        entry.key: entry.value['en']!,
    };
    final payload = jsonEncode({
      'schema': 1,
      'locale': 'en',
      'version': 2,
      'strings': strings,
      'content': <String, dynamic>{},
    });
    final bytes = utf8.encode(payload);
    envelope = {
      'release_id': 9,
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
        jsonEncode({
          'data': request.path == '/bootstrap'
              ? {
                  'schema': 1,
                  'languages': [
                    {'locale': 'en', 'release_id': 9},
                  ],
                }
              : envelope,
        }),
        200,
        headers: {
          'content-type': ['application/json'],
        },
      ),
    );
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'content language is independent, persists and can follow the interface again',
    () async {
      expect(controller.code, 'ar');
      await controller.selectContent('en');
      expect(controller.code, 'ar');
      expect(controller.contentCode, 'en');
      final restored = AppLocalization(
        controller.preferences,
        directory: directory,
      );
      expect(restored.contentCode, 'en');
      restored.dispose();
      await expectLater(controller.selectContent('fr'), throwsStateError);
      expect(controller.contentCode, 'en');
      await controller.selectContent(null);
      expect(controller.contentCode, 'ar');
      await controller.select('en');
      expect(controller.contentCode, 'en');
    },
  );

  test(
    'content selection does not require changing system interface delegates',
    () async {
      final candidates = controller.languages.where(
        (language) => !AppLocalization.systemSupported(language),
      );
      if (candidates.isEmpty) {
        return; // A newer SDK may provide every target delegate.
      }
      final language = candidates.first;
      controller.installed[language.code] = LanguagePackage(
        language.code,
        1,
        {},
        {},
      );
      expect(controller.availableContent.contains(language), true);
      expect(controller.available.contains(language), false);
      await controller.selectContent(language.code);
      expect(controller.contentCode, language.code);
      expect(controller.code, 'ar');
      await expectLater(
        controller.select(language.code),
        throwsFormatException,
      );
      await controller.remove(language.code);
      expect(controller.installed.containsKey(language.code), true);
    },
  );

  test(
    '35 unique language identities; bundled startup and asset sources agree',
    () {
      expect(
        controller.languages.map((language) => language.code).toSet(),
        hasLength(35),
      );
      expect(
        jsonDecode(bundledUiJson),
        jsonDecode(File('assets/localization/ui.json').readAsStringSync()),
      );
      expect(
        jsonDecode(bundledLanguagesJson),
        jsonDecode(
          File('assets/localization/languages.json').readAsStringSync(),
        ),
      );
      expect(controller.text('nav.home'), 'الرئيسية');
      expect(controller.local('fr'), false);
      expect(controller.available.map((language) => language.code), [
        'ar',
        'en',
      ]);
    },
  );

  test(
    'valid exact-byte signature is required, tampering and unknown keys rejected',
    () async {
      final pack = await LanguagePackage.verify(
        envelope,
        keys,
        controller.registry,
        'en',
      );
      expect(pack.strings['nav.home'], 'Home');
      await expectLater(
        LanguagePackage.verify(
          {...envelope, 'payload': '${envelope['payload']} '},
          keys,
          controller.registry,
          'en',
        ),
        throwsFormatException,
      );
      await expectLater(
        LanguagePackage.verify(envelope, {}, controller.registry, 'en'),
        throwsFormatException,
      );
      await expectLater(
        LanguagePackage.verify(envelope, keys, controller.registry, 'ar'),
        throwsFormatException,
      );
    },
  );

  test('signed but incomplete package is rejected before activation', () async {
    final payload = jsonEncode({
      'schema': 1,
      'locale': 'en',
      'version': 3,
      'strings': {'nav.home': 'Home'},
      'content': {},
    });
    final bytes = utf8.encode(payload);
    final incomplete = {
      ...envelope,
      'payload': payload,
      'bytes': bytes.length,
      'sha256': hash.sha256.convert(bytes).toString(),
      'signature': base64Encode(
        (await Ed25519().sign(bytes, keyPair: keyPair)).bytes,
      ),
    };
    await expectLater(
      LanguagePackage.verify(incomplete, keys, controller.registry, 'en'),
      throwsFormatException,
    );
    expect(controller.code, 'ar');
  });

  test(
    'download activates only verified bytes and restores on a fresh controller offline',
    () async {
      await controller.refresh();
      expect(await controller.install('en'), true);
      await controller.select('en');
      expect(controller.text('nav.home'), 'Home');
      final restored = AppLocalization(
        controller.preferences,
        publicKeys: keys,
        directory: directory,
      );
      await restored.initialize();
      expect(restored.code, 'en');
      expect(restored.installed['en']!.version, 2);
      expect(restored.language.direction, TextDirection.ltr);
      restored.dispose();
    },
  );

  test(
    'failed replacement preserves previous installed package and selection',
    () async {
      await controller.refresh();
      expect(await controller.install('en'), true);
      await controller.select('en');
      envelope['signature'] = base64Encode(List<int>.filled(64, 0));
      expect(await controller.install('en'), false);
      expect(controller.installed['en']!.version, 2);
      expect(controller.code, 'en');
      expect(controller.text('nav.home'), 'Home');
    },
  );

  test(
    'fresh install retains every bundled Arabic content item and its original text',
    () async {
      final before = await ReligiousCatalog.load();
      await controller.select('en');
      final after = await ReligiousCatalog.load();
      expect(after.items.length, before.items.length);
      expect(after.byId.keys.toSet(), before.byId.keys.toSet());
      for (final item in before.items) {
        expect(after.byId[item.id]!.text, item.text);
      }
      expect(controller.content(before.items.first.id), isNull);
    },
  );

  testWidgets(
    'language selection is available offline with explicit partial-coverage notice',
    (tester) async {
      await tester.pumpWidget(
        LocalizationScope(
          controller: controller,
          child: const MaterialApp(home: LanguagePage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('language-interface-ar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('language-interface-en')),
        findsOneWidget,
      );
      expect(find.text('Français'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('language-interface-en')));
      await tester.pumpAndSettle();
      expect(controller.code, 'en');
      expect(find.text('App language'), findsOneWidget);
      expect(find.text(controller.text('language.scope')), findsOneWidget);
    },
  );
}
