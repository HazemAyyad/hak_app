part of 'prayer_page.dart';

/// In-app visual preview. Android's closed-app alarm uses HaqAdhanActivity.
/// This surface never schedules a prayer or starts audio.
class AdhanScreenPreview extends StatefulWidget {
  const AdhanScreenPreview({super.key, required this.controller});
  final PrayerController controller;
  @override
  State<AdhanScreenPreview> createState() => _AdhanScreenPreviewState();
}

class _AdhanScreenPreviewState extends State<AdhanScreenPreview> {
  int scene = 0;
  Timer? timer;
  static const photos = [
    'assets/home/dawn.png',
    'assets/religious/hands.png',
    'assets/religious/madina.png',
  ];
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !MediaQuery.disableAnimationsOf(context)) {
        setState(() => scene = (scene + 1) % photos.length);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF102A43),
        body: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 850),
              child: Image.asset(
                photos[scene],
                key: ValueKey(scene),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x80102A43),
                    Color(0x20102A43),
                    Color(0xEE0B1722),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'إغلاق المعاينة',
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                  ),
                                ),
                                const Expanded(
                                  child: Text(
                                    'حق · معاينة شاشة الأذان',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                                const Icon(Icons.tune, color: Colors.white),
                              ],
                            ),
                            Text(
                              'حان وقت ${c.upcoming?.name.label ?? 'الصلاة'}',
                              style: const TextStyle(
                                color: Color(0xFFC7A45A),
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Container(
                              width: 84,
                              height: 84,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F4ED),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFC7A45A),
                                ),
                              ),
                              child: Image.asset(
                                'assets/branding/haq_logo_transparent.png',
                              ),
                            ),
                            const Text(
                              'الله أكبر',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 44,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            if (c.config.iqamaMinutes > 0)
                              Container(
                                width: 164,
                                height: 164,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xCC0C4B4C),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFC7A45A),
                                    width: 2,
                                  ),
                                ),
                                child: Text(
                                  'الإقامة بعد\n${c.config.iqamaMinutes.toString().padLeft(2, '0')}:00',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            const Text(
                              'مدة الإقامة حسب إعدادك · المعاينة بدون صوت',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: FilledButton(
                                onPressed: () => Navigator.pop(context),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF2A8C82),
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('أذكار الصلاة'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                for (final label in ['القرآن', 'القبلة'])
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 3,
                                      ),
                                      child: OutlinedButton(
                                        onPressed: () => Navigator.pop(context),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          side: const BorderSide(
                                            color: Color(0xFFC7A45A),
                                          ),
                                          minimumSize: const Size(0, 50),
                                        ),
                                        child: Text(label),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
