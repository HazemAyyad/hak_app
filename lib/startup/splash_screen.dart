import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;
import '../core/localization/ui_text.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({required this.onFinished, super.key});
  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _taglineMotion;
  rive.File? _file;
  rive.RiveWidgetController? _controller;
  bool _loading = false;
  bool _failed = false;
  Timer? _timer;
  bool _started = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _taglineMotion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _begin(const Duration(milliseconds: 400));
    } else if (!_loading && _controller == null) {
      _loading = true;
      _timer = Timer(const Duration(seconds: 6), _finish);
      _loadAnimation();
    }
  }

  Future<void> _loadAnimation() async {
    rive.File? file;
    try {
      await rive.RiveNative.init();
      file = await rive.File.asset(
        'assets/animations/haq_splash.riv',
        riveFactory: rive.Factory.flutter,
      );
      if (!mounted || _finished) {
        file?.dispose();
        return;
      }
      if (file == null) {
        throw StateError('Unable to load the splash animation.');
      }
      final controller = rive.RiveWidgetController(file);
      _file = file;
      setState(() => _controller = controller);
      _begin();
    } catch (_) {
      file?.dispose();
      if (!mounted || _finished) return;
      setState(() => _failed = true);
      _begin();
    }
  }

  void _begin([Duration duration = const Duration(milliseconds: 2500)]) {
    if (_started || _finished || !mounted) return;
    _started = true;
    _timer?.cancel();
    if (!MediaQuery.disableAnimationsOf(context) && _controller != null) {
      _taglineMotion.forward();
    }
    _timer = Timer(duration, _finish);
  }

  void _finish() {
    if (!mounted || _finished) return;
    _finished = true;
    _timer?.cancel();
    widget.onFinished();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    _file?.dispose();
    _taglineMotion.dispose();
    super.dispose();
  }

  Widget _logo() =>
      Image.asset('assets/branding/haq_splash_logo.png', fit: BoxFit.contain);

  Widget _tagline(BuildContext context) {
    final text = context.homeLabel('نورٌ لقلبك، ورفيقٌ ليومك');
    final separator = RegExp('[،,]').firstMatch(text);
    final phrases = separator == null
        ? [text]
        : [
            text.substring(0, separator.end),
            text.substring(separator.end).trim(),
          ];
    final immediate = MediaQuery.disableAnimationsOf(context) || _failed;
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 4,
        runSpacing: 3,
        children: [
          for (var index = 0; index < phrases.length; index++)
            _phrase(phrases[index], index, immediate),
        ],
      ),
    );
  }

  Widget _phrase(String text, int index, bool immediate) {
    final phrase = Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 16,
        color: Color(0xFF102A43),
        fontWeight: FontWeight.w700,
      ),
    );
    if (immediate) return phrase;
    final progress = _taglineMotion.drive(
      CurveTween(
        curve: Interval(
          index == 0 ? .30 : .48,
          index == 0 ? .46 : .65,
          curve: Curves.easeOutCubic,
        ),
      ),
    );
    return FadeTransition(
      key: ValueKey('splash-tagline-$index'),
      opacity: progress,
      child: SlideTransition(
        position: progress.drive(
          Tween(begin: const Offset(0, .18), end: Offset.zero),
        ),
        child: phrase,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: const Color(0xFFFFFCF7),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: 'شعار تطبيق حق',
                image: true,
                child: SizedBox.square(
                  dimension: MediaQuery.sizeOf(
                    context,
                  ).width.clamp(220, 320).toDouble(),
                  child:
                      MediaQuery.disableAnimationsOf(context) ||
                          _controller == null
                      ? _logo()
                      : rive.RiveWidget(
                          controller: _controller!,
                          fit: rive.Fit.contain,
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _tagline(context),
              ),
              const SizedBox(height: 18),
              Container(
                width: 42,
                height: 3,
                decoration: BoxDecoration(
                  color: const Color(0xFFCAA15D),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
