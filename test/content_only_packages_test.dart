import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/core/localization/app_localization.dart';
import 'quran_media_test.dart' show StubHttp;

// All translations below are synthetic protocol fixtures, never published
// religious translations or evidence of Turkish language readiness.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppLocalization controller;
  late SimpleKeyPair signer;
  late Map<String, String> keys;
  final releases = <int, Map<String, dynamic>>{};
  int? uiId, contentId;

  Future<Map<String, dynamic>> envelope(
    int id,
    int version, {
    String locale = 'tr',
    bool includesUi = true,
    bool legacy = false,
    Map<String, String>? strings,
    Map<String, dynamic>? content,
  }) async {
    final payload = jsonEncode({
      'schema': 1,
      'locale': locale,
      'version': version,
      if (!legacy) 'ui_complete': includesUi,
      'strings':
          strings ??
          (includesUi
              ? {
                  for (final entry in controller.registry.entries)
                    entry.key: entry.value['en']!,
                  'nav.home': 'Test interface v$version',
                }
              : <String, String>{}),
      'content':
          content ??
          {
            'sunnah-hands': {
              'title': 'Synthetic source fixture',
              'text': 'Test content version $version',
              'source': 'Protocol test fixture',
              'sourceUrl': 'https://example.test/source',
            },
          },
    });
    final bytes = utf8.encode(payload);
    return {
      'release_id': id,
      'payload': payload,
      'bytes': bytes.length,
      'sha256': hash.sha256.convert(bytes).toString(),
      'key_id': 'test',
      'signature': base64Encode(
        (await Ed25519().sign(bytes, keyPair: signer)).bytes,
      ),
    };
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('haq-content-packages-');
    signer = await Ed25519().newKeyPair();
    keys = {'test': base64Encode((await signer.extractPublicKey()).bytes)};
    releases.clear();
    uiId = null;
    contentId = null;
    final dio = Dio(
      BaseOptions(baseUrl: 'https://backend.test/api/v2/app-content'),
    );
    dio.httpClientAdapter = StubHttp((request) {
      if (request.path == '/bootstrap') {
        expect(request.queryParameters['include_content_only'], 1);
        return ResponseBody.fromString(
          jsonEncode({
            'data': {
              'schema': 1,
              'languages': [
                if (contentId != null)
                  {
                    'locale': 'tr',
                    'release_id': uiId ?? contentId,
                    'interface_release_id': uiId,
                    'content_release_id': contentId,
                  },
              ],
            },
          }),
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      }
      final id = int.parse(request.path.split('/').last);
      return ResponseBody.fromString(
        jsonEncode({'data': releases[id]!}),
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
    });
    controller = AppLocalization(
      await SharedPreferences.getInstance(),
      dio: dio,
      directory: directory,
      publicKeys: keys,
    );
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    expect(
      directory.absolute.path,
      startsWith(Directory.systemTemp.absolute.path),
    );
    expect(
      directory.uri.pathSegments.where((part) => part.isNotEmpty).last,
      startsWith('haq-content-packages-'),
    );
    await directory.delete(recursive: true);
  });

  Future<AppLocalization> offline() async {
    final value = AppLocalization(
      controller.preferences,
      directory: directory,
      publicKeys: keys,
    );
    await value.initialize();
    addTearDown(value.dispose);
    return value;
  }

  test(
    'content-only Turkish discovery and offline reading keep the bundled English interface',
    () async {
      releases[1] = await envelope(1, 2, includesUi: false);
      contentId = 1;
      await controller.select('en');
      await controller.refresh();
      expect(
        controller.available.any((language) => language.code == 'tr'),
        false,
      );
      expect(
        controller.availableContent.any((language) => language.code == 'tr'),
        true,
      );
      expect(await controller.install('tr'), false);
      expect(await controller.install('tr', contentOnly: true), true);
      await controller.selectContent('tr');
      expect(controller.code, 'en');
      expect(controller.text('nav.home'), 'Home');
      expect(
        controller.content('sunnah-hands')!['text'],
        'Test content version 2',
      );
      await expectLater(controller.select('tr'), throwsFormatException);
      final restored = await offline();
      expect(restored.code, 'en');
      expect(restored.contentCode, 'tr');
      expect(restored.text('nav.home'), 'Home');
      expect(
        restored.content('sunnah-hands')!['text'],
        'Test content version 2',
      );
      await controller.remove('tr');
      expect(controller.installed.containsKey('tr'), true);
      await controller.selectContent(null);
      await controller.remove('tr');
      expect(controller.installed.containsKey('tr'), false);
      expect((await offline()).installed.containsKey('tr'), false);
    },
  );

  test(
    'new content and an older interface update have independent counters and survive restart',
    () async {
      releases[1] = await envelope(1, 2);
      uiId = contentId = 1;
      await controller.refresh();
      expect(await controller.install('tr'), true);
      await controller.select('tr');
      releases[3] = await envelope(3, 4, includesUi: false);
      contentId = 3;
      await controller.refresh();
      expect(await controller.install('tr', contentOnly: true), true);
      expect(controller.text('nav.home'), 'Test interface v2');
      expect(controller.installed['tr']!.version, 4);
      expect(controller.interfacePackages['tr']!.version, 2);
      var restored = await offline();
      expect(restored.code, 'tr');
      expect(restored.text('nav.home'), 'Test interface v2');
      expect(
        restored.content('sunnah-hands')!['text'],
        'Test content version 4',
      );
      releases[2] = await envelope(2, 3);
      uiId = 2;
      await controller.refresh();
      expect(await controller.install('tr'), true);
      expect(controller.text('nav.home'), 'Test interface v3');
      expect(controller.installed['tr']!.version, 4);
      expect(
        controller.content('sunnah-hands')!['text'],
        'Test content version 4',
      );
      uiId = contentId = 1;
      await controller.refresh();
      expect(await controller.install('tr'), false);
      expect(await controller.install('tr', contentOnly: true), false);
      expect(controller.text('nav.home'), 'Test interface v3');
      restored = await offline();
      expect(restored.code, 'tr');
      expect(restored.text('nav.home'), 'Test interface v3');
      expect(
        restored.content('sunnah-hands')!['text'],
        'Test content version 4',
      );
    },
  );

  test(
    'a content download that contains a full newer interface does not replace the selected interface',
    () async {
      releases[1] = await envelope(1, 2);
      uiId = contentId = 1;
      await controller.refresh();
      expect(await controller.install('tr'), true);
      await controller.select('tr');
      releases[4] = await envelope(4, 5);
      uiId = contentId = 4;
      await controller.refresh();
      expect(await controller.install('tr', contentOnly: true), true);
      expect(controller.text('nav.home'), 'Test interface v2');
      expect(
        controller.content('sunnah-hands')!['text'],
        'Test content version 5',
      );
      final restored = await offline();
      expect(restored.text('nav.home'), 'Test interface v2');
      expect(
        restored.content('sunnah-hands')!['text'],
        'Test content version 5',
      );
      expect(await controller.install('tr'), true);
      expect(controller.text('nav.home'), 'Test interface v5');
    },
  );

  test(
    'an app upgrade retains signed content from an incomplete older interface package',
    () async {
      final old = await envelope(
        9,
        2,
        legacy: true,
        strings: {'nav.home': 'Old interface'},
      );
      final bytes = jsonEncode(old);
      await File('${directory.path}/release-9.json').writeAsString(bytes);
      await controller.preferences.setInt('app.language.release.tr', 9);
      await controller.preferences.setString('app.language.v1', 'tr');
      await controller.initialize();
      expect(controller.code, 'ar');
      expect(controller.local('tr'), true);
      expect(controller.localInterface('tr'), false);
      expect(controller.contentLanguage.code, 'ar');
      await controller.selectContent('tr');
      expect(
        controller.content('sunnah-hands')!['text'],
        'Test content version 2',
      );
      expect(
        await File('${directory.path}/release-9.json').readAsString(),
        bytes,
      );
      final restored = await offline();
      expect(restored.contentCode, 'tr');
      expect(
        restored.content('sunnah-hands')!['text'],
        'Test content version 2',
      );
      await expectLater(
        LanguagePackage.verify(old, keys, controller.registry, 'tr'),
        throwsFormatException,
      );
    },
  );

  test(
    'bad signatures, mixed content-only strings and empty content never replace a good release',
    () async {
      releases[1] = await envelope(1, 2, includesUi: false);
      contentId = 1;
      await controller.refresh();
      expect(await controller.install('tr', contentOnly: true), true);
      final bad = await envelope(2, 3, includesUi: false);
      bad['signature'] = base64Encode(List<int>.filled(64, 0));
      releases[2] = bad;
      contentId = 2;
      await controller.refresh();
      expect(await controller.install('tr', contentOnly: true), false);
      expect(controller.installed['tr']!.version, 2);
      for (final invalid in [
        await envelope(
          3,
          3,
          includesUi: false,
          strings: {'nav.home': 'Not a content-only release'},
        ),
        await envelope(4, 3, includesUi: false, content: {}),
        await envelope(5, 3, strings: {'nav.home': '{wrong}'}),
      ]) {
        await expectLater(
          LanguagePackage.verify(
            invalid,
            keys,
            controller.registry,
            'tr',
            allowIncompleteUi: true,
          ),
          throwsFormatException,
        );
      }
      final restored = await offline();
      expect(restored.installed['tr']!.version, 2);
    },
  );

  test(
    'a corrupted content cache falls back to the verified interface artifact without deleting either file',
    () async {
      releases[1] = await envelope(1, 2);
      uiId = contentId = 1;
      await controller.refresh();
      expect(await controller.install('tr'), true);
      await controller.select('tr');
      releases[2] = await envelope(2, 3, includesUi: false);
      contentId = 2;
      await controller.refresh();
      expect(await controller.install('tr', contentOnly: true), true);
      await File(
        '${directory.path}/release-2.json',
      ).writeAsString('broken cache');
      final restored = await offline();
      expect(restored.code, 'tr');
      expect(restored.text('nav.home'), 'Test interface v2');
      expect(
        restored.content('sunnah-hands')!['text'],
        'Test content version 2',
      );
      expect(await File('${directory.path}/release-1.json').exists(), true);
      expect(await File('${directory.path}/release-2.json').exists(), true);
    },
  );
}
