import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../religious_activity/data/activity_controller.dart';
import '../../religious_activity/data/activity_models.dart';
import 'adhkar_repository.dart';
import 'adhkar_session_controller.dart';

class DhikrGroupProgress {
  const DhikrGroupProgress({
    required this.completed,
    required this.total,
    required this.read,
    required this.target,
  });
  final int completed, total, read, target;
  double get fraction => target == 0 ? 0 : read / target;
  int get percent => (fraction * 100).floor();
}

/// Reads the existing daily event ledger; browsing never creates a session.
class AdhkarProgress extends ChangeNotifier {
  AdhkarProgress(
    this.activity,
    this.repository, {
    DateTime Function()? clock,
    bool autoRefresh = true,
  }) : now = clock ?? DateTime.now {
    activity.addListener(_changed);
    if (autoRefresh) {
      _timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (_day != AdhkarSessionController.day(now())) unawaited(refresh());
      });
    }
  }
  final ReligiousActivityController activity;
  final AdhkarRepository repository;
  final DateTime Function() now;
  Map<String, DhikrGroupProgress> groups = {};
  String? error, _day, _scope;
  Timer? _timer;
  bool _disposed = false;
  int _generation = 0;
  void _changed() {
    if (_scope != activity.scope) {
      groups = {};
      notifyListeners();
    }
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final generation = ++_generation, scope = activity.scope;
    final day = AdhkarSessionController.day(now());
    try {
      final library = await repository.library(activity.store, scope);
      final sessions = (await activity.store.entities(
        scope,
        kind: PersonalEntityKind.session,
      )).whereType<DhikrSession>().where((s) => s.day == day);
      final saved = {for (final session in sessions) session.groupId: session};
      final next = <String, DhikrGroupProgress>{};
      for (final group in library.groups) {
        final session = saved[group.id];
        final counts = session == null
            ? <String, int>{}
            : await activity.store.counts(scope, session.id, session.epoch);
        var completed = 0, read = 0, target = 0, total = 0;
        for (final id in group.itemIds) {
          final item = library.entries[id];
          if (item == null) continue;
          final goal = item.personal
              ? item.target
              : session?.targets[id] ?? item.target;
          final value = (counts[id] ?? 0).clamp(0, goal);
          total++;
          target += goal;
          read += value;
          if (value == goal) completed++;
        }
        next[group.id] = DhikrGroupProgress(
          completed: completed,
          total: total,
          read: read,
          target: target,
        );
      }
      if (_disposed ||
          generation != _generation ||
          scope != activity.scope ||
          day != AdhkarSessionController.day(now())) {
        return;
      }
      _scope = scope;
      _day = day;
      groups = next;
      error = null;
      notifyListeners();
    } catch (_) {
      if (!_disposed && generation == _generation && scope == activity.scope) {
        groups = {};
        error = 'تعذّر تحميل تقدّم اليوم؛ اضغط لإعادة المحاولة';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    activity.removeListener(_changed);
    super.dispose();
  }
}
