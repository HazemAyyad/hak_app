import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app_appearance.dart';
import '../data/quran_controller.dart';
import '../data/quran_repository.dart';
import 'quran_widgets.dart';

class QuranReader extends StatefulWidget {
  const QuranReader({
    super.key,
    required this.controller,
    required this.verse,
    required this.onFullscreenChanged,
    this.highlight,
  });
  final QuranController controller;
  final QuranVerse verse;
  final String? highlight;
  final ValueChanged<bool> onFullscreenChanged;
  @override
  State<QuranReader> createState() => _QuranReaderState();
}

class _QuranReaderState extends State<QuranReader> with WidgetsBindingObserver {
  final positions = ItemPositionsListener.create();
  ItemScrollController items = ItemScrollController();
  late final ValueNotifier<QuranVerse> active;
  late int surahId;
  bool fullscreen = false;
  double initialAlignment = 0;
  QuranController get controller => widget.controller;
  QuranRepository get repo => controller.repository!;

  @override
  void initState() {
    super.initState();
    active = ValueNotifier(widget.verse);
    surahId = widget.verse.surah;
    initialAlignment = controller.lastKey == widget.verse.key
        ? controller.lastAlignment
        : 0;
    controller.remember(widget.verse, alignment: initialAlignment);
    positions.itemPositions.addListener(_onVisibleItems);
    WidgetsBinding.instance.addObserver(this);
  }

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

