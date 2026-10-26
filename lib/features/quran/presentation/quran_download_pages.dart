import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_appearance.dart';
import '../../../app_loading.dart';
import '../data/quran_audio.dart';
import '../data/quran_audio_models.dart';
import '../data/quran_controller.dart';
import '../data/quran_downloads.dart';
import '../data/quran_repository.dart';
import 'quran_audio_pages.dart';
import 'quran_audio_widgets.dart';
import 'quran_widgets.dart';

String downloadLabel(QuranDownloadState state) => switch (state) {
  QuranDownloadState.queued => 'في الانتظار',
  QuranDownloadState.downloading => 'جارٍ التحميل',
  QuranDownloadState.paused => 'التحميل متوقف',
  QuranDownloadState.failed => 'فشل التنزيل',
  QuranDownloadState.complete => 'تم التحميل',
};

Future<void> confirmAudioDelete(
  BuildContext context,
  QuranMedia media,
  List<QuranDownload> entries,
) async {
  if (entries.isEmpty) return;
  final size = entries.fold<int>(0, (sum, entry) => sum + entry.received);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: AppPalette.of(context).surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 29,
                backgroundColor: Color(0xFFFFECEB),
                child: Icon(
                  Icons.delete_outline,
                  color: Color(0xFFDC3C3F),
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'حذف التلاوة المحمّلة؟',
                textAlign: TextAlign.center,
                style: qText(context, size: 19, weight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'سيتم حذف الملف من هذا الجهاز وتحرير ${audioBytes(size)}. يمكنك تنزيله مرة أخرى للاستماع دون إنترنت.',
                textAlign: TextAlign.center,
                style: qText(
                  context,
                  size: 12,
                  color: AppPalette.of(context).muted,
                ),
              ),
              const SizedBox(height: 16),
              if (entries.length == 1)
                QCard(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      QMedallion(number: entries.first.track.surah, size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entries.first.track.title,
                              style: qText(
                                context,
                                size: 14,
                                weight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              entries.first.track.reciter,
                              style: qText(
                                context,
                                size: 10,
                                color: AppPalette.of(context).muted,
                              ),
                            ),
                            Text(
                              audioBytes(size),
                              textDirection: TextDirection.ltr,
                              style: qText(context, size: 10, color: qTeal),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.audiotrack_outlined,
                        color: qTeal,
                        size: 24,
                      ),
                    ],
                  ),
                )
              else
                Text(
                  '${entries.length} ملف صوتي',
                  style: qText(context, size: 14),
                ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC3C3F),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  label: Text(
                    'حذف',
                    style: qText(context, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: AppPalette.of(context).neutral,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('إلغاء', style: qText(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (confirmed != true) return;
  try {
    if (entries.any((entry) => entry.track.id == media.current?.id)) {
      await media.stop();
    }
    for (final entry in entries) {
      await media.downloads.remove(entry.track.id);
    }
    if (context.mounted) qNotice(context, 'تم حذف الملفات الصوتية المحددة');
  } catch (_) {
    if (context.mounted) {
      qNotice(context, 'تعذّر حذف بعض الملفات؛ أعد المحاولة');
    }
  }
}

class QuranDownloadPage extends StatefulWidget {
  const QuranDownloadPage({
    super.key,
    required this.controller,
    this.saved = false,
  });
  final QuranController controller;
  final bool saved;
  @override
  State<QuranDownloadPage> createState() => _QuranDownloadPageState();
}

class _QuranDownloadPageState extends State<QuranDownloadPage> {
  late final QuranMedia media = widget.controller.audio;
  late Future<void> request;
  late int tab;
  String query = '';
  int sort = 0;
  @override
  void initState() {
    super.initState();
    tab = widget.saved ? 2 : 0;
    request = media.initialize();
  }

  void _storage() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: AppPalette.of(context).background,
        body: SafeArea(
          bottom: false,
          child: QuranStoragePage(controller: widget.controller),
        ),
      ),
    ),
  );
  void _reader() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: AppPalette.of(context).background,
        body: SafeArea(
          bottom: false,
          child: QuranReciterPicker(media: media, verse: tab == 1),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: request,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: QPrimaryButton(
            label: 'إعادة المحاولة',
            onTap: () => setState(() {
              request = media.initialize();
            }),
          ),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const AppLoadingSkeleton(label: 'جارٍ تحميل التنزيلات');
      }
      return ListenableBuilder(
        listenable: media.downloads,
        builder: (context, _) => ListenableBuilder(
          listenable: media,
          builder: (context, _) {
            final repo = widget.controller.repository!;
            final recitation = media.selection(verse: tab == 1);
            final chapters = repo.surahs
                .where(
                  (chapter) =>
                      recitation.chapters.contains(chapter.id) &&
                      normalizeQuranSearch(
                        chapter.name,
                      ).contains(normalizeQuranSearch(query)),
                )
                .toList();
            final parts = repo.juzs
                .where(
                  (part) => normalizeQuranSearch(
                    juzName(part.id),
                  ).contains(normalizeQuranSearch(query)),
                )
                .toList();
            final saved = media.downloads.entries.values
                .where(
                  (entry) => normalizeQuranSearch(
                    '${entry.track.title} ${entry.track.reciter}',
                  ).contains(normalizeQuranSearch(query)),
                )
                .toList();
            final pending = media.downloads.entries.values
                .where(
                  (entry) =>
                      entry.track.recitation == recitation.id &&
                      (entry.state == QuranDownloadState.queued ||
                          entry.state == QuranDownloadState.downloading),
                )
                .map((entry) => entry.track.id)
                .toList();
            final hasPending = pending.isNotEmpty;
            final hasPaused = media.downloads.entries.values.any(
              (entry) =>
                  entry.track.recitation == recitation.id &&
                  entry.state == QuranDownloadState.paused,
            );
            final hasAnyPending = media.downloads.entries.values.any(
              (entry) =>
                  entry.state == QuranDownloadState.queued ||
                  entry.state == QuranDownloadState.downloading,
            );
            saved.sort(
              (a, b) => switch (sort) {
                1 => a.track.surah.compareTo(b.track.surah),
                2 => a.track.reciter.compareTo(b.track.reciter),
                _ => b.created.compareTo(a.created),
              },
            );
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: QuranHeader(
                    title: tab == 2
                        ? 'إدارة التلاوات المحمّلة'
                        : 'التحميل والاستخدام دون إنترنت',
                    subtitle: tab == 2
                        ? 'استمع للتلاوات التي نزّلتها على جهازك'
                        : 'تنزيل السور أو الأجزاء للاستماع دون إنترنت',
                    height: 164,
                    dark: tab == 2,
                    onBack: () => Navigator.pop(context),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      children: [
                        QSegments(
                          labels: const ['السور', 'الأجزاء', 'المحفوظات'],
                          selected: tab,
                          onSelect: (value) => setState(() => tab = value),
                        ),
                        const SizedBox(height: 12),
                        if (tab != 2)
                          QCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'تحميل سريع',
                                        style: qText(
                                          context,
                                          size: 18,
                                          weight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: hasPending
                                          ? () => media.downloads.pauseAll(
                                              pending,
                                            )
                                          : () => _downloadAll(
                                              chapters,
                                              parts,
                                              recitation,
                                            ),
                                      icon: Icon(
                                        hasPending
                                            ? Icons.pause_circle_outline
                                            : Icons.download_outlined,
                                        size: 19,
                                      ),
                                      label: Text(
                                        hasPending
                                            ? 'إيقاف الكل'
                                            : hasPaused
                                            ? 'استئناف الكل'
                                            : 'تحميل الكل',
                                        style: qText(
                                          context,
                                          size: 12,
                                          color: qTeal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  'اختر قارئًا ثم حدد ${tab == 0 ? 'السور' : 'الأجزاء'} التي تريد تنزيلها',
                                  style: qText(
                                    context,
                                    size: 11,
                                    color: AppPalette.of(context).muted,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                QCard(
                                  onTap: _reader,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      ReciterAvatar(recitation: recitation),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              recitation.name,
                                              style: qText(context, size: 13),
                                            ),
                                            Text(
                                              recitation.quality ??
                                                  recitation.style,
                                              style: qText(
                                                context,
                                                size: 10,
                                                color: qTeal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.expand_more,
                                        color: qTeal,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'حجم الملف يظهر من التنزيل الفعلي. تنزيل الأجزاء يستخدم ملفات آياتها فقط.',
                                  style: qText(
                                    context,
                                    size: 10,
                                    color: AppPalette.of(context).muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (tab == 2 && hasAnyPending)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: QPrimaryButton(
                              label: 'إيقاف جميع التنزيلات',
                              icon: Icons.pause_circle_outline,
                              onTap: () => media.downloads.pauseAll(),
                            ),
                          ),
                        if (tab == 2)
                          QCard(
                            onTap: _storage,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.storage_outlined,
                                  color: qTeal,
                                  size: 30,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'إدارة المساحة',
                                        style: qText(
                                          context,
                                          size: 16,
                                          weight: FontWeight.w800,
                                        ),
                                      ),
                                      FutureBuilder<int>(
                                        future: media.downloads.diskUsage(),
                                        builder: (context, size) => Text(
                                          size.hasData
                                              ? audioBytes(size.data!)
                                              : 'حساب حجم الملفات...',
                                          style: qText(
                                            context,
                                            size: 12,
                                            color: qTeal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_left, color: qTeal),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        QSearchField(
                          hint: tab == 2
                              ? 'ابحث في التلاوات المحمّلة...'
                              : tab == 1
                              ? 'ابحث في الأجزاء...'
                              : 'ابحث عن سورة...',
                          onChanged: (value) => setState(() => query = value),
                        ),
                        if (tab == 2)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: QSegments(
                              labels: const [
                                'المحمّلة حديثًا',
                                'حسب السور',
                                'حسب القراء',
                              ],
                              selected: sort,
                              onSelect: (value) => setState(() => sort = value),
                            ),
                          ),
                        if (media.downloads.storageError != null)
                          Text(
                            media.downloads.storageError!,
                            style: qText(context, size: 11, color: Colors.red),
                          ),
                      ],
                    ),
                  ),
                ),
                if (tab == 0)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.builder(
                      itemCount: chapters.length,
                      itemBuilder: (context, index) {
                        final chapter = chapters[index];
                        return _trackTile(
                          context,
                          recitation.track(repo, chapter.id),
                        );
                      },
                    ),
                  ),
                if (tab == 1)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.builder(
                      itemCount: parts.length,
                      itemBuilder: (context, index) {
                        final part = parts[index];
                        final tracks = _juzTracks(part, recitation);
                        final completed = tracks
                            .where(
                              (track) =>
                                  media.downloads.entries[track.id]?.state ==
                                  QuranDownloadState.complete,
                            )
                            .length;
                        final pendingTracks = tracks
                            .where(
                              (track) =>
                                  media.downloads.entries[track.id]?.state ==
                                      QuranDownloadState.queued ||
                                  media.downloads.entries[track.id]?.state ==
                                      QuranDownloadState.downloading,
                            )
                            .map((track) => track.id)
                            .toList();
                        final running = pendingTracks.isNotEmpty;
                        Future<void> toggle() => running
                            ? media.downloads.pauseAll(pendingTracks)
                            : media.downloads.enqueueAll(tracks);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: QCard(
                            onTap: toggle,
                            child: Row(
                              children: [
                                QMedallion(
                                  number: part.id,
                                  filled: true,
                                  size: 40,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        juzName(part.id),
                                        style: qText(
                                          context,
                                          size: 16,
                                          weight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        '$completed من ${tracks.length} ملف آية مكتمل',
                                        style: qText(
                                          context,
                                          size: 11,
                                          color: qTeal,
                                        ),
                                      ),
                                      Text(
                                        'من ${part.startKey} إلى ${part.endKey}',
                                        textDirection: TextDirection.ltr,
                                        style: qText(context, size: 10),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: running
                                      ? 'إيقاف تنزيل ${juzName(part.id)}'
                                      : 'تنزيل أو استئناف ${juzName(part.id)}',
                                  onPressed: toggle,
                                  icon: Icon(
                                    running
                                        ? Icons.pause_circle_outline
                                        : completed == tracks.length
                                        ? Icons.check_circle
                                        : Icons.download_outlined,
                                    color: qTeal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                if (tab == 2 && saved.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        'لا توجد تلاوات محمّلة مطابقة',
                        style: qText(context),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                if (tab == 2)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.builder(
                      itemCount: saved.length,
                      itemBuilder: (context, index) =>
                          _trackTile(context, saved[index].track),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 105),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      children: [
                        if (tab == 2 && saved.isNotEmpty)
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () => confirmAudioDelete(
                              context,
                              media,
                              media.downloads.entries.values.toList(),
                            ),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('حذف جميع التلاوات المحمّلة'),
                          ),
                        if (tab != 2)
                          QCard(
                            onTap: () => setState(() => tab = 2),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.settings_outlined,
                                  color: qTeal,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'إدارة التحميلات والمساحة',
                                    style: qText(context, size: 14),
                                  ),
                                ),
                                const Icon(Icons.chevron_left, color: qTeal),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
  Widget _trackTile(BuildContext context, QuranAudioTrack track) {
    final entry = media.downloads.entries[track.id];
    final complete = entry?.state == QuranDownloadState.complete;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: QCard(
        color: complete ? AppPalette.of(context).paleTeal : null,
        padding: const EdgeInsets.all(10),
        onTap: entry == null
            ? () => media.downloads.enqueue(track)
            : () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    backgroundColor: AppPalette.of(context).background,
                    body: SafeArea(
                      bottom: false,
                      child: QuranDownloadDetail(media: media, entry: entry),
                    ),
                  ),
                ),
              ),
        child: Row(
          children: [
            QMedallion(number: track.surah, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: qText(context, size: 14, weight: FontWeight.w800),
                  ),
                  Text(
                    track.reciter,
                    style: qText(
                      context,
                      size: 11,
                      color: AppPalette.of(context).muted,
                    ),
                  ),
                  if (entry != null) ...[
                    Text(
                      '${downloadLabel(entry.state)} • ${audioBytes(entry.received)}${entry.total > 0 ? ' / ${audioBytes(entry.total)}' : ''}',
                      style: qText(
                        context,
                        size: 10,
                        color: entry.state == QuranDownloadState.failed
                            ? Colors.red
                            : qTeal,
                      ),
                    ),
                    if (entry.state == QuranDownloadState.downloading)
                      LinearProgressIndicator(
                        value: entry.total > 0
                            ? (entry.received / entry.total).clamp(0, 1)
                            : null,
                        color: qTeal,
                      ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: complete
                  ? 'استماع دون إنترنت'
                  : entry?.state == QuranDownloadState.downloading ||
                        entry?.state == QuranDownloadState.queued
                  ? 'إيقاف التنزيل'
                  : 'تنزيل أو استئناف',
              onPressed: complete
                  ? () => media.playTracks([track])
                  : entry?.state == QuranDownloadState.downloading ||
                        entry?.state == QuranDownloadState.queued
                  ? () => media.downloads.pause(track.id)
                  : () => media.downloads.enqueue(track),
              icon: Icon(
                complete
                    ? Icons.play_circle_fill
                    : entry?.state == QuranDownloadState.downloading ||
                          entry?.state == QuranDownloadState.queued
                    ? Icons.pause_circle_outline
                    : entry?.state == QuranDownloadState.failed
                    ? Icons.refresh
                    : Icons.download_outlined,
                color: qTeal,
              ),
            ),
            if (entry != null && tab == 2)
              IconButton(
                tooltip: 'حذف التلاوة',
                onPressed: () => confirmAudioDelete(context, media, [entry]),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 23,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<QuranAudioTrack> _juzTracks(QuranJuz part, QuranRecitation recitation) =>
      widget.controller.repository!.verses
          .where((verse) => verse.juz == part.id)
          .map(
            (verse) => recitation.track(
              widget.controller.repository!,
              verse.surah,
              ayah: verse.ayah,
            ),
          )
          .toList();
  Future<void> _downloadAll(
    List<QuranSurah> chapters,
    List<QuranJuz> parts,
    QuranRecitation recitation,
  ) async {
    final tracks = tab == 0
        ? chapters
              .map(
                (chapter) =>
                    recitation.track(widget.controller.repository!, chapter.id),
              )
              .toList()
        : parts.expand((part) => _juzTracks(part, recitation)).toList();
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحميل جميع الملفات المعروضة؟'),
        content: Text(
          '${tracks.length} ملف صوتي للقارئ ${recitation.name}. يُفضّل اتصال Wi-Fi ومساحة كافية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('بدء التحميل'),
          ),
        ],
      ),
    );
    if (yes == true) await media.downloads.enqueueAll(tracks);
  }
}

class QuranDownloadDetail extends StatelessWidget {
  const QuranDownloadDetail({
    super.key,
    required this.media,
    required this.entry,
  });
  final QuranMedia media;
  final QuranDownload entry;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: media.downloads,
    builder: (context, _) => ListView(
      padding: EdgeInsets.zero,
      children: [
        QuranHeader(
          title: 'تنزيل التلاوة',
          subtitle: 'تحميل تلاوات القراء للاستماع دون إنترنت',
          height: 160,
          dark: true,
          onBack: () => Navigator.pop(context),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 105),
          child: QCard(
            child: Column(
              children: [
                Text(
                  entry.track.reciter,
                  style: qText(context, size: 18, weight: FontWeight.w800),
                ),
                Text(
                  entry.track.title,
                  style: qText(
                    context,
                    size: 14,
                    color: AppPalette.of(context).muted,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: entry.state == QuranDownloadState.failed
                        ? const Color(0x10FF0000)
                        : AppPalette.of(context).paleTeal,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        entry.state == QuranDownloadState.failed
                            ? Icons.cloud_off_outlined
                            : entry.state == QuranDownloadState.complete
                            ? Icons.check_circle_outline
                            : Icons.cloud_download_outlined,
                        color: entry.state == QuranDownloadState.failed
                            ? Colors.red
                            : qTeal,
                        size: 58,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        downloadLabel(entry.state),
                        style: qText(
                          context,
                          size: 21,
                          weight: FontWeight.w800,
                          color: entry.state == QuranDownloadState.failed
                              ? Colors.red
                              : qTeal,
                        ),
                      ),
                      if (entry.error != null)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            entry.error!,
                            textAlign: TextAlign.center,
                            style: qText(context, size: 13),
                          ),
                        ),
                      if (entry.state == QuranDownloadState.downloading)
                        LinearProgressIndicator(
                          value: entry.total > 0
                              ? (entry.received / entry.total).clamp(0, 1)
                              : null,
                          color: qTeal,
                        ),
                      const SizedBox(height: 12),
                      Text(
                        '${audioBytes(entry.received)}${entry.total > 0 ? ' / ${audioBytes(entry.total)}' : ''}',
                        style: qText(context, size: 13),
                      ),
                      const SizedBox(height: 16),
                      QPrimaryButton(
                        label: entry.state == QuranDownloadState.complete
                            ? 'استماع دون إنترنت'
                            : entry.state == QuranDownloadState.downloading ||
                                  entry.state == QuranDownloadState.queued
                            ? 'إيقاف التحميل'
                            : 'إعادة المحاولة أو الاستئناف',
                        icon: entry.state == QuranDownloadState.complete
                            ? Icons.play_arrow
                            : Icons.refresh,
                        onTap: () => entry.state == QuranDownloadState.complete
                            ? media.playTracks([entry.track])
                            : entry.state == QuranDownloadState.downloading ||
                                  entry.state == QuranDownloadState.queued
                            ? media.downloads.pause(entry.track.id)
                            : media.downloads.enqueue(entry.track),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await confirmAudioDelete(context, media, [entry]);
                          if (context.mounted &&
                              !media.downloads.entries.containsKey(
                                entry.track.id,
                              )) {
                            Navigator.pop(context);
                          }
                        },
                        icon: const Icon(Icons.close),
                        label: const Text('إلغاء التنزيل أو حذف الملف'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class QuranStoragePage extends StatefulWidget {
  const QuranStoragePage({super.key, required this.controller});
  final QuranController controller;
  @override
  State<QuranStoragePage> createState() => _QuranStoragePageState();
}

class _QuranStoragePageState extends State<QuranStoragePage> {
  late final media = widget.controller.audio;
  final selected = <String>{};
  Map<dynamic, dynamic>? disk;
  @override
  void initState() {
    super.initState();
    _readDisk();
  }

  Future<void> _readDisk() async {
    try {
      final result = await const MethodChannel(
        'com.haqfoundation.haq_app/storage',
      ).invokeMapMethod('diskSpace');
      if (mounted) setState(() => disk = result);
    } catch (_) {
      /* Show exact audio usage without inventing device capacity. */
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: media.downloads,
    builder: (context, _) {
      final entries = media.downloads.entries.values.toList();
      selected.removeWhere((id) => !media.downloads.entries.containsKey(id));
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: QuranHeader(
              title: 'إدارة المساحة',
              subtitle: 'إدارة التلاوات المحمّلة وتحرير المساحة عند الحاجة',
              height: 164,
              dark: true,
              onBack: () => Navigator.pop(context),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  QCard(
                    child: FutureBuilder<int>(
                      future: media.downloads.diskUsage(),
                      builder: (context, snapshot) {
                        final used = snapshot.data ?? 0;
                        final total = (disk?['total'] as num?)?.toInt();
                        final free = (disk?['free'] as num?)?.toInt();
                        return Column(
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.storage_outlined,
                                  color: qTeal,
                                  size: 34,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'مساحة التلاوات على الجهاز',
                                        style: qText(
                                          context,
                                          size: 16,
                                          weight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        snapshot.hasData
                                            ? audioBytes(used)
                                            : 'حساب حجم الملفات...',
                                        style: qText(
                                          context,
                                          size: 18,
                                          color: qTeal,
                                        ),
                                      ),
                                      if (free != null)
                                        Text(
                                          'المتاح على الجهاز: ${audioBytes(free)}',
                                          style: qText(
                                            context,
                                            size: 11,
                                            color: AppPalette.of(context).muted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (total != null && total > 0)
                                  SizedBox(
                                    width: 60,
                                    height: 60,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        CircularProgressIndicator(
                                          value: (used / total).clamp(0, 1),
                                          color: qTeal,
                                          backgroundColor: AppPalette.of(
                                            context,
                                          ).border,
                                          strokeWidth: 6,
                                        ),
                                        Text(
                                          '${(100 * used / total).toStringAsFixed(1)}%',
                                          style: qText(context, size: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            if (total != null && total > 0) ...[
                              const SizedBox(height: 14),
                              LinearProgressIndicator(
                                value: (used / total).clamp(0, 1),
                                color: qTeal,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'من سعة تخزين الجهاز ${audioBytes(total)}',
                                style: qText(context, size: 11),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'التلاوات المحمّلة',
                          style: qText(
                            context,
                            size: 17,
                            weight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(
                          () => selected.length == entries.length
                              ? selected.clear()
                              : selected.addAll(
                                  entries.map((entry) => entry.track.id),
                                ),
                        ),
                        child: Text(
                          selected.length == entries.length &&
                                  entries.isNotEmpty
                              ? 'إلغاء التحديد'
                              : 'تحديد الكل',
                          style: qText(context, size: 12, color: qTeal),
                        ),
                      ),
                    ],
                  ),
                  if (entries.isEmpty)
                    QCard(
                      child: Text(
                        'لا توجد ملفات صوتية محمّلة',
                        style: qText(context),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: QCard(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Checkbox(
                          value: selected.contains(entry.track.id),
                          onChanged: (value) => setState(
                            () => value == true
                                ? selected.add(entry.track.id)
                                : selected.remove(entry.track.id),
                          ),
                        ),
                        QMedallion(number: entry.track.surah, size: 35),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.track.title,
                                style: qText(
                                  context,
                                  size: 14,
                                  weight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                entry.track.reciter,
                                style: qText(
                                  context,
                                  size: 11,
                                  color: AppPalette.of(context).muted,
                                ),
                              ),
                              Text(
                                '${audioBytes(entry.received)} • ${downloadLabel(entry.state)}',
                                style: qText(context, size: 10, color: qTeal),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'حذف التلاوة',
                          onPressed: () async {
                            await confirmAudioDelete(context, media, [entry]);
                            _readDisk();
                          },
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 105),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: entries.isEmpty
                            ? null
                            : () async {
                                await confirmAudioDelete(
                                  context,
                                  media,
                                  entries,
                                );
                                _readDisk();
                              },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('حذف جميع التلاوات'),
                      ),
                      OutlinedButton.icon(
                        onPressed: selected.isEmpty
                            ? null
                            : () async {
                                await confirmAudioDelete(
                                  context,
                                  media,
                                  entries
                                      .where(
                                        (entry) =>
                                            selected.contains(entry.track.id),
                                      )
                                      .toList(),
                                );
                                _readDisk();
                              },
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        label: Text('حذف المحدد (${selected.length})'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
