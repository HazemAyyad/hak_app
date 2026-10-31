import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/core/localization/interface_messages.dart';
import 'package:haq_app/core/localization/app_localization.dart';
import 'package:haq_app/features/prayer/data/prayer_controller.dart';
import 'package:haq_app/features/prayer/data/prayer_models.dart';
import 'package:haq_app/features/settings/data/app_settings.dart';
import 'package:haq_app/features/settings/data/reminder_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'background snapshot follows the interface while content and recordings remain independent',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final localization = AppLocalization(prefs);
      addTearDown(localization.dispose);
      await localization.select('en');
      final snapshot = localization.messages;
      expect(
        snapshot.text('prayer.timeFor', args: {'prayer': 'Fajr'}),
        'It is time for Fajr',
      );
      expect(snapshot.nativePayload['locale'], 'en');
      expect(snapshot.nativePayload['direction'], 'ltr');
      expect(
        (snapshot.nativePayload['strings'] as Map).keys.every(
          (key) => (key as String).startsWith('native.'),
        ),
        isTrue,
      );
      await localization.select('ar');
      expect(snapshot.text('native.stop'), 'Stop');
      expect(localization.messages.text('native.stop'), 'إيقاف');
      expect(
        () => snapshot.strings['native.stop'] = 'changed',
        throwsUnsupportedError,
      );
      expect(InterfaceMessages.bundled('ps').nativePayload['direction'], 'rtl');
    },
  );

  test(
    'translated notification plans retain identities, times and original personal data',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = PrayerController(
        prefs,
        scopeOf: () => 'guest',
        autoTick: false,
        clock: () => DateTime.utc(2026, 10, 31, 8),
      );
      addTearDown(controller.dispose);
      await controller.save(
        PrayerConfig(
          location: PrayerLocation(
            latitude: 31.53,
            longitude: 35.1,
            zone: 'Asia/Hebron',
            label: 'بيتي',
          ),
          notifications: true,
        ),
      );
      final original = controller.reminderJobs();
      controller.setInterfaceMessages(InterfaceMessages.bundled('en'));
      final translated = controller.reminderJobs();
      expect(translated.map((job) => job.id), original.map((job) => job.id));
      expect(translated.map((job) => job.at), original.map((job) => job.at));
      final due = translated.firstWhere(
        (job) => job.id.contains(':fajr:') && job.reminderVariant == null,
      );
      expect(due.title, 'It is time for Fajr');
      expect(due.body, startsWith('بيتي • '));
      expect(controller.config.location!.zone, 'Asia/Hebron');
      final settings = AppSettings(prefs, 'guest');
      addTearDown(settings.dispose);
      await settings.set('enabled', true);
      await settings.set('morning', true);
      final ar = reminderPlan(settings, [], []);
      final en = reminderPlan(
        settings,
        [],
        [],
        messages: InterfaceMessages.bundled('en'),
      );
      expect(en.map((job) => job.id), ar.map((job) => job.id));
      expect(en.map((job) => job.minute), ar.map((job) => job.minute));
      expect(en.single.title, 'Morning remembrances');
      expect(en.single.voice, 'dhikr-morning');
    },
  );
}
