import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app_appearance.dart';
import '../../../app_experience.dart';
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
    this.floating = false,
    this.collapsed = false,
    this.onToggleCollapsed,
    this.onMinimize,
    this.onClose,
  });
  final QuranMedia media;
  final QuranRepository repository;
  final bool compact;
  final VoidCallback? onReciter, onOpen, onStart;
  final String? initialTitle;
  final bool floating, collapsed;
  final VoidCallback? onToggleCollapsed, onMinimize, onClose;

  @override
  Widget build(BuildContext context) {
    final experience = AppExperienceScope.maybeOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([media, experience]),
      builder: (context, _) {
        if (!floating && experience?.isDocked(media) == true) {
          return const SizedBox.shrink();
        }
        final track = media.current;
        if (compact &&
            track == null &&
            onStart == null &&
            !media.loading &&
            media.error == null) {
          return const SizedBox();
        }
        return QCard(
          padding: EdgeInsets.all(compact ? 8 : 15),
          child: compact ? _compact(context) : _full(context),
        );
      },
    );
  }

  VoidCallback? _minimize(BuildContext context) {
    if (onMinimize != null) return onMinimize;
    final experience = AppExperienceScope.maybeOf(context);
    return experience != null && (media.current != null || media.loading)
        ? () => experience.minimize(media)
        : null;
  }

  String get _reciter =>
      media.current?.reciter ??
      (media.catalog == null
          ? 'حفص عن عاصم'
          : media.selection(verse: compact && onStart != null).name);

  Widget _compact(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (floating || _minimize(context) != null)
        Row(
          children: [
            IconButton(
              tooltip: onToggleCollapsed == null
                  ? 'تصغير المشغل'
                  : collapsed
                  ? 'توسيع المشغل'
                  : 'طي المشغل',
              icon: Icon(
                collapsed ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              ),
              onPressed: onToggleCollapsed ?? _minimize(context),
            ),
            Expanded(
              child: InkWell(
                onTap:
                    onOpen ?? AppExperienceScope.maybeOf(context)?.openPlayer,
                child: Text(
                  media.current?.title ?? initialTitle ?? 'جارٍ تحميل التلاوة…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: qText(context, size: 12, weight: FontWeight.w800),
                ),
              ),
            ),
            if (collapsed) _playButton(size: 32),
            if (onClose != null)
              IconButton(
                tooltip: 'إغلاق المشغل وإيقاف الصوت',
                icon: const Icon(Icons.close, size: 20),
                onPressed: onClose,
              ),
          ],
        ),
      if (!collapsed) ...[
        SizedBox(
          height: 26,
          child: Row(
            children: [
              _AudioPortrait(name: _reciter, size: 26),
              const SizedBox(width: 7),
              Expanded(
                child: InkWell(
                  onTap: onReciter,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _reciter,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: qText(
                              context,
                              size: 10.5,
                              weight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (onReciter != null)
                          const Icon(Icons.expand_more, size: 16, color: qNavy),
                      ],
                    ),
                  ),
                ),
              ),
              _smallButton(
                Icons.timer_outlined,
                !media.sleepTimerActive ? 'مؤقت إيقاف' : 'المؤقت مفعّل',
                () => chooseAudioTimer(context, media),
                active: media.sleepTimerActive,
              ),
              SizedBox(
                width: 37,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 26),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => chooseAudioSpeed(context, media),
                  child: Text(
                    '${media.speed.toStringAsFixed(1)}x',
                    textDirection: TextDirection.ltr,
                    style: qText(context, size: 10.5, weight: FontWeight.w800),
                  ),
                ),
              ),
              SizedBox(
                width: 26,
                child: PopupMenuButton<String>(
                  tooltip: 'قائمة التشغيل وخيارات التلاوة',
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.playlist_play, size: 23, color: qNavy),
                  onSelected: (value) {
                    if (value == 'queue') _showQueue(context);
                    if (value == 'open') onOpen?.call();
                    if (value == 'stop') unawaited(media.stop());
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'queue',
                      child: Text('قائمة التشغيل'),
                    ),
                    if (onOpen != null)
                      const PopupMenuItem(
                        value: 'open',
                        child: Text('فتح المشغل'),
                      ),
                    PopupMenuItem(
                      value: 'stop',
                      enabled: media.current != null || media.loading,
                      child: const Text('إيقاف التلاوة'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 20, child: _timeline(context, small: true)),
        SizedBox(
          height: 36,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: [
                _timeLabel(context, media.position),
                const Spacer(),
                _smallButton(
                  Icons.skip_previous,
                  'التلاوة السابقة',
                  media.handler?.player.hasPrevious == true
                      ? () => media.skip(-1)
                      : null,
                  size: 30,
                ),
                const SizedBox(width: 8),
                _playButton(size: 36),
                const SizedBox(width: 8),
                _smallButton(
                  Icons.skip_next,
                  'التلاوة التالية',
                  media.handler?.player.hasNext == true
                      ? () => media.skip(1)
                      : null,
                  size: 30,
                ),
                const Spacer(),
                _smallButton(
                  Icons.repeat,
                  'التكرار',
                  () => chooseAudioRepeat(context, media),
                  active: media.repeat != AudioServiceRepeatMode.none,
                ),
                _timeLabel(context, media.duration),
              ],
            ),
          ),
        ),
        if (media.error != null) _error(context),
      ],
    ],
  );

  Widget _full(BuildContext context) {
    final track = media.current;
    final isQuran =
        track != null &&
        (track.recitation.startsWith('mp3quran:') ||
            track.recitation.startsWith('everyayah:') ||
            track.recitation.startsWith('qurancom:'));
    final verse = !isQuran
        ? null
        : repository.byKey['${track.surah}:${track.ayah ?? 1}'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onOpen,
          child: Row(
            children: [
              _AudioPortrait(name: _reciter, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track?.title ?? initialTitle ?? 'اختر سورة للاستماع',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: qText(context, size: 18, weight: FontWeight.w800),
                    ),
                    InkWell(
                      onTap: onReciter,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _reciter,
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
              if (_minimize(context) != null)
                IconButton(
                  tooltip: 'تصغير المشغل',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: _minimize(context),
                ),
            ],
          ),
        ),
        if (verse != null) ...[
          const SizedBox(height: 14),
          Text(
            verse.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'AmiriQuran',
              fontSize: 22,
              height: 1.8,
              color: AppPalette.of(context).heading,
            ),
          ),
          Text(
            track?.ayah == null ? 'مطلع السورة' : 'الآية ${track!.ayah}',
            style: qText(
              context,
              size: 10,
              color: AppPalette.of(context).muted,
            ),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(height: 24, child: _timeline(context)),
        Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                audioTime(media.position),
                style: qText(context, size: 10, color: qTeal),
              ),
              Text(
                audioTime(media.duration),
                style: qText(context, size: 10, color: qTeal),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: _smallButton(
                  Icons.repeat,
                  'التكرار',
                  () => chooseAudioRepeat(context, media),
                  active: media.repeat != AudioServiceRepeatMode.none,
                ),
              ),
              Expanded(
                child: _smallButton(
                  Icons.replay_10,
                  'إرجاع 10 ثوانٍ',
                  () =>
                      media.seek(media.position - const Duration(seconds: 10)),
                ),
              ),
              Expanded(
                child: _smallButton(
                  Icons.skip_previous,
                  'التلاوة السابقة',
                  media.handler?.player.hasPrevious == true
                      ? () => media.skip(-1)
                      : null,
                ),
              ),
              _playButton(size: 52),
              Expanded(
                child: _smallButton(
                  Icons.skip_next,
                  'التلاوة التالية',
                  media.handler?.player.hasNext == true
                      ? () => media.skip(1)
                      : null,
                ),
              ),
              Expanded(
                child: _smallButton(
                  Icons.forward_10,
                  'تقديم 10 ثوانٍ',
                  () =>
                      media.seek(media.position + const Duration(seconds: 10)),
                ),
              ),
            ],
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => chooseAudioSpeed(context, media),
              icon: const Icon(Icons.speed, size: 17),
              label: Text(
                '${media.speed.toStringAsFixed(2)}x',
                style: qText(context, size: 11, color: qTeal),
              ),
            ),
            TextButton.icon(
              onPressed: () => chooseAudioTimer(context, media),
              icon: const Icon(Icons.timer_outlined, size: 17),
              label: Text(
                !media.sleepTimerActive ? 'مؤقت إيقاف' : 'المؤقت مفعّل',
                style: qText(context, size: 11, color: qTeal),
              ),
            ),
          ],
        ),
        if (media.error != null) _error(context),
      ],
    );
  }

  Widget _timeline(BuildContext context, {bool small = false}) {
    final max = media.duration?.inMilliseconds.toDouble() ?? 0;
    return Stack(
      alignment: Alignment.center,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: small ? 3 : 4,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: small ? 4 : 6,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Slider(
              key: floating ? const ValueKey('app-playback-seek') : null,
              value: max > 0
                  ? media.position.inMilliseconds.toDouble().clamp(0, max)
                  : 0,
              max: max > 0 ? max : 1,
              activeColor: qTeal,
              inactiveColor: AppPalette.of(context).border,
              onChanged: max > 0
                  ? (value) => media.seek(Duration(milliseconds: value.round()))
                  : null,
            ),
          ),
        ),
        if (media.buffering)
          const IgnorePointer(
            child: LinearProgressIndicator(color: qTeal, minHeight: 2),
          ),
      ],
    );
  }

  Widget _playButton({required double size}) => Tooltip(
    message: media.playing ? 'إيقاف مؤقت' : 'تشغيل',
    child: Material(
      color: qTeal,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: media.buffering
            ? null
            : media.current == null
            ? onStart
            : media.toggle,
        child: SizedBox.square(
          dimension: size,
          child: media.buffering
              ? Padding(
                  padding: EdgeInsets.all(size * .27),
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  media.playing ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: size * .59,
                ),
        ),
      ),
    ),
  );

  Widget _smallButton(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    bool active = false,
    double size = 26,
  }) => SizedBox.square(
    dimension: size,
    child: IconButton(
      tooltip: label,
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tight(Size.square(size)),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Transform.flip(
        flipX: icon == Icons.skip_previous || icon == Icons.skip_next,
        child: Icon(
          icon,
          color: onTap == null
              ? null
              : active
              ? qTeal
              : qNavy,
          size: 21,
        ),
      ),
    ),
  );

  Widget _timeLabel(BuildContext context, Duration? time) => SizedBox(
    width: 37,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        audioTime(time),
        style: qText(context, size: 9.5, color: qTeal),
      ),
    ),
  );

  Widget _error(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      media.error!,
      style: qText(context, size: 11, color: AppPalette.of(context).muted),
      textAlign: TextAlign.center,
    ),
  );

  Future<void> _showQueue(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'قائمة التشغيل',
              style: qText(context, size: 18, weight: FontWeight.w800),
            ),
          ),
          if (media.playingTracks.isEmpty)
            const ListTile(title: Text('لم تبدأ تلاوة بعد')),
          for (var i = 0; i < media.playingTracks.length; i++)
            ListTile(
              title: Text(media.playingTracks[i].title),
              subtitle: Text(media.playingTracks[i].reciter),
              trailing: media.handler?.playbackState.value.queueIndex == i
                  ? const Icon(Icons.check_circle, color: qTeal)
                  : null,
              onTap: media.handler == null
                  ? null
                  : () {
                      unawaited(media.handler!.skipToQueueItem(i));
                      Navigator.pop(context);
                    },
            ),
        ],
      ),
    ),
  );
}

