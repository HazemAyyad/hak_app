import 'dart:async';
import 'package:flutter/material.dart';

import '../../../app_appearance.dart';
import '../data/quran_audio.dart';
import '../data/quran_audio_models.dart';
import '../data/quran_controller.dart';
import '../data/quran_repository.dart';
import 'quran_audio_widgets.dart';
import 'quran_download_pages.dart';
import 'quran_widgets.dart';

class QuranAudioPage extends StatefulWidget {
  const QuranAudioPage({super.key, required this.controller});
  final QuranController controller;
  @override
  State<QuranAudioPage> createState() => _QuranAudioPageState();
}

class _QuranAudioPageState extends State<QuranAudioPage> {
  late final QuranMedia media = widget.controller.audio;
  late Future<void> request;
  String query = '';
  int? juz;
  bool onlyFavorites = false;
  @override
  void initState() {
    super.initState();
    request = media.initialize();
  }

  void _readers() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: AppPalette.of(context).background,
        body: SafeArea(bottom: false, child: QuranReciterPicker(media: media)),
      ),
    ),
  );
  void _downloads() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: AppPalette.of(context).background,
        body: SafeArea(
          bottom: false,
          child: QuranDownloadPage(controller: widget.controller),
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
            label: 'إعادة تحميل قائمة القراء',
            onTap: () => setState(() => request = media.initialize()),
          ),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator(color: qTeal));
      }
      return ListenableBuilder(
        listenable: media,
        builder: (context, _) {
          final repo = widget.controller.repository!;
          final recitation = media.selection();
          final chapters = repo.surahs
              .where(
                (s) =>
                    recitation.chapters.contains(s.id) &&
                    normalizeQuranSearch(
                      s.name,
                    ).contains(normalizeQuranSearch(query)) &&
                    (juz == null ||
                        repo.surahVerses(s.id).any((v) => v.juz == juz)) &&
                    (!onlyFavorites ||
                        media.favorites.contains(
                          recitation.track(repo, s.id).id,
                        )),
              )
              .toList();
          final spotlight = media.catalog!.recitations
              .where(
                (r) => [
                  'mp3quran:123',
                  'mp3quran:51',
                  'mp3quran:102',
                  'mp3quran:30',
                  'mp3quran:54',
                ].contains(r.id),
              )
              .toList();
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: QuranHeader(
                  title: 'القرآن المسموع',
                  subtitle: 'استمع إلى تلاوات متنوعة وخشوع',
                  height: 145,
                  onBack: () => Navigator.pop(context),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      QuranPlayerPanel(
                        media: media,
                        repository: repo,
                        onReciter: _readers,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _action(
                            context,
                            'مؤقت إيقاف',
                            Icons.timer_outlined,
                            () => chooseAudioTimer(context, media),
                          ),
                          const SizedBox(width: 6),
                          _action(
                            context,
                            'التنزيلات',
                            Icons.cloud_download_outlined,
                            _downloads,
                          ),
                          const SizedBox(width: 6),
                          _action(
                            context,
                            'المفضلة',
                            Icons.favorite_border,
                            () =>
                                setState(() => onlyFavorites = !onlyFavorites),
                            active: onlyFavorites,
                          ),
                          const SizedBox(width: 6),
                          _action(
                            context,
                            'مشاركة',
                            Icons.share_outlined,
                            media.current == null
                                ? null
                                : () => shareAudio(context, media.current!),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      QSectionTitle(
                        'اختر القارئ',
                        action: 'عرض الكل',
                        onAction: _readers,
                      ),
                      SizedBox(
                        height: 116 * MediaQuery.textScalerOf(context).scale(1),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: spotlight.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final entry = spotlight[index];
                            return SizedBox(
                              width: 105,
                              child: QCard(
                                color: entry.id == recitation.id
                                    ? AppPalette.of(context).paleTeal
                                    : null,
                                padding: const EdgeInsets.all(8),
                                onTap: () => _select(entry),
                                child: Column(
                                  children: [
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        ReciterAvatar(recitation: entry),
                                        if (entry.id == recitation.id)
                                          const Positioned(
                                            top: -4,
                                            right: -8,
                                            child: Icon(
                                              Icons.check_circle,
                                              color: qTeal,
                                              size: 16,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      entry.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: qText(
                                        context,
                                        size: 11,
                                        weight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      entry.style,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: qText(
                                        context,
                                        size: 9,
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
                      const SizedBox(height: 14),
                      const QSectionTitle('قائمة السور'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: QSearchField(
                              hint: 'بحث عن سورة...',
                              onChanged: (value) =>
                                  setState(() => query = value),
                            ),
                          ),
                          const SizedBox(width: 8),
                          PopupMenuButton<int>(
                            onSelected: (value) =>
                                setState(() => juz = value == 0 ? null : value),
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 0,
                                child: Text('كل القرآن'),
                              ),
                              for (final part in repo.juzs)
                                PopupMenuItem(
                                  value: part.id,
                                  child: Text(juzName(part.id)),
                                ),
                            ],
                            child: QCard(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  Text(
                                    juz == null ? 'كل القرآن' : juzName(juz!),
                                    style: qText(context, size: 11),
                                  ),
                                  const Icon(
                                    Icons.expand_more,
                                    size: 18,
                                    color: qTeal,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              if (chapters.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'لا توجد سور مطابقة',
                      textAlign: TextAlign.center,
                      style: qText(context),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                sliver: SliverList.builder(
                  itemCount: chapters.length,
                  itemBuilder: (context, index) {
                    final chapter = chapters[index];
                    final track = recitation.track(repo, chapter.id);
                    final current = media.current?.id == track.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: QCard(
                        color: current ? AppPalette.of(context).paleTeal : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        onTap: () => media.playChapter(chapter.id),
                        child: Row(
                          children: [
                            QCircleButton(
                              icon: current && media.playing
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              label: 'استماع إلى سورة ${chapter.name}',
                              color: qTeal,
                              onTap: () => current
                                  ? media.toggle()
                                  : media.playChapter(chapter.id),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'سورة ${chapter.name}',
                                    style: qText(
                                      context,
                                      size: 14,
                                      weight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    '${chapter.ayahCount} آية • الصفحة ${chapter.startPage}',
                                    style: qText(
                                      context,
                                      size: 11,
                                      color: AppPalette.of(context).muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            QMedallion(number: chapter.id, size: 35),
                            PopupMenuButton<String>(
                              tooltip: 'خيارات التلاوة',
                              onSelected: (value) {
                                if (value == 'download') {
                                  unawaited(media.downloads.enqueue(track));
                                }
                                if (value == 'favorite') {
                                  unawaited(media.toggleFavorite(track.id));
                                }
                                if (value == 'share') {
                                  unawaited(shareAudio(context, track));
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'download',
                                  child: Text('تنزيل السورة'),
                                ),
                                PopupMenuItem(
                                  value: 'favorite',
                                  child: Text(
                                    media.favorites.contains(track.id)
                                        ? 'إزالة من المفضلة الصوتية'
                                        : 'إضافة للمفضلة الصوتية',
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'share',
                                  child: Text('مشاركة التلاوة'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 105),
                  child: Text(
                    'مصدر التلاوات: MP3Quran.net • رواية حفص عن عاصم',
                    textAlign: TextAlign.center,
                    style: qText(
                      context,
                      size: 10,
                      color: AppPalette.of(context).muted,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
  Future<void> _select(QuranRecitation recitation) async {
    final current = media.current;
    await media.select(recitation);
    if (current != null &&
        current.recitation.startsWith('mp3quran:') &&
        recitation.chapters.contains(current.surah)) {
      await media.playChapter(current.surah);
    }
  }

  Widget _action(
    BuildContext context,
    String text,
    IconData icon,
    VoidCallback? onTap, {
    bool active = false,
  }) => Expanded(
    child: QCard(
      color: active ? AppPalette.of(context).paleTeal : null,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 12),
      child: Column(
        children: [
          Icon(icon, color: qTeal, size: 24),
          const SizedBox(height: 7),
          Text(
            text,
            style: qText(context, size: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class ReciterAvatar extends StatelessWidget {
  const ReciterAvatar({super.key, required this.recitation});
  final QuranRecitation recitation;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 23,
    backgroundColor: AppPalette.of(context).paleTeal,
    child: reciterPortrait(recitation.name) == null
        ? const Icon(Icons.person_outline, color: qTeal, size: 28)
        : ClipOval(
            child: Image.network(
              reciterPortrait(recitation.name)!,
              width: 46,
              height: 46,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) =>
                  const Icon(Icons.person_outline, color: qTeal, size: 28),
            ),
          ),
  );
}

class QuranReciterPicker extends StatefulWidget {
  const QuranReciterPicker({
    super.key,
    required this.media,
    this.verse = false,
  });
  final QuranMedia media;
  final bool verse;
  @override
  State<QuranReciterPicker> createState() => _QuranReciterPickerState();
}

class _QuranReciterPickerState extends State<QuranReciterPicker> {
  String query = '';
  int filter = 0;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.media,
    builder: (context, _) {
      final catalog = widget.media.catalog;
      if (catalog == null) {
        return const Center(child: CircularProgressIndicator(color: qTeal));
      }
      final recitations = catalog.recitations
          .where(
            (r) =>
                r.verseAudio == widget.verse &&
                normalizeQuranSearch(
                  r.name,
                ).contains(normalizeQuranSearch(query)) &&
                (filter == 0 ||
                    filter == 1 && !r.style.contains('مجود') ||
                    filter == 2 && r.style.contains('مجود') ||
                    filter == 3 && widget.media.favorites.contains(r.id)),
          )
          .toList();
      final selected = widget.media.selection(verse: widget.verse).id;
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: QuranHeader(
              title: 'اختيار القارئ والتلاوة',
              subtitle: widget.verse
                  ? 'تلاوة الآيات • حفص عن عاصم'
                  : 'تلاوات السور • حفص عن عاصم',
              height: 150,
              onBack: () => Navigator.pop(context),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  if (widget.media.current != null) ...[
                    QuranPlayerPanel(
                      media: widget.media,
                      repository: widget.media.repository(),
                      compact: true,
                    ),
                    const SizedBox(height: 12),
                  ],
                  QSearchField(
                    hint: 'ابحث عن قارئ...',
                    onChanged: (value) => setState(() => query = value),
                  ),
                  const SizedBox(height: 12),
                  QSegments(
                    labels: const ['الكل', 'مرتل', 'مجود', 'المفضلة'],
                    selected: filter,
                    onSelect: (value) => setState(() => filter = value),
                  ),
                ],
              ),
            ),
          ),
          if (recitations.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'لا توجد تلاوات مطابقة',
                  style: qText(context),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 105),
            sliver: SliverList.builder(
              itemCount: recitations.length,
              itemBuilder: (context, index) {
                final entry = recitations[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: QCard(
                    onTap: () async {
                      final active = widget.media.current;
                      await widget.media.select(entry);
                      if (active != null &&
                          active.recitation.startsWith(
                            widget.verse ? 'everyayah:' : 'mp3quran:',
                          ) &&
                          entry.chapters.contains(active.surah)) {
                        if (widget.verse && active.ayah != null) {
                          await widget.media.playVerse(
                            widget.media
                                .repository()
                                .byKey['${active.surah}:${active.ayah}']!,
                          );
                        } else {
                          await widget.media.playChapter(active.surah);
                        }
                      }
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Row(
                      children: [
                        ReciterAvatar(recitation: entry),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.name,
                                style: qText(
                                  context,
                                  size: 15,
                                  weight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${entry.style}${entry.quality == null ? '' : ' • ${entry.quality}'}',
                                style: qText(
                                  context,
                                  size: 11,
                                  color: AppPalette.of(context).muted,
                                ),
                              ),
                              Text(
                                '${entry.chapters.length} سورة متاحة',
                                style: qText(context, size: 10, color: qTeal),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'مفضلة القراء',
                          onPressed: () =>
                              widget.media.toggleFavorite(entry.id),
                          icon: Icon(
                            widget.media.favorites.contains(entry.id)
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: qGold,
                          ),
                        ),
                        if (selected == entry.id)
                          const Icon(Icons.check_circle, color: qTeal),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}
