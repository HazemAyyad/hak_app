import '../../../core/localization/app_localization.dart';
import '../../../core/localization/ui_text.dart';
import '../../../core/localization/published_meaning_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../app_appearance.dart';
import '../data/quran_controller.dart';
import '../data/quran_repository.dart';
import 'quran_widgets.dart';
import 'quran_account.dart';
import 'quran_mushaf.dart';
import 'quran_reader_player.dart';
import 'quran_audio_widgets.dart' show chooseVerseRange;
import 'quran_audio_pages.dart';
import 'quran_tafsir.dart';
import '../../sharing/share_card.dart';

class QuranReader extends StatefulWidget {
  const QuranReader({
    super.key,
    required this.controller,
    required this.verse,
    required this.onFullscreenChanged,
    this.highlight,
    this.onActiveVerseChanged,
  });
  final QuranController controller;
  final QuranVerse verse;
  final String? highlight;
  final ValueChanged<QuranVerse>? onActiveVerseChanged;
  final ValueChanged<bool> onFullscreenChanged;
  @override
  State<QuranReader> createState() => _QuranReaderState();
}

class _QuranReaderState extends State<QuranReader> with WidgetsBindingObserver {
  final positions = ItemPositionsListener.create();
  ItemScrollController items = ItemScrollController();
  late final ValueNotifier<QuranVerse> active;
  late int surahId;
  QuranVerse? selected;
  bool playerExpanded = false;
  bool showHeader = true;
  bool fullscreen = false;
  double initialAlignment = 0;
  late int fixedPage;
  late QuranReadingMode previousMode;
  double _ayahDrag = 0;
  QuranController get controller => widget.controller;
  QuranRepository get repo => controller.repository!;

  @override
  void initState() {
    super.initState();
    active = ValueNotifier(widget.verse);
    active.addListener(_reportActiveVerse);
    surahId = widget.verse.surah;
    previousMode = controller.mode;
    fixedPage = controller.lastKey == widget.verse.key
        ? controller.lastPage ?? widget.verse.page
        : widget.verse.page;
    initialAlignment = controller.lastKey == widget.verse.key
        ? controller.lastAlignment
        : 0;
    controller.remember(
      widget.verse,
      alignment: initialAlignment,
      page: controller.mode == QuranReadingMode.pages ? fixedPage : null,
    );
    controller.addListener(_onPreferencesChanged);
    controller.audio.addListener(_onAudioChanged);
    positions.itemPositions.addListener(_onVisibleItems);
    WidgetsBinding.instance.addObserver(this);
  }

  void _reportActiveVerse() => widget.onActiveVerseChanged?.call(active.value);

