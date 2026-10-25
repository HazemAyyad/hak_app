import 'dart:math' as math;
import 'package:flutter/foundation.dart';

enum BreathingStatus { idle, preparing, running, paused, completed, cancelled }

enum BreathingPhase { inhale, holdIn, exhale, holdOut }

class BreathingPattern {
  BreathingPattern(this.inhale, this.holdIn, this.exhale, this.holdOut) {
    if (inhale < 1 ||
        inhale > 20 ||
        exhale < 1 ||
        exhale > 20 ||
        holdIn < 0 ||
        holdIn > 20 ||
        holdOut < 0 ||
        holdOut > 20) {
      throw const FormatException('Invalid breathing pattern');
    }
  }
  final int inhale, holdIn, exhale, holdOut;
  List<int> get seconds => [inhale, holdIn, exhale, holdOut];
  int get cycleSeconds => inhale + holdIn + exhale + holdOut;
  static BreathingPattern get relaxing => BreathingPattern(4, 7, 8, 0);
  static BreathingPattern get box => BreathingPattern(4, 4, 4, 4);
  static BreathingPattern get coherent => BreathingPattern(5, 0, 5, 0);
}

/// A monotonic clock supplies elapsed time. UI ticks only repaint; missed
/// frames do not stretch the session, and paused/background time never counts.
class BreathingSession extends ChangeNotifier {
  BreathingSession({
    required this.pattern,
    required this.duration,
    Duration Function()? monotonicClock,
    this.preparation = const Duration(seconds: 3),
  }) {
    if (![60, 180, 300].contains(duration.inSeconds) ||
        duration.inMilliseconds % 1000 != 0 ||
        preparation.isNegative) {
      throw const FormatException('Invalid breathing duration');
    }
    final watch = Stopwatch()..start();
    _clock = monotonicClock ?? (() => watch.elapsed);
  }
  final BreathingPattern pattern;
  final Duration duration, preparation;
  late final Duration Function() _clock;
  BreathingStatus status = BreathingStatus.idle;
  BreathingStatus _beforePause = BreathingStatus.preparing;
  Duration _start = Duration.zero, _active = Duration.zero;
  late Duration _prepareLeft = preparation;
  bool _disposed = false;

  bool get finished =>
      status == BreathingStatus.completed ||
      status == BreathingStatus.cancelled;
  Duration _delta(Duration since) {
    final result = _clock() - since;
    return result.isNegative ? Duration.zero : result;
  }

  Duration get elapsed {
    final raw = status == BreathingStatus.running
        ? _active + _delta(_start)
        : _active;
    return Duration(
      microseconds: math.min(duration.inMicroseconds, raw.inMicroseconds),
    );
  }

  Duration get remaining => duration - elapsed;
  int get remainingSeconds => (remaining.inMilliseconds / 1000).ceil();
  int get preparationSeconds => status == BreathingStatus.preparing
      ? math.max(
          0,
          ((_prepareLeft - _delta(_start)).inMilliseconds / 1000).ceil(),
        )
      : (_prepareLeft.inMilliseconds / 1000).ceil();
  double get progress => elapsed.inMicroseconds / duration.inMicroseconds;
  int get cycles => elapsed.inMilliseconds ~/ (pattern.cycleSeconds * 1000);
  ({BreathingPhase phase, double fraction, int seconds}) get current {
    var ms = elapsed.inMilliseconds % (pattern.cycleSeconds * 1000);
    for (var i = 0; i < 4; i++) {
      final length = pattern.seconds[i] * 1000;
      if (length > 0 && ms < length) {
        return (
          phase: BreathingPhase.values[i],
          fraction: ms / length,
          seconds: ((length - ms) / 1000).ceil(),
        );
      }
      ms -= length;
    }
    return (phase: BreathingPhase.inhale, fraction: 0, seconds: pattern.inhale);
  }

  void start() {
    if (_disposed || status != BreathingStatus.idle) return;
    _start = _clock();
    status = preparation == Duration.zero
        ? BreathingStatus.running
        : BreathingStatus.preparing;
    notifyListeners();
  }

  void tick() {
    if (_disposed ||
        finished ||
        status == BreathingStatus.idle ||
        status == BreathingStatus.paused) {
      return;
    }
    if (status == BreathingStatus.preparing && _delta(_start) >= _prepareLeft) {
      _start += _prepareLeft;
      _prepareLeft = Duration.zero;
      status = BreathingStatus.running;
    }
    if (status == BreathingStatus.running && elapsed >= duration) {
      _active = duration;
      status = BreathingStatus.completed;
    }
    notifyListeners();
  }

  void pause() {
    if (_disposed ||
        finished ||
        status == BreathingStatus.paused ||
        status == BreathingStatus.idle) {
      return;
    }
    tick();
    if (finished) return;
    _beforePause = status;
    if (status == BreathingStatus.preparing) {
      _prepareLeft -= _delta(_start);
    } else {
      _active = elapsed;
    }
    status = BreathingStatus.paused;
    notifyListeners();
  }

  void resume() {
    if (_disposed || status != BreathingStatus.paused) return;
    _start = _clock();
    status = _beforePause;
    notifyListeners();
  }

  void cancel() {
    if (_disposed || finished) return;
    pause();
    if (finished) return;
    status = BreathingStatus.cancelled;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
