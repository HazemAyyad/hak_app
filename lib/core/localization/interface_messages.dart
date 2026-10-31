import 'dart:convert';
import 'bundled_localization.dart';
import 'locale_formats.dart';

final _messageVariable = RegExp(r'\{([a-zA-Z][a-zA-Z0-9_]*)\}');

/// Substitute the template once. Inserted personal text is never interpreted as
/// another placeholder, even when it contains braces or another argument name.
String formatInterfaceMessage(String template, Map<String, Object> args) =>
    template.replaceAllMapped(
      _messageVariable,
      (match) =>
          args.containsKey(match[1]) ? args[match[1]].toString() : match[0]!,
    );

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
    final result = strings[key] ?? (_registry[key]?['ar'] as String?) ?? key;
    return formatInterfaceMessage(result, args);
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