  void _go(QuranVerse verse) {
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    positions.itemPositions.removeListener(_onVisibleItems);
    controller.flushReading();
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
                if (!fullscreen)
                  QuranHeader(
                    title: 'سورة ${chapter.name}',
                    subtitle:
                        '${juzName(verse.juz)} • الصفحة ${verse.page}\n${chapter.revelation} • ${chapter.ayahCount} آية',
                    height: 154,
                    onBack: () => Navigator.pop(context),
                    actions: [
                      QCircleButton(
                        icon: controller.bookmarks.containsKey(verse.key)
                            ? Icons.bookmark
                            : Icons.bookmark_outline,
                        label: 'علامة مرجعية',
                        onTap: () => controller.toggleBookmark(verse.key),
                        color: qNavy,
                      ),
                      QCircleButton(
                        icon: Icons.settings_outlined,
                        label: 'إعدادات القراءة',
                        onTap: _settings,
                      ),
                    ],
                  ),
                if (fullscreen)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: IconButton(
                      tooltip: 'إغلاق التكبير',
                      onPressed: () => _setFullscreen(false),
                      icon: Icon(Icons.close, color: _ink(context)),
                    ),
                  ),
                if (!fullscreen)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: _selector<int>(
                            context,
                            verse.ayah,
                            List.generate(
                              chapter.ayahCount,
                              (i) => DropdownMenuItem(
                                value: i + 1,
                                child: Text(
                                  'الآية ${i + 1}',
                                  style: qText(context, size: 11),
                                ),
                              ),
                            ),
                            (id) => _go(repo.byKey['$surahId:$id']!),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: _selector<int>(
                            context,
                            surahId,
                            repo.surahs
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s.id,
                                    child: Text(
                                      'سورة ${s.name}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: qText(context, size: 11),
                                    ),
                                  ),
                                )
                                .toList(),
                            (id) => _go(repo.byKey['$id:1']!),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: _selector<int>(
                            context,
                            verse.juz,
                            repo.juzs
                                .map(
                                  (j) => DropdownMenuItem(
                                    value: j.id,
                                    child: Text(
                                      juzName(j.id),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: qText(context, size: 11),
                                    ),
                                  ),
                                )
                                .toList(),
                            (id) =>
                                _go(repo.byKey[repo.juzs[id - 1].startKey]!),
                          ),
                        ),
                      ],
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
                            'العودة إلى النتائج',
                            style: qText(context, size: 11, color: qTeal),
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
                  child: controller.mode == QuranReadingMode.continuous
                      ? _continuous(context, chapter)
                      : _single(context, verse),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: QPrimaryButton(
                          label: fullscreen
                              ? 'إغلاق التكبير'
                              : (controller.mode == QuranReadingMode.ayah
                                    ? 'تكبير الآية'
                                    : 'تكبير السورة'),
                          icon: fullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          onTap: () => _setFullscreen(!fullscreen),
                        ),
                      ),
                      const SizedBox(width: 8),
                      QCircleButton(
                        icon: Icons.format_list_bulleted,
                        label: 'طريقة العرض',
                        onTap: _chooseMode,
                      ),
                      const SizedBox(width: 8),
                      QCircleButton(
                        icon: Icons.more_horiz,
                        label: 'خيارات الآية',
                        onTap: () => _options(active.value),
                      ),
                    ],
                  ),
                ),
                // The app shell keeps its existing navigation; reserve room for extendBody.
                if (!fullscreen) const SizedBox(height: 78),
              ],
            ),
          );
        },
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
                style: const TextStyle(
                  fontFamily: 'AmiriQuran',
                  fontSize: 26,
                  color: qTeal,
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
              style: TextStyle(
                fontFamily: 'AmiriQuran',
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
          label: 'سورة ${chapter.name} الآية ${verse.ayah}',
          child: InkWell(
            onLongPress: () => _options(verse),
            onTap: () => _options(verse),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: highlighted ? qGold.withValues(alpha: .13) : null,
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
                    child: Text(
                      verse.text,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'AmiriQuran',
                        fontSize: controller.fontSize,
                        color: _ink(context),
                        height: 1.85,
                      ),
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

  Widget _single(BuildContext context, QuranVerse verse) =>
      SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            QCard(
              color: _paper(context),
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
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'AmiriQuran',
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
                        label: 'مشاركة الآية',
                        onTap: () => _share(verse),
                      ),
                      QCircleButton(
                        icon: controller.favorites.containsKey(verse.key)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        label: 'المفضلة',
                        onTap: () => controller.toggleFavorite(verse.key),
                        color: qTeal,
                      ),
                      QCircleButton(
                        icon: Icons.more_horiz,
                        label: 'خيارات الآية',
                        onTap: () => _options(verse),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: QCard(
                    onTap: () => _step(1),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chevron_right, color: qTeal),
                        Text('الآية التالية', style: qText(context, size: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: QCard(
                    onTap: () => _step(-1),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('الآية السابقة', style: qText(context, size: 12)),
                        const Icon(Icons.chevron_left, color: qTeal),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  String _shareText(QuranVerse verse) =>
      '${verse.text}\n[سورة ${repo.surah(verse.surah).name}: ${verse.ayah}]\nالنص: Tanzil Project • https://tanzil.net';

  Future<void> _share(QuranVerse verse) async {
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _shareText(verse),
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (mounted) qNotice(context, 'تعذّرت المشاركة. يمكنك نسخ الآية.');
    }
  }

  void _options(QuranVerse verse) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppPalette.of(context).surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'خيارات الآية',
                style: qText(context, size: 20, weight: FontWeight.w800),
              ),
              Text(
                'سورة ${repo.surah(verse.surah).name} • الآية ${verse.ayah}',
                style: qText(
                  context,
                  size: 12,
                  color: AppPalette.of(context).muted,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.favorite_border, color: qTeal),
                title: Text(
                  controller.favorites.containsKey(verse.key)
                      ? 'إزالة من المفضلة'
                      : 'إضافة إلى المفضلة',
                ),
                onTap: () => controller.toggleFavorite(verse.key),
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_outline, color: qGold),
                title: Text(
                  controller.bookmarks.containsKey(verse.key)
                      ? 'إزالة العلامة المرجعية'
                      : 'حفظ علامة مرجعية',
                ),
                onTap: () => controller.toggleBookmark(verse.key),
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined, color: qNavy),
                title: const Text('نسخ الآية'),
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: _shareText(verse)),
                  );
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  if (mounted) qNotice(this.context, 'تم نسخ الآية');
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined, color: qNavy),
                title: const Text('مشاركة الآية'),
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
  );

  void _chooseMode() => showModalBottomSheet<void>(
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
              'طريقة عرض المصحف',
              style: qText(context, size: 18, weight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            QSegments(
              labels: const ['نص متصل', 'آية بآية'],
              selected: controller.mode.index,
              onSelect: (value) {
                _mode(QuranReadingMode.values[value]);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    ),
  );

  void _settings() {
    if (fullscreen) _setFullscreen(false);
    Navigator.push(
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
          title: 'إعدادات القراءة',
          subtitle: 'خصص تجربة القراءة بما يناسبك',
          onBack: () => Navigator.pop(context),
          height: 150,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 105),
          child: Column(
            children: [
              QCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'طريقة العرض',
                      style: qText(context, size: 18, weight: FontWeight.w800),
                    ),
                    Text(
                      'اختر الطريقة المناسبة لعرض الآيات',
                      style: qText(
                        context,
                        size: 11,
                        color: AppPalette.of(context).muted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    QSegments(
                      labels: const ['نص متصل', 'آية بآية'],
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
                      'الخط وحجم النص',
                      style: qText(context, size: 18, weight: FontWeight.w800),
                    ),
                    Text(
                      'خط أميري قرآن • رسم عثماني',
                      style: qText(
                        context,
                        size: 12,
                        color: AppPalette.of(context).muted,
                      ),
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
                            activeColor: qTeal,
                            onChanged: controller.setFontSize,
                          ),
                        ),
                        Text('A', style: qText(context, size: 22)),
                      ],
                    ),
                    Center(
                      child: Text(
                        controller.repository!.verses.first.text,
                        style: TextStyle(
                          fontFamily: 'AmiriQuran',
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
                      'المظهر والألوان',
                      style: qText(context, size: 18, weight: FontWeight.w800),
                    ),
                    Text(
                      'اختر نمط القراءة المريح لعينيك',
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
                          ('light', 'فاتح', const Color(0xFFFFFCF7)),
                          ('ivory', 'ورق أصفر', const Color(0xFFFFF5DA)),
                          ('green', 'ورق مريح', const Color(0xFFEFF5E6)),
                          ('dark', 'داكن', const Color(0xFF172833)),
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
                                              ? qTeal
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
