import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'app_localization.dart';
import 'bundled_localization.dart';
import 'package:intl/intl.dart' show Bidi;

TextDirection contentTextDirection(String text) =>
    Bidi.detectRtlDirectionality(text) ? TextDirection.rtl : TextDirection.ltr;

// Source lookup is confined to fixed interface labels. User content and scripture
// must use their own stable content identities and attributed translations.
final _sourceKeys = <String, String>{
  for (final entry in (jsonDecode(bundledUiJson) as Map).entries)
    if ((entry.key as String).contains('.label.'))
      '${(entry.key as String).split('.').first}\u0000${entry.value['ar']}':
          entry.key as String,
};

extension FixedInterfaceText on BuildContext {
  String settingsLabel(String original) {
    return _interfaceLabel(original, 'settings');
  }

  String quranLabel(String original) => _interfaceLabel(original, 'quran');
  String accountLabel(String original) => _interfaceLabel(original, 'account');
  String prayerLabel(String original) => _interfaceLabel(original, 'prayer');
  String adhkarLabel(String original) => _interfaceLabel(original, 'adhkar');
  String assistantLabel(String original) =>
      _interfaceLabel(original, 'assistant');
  String _interfaceLabel(String original, String namespace) {
    final key = _sourceKeys['$namespace\u0000$original'];
    return key == null ? original : tr(key, fallback: original);
  }
}
