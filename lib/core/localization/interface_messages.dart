import 'dart:convert';
import 'bundled_localization.dart';
import 'locale_formats.dart';

/// A snapshot for background plans. It contains interface text only; recordings,
/// scripture and user-authored text never pass through this registry.
class InterfaceMessages {
  InterfaceMessages(this.code, Map<String, String> values)
    : strings = Map.unmodifiable(values);

  factory InterfaceMessages.bundled(String code) => InterfaceMessages(code, {
    for (final entry in _registry.entries)
      entry.key as String: (entry.value[code] ?? entry.value['ar']) as String,
  });

  static final _registry = jsonDecode(bundledUiJson) as Map;
  static final _directions = {
    for (final language in jsonDecode(bundledLanguagesJson) as List)
      language['locale'] as String: language['direction'] as String,
  };
  final String code;
  final Map<String, String> strings;
  LocaleFormats get formats => LocaleFormats(code);

  String text(String key, {Map<String, Object> args = const {}}) {
    var result = strings[key] ?? (_registry[key]?['ar'] as String?) ?? key;
    for (final entry in args.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value.toString());
    }
    return result;
  }

  Map<String, Object> get nativePayload => {
    'locale': code,
    'direction': _directions[code] ?? 'rtl',
    'strings': {
      for (final entry in strings.entries)
        if (entry.key.startsWith('native.')) entry.key: entry.value,
    },
  };
}
