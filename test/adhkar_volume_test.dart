import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/adhkar/data/adhkar_volume_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(AdhkarVolumeControls.channel, null);
  });
  test(
    'only current Android focus lease receives volume count; retiring old lease does not disable new one',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <bool>[];
      messenger.setMockMethodCallHandler(AdhkarVolumeControls.channel, (
        call,
      ) async {
        calls.add(call.arguments as bool);
        return null;
      });
      final first = AdhkarVolumeControls(), second = AdhkarVolumeControls();
      var oldCount = 0, newCount = 0;
      await first.setEnabled(true, () => oldCount++);
      await second.setEnabled(true, () => newCount++);
      await first.setEnabled(false, () => {});
      await messenger.handlePlatformMessage(
        AdhkarVolumeControls.channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('count')),
        null,
      );
      expect(oldCount, 0);
      expect(newCount, 1);
      expect(calls, [true, true]);
      await first.dispose();
      await second.setEnabled(false, () => {});
      expect(calls, [true, true, false]);
      await second.dispose();
    },
  );
  test('unsupported platform never claims volume controls', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var calls = 0;
    messenger.setMockMethodCallHandler(AdhkarVolumeControls.channel, (
      call,
    ) async {
      calls++;
      return null;
    });
    final volume = AdhkarVolumeControls();
    expect(volume.supported, isFalse);
    await volume.setEnabled(true, () => {});
    await volume.dispose();
    expect(calls, 0);
  });
}
