import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../adhkar/data/adhkar_repository.dart' show adhkarIdentity;
import '../../quran/data/quran_repository.dart';
import '../../quran/data/quran_sync.dart' show operationId;
import '../../religious_activity/data/activity_controller.dart';
import '../../religious_activity/data/activity_models.dart';

/// Civil dates deliberately ignore DST when measuring a reading plan.
DateTime civilDate(String day) {
  activityDate(day);
  final date = DateTime.parse(day);
  return DateTime.utc(date.year, date.month, date.day);
}

String progressDay(DateTime now) =>
    '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

class KhatmaPortion {
  const KhatmaPortion(this.day, this.first, this.last);
  final String day;
  final int first, last;
  int get pages => math.max(0, last - first + 1);
}

List<KhatmaPortion> khatmaPlan(QuranKhatma value) {
  final start = civilDate(value.startDate);
  final days = civilDate(value.endDate).difference(start).inDays + 1;
  if (days > 3650) throw const FormatException('Plan exceeds ten years');
  final total = value.lastPage - value.firstPage + 1;
  return List.generate(
    days,
    (i) => KhatmaPortion(
      progressDay(start.add(Duration(days: i))),
      value.firstPage + total * i ~/ days,
      value.firstPage + total * (i + 1) ~/ days - 1,
    ),
  );
}

class ProgressTotals {
  const ProgressTotals({
    this.adhkar = 0,
    this.tasbih = 0,
    this.pages = 0,
    this.habits = 0,
    this.breathingSeconds = 0,
    this.morning = 0,
    this.evening = 0,
    this.otherAdhkar = 0,
  });
  final int adhkar, tasbih, pages, habits, breathingSeconds;
  final int morning, evening, otherAdhkar;
}

class ProgressController extends ChangeNotifier {
  ProgressController._(
    this.activity,
    this.repository,
    this.scope,
    this.device,
    this.clock,
  ) {
    activity.addListener(_changed);
  }
  final ReligiousActivityController activity;
  final QuranRepository repository;
  final String scope, device;
  final DateTime Function() clock;
  List<ReligiousHabit> habits = [];
  List<QuranKhatma> khatmas = [];
  List<ReligiousActivityEvent> history = [];
  Map<String, DhikrSession> sessions = {};
  bool _disposed = false, _publishing = false;
  Future<void> _jobs = Future.value();
  Timer? _refreshDelay;
  String? error;
  bool get available => !_disposed && activity.scope == scope;
  String get day => progressDay(clock());

  static Future<ProgressController> open(
    ReligiousActivityController activity,
    QuranRepository repository, {
    DateTime Function()? clock,
  }) async {
    final scope = activity.scope;
    final c = ProgressController._(
      activity,
      repository,
      scope,
      await activity.store.deviceId,
      clock ?? DateTime.now,
    );
    try {
      await c._refresh();
      return c;
    } catch (_) {
      c.dispose();
      rethrow;
    }
  }

  void _changed() {
    if (_disposed || _publishing) return;
    if (!available) {
      notifyListeners();
      return;
    }
    _refreshDelay?.cancel();
    _refreshDelay = Timer(
      const Duration(milliseconds: 120),
      () => unawaited(refresh()),
    );
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final job = _jobs.then((_) async {
      if (available) await action();
    });
    _jobs = job.catchError((Object e) {
      if (!_disposed) {
        error = 'تعذّر حفظ التغيير؛ حاول مرة أخرى';
        notifyListeners();
      }
    });
    return _jobs;
  }

  Future<void> refresh() => _enqueue(_refresh);
  Future<void> flush() => _jobs;
  Future<void> _refresh() async {
    final entities = await activity.store.entities(scope);
    final events = await activity.store.events(scope);
    if (!available) return;
    habits = entities.whereType<ReligiousHabit>().toList();
    khatmas = entities.whereType<QuranKhatma>().toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    sessions = {for (final s in entities.whereType<DhikrSession>()) s.id: s};
    history = events;
    error = null;
    notifyListeners();
  }

  Future<void> _publish() async {
    await _refresh();
    if (!available) return;
    _publishing = true;
    activity.changed(scope);
    _publishing = false;
  }

