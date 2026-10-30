import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_experience.dart';
import '../core/localization/app_localization.dart';
import '../core/localization/language_page.dart';

import 'onboarding_screen.dart';
import 'splash_screen.dart';

enum _StartupStage { splash, language, onboarding, ready }

class StartupFlow extends StatefulWidget {
  const StartupFlow({
    required this.preferences,
    required this.child,
    super.key,
  });
  static const onboardingKey = 'startup.onboarding.v1.completed';
  final SharedPreferences preferences;
  final Widget child;

  @override
  State<StartupFlow> createState() => _StartupFlowState();
}

class _StartupFlowState extends State<StartupFlow> {
  _StartupStage _stage = _StartupStage.splash;

  void _finishSplash() {
    if (!mounted || _stage != _StartupStage.splash) return;
    AppExperienceScope.maybeOf(context)?.transition();
    setState(
      () =>
          _stage = widget.preferences.getBool(StartupFlow.onboardingKey) == true
          ? _StartupStage.ready
          : LocalizationScope.maybeOf(context) != null &&
                !LocalizationScope.maybeOf(context)!.chosen
          ? _StartupStage.language
          : _StartupStage.onboarding,
    );
  }

  Future<void> _finishOnboarding() async {
    final saved = await widget.preferences.setBool(
      StartupFlow.onboardingKey,
      true,
    );
    if (!saved) throw StateError('Unable to save onboarding preference.');
    if (mounted) {
      AppExperienceScope.maybeOf(context)?.transition();
      setState(() => _stage = _StartupStage.ready);
    }
  }

  @override
  Widget build(BuildContext context) => switch (_stage) {
    _StartupStage.splash => SplashScreen(onFinished: _finishSplash),
    _StartupStage.language => LanguagePage(
      onContinue: () async {
        if (mounted) setState(() => _stage = _StartupStage.onboarding);
      },
    ),
    _StartupStage.onboarding => OnboardingScreen(onComplete: _finishOnboarding),
    _StartupStage.ready => widget.child,
  };
}
