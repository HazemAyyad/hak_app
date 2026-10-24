import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../religious_activity/data/activity_models.dart';

class AdhkarPreferences {
  DhikrReadingMode mode = DhikrReadingMode.cards;
  String font = 'QuranUI';
  double size = 23;
  bool hapticZero = true,
      hapticEvery = false,
      hideCompleted = false,
      tapText = true,
      autoAdvance = true,
      dim = false,
      volumeKeys = false,
      confirmExit = true;
  static String key(String scope) => 'adhkar.display.v1.$scope';
  static AdhkarPreferences load(SharedPreferences preferences, String scope) {
    final result = AdhkarPreferences();
    try {
      final data = jsonDecode(preferences.getString(key(scope)) ?? '{}') as Map;
      result.mode = DhikrReadingMode.values.byName(
        data['mode'] as String? ?? 'cards',
      );
      final font = data['font'] as String?;
      if (['QuranUI', 'Tajawal', 'AmiriQuran'].contains(font)) {
        result.font = font!;
      }
      result.size = ((data['size'] as num?)?.toDouble() ?? 23).clamp(16, 42);
      result.hapticZero = data['haptic_zero'] as bool? ?? true;
      result.hapticEvery = data['haptic_every'] as bool? ?? false;
      result.hideCompleted = data['hide_completed'] as bool? ?? false;
      result.tapText = data['tap_text'] as bool? ?? true;
      result.autoAdvance = data['auto_advance'] as bool? ?? true;
      result.dim = data['dim'] as bool? ?? false;
      result.volumeKeys = data['volume_keys'] as bool? ?? false;
      result.confirmExit = data['confirm_exit'] as bool? ?? true;
    } catch (_) {
      /* Keep defaults, without deleting an existing record. */
    }
    return result;
  }

  Future<void> save(SharedPreferences preferences, String scope) async {
    await preferences.setString(
      key(scope),
      jsonEncode({
        'mode': mode.name,
        'font': font,
        'size': size,
        'haptic_zero': hapticZero,
        'haptic_every': hapticEvery,
        'hide_completed': hideCompleted,
        'tap_text': tapText,
        'auto_advance': autoAdvance,
        'dim': dim,
        'volume_keys': volumeKeys,
        'confirm_exit': confirmExit,
      }),
    );
  }
}