  ReligiousActivityEvent _event(
    String session,
    String subject,
    String epoch,
    ActivityKind kind, {
    int amount = 0,
    String? reverses,
  }) {
    final now = clock();
    return ReligiousActivityEvent(
      id: operationId(),
      deviceId: device,
      sessionId: session,
      subjectId: subject,
      epoch: epoch,
      kind: kind,
      amount: amount,
      reverses: reverses,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        now.millisecondsSinceEpoch,
        isUtc: true,
      ),
      day: progressDay(now),
      utcOffsetMinutes: now.timeZoneOffset.inMinutes,
    );
  }

  Set<String> get _reversed => {
    for (final e in history)
      if (e.reverses != null) e.reverses!,
  };
  List<ReligiousActivityEvent> get effective {
    final reversed = _reversed;
    return history
        .where((e) => !reversed.contains(e.id) && e.kind != ActivityKind.undo)
        .toList();
  }

  bool due(ReligiousHabit habit, [String? date]) =>
      habit.enabled && habit.weekdays.contains(civilDate(date ?? day).weekday);
  int habitCount(ReligiousHabit habit, [String? date]) => math.min(
    habit.target,
    effective
        .where(
          (e) =>
              e.kind == ActivityKind.habit &&
              e.sessionId == habit.id &&
              e.epoch == habit.activeEpoch &&
              e.day == (date ?? day),
        )
        .fold<int>(0, (sum, e) => sum + e.amount),
  );

  Future<void> saveHabit(ReligiousHabit value) => _enqueue(() async {
    await activity.store.save(scope, value);
    await _publish();
  });
  Future<void> deleteHabit(ReligiousHabit value) => _enqueue(() async {
    await activity.store.remove(scope, value.kind, value.id);
    await _publish();
  });
  Future<void> countHabit(String id) => _enqueue(() async {
    await _refresh();
    if (!available) return;
    final matches = habits.where((h) => h.id == id);
    if (matches.isEmpty) return;
    final h = matches.first;
    if (!due(h) || habitCount(h) >= h.target) return;
    await activity.store.append(
      scope,
      _event(
        h.id,
        'habit:${h.id}:${h.target}',
        h.activeEpoch,
        ActivityKind.habit,
        amount: 1,
      ),
    );
    await _publish();
  });
  Future<void> undoHabit(String id) => _enqueue(() async {
    await _refresh();
    final matches = habits.where((h) => h.id == id);
    if (!available || matches.isEmpty) return;
    final h = matches.first;
    final candidates = effective.where(
      (e) =>
          e.sessionId == id &&
          e.epoch == h.activeEpoch &&
          e.kind == ActivityKind.habit &&
          e.day == day,
    );
    if (candidates.isEmpty) return;
    final e = candidates.last;
    await activity.store.append(
      scope,
      _event(id, e.subjectId, e.epoch, ActivityKind.undo, reverses: e.id),
    );
    await _publish();
  });

  QuranVerse firstVerse(QuranKhatma k) =>
      repository.verses.firstWhere((v) => v.page >= k.firstPage);
  QuranVerse lastVerse(QuranKhatma k) =>
      repository.verses.lastWhere((v) => v.page <= k.lastPage);
  int verseIndex(QuranVerse v) => repository.surah(v.surah).start + v.ayah - 1;
  QuranVerse? lastRead(QuranKhatma k) {
    var index = -1;
    for (final e in effective) {
      if (e.sessionId != k.id ||
          e.epoch != k.activeEpoch ||
          e.kind != ActivityKind.quranPage ||
          !e.subjectId.startsWith('quran-verse:')) {
        continue;
      }
      final v = repository.byKey[e.subjectId.substring('quran-verse:'.length)];
      if (v != null && v.page >= k.firstPage && v.page <= k.lastPage) {
        index = math.max(index, verseIndex(v));
      }
    }
    return index < 0 ? null : repository.verses[index];
  }

  Set<int> readPages(QuranKhatma k) => effective
      .where(
        (e) =>
            e.sessionId == k.id &&
            e.epoch == k.activeEpoch &&
            e.kind == ActivityKind.quranPage &&
            e.subjectId.startsWith('quran-page:'),
      )
      .map((e) => int.tryParse(e.subjectId.split(':').last))
      .whereType<int>()
      .where((p) => p >= k.firstPage && p <= k.lastPage)
      .toSet();
  bool completed(QuranKhatma k) => lastRead(k)?.key == lastVerse(k).key;
  List<({String epoch, int pages, bool complete, String day})> previousCycles(
    QuranKhatma k,
  ) {
    final events = effective
        .where((e) => e.sessionId == k.id && e.epoch != k.activeEpoch)
        .toList();
    return events.map((e) => e.epoch).toSet().map((epoch) {
      final cycle = events.where((e) => e.epoch == epoch).toList();
      final pages = cycle
          .where(
            (e) =>
                e.kind == ActivityKind.quranPage &&
                e.subjectId.startsWith('quran-page:'),
          )
          .map((e) => e.subjectId)
          .toSet()
          .length;
      final days = cycle.map((e) => e.day).toList()..sort();
      return (
        epoch: epoch,
        pages: pages,
        complete: cycle.any(
          (e) =>
              e.kind == ActivityKind.complete &&
              e.subjectId == 'khatma:complete',
        ),
        day: days.last,
      );
    }).toList()..sort((a, b) => b.day.compareTo(a.day));
  }

  QuranVerse resume(QuranKhatma k) {
    final read = lastRead(k);
    if (read == null) return firstVerse(k);
    final next = math.min(verseIndex(read) + 1, verseIndex(lastVerse(k)));
    return repository.verses[next];
  }

  double fraction(QuranKhatma k) =>
      readPages(k).length / (k.lastPage - k.firstPage + 1);
  Future<void> saveKhatma(QuranKhatma value) => _enqueue(() async {
    khatmaPlan(value); // Validate before writing, including plan duration.
    await activity.store.save(scope, value);
    await _publish();
  });
  Future<void> confirmRead(
    String id,
    QuranVerse verse, {
    String? expectedEpoch,
  }) => _enqueue(() async {
    await _refresh();
    final matches = khatmas.where((k) => k.id == id);
    if (!available || matches.isEmpty) return;
    final k = matches.first;
    if (expectedEpoch != null && expectedEpoch != k.activeEpoch) return;
    if (k.archived == true ||
        day.compareTo(k.startDate) < 0 ||
        verse.page < k.firstPage ||
        verse.page > k.lastPage ||
        verseIndex(verse) <=
            (lastRead(k) == null ? -1 : verseIndex(lastRead(k)!))) {
      return;
    }
    final done = readPages(k);
    final pageLast = repository.verses.lastWhere((v) => v.page == verse.page);
    final through = verse.key == pageLast.key ? verse.page : verse.page - 1;
    await activity.store.apply(
      scope,
      events: [
        _event(
          k.id,
          'quran-verse:${verse.key}',
          k.activeEpoch,
          ActivityKind.quranPage,
          amount: verse.page,
        ),
        for (var page = k.firstPage; page <= through; page++)
          if (!done.contains(page))
            _event(
              k.id,
              'quran-page:$page',
              k.activeEpoch,
              ActivityKind.quranPage,
              amount: 1,
            ),
        if (verse.key == lastVerse(k).key && !completed(k))
          _event(k.id, 'khatma:complete', k.activeEpoch, ActivityKind.complete),
      ],
    );
    await _publish();
  });
  Future<void> resetKhatma(QuranKhatma k) => saveKhatma(
    QuranKhatma(
      id: k.id,
      title: k.title,
      startDate: day,
      endDate: progressDay(
        civilDate(day).add(Duration(days: khatmaPlan(k).length - 1)),
      ),
      firstPage: k.firstPage,
      lastPage: k.lastPage,
      epoch: operationId(),
      archived: false,
      reminderMinutes: k.reminderMinutes,
    ),
  );

  ProgressTotals totals({String? date}) {
    var events = effective;
    final reset = events.lastIndexWhere(
      (e) => e.subjectId == 'statistics:all' && e.kind == ActivityKind.reset,
    );
    if (reset >= 0) events = events.sublist(reset + 1);
    var adhkar = 0, tasbih = 0, breathing = 0, morning = 0, evening = 0;
    final pages = <String, ReligiousActivityEvent>{},
        habitGroups = <String, int>{};
    final habitTargets = <String, int>{};
    for (final e in events) {
      if (e.kind == ActivityKind.quranPage &&
          e.subjectId.startsWith('quran-page:')) {
        final key = '${e.sessionId}:${e.epoch}:${e.subjectId}';
        final previous = pages[key];
        if (previous == null ||
            e.occurredAt.isBefore(previous.occurredAt) ||
            (e.occurredAt == previous.occurredAt &&
                e.id.compareTo(previous.id) < 0)) {
          pages[key] = e;
        }
      }
      if (date != null && e.day != date) continue;
      if (e.kind == ActivityKind.count) {
        if (e.subjectId.startsWith('tasbih:')) {
          tasbih += e.amount;
        } else {
          adhkar += e.amount;
          final group = sessions[e.sessionId]?.groupId;
          if (group == 'daily:morning') morning += e.amount;
          if (group == 'daily:evening') evening += e.amount;
        }
      }
      if (e.kind == ActivityKind.breathing) breathing += e.amount;
      if (e.kind == ActivityKind.habit) {
        final key = '${e.sessionId}:${e.epoch}:${e.day}';
        habitGroups[key] = (habitGroups[key] ?? 0) + e.amount;
        final target = e.subjectId.startsWith('habit:')
            ? int.tryParse(e.subjectId.split(':').last)
            : null;
        habitTargets[key] = target != null && target >= 1 && target <= 1000000
            ? target
            : habits.where((h) => h.id == e.sessionId).firstOrNull?.target ??
                  1000000;
      }
    }
    var habitTotal = 0;
    for (final entry in habitGroups.entries) {
      habitTotal += math.min(habitTargets[entry.key]!, entry.value);
    }
    return ProgressTotals(
      adhkar: adhkar,
      tasbih: tasbih,
      pages: pages.values.where((e) => date == null || e.day == date).length,
      habits: habitTotal,
      breathingSeconds: breathing,
      morning: morning,
      evening: evening,
      otherAdhkar: adhkar - morning - evening,
    );
  }

  Future<void> resetStatistics() => _enqueue(() async {
    final id = adhkarIdentity('statistics');
    await activity.store.append(
      scope,
      _event(id, 'statistics:all', id, ActivityKind.reset),
    );
    await _publish();
  });
  @override
  void dispose() {
    _disposed = true;
    _refreshDelay?.cancel();
    activity.removeListener(_changed);
    super.dispose();
  }
}
