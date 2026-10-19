import 'package:flutter/material.dart';

import '../../../app_appearance.dart';
import '../../../app_experience.dart';
import '../../../app_loading.dart';
import '../data/quran_controller.dart';
import '../data/quran_repository.dart';
import 'quran_reader.dart';
import 'quran_search.dart';
import 'quran_saved.dart';
import 'quran_widgets.dart';
import 'quran_audio_pages.dart';
import 'quran_audio_widgets.dart';
import 'quran_download_pages.dart';
import 'quran_tafsir.dart';
import 'quran_account.dart';
import 'quran_home_sections.dart';

class QuranHost extends StatefulWidget {
  const QuranHost({
    super.key,
    required this.controller,
    required this.onFullscreenChanged,
    this.active = true,
  });
  final QuranController controller;
  final ValueChanged<bool> onFullscreenChanged;
  final bool active;
  @override
  State<QuranHost> createState() => QuranHostState();
}

class QuranHostState extends State<QuranHost> {
  final navigator = GlobalKey<NavigatorState>();
  bool _pendingResume = false;
  Widget? _pendingPage;
  NavigatorObserver? _observer;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observer ??= AppExperienceScope.maybeOf(context)?.observer('quran');
  }

  QuranController get controller => widget.controller;
  Future<void> openReader(QuranVerse verse, {String? highlight}) async {
    await navigator.currentState?.push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/quran/read/${verse.key}'),
        builder: (_) => _frame(
          QuranReader(
            controller: controller,
            verse: verse,
            highlight: highlight,
            onFullscreenChanged: widget.onFullscreenChanged,
          ),
        ),
      ),
    );
    if (mounted) {
      controller.refreshReading();
      widget.onFullscreenChanged(false);
    }
  }

  void openLastReading() {
    if (controller.loading || navigator.currentState == null) {
      _pendingResume = true;
      return;
    }
    final verse = controller.lastVerse ?? controller.repository?.verses.first;
    if (verse != null) openReader(verse);
  }

  void openIndex({bool juz = false}) => _push(
    QuranIndexPage(
      controller: controller,
      juz: juz,
      onRead: openReader,
      onSearch: openSearch,
      onJuz: (part) => _push(
        QuranJuzPage(controller: controller, part: part, onRead: openReader),
      ),
    ),
  );

  void openSearch({String query = ''}) => _push(
    QuranSearchPage(
      controller: controller,
      initialQuery: query,
      onRead: (verse, search) => openReader(verse, highlight: search),
    ),
  );

  void openSaved({bool bookmarks = false}) => _push(
    QuranSavedPage(
      controller: controller,
      initialBookmarks: bookmarks,
      onRead: openReader,
    ),
  );

  void openSettings() => _push(QuranReadingSettings(controller: controller));
  void openAccount() => _push(QuranAccountPage(controller: controller));
  void openAudio() => _push(QuranAudioPage(controller: controller));
  void openDownloads() => _push(QuranDownloadPage(controller: controller));
  void openExplanation({bool meanings = false, QuranVerse? verse}) => _push(
    QuranExplanation(
      controller: controller,
      verse:
          verse ?? controller.lastVerse ?? controller.repository!.verses.first,
      meanings: meanings,
      onPlay: controller.audio.playVerse,
      onWordPlay: (word) =>
          controller.audio.playWord(word.key, word.position, word.audio!),
    ),
  );

  void _push(Widget page) {
    if (navigator.currentState == null) {
      _pendingPage = page;
      return;
    }
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => _frame(page)),
    );
  }

  Widget _frame(Widget child) => Builder(
    builder: (context) => Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(
          context,
        ).textTheme.apply(fontFamily: AppearanceScope.of(context).font.family),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: AppPalette.of(context).dark
              ? AppPalette.of(context).background
              : Colors.white,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(child: child),
                if (AppExperienceScope.maybeOf(context) == null &&
                    child is! QuranReader &&
                    child is! QuranAudioPage &&
                    child is! QuranExplanation)
                  ListenableBuilder(
                    listenable: controller.audio,
                    builder: (context, _) =>
                        controller.audio.current == null &&
                            !controller.audio.loading &&
                            controller.audio.error == null
                        ? const SizedBox()
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 82),
                            child: QuranPlayerPanel(
                              media: controller.audio,
                              repository: controller.repository!,
                              compact: true,
                              onOpen: openAudio,
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.loading) {
        return const AppLoadingSkeleton(label: 'جارٍ تحميل القرآن الكريم');
      }
      if (controller.loadError != null || controller.repository == null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('تعذّر فتح المصحف', style: qText(context, size: 20)),
              const SizedBox(height: 12),
              QPrimaryButton(label: 'إعادة المحاولة', onTap: controller.load),
            ],
          ),
        );
      }
      if (_pendingResume) {
        _pendingResume = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) openLastReading();
        });
      }
      if (_pendingPage != null) {
        final pending = _pendingPage!;
        _pendingPage = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _push(pending);
        });
      }
      return NavigatorPopHandler<void>(
        enabled: widget.active,
        onPopWithResult: (_) => navigator.currentState?.maybePop(),
        child: Navigator(
          key: navigator,
          observers: [?_observer],
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _frame(
              QuranHomePage(
                controller: controller,
                onIndex: openIndex,
                onResume: openLastReading,
                onSaved: openSaved,
                onSearch: openSearch,
                onAudio: openAudio,
                onDownloads: openDownloads,
                onExplain: () => openExplanation(),
                onVerseExplain: (verse) => openExplanation(verse: verse),
                onSettings: () =>
                    _push(QuranReadingSettings(controller: controller)),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class QuranHomePage extends StatelessWidget {
  const QuranHomePage({
    super.key,
    required this.controller,
    required this.onIndex,
    required this.onResume,
    required this.onSaved,
    required this.onSearch,
    required this.onSettings,
    required this.onAudio,
    required this.onDownloads,
    required this.onExplain,
    required this.onVerseExplain,
  });
  final QuranController controller;
  final void Function({bool juz}) onIndex;
  final void Function({bool bookmarks}) onSaved;
  final void Function({String query}) onSearch;
  final VoidCallback onResume, onSettings, onAudio, onDownloads, onExplain;
  final ValueChanged<QuranVerse> onVerseExplain;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final verse = controller.lastVerse;
      final repo = controller.repository!;
      return CustomScrollView(
        key: const PageStorageKey('quran-home'),
        slivers: [
          SliverToBoxAdapter(
            child: QuranHeader(
              title: 'القرآن الكريم',
              subtitle: 'نور وهداية لكل وقت',
              center: true,
              height: 182,
              actions: [
                QCircleButton(
                  icon: Icons.search,
                  label: 'بحث القرآن',
                  onTap: () => onSearch(),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                QSearchField(
                  hint: 'ابحث في السور أو الآيات ...',
                  readOnly: true,
                  onTap: () => onSearch(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _homeShortcut(
                      context,
                      'السور',
                      Icons.menu_book_outlined,
                      () => onIndex(),
                      active: true,
                    ),
                    const SizedBox(width: 8),
                    _homeShortcut(
                      context,
                      'الأجزاء',
                      Icons.layers_outlined,
                      () => onIndex(juz: true),
                    ),
                    const SizedBox(width: 8),
                    _homeShortcut(
                      context,
                      'المفضلة',
                      Icons.favorite_border,
                      () => onSaved(),
                    ),
                    const SizedBox(width: 8),
                    _homeShortcut(
                      context,
                      'العلامات',
                      Icons.bookmark_outline,
                      () => onSaved(bookmarks: true),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                QCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'آخر قراءة',
                              style: qText(
                                context,
                                size: 20,
                                weight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              verse == null
                                  ? 'ابدأ رحلتك مع القرآن'
                                  : 'سورة ${repo.surah(verse.surah).name}',
                              style: qText(
                                context,
                                size: 17,
                                weight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              verse == null
                                  ? 'يُحفظ موضع القراءة على هذا الجهاز'
                                  : 'الآية ${verse.ayah} من ${repo.surah(verse.surah).ayahCount}',
                              style: qText(
                                context,
                                size: 12,
                                color: AppPalette.of(context).muted,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (verse != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value:
                                      verse.ayah /
                                      repo.surah(verse.surah).ayahCount,
                                  minHeight: 5,
                                  color: qTeal,
                                  backgroundColor: AppPalette.of(
                                    context,
                                  ).border,
                                ),
                              ),
                            const SizedBox(height: 10),
                            QPrimaryButton(
                              label: verse == null
                                  ? 'بدء القراءة'
                                  : 'متابعة القراءة',
                              onTap: onResume,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Image.asset(
                        'assets/quran/quran_cover.png',
                        width: 78,
                        height: 118,
                        fit: BoxFit.contain,
                        semanticLabel: 'القرآن الكريم',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                QuranAudioBanner(onOpen: onAudio),
                const SizedBox(height: 14),
                QSectionTitle(
                  'استكشف القرآن',
                  action: 'عرض الكل',
                  onAction: () => onIndex(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _explore(
                      context,
                      'السور',
                      'تصفح جميع السور\nمرتبة ومقسمة',
                      Icons.menu_book,
                      () => onIndex(),
                    ),
                    const SizedBox(width: 8),
                    _explore(
                      context,
                      'الأجزاء',
                      'القرآن مقسم إلى\n30 جزءًا',
                      Icons.layers,
                      () => onIndex(juz: true),
                    ),
                    const SizedBox(width: 8),
                    _explore(
                      context,
                      'المفضلة',
                      'الآيات والمواضع\nالمحفوظة لديك',
                      Icons.favorite_border,
                      () => onSaved(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const QSectionTitle('أدوات إضافية'),
                const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _homeShortcut(
                        context,
                        'التفسير',
                        Icons.menu_book_outlined,
                        onExplain,
                      ),
                      const SizedBox(width: 8),
                      _homeShortcut(
                        context,
                        'المحتوى المحمل',
                        Icons.cloud_download_outlined,
                        onDownloads,
                      ),
                      const SizedBox(width: 8),
                      _homeShortcut(
                        context,
                        'العلامات',
                        Icons.bookmark_outline,
                        () => onSaved(bookmarks: true),
                      ),
                      const SizedBox(width: 8),
                      _homeShortcut(
                        context,
                        'آخر قراءة',
                        Icons.history,
                        onResume,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                QuranDailyVerse(repository: repo, onExplain: onVerseExplain),
                const SizedBox(height: 16),
                QCard(
                  onTap: onSettings,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.settings_outlined,
                        color: qTeal,
                        size: 27,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'إعدادات القراءة',
                              style: qText(context, weight: FontWeight.w800),
                            ),
                            Text(
                              'حجم الخط وطريقة العرض ومظهر القراءة',
                              style: qText(
                                context,
                                size: 11,
                                color: AppPalette.of(context).muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_left, color: qNavy),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('مصدر القرآن الكريم'),
                        content: SingleChildScrollView(
                          child: SelectableText(
                            'Tanzil Project\n${repo.sourceUrl}\n\n${repo.license}\n\nصفحات التجويد: خط QCF V4 من مجمع الملك فهد عبر Quran Foundation.\nhttps://api-docs.quran.com/docs/tutorials/fonts/font-rendering/\n\nصور المصحف المحفوظة: مصحف المدينة برواية حفص، مجمع الملك فهد عبر Quran.ws quran-svg v1.1.1.\nحقوق الرسوم للمجمع؛ بيانات مناطق الآيات © 2026 Quran.ws، ترخيص CC BY 4.0.\nhttps://github.com/quran-ws/quran-svg/blob/v1.1.1/NOTICE.md',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('إغلاق'),
                          ),
                        ],
                      ),
                    ),
                    child: Text(
                      'مصادر القرآن وحقوقه',
                      style: qText(
                        context,
                        size: 10,
                        color: AppPalette.of(context).muted,
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      );
    },
  );

  Widget _homeShortcut(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool active = false,
  }) => Expanded(
    child: QCard(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 12),
      color: active ? qTeal : AppPalette.of(context).neutral,
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, size: 25, color: active ? Colors.white : qNavy),
          const SizedBox(height: 6),
          Text(
            label,
            style: qText(
              context,
              size: 12,
              color: active ? Colors.white : null,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _explore(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) => Expanded(
    child: QCard(
      color: AppPalette.of(context).paleTeal,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Column(
        children: [
          Icon(icon, color: qTeal, size: 40),
          const SizedBox(height: 8),
          Text(title, style: qText(context, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: qText(
              context,
              size: 10,
              color: AppPalette.of(context).muted,
            ),
          ),
          const SizedBox(height: 5),
          const Align(
            alignment: Alignment.centerLeft,
            child: Icon(Icons.chevron_left, color: qTeal, size: 18),
          ),
        ],
      ),
    ),
  );
}

class QuranIndexPage extends StatefulWidget {
  const QuranIndexPage({
    super.key,
    required this.controller,
    required this.onRead,
    required this.onSearch,
    required this.onJuz,
    this.juz = false,
  });
  final QuranController controller;
  final bool juz;
  final void Function(QuranVerse) onRead;
  final void Function({String query}) onSearch;
  final ValueChanged<QuranJuz> onJuz;
  @override
  State<QuranIndexPage> createState() => _QuranIndexPageState();
}

class _QuranIndexPageState extends State<QuranIndexPage> {
  String query = '';
  int filter = 0;
  int sort = 0;
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final repo = widget.controller.repository!;
      final chapters = repo.surahs
          .where(
            (s) =>
                normalizeQuranSearch(
                  s.name,
                ).contains(normalizeQuranSearch(query)) &&
                (filter == 0 || s.meccan == (filter == 1)),
          )
          .toList();
      if (sort == 1) {
        chapters.sort((a, b) => b.ayahCount.compareTo(a.ayahCount));
      }
      if (sort == 2) {
        chapters.sort(
          (a, b) => normalizeQuranSearch(
            a.name,
          ).compareTo(normalizeQuranSearch(b.name)),
        );
      }
      final parts = repo.juzs
          .where(
            (part) =>
                (query.isEmpty ||
                    normalizeQuranSearch(
                      juzName(part.id),
                    ).contains(normalizeQuranSearch(query)) ||
                    part.id.toString() == query) &&
                (filter == 0 ||
                    (filter == 1
                        ? widget.controller.bookmarks.keys.any(
                            (key) => repo.byKey[key]?.juz == part.id,
                          )
                        : widget.controller.readJuzs.contains(part.id))),
          )
          .toList();
      return CustomScrollView(
        controller: scroll,
        slivers: [
          SliverToBoxAdapter(
            child: QuranHeader(
              title: widget.juz ? 'الأجزاء الثلاثون' : 'السور',
              subtitle: widget.juz
                  ? 'تصفح القرآن الكريم حسب الأجزاء'
                  : 'اختر السورة لبدء القراءة',
              dark: widget.juz,
              height: widget.juz ? 164 : 128,
              onBack: () => Navigator.pop(context),
              actions: [
                QCircleButton(
                  icon: Icons.search,
                  label: 'بحث الآيات',
                  onTap: () => widget.onSearch(),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  if (!widget.juz) ...[
                    QSegments(
                      labels: const [
                        'كل السور',
                        'السور المكية',
                        'السور المدنية',
                      ],
                      selected: filter,
                      onSelect: (value) => setState(() => filter = value),
                    ),
                    const SizedBox(height: 10),
                  ],
                  QSearchField(
                    hint: widget.juz
                        ? 'ابحث في الأجزاء ...'
                        : 'ابحث في السور ...',
                    onChanged: (value) => setState(() => query = value),
                  ),
                  const SizedBox(height: 10),
                  if (widget.juz)
                    QSegments(
                      labels: const [
                        'الكل',
                        'الأجزاء المحفوظة',
                        'الأجزاء التي تمت قراءتها',
                      ],
                      selected: filter,
                      onSelect: (value) => setState(() => filter = value),
                    ),
                  if (!widget.juz)
                    Row(
                      children: [
                        QCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            '${chapters.length} سورة',
                            style: qText(context, size: 11),
                          ),
                        ),
                        const Spacer(),
                        PopupMenuButton<int>(
                          onSelected: (value) => setState(() => sort = value),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 0,
                              child: Text('ترتيب المصحف'),
                            ),
                            PopupMenuItem(value: 1, child: Text('عدد الآيات')),
                            PopupMenuItem(value: 2, child: Text('الاسم')),
                          ],
                          child: QCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.filter_alt_outlined, size: 19),
                                const SizedBox(width: 8),
                                Text(
                                  ['ترتيب المصحف', 'عدد الآيات', 'الاسم'][sort],
                                  style: qText(context, size: 11),
                                ),
                                const Icon(Icons.expand_more, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if ((widget.juz ? parts.length : chapters.length) == 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'لا توجد عناصر مطابقة',
                  textAlign: TextAlign.center,
                  style: qText(context),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 105),
            sliver: SliverList.builder(
              itemCount: widget.juz ? parts.length : chapters.length,
              itemBuilder: (context, index) {
                if (widget.juz) {
                  final part = parts[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: QCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 9,
                      ),
                      onTap: () => widget.onJuz(part),
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Row(
                          children: [
                            QMedallion(number: part.id, filled: true, size: 44),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Directionality(
                                textDirection: TextDirection.rtl,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      juzName(part.id),
                                      style: qText(
                                        context,
                                        size: 17,
                                        weight: FontWeight.w800,
                                        color: AppPalette.of(
                                          context,
                                        ).tealHeading,
                                      ),
                                    ),
                                    Text(
                                      'من سورة ${repo.surah(part.startSurah).name} إلى سورة ${repo.surah(part.endSurah).name}',
                                      style: qText(context, size: 11),
                                    ),
                                    Text(
                                      'يبدأ من سورة ${repo.surah(part.startSurah).name} • الآية ${part.startAyah}',
                                      style: qText(
                                        context,
                                        size: 10,
                                        color: AppPalette.of(context).muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.chevron_right,
                              color: qTeal,
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                final chapter = chapters[index];
                final saved = widget.controller.savedSurahs.contains(
                  chapter.id,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: QCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    onTap: () => widget.onRead(repo.byKey['${chapter.id}:1']!),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        children: [
                          QMedallion(number: chapter.id, size: 38),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'سورة ${chapter.name}',
                                  style: qText(
                                    context,
                                    size: 12,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${chapter.revelation} • ${chapter.ayahCount} آية',
                                  style: qText(
                                    context,
                                    size: 10,
                                    color: AppPalette.of(context).muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          QCircleButton(
                            icon: Icons.play_arrow,
                            size: 30,
                            label: 'بدء قراءة سورة ${chapter.name}',
                            onTap: () =>
                                widget.onRead(repo.byKey['${chapter.id}:1']!),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            tooltip: saved
                                ? 'إزالة السورة المحفوظة'
                                : 'حفظ السورة',
                            onPressed: () =>
                                widget.controller.toggleSurah(chapter.id),
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: const EdgeInsets.all(4),
                            icon: Icon(
                              saved ? Icons.bookmark : Icons.bookmark_outline,
                              color: saved ? qGold : qTeal,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
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

class QuranJuzPage extends StatelessWidget {
  const QuranJuzPage({
    super.key,
    required this.controller,
    required this.part,
    required this.onRead,
  });
  final QuranController controller;
  final QuranJuz part;
  final ValueChanged<QuranVerse> onRead;
  @override
  Widget build(BuildContext context) {
    final repo = controller.repository!;
    final chapters = repo.surahs.sublist(part.startSurah - 1, part.endSurah);
    final range =
        'من سورة ${repo.surah(part.startSurah).name} إلى سورة ${repo.surah(part.endSurah).name}';
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        QuranHeader(
          title: juzName(part.id),
          subtitle: range,
          dark: true,
          height: 164,
          onBack: () => Navigator.pop(context),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 105),
          child: Column(
            children: [
              QCard(
                color: AppPalette.of(context).notice,
                child: Row(
                  children: [
                    const Icon(
                      Icons.menu_book_outlined,
                      color: qTeal,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            juzName(part.id),
                            style: qText(
                              context,
                              size: 19,
                              weight: FontWeight.w800,
                              color: AppPalette.of(context).tealHeading,
                            ),
                          ),
                          Text(range, style: qText(context, size: 11)),
                          Text(
                            'عدد السور: ${chapters.length} • عدد الآيات: ${part.ayahCount}',
                            style: qText(
                              context,
                              size: 11,
                              color: AppPalette.of(context).muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    QMedallion(number: part.id, size: 48, filled: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ...chapters.map((chapter) {
                final start = chapter.id == part.startSurah
                    ? part.startAyah
                    : 1;
                final end = chapter.id == part.endSurah
                    ? part.endAyah
                    : chapter.ayahCount;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: QCard(
                    onTap: () => onRead(repo.byKey['${chapter.id}:$start']!),
                    child: Row(
                      children: [
                        const Icon(Icons.chevron_right, color: qTeal),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'سورة ${chapter.name}',
                                style: qText(
                                  context,
                                  size: 18,
                                  weight: FontWeight.w800,
                                  color: AppPalette.of(context).tealHeading,
                                ),
                              ),
                              Text(
                                'الآيات $start–$end • ${chapter.revelation}',
                                style: qText(
                                  context,
                                  size: 12,
                                  color: AppPalette.of(context).muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        QMedallion(number: chapter.id, size: 48),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 5),
              SizedBox(
                width: double.infinity,
                child: QPrimaryButton(
                  label: 'بدء قراءة ${juzName(part.id)}',
                  icon: Icons.menu_book_outlined,
                  onTap: () => onRead(repo.byKey[part.startKey]!),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
