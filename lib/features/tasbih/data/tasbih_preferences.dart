import 'package:shared_preferences/shared_preferences.dart';

class TasbihPreferences {
  TasbihPreferences(this.preferences, this.scope);
  final SharedPreferences preferences;
  final String scope;
  String key(String name) => 'tasbih.settings.v1.$scope.$name';
  bool get haptic => preferences.getBool(key('haptic')) ?? true;
  bool get autoCount => haptic && (preferences.getBool(key('auto')) ?? false);
  bool get countSound => preferences.getBool(key('countSound')) ?? false;
  bool get goalSound => preferences.getBool(key('goalSound')) ?? false;
  Future<void> set(String name, bool value) async {
    await preferences.setBool(key(name), value);
    if (name == 'haptic' && !value) {
      await preferences.setBool(key('auto'), false);
    }
  }
}
