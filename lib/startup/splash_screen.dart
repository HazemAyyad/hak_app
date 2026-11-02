import 'dart:async';

import 'package:flutter/material.dart';
import '../core/localization/ui_text.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({required this.onFinished, super.key});
  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  bool _started = false;
  bool _finished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _begin(const Duration(milliseconds: 400));
    } else {
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
    super.dispose();
  }

  Widget _logo() =>
      Image.asset('assets/branding/haq_splash_logo.png', fit: BoxFit.contain);

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
                  child: MediaQuery.disableAnimationsOf(context)
                      ? _logo()
                      : TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOutCubic,
                          child: _logo(),
                          builder: (context, value, child) => Opacity(
                            opacity: value,
                            child: Transform.scale(
                              scale: .92 + .08 * value,
                              child: child,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                context.homeLabel('نورٌ لقلبك، ورفيقٌ ليومك'),
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
