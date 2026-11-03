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
              QuranSleepTimerButton(media: media),
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

class QuranPlayerDismissGesture extends StatefulWidget {
  const QuranPlayerDismissGesture({
    super.key,
    required this.child,
    this.onHide,
  });
  final Widget child;
  final ValueChanged<bool>? onHide;
  @override
  State<QuranPlayerDismissGesture> createState() =>
      _QuranPlayerDismissGestureState();
}

class _QuranPlayerDismissGestureState extends State<QuranPlayerDismissGesture> {
  double drag = 0;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onHorizontalDragStart: widget.onHide == null ? null : (_) => drag = 0,
    onHorizontalDragUpdate: widget.onHide == null
        ? null
        : (details) => drag += details.delta.dx,
    onHorizontalDragEnd: widget.onHide == null
        ? null
        : (_) {
            if (drag.abs() > 48) widget.onHide!(drag < 0);
          },
    child: widget.child,
  );
}

class QuranPlaybackBubble extends StatelessWidget {
  const QuranPlaybackBubble({
    super.key,
    required this.media,
    required this.onOpen,
  });
  final QuranMedia media;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: media,
    builder: (context, _) => Material(
      key: const ValueKey('quran-player-bubble'),
      elevation: 4,
      color: AppPalette.of(context).surface,
      shape: CircleBorder(
        side: BorderSide(color: qAccent(context).withValues(alpha: .4)),
      ),
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 54, height: 54),
        tooltip: context.tr('quran.restorePlayer'),
        onPressed: onOpen,
        icon: Icon(
          media.playing ? Icons.graphic_eq : Icons.pause,
          color: qAccent(context),
        ),
      ),
    ),
  );
}

class QuranSleepTimerButton extends StatefulWidget {
  const QuranSleepTimerButton({super.key, required this.media});
  final QuranMedia media;
  @override
  State<QuranSleepTimerButton> createState() => _QuranSleepTimerButtonState();
}

class _QuranSleepTimerButtonState extends State<QuranSleepTimerButton> {
  Timer? ticker;
  DateTime? deadline;
  @override
  void initState() {
    super.initState();
    widget.media.addListener(changed);
    syncTicker();
  }

  void syncTicker() {
    if (deadline == widget.media.stopAt) return;
    deadline = widget.media.stopAt;
    ticker?.cancel();
    if (deadline != null) {
      ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  void changed() {
    syncTicker();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant QuranSleepTimerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media != widget.media) {
      oldWidget.media.removeListener(changed);
      widget.media.addListener(changed);
      syncTicker();
    }
  }

  @override
  void dispose() {
    ticker?.cancel();
    widget.media.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.media.stopAt?.difference(DateTime.now());
    return TextButton(
      key: const ValueKey('quran-sleep-timer'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        minimumSize: const Size(34, 40),
        foregroundColor: qAccent(context),
      ),
      onPressed: () => chooseAudioTimer(context, widget.media),
      child: Tooltip(
        message: context.tr('quran.sleepTimer'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.media.sleepTimerActive
                  ? Icons.bedtime
                  : Icons.bedtime_outlined,
              size: 20,
            ),
            if (remaining != null) ...[
              const SizedBox(width: 3),
              Text(
                audioTime(
                  remaining.isNegative ? Duration.zero : remaining,
                  formats: LocalizationScope.maybeOf(context)?.formats,
                ),
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> chooseAudioTimer(BuildContext context, QuranMedia media) {
  const durations = [5, 10, 15, 20, 30, 60];
  final remaining = media.stopAt?.difference(DateTime.now()).inSeconds;
  int? choice = media.stoppingAfterSurah
      ? 0
      : remaining == null
      ? null
      : durations.firstWhere(
          (minutes) => minutes * 60 >= remaining,
          orElse: () => 60,
        );
  var fade = media.fadeTimer;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppPalette.of(context).surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: StatefulBuilder(
        builder: (context, update) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr('quran.sleepAfter'),
                  style: qText(context, size: 19, weight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        RadioGroup<int>(
                          groupValue: choice,
                          onChanged: (value) => update(() => choice = value),
                          child: Column(
                            children: [
                              for (final minutes in durations)
                                RadioListTile<int>(
                                  key: ValueKey('quran-timer-minutes-$minutes'),
                                  value: minutes,
                                  title: Text(
                                    context.tr(
                                      'quran.audioSleepMinutes',
                                      args: {
                                        'minutes': quranNumber(
                                          context,
                                          minutes,
                                        ),
                                      },
                                    ),
                                  ),
                                ),
                              RadioListTile<int>(
                                key: const ValueKey('quran-timer-after-surah'),
                                value: 0,
                                title: Text(
                                  media.current?.surah == 0
                                      ? context.quranLabel('بعد التسجيل الحالي')
                                      : context.quranLabel(
                                          'بعد السورة الحالية',
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(),
                        SwitchListTile(
                          title: Text(
                            context.quranLabel('تلاشي الصوت في آخر 5 ثوانٍ'),
                          ),
                          value: fade,
                          onChanged: (value) => update(() => fade = value),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('quran-timer-cancel'),
                        onPressed: !media.sleepTimerActive
                            ? null
                            : () {
                                media.setTimer(null);
                                Navigator.pop(context);
                              },
                        child: Text(context.quranLabel('إلغاء المؤقت')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('quran-timer-apply'),
                        onPressed:
                            choice == null ||
                                !media.ownsPlayback ||
                                media.current == null
                            ? null
                            : () {
                                media.setTimerFade(fade);
                                if (choice == 0) {
                                  media.setTimerAfterSurah();
                                } else {
                                  media.setTimer(Duration(minutes: choice!));
                                }
                                Navigator.pop(context);
                              },
                        child: Text(context.tr('quran.setTimer')),
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
  );
}

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
