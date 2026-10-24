import 'dart:async';
import 'package:flutter/foundation.dart';

/// One lease per native handler. Loads and controls share a serial command lane,
/// so a previous owner's delayed command cannot affect a later recording.
class QuranPlaybackOwnership {
  Object? _owner;
  VoidCallback? _onLost;
  int _epoch = 0;
  Future<void>? _commands;

  bool owns(Object owner) => identical(_owner, owner);
  bool get unclaimed => _owner == null;

  void claim(Object owner, VoidCallback onLost) {
    if (owns(owner)) return;
    final previous = _onLost;
    _owner = owner;
    _onLost = onLost;
    _epoch++;
    previous?.call();
  }

  Future<bool> run(Object owner, Future<void> Function() command) {
    final epoch = _epoch;
    Future<bool> execute() async {
      if (!owns(owner) || epoch != _epoch) return false;
      await command();
      return true;
    }

    final previous = _commands;
    final completed = Completer<void>();
    final tail = completed.future;
    _commands = tail;
    final job = previous == null ? execute() : previous.then((_) => execute());
    void finish() {
      if (identical(_commands, tail)) _commands = null;
      completed.complete();
    }

    unawaited(
      job.then<void>(
        (_) => finish(),
        onError: (Object _, StackTrace _) => finish(),
      ),
    );
    return job;
  }

  void release(Object owner) {
    if (!owns(owner)) return;
    _owner = null;
    _onLost = null;
    _epoch++;
  }
}
