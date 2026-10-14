import 'package:flutter/material.dart';

import '../app_appearance.dart';

const _teal = Color(0xFF00818B);
const _gold = Color(0xFFCAA15D);

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.onComplete, super.key});
  final Future<void> Function() onComplete;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;
  bool _saving = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int index) {
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _complete() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onComplete();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ الاختيار. حاول مجددًا.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _index > 0 && !_saving) _go(_index - 1);
        },
        child: Scaffold(
          backgroundColor: palette.background,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: _index == 0
                            ? null
                            : IconButton(
                                tooltip: 'رجوع',
                                onPressed: _saving
                                    ? null
                                    : () => _go(_index - 1),
                                icon: Icon(
                                  Icons.arrow_back_ios_new,
                                  color: palette.heading,
                                ),
                              ),
                      ),
                      Expanded(
                        child: Text(
                          '${_index + 1} من 3',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.muted, fontSize: 12),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: TextButton(
                          onPressed: _saving ? null : _complete,
                          child: const Text(
                            'تخطي',
                            style: TextStyle(color: _teal),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (index) => setState(() => _index = index),
                    children: const [
                      _OnboardingPage(
                        index: 0,
                        title: 'القرآن قريبٌ منك',
                        description:
                            'اقرأ القرآن دون إنترنت، وابحث عن الآيات، واحفظ موضع قراءتك للعودة إليه في أي وقت.',
                      ),
                      _OnboardingPage(
                        index: 1,
                        title: 'ابدأ يومك بذكر الله',
                        description:
                            'تعرّف على أقسام الأذكار والأدعية، واستكشف آية اليوم والمحتوى الديني في مكان واحد.',
                      ),
                      _OnboardingPage(
                        index: 2,
                        title: 'تجربة تناسبك',
                        description:
                            'اختر المظهر الفاتح أو الداكن، وغيّر نوع الخط وحجمه من الإعدادات لقراءة أكثر راحة.',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 22),
                  child: Column(
                    children: [
                      Semantics(
                        label: 'الصفحة ${_index + 1} من 3',
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            3,
                            (index) => AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              width: index == _index ? 26 : 7,
                              height: 7,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: index == _index ? _teal : palette.border,
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: _saving
                              ? null
                              : _index < 2
                              ? () => _go(_index + 1)
                              : _complete,
                          style: FilledButton.styleFrom(
                            backgroundColor: _teal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _saving
                                ? 'جارٍ الحفظ…'
                                : _index == 2
                                ? 'ابدأ الآن'
                                : 'التالي',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.index,
    required this.title,
    required this.description,
  });
  final int index;
  final String title, description;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: (constraints.maxHeight * .52).clamp(160, 300),
                child: _OnboardingIllustration(index: index),
              ),
              const SizedBox(height: 26),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  height: 1.5,
                  fontWeight: FontWeight.w800,
                  color: palette.heading,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.9,
                  color: palette.muted,
                ),
              ),
              const SizedBox(height: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingIllustration extends StatelessWidget {
  const _OnboardingIllustration({required this.index});
  final int index;
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: 280,
        height: 280,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                color: palette.paleTeal,
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _gold.withValues(alpha: .5)),
              ),
            ),
            if (index == 0)
              Image.asset(
                'assets/quran/quran_cover.png',
                height: 240,
                fit: BoxFit.contain,
              ),
            if (index == 1)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.eco_outlined, size: 80, color: _teal),
                  const SizedBox(height: 16),
                  _IllustrationTile(
                    icon: Icons.wb_sunny_outlined,
                    text: 'أذكار الصباح',
                    color: _gold,
                  ),
                  const SizedBox(height: 8),
                  _IllustrationTile(
                    icon: Icons.dark_mode_outlined,
                    text: 'أذكار المساء',
                    color: _teal,
                  ),
                ],
              ),
            if (index == 2)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ThemeSample(dark: false),
                      const SizedBox(width: 12),
                      _ThemeSample(dark: true),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _IllustrationTile(
                    icon: Icons.text_fields,
                    text: 'خطٌ يناسب قراءتك',
                    color: _teal,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _IllustrationTile extends StatelessWidget {
  const _IllustrationTile({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 206,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: AppPalette.of(context).surface,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: AppPalette.of(context).border),
    ),
    child: Row(
      children: [
        Icon(icon, size: 25, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: AppPalette.of(context).heading,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ThemeSample extends StatelessWidget {
  const _ThemeSample({required this.dark});
  final bool dark;
  @override
  Widget build(BuildContext context) => Container(
    width: 88,
    height: 120,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: dark ? const Color(0xFF102D3A) : const Color(0xFFFFFCF7),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: _gold.withValues(alpha: .5)),
    ),
    child: Column(
      children: [
        Icon(
          dark ? Icons.dark_mode_outlined : Icons.wb_sunny_outlined,
          color: _gold,
          size: 28,
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < 3; i++)
          Container(
            height: 5,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF527785) : const Color(0xFFBEDBD6),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    ),
  );
}
