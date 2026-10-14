import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app_appearance.dart';
import '../data/quran_repository.dart';
import 'quran_widgets.dart';

class QuranAudioBanner extends StatelessWidget {
  const QuranAudioBanner({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Material(
      color: qTeal,
      child: InkWell(
        onTap: onOpen,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/quran/header_dark.png',
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),
            Positioned.fill(
              child: ColoredBox(color: qTeal.withValues(alpha: .72)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'التلاوة الصوتية',
                          style: qText(
                            context,
                            size: 18,
                            weight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'استمع إلى القرآن الكريم بصوت قارئك المفضل',
                          style: qText(context, size: 11, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'اختر القارئ  ‹',
                          style: qText(
                            context,
                            size: 12,
                            weight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.headphones_outlined,
                    color: Colors.white,
                    size: 45,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class QuranDailyVerse extends StatelessWidget {
  const QuranDailyVerse({
    super.key,
    required this.repository,
    required this.onExplain,
  });
  final QuranRepository repository;
  final ValueChanged<QuranVerse> onExplain;

  @override
  Widget build(BuildContext context) {
    const keys = ['2:255', '2:286', '65:4', '39:53', '94:5', '13:28', '20:114'];
    final now = DateTime.now();
    final day =
        DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
    final verse = repository.byKey[keys[day % keys.length]]!;
    final name = repository.surah(verse.surah).name;
    return QCard(
      color: AppPalette.of(context).dark
          ? AppPalette.of(context).notice
          : const Color(0xFFFFF8E9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_outlined, color: qGold, size: 21),
              const SizedBox(width: 8),
              Text(
                'آية اليوم',
                style: qText(context, size: 17, weight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            verse.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'AmiriQuran',
              fontSize: 22,
              height: 1.65,
              color: AppPalette.of(context).heading,
            ),
          ),
          Text(
            'سورة $name • الآية ${verse.ayah}',
            style: qText(
              context,
              size: 10,
              color: AppPalette.of(context).muted,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => onExplain(verse),
                  icon: const Icon(Icons.menu_book_outlined, size: 17),
                  label: Text(
                    'قراءة التفسير',
                    style: qText(context, size: 11, color: qTeal),
                  ),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    final box = context.findRenderObject() as RenderBox?;
                    SharePlus.instance.share(
                      ShareParams(
                        text: '${verse.text}\n[سورة $name: ${verse.ayah}]',
                        sharePositionOrigin: box == null
                            ? null
                            : box.localToGlobal(Offset.zero) & box.size,
                      ),
                    );
                  },
                  icon: const Icon(Icons.share_outlined, size: 17),
                  label: Text(
                    'مشاركة الآية',
                    style: qText(context, size: 11, color: qTeal),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
