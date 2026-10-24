import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../quran/data/quran_sync.dart';
import '../../religious_activity/data/activity_controller.dart';
import '../../religious_activity/data/activity_models.dart';
import 'adhkar_preferences.dart';
import 'adhkar_repository.dart';

class AdhkarSessionController extends ChangeNotifier {
  AdhkarSessionController._(
    this.activity,
    this.scope,
    this.group,
    this.items,
    this.session,
    this.settings,
    this.now,
  ) {
    activity.addListener(_activityChanged);
  }
  final ReligiousActivityController activity;
  final String scope;
  final DhikrGroup group;
  final List<DhikrEntry> items;
  final AdhkarPreferences settings;
  final DateTime Function() now;
  DhikrSession session;
  Map<String, int> counts = {};
  String? error;
  bool _disposed = false;
  bool _sourceChanged = false;
  Future<void> _writes = Future.value();
  static String day(DateTime time) =>
      '${time.year.toString().padLeft(4, '0')}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  bool get available =>
      !_disposed &&
      !_sourceChanged &&
      activity.scope == scope &&
      session.day == day(now());
  int get cursor => session.cursor.clamp(0, items.length - 1);
  DhikrEntry get current => items[cursor];
  int remaining(String id) => ((session.targets[id] ?? 0) - (counts[id] ?? 0))
      .clamp(0, session.targets[id] ?? 0);
  bool get completed => session.targets.keys.every((id) => remaining(id) == 0);
  int get completedItems =>
      session.targets.keys.where((id) => remaining(id) == 0).length;
  double get progress =>
      session.targets.entries.fold<int>(
        0,
        (v, e) => v + e.value - remaining(e.key),
      ) /
      session.targets.values.fold<int>(0, (v, e) => v + e);

  static Future<AdhkarSessionController> open({
    required ReligiousActivityController activity,
    required DhikrGroup group,
    required AdhkarLibrary library,
    required String catalogVersion,
    DateTime Function()? clock,
  }) async {
    final now = clock ?? DateTime.now, scope = activity.scope;
    final items = [for (final id in group.itemIds) ?library.entries[id]];
    if (items.isEmpty) throw StateError('Empty dhikr group');
    final settings = AdhkarPreferences.load(activity.quran.preferences!, scope);
    final existing =
        (await activity.store.entities(scope, kind: PersonalEntityKind.session))
            .whereType<DhikrSession>()
            .where((s) => s.groupId == group.id && s.day == day(now()))
            .toList();
    final previous = existing.lastOrNull;
    final previousItem = previous?.targets.keys.elementAt(previous.cursor);
    final cursor = items
        .indexWhere((item) => item.id == previousItem)
        .clamp(0, items.length - 1);
    final session = DhikrSession(
      id: previous?.id ?? adhkarIdentity('session:${group.id}:${day(now())}'),
      groupId: group.id,
      day: day(now()),
      epoch:
          previous?.epoch ?? adhkarIdentity('epoch:${group.id}:${day(now())}'),
      targets: {
        for (final item in items)
          item.id: item.personal
              ? item.target
              : previous?.targets[item.id] ?? item.target,
      },
      mode: settings.mode,
      catalogVersion: catalogVersion,
      autoAdvance: settings.autoAdvance,
      cursor: cursor,
    );
    await activity.store.save(scope, session);
    final result = AdhkarSessionController._(
      activity,
      scope,
      group,
      List.unmodifiable(items),
      session,
      settings,
      now,
    );
    await result._refresh();
    activity.changed(scope);
    return result;
  }

  Future<void> _refresh() async {
    final saved = await activity.store.entity(scope, session.key);
    if (saved is DhikrSession) {
      _sourceChanged = !listEquals(
        saved.targets.keys.toList(),
        items.map((item) => item.id).toList(),
      );
      if (!_sourceChanged) {
        session = saved;
      } else {
        error = 'تغيّرت عناصر المجموعة؛ ارجع لفتح نسختها الحالية';
      }
    }
    counts = await activity.store.counts(scope, session.id, session.epoch);
    if (!_disposed) notifyListeners();
  }

  void _activityChanged() {
    if (!_disposed) unawaited(refresh());
  }

  Future<void> refresh() => _enqueue(_refresh);

  Future<void> _enqueue(Future<void> Function() action) {
    final job = _writes.catchError((Object _) {}).then((_) async {
      if (_disposed) return;
      if (!available) {
        error = _sourceChanged
            ? 'تغيّرت عناصر المجموعة؛ ارجع لفتح نسختها الحالية'
            : activity.scope != scope
            ? 'تغيّر الحساب؛ ارجع لفتح أذكار الحساب الحالي'
            : 'بدأ يوم جديد؛ ارجع لبدء أذكار اليوم';
        notifyListeners();
        return;
      }
      try {
        error = null;
        await action();
      } catch (_) {
        error = 'تعذّر حفظ التغيير؛ بقي تقدمك السابق محفوظًا';
      }
      if (!_disposed) notifyListeners();
    });
    _writes = job;
    return job;
  }

