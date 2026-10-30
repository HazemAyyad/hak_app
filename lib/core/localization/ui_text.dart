import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'app_localization.dart';
import 'bundled_localization.dart';

// Source lookup is confined to fixed interface labels. User content and scripture
// must use their own stable content identities and attributed translations.
final _sourceKeys = <String, String>{
  for (final entry in (jsonDecode(bundledUiJson) as Map).entries)
    if ((entry.key as String).startsWith('settings.label.'))
      entry.value['ar'] as String: entry.key as String,
};

extension FixedInterfaceText on BuildContext {
  String settingsLabel(String original) {
    final key = _sourceKeys[original];
    return key == null ? original : tr(key, fallback: original);
  }
}