class _AudioPortrait extends StatelessWidget {
  const _AudioPortrait({required this.name, required this.size});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final portrait = reciterPortrait(name);
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppPalette.of(context).paleTeal,
      child: portrait == null
          ? Icon(Icons.headphones, color: qTeal, size: size * .6)
          : ClipOval(
              child: Image.network(
                portrait,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) =>
                    Icon(Icons.headphones, color: qTeal, size: size * .6),
              ),
            ),
    );
  }
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
        child: StatefulBuilder(
          builder: (context, update) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'مؤقت إيقاف التلاوة',
                  style: qText(context, size: 18, weight: FontWeight.w800),
                ),
                SwitchListTile(
                  title: const Text('تلاشي الصوت في آخر 5 ثوانٍ'),
                  value: media.fadeTimer,
                  onChanged: (value) {
                    media.setTimerFade(value);
                    update(() {});
                  },
                ),
                ListTile(
                  title: const Text('إلغاء المؤقت'),
                  onTap: () {
                    media.setTimer(null);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  title: Text(
                    media.current?.surah == 0
                        ? 'بعد التسجيل الحالي'
                        : 'بعد السورة الحالية',
                  ),
                  subtitle: const Text(
                    'حتى نهاية السورة أو النطاق المحمّل؛ يلغي التكرار الحالي',
                  ),
                  enabled: media.ownsPlayback && media.current != null,
                  onTap: () {
                    media.setTimerAfterSurah();
                    Navigator.pop(context);
                  },
                ),
                for (final minutes in [5, 10, 15, 20, 30, 60])
                  ListTile(
                    title: Text('بعد $minutes دقيقة'),
                    enabled: media.ownsPlayback,
                    onTap: () {
                      media.setTimer(Duration(minutes: minutes));
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
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