  ReligiousActivityEvent _event(
    ActivityKind kind,
    String subject, {
    int amount = 0,
    String? reverses,
  }) {
    final time = now();
    return ReligiousActivityEvent(
      id: operationId(),
      deviceId: _device!,
      sessionId: session.id,
      subjectId: subject,
      epoch: session.epoch,
      kind: kind,
      amount: amount,
      occurredAt: time,
      day: session.day,
      utcOffsetMinutes: time.timeZoneOffset.inMinutes,
      reverses: reverses,
    );
  }

  String? _device;
  Future<void> _saveSession({
    int? cursor,
    String? epoch,
    Map<String, int>? targets,
  }) async {
    final next = DhikrSession(
      id: session.id,
      groupId: session.groupId,
      day: session.day,
      epoch: epoch ?? session.epoch,
      targets: targets ?? session.targets,
      mode: settings.mode,
      catalogVersion: session.catalogVersion,
      autoAdvance: settings.autoAdvance,
      cursor: cursor ?? session.cursor,
    );
    await activity.store.save(scope, next);
    session = next;
  }

  Future<void> select(int index) => _enqueue(() async {
    await _saveSession(cursor: index.clamp(0, items.length - 1));
    activity.changed(scope);
  });

  Future<void> count(String id, {bool complete = false}) => _enqueue(() async {
    if (!session.targets.containsKey(id) || remaining(id) == 0) return;
    _device ??= await activity.store.deviceId;
    final event = _event(
      ActivityKind.count,
      id,
      amount: complete ? remaining(id) : 1,
    );
    final accepted = await activity.store.appendWithinTarget(
      scope,
      event,
      session.targets[id]!,
    );
    if (!accepted) {
      await _refresh();
      return;
    }
    await _refresh();
    if (settings.mode == DhikrReadingMode.list && current.id != id) {
      await _saveSession(cursor: items.indexWhere((item) => item.id == id));
    }
    if ((settings.hideCompleted ||
            settings.mode == DhikrReadingMode.focus && settings.autoAdvance) &&
        remaining(id) == 0 &&
        current.id == id &&
        !completed) {
      var index = (cursor + 1) % items.length;
      while (remaining(items[index].id) == 0) {
        index = (index + 1) % items.length;
      }
      await _saveSession(cursor: index);
    }
    if (completed) {
      final events = await activity.store.events(scope, sessionId: session.id);
      if (!events.any(
        (e) => e.epoch == session.epoch && e.kind == ActivityKind.complete,
      )) {
        await activity.store.append(
          scope,
          _event(ActivityKind.complete, group.id),
        );
      }
    }
    activity.changed(scope);
  });

  Future<void> undo() => _enqueue(() async {
    _device ??= await activity.store.deviceId;
    final events = (await activity.store.events(
      scope,
      sessionId: session.id,
    )).where((e) => e.epoch == session.epoch).toList();
    final reversed = events
        .where((e) => e.kind == ActivityKind.undo)
        .map((e) => e.reverses)
        .toSet();
    final candidates = events
        .where(
          (e) =>
              e.kind == ActivityKind.count &&
              session.targets.containsKey(e.subjectId) &&
              !reversed.contains(e.id),
        )
        .toList();
    if (candidates.isEmpty) return;
    final last = candidates.last;
    await activity.store.append(
      scope,
      _event(ActivityKind.undo, last.subjectId, reverses: last.id),
    );
    await _saveSession(
      cursor: items
          .indexWhere((e) => e.id == last.subjectId)
          .clamp(0, items.length - 1),
    );
    await _refresh();
    activity.changed(scope);
  });

  Future<void> restart() => _enqueue(() async {
    _device ??= await activity.store.deviceId;
    await _saveSession(
      cursor: 0,
      epoch: operationId(),
      targets: {for (final item in items) item.id: item.target},
    );
    await activity.store.append(scope, _event(ActivityKind.reset, group.id));
    await _refresh();
    activity.changed(scope);
  });
  Future<void> saveSettings() => _enqueue(() async {
    await settings.save(activity.quran.preferences!, scope);
    await _saveSession();
    activity.changed(scope);
  });
  Future<void> flush() => _writes;
  @override
  void dispose() {
    _disposed = true;
    activity.removeListener(_activityChanged);
    super.dispose();
  }
}
