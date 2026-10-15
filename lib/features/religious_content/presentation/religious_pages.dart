part of 'religious_host.dart';

class _ReligiousTopicsPage extends StatelessWidget {
  const _ReligiousTopicsPage({required this.host});
  final ReligiousHostState host;
  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.zero,
    children: [
      ReligiousHeader(
        title: 'بماذا تشعر؟',
        subtitle: 'اختر موضوعًا لعرض الأدعية المرتبطة به',
        image: 'home',
        light: true,
        onBack: host.back,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        child: Column(
          children: [
            for (final (title, query, icon) in [
              ('الهم والحزن', 'الهم', Icons.favorite_border),
              ('الكرب', 'الكرب', Icons.spa_outlined),
              ('الخوف', 'خاف', Icons.shield_outlined),
              ('طلب التيسير', 'استصعب', Icons.wb_sunny_outlined),
              ('طلب المغفرة', 'الاستغفار', Icons.front_hand_outlined),
            ])
              ReligiousCard(
                margin: const EdgeInsets.only(bottom: 8),
                onTap: () => host._push(
                  _ReligiousCategoryPage(
                    host: host,
                    category: host.catalog.byCategory['prophetic-duas'],
                    initialQuery: query,
                    titleOverride: title,
                  ),
                  '/religious/topics/$query',
                ),
                child: Row(
                  children: [
                    Icon(icon, color: rGold),
                    const SizedBox(width: 12),
                    Expanded(child: Text(title, style: rText(context, 14))),
                    const Icon(
                      Icons.chevron_left,
                      textDirection: TextDirection.ltr,
                      color: rTeal,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _ReligiousHomePage extends StatefulWidget {
  const _ReligiousHomePage({required this.host});
  final ReligiousHostState host;
  @override
  State<_ReligiousHomePage> createState() => _ReligiousHomePageState();
}

class _ReligiousHomePageState extends State<_ReligiousHomePage> {
  final search = TextEditingController();
  String? scope;
  ReligiousHostState get host => widget.host;
  Future<void> chooseScope() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('جميع الأقسام'),
                onTap: () => Navigator.pop(context, 'all'),
              ),
              for (final category in host.catalog.children(null))
                ListTile(
                  title: Text(category.title),
                  onTap: () => Navigator.pop(context, category.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (value != null && mounted) {
      setState(() => scope = value == 'all' ? null : value);
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: host.controller,
    builder: (context, _) {
      final categories = [
        ...host.catalog.children(null).where((c) => c.id != 'nawawi'),
        ReligiousCategory({
          'id': 'daily-shortcut',
          'title': 'أدعية الحياة اليومية',
          'description': 'أدعية مقسمة حسب مناحي الحياة اليومية',
          'image': 'lantern',
        }),
        ReligiousCategory({
          'id': 'feelings-shortcut',
          'title': 'أدعية حسب الحالة',
          'description': 'أدعية مناسبة لمختلف المواقف',
          'image': 'hands',
        }),
      ];
      final query = search.text.trim();
      final results = host.catalog.search(category: scope, query: query);
      return RefreshIndicator(
        onRefresh: host.controller.refresh,
        color: rTeal,
        child: ListView(
          key: const PageStorageKey('religious-home'),
          padding: EdgeInsets.zero,
          children: [
            ReligiousHeader(
              title: 'الأدعية والمحتوى الديني',
              subtitle:
                  'مجموعة من الأدعية والكتب والمحتوى الإسلامي\nللاقتراب من الله في كل وقت',
              image: 'home',
              light: true,
            ),
            Container(
              decoration: BoxDecoration(
                color: ReligiousColors(context).background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Transform.translate(
                    offset: const Offset(0, -10),
                    child: ReligiousSearch(
                      controller: search,
                      hint: 'ابحث عن دعاء أو موضوع...',
                      onChanged: (_) => setState(() {}),
                      onFilter: chooseScope,
                    ),
                  ),
                  if (query.isNotEmpty || scope != null) ...[
                    if (scope != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InputChip(
                          label: Text(host.catalog.byCategory[scope]!.title),
                          onDeleted: () => setState(() => scope = null),
                        ),
                      ),
                    if (results.isEmpty)
                      const ReligiousEmpty(text: 'لا توجد نتائج مطابقة للبحث'),
                    for (final (index, item) in results.indexed)
                      _ItemTile(host: host, item: item, index: index),
                  ] else ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final scale = MediaQuery.textScalerOf(context).scale(1);
                        final count = constraints.maxWidth > 650 ? 3 : 2;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: count,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                mainAxisExtent:
                                    (constraints.maxWidth < 340 ? 130 : 86) *
                                    scale,
                              ),
                          itemCount: categories.length,
                          itemBuilder: (context, index) => _CategoryTile(
                            host: host,
                            category: categories[index],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 68 * MediaQuery.textScalerOf(context).scale(1),
                      child: _CategoryTile(
                        host: host,
                        category: host.catalog.byCategory['nawawi']!,
                        compact: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ReligiousCard(
                      onTap: () => host._push(
                        _ReligiousCategoryPage(
                          host: host,
                          titleOverride: 'محتوى ديني متنوع',
                        ),
                        '/religious/browse',
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.description_outlined, color: rGold),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'محتوى ديني متنوع',
                                  style: rText(
                                    context,
                                    13,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'نصوص وفوائد من المصادر المعتمدة',
                                  style: rText(context, 10),
                                ),
                              ],
                            ),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              rAsset('books'),
                              width: 82,
                              height: 50,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ReligiousCard(
                      onTap: () =>
                          host.openItem(host.catalog.byId['qdua-goodness']!),
                      padding: EdgeInsets.zero,
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          image: DecorationImage(
                            image: AssetImage(rAsset('daily')),
                            fit: BoxFit.cover,
                          ),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF082B3C), Color(0xFF082B3C)],
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.menu_book_outlined,
                              color: Color(0xFFF3C165),
                              size: 26,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'دعاء اليوم',
                                    style: rText(
                                      context,
                                      13,
                                      color: Colors.white,
                                      weight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    host.catalog.byId['qdua-goodness']!.title,
                                    style: rText(
                                      context,
                                      11,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    'البقرة • 201',
                                    style: rText(
                                      context,
                                      9,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'الوصول السريع',
                            style: rText(context, 16, weight: FontWeight.w800),
                          ),
                        ),
                        TextButton(
                          onPressed: () => host.openCategory('prophetic-duas'),
                          child: Text('عرض الكل', style: rText(context, 11)),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        for (final (title, icon, tag) in [
                          ('المفضلة', Icons.bookmark_border, 'saved'),
                          ('أذكاري', Icons.front_hand_outlined, 'adhkar'),
                          ('أدعية الصباح', Icons.wb_sunny_outlined, 'morning'),
                          ('أدعية النوم', Icons.nightlight_outlined, 'sleep'),
                        ])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(end: 5),
                              child: ReligiousCard(
                                onTap: () => tag == 'saved'
                                    ? host.openSaved()
                                    : tag == 'adhkar'
                                    ? host.openSaved(adhkar: true)
                                    : host._push(
                                        _ReligiousCategoryPage(
                                          host: host,
                                          category: host
                                              .catalog
                                              .byCategory['prophetic-duas'],
                                          initialQuery: tag == 'morning'
                                              ? 'الصباح'
                                              : 'النوم',
                                        ),
                                        '/religious/quick/$tag',
                                      ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 2,
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      icon,
                                      color: tag == 'morning'
                                          ? Colors.orange
                                          : rGold,
                                      size: 27,
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      title,
                                      textAlign: TextAlign.center,
                                      style: rText(context, 9),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (host.controller.updateError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        host.controller.updateError!,
                        style: rText(context, 11),
                      ),
                    ),
                  if (host.controller.syncError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        host.controller.syncError!,
                        style: rText(context, 11),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ReligiousCategoryPage extends StatefulWidget {
  const _ReligiousCategoryPage({
    required this.host,
    this.category,
    this.saved = false,
    this.adhkar = false,
    this.initialQuery = '',
    this.titleOverride,
  });
  final ReligiousHostState host;
  final ReligiousCategory? category;
  final bool saved, adhkar;
  final String initialQuery;
  final String? titleOverride;
  @override
  State<_ReligiousCategoryPage> createState() => _ReligiousCategoryPageState();
}

class _ReligiousCategoryPageState extends State<_ReligiousCategoryPage> {
  late final TextEditingController search = TextEditingController(
    text: widget.initialQuery,
  );
  String? tag;
  bool onlySaved = false;
  ReligiousHostState get host => widget.host;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> filter() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('جميع المواد'),
              leading: const Icon(Icons.view_list_outlined),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              title: const Text('المفضلة فقط'),
              leading: const Icon(Icons.bookmark_border),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) setState(() => onlySaved = result);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: host.controller,
    builder: (context, _) {
      final category = widget.category;
      final title =
          widget.titleOverride ??
          category?.title ??
          (widget.adhkar ? 'أذكاري' : 'المفضلة');
      final items = host.catalog.search(
        category: category?.id,
        query: search.text,
        tag: tag,
        favorites: widget.adhkar
            ? host.controller.customAdhkar
            : (widget.saved || onlySaved)
            ? host.controller.favorites
            : null,
      );
      final all = host.catalog.search(category: category?.id);
      final tags = {for (final item in all) ...item.tags}.toList();
      if (category?.id == 'friday') {
        tags.clear();
        tags.addAll(['قبل الجمعة', 'أثناء الجمعة', 'بعد الجمعة']);
      }
      final children = category == null
          ? <ReligiousCategory>[]
          : host.catalog.children(category.id);
      if (category?.kind == 'ruqya' && search.text.isEmpty) {
        return _ruqya(context, category!, children);
      }
      final showChildren =
          category?.kind == 'categories' && search.text.isEmpty && !onlySaved;
      final names = category?.kind == 'names';
      final verses = category?.kind == 'verses';
      return ListView(
        key: PageStorageKey(
          'religious-list-${category?.id}-${widget.saved}-${widget.adhkar}',
        ),
        padding: EdgeInsets.zero,
        children: [
          ReligiousHeader(
            title: title,
            subtitle: category?.description ?? 'المحتوى الذي حفظته للرجوع إليه',
            image: category?.header ?? 'ruqya',
            light: const ['home', 'medina'].contains(category?.header),
            onBack: host.back,
            onSaved: () => host.openSaved(),
            onShare: () => SharePlus.instance.share(ShareParams(text: title)),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 105),
            decoration: BoxDecoration(
              color: ReligiousColors(context).background,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ReligiousSearch(
                  controller: search,
                  hint: 'ابحث في $title ...',
                  onChanged: (_) => setState(() {}),
                  onFilter: filter,
                ),
                const SizedBox(height: 10),
                if (tags.isNotEmpty && !showChildren)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ReligiousPill(
                          text: 'الكل',
                          selected: tag == null,
                          onTap: () => setState(() => tag = null),
                        ),
                        for (final label in tags)
                          ReligiousPill(
                            text: label,
                            selected: tag == label,
                            onTap: () => setState(() => tag = label),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                if (showChildren) ...[
                  for (final child in children)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        height: 78 * MediaQuery.textScalerOf(context).scale(1),
                        child: _CategoryTile(
                          host: host,
                          category: child,
                          compact: true,
                        ),
                      ),
                    ),
                ],
                if (!showChildren && items.isEmpty)
                  ReligiousEmpty(
                    text: widget.saved
                        ? 'لم تحفظ أي محتوى بعد'
                        : widget.adhkar
                        ? 'أضف الأدعية إلى أذكارك من صفحة التفاصيل'
                        : 'لا توجد نتائج مطابقة',
                    icon: widget.saved
                        ? Icons.bookmark_border
                        : Icons.search_off,
                  ),
                if (names)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 7,
                      crossAxisSpacing: 7,
                      mainAxisExtent:
                          96 * MediaQuery.textScalerOf(context).scale(1),
                    ),
                    itemBuilder: (context, i) => _nameCard(context, items[i]),
                  ),
                if (!showChildren && !names)
                  for (final (index, item) in items.indexed)
                    _ItemTile(
                      host: host,
                      item: item,
                      index: index,
                      verse: verses,
                    ),
              ],
            ),
          ),
        ],
      );
    },
  );
  Widget _nameCard(BuildContext context, ReligiousItem item) => ReligiousCard(
    onTap: () => host.openItem(item),
    padding: const EdgeInsets.all(6),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${item.number}',
                style: rText(context, 8, color: rGold),
              ),
            ),
            SizedBox(
              width: 28,
              height: 18,
              child: IconButton(
                padding: EdgeInsets.zero,
                onPressed: () => host.controller.toggleFavorite(item.id),
                tooltip: 'المفضلة',
                icon: Icon(
                  host.controller.favorites.contains(item.id)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  size: 14,
                  color: rGold,
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                item.title,
                style: TextStyle(
                  fontFamily: 'AmiriQuran',
                  fontSize: 27,
                  color: ReligiousColors(context).heading,
                ),
              ),
            ),
          ),
        ),
        Text(
          item.summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: rText(context, 9),
        ),
      ],
    ),
  );
  Widget _ruqya(
    BuildContext context,
    ReligiousCategory category,
    List<ReligiousCategory> children,
  ) {
    final recent = host.controller.progress.entries.toList().reversed.take(3);
    return ListView(
      padding: EdgeInsets.zero,
      key: const PageStorageKey('religious-ruqya-home'),
      children: [
        ReligiousHeader(
          title: category.title,
          subtitle: category.description,
          image: 'ruqya',
          onBack: host.back,
          onSaved: () => host.openSaved(),
          onShare: () =>
              SharePlus.instance.share(ShareParams(text: category.title)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 105),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReligiousSearch(
                controller: search,
                hint: 'ابحث في الرقية الشرعية...',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: 105 * MediaQuery.textScalerOf(context).scale(1),
                ),
                child: ReligiousCard(
                  onTap: () =>
                      host.openItem(host.catalog.byId['ruqya-complete']!),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.play_circle_fill,
                        color: rTeal,
                        size: 32,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'الرقية الشرعية الكاملة',
                              style: rText(
                                context,
                                15,
                                weight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'استمع إلى الآيات المختارة\nمن القرآن الكريم',
                              style: rText(context, 12),
                            ),
                          ],
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          rAsset('mosque'),
                          width: 85,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'الأقسام',
                style: rText(context, 17, weight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: children.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent:
                      (MediaQuery.sizeOf(context).width < 360 ? 90 : 64) *
                      MediaQuery.textScalerOf(context).scale(1),
                ),
                itemBuilder: (context, i) => ReligiousCard(
                  onTap: () => host.openCategory(children[i].id),
                  padding: const EdgeInsets.all(9),
                  child: Row(
                    children: [
                      Icon(
                        [
                          Icons.shield_outlined,
                          Icons.favorite_border,
                          Icons.visibility_outlined,
                          Icons.auto_fix_high_outlined,
                          Icons.child_care,
                          Icons.front_hand_outlined,
                          Icons.menu_book_outlined,
                        ][i],
                        color: rTeal,
                        size: 22,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              children[i].title,
                              style: rText(
                                context,
                                11,
                                weight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              children[i].description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: rText(context, 10),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_left, size: 18, color: rTeal),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'آخر ما استمعت إليه',
                style: rText(context, 16, weight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (recent.isEmpty)
                const ReligiousEmpty(
                  text: 'ابدأ الاستماع لتظهر هنا المقاطع الأخيرة',
                  icon: Icons.history,
                ),
              for (final id in host.controller.listeningQueue)
                if (host.catalog.byId[id] case final queued?)
                  ReligiousCard(
                    margin: const EdgeInsets.only(bottom: 7),
                    onTap: () => host.openItem(queued),
                    child: Row(
                      children: [
                        const Icon(Icons.queue_music, color: rGold),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(queued.title, style: rText(context, 12)),
                        ),
                        ReligiousRoundButton(
                          icon: Icons.play_arrow,
                          label: 'تشغيل قائمة الاستماع',
                          filled: true,
                          onTap: () => host.play(context, queued),
                        ),
                      ],
                    ),
                  ),
              for (final entry in recent)
                if (host.catalog.byId[entry.key] case final item?)
                  ReligiousCard(
                    margin: const EdgeInsets.only(bottom: 7),
                    onTap: () => host.openItem(item),
                    child: Row(
                      children: [
                        const Icon(Icons.history, color: rGold),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(item.title, style: rText(context, 12)),
                        ),
                        Text(
                          _duration(
                            Duration(
                              seconds: entry.value['seconds'] as int? ?? 0,
                            ),
                          ),
                          style: rText(context, 10),
                        ),
                        ReligiousRoundButton(
                          icon: Icons.play_arrow,
                          label: 'استئناف الاستماع',
                          filled: true,
                          onTap: () => host.play(context, item),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
