import '../../religious_activity/data/activity_models.dart';
import 'app_settings.dart';

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
  });
  final String id, title, body, route;
  final int minute;
  final int? weekday, interval;
  final String? start, end;
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
  };
}

/// Pure plan: no permission prompts, device timers, invented prayer times, or
/// remote messages. Native schedulers replace this namespace idempotently.
List<ReminderJob> reminderPlan(
  AppSettings settings,
  List<PersonalEntity> entities,
  List<ReligiousActivityEvent> history,
) {
  if (!settings.flag('enabled')) return [];
  final jobs = <ReminderJob>[];
  const labels = {
    'morning': 'أذكار الصباح',
    'evening': 'أذكار المساء',
    'sleep': 'أذكار النوم',
    'dailyWird': 'ورد القرآن',
    'friday': 'تذكير يوم الجمعة',
    'messages': 'المحتوى الإيماني',
  };
  for (final entry in labels.entries) {
    if (!settings.flag(entry.key)) continue;
    jobs.add(
      ReminderJob(
        id: '${settings.scope}:${entry.key}',
        title: entry.value,
        body: 'حان موعدك مع ${entry.value}',
        route: entry.key == 'dailyWird'
            ? 'quran'
            : entry.key == 'messages'
            ? 'library'
            : entry.key == 'friday'
            ? 'friday'
            : 'adhkar',
        minute: settings.time(entry.key),
        weekday: entry.key == 'friday' ? 5 : null,
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
        title: 'ورد الختمة',
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
        title: 'تذكير بالذكر',
        body: '',
        route: 'adhkar',
        minute: 0,
        interval: settings.number('frequency', 5),
      ),
    );
  }
  return jobs..sort((a, b) => a.id.compareTo(b.id));
}
