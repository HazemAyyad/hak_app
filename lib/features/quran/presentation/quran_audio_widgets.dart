import '../../../core/localization/app_localization.dart';
import '../../../core/localization/ui_text.dart';
import '../../../core/localization/locale_formats.dart';
import '../../../core/localization/interface_messages.dart';
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../../sharing/share_card.dart';

import '../../../app_appearance.dart';
import '../../../app_experience.dart';
import '../data/quran_audio.dart';
import '../data/quran_audio_models.dart';
import '../data/quran_audio_labels.dart';
import '../data/quran_repository.dart';
import 'quran_widgets.dart';

String audioTime(Duration? duration, {LocaleFormats? formats}) {
  if (duration == null) return '--:--';
  final seconds = duration.inSeconds;
  return formats == null
      ? '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
      : '${formats.integer(seconds ~/ 60)}:${formats.integer(seconds % 60).padLeft(2, formats.integer(0))}';
}

String audioBytes(int bytes, {LocaleFormats? formats}) {
  final gigabytes = bytes >= 1024 * 1024 * 1024;
  final value = (bytes / (gigabytes ? 1024 * 1024 * 1024 : 1024 * 1024))
      .toStringAsFixed(gigabytes ? 2 : 1);
  return '${formats?.number(double.parse(value)) ?? value} ${gigabytes ? 'GB' : 'MB'}';
}

extension QuranRecitationInterfaceLabels on QuranRecitation {
  String localizedName(BuildContext context) =>
      context.tr('quran.recitation.$id.name', fallback: name);
  String localizedStyle(BuildContext context) =>
      context.tr('quran.recitation.$id.style', fallback: style);
}

extension QuranTrackInterfaceLabels on QuranAudioTrack {
  String localizedTitle(BuildContext context, QuranRepository repository) =>
      audioTrackLabel(
        this,
        repository,
        LocalizationScope.maybeOf(context)?.messages ??
            InterfaceMessages.bundled('ar'),
      );
  String localizedReciter(BuildContext context) =>
      context.tr('quran.recitation.$recitation.name', fallback: reciter);
}

