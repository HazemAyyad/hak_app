import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app_appearance.dart';
import '../data/quran_audio.dart';
import '../data/quran_audio_models.dart';
import '../data/quran_repository.dart';
import 'quran_widgets.dart';

String audioTime(Duration? duration) {
  if (duration == null) return '--:--';
  final seconds = duration.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String audioBytes(int bytes) => bytes >= 1024 * 1024 * 1024
    ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

class QuranPlayerPanel extends StatelessWidget {
  const QuranPlayerPanel({
    super.key,
    required this.media,
    required this.repository,
    this.compact = false,
    this.onReciter,
    this.onOpen,
    this.onStart,
    this.initialTitle,
  });
  final QuranMedia media;
  final QuranRepository repository;
  final bool compact;
  final VoidCallback? onReciter, onOpen;
  final VoidCallback? onStart;
  final String? initialTitle;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: media,
    builder: (context, _) {
      final track = media.current;
      if (compact &&
          track == null &&
          onStart == null &&
          !media.loading &&
          media.error == null) {
        return const SizedBox();
      }
      final duration = media.duration;
      final position = media.position;
      final max = duration?.inMilliseconds.toDouble() ?? 0;
      return QCard(
        padding: EdgeInsets.all(compact ? 9 : 15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onOpen,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: compact ? 16 : 22,
                    backgroundColor: AppPalette.of(context).paleTeal,
                    child:
                        track == null || reciterPortrait(track.reciter) == null
                        ? const Icon(Icons.headphones, color: qTeal)
                        : ClipOval(
                            child: Image.network(
                              reciterPortrait(track.reciter)!,
                              width: 42,
                              height: 42,
                              fit: BoxFit.cover,
                              errorBuilder: (_, error, stack) =>
                                  const Icon(Icons.headphones, color: qTeal),
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track?.title ?? initialTitle ?? 'اختر سورة للاستماع',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: qText(
                            context,
                            size: compact ? 12 : 18,
                            weight: FontWeight.w800,
                          ),
                        ),
                        InkWell(
                          onTap: onReciter,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  track?.reciter ?? 'حفص عن عاصم',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: qText(context, size: 11, color: qTeal),
                                ),
                              ),
                              if (onReciter != null)
                                const Icon(
                                  Icons.expand_more,
                                  color: qTeal,
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (compact)
                    IconButton(
                      tooltip: media.playing ? 'إيقاف مؤقت' : 'تشغيل',
                      onPressed: media.buffering
                          ? null
                          : track == null
                          ? onStart
                          : media.toggle,
                      icon: Icon(
                        media.playing
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                        color: qTeal,
                        size: 34,
                      ),
                    ),
                  if (compact)
                    IconButton(
                      tooltip: 'إيقاف التلاوة',
                      onPressed: media.stop,
                      icon: const Icon(Icons.close, size: 19, color: qNavy),
                    ),
                ],
              ),
            ),
            if (!compact && track?.ayah != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  repository.byKey['${track!.surah}:${track.ayah}']!.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'AmiriQuran',
                    fontSize: 22,
                    height: 1.8,
                    color: AppPalette.of(context).heading,
                  ),
                ),
              ),
            if (media.buffering)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(color: qTeal),
              ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: compact ? 3 : 4,
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: compact ? 5 : 7,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: max > 0
                    ? position.inMilliseconds.toDouble().clamp(0, max)
                    : 0,
                max: max > 0 ? max : 1,
                min: 0,
                activeColor: qTeal,
                onChanged: max > 0
                    ? (value) =>
                          media.seek(Duration(milliseconds: value.round()))
                    : null,
              ),
            ),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    audioTime(position),
                    style: qText(context, size: 10, color: qTeal),
                  ),
                  Text(
                    audioTime(duration),
                    style: qText(context, size: 10, color: qTeal),
                  ),
                ],
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _control(
                    context,
                    Icons.repeat,
                    'التكرار',
                    () => chooseAudioRepeat(context, media),
                    active: media.repeat != AudioServiceRepeatMode.none,
                  ),
                  _control(
                    context,
                    Icons.replay_10,
                    'إرجاع 10 ثوانٍ',
                    () => media.seek(position - const Duration(seconds: 10)),
                  ),
                  IconButton(
                    tooltip: 'التلاوة السابقة',
                    onPressed: media.handler?.player.hasPrevious == true
                        ? () => media.skip(-1)
                        : null,
                    icon: const Icon(Icons.skip_previous, color: qNavy),
                  ),
                  Material(
                    color: qTeal,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: media.playing ? 'إيقاف مؤقت' : 'تشغيل',
                      onPressed: track == null || media.buffering
                          ? null
                          : media.toggle,
                      icon: Icon(
                        media.playing ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'التلاوة التالية',
                    onPressed: media.handler?.player.hasNext == true
                        ? () => media.skip(1)
                        : null,
                    icon: const Icon(Icons.skip_next, color: qNavy),
                  ),
                  _control(
                    context,
                    Icons.forward_10,
                    'تقديم 10 ثوانٍ',
                    () => media.seek(position + const Duration(seconds: 10)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () => chooseAudioSpeed(context, media),
                    icon: const Icon(Icons.speed, size: 18),
                    label: Text(
                      '${media.speed.toStringAsFixed(2)}x',
                      style: qText(context, size: 11, color: qTeal),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => chooseAudioTimer(context, media),
                    icon: const Icon(Icons.timer_outlined, size: 18),
                    label: Text(
                      media.stopAt == null ? 'مؤقت إيقاف' : 'المؤقت مفعّل',
                      style: qText(context, size: 11, color: qTeal),
                    ),
                  ),
                ],
              ),
            ],
            if (compact && MediaQuery.sizeOf(context).height >= 700)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                children: [
                  IconButton(
                    tooltip: 'التلاوة السابقة',
                    onPressed: media.handler?.player.hasPrevious == true
                        ? () => media.skip(-1)
                        : null,
                    icon: const Icon(
                      Icons.skip_previous,
                      size: 20,
                      color: qNavy,
                    ),
                  ),
                  TextButton(
                    onPressed: () => chooseAudioSpeed(context, media),
                    child: Text(
                      '${media.speed.toStringAsFixed(1)}x',
                      style: qText(context, size: 11, color: qTeal),
                    ),
                  ),
                  IconButton(
                    tooltip: 'مؤقت إيقاف',
                    onPressed: () => chooseAudioTimer(context, media),
                    icon: Icon(
                      Icons.timer_outlined,
                      size: 20,
                      color: media.stopAt == null ? qNavy : qTeal,
                    ),
                  ),
                  IconButton(
                    tooltip: 'التكرار',
                    onPressed: () => chooseAudioRepeat(context, media),
                    icon: Icon(
                      Icons.repeat,
                      size: 20,
                      color: media.repeat == AudioServiceRepeatMode.none
                          ? qNavy
                          : qTeal,
                    ),
                  ),
                  IconButton(
                    tooltip: 'التلاوة التالية',
                    onPressed: media.handler?.player.hasNext == true
                        ? () => media.skip(1)
                        : null,
                    icon: const Icon(Icons.skip_next, size: 20, color: qNavy),
                  ),
                ],
              ),
            if (media.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  media.error!,
                  style: qText(
                    context,
                    size: 11,
                    color: AppPalette.of(context).muted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      );
    },
  );
  Widget _control(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) => IconButton(
    tooltip: label,
    onPressed: onTap,
    visualDensity: VisualDensity.compact,
    icon: Icon(icon, color: active ? qTeal : qNavy, size: 23),
  );
}

