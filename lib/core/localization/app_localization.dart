import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/quran/data/haq_api.dart';
import 'bundled_localization.dart';
import 'quran_translation_source.dart';
import 'locale_formats.dart';
import 'interface_messages.dart';
import 'hadith_translation_source.dart';

final _bundledInterface = jsonDecode(bundledUiJson) as Map;

String _bundledArabicText(
  String key,
  String? fallback,
  Map<String, Object> args,
) {
  final value = fallback ?? _bundledInterface[key]?['ar'] as String? ?? key;
  return formatInterfaceMessage(value, args);
}

class AppLanguage {
  const AppLanguage(this.code, this.name, this.direction);
  factory AppLanguage.fromJson(Map value) => AppLanguage(
    value['locale'] as String,
    value['name'] as String,
    value['direction'] == 'rtl' ? TextDirection.rtl : TextDirection.ltr,
  );
  final String code, name;
  final TextDirection direction;
  Locale get locale => code == 'zh-Hans'
      ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')
      : Locale(code);
}

/// Validates exact published bytes before any disk/cache activation.
class LanguagePackage {
  LanguagePackage(
    this.locale,
    this.version,
    this.strings,
    this.content, {
    this.quranSource,
    this.hadithSource,
  });
  final String locale;
  final int version;
  final Map<String, String> strings;
  final Map<String, dynamic> content;
  final QuranTranslationSource? quranSource;
  final HadithTranslationSource? hadithSource;

