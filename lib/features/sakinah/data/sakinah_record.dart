import '../../quran/data/quran_sync.dart' show operationId;
import '../../progress/data/progress_controller.dart' show progressDay;
import '../../religious_activity/data/activity_controller.dart';
import '../../religious_activity/data/activity_models.dart';
import 'breathing_session.dart';

const sakinahPaths = ['calm', 'peace', 'gratitude', 'repentance', 'trust'];
const sakinahNames = ['سكينة', 'طمأنينة', 'شكر', 'استغفار', 'توكل'];
const sakinahVerses = [
  ['2:201'],
  ['13:28'],
  ['14:7', '27:19'],
  ['7:23'],
  ['9:129'],
];
const sakinahWords = [
  'سبحان الله',
  'لا إله إلا الله',
  'الحمد لله',
  'أستغفر الله',
  'حسبي الله ونعم الوكيل',
];

/// Frozen payload IDs/time make retry of the same session idempotent. Partial
/// sessions have duration only; a completed session has a separate marker.
class SakinahRecord {
  SakinahRecord._(this.activity, this.scope, this.events);
  final ReligiousActivityController activity;
  final String scope;
  final List<ReligiousActivityEvent> events;
  bool saved = false;
  static Future<SakinahRecord> create(
    ReligiousActivityController activity,
    String scope,
    String sessionId,
    String path,
    BreathingSession session, {
    DateTime? endedAt,
  }) async {
    if (!session.finished || !sakinahPaths.contains(path)) {
      throw StateError('Unfinished session');
    }
    final now = endedAt ?? DateTime.now();
    final seconds = session.elapsed.inSeconds;
    final device = await activity.store.deviceId;
    ReligiousActivityEvent event(ActivityKind kind, int amount) =>
        ReligiousActivityEvent(
          id: operationId(),
          deviceId: device,
          sessionId: sessionId,
          subjectId: 'breathing:$path',
          epoch: sessionId,
          kind: kind,
          amount: amount,
          occurredAt: now.toUtc(),
          day: progressDay(now),
          utcOffsetMinutes: now.timeZoneOffset.inMinutes,
        );
    return SakinahRecord._(activity, scope, [
      if (seconds > 0) event(ActivityKind.breathing, seconds),
      if (session.status == BreathingStatus.completed)
        event(ActivityKind.complete, 0),
    ]);
  }

  Future<bool> save() async {
    if (saved) return true;
    if (activity.scope != scope || activity.syncClient.disposed) return false;
    await activity.store.apply(scope, events: events);
    saved = true;
    activity.changed(scope);
    return true;
  }
}
