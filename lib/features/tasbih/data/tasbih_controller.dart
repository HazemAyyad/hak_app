import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../adhkar/data/adhkar_repository.dart' show adhkarIdentity;
import '../../adhkar/data/adhkar_session_controller.dart'
    show AdhkarSessionController;
import '../../quran/data/quran_sync.dart' show operationId;
import '../../religious_activity/data/activity_controller.dart';
import '../../religious_activity/data/activity_models.dart';

class TasbihController extends ChangeNotifier {
  TasbihController._(
    this.activity,
    this.scope,
    this.definition,
    this.device,
    this.clock,
  ) {
    activity.addListener(_changed);
  }
  final ReligiousActivityController activity;
  final String scope, device;
  final DateTime Function() clock;
  PersonalTasbih definition;
  int total = 0, rounds = 0, current = 0;
  String? error;
  bool _disposed = false, _notifying = false;
  Future<void> _writes = Future.value();
  final _active = <ReligiousActivityEvent>[];
  bool get available =>
      !_disposed && activity.scope == scope && error != 'deleted';
  bool get canUndo => _active.isNotEmpty;
  String get subject => 'tasbih:${definition.id}:${definition.goal}';
  static List<PersonalTasbih> defaults() => [
    for (final (index, text, goal) in [
      (0, 'سبحان الله وبحمده', 33),
      (1, 'الحمد لله', 33),
      (2, 'الله أكبر', 34),
    ])
      PersonalTasbih(
        id: adhkarIdentity('tasbih:$index'),
        text: text,
        goal: goal,
        epoch: adhkarIdentity('tasbih-epoch:$index'),
        order: index,
      ),
  ];
  static Future<List<PersonalTasbih>> library(
    ReligiousActivityController activity,
  ) async {
    final scope = activity.scope;
    await activity.store.seed(scope, defaults());
    final list = (await activity.store.entities(
      scope,
      kind: PersonalEntityKind.tasbih,
    )).cast<PersonalTasbih>();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  static Future<TasbihController> open(
    ReligiousActivityController activity,
    PersonalTasbih definition, {
    DateTime Function()? clock,
  }) async {
    final scope = activity.scope;
    final result = TasbihController._(
      activity,
      scope,
      definition,
      await activity.store.deviceId,
      clock ?? DateTime.now,
    );
    await result._refresh();
    return result;
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _writes.then((_) async {
      if (available) await action();
    });
    _writes = next.catchError((Object _) {
      if (!_disposed) {
        error = 'تعذّر حفظ العدّ؛ حاول مرة أخرى';
        notifyListeners();
      }
    });
    return _writes;
  }

  Future<void> flush() => _writes;
  void _changed() {
    if (!_notifying && !_disposed) {
      if (activity.scope != scope) {
        notifyListeners();
        return;
      }
      unawaited(refresh());
    }
  }

  void _publish() {
    if (_disposed) return;
    _notifying = true;
    activity.changed(scope);
    _notifying = false;
    notifyListeners();
  }

  Future<void> refresh() => _enqueue(_refresh);
  Future<void> _refresh() async {
    final saved = await activity.store.entity(scope, definition.key);
    if (_disposed) return;
    if (saved is! PersonalTasbih) {
      error = 'deleted';
      notifyListeners();
      return;
    }
    definition = saved;
    final events = await activity.store.events(scope, sessionId: definition.id);
    final reversed = {
      for (final e in events)
        if (e.reverses != null) e.reverses!,
    };
    total = 0;
    rounds = 0;
    current = 0;
    _active.clear();
    var segment = 0, goal = definition.goal;
    for (final event in events) {
      if (event.epoch != definition.epoch) continue;
      if (event.kind == ActivityKind.reset) {
        rounds += segment ~/ goal;
        segment = 0;
        _active.clear();
        goal = _goal(event.subjectId);
      } else if (event.kind == ActivityKind.count &&
          !reversed.contains(event.id)) {
        final nextGoal = _goal(event.subjectId);
        if (nextGoal != goal) {
          rounds += segment ~/ goal;
          segment = 0;
          _active.clear();
          goal = nextGoal;
        }
        total += event.amount;
        segment += event.amount;
        _active.add(event);
      }
    }
    rounds += segment ~/ goal;
    current = segment % goal;
    // Offline counts from a previously edited goal remain in history/total.
    // They cannot become the current segment of the winning definition.
    if (goal != definition.goal) {
      current = 0;
      _active.clear();
    }
    if (!_disposed) notifyListeners();
  }

  int _goal(String subject) {
    final value = int.tryParse(subject.split(':').last);
    return value != null && value >= 1 && value <= 1000000
        ? value
        : definition.goal;
  }

  ReligiousActivityEvent _event(
    ActivityKind kind, {
    String? reverses,
    String? epoch,
    int? goal,
    String? id,
  }) {
    final now = clock();
    return ReligiousActivityEvent(
      id: id ?? operationId(),
      deviceId: device,
      sessionId: definition.id,
      subjectId: 'tasbih:${definition.id}:${goal ?? definition.goal}',
      epoch: epoch ?? definition.epoch,
      kind: kind,
      amount: kind == ActivityKind.count ? 1 : 0,
      occurredAt: now.toUtc(),
      day: AdhkarSessionController.day(now),
      utcOffsetMinutes: now.timeZoneOffset.inMinutes,
      reverses: reverses,
    );
  }

  Future<void> increment({String? eventId}) => _enqueue(() async {
    final event = _event(ActivityKind.count, id: eventId);
    if (!await activity.store.append(scope, event)) return;
    _active.add(event);
    total++;
    current++;
    if (current >= definition.goal) {
      current = 0;
      rounds++;
    }
    error = null;
    _publish();
  });
  Future<void> undo() => _enqueue(() async {
    if (_active.isEmpty) return;
    final target = _active.last;
    final event = _event(
      ActivityKind.undo,
      reverses: target.id,
      goal: _goal(target.subjectId),
    );
    await activity.store.append(scope, event);
    final segment = _active.fold<int>(
      0,
      (value, event) => value + event.amount,
    );
    _active.removeLast();
    total -= target.amount;
    rounds =
        rounds -
        segment ~/ definition.goal +
        (segment - target.amount) ~/ definition.goal;
    current = (segment - target.amount) % definition.goal;
    _publish();
  });
  Future<void> resetCurrent() => _enqueue(() async {
    await activity.store.append(scope, _event(ActivityKind.reset));
    current = 0;
    _active.clear();
    _publish();
  });
  Future<void> resetAll() => _enqueue(() async {
    final epoch = operationId();
    // The definition and explicit reset marker are committed together.
    final next = definition.copyWith(epoch: epoch);
    await activity.store.apply(
      scope,
      upserts: [next],
      events: [_event(ActivityKind.reset, epoch: epoch)],
    );
    definition = next;
    total = 0;
    rounds = 0;
    current = 0;
    _active.clear();
    _publish();
  });
  Future<void> edit({
    required String text,
    required String benefit,
    required int goal,
  }) => _enqueue(() async {
    final next = definition.copyWith(text: text, benefit: benefit, goal: goal);
    await activity.store.apply(
      scope,
      upserts: [next],
      events: goal == definition.goal
          ? []
          : [_event(ActivityKind.reset, goal: goal)],
    );
    definition = next;
    await _refresh();
    _publish();
  });
  Future<void> style(TasbihStyle value) => _enqueue(() async {
    final next = definition.copyWith(style: value);
    await activity.store.save(scope, next);
    definition = next;
    _publish();
  });
  @override
  void dispose() {
    _disposed = true;
    activity.removeListener(_changed);
    super.dispose();
  }
}