  static Future<LanguagePackage> verify(
    Map<String, dynamic> envelope,
    Map<String, String> keys,
    Map<String, Map<String, String>> registry,
    String expectedLocale,
  ) async {
    final payload = envelope['payload'] as String;
    final bytes = utf8.encode(payload);
    final encodedKey = keys[envelope['key_id']];
    if (bytes.length > AppLocalization.maxBytes ||
        bytes.length != envelope['bytes'] ||
        hash.sha256.convert(bytes).toString() != envelope['sha256'] ||
        encodedKey == null) {
      throw const FormatException('Untrusted language package');
    }
    final valid = await Ed25519().verify(
      bytes,
      signature: Signature(
        base64Decode(envelope['signature'] as String),
        publicKey: SimplePublicKey(
          base64Decode(encodedKey),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) throw const FormatException('Invalid package signature');
    final data = jsonDecode(payload) as Map<String, dynamic>;
    if (data['schema'] != 1 ||
        data['locale'] != expectedLocale ||
        data['version'] is! int ||
        (data['version'] as int) < 1) {
      throw const FormatException('Incompatible language package');
    }
    final strings = Map<String, String>.from(data['strings'] as Map);
    for (final entry in registry.entries) {
      final value = strings[entry.key];
      if (value == null || value.trim().isEmpty || value.length > 3000) {
        throw const FormatException('Incomplete language package');
      }
      final pattern = RegExp(r'\{([a-zA-Z][a-zA-Z0-9_]*)\}');
      List<String> variables(String text) =>
          pattern.allMatches(text).map((m) => m.group(1)!).toList()..sort();
      if (variables(value).join('|') !=
              variables(entry.value['ar']!).join('|') ||
          value.replaceAll(pattern, '').contains(RegExp(r'[{}<>]'))) {
        throw const FormatException('Invalid translation variables');
      }
    }
    final content = Map<String, dynamic>.from(data['content'] as Map);
    for (final entry in content.entries) {
      final value = Map<String, dynamic>.from(entry.value as Map);
      if (value.keys.any(
        (key) =>
            !['title', 'text', 'summary', 'source', 'sourceUrl'].contains(key),
      )) {
        throw const FormatException('Invalid translated content fields');
      }
      for (final field in ['title', 'text', 'source', 'sourceUrl']) {
        if (value[field] is! String || (value[field] as String).isEmpty) {
          throw const FormatException('Invalid translated content');
        }
      }
      if (Uri.tryParse(value['sourceUrl'] as String)?.scheme != 'https') {
        throw const FormatException('Invalid translation source');
      }
    }
    return LanguagePackage(
      expectedLocale,
      data['version'] as int,
      strings,
      content,
      quranSource: data['quran_source'] == null
          ? null
          : QuranTranslationSource.verify(
              data['quran_source'] as Map,
              expectedLocale,
            ),
      hadithSource: data['hadith_source'] == null
          ? null
          : HadithTranslationSource.verify(
              data['hadith_source'] as Map,
              expectedLocale,
            ),
    );
  }
}

class AppLocalization extends ChangeNotifier {
  AppLocalization(
    this.preferences, {
    Dio? dio,
    Map<String, String>? publicKeys,
    this.directory,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: '$haqApiBase/v2/app-content',
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 30),
             ),
           ),
       publicKeys =
           publicKeys ??
           Map<String, String>.from(
             jsonDecode(
                   const String.fromEnvironment(
                     'HAQ_CONTENT_PUBLIC_KEYS',
                     defaultValue: '{}',
                   ),
                 )
                 as Map,
           ) {
    final raw = jsonDecode(bundledUiJson) as Map;
    registry = {
      for (final entry in raw.entries)
        entry.key as String: Map<String, String>.from(entry.value as Map),
    };
    languages = (jsonDecode(bundledLanguagesJson) as List)
        .map((v) => AppLanguage.fromJson(v as Map))
        .toList();
    final saved = preferences.getString('app.language.v1');
    code = saved != null && ['ar', 'en'].contains(saved) ? saved : 'ar';
  }
  static const maxBytes = 8 * 1024 * 1024;
  final SharedPreferences preferences;
  final Dio dio;
  final Map<String, String> publicKeys;
  Directory? directory;
  Map<String, Map<String, String>> registry = {};
  List<AppLanguage> languages = const [
    AppLanguage('ar', 'العربية', TextDirection.rtl),
    AppLanguage('en', 'English', TextDirection.ltr),
  ];
  final installed = <String, LanguagePackage>{};
  final published = <String, int>{};
  String code = 'ar';
  String? error;
  bool busy = false, _disposed = false;
  int received = 0, total = 0;
  CancelToken? _cancel;
  AppLanguage get language => languages.firstWhere(
    (v) => v.code == code,
    orElse: () => languages.first,
  );
  LocaleFormats get formats => LocaleFormats(code);
  InterfaceMessages get messages => InterfaceMessages(code, {
    for (final entry in registry.entries)
      entry.key:
          installed[code]?.strings[entry.key] ??
          entry.value[code] ??
          entry.value['ar']!,
  });

  String pluralText(String key, num count) {
    final category = formats.pluralCategory(count);
    final selected = registry.containsKey('$key.$category')
        ? '$key.$category'
        : '$key.other';
    return text(selected, args: {'count': formats.number(count)});
  }

  bool get chosen => preferences.getBool('app.language.chosen.v1') == true;
  int get localPackageCount => <String>{'ar', 'en', ...installed.keys}.length;
  String? get contentSelection =>
      preferences.getString('app.content.language.v1');
  String get contentCode {
    final selected = contentSelection;
    return selected != null &&
            local(selected) &&
            languages.any((language) => language.code == selected)
        ? selected
        : code;
  }

  AppLanguage get contentLanguage =>
      languages.firstWhere((language) => language.code == contentCode);

  Future<void> selectContent(String? locale) async {
    if (locale != null &&
        (!local(locale) ||
            !languages.any((language) => language.code == locale))) {
      throw StateError('Content language is not installed');
    }
    final saved = locale == null
        ? await preferences.remove('app.content.language.v1')
        : await preferences.setString('app.content.language.v1', locale);
    if (!saved) throw StateError('Cannot save content language');
    if (!_disposed) notifyListeners();
  }

  bool local(String locale) =>
      ['ar', 'en'].contains(locale) || installed.containsKey(locale);
  List<AppLanguage> get available => languages
      .where(
        (v) =>
            systemSupported(v) &&
            (local(v.code) || published.containsKey(v.code)),
      )
      .toList();
  List<AppLanguage> get availableContent => languages
      .where(
        (language) =>
            local(language.code) || published.containsKey(language.code),
      )
      .toList();

  static bool systemSupported(AppLanguage language) =>
      GlobalMaterialLocalizations.delegate.isSupported(language.locale) &&
      GlobalCupertinoLocalizations.delegate.isSupported(language.locale);

  Future<void> initialize() async {
    await LocaleFormats.prepare();
    try {
      directory ??= Directory(
        '${(await getApplicationSupportDirectory()).path}/haq_language_packages_v1',
      );
      await directory!.create(recursive: true);
      for (final language in languages) {
        final release = preferences.getInt(
          'app.language.release.${language.code}',
        );
        if (release == null) continue;
        try {
          final file = File('${directory!.path}/release-$release.json');
          final envelope =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          installed[language.code] = await LanguagePackage.verify(
            envelope,
            publicKeys,
            registry,
            language.code,
          );
        } catch (_) {
          /* Bundled content and another valid language remain available. */
        }
      }
    } catch (_) {
      /* Public content and bundled language resources do not depend on storage plugins. */
    }
    final saved = preferences.getString('app.language.v1');
    code =
        saved != null &&
            local(saved) &&
            languages.any(
              (language) => language.code == saved && systemSupported(language),
            )
        ? saved
        : 'ar';
    _emit();
  }

  String text(
    String key, {
    String? fallback,
    Map<String, Object> args = const {},
  }) {
    final value =
        installed[code]?.strings[key] ??
        registry[key]?[code] ??
        registry[key]?['ar'] ??
        fallback ??
        key;
    return formatInterfaceMessage(value, args);
  }

  Map<String, dynamic>? content(String id) {
    final value = installed[contentCode]?.content[id];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<void> select(String locale) async {
    if (!languages.any((l) => l.code == locale && systemSupported(l)) ||
        !local(locale)) {
      throw const FormatException('Language needs a verified package');
    }
    if (!await preferences.setString('app.language.v1', locale) ||
        !await preferences.setBool('app.language.chosen.v1', true)) {
      throw StateError('Cannot save language');
    }
    code = locale;
    _emit();
  }

  Future<void> refresh() async {
    error = null;
    try {
      final data =
          (await dio.get<Map<String, dynamic>>('/bootstrap')).data!['data']
              as Map;
      if (data['schema'] != 1) {
        throw const FormatException('Unsupported catalog');
      }
      final next = <String, int>{};
      for (final row in data['languages'] as List) {
        if (languages.any((l) => l.code == row['locale']) &&
            row['release_id'] is int) {
          next[row['locale'] as String] = row['release_id'] as int;
        }
      }
      if (_disposed) return;
      published
        ..clear()
        ..addAll(next);
    } catch (_) {
      error = 'language.failed';
    }
    _emit();
  }

  void pause() => _cancel?.cancel('paused');

  Future<bool> install(String locale, {bool contentOnly = false}) async {
    if (busy || directory == null || !published.containsKey(locale)) {
      return false;
    }
    if (!languages.any(
      (language) =>
          language.code == locale && (contentOnly || systemSupported(language)),
    )) {
      return false;
    }
    busy = true;
    error = null;
    received = 0;
    total = 0;
    final release = published[locale]!;
    final partial = File('${directory!.path}/release-$release.partial');
    final cancel = CancelToken();
    _cancel = cancel;
    _emit();
    IOSink? sink;
    var completedDownload = false;
    try {
      var offset = await partial.exists() ? await partial.length() : 0;
      final response = await dio.get<ResponseBody>(
        '/releases/$release',
        options: Options(
          responseType: ResponseType.stream,
          headers: {if (offset > 0) 'Range': 'bytes=$offset-'},
        ),
        cancelToken: cancel,
      );
      if (response.statusCode == 206) {
        final range = response.headers.value('content-range');
        if (range == null || !range.startsWith('bytes $offset-')) {
          throw const FormatException('Invalid resume response');
        }
      } else {
        offset = 0;
      }
      total =
          (int.tryParse(response.headers.value('content-length') ?? '') ?? 0) +
          offset;
      if (total > maxBytes * 3) {
        throw const FormatException('Package exceeds limit');
      }
      sink = partial.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      received = offset;
      await for (final chunk in response.data!.stream) {
        received += chunk.length;
        if (received > maxBytes * 3) {
          throw const FormatException('Package exceeds limit');
        }
        sink.add(chunk);
        _emit();
      }
      await sink.flush();
      await sink.close();
      sink = null;
      completedDownload = true;
      final envelope = Map<String, dynamic>.from(
        (jsonDecode(await partial.readAsString()) as Map)['data'] as Map,
      );
      if (envelope['release_id'] != release) {
        throw const FormatException('Release mismatch');
      }
      final pack = await LanguagePackage.verify(
        envelope,
        publicKeys,
        registry,
        locale,
      );
      if (pack.version < (installed[locale]?.version ?? 0)) {
        throw const FormatException('Stale release');
      }
      if (_disposed || cancel.isCancelled) return false;
      final target = File('${directory!.path}/release-$release.json');
      final staging = File('${directory!.path}/release-$release.verified');
      await staging.writeAsString(jsonEncode(envelope), flush: true);
      if (await target.exists()) {
        var cacheValid = false;
        String? cachedHash;
        try {
          final cached =
              jsonDecode(await target.readAsString()) as Map<String, dynamic>;
          await LanguagePackage.verify(cached, publicKeys, registry, locale);
          cacheValid = true;
          cachedHash = cached['sha256'] as String;
        } catch (_) {
          /* Repair a corrupted target after verifying its replacement. */
        }
        if (cacheValid && cachedHash != envelope['sha256']) {
          throw const FormatException('Release ID reused');
        }
        if (cacheValid) {
          await staging.delete();
        } else {
          await target.delete();
          await staging.rename(target.path);
        }
      } else {
        await staging.rename(target.path);
      }
      if (!await preferences.setInt('app.language.release.$locale', release)) {
        throw StateError('Cannot activate language package');
      }
      installed[locale] = pack;
      await partial.delete();
      return true;
    } catch (_) {
      if (completedDownload && await partial.exists()) await partial.delete();
      error = 'language.failed';
      return false;
    } finally {
      await sink?.close();
      _cancel = null;
      busy = false;
      _emit();
    }
  }

  Future<void> remove(String locale) async {
    if (locale == code ||
        locale == contentCode ||
        ['ar', 'en'].contains(locale) ||
        busy) {
      return;
    }
    final release = preferences.getInt('app.language.release.$locale');
    await preferences.remove('app.language.release.$locale');
    installed.remove(locale);
    if (release != null && directory != null) {
      final file = File('${directory!.path}/release-$release.json');
      if (await file.exists()) await file.delete();
    }
    _emit();
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    pause();
    dio.close(force: true);
    super.dispose();
  }
}

class LocalizationScope extends InheritedNotifier<AppLocalization> {
  const LocalizationScope({
    super.key,
    required AppLocalization controller,
    required super.child,
  }) : super(notifier: controller);
  static AppLocalization? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LocalizationScope>()?.notifier;
}

extension HaqTranslation on BuildContext {
  String tr(
    String key, {
    String? fallback,
    Map<String, Object> args = const {},
  }) =>
      LocalizationScope.maybeOf(
        this,
      )?.text(key, fallback: fallback, args: args) ??
      _bundledArabicText(key, fallback, args);
}
