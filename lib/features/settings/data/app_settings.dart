import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// General settings have one durable, account-scoped owner. Quran, appearance
/// and exercise preferences retain their existing authoritative repositories.
class AppSettings extends ChangeNotifier {
  AppSettings(this.preferences, this.scope) {
    final raw = preferences.getString('app.settings.v1.$scope');
    try {
      _data = Map<String, dynamic>.from(jsonDecode(raw ?? '{}') as Map);
      for (final key in _data.keys.toList()) {
        try {
          final value = _data[key];
          // JSON lists are dynamic; normalize only this known typed field.
          if (key == 'content' &&
              value is List &&
              value.every((e) => e is String)) {
            _data[key] = List<String>.from(value);
          }
          _validate(key, _data[key] as Object);
        } catch (_) {
          _data.remove(key);
        }
      }
    } catch (_) {
      error = 'تعذّر قراءة الإعدادات المحفوظة. أعد ضبطها للمتابعة.';
      _corrupt = true;
    }
  }
  final SharedPreferences preferences;
  final String scope;
  Map<String, dynamic> _data = {};
  Future<void> _writes = Future.value();
  bool _disposed = false, _corrupt = false;
  String? error;
  static const times = {
    'morning': 300,
    'evening': 1020,
    'sleep': 1245,
    'dailyWird': 480,
    'friday': 540,
    'messages': 1080,
  };
  static const switches = {
    'enabled',
    'morning',
    'evening',
    'sleep',
    'dailyWird',
    'friday',
    'messages',
    'smart',
    'transparent',
    'sound',
    'speech',
    'ordered',
    'effects',
    'correctHijri',
    'startup',
  };
  static const frequencies = [1, 3, 5, 10, 15, 30, 60, 120, 180, 300];
  static const snoozes = [10, 15, 20, 30, 45, 60];
  static const hides = [0, -1, 5, 10, 20, 30];
  static const colors = [0xFF2A8C82, 0xFF102A43, 0xFFC7A45A, 0xFFFFFCF7];
  bool flag(String key) => _data[key] is bool
      ? _data[key] as bool
      : {
          'sound',
          'ordered',
          'effects',
          'correctHijri',
          'startup',
        }.contains(key);
  int number(String key, int fallback) =>
      _data[key] is int ? _data[key] as int : fallback;
  int time(String key) => number('$key.time', times[key] ?? 480).clamp(0, 1439);
  String text(String key, String fallback) =>
      _data[key] is String ? _data[key] as String : fallback;
  List<String> get content =>
      (_data['content'] is List ? _data['content'] as List : const [])
          .whereType<String>()
          .take(50)
          .toList();
  static String clockLabel(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  Future<void> set(String key, Object value) {
    if (_disposed) return Future.value();
    _validate(key, value);
    final job = _writes.then((_) async {
      if (_corrupt) return;
      final next = {..._data, key: value};
      try {
        if (!await preferences.setString(
          'app.settings.v1.$scope',
          jsonEncode(next),
        )) {
          throw StateError('Preferences');
        }
        _data = next;
        error = null;
      } catch (_) {
        error = 'تعذّر حفظ الإعداد. حاول مرة أخرى.';
      }
      if (!_disposed) notifyListeners();
    });
    _writes = job;
    return job;
  }

  static void validate(String key, Object value) {
    final valid = switches.contains(key)
        ? value is bool
        : key.endsWith('.time') && times.containsKey(key.split('.').first)
        ? value is int && value >= 0 && value < 1440
        : switch (key) {
            'frequency' => frequencies.contains(value),
            'snooze' => snoozes.contains(value),
            'hide' => hides.contains(value),
            'fontSize' => [12, 15, 20, 25, 30, 35, 40, 45, 50].contains(value),
            'background' || 'border' || 'textColor' => colors.contains(value),
            'hijriOffset' => value is int && value >= -3 && value <= 3,
            'type' => ['center', 'overlay'].contains(value),
            'position' => ['top', 'center', 'bottom'].contains(value),
            'font' => ['Cairo', 'Tajawal', 'Amiri'].contains(value),
            'animation' => [
              'zoom',
              'fade',
              'height',
              'width',
              'vertical',
              'horizontal',
              'bounce',
            ].contains(value),
            'content' =>
              value is List<String> &&
                  value.every(
                    (e) =>
                        e.length <= 120 &&
                        RegExp(r'^[a-z0-9:_-]+$').hasMatch(e),
                  ) &&
                  value.length <= 50 &&
                  value.toSet().length == value.length,
            _ => false,
          };
    if (!valid) throw ArgumentError('Invalid setting: $key');
  }

  void _validate(String key, Object value) => validate(key, value);

  Future<void> reset() {
    if (_disposed) return Future.value();
    final job = _writes.then((_) async {
      try {
        if (!await preferences.remove('app.settings.v1.$scope')) {
          throw StateError('Preferences');
        }
        _data = {};
        _corrupt = false;
        error = null;
      } catch (_) {
        error = 'تعذّرت إعادة الضبط؛ حاول مرة أخرى.';
      }
      if (!_disposed) notifyListeners();
    });
    _writes = job;
    return job;
  }

  Future<void> flush() => _writes;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