Future<void> chooseAudioSpeed(BuildContext context, QuranMedia media) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'سرعة التلاوة',
              style: qText(context, size: 18, weight: FontWeight.w800),
            ),
            for (final speed in [.5, .75, 1.0, 1.25, 1.5, 2.0])
              ListTile(
                title: Text('${speed}x'),
                trailing: media.speed == speed
                    ? const Icon(Icons.check, color: qTeal)
                    : null,
                onTap: () {
                  unawaited(media.setSpeed(speed));
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
Future<void> chooseAudioRepeat(BuildContext context, QuranMedia media) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'تكرار التلاوة',
              style: qText(context, size: 18, weight: FontWeight.w800),
            ),
            for (final option in [
              (AudioServiceRepeatMode.none, 'دون تكرار'),
              (AudioServiceRepeatMode.one, 'تكرار التلاوة الحالية'),
              (AudioServiceRepeatMode.all, 'تكرار القائمة أو نطاق الآيات'),
            ])
              ListTile(
                title: Text(option.$2),
                trailing: media.repeat == option.$1
                    ? const Icon(Icons.check, color: qTeal)
                    : null,
                onTap: () {
                  unawaited(media.setRepeat(option.$1));
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
Future<void> chooseAudioTimer(BuildContext context, QuranMedia media) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'مؤقت إيقاف التلاوة',
              style: qText(context, size: 18, weight: FontWeight.w800),
            ),
            ListTile(
              title: const Text('إلغاء المؤقت'),
              onTap: () {
                media.setTimer(null);
                Navigator.pop(context);
              },
            ),
            for (final minutes in [5, 10, 15, 30, 60])
              ListTile(
                title: Text('بعد $minutes دقيقة'),
                onTap: () {
                  media.setTimer(Duration(minutes: minutes));
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );

Future<void> shareAudio(BuildContext context, QuranAudioTrack track) async {
  final box = context.findRenderObject() as RenderBox?;
  try {
    await SharePlus.instance.share(
      ShareParams(
        text: '${track.title}\n${track.reciter}\n${track.url}',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  } catch (_) {
    if (context.mounted) qNotice(context, 'تعذّرت المشاركة');
  }
}

Future<void> chooseVerseRange(
  BuildContext context,
  QuranMedia media,
  QuranVerse verse,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) {
    var first = verse.ayah, last = verse.ayah, repeats = 1;
    return StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'استماع وتكرار نطاق آيات',
                  style: qText(context, size: 18, weight: FontWeight.w800),
                ),
                Text(
                  'سورة ${media.repository().surah(verse.surah).name}',
                  style: qText(context, size: 12),
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: first,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'من الآية',
                        ),
                        items: List.generate(
                          media.repository().surah(verse.surah).ayahCount,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text('${i + 1}'),
                          ),
                        ),
                        onChanged: (value) => setState(() {
                          first = value!;
                          if (last < first) last = first;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey(first),
                        initialValue: last,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'إلى الآية',
                        ),
                        items: List.generate(
                          media.repository().surah(verse.surah).ayahCount -
                              first +
                              1,
                          (i) => DropdownMenuItem(
                            value: first + i,
                            child: Text('${first + i}'),
                          ),
                        ),
                        onChanged: (value) => setState(() => last = value!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: repeats,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'عدد مرات تكرار النطاق',
                  ),
                  items: List.generate(
                    10,
                    (i) =>
                        DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                  ),
                  onChanged: (value) => repeats = value!,
                ),
                const SizedBox(height: 18),
                QPrimaryButton(
                  label: 'بدء الاستماع',
                  icon: Icons.play_arrow,
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(
                      media.playVerse(
                        media.repository().byKey['${verse.surah}:$first']!,
                        endAyah: last,
                        repeats: repeats,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  },
);