class QuranPlayerPanel extends StatelessWidget {
  const QuranPlayerPanel({
    super.key,
    required this.media,
    required this.repository,
    this.compact = false,
    this.onReciter,
    this.onOpen,
    this.onStart,
    this.onPlay,
    this.verseReciter,
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
  final VoidCallback? onPlay;
  final bool? verseReciter;
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

  String _reciter(BuildContext context) =>
      media.current?.localizedReciter(context) ??
      (media.catalog == null
          ? context.quranLabel('حفص عن عاصم')
          : media
                .selection(verse: verseReciter ?? (compact && onStart != null))
                .localizedName(context));

  String get _reciterSource =>
      media.current?.reciter ??
      (media.catalog == null
          ? ''
          : media
                .selection(verse: verseReciter ?? (compact && onStart != null))
                .name);

  Widget _compact(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (floating || _minimize(context) != null)
        Row(
          children: [
            IconButton(
              tooltip: onToggleCollapsed == null
                  ? context.quranLabel('تصغير المشغل')
                  : collapsed
                  ? context.quranLabel('توسيع المشغل')
                  : context.quranLabel('طي المشغل'),
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
                  media.current?.localizedTitle(context, repository) ??
                      initialTitle ??
                      context.quranLabel('جارٍ تحميل التلاوة…'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: qText(context, size: 12, weight: FontWeight.w800),
                ),
              ),
            ),
            if (collapsed) _playButton(context, size: 32),
            if (onClose != null)
              IconButton(
                tooltip: context.quranLabel('إغلاق المشغل وإيقاف الصوت'),
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
              _AudioPortrait(name: _reciterSource, size: 26),
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
                            _reciter(context),
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
                context,
                Icons.timer_outlined,
                !media.sleepTimerActive
                    ? context.quranLabel('مؤقت إيقاف')
                    : context.quranLabel('المؤقت مفعّل'),
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
                    '${quranNumber(context, media.speed)}x',
                    textDirection: TextDirection.ltr,
                    style: qText(context, size: 10.5, weight: FontWeight.w800),
                  ),
                ),
              ),
              SizedBox(
                width: 26,
                child: PopupMenuButton<String>(
                  tooltip: context.quranLabel('قائمة التشغيل وخيارات التلاوة'),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.playlist_play, size: 23, color: qNavy),
                  onSelected: (value) {
                    if (value == 'queue') _showQueue(context);
                    if (value == 'open') onOpen?.call();
                    if (value == 'stop') unawaited(media.stop());
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'queue',
                      child: Text(context.quranLabel('قائمة التشغيل')),
                    ),
                    if (onOpen != null)
                      PopupMenuItem(
                        value: 'open',
                        child: Text(context.quranLabel('فتح المشغل')),
                      ),
                    PopupMenuItem(
                      value: 'stop',
                      enabled: media.current != null || media.loading,
                      child: Text(context.quranLabel('إيقاف التلاوة')),
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
                  context,
                  Icons.skip_previous,
                  context.quranLabel('التلاوة السابقة'),
                  media.handler?.player.hasPrevious == true
                      ? () => media.skip(-1)
                      : null,
                  size: 30,
                ),
                const SizedBox(width: 8),
                _playButton(context, size: 36),
                const SizedBox(width: 8),
                _smallButton(
                  context,
                  Icons.skip_next,
                  context.quranLabel('التلاوة التالية'),
                  media.handler?.player.hasNext == true
                      ? () => media.skip(1)
                      : null,
                  size: 30,
                ),
                const Spacer(),
                _smallButton(
                  context,
                  Icons.repeat,
                  context.quranLabel('التكرار'),
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
              _AudioPortrait(name: _reciterSource, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track?.localizedTitle(context, repository) ??
                          initialTitle ??
                          context.quranLabel('اختر سورة للاستماع'),
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
                              _reciter(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: qText(
                                context,
                                size: 11,
                                color: qAccent(context),
                              ),
                            ),
                          ),
                          if (onReciter != null)
                            Icon(
                              Icons.expand_more,
                              color: qAccent(context),
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
                  tooltip: context.quranLabel('تصغير المشغل'),
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
            track?.ayah == null
                ? context.quranLabel('مطلع السورة')
                : context.tr(
                    'quran.verseLabel',
                    args: {'ayah': quranNumber(context, track!.ayah!)},
                  ),
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
                audioTime(media.position, formats: quranFormats(context)),
                style: qText(context, size: 10, color: qAccent(context)),
              ),
              Text(
                audioTime(media.duration, formats: quranFormats(context)),
                style: qText(context, size: 10, color: qAccent(context)),
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
                  context,
                  Icons.repeat,
                  context.quranLabel('التكرار'),
                  () => chooseAudioRepeat(context, media),
                  active: media.repeat != AudioServiceRepeatMode.none,
                ),
              ),
              Expanded(
                child: _smallButton(
                  context,
                  Icons.replay_10,
                  context.quranLabel('إرجاع 10 ثوانٍ'),
                  () =>
                      media.seek(media.position - const Duration(seconds: 10)),
                ),
              ),
              Expanded(
                child: _smallButton(
                  context,
                  Icons.skip_previous,
                  context.quranLabel('التلاوة السابقة'),
                  media.handler?.player.hasPrevious == true
                      ? () => media.skip(-1)
                      : null,
                ),
              ),
              _playButton(context, size: 52),
              Expanded(
                child: _smallButton(
                  context,
                  Icons.skip_next,
                  context.quranLabel('التلاوة التالية'),
                  media.handler?.player.hasNext == true
                      ? () => media.skip(1)
                      : null,
                ),
              ),
              Expanded(
                child: _smallButton(
                  context,
                  Icons.forward_10,
                  context.quranLabel('تقديم 10 ثوانٍ'),
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
                '${quranNumber(context, media.speed)}x',
                style: qText(context, size: 11, color: qAccent(context)),
              ),
            ),
            TextButton.icon(
              onPressed: () => chooseAudioTimer(context, media),
              icon: const Icon(Icons.timer_outlined, size: 17),
              label: Text(
                !media.sleepTimerActive
                    ? context.quranLabel('مؤقت إيقاف')
                    : context.quranLabel('المؤقت مفعّل'),
                style: qText(context, size: 11, color: qAccent(context)),
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
            textDirection: Directionality.of(context),
            child: Slider(
              key: floating ? const ValueKey('app-playback-seek') : null,
              value: max > 0
                  ? media.position.inMilliseconds.toDouble().clamp(0, max)
                  : 0,
              max: max > 0 ? max : 1,
              activeColor: qAccent(context),
              inactiveColor: AppPalette.of(context).border,
              onChanged: max > 0
                  ? (value) => media.seek(Duration(milliseconds: value.round()))
                  : null,
            ),
          ),
        ),
        if (media.buffering)
          IgnorePointer(
            child: LinearProgressIndicator(
              color: qAccent(context),
              minHeight: 2,
            ),
          ),
      ],
    );
  }

