import 'dart:async';
import 'package:flutter/material.dart';
import '../../religious_activity/data/activity_controller.dart';
import '../../religious_content/data/religious_controller.dart';
import '../data/progress_controller.dart';

/// Read-only home binding. Loading/failure never becomes invented progress.
class ProgressSummary extends StatefulWidget {
  const ProgressSummary({
    super.key,
    required this.controller,
    required this.builder,
  });
  final ReligiousController? controller;
  final Widget Function(BuildContext, ProgressController?, bool) builder;
  @override
  State<ProgressSummary> createState() => _ProgressSummaryState();
}

class _ProgressSummaryState extends State<ProgressSummary>
    with WidgetsBindingObserver {
  ProgressController? _value;
  ReligiousActivityController? _activity;
  bool _opening = false, _failed = false, _closed = false;
  Timer? _timer;
  String? _day;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller?.quran.addListener(_ready);
    _ready();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      final c = _value;
      if (c != null && c.day != _day) {
        _day = c.day;
        unawaited(c.refresh());
      }
    });
  }

  void _ready() {
    final controller = widget.controller;
    if (_closed ||
        _opening ||
        _value != null ||
        _failed ||
        controller?.quran.repository == null) {
      return;
    }
    _opening = true;
    unawaited(_open());
  }

  Future<void> _open() async {
    final generation = ++_generation;
    try {
      final activity = await widget.controller!.activity;
      if (_closed || generation != _generation) return;
      if (_activity != activity) {
        _activity?.removeListener(_account);
        _activity = activity..addListener(_account);
      }
      final c = await ProgressController.open(
        activity,
        widget.controller!.quran.repository!,
      );
      if (_closed || generation != _generation || c.scope != activity.scope) {
        c.dispose();
        return;
      }
      _value = c..addListener(_changed);
      _day = c.day;
    } catch (_) {
      if (!_closed && generation == _generation) _failed = true;
    } finally {
      if (!_closed && generation == _generation) {
        _opening = false;
        if (mounted) setState(() {});
        if (_value == null && !_failed) scheduleMicrotask(_ready);
      }
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _account() {
    if (_value == null || _value!.scope == _activity!.scope) return;
    _value!.removeListener(_changed);
    _value!.dispose();
    _value = null;
    _opening = false;
    _failed = false;
    _generation++;
    _ready();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_failed) {
        _failed = false;
        _ready();
      }
      unawaited(_value?.refresh());
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    widget.controller?.quran.removeListener(_ready);
    _activity?.removeListener(_account);
    _timer?.cancel();
    _value?.removeListener(_changed);
    _value?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    _value?.available == true ? _value : null,
    _failed,
  );
}
