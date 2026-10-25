part of 'sakinah_page.dart';

class _SakinahSessionPage extends StatefulWidget {
  const _SakinahSessionPage({
    required this.controller,
    required this.activity,
    required this.scope,
    required this.path,
    required this.pattern,
    required this.minutes,
    required this.routes,
    required this.reduced,
    required this.haptic,
    required this.record,
    this.clock,
  });
  final ReligiousController controller;
  final ReligiousActivityController activity;
  final String scope;
  final int path, minutes;
  final BreathingPattern pattern;
  final RouteObserver<ModalRoute<dynamic>> routes;
  final bool reduced, haptic, record;
  final Duration Function()? clock;
  @override
  State<_SakinahSessionPage> createState() => _SakinahSessionPageState();
}

class _SakinahSessionPageState extends State<_SakinahSessionPage>
    with WidgetsBindingObserver, RouteAware {
  late final BreathingSession session;
  late final String _id = operationId();
  late bool _hapticEnabled = widget.haptic;
  Timer? _timer;
  ModalRoute<dynamic>? _route;
  bool _ending = false, _saving = false, _saved = false, _foreground = true;
  String? _error;
  SakinahRecord? _record;
  BreathingPhase? _lastPhase;
  @override
  void initState() {
    super.initState();
    session = BreathingSession(
      pattern: widget.pattern,
      duration: Duration(minutes: widget.minutes),
      monotonicClock: widget.clock,
    )..addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    session.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route && route != null) {
      widget.routes.unsubscribe(this);
      _route = route;
      widget.routes.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    session.pause();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) session.pause();
  }

  void _changed() {
    if (!mounted) return;
    if (session.finished || session.status == BreathingStatus.paused) {
      _timer?.cancel();
    } else if (_timer?.isActive != true) {
      _timer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => session.tick(),
      );
    }
    if (session.status == BreathingStatus.running &&
        _foreground &&
        _hapticEnabled &&
        session.current.phase != _lastPhase) {
      unawaited(HapticFeedback.selectionClick());
    }
    _lastPhase = session.current.phase;
    if (session.finished) {
      _timer?.cancel();
      if (!_saving && !_saved && _error == null) unawaited(_save());
    }
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving || _saved) return;
    if (!widget.record) {
      _saved = true;
      return;
    }
    _saving = true;
    try {
      _record ??= await SakinahRecord.create(
        widget.activity,
        widget.scope,
        _id,
        sakinahPaths[widget.path],
        session,
      );
      final saved = await _record!.save();
      if (mounted) {
        _saved = saved;
        _error = saved ? null : 'تغيّر الحساب؛ لم تحفظ الجلسة في الحساب الجديد';
      }
    } catch (_) {
      if (mounted) _error = 'تعذّر حفظ الجلسة؛ يمكنك إعادة المحاولة';
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _end() async {
    if (_ending || session.finished) return;
    _ending = true;
    final wasPaused = session.status == BreathingStatus.paused;
    session.pause();
    final end = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('إنهاء الجلسة مبكرًا؟'),
        content: const Text(
          'يمكنك المتابعة من مكانك. الإنهاء المبكر يحفظ وقت التنفّس الفعلي فقط إذا اخترت الحفظ، ولا يعتبر جلسة مكتملة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('متابعة الجلسة'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إنهاء الجلسة'),
          ),
        ],
      ),
    );
    _ending = false;
    if (!mounted) return;
    if (end == true) {
      session.cancel();
    } else if (!wasPaused && _foreground) {
      session.resume();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.routes.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(_changed);
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: session.finished,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_end());
    },
    child: _SakinahLayout(
      title: session.finished
          ? session.status == BreathingStatus.completed
                ? 'اكتملت الجلسة'
                : 'انتهت الجلسة'
          : 'جلسة ${sakinahNames[widget.path]}',
      subtitle: 'لحظات من الطمأنينة',
      onBack: session.finished ? () => Navigator.pop(context) : _end,
      children: session.finished ? _closing(context) : _active(context),
    ),
  );
  List<Widget> _active(BuildContext context) {
    final p = AppPalette.of(context),
        paused = session.status == BreathingStatus.paused;
    final phase = session.current;
    final preparing = session.status == BreathingStatus.preparing;
    final reduced = widget.reduced || MediaQuery.disableAnimationsOf(context);
    final expansion = switch (phase.phase) {
      BreathingPhase.inhale => phase.fraction,
      BreathingPhase.holdIn => 1.0,
      BreathingPhase.exhale => 1 - phase.fraction,
      BreathingPhase.holdOut => 0.0,
    };
    return [
      _sPanel(
        context,
        Column(
          children: [
            LayoutBuilder(
              builder: (context, limits) => SizedBox(
                width: math.min(320, limits.maxWidth),
                height: math.min(320, limits.maxWidth),
                child: CustomPaint(
                  painter: _BreathingRing(
                    p.dark,
                    session.progress,
                    reduced ? 1 : .65 + expansion * .35,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          paused
                              ? 'متوقف مؤقتًا'
                              : preparing
                              ? 'استعد بهدوء'
                              : [
                                  'شهيق',
                                  'حبس',
                                  'زفير',
                                  'حبس',
                                ][phase.phase.index],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: paused ? 18 : 26,
                            fontWeight: FontWeight.bold,
                            color: p.heading,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Icon(
                          paused ? Icons.pause : Icons.air,
                          size: 36,
                          color: const Color(0xFF2A8C82),
                        ),
                        Text(
                          preparing
                              ? '${session.preparationSeconds}'
                              : '${phase.seconds}',
                          style: TextStyle(fontSize: 20, color: p.muted),
                        ),
                        const SizedBox(height: 8),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            '${(session.remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(session.remainingSeconds % 60).toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                              color: p.heading,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('الدورات المكتملة: ${session.cycles}'),
            const SizedBox(height: 8),
            Text(
              sakinahWords[widget.path],
              style: TextStyle(
                fontFamily: 'AmiriQuran',
                color: p.tealHeading,
                fontSize: 25,
              ),
            ),
            const SizedBox(height: 16),
            FilterChip(
              key: const ValueKey('breathing-haptic'),
              avatar: const Icon(Icons.vibration),
              label: const Text('اهتزاز الجلسة'),
              selected: _hapticEnabled,
              onSelected: (v) => setState(() => _hapticEnabled = v),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  key: const ValueKey('breathing-pause'),
                  onPressed: paused ? session.resume : session.pause,
                  icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                  label: Text(paused ? 'متابعة' : 'إيقاف مؤقت'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _end,
                  icon: const Icon(Icons.stop_outlined),
                  label: const Text('إنهاء الجلسة'),
                ),
              ],
            ),
          ],
        ),
      ),
      const Text('عند انتقال التطبيق للخلفية تتوقف الجلسة حتى تختار المتابعة.'),
    ];
  }

  List<Widget> _closing(BuildContext context) {
    final p = AppPalette.of(context),
        repo = widget.controller.quran.repository!;
    return [
      _sPanel(
        context,
        Column(
          children: [
            Icon(
              session.status == BreathingStatus.completed
                  ? Icons.check
                  : Icons.stop_circle_outlined,
              color: const Color(0xFFC7A45A),
              size: 54,
            ),
            const SizedBox(height: 12),
            Text(
              session.status == BreathingStatus.completed
                  ? 'تقبّل الله منك'
                  : 'يمكنك العودة في وقت يناسبك',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 23, color: p.heading),
            ),
            Text('${session.elapsed.inSeconds} ثانية من التنفّس الفعلي'),
          ],
        ),
        tinted: true,
      ),
      for (final key in sakinahVerses[widget.path])
        _sPanel(
          context,
          Column(
            children: [
              Text(
                repo.byKey[key]!.text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'AmiriQuran',
                  fontSize: 25,
                  height: 1.9,
                  color: p.heading,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'سورة ${repo.surah(repo.byKey[key]!.surah).name} • الآية ${repo.byKey[key]!.ayah}',
                style: TextStyle(color: p.muted),
              ),
            ],
          ),
        ),
      Text(
        !widget.record
            ? 'لم تحفظ هذه الجلسة حسب اختيارك.'
            : _saved
            ? 'حُفظت الجلسة في سجلك.'
            : _saving
            ? 'جارٍ حفظ الجلسة…'
            : _error ?? '',
      ),
      if (_error != null)
        TextButton(
          onPressed: _saving
              ? null
              : () {
                  _error = null;
                  unawaited(_save());
                },
          child: const Text('إعادة محاولة الحفظ'),
        ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('تم'),
      ),
    ];
  }
}

class _BreathingRing extends CustomPainter {
  const _BreathingRing(this.dark, this.progress, this.expansion);
  final bool dark;
  final double progress, expansion;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero),
        radius = size.shortestSide / 2 - 10;
    final ornament = Paint()
      ..color = const Color(0xFFC7A45A).withValues(alpha: dark ? .1 : .12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6;
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * radius * .42;
      canvas.drawCircle(point, radius * .3 * expansion, ornament);
    }
    final stroke = Paint()
      ..color = dark ? const Color(0xFF263F4C) : const Color(0xFFEFEBE3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9;
    canvas.drawCircle(center, radius, stroke);
    stroke
      ..color = const Color(0xFF2A8C82)
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      stroke,
    );
  }

  @override
  bool shouldRepaint(_BreathingRing old) =>
      old.progress != progress ||
      old.expansion != expansion ||
      old.dark != dark;
}
