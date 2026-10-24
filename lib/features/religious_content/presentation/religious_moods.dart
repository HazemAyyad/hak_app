part of 'religious_host.dart';

const _moodIcons = <String, IconData>{
  'sun': Icons.wb_sunny_outlined,
  'rain': Icons.cloud_outlined,
  'air': Icons.air,
  'leaf': Icons.eco_outlined,
  'heart': Icons.favorite_border,
  'flower': Icons.spa_outlined,
  'fire': Icons.local_fire_department_outlined,
  'question': Icons.help_outline,
  'search': Icons.search,
  'mosque': Icons.mosque_outlined,
  'health': Icons.health_and_safety_outlined,
  'hourglass': Icons.hourglass_empty,
  'cloud': Icons.cloud_outlined,
  'hands': Icons.front_hand_outlined,
  'shield': Icons.shield_outlined,
  'book': Icons.menu_book_outlined,
};

class _ReligiousTopicsPage extends StatelessWidget {
  const _ReligiousTopicsPage({required this.host});
  final ReligiousHostState host;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context), width = MediaQuery.sizeOf(context).width;
    return CustomScrollView(
      key: const PageStorageKey('religious-moods'),
      slivers: [
        SliverToBoxAdapter(
          child: Stack(
            children: [
              const DirectoryHeader(
                title: 'بماذا تشعر؟',
                subtitle: 'اختر شعورك في هذه اللحظة',
                maxTitleLines: 2,
                imageAsset: 'assets/navigation/header-moods.png',
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 12,
                left: 16,
                child: IconButton.filledTonal(
                  onPressed: host.back,
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'رجوع',
                ),
              ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          sliver: SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: p.paleTeal,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'كيف تشعر اليوم؟',
                    style: TextStyle(
                      color: p.tealHeading,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'دعاء وذكر يرافقان لحظتك',
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (host.catalog.moods.isEmpty)
          const SliverToBoxAdapter(
            child: ReligiousEmpty(
              text: 'لا توجد مشاعر منشورة في هذا المحتوى',
              icon: Icons.favorite_border,
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: width > 700 ? 4 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
              mainAxisExtent:
                  (width - 44) / (width > 700 ? 4 : 2) * .54 +
                  47 +
                  MediaQuery.textScalerOf(context).scale(42),
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final mood = host.catalog.moods[index];
              return Material(
                color: p.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: p.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('mood-${mood.id}'),
                  onTap: () => host._push(
                    _MoodReadingPage(host: host, mood: mood),
                    '/religious/mood/${mood.id}',
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final photoHeight = constraints.maxWidth * .54;
                            return SizedBox(
                              height: photoHeight + 35,
                              child: Stack(
                                alignment: Alignment.topCenter,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: Image.asset(
                                      'assets/navigation/mood-${mood.image}.png',
                                      height: photoHeight,
                                      width: constraints.maxWidth,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: photoHeight - 26,
                                    child: Container(
                                      width: 62,
                                      height: 62,
                                      decoration: BoxDecoration(
                                        color: p.surface,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: p.border),
                                      ),
                                      child: Icon(
                                        _moodIcons[mood.icon] ??
                                            Icons.favorite_border,
                                        color: p.tealHeading,
                                        size: 30,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
                            child: Text(
                              mood.title,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: p.heading,
                                fontSize: 17,
                                height: 1.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }, childCount: host.catalog.moods.length),
          ),
        ),
      ],
    );
  }
}

class _MoodReadingPage extends StatefulWidget {
  const _MoodReadingPage({required this.host, this.mood, this.collectionId})
    : assert(mood != null || collectionId != null);
  final ReligiousHostState host;
  final ReligiousMood? mood;
  final String? collectionId;
  String get id => mood?.id ?? collectionId!;
  String get title =>
      mood?.title ?? host.catalog.byCategory[collectionId]!.title;
  List<String> get itemIds =>
      mood?.itemIds ??
      host.catalog
          .search(category: collectionId)
          .map((item) => item.id)
          .toList();
  @override
  State<_MoodReadingPage> createState() => _MoodReadingPageState();
}

class _MoodReadingPageState extends State<_MoodReadingPage> {
  AdhkarSessionController? _session;
  late Future<AdhkarSessionController> _load = _prepare();
  Future<AdhkarSessionController> _prepare() async {
    final host = widget.host;
    final repository =
        host.controller.initialAdhkarCatalog ??
        await AdhkarRepository.load(host.controller.quran.repository!);
    final activity = await host.controller.activity, scope = activity.scope;
    final entries = <String, DhikrEntry>{};
    for (final id in widget.itemIds) {
      final matched = repository.items.values
          .where((entry) => entry.haqContentId == id)
          .toList();
      if (matched.isNotEmpty) {
        for (final item in matched) {
          entries[item.id] = item;
        }
      } else {
        final item = host.catalog.byId[id]!;
        final entry = DhikrEntry(
          id: item.id,
          title: item.title,
          text: item.text,
          target: 1,
          source: item.source,
          sourceUrl: item.sourceUrl,
          haqContentId: item.id,
          preface:
              'علامة لإتمام قراءة البطاقة مرة واحدة، وليست عدد تكرار مسنونًا لهذا القسم.',
        );
        entries[entry.id] = entry;
      }
    }
    if (entries.isEmpty) throw StateError('No published content');
    final group = DhikrGroup(
      id: '${widget.mood == null ? 'collection' : 'mood'}:${widget.id}',
      title: widget.title,
      itemIds: entries.keys.toList(),
    );
    if (!mounted || activity.scope != scope) {
      throw StateError('Account changed');
    }
    final session = await AdhkarSessionController.open(
      activity: activity,
      group: group,
      library: AdhkarLibrary([group], entries),
      catalogVersion: adhkarIdentity(
        'mood-catalog:${host.catalog.version}:${repository.version}',
      ),
    );
    if (!mounted || activity.scope != scope) {
      session.dispose();
      throw StateError('Account changed');
    }
    _session = session;
    session.addListener(_changed);
    return session;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session?.removeListener(_changed);
    _session?.dispose();
    super.dispose();
  }

  Future<void> _count(DhikrEntry item) async {
    final c = _session!;
    final before = c.remaining(item.id);
    await c.count(item.id);
    if (mounted &&
        c.available &&
        c.remaining(item.id) < before &&
        c.settings.hapticEvery) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context), host = widget.host;
    return FutureBuilder<AdhkarSessionController>(
      future: _load,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return ListView(
            children: [
              ReligiousHeader(title: widget.title, onBack: host.back),
              if (snapshot.hasError)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: TextButton(
                    onPressed: () => setState(() => _load = _prepare()),
                    child: const Text('لا يمكن فتح النصوص الآن؛ أعد المحاولة'),
                  ),
                )
              else
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          );
        }
        final c = snapshot.data!;
        if (!c.available) {
          return ListView(
            children: [
              ReligiousHeader(title: widget.title, onBack: host.back),
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'افتح القسم مجددًا لاستعادة جلسة الحساب واليوم الحالي.',
                ),
              ),
            ],
          );
        }
        return ListView(
          key: PageStorageKey('mood-reader-${widget.id}'),
          padding: EdgeInsets.zero,
          children: [
            ReligiousHeader(
              title: widget.title,
              subtitle: 'دعاء وذكر يرافقان لحظتك',
              image: 'medina',
              light: true,
              onBack: host.back,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'الأعداد الواردة مع النص من مصدره؛ علامة القراءة الواحدة لا تخصّص عبادة بعدد لهذا القسم.',
                style: TextStyle(fontSize: 12, color: p.muted, height: 1.7),
              ),
            ),
            for (final item in c.items)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: ReligiousCard(
                  ornament: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        item.title,
                        style: rText(context, 15, weight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        item.text,
                        textAlign: TextAlign.center,
                        style: rText(context, 22, height: 1.95),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        item.source,
                        style: rText(context, 11, color: p.muted),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              key: ValueKey('mood-count-${item.id}'),
                              onPressed: () => _count(item),
                              style: FilledButton.styleFrom(
                                backgroundColor: c.remaining(item.id) == 0
                                    ? const Color(0xFFB84B4B)
                                    : const Color(0xFF2A8C82),
                                foregroundColor: Colors.white,
                              ),
                              child: Text(
                                '${c.remaining(item.id)}',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => c.undo(subjectId: item.id),
                            icon: const Icon(Icons.undo),
                            tooltip: 'تراجع',
                          ),
                          IconButton(
                            onPressed: () => Clipboard.setData(
                              ClipboardData(
                                text: '${item.text}\n${item.source}',
                              ),
                            ),
                            icon: const Icon(Icons.copy_outlined),
                            tooltip: 'نسخ',
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'خيارات الدعاء',
                            onSelected: (action) {
                              final content =
                                  host.catalog.byId[item.haqContentId];
                              if (content == null) return;
                              if (action == 'details') host.openItem(content);
                              if (action == 'save') {
                                host.controller.toggleFavorite(content.id);
                              }
                              if (action == 'share') {
                                host.share(context, content);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'details',
                                child: Text('التفاصيل والمصدر'),
                              ),
                              const PopupMenuItem(
                                value: 'save',
                                child: Text('حفظ في المفضلة'),
                              ),
                              const PopupMenuItem(
                                value: 'share',
                                child: Text('مشاركة'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
              child: Column(
                children: [
                  if (c.error != null)
                    Text(c.error!, style: const TextStyle(color: Colors.red)),
                  if (c.completed)
                    Text(
                      'أتممت قراءة بطاقات هذا القسم اليوم',
                      style: TextStyle(
                        color: p.tealHeading,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: () => c.restart(),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('بدء جلسة جديدة'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
