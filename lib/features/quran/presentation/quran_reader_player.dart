import '../../../core/localization/app_localization.dart';
import '../../../core/localization/ui_text.dart';
import 'package:flutter/material.dart';

import '../../../app_appearance.dart';
import '../../../app_experience.dart';
import '../data/quran_audio.dart';
import '../data/quran_repository.dart';
import 'quran_audio_widgets.dart';
import 'quran_widgets.dart';

/// Reading location is independent from the user's explicit audio selection.
class QuranReaderPlayer extends StatelessWidget {
  const QuranReaderPlayer({
    super.key,
    required this.media,
    required this.repository,
    required this.surah,
    required this.selected,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onReciter,
  });
  final QuranMedia media;
  final QuranRepository repository;
  final int surah;
  final QuranVerse? selected;
  final bool expanded;
  final VoidCallback onToggleExpanded, onReciter;

  bool get matches {
    final track = media.current;
    if (track == null || track.surah != surah) return false;
    return selected == null
        ? track.ayah == null
        : track.ayah == selected!.ayah &&
              track.recitation.startsWith('everyayah:');
  }

  Future<void> toggle() async {
    if (matches) {
      await media.toggle();
    } else if (selected case final verse?) {
      await media.playVerse(verse);
    } else {
      await media.playChapter(surah);
    }
  }

  @override
  Widget build(BuildContext context) {
    final experience = AppExperienceScope.maybeOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([media, experience]),
      builder: (context, _) {
        if (experience?.isDocked(media) == true) return const SizedBox.shrink();
        final palette = AppPalette.of(context);
        final name = repository.surah(surah).localizedName(context);
        final title = selected == null
            ? context.tr('quran.fullSurahTitle', args: {'name': name})
            : quranVerseTitle(context, repository.surah(surah), selected!.ayah);
        final reciter = matches
            ? media.current!.reciter
            : media.catalog == null
            ? context.quranLabel('اختيار القارئ')
            : media.selection(verse: selected != null).name;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const ValueKey('quran-reader-player'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: palette.dark ? palette.surface : const Color(0xFFF4F8F6),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: palette.dark
                      ? palette.border
                      : const Color(0xFFDDE9E3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.headphones_rounded,
                    color: qAccent(context),
                    size: 25,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: qText(
                            context,
                            size: 13,
                            weight: FontWeight.w800,
                          ),
                        ),
                        InkWell(
                          onTap: onReciter,
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  reciter,
                                  textDirection: contentTextDirection(reciter),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: qText(
                                    context,
                                    size: 10,
                                    color: palette.muted,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.keyboard_arrow_down,
                                color: palette.muted,
                                size: 15,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onToggleExpanded,
                    tooltip: expanded
                        ? context.quranLabel('طي المشغل')
                        : context.quranLabel('توسيع المشغل'),
                    icon: Icon(
                      expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: qAccentFill(context),
                    shape: const CircleBorder(),
                    child: IconButton(
                      key: const ValueKey('quran-reader-play'),
                      onPressed: media.buffering ? null : toggle,
                      tooltip: matches && media.playing
                          ? context.quranLabel('إيقاف مؤقت')
                          : selected == null
                          ? context.quranLabel('تشغيل السورة كاملة')
                          : context.quranLabel('تشغيل الآية المحددة'),
                      icon: media.buffering
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              matches && media.playing
                                  ? Icons.pause
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 29,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (expanded)
              QuranPlayerPanel(
                media: media,
                repository: repository,
                compact: true,
                verseReciter: selected != null,
                initialTitle: title,
                onReciter: onReciter,
                onStart: toggle,
                onPlay: toggle,
              ),
            if (!expanded && media.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  media.error!,
                  textAlign: TextAlign.center,
                  style: qText(context, size: 11, color: palette.muted),
                ),
              ),
          ],
        );
      },
    );
  }
}