  void _onVisibleItems() {
    if (!mounted || controller.mode != QuranReadingMode.continuous) return;
    final visible =
        positions.itemPositions.value
            .where(
              (p) =>
                  p.index > 0 &&
                  p.itemTrailingEdge > 0 &&
                  p.itemLeadingEdge < 1,
            )
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    if (visible.isEmpty) return;
    final index = visible.first.index;
    final verses = repo.surahVerses(surahId);
    if (index <= verses.length) {
      active.value = verses[index - 1];
      controller.remember(
        active.value,
        alignment: visible.first.itemLeadingEdge.clamp(0, .9),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) controller.persist();
  }

  void _setFullscreen(bool value) {
    setState(() => fullscreen = value);
    widget.onFullscreenChanged(value);
  }

  void _go(QuranVerse verse, {bool fromAudio = false}) {
    if (!fromAudio || verse.surah != surahId) {
      setState(() => selected = null);
    }
    fixedPage = verse.page;
    if (verse.surah != surahId) {
      setState(() {
        surahId = verse.surah;
        items = ItemScrollController();
        initialAlignment = 0;
      });
    }
    active.value = verse;
    controller.remember(verse);
    if (controller.mode == QuranReadingMode.continuous && items.isAttached) {
      items.jumpTo(index: verse.ayah);
    }
  }

  void _step(int delta) {
    final index = repo.surah(active.value.surah).start + active.value.ayah - 1;
    final next = index + delta;
    if (next >= 0 && next < repo.verses.length) _go(repo.verses[next]);
  }

  void _mode(QuranReadingMode value) {
    if (controller.mode == value) return;
    initialAlignment = controller.lastAlignment;
    items = ItemScrollController();
    controller.setMode(value);
  }

  void _onPreferencesChanged() {
    if (!mounted || previousMode == controller.mode) return;
    setState(() {
      selected = null;
      if (controller.mode == QuranReadingMode.pages) {
        fixedPage = active.value.page;
      }
      initialAlignment = 0;
      items = ItemScrollController();
      previousMode = controller.mode;
    });
  }

  void _onAudioChanged() {
    final track = controller.audio.current;
    if (!mounted ||
        track == null ||
        track.ayah == null ||
        !track.recitation.startsWith('everyayah:')) {
      return;
    }
    final verse = repo.byKey['${track.surah}:${track.ayah}'];
    if (verse != null && verse.key != active.value.key) {
      _go(verse, fromAudio: true);
    }
  }

  void _turnPage(int page) {
    final verse = repo.verses.firstWhere((v) => v.page == page);
    setState(() {
      fixedPage = page;
      surahId = verse.surah;
      selected = null;
    });
    active.value = verse;
    controller.remember(verse, page: page);
  }

  void _selectPageVerse(QuranVerse verse) {
    setState(() {
      selected = selected?.key == verse.key ? null : verse;
      surahId = verse.surah;
    });
    active.value = verse;
    controller.remember(
      verse,
      page: controller.mode == QuranReadingMode.pages ? fixedPage : null,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    positions.itemPositions.removeListener(_onVisibleItems);
    controller.removeListener(_onPreferencesChanged);
    controller.audio.removeListener(_onAudioChanged);
    controller.flushReading();
    active.removeListener(_reportActiveVerse);
    active.dispose();
    super.dispose();
  }

  Color _paper(BuildContext context) => switch (controller.paper) {
    'ivory' => const Color(0xFFFFF5DA),
    'green' => const Color(0xFFEFF5E6),
    'dark' => const Color(0xFF172833),
    _ => AppPalette.of(context).surface,
  };

  Color _ink(BuildContext context) =>
      controller.paper == 'dark' ||
          (controller.paper == 'light' &&
              Theme.of(context).brightness == Brightness.dark)
      ? const Color(0xFFF2EFE3)
      : const Color(0xFF17222C);

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !fullscreen,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && fullscreen) _setFullscreen(false);
    },
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ValueListenableBuilder(
        valueListenable: active,
        builder: (context, verse, _) {
          final chapter = repo.surah(surahId);
          return ColoredBox(
            color: _paper(context),
            child: Column(
              children: [
                if (!fullscreen) _toolbar(context, verse),
                if (!fullscreen && showHeader)
                  QuranHeader(
                    title: chapter.localizedTitle(context),
                    subtitle: context.tr(
                      'quran.readerHeader',
                      args: {
                        'juz': quranJuzName(context, verse.juz),
                        'page': quranNumber(
                          context,
                          controller.mode == QuranReadingMode.pages
                              ? fixedPage
                              : verse.page,
                        ),
                        'revelation': chapter.localizedRevelation(context),
                        'count': quranNumber(context, chapter.ayahCount),
                      },
                    ),
                    height: 154,
                    onBack: () => Navigator.pop(context),
                    actions: [
                      QCircleButton(
                        icon:
                            controller.bookmarks.containsKey(
                              (selected ?? verse).key,
                            )
                            ? Icons.bookmark
                            : Icons.bookmark_outline,
                        label: context.quranLabel('علامة مرجعية'),
                        onTap: () =>
                            controller.toggleBookmark((selected ?? verse).key),
                        color: qNavy,
                      ),
                      QCircleButton(
                        icon: Icons.menu_book_outlined,
                        label: context.quranLabel('تفسير الآية'),
                        onTap: () => _explanation(selected ?? verse),
                      ),
                      QCircleButton(
                        icon: Icons.settings_outlined,
                        label: context.quranLabel('إعدادات القراءة'),
                        onTap: _settings,
                      ),
                    ],
                  ),
                if (fullscreen)
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: context.quranLabel('إغلاق التكبير'),
                      onPressed: () => _setFullscreen(false),
                      icon: Icon(Icons.close, color: _ink(context)),
                    ),
                  ),
                if (widget.highlight != null && !fullscreen)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          label: Text(
                            context.quranLabel('العودة إلى النتائج'),
                            style: qText(
                              context,
                              size: 11,
                              color: qAccent(context),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          widget.highlight!,
                          style: qText(context, size: 11, color: qGold),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: controller.mode == QuranReadingMode.pages
                      ? QuranMushaf(
                          showTajweed: controller.showTajweed,
                          content: controller.content,
                          repository: repo,
                          page: fixedPage,
                          selected: selected?.key,
                          onPage: _turnPage,
                          onSelect: _selectPageVerse,
                          onOptions: _options,
                          paper: _paper(context),
                          ink: _ink(context),
                          fontFamily: controller.pageFont?.family,
                        )
                      : controller.mode == QuranReadingMode.continuous
                      ? _continuous(context, chapter)
                      : _single(context, verse),
                ),
                if (selected != null) _selectionTools(context),
                if (!fullscreen)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
                    child: QuranReaderPlayer(
                      media: controller.audio,
                      repository: repo,
                      surah: surahId,
                      selected: selected,
                      expanded: playerExpanded,
                      onToggleExpanded: () =>
                          setState(() => playerExpanded = !playerExpanded),
                      onReciter: () => _reciter(),
                    ),
                  ),
                if (!fullscreen) const SizedBox(height: 78),
              ],
            ),
          );
        },
      ),
    ),
  );

  Widget _toolbar(BuildContext context, QuranVerse verse) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          if (!showHeader)
            IconButton(
              tooltip: context.quranLabel('رجوع'),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_forward_ios, size: 20),
            ),
          Flexible(
            child: TextButton.icon(
              onPressed: _navigation,
              icon: Icon(Icons.unfold_more, size: 19, color: qAccent(context)),
              label: Text(
                context.quranLabel('انتقال'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: qText(context, size: 12, color: qAccent(context)),
              ),
            ),
          ),
          if (constraints.maxWidth > 390)
            Text(
              context.tr(
                'quran.pageLabel',
                args: {
                  'page': quranNumber(
                    context,
                    controller.mode == QuranReadingMode.pages
                        ? fixedPage
                        : verse.page,
                  ),
                },
              ),
              style: qText(
                context,
                size: 11,
                color: AppPalette.of(context).muted,
              ),
            ),
          const Spacer(),
          IconButton(
            key: const ValueKey('quran-toggle-header'),
            tooltip: showHeader
                ? context.quranLabel('إخفاء الهيدر')
                : context.quranLabel('إظهار الهيدر'),
            onPressed: () => setState(() => showHeader = !showHeader),
            icon: Icon(
              showHeader
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 21,
            ),
          ),
          if (controller.mode == QuranReadingMode.pages)
            Tooltip(
              message: context.tr('quran.bundledMushafReady'),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.offline_pin_outlined, size: 20),
              ),
            ),
          IconButton(
            tooltip: context.quranLabel('طريقة العرض'),
            onPressed: _chooseMode,
            icon: const Icon(Icons.chrome_reader_mode_outlined, size: 21),
          ),
          IconButton(
            tooltip: context.quranLabel('تكبير السورة'),
            onPressed: () => _setFullscreen(true),
            icon: const Icon(Icons.fullscreen, size: 24),
          ),
        ],
      ),
    ),
  );

  Widget _selectionTools(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        Text(
          context.tr(
            'quran.verseLabel',
            args: {'ayah': quranNumber(context, selected!.ayah)},
          ),
          style: qText(context, size: 12, color: qAccent(context)),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () => _explanation(selected!),
          icon: const Icon(Icons.menu_book_outlined, size: 18),
          label: Text(context.quranLabel('التفسير')),
        ),
        IconButton(
          tooltip: context.quranLabel('خيارات الآية'),
          onPressed: () => _options(selected!),
          icon: const Icon(Icons.more_horiz),
        ),
        IconButton(
          tooltip: context.quranLabel('إلغاء التحديد'),
          onPressed: () => setState(() => selected = null),
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    ),
  );

  Future<void> _navigation() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppPalette.of(context).surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.quranLabel('انتقال'),
              style: qText(context, size: 20, weight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(context.quranLabel('السورة'), style: qText(context, size: 12)),
            _selector<int>(
              context,
              surahId,
              [
                for (final chapter in repo.surahs)
                  DropdownMenuItem(
                    value: chapter.id,
                    child: Text(
                      chapter.localizedTitle(context),
                      style: qText(context, size: 13),
                    ),
                  ),
              ],
              (id) {
                Navigator.pop(sheetContext);
                _go(repo.byKey['$id:1']!);
              },
            ),
            const SizedBox(height: 12),
            Text(
              controller.mode == QuranReadingMode.pages
                  ? context.quranLabel('الصفحة')
                  : context.quranLabel('الآية'),
              style: qText(context, size: 12),
            ),
            _selector<int>(
              context,
              controller.mode == QuranReadingMode.pages
                  ? fixedPage
                  : active.value.ayah,
              List.generate(
                controller.mode == QuranReadingMode.pages
                    ? 604
                    : repo.surah(surahId).ayahCount,
                (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text(
                    context.tr(
                      'quran.readerLocationOption',
                      args: {
                        'kind': context.quranLabel(
                          controller.mode == QuranReadingMode.pages
                              ? 'الصفحة'
                              : 'الآية',
                        ),
                        'number': quranNumber(context, i + 1),
                      },
                    ),
                    style: qText(context, size: 13),
                  ),
                ),
              ),
              (id) {
                Navigator.pop(sheetContext);
                if (controller.mode == QuranReadingMode.pages) {
                  _turnPage(id);
                } else {
                  _go(repo.byKey['$surahId:$id']!);
                }
              },
            ),
            const SizedBox(height: 12),
            Text(context.quranLabel('الجزء'), style: qText(context, size: 12)),
            _selector<int>(
              context,
              active.value.juz,
              [
                for (final part in repo.juzs)
                  DropdownMenuItem(
                    value: part.id,
                    child: Text(
                      quranJuzName(context, part.id),
                      style: qText(context, size: 13),
                    ),
                  ),
              ],
              (id) {
                Navigator.pop(sheetContext);
                _go(repo.byKey[repo.juzs[id - 1].startKey]!);
              },
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                _settings();
              },
              icon: const Icon(Icons.settings_outlined),
              label: Text(context.quranLabel('إعدادات القراءة')),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _selector<T>(
    BuildContext context,
    T selected,
    List<DropdownMenuItem<T>> entries,
    ValueChanged<T> onSelect,
  ) => QCard(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: selected,
        isExpanded: true,
        iconSize: 18,
        items: entries,
        onChanged: (value) {
          if (value != null) onSelect(value);
        },
      ),
    ),
  );

  Widget _surahBanner(BuildContext context, QuranSurah chapter) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    child: Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F1E2),
            border: Border.all(color: qGold, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: QMedallion(
                  number: chapter.ayahCount,
                  size: 30,
                  textColor: qNavy,
                ),
              ),
              Text(
                'سُورَةُ ${chapter.name}',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: 'AmiriQuran',
                  fontSize: 26,
                  color: qAccent(context),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: QMedallion(
                  number: chapter.id,
                  size: 30,
                  textColor: qNavy,
                ),
              ),
            ],
          ),
        ),
        if (chapter.basmala != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              chapter.basmala!,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: controller.scriptFont.family,
                fontSize: controller.fontSize,
                color: _ink(context),
                height: 1.8,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _continuous(BuildContext context, QuranSurah chapter) {
    final verses = repo.surahVerses(surahId);
    return ScrollablePositionedList.builder(
      key: ValueKey('quran-continuous-$surahId'),
      itemScrollController: items,
      itemPositionsListener: positions,
      initialScrollIndex: active.value.ayah == 1 ? 0 : active.value.ayah,
      initialAlignment: initialAlignment,
      itemCount: verses.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _surahBanner(context, chapter);
        final verse = verses[index - 1];
        final highlighted =
            verse.key == widget.verse.key && widget.highlight != null;
        return Semantics(
          label: context.tr(
            'quran.surahVerseSemantics',
            args: {
              'name': chapter.localizedName(context),
              'ayah': quranNumber(context, verse.ayah),
            },
          ),
          selected: selected?.key == verse.key,
          child: InkWell(
            key: ValueKey('quran-select-${verse.key}'),
            onLongPress: () => _options(verse),
            onTap: () => _selectPageVerse(verse),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: selected?.key == verse.key
                  ? qAccent(context).withValues(alpha: .09)
                  : highlighted
                  ? qGold.withValues(alpha: .13)
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  QMedallion(
                    number: verse.ayah,
                    size: 31,
                    textColor: _ink(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          verse.text,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontFamily: controller.scriptFont.family,
                            fontSize: controller.fontSize,
                            color: _ink(context),
                            height: 1.85,
                          ),
                        ),
                        PublishedMeaningCard(verseKey: verse.key),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _single(BuildContext context, QuranVerse verse) => GestureDetector(
    key: const ValueKey('quran-ayah-swipe'),
    behavior: HitTestBehavior.opaque,
    onLongPress: () => _options(verse),
    onHorizontalDragStart: (_) => _ayahDrag = 0,
    onHorizontalDragUpdate: (details) => _ayahDrag += details.delta.dx,
    onHorizontalDragEnd: (details) {
      if (_ayahDrag.abs() >= 48 ||
          (_ayahDrag.abs() >= 18 && details.primaryVelocity!.abs() >= 350)) {
        _step(_ayahDrag > 0 ? 1 : -1);
      }
    },
    child: SingleChildScrollView(
      key: ValueKey('quran-ayah-scroll-${verse.key}'),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          QCard(
            key: ValueKey('quran-ayah-${verse.key}'),
            onTap: () => _selectPageVerse(verse),
            color: selected?.key == verse.key
                ? Color.alphaBlend(
                    qAccent(context).withValues(alpha: .09),
                    _paper(context),
                  )
                : _paper(context),
            child: Column(
              children: [
                QMedallion(
                  number: verse.ayah,
                  size: 42,
                  textColor: _ink(context),
                ),
                const SizedBox(height: 15),
                Text(
                  verse.text,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: controller.scriptFont.family,
                    fontSize: controller.fontSize + 3,
                    height: 1.85,
                    color: _ink(context),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    QCircleButton(
                      icon: Icons.share_outlined,
                      label: context.quranLabel('مشاركة الآية'),
                      onTap: () => _share(verse),
                    ),
                    QCircleButton(
                      icon: controller.favorites.containsKey(verse.key)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      label: context.quranLabel('المفضلة'),
                      onTap: () => controller.toggleFavorite(verse.key),
                      color: qAccent(context),
                    ),
                    QCircleButton(
                      icon: Icons.more_horiz,
                      label: context.quranLabel('خيارات الآية'),
                      onTap: () => _options(verse),
                    ),
                    QCircleButton(
                      icon: Icons.play_arrow,
                      label: context.quranLabel('تشغيل الآية'),
                      onTap: () => controller.audio.playVerse(verse),
                    ),
                    QCircleButton(
                      icon: Icons.repeat,
                      label: context.quranLabel('تكرار الآية'),
                      onTap: () =>
                          chooseVerseRange(context, controller.audio, verse),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          if (!fullscreen) ...[
            PublishedMeaningCard(verseKey: verse.key),
            QuranVerseInsight(
              key: ValueKey('insight-${verse.key}'),
              controller: controller,
              verse: verse,
              onOpen: (meanings) => _explanation(verse, meanings: meanings),
            ),
            const SizedBox(height: 15),
          ],
          QuranVerseNavigation(
            onPrevious: verse.key == repo.verses.first.key
                ? null
                : () => _step(-1),
            onNext: verse.key == repo.verses.last.key ? null : () => _step(1),
          ),
        ],
      ),
    ),
  );

  Future<void> _share(QuranVerse verse) async {
    await chooseContentShare(
      context,
      ShareCardContent.quran(repo, [verse.key]),
      repository: repo,
    );
  }

  void _options(QuranVerse verse) {
    setState(() {
      selected = verse;
      surahId = verse.surah;
    });
    active.value = verse;
    controller.remember(
      verse,
      page: controller.mode == QuranReadingMode.pages ? fixedPage : null,
    );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.of(context).surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.quranLabel('خيارات الآية'),
                    style: qText(context, size: 20, weight: FontWeight.w800),
                  ),
                  Text(
                    quranVerseTitle(
                      context,
                      repo.surah(verse.surah),
                      verse.ayah,
                    ),
                    style: qText(
                      context,
                      size: 12,
                      color: AppPalette.of(context).muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: Icon(Icons.play_arrow, color: qAccent(context)),
                    title: Text(context.quranLabel('استماع إلى الآية')),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      controller.audio.playVerse(verse);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined, color: qNavy),
                    title: Text(context.quranLabel('تفسير الآية')),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _explanation(verse);
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.description_outlined,
                      color: qNavy,
                    ),
                    title: Text(context.quranLabel('معاني الكلمات')),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _explanation(verse, meanings: true);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.repeat, color: qAccent(context)),
                    title: Text(context.quranLabel('استماع وتكرار نطاق آيات')),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      chooseVerseRange(this.context, controller.audio, verse);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.headphones, color: qAccent(context)),
                    title: Text(context.quranLabel('اختيار قارئ الآيات')),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _reciter(verse: true);
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.favorite_border,
                      color: qAccent(context),
                    ),
                    title: Text(
                      controller.favorites.containsKey(verse.key)
                          ? context.quranLabel('إزالة من المفضلة')
                          : context.quranLabel('إضافة إلى المفضلة'),
                    ),
                    onTap: () => controller.toggleFavorite(verse.key),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bookmark_outline, color: qGold),
                    title: Text(
                      controller.bookmarks.containsKey(verse.key)
                          ? context.quranLabel('إزالة العلامة المرجعية')
                          : context.quranLabel('حفظ علامة مرجعية'),
                    ),
                    onTap: () => controller.toggleBookmark(verse.key),
                  ),
                  ListTile(
                    leading: const Icon(Icons.copy_outlined, color: qNavy),
                    title: Text(context.quranLabel('نسخ الآية')),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: verse.text));
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      if (mounted) {
                        qNotice(
                          this.context,
                          this.context.quranLabel('تم نسخ الآية'),
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.share_outlined, color: qNavy),
                    title: Text(context.quranLabel('مشاركة الآية')),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _share(verse);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseMode() async {
    final choice = await showModalBottomSheet<QuranReadingMode>(
      context: context,
      backgroundColor: AppPalette.of(context).surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.quranLabel('طريقة عرض المصحف'),
                style: qText(context, size: 18, weight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              QSegments(
                labels: [
                  context.quranLabel('نص متصل'),
                  context.quranLabel('آية بآية'),
                  context.quranLabel('صفحات المصحف'),
                ],
                selected: controller.mode.index,
                onSelect: (value) {
                  Navigator.pop(context, QuranReadingMode.values[value]);
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && choice != null) _mode(choice);
  }

  void _explanation(QuranVerse verse, {bool meanings = false}) =>
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            backgroundColor: AppPalette.of(context).background,
            body: SafeArea(
              bottom: false,
              child: QuranExplanation(
                controller: controller,
                verse: verse,
                meanings: meanings,
                onPlay: controller.audio.playVerse,
                onWordPlay: (word) => controller.audio.playWord(
                  word.key,
                  word.position,
                  word.audio!,
                ),
              ),
            ),
          ),
        ),
      );
  Future<void> _reciter({bool? verse}) async {
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            backgroundColor: AppPalette.of(context).background,
            body: SafeArea(
              bottom: false,
              child: QuranReciterPicker(
                media: controller.audio,
                verse: verse ?? selected != null,
              ),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _settings() async {
    if (fullscreen) _setFullscreen(false);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: AppPalette.of(context).background,
          body: SafeArea(
            bottom: false,
            child: QuranReadingSettings(controller: controller),
          ),
        ),
      ),
    );
  }
}

class QuranReadingSettings extends StatelessWidget {
  const QuranReadingSettings({super.key, required this.controller});
  final QuranController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ListView(
      padding: EdgeInsets.zero,
      children: [
        QuranHeader(
          title: context.quranLabel('إعدادات القراءة'),
          subtitle: context.quranLabel('خصص تجربة القراءة بما يناسبك'),
          onBack: () => Navigator.pop(context),
          height: 150,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 105),
          child: Column(
            children: [
              QCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.account_circle_outlined,
                    color: qAccent(context),
                  ),
                  title: Text(
                    context.quranLabel('الحساب والمزامنة'),
                    style: qText(context, size: 16, weight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    context.quranLabel(
                      'حفظ المفضلة والعلامات والتقدم على حسابك',
                    ),
                    style: qText(context, size: 11),
                  ),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: SafeArea(
                          child: QuranAccountPage(controller: controller),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              QCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.quranLabel('طريقة العرض'),
                      style: qText(context, size: 18, weight: FontWeight.w800),
                    ),
                    Text(
                      context.quranLabel('اختر الطريقة المناسبة لعرض الآيات'),
                      style: qText(
                        context,
                        size: 11,
                        color: AppPalette.of(context).muted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    QSegments(
                      labels: [
                        context.quranLabel('نص متصل'),
                        context.quranLabel('آية بآية'),
                        context.quranLabel('صفحات المصحف'),
                      ],
                      selected: controller.mode.index,
                      onSelect: (value) =>
                          controller.setMode(QuranReadingMode.values[value]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              QCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.quranLabel('الخط وحجم النص'),
                      style: qText(context, size: 18, weight: FontWeight.w800),
                    ),
                    Text(
                      context.quranLabel('اختر خط نص القرآن'),
                      style: qText(
                        context,
                        size: 12,
                        color: AppPalette.of(context).muted,
                      ),
                    ),
                    if (controller.mode == QuranReadingMode.pages)
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'quran-page-font-${controller.pageFont?.name ?? 'original'}',
                        ),
                        initialValue: controller.pageFont?.name ?? 'original',
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.tr('quran.pageFont'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'original',
                            child: Text(context.tr('quran.originalMushafFont')),
                          ),
                          for (final font in QuranScriptFont.values)
                            DropdownMenuItem(
                              value: font.name,
                              child: Text(context.quranLabel(font.label)),
                            ),
                        ],
                        onChanged: (name) => controller.setPageFont(
                          QuranScriptFont.values
                              .where((font) => font.name == name)
                              .firstOrNull,
                        ),
                      )
                    else
                      DropdownButtonFormField<QuranScriptFont>(
                        key: ValueKey(
                          'quran-script-font-${controller.scriptFont.name}',
                        ),
                        initialValue: controller.scriptFont,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.quranLabel('نوع خط القرآن'),
                        ),
                        items: [
                          for (final font in QuranScriptFont.values)
                            DropdownMenuItem(
                              value: font,
                              child: Text(context.quranLabel(font.label)),
                            ),
                        ],
                        onChanged: controller.mode == QuranReadingMode.pages
                            ? null
                            : (font) {
                                if (font != null) {
                                  controller.setScriptFont(font);
                                }
                              },
                      ),
                    if (controller.mode == QuranReadingMode.pages)
                      Text(
                        context.tr('quran.pageFontHint'),
                        style: qText(context, size: 11),
                      ),
                    Row(
                      children: [
                        Text(
                          '${controller.fontSize.round()}',
                          style: qText(context),
                        ),
                        Expanded(
                          child: Slider(
                            value: controller.fontSize,
                            min: 18,
                            max: 36,
                            divisions: 18,
                            activeColor: qAccent(context),
                            onChanged: controller.mode == QuranReadingMode.pages
                                ? null
                                : controller.setFontSize,
                          ),
                        ),
                        Text('A', style: qText(context, size: 22)),
                      ],
                    ),
                    Center(
                      child: Text(
                        controller.repository!.verses.first.text,
                        style: TextStyle(
                          fontFamily: controller.mode == QuranReadingMode.pages
                              ? (controller.pageFont?.family ?? 'UthmanicHafs')
                              : controller.scriptFont.family,
                          fontSize: controller.fontSize,
                          height: 1.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              QCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.quranLabel('المظهر والألوان'),
                      style: qText(context, size: 18, weight: FontWeight.w800),
                    ),
                    SwitchListTile(
                      key: const ValueKey('quran-show-tajweed'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.quranLabel('إظهار ألوان التجويد')),
                      subtitle: Text(context.tr('quran.tajweedFontHint')),
                      value:
                          controller.mode == QuranReadingMode.pages &&
                              controller.pageFont != null
                          ? false
                          : controller.showTajweed,
                      onChanged:
                          controller.mode == QuranReadingMode.pages &&
                              controller.pageFont != null
                          ? null
                          : controller.setShowTajweed,
                    ),
                    Text(
                      context.quranLabel('اختر نمط القراءة المريح لعينيك'),
                      style: qText(
                        context,
                        size: 11,
                        color: AppPalette.of(context).muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final entry in [
                          (
                            'light',
                            context.quranLabel('فاتح'),
                            const Color(0xFFFFFCF7),
                          ),
                          (
                            'ivory',
                            context.quranLabel('ورق أصفر'),
                            const Color(0xFFFFF5DA),
                          ),
                          (
                            'green',
                            context.quranLabel('ورق مريح'),
                            const Color(0xFFEFF5E6),
                          ),
                          (
                            'dark',
                            context.quranLabel('داكن'),
                            const Color(0xFF172833),
                          ),
                        ])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: InkWell(
                                onTap: () => controller.setPaper(entry.$1),
                                borderRadius: BorderRadius.circular(9),
                                child: Column(
                                  children: [
                                    Container(
                                      height: 66,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: entry.$3,
                                        borderRadius: BorderRadius.circular(9),
                                        border: Border.all(
                                          color: controller.paper == entry.$1
                                              ? qAccent(context)
                                              : AppPalette.of(context).border,
                                          width: controller.paper == entry.$1
                                              ? 1.5
                                              : .8,
                                        ),
                                      ),
                                      child: Icon(
                                        controller.paper == entry.$1
                                            ? Icons.check_circle
                                            : Icons.menu_book_outlined,
                                        color: entry.$1 == 'dark'
                                            ? Colors.white
                                            : qGold,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      entry.$2,
                                      style: qText(context, size: 10),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
