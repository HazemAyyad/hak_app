import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;

class SplashScreen extends StatefulWidget {
  const SplashScreen({required this.onFinished, super.key});
  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  rive.File? _file;
  rive.RiveWidgetController? _controller;
  bool _loading = false;
  bool _failed = false;
  Timer? _timer;
  bool _started = false;
  bool _finished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _begin(const Duration(milliseconds: 400));
    } else if (!_loading && _controller == null) {
      _loading = true;
      // Keep startup usable if loading or the native renderer fails.
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

  void _begin([Duration duration = const Duration(milliseconds: 2600)]) {
    if (_started || _finished || !mounted) return;
    _started = true;
    _timer?.cancel();
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
    super.dispose();
  }

  Widget _logo() => Image.asset(
    'assets/branding/haq_logo_transparent.png',
    fit: BoxFit.contain,
  );

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
                  child: _failed || MediaQuery.disableAnimationsOf(context)
                      ? _logo()
                      : _controller == null
                      ? const SizedBox()
                      : rive.RiveWidget(
                          controller: _controller!,
                          fit: rive.Fit.contain,
                        ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'نورٌ لقلبك، ورفيقٌ ليومك',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF102A43),
                  fontWeight: FontWeight.w700,
                ),
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
