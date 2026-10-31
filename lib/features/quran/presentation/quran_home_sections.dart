import '../../../core/localization/ui_text.dart';
import 'package:flutter/material.dart';
import '../../sharing/share_card.dart';

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
      color: qAccentFill(context),
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
              child: ColoredBox(
                color: qAccentFill(context).withValues(alpha: .72),
              ),
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
                          context.quranLabel('التلاوة الصوتية'),
                          style: qText(
                            context,
                            size: 18,
                            weight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          context.quranLabel(
                            'استمع إلى القرآن الكريم بصوت قارئك المفضل',
                          ),
                          style: qText(context, size: 11, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.quranLabel('اختر القارئ  ‹'),
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
                context.quranLabel('آية اليوم'),
                style: qText(context, size: 17, weight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            verse.text,
            textDirection: TextDirection.rtl,
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
            quranVerseTitle(context, repository.surah(verse.surah), verse.ayah),
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
                    context.quranLabel('قراءة التفسير'),
                    style: qText(context, size: 11, color: qAccent(context)),
                  ),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => chooseContentShare(
                    context,
                    ShareCardContent.quran(repository, [verse.key]),
                    repository: repository,
                  ),
                  icon: const Icon(Icons.share_outlined, size: 17),
                  label: Text(
                    context.quranLabel('مشاركة الآية'),
                    style: qText(context, size: 11, color: qAccent(context)),
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