  Widget _playButton(BuildContext context, {required double size}) => Tooltip(
    message: media.playing
        ? context.quranLabel('إيقاف مؤقت')
        : context.quranLabel('تشغيل'),
    child: Material(
      color: qAccentFill(context),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: media.buffering
            ? null
            : onPlay ?? (media.current == null ? onStart : media.toggle),
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
    BuildContext context,
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
              ? qAccent(context)
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
        audioTime(time, formats: quranFormats(context)),
        style: qText(context, size: 9.5, color: qAccent(context)),
      ),
    ),
  );

  Widget _error(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      context.quranLabel(media.error!),
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
              context.quranLabel('قائمة التشغيل'),
              style: qText(context, size: 18, weight: FontWeight.w800),
            ),
          ),
          if (media.playingTracks.isEmpty)
            ListTile(title: Text(context.quranLabel('لم تبدأ تلاوة بعد'))),
          for (var i = 0; i < media.playingTracks.length; i++)
            ListTile(
              title: Text(
                media.playingTracks[i].localizedTitle(context, repository),
              ),
              subtitle: Text(media.playingTracks[i].localizedReciter(context)),
              trailing: media.handler?.playbackState.value.queueIndex == i
                  ? Icon(Icons.check_circle, color: qAccent(context))
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
          ? Icon(Icons.headphones, color: qAccent(context), size: size * .6)
          : ClipOval(
              child: Image.network(
                portrait,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => Icon(
                  Icons.headphones,
                  color: qAccent(context),
                  size: size * .6,
                ),
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
              context.quranLabel('سرعة التلاوة'),
              style: qText(context, size: 18, weight: FontWeight.w800),
            ),
            for (final speed in [.5, .75, 1.0, 1.25, 1.5, 2.0])
              ListTile(
                title: Text('${quranNumber(context, speed)}x'),
                trailing: media.speed == speed
                    ? Icon(Icons.check, color: qAccent(context))
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
              context.quranLabel('تكرار التلاوة'),
              style: qText(context, size: 18, weight: FontWeight.w800),
            ),
            for (final option in [
              (AudioServiceRepeatMode.none, context.quranLabel('دون تكرار')),
              (
                AudioServiceRepeatMode.one,
                context.quranLabel('تكرار التلاوة الحالية'),
              ),
              (
                AudioServiceRepeatMode.all,
                context.quranLabel('تكرار القائمة أو نطاق الآيات'),
              ),
            ])
              ListTile(
                title: Text(option.$2),
                trailing: media.repeat == option.$1
                    ? Icon(Icons.check, color: qAccent(context))
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
                  context.quranLabel('مؤقت إيقاف التلاوة'),
                  style: qText(context, size: 18, weight: FontWeight.w800),
                ),
                SwitchListTile(
                  title: Text(context.quranLabel('تلاشي الصوت في آخر 5 ثوانٍ')),
                  value: media.fadeTimer,
                  onChanged: (value) {
                    media.setTimerFade(value);
                    update(() {});
                  },
                ),
                ListTile(
                  title: Text(context.quranLabel('إلغاء المؤقت')),
                  onTap: () {
                    media.setTimer(null);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  title: Text(
                    media.current?.surah == 0
                        ? context.quranLabel('بعد التسجيل الحالي')
                        : context.quranLabel('بعد السورة الحالية'),
                  ),
                  subtitle: Text(
                    context.quranLabel(
                      'حتى نهاية السورة أو النطاق المحمّل؛ يلغي التكرار الحالي',
                    ),
                  ),
                  enabled: media.ownsPlayback && media.current != null,
                  onTap: () {
                    media.setTimerAfterSurah();
                    Navigator.pop(context);
                  },
                ),
                for (final minutes in [5, 10, 15, 20, 30, 60])
                  ListTile(
                    title: Text(
                      context.tr(
                        'quran.audioSleepMinutes',
                        args: {'minutes': quranNumber(context, minutes)},
                      ),
                    ),
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
  await chooseContentShare(
    context,
    ShareCardContent.message('${track.title}\n${track.url}'),
  );
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
                  context.quranLabel('استماع وتكرار نطاق آيات'),
                  style: qText(context, size: 18, weight: FontWeight.w800),
                ),
                Text(
                  media.repository().surah(verse.surah).localizedTitle(context),
                  style: qText(context, size: 12),
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: first,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.quranLabel('من الآية'),
                        ),
                        items: List.generate(
                          media.repository().surah(verse.surah).ayahCount,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text(quranNumber(context, i + 1)),
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
                        decoration: InputDecoration(
                          labelText: context.quranLabel('إلى الآية'),
                        ),
                        items: List.generate(
                          media.repository().surah(verse.surah).ayahCount -
                              first +
                              1,
                          (i) => DropdownMenuItem(
                            value: first + i,
                            child: Text(quranNumber(context, first + i)),
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
                  decoration: InputDecoration(
                    labelText: context.quranLabel('عدد مرات تكرار النطاق'),
                  ),
                  items: List.generate(
                    10,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(quranNumber(context, i + 1)),
                    ),
                  ),
                  onChanged: (value) => repeats = value!,
                ),
                const SizedBox(height: 18),
                QPrimaryButton(
                  label: context.quranLabel('بدء الاستماع'),
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
