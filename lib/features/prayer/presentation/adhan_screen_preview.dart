part of 'prayer_page.dart';

/// Silent, viewport-sized preview of the native Android alarm surface.
class AdhanScreenPreview extends StatefulWidget {
  const AdhanScreenPreview({super.key, required this.controller});
  final PrayerController controller;
  @override
  State<AdhanScreenPreview> createState() => _AdhanScreenPreviewState();
}

class _AdhanScreenPreviewState extends State<AdhanScreenPreview>
    with SingleTickerProviderStateMixin {
  static const photos = [
    'assets/home/dawn.png',
    'assets/religious/hands.png',
    'assets/religious/madina.png',
  ];
  int scene = 0;
  Timer? timer;
  late final AnimationController pulse;
  @override
  void initState() {
    super.initState();
    pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !MediaQuery.disableAnimationsOf(context)) {
        setState(() => scene = (scene + 1) % photos.length);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      pulse.stop();
      pulse.value = 1;
    } else {
      pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    pulse.dispose();
    super.dispose();
  }

  void open(String route) => Navigator.pop(context, route);
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection:
        LocalizationScope.maybeOf(context)?.language.direction ??
        TextDirection.rtl,
    child: Scaffold(
      backgroundColor: const Color(0xFF0B1722),
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 900),
            child: Image.asset(
              photos[scene],
              key: ValueKey(scene),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x99102A43),
                  Color(0x55102A43),
                  Color(0xF50B1722),
                ],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxHeight < 680 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.2;
                return Padding(
                  padding: EdgeInsets.all(compact ? 12 : 18),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: context.prayerLabel('إغلاق المعاينة'),
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
                            ),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  context.prayerLabel(
                                    'حق · معاينة شاشة الأذان',
                                  ),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'إعدادات الأذان',
                              onPressed: () => open('prayer-settings'),
                              icon: const Icon(Icons.tune, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: compact ? 40 : 52,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            context.tr(
                              'prayer.timeFor',
                              args: {
                                'prayer':
                                    widget.controller.upcoming?.name
                                        .displayLabel(context) ??
                                    context.prayerLabel('الصلاة'),
                              },
                            ),
                            style: const TextStyle(
                              color: Color(0xFFC7A45A),
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: compact ? 48 : 68,
                        height: compact ? 48 : 68,
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F4ED),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFC7A45A)),
                        ),
                        child: Image.asset(
                          'assets/branding/haq_logo_transparent.png',
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: constraints.maxWidth - 36,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    height: compact ? 80 : 110,
                                    child: AnimatedBuilder(
                                      animation: pulse,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          'الله أكبر',
                                          key: ValueKey('adhan-animated-title'),
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 56,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      builder: (context, child) => Opacity(
                                        opacity: .75 + .25 * pulse.value,
                                        child: Transform.scale(
                                          scale: .96 + .04 * pulse.value,
                                          child: child,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (widget.controller.config.iqamaMinutes >
                                      0) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      width: compact ? 76 : 106,
                                      height: compact ? 76 : 106,
                                      padding: const EdgeInsets.all(8),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: const Color(0xCC0C4B4C),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFFC7A45A),
                                          width: 2,
                                        ),
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          context.tr(
                                            'prayer.iqamaPreview',
                                            args: {
                                              'time':
                                                  '${widget.controller.config.iqamaMinutes.toString().padLeft(2, '0')}:00',
                                            },
                                          ),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      context.prayerLabel(
                                        'مدة الإقامة حسب إعدادك',
                                      ),
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: () => open('adhkar-after-prayer'),
                          style: FilledButton.styleFrom(
                            backgroundColor: appAccentFill(
                              context,
                              const Color(0xFF2A8C82),
                            ),
                            foregroundColor: Colors.white,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('أذكار بعد الصلاة'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final item in [
                            (context.prayerLabel('القرآن'), 'quran'),
                            (context.prayerLabel('القبلة'), 'qibla'),
                          ])
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: SizedBox(
                                  height: 48,
                                  child: OutlinedButton(
                                    onPressed: () => open(item.$2),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(
                                        color: Color(0xFFC7A45A),
                                      ),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(context.prayerLabel(item.$1)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFFC7A45A)),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(context.prayerLabel('إغلاق المعاينة')),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'المعاينة بدون صوت',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
