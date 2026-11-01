part of 'religious_host.dart';

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
                title: Text(context.religiousLabel('جميع الأقسام')),
                onTap: () => Navigator.pop(context, 'all'),
              ),
              for (final category in host.catalog.children(null))
                ListTile(
                  title: Text(category.interfaceTitle(context)),
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
          'title': context.religiousLabel('أدعية الحياة اليومية'),
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
      return AppRefreshRegion(
        onRefresh: host.controller.refresh,
        color: rAccent(context),
        child: ListView(
          key: const PageStorageKey('religious-home'),
          padding: EdgeInsets.zero,
          children: [
            ReligiousHeader(
              title: context.religiousLabel('المزيد'),
              subtitle: context.religiousLabel(
                'مجموعة من الأدعية والكتب والمحتوى الإسلامي\nللاقتراب من الله في كل وقت',
              ),
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
                      hint: context.religiousLabel('ابحث عن دعاء أو موضوع...'),
                      onChanged: (_) => setState(() {}),
                      onFilter: chooseScope,
                    ),
                  ),
                  if (query.isNotEmpty || scope != null) ...[
                    if (scope != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InputChip(
                          label: Text(
                            host.catalog.byCategory[scope]!.interfaceTitle(
                              context,
                            ),
                          ),
                          onDeleted: () => setState(() => scope = null),
                        ),
                      ),
                    if (results.isEmpty)
                      ReligiousEmpty(
                        text: context.religiousLabel(
                          'لا توجد نتائج مطابقة للبحث',
                        ),
                      ),
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
                    ReligiousCard(
                      onTap: () => host._push(
                        _ReligiousCategoryPage(
                          host: host,
                          titleOverride: context.religiousLabel(
                            'محتوى ديني متنوع',
                          ),
                        ),
                        '/religious/browse',
                      ),
                      padding: EdgeInsets.zero,
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius:
                                const BorderRadiusDirectional.horizontal(
                                  start: Radius.circular(14),
                                ).resolve(
                                  LocalizationScope.maybeOf(
                                        context,
                                      )?.language.direction ??
                                      TextDirection.rtl,
                                ),
                            child: Image.asset(
                              rAsset('books'),
                              width: 110,
                              height: 76,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.religiousLabel('محتوى ديني متنوع'),
                                  style: rText(
                                    context,
                                    13,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  context.religiousLabel(
                                    'مقالات وقصص وفوائد إيمانية',
                                  ),
                                  style: rText(context, 10),
                                ),
                                InkWell(
                                  onTap: () => host.openCategory('nawawi'),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 5,
                                    ),
                                    child: Text(
                                      context.religiousLabel(
                                        'الأربعون النووية  ‹',
                                      ),
                                      style: rText(
                                        context,
                                        12,
                                        weight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.chevron_left,
                              color: rAccent(context),
                              textDirection: TextDirection.ltr,
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
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          image: DecorationImage(
                            image: AssetImage(rAsset('daily')),
                            fit: BoxFit.cover,
                            colorFilter: ColorFilter.mode(
                              Colors.black.withValues(alpha: .35),
                              BlendMode.darken,
                            ),
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
                                    context.religiousLabel('دعاء اليوم'),
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
                                    context.tr(
                                      'religious.dailyDuaReference',
                                      args: {
                                        'surah': context.tr(
                                          'quran.surah.2',
                                          fallback: 'البقرة',
                                        ),
                                        'ayah': religiousNumber(context, 201),
                                      },
                                    ),
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
                            context.religiousLabel('الوصول السريع'),
                            style: rText(context, 14, weight: FontWeight.w800),
                          ),
                        ),
                        TextButton(
                          onPressed: () => host.openCategory('prophetic-duas'),
                          style: TextButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.all(8),
                          ),
                          child: Text(
                            context.religiousLabel('عرض الكل'),
                            style: rText(context, 11),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        for (final (title, icon, tag) in [
                          (
                            context.religiousLabel('المفضلة'),
                            Icons.bookmark_border,
                            'saved',
                          ),
                          (
                            context.religiousLabel('أذكاري'),
                            Icons.front_hand_outlined,
                            'adhkar',
                          ),
                          (
                            context.religiousLabel('أدعية الصباح'),
                            Icons.wb_sunny_outlined,
                            'morning',
                          ),
                          (
                            context.religiousLabel('أدعية النوم'),
                            Icons.nightlight_outlined,
                            'sleep',
                          ),
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
              title: Text(context.religiousLabel('جميع المواد')),
              leading: const Icon(Icons.view_list_outlined),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              title: Text(context.religiousLabel('المفضلة فقط')),
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
          category?.interfaceTitle(context) ??
          (widget.adhkar
              ? context.religiousLabel('أذكاري')
              : context.religiousLabel('المفضلة'));
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
      return CustomScrollView(
        key: PageStorageKey(
          'religious-list-${category?.id}-${widget.saved}-${widget.adhkar}',
        ),
        slivers: [
          SliverToBoxAdapter(
            child: ReligiousHeader(
              title: title,
              subtitle:
                  category?.description ??
                  context.religiousLabel('المحتوى الذي حفظته للرجوع إليه'),
              image: category?.header ?? 'ruqya',
              light: const ['home', 'medina'].contains(category?.header),
              onBack: host.back,
              onSaved: () => host.openSaved(),
              onShare: () =>
                  chooseContentShare(context, ShareCardContent.message(title)),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
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
                    hint: context.tr(
                      'religious.searchIn',
                      args: {'title': title},
                    ),
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
                            text: context.religiousLabel('الكل'),
                            selected: tag == null,
                            onTap: () => setState(() => tag = null),
                          ),
                          for (final label in tags)
                            ReligiousPill(
                              text: context.religiousLabel(label),
                              selected: tag == label,
                              onTap: () => setState(() => tag = label),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            sliver: showChildren
                ? SliverList.builder(
                    itemCount: children.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        height: 78 * MediaQuery.textScalerOf(context).scale(1),
                        child: _CategoryTile(
                          host: host,
                          category: children[index],
                          compact: true,
                        ),
                      ),
                    ),
                  )
                : items.isEmpty
                ? SliverToBoxAdapter(
                    child: ReligiousEmpty(
                      text: widget.saved
                          ? context.religiousLabel('لم تحفظ أي محتوى بعد')
                          : widget.adhkar
                          ? context.religiousLabel(
                              'أضف الأدعية إلى أذكارك من صفحة التفاصيل',
                            )
                          : context.religiousLabel('لا توجد نتائج مطابقة'),
                      icon: widget.saved
                          ? Icons.bookmark_border
                          : Icons.search_off,
                    ),
                  )
                : names
                ? SliverGrid.builder(
                    itemCount: items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 7,
                      crossAxisSpacing: 7,
                      mainAxisExtent:
                          96 * MediaQuery.textScalerOf(context).scale(1),
                    ),
                    itemBuilder: (context, index) =>
                        _nameCard(context, items[index]),
                  )
                : SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) => _ItemTile(
                      host: host,
                      item: items[index],
                      index: index,
                      verse: verses,
                    ),
                  ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 105)),
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
                tooltip: context.religiousLabel('المفضلة'),
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
          title: category.interfaceTitle(context),
          subtitle: category.description,
          image: 'ruqya',
          onBack: host.back,
          onSaved: () => host.openSaved(),
          onShare: () => chooseContentShare(
            context,
            ShareCardContent.message(category.title),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 105),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReligiousSearch(
                controller: search,
                hint: context.religiousLabel('ابحث في الرقية الشرعية...'),
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
                      Icon(
                        Icons.play_circle_fill,
                        color: rAccent(context),
                        size: 32,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.religiousLabel('الرقية الشرعية الكاملة'),
                              style: rText(
                                context,
                                15,
                                weight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              context.religiousLabel(
                                'استمع إلى الآيات المختارة\nمن القرآن الكريم',
                              ),
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
                context.religiousLabel('الأقسام'),
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
                        color: rAccent(context),
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
                      Icon(
                        Icons.chevron_left,
                        size: 18,
                        color: rAccent(context),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                context.religiousLabel('آخر ما استمعت إليه'),
                style: rText(context, 16, weight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (recent.isEmpty)
                ReligiousEmpty(
                  text: context.religiousLabel(
                    'ابدأ الاستماع لتظهر هنا المقاطع الأخيرة',
                  ),
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
                        if (host.controller.hasAudio(queued))
                          ReligiousRoundButton(
                            icon: Icons.play_arrow,
                            label: context.religiousLabel(
                              'تشغيل قائمة الاستماع',
                            ),
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
                        if (host.controller.hasAudio(item))
                          ReligiousRoundButton(
                            icon: Icons.play_arrow,
                            label: context.religiousLabel('استئناف الاستماع'),
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
