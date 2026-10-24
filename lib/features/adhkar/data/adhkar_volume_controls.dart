import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android counts only while a visible, resumed focus session owns this lease.
/// iOS/system volume behavior is left to the OS; the option is unavailable there.
class AdhkarVolumeControls {
  static const channel = MethodChannel(
    'com.haqfoundation.haq_app/adhkar_controls',
  );
  static Object? _owner;
  final Object owner = Object();
  bool _disposed = false;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<void> setEnabled(bool enabled, VoidCallback onCount) async {
    if (!supported || _disposed) return;
    if (enabled) {
      _owner = owner;
      channel.setMethodCallHandler((call) async {
        if (call.method == 'count' && identical(_owner, owner) && !_disposed) {
          onCount();
        }
      });
    } else if (!identical(_owner, owner)) {
      return;
    }
    try {
      await channel.invokeMethod<void>('enable', enabled);
    } on MissingPluginException {
      /* Platform build/device validation is deferred. */
    }
    if (!enabled && identical(_owner, owner)) {
      _owner = null;
      channel.setMethodCallHandler(null);
    }
  }

  Future<void> dispose() async {
    await setEnabled(false, () {});
    _disposed = true;
  }
}
