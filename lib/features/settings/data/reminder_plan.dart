import '../../religious_activity/data/activity_models.dart';
import 'app_settings.dart';
import '../../../core/localization/interface_messages.dart';

class ReminderJob {
  const ReminderJob({
    required this.id,
    required this.title,
    required this.body,
    required this.route,
    required this.minute,
    this.weekday,
    this.start,
    this.end,
    this.interval,
    this.at,
    this.alertMode,
    this.voice,
    this.fullAdhan = false,
    this.volume,
    this.showAdhanScreen,
    this.iqamaMinutes,
    this.reminderVariant,
  });
  final String id, title, body, route;
  final int minute;
  final int? weekday, interval, at, volume, iqamaMinutes;
  final bool? showAdhanScreen;
  final String? start, end;
  final String? alertMode, voice, reminderVariant;
  final bool fullAdhan;
  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'route': route,
    'minute': minute,
    'weekday': ?weekday,
    'interval': ?interval,
    'start': ?start,
    'end': ?end,
    'at': ?at,
    'alertMode': ?alertMode,
    'voice': ?voice,
    'reminderVariant': ?reminderVariant,
    if (alertMode == 'adhan') 'fullAdhan': fullAdhan,
    'volume': ?volume,
    'showAdhanScreen': ?showAdhanScreen,
    'iqamaMinutes': ?iqamaMinutes,
  };
}

/// Pure plan: no permission prompts, device timers, invented prayer times, or
/// remote messages. Native schedulers replace this namespace idempotently.
List<ReminderJob> reminderPlan(
  AppSettings settings,
  List<PersonalEntity> entities,
  List<ReligiousActivityEvent> history, {
  InterfaceMessages? messages,
}) {
  if (!settings.flag('enabled')) return [];
  final labels = messages ?? InterfaceMessages.bundled('ar');
  final jobs = <ReminderJob>[];
  const kinds = [
    'morning',
    'evening',
    'sleep',
    'dailyWird',
    'friday',
    'messages',
  ];
  for (final kind in kinds) {
    if (!settings.flag(kind)) continue;
    final dhikr = const {'morning', 'evening', 'sleep'}.contains(kind);
    jobs.add(
      ReminderJob(
        id: '${settings.scope}:$kind',
        title: labels.text('reminder.$kind'),
        body: labels.text(
          'reminder.timeFor',
          args: {'name': labels.text('reminder.$kind')},
        ),
        route: dhikr
            ? 'adhkar-$kind'
            : kind == 'dailyWird'
            ? 'quran'
            : kind == 'messages'
            ? 'library'
            : kind == 'friday'
            ? 'friday'
            : 'adhkar',
        minute: settings.time(kind),
        weekday: kind == 'friday' ? 5 : null,
        alertMode: dhikr ? 'dhikr' : null,
        voice: dhikr ? 'dhikr-$kind' : null,
        volume: dhikr ? (settings.flag('sound') ? 100 : 0) : null,
        showAdhanScreen: dhikr ? true : null,
      ),
    );
  }
  for (final k in entities.whereType<QuranKhatma>()) {
    final completed = history.any(
      (e) =>
          e.sessionId == k.id &&
          e.epoch == k.activeEpoch &&
          e.subjectId == 'khatma:complete' &&
          e.kind == ActivityKind.complete,
    );
    if (k.archived == true || k.reminderMinutes == null || completed) continue;
    jobs.add(
      ReminderJob(
        id: '${settings.scope}:khatma:${k.id}:${k.activeEpoch}',
        title: labels.text('reminder.khatma'),
        body: k.title,
        route: 'khatma',
        minute: k.reminderMinutes!,
        start: k.startDate,
        end: k.endDate,
      ),
    );
  }
  if (settings.flag('smart') && settings.content.isNotEmpty) {
    jobs.add(
      ReminderJob(
        id: '${settings.scope}:smart',
        title: labels.text('reminder.smart'),
        body: '',
        route: 'adhkar',
        minute: 0,
        interval: settings.number('frequency', 5),
      ),
    );
  }
  return jobs..sort((a, b) => a.id.compareTo(b.id));
}
