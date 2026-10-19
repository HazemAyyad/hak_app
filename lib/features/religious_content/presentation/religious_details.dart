part of 'religious_host.dart';

class _ReligiousDetailsPage extends StatefulWidget {
  const _ReligiousDetailsPage({required this.host, required this.item});
  final ReligiousHostState host;
  final ReligiousItem item;
  @override
  State<_ReligiousDetailsPage> createState() => _ReligiousDetailsPageState();
}

class _ReligiousDetailsPageState extends State<_ReligiousDetailsPage> {
  ReligiousHostState get host => widget.host;
  ReligiousItem get item => widget.item;
  String get fontPreference => 'religious.fontSize.${item.type}';
  late double fontSize =
      host.controller.quran.preferences!.getDouble(fontPreference) ??
      (item.type == 'hadith' ? 18 : 22);
  late Future<TafsirText>? explanation =
      item.type == 'quran' && item.verseKeys.isNotEmpty
      ? host.controller.quran.content.tafsir(item.verseKeys.first, 91)
      : null;
  void fontSheet() => showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: StatefulBuilder(
        builder: (context, update) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'حجم خط القراءة',
                style: rText(context, 16, weight: FontWeight.w800),
              ),
              Slider(
                min: 14,
                max: 34,
                value: fontSize,
                divisions: 10,
                label: fontSize.round().toString(),
                onChanged: (v) {
                  setState(() => fontSize = v);
                  update(() {});
                  host.controller.quran.preferences!.setDouble(
                    fontPreference,
                    v,
                  );
                },
              ),
              Text(
                item.title,
                textAlign: TextAlign.center,
                style: rText(context, fontSize),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: host.controller,
    builder: (context, _) {
      final name = item.type == 'name';
      final quran = item.type == 'quran';
      final saved = host.controller.favorites.contains(item.id);
      final sections = item.sections;
      final narrationBreak = item.type == 'hadith'
          ? item.text.indexOf('يقول:')
          : -1;
      final narration = narrationBreak < 0
          ? null
          : item.text.substring(0, narrationBreak + 5);
      final mainText = narrationBreak < 0
          ? item.text
          : item.text.substring(narrationBreak + 5).trim();
      return ListView(
        padding: EdgeInsets.zero,
        key: PageStorageKey('religious-details-${item.id}'),
        children: [
          ReligiousHeader(
            title: item.title,
            subtitle: name
                ? 'من أسماء الله الحسنى'
                : quran
                ? item.source
                : item.categories.contains('nawawi')
                ? 'الحديث ${item.number} من الأربعين النووية'
                : host.catalog.byCategory[item.categories.first]?.title ?? '',
            breadcrumb: quran
                ? 'الأدعية والمحتوى الديني  ‹  ${item.categories.first == 'quran-duas' ? 'الأدعية القرآنية' : 'الرقية الشرعية'}'
                : item.categories.contains('nawawi')
                ? 'الأربعون النووية  ‹  الحديث ${item.number}'
                : null,
            image: quran
                ? 'quran'
                : name || item.categories.contains('nawawi')
                ? 'reading'
                : item.id == 'hisn-001'
                ? 'sleep'
                : 'sunnah',
            onBack: host.back,
            onSaved: () => host.controller.toggleFavorite(item.id),
            onShare: () => host.share(context, item),
            tall: quran,
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
                ReligiousCard(
                  ornament: quran,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!quran && !name)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: ReligiousColors(context).subtle,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.menu_book_outlined,
                                color: rGold,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              item.type == 'sunnah'
                                  ? 'نص السنة'
                                  : item.type == 'hadith'
                                  ? 'نص الحديث'
                                  : 'نص الدعاء',
                              style: rText(
                                context,
                                14,
                                weight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      if (narration != null)
                        Text(
                          narration,
                          textAlign: TextAlign.right,
                          style: rText(
                            context,
                            13,
                            color: ReligiousColors(context).text,
                            height: 1.7,
                          ),
                        ),
                      SelectableText(
                        mainText,
                        textAlign: name || quran
                            ? TextAlign.center
                            : TextAlign.right,
                        style: TextStyle(
                          fontFamily: 'AmiriQuran',
                          fontSize: name ? 42 : fontSize,
                          color: ReligiousColors(context).heading,
                          height: name
                              ? 1.8
                              : item.type == 'hadith'
                              ? 1.7
                              : 2,
                        ),
                      ),
                      if (name && item.transliteration.isNotEmpty)
                        Text(
                          item.transliteration,
                          textAlign: TextAlign.center,
                          style: rText(context, 11),
                        ),
                      if (name)
                        Text(
                          item.summary,
                          textAlign: TextAlign.center,
                          style: rText(context, 14),
                        ),
                      if (!name)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            item.source,
                            textAlign: TextAlign.center,
                            style: rText(
                              context,
                              10,
                              color: ReligiousColors(context).muted,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 65,
                              height: .5,
                              color: rGold.withValues(alpha: .3),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 5),
                              child: Icon(
                                Icons.diamond_outlined,
                                color: rGold,
                                size: 9,
                              ),
                            ),
                            Container(
                              width: 65,
                              height: .5,
                              color: rGold.withValues(alpha: .3),
                            ),
                          ],
                        ),
                      ),
                      Wrap(
                        alignment: WrapAlignment.spaceEvenly,
                        spacing: 7,
                        runSpacing: 5,
                        children: [
                          _detailAction(
                            context,
                            saved ? Icons.bookmark : Icons.bookmark_border,
                            'المفضلة',
                            () => host.controller.toggleFavorite(item.id),
                          ),
                          _detailAction(
                            context,
                            Icons.text_fields,
                            'حجم الخط',
                            fontSheet,
                          ),
                          _detailAction(
                            context,
                            Icons.copy_outlined,
                            'نسخ',
                            () => host.copy(context, item),
                          ),
                          _detailAction(
                            context,
                            Icons.share_outlined,
                            'مشاركة',
                            () => host.share(context, item),
                          ),
                          _detailAction(
                            context,
                            Icons.play_arrow,
                            'استماع',
                            () => host.play(context, item),
                            filled: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (host.controller.activeItem == item.id)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ReligiousPlayer(host: host, compact: true),
                  ),
                if (quran) ...[
                  FutureBuilder<TafsirText>(
                    future: explanation,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return ReligiousSectionCard(
                          title: 'تفسير الآية',
                          text: snapshot.data!.text,
                          source: snapshot.data!.title,
                        );
                      }
                      return ReligiousCard(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'تفسير الآية',
                              style: rText(
                                context,
                                14,
                                weight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              snapshot.hasError
                                  ? 'التفسير غير متاح دون اتصال؛ يمكنك إعادة المحاولة من صفحة التفسير.'
                                  : 'جارٍ تحميل التفسير من المصدر...',
                              style: rText(
                                context,
                                13,
                                color: ReligiousColors(context).text,
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  host.openQuran(item, tafsir: true),
                              child: const Text('عرض التفسير'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  ReligiousSectionCard(
                    title: 'مواضع ورد فيها',
                    text: item.source,
                    icon: Icons.auto_stories_outlined,
                  ),
                  OutlinedButton.icon(
                    onPressed: () => host.openQuran(item),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('عرض في المصحف'),
                  ),
                ],
                for (final section in sections)
                  if (section.title == 'الشرح المطول' ||
                      section.title == 'التخريج')
                    ReligiousCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: EdgeInsets.zero,
                      child: ExpansionTile(
                        title: Text(
                          section.title,
                          style: rText(context, 14, weight: FontWeight.w800),
                        ),
                        childrenPadding: const EdgeInsets.all(12),
                        children: [
                          SelectableText(
                            section.text,
                            style: rText(
                              context,
                              13,
                              color: ReligiousColors(context).text,
                            ),
                          ),
                          if (section.source != null)
                            Text(section.source!, style: rText(context, 9)),
                        ],
                      ),
                    )
                  else
                    ReligiousSectionCard(
                      title: section.title,
                      text: section.text,
                      source: section.source?.startsWith('فوائد موجزة') == true
                          ? null
                          : section.source,
                      icon: section.title.contains('وقت')
                          ? Icons.schedule
                          : section.title.contains('تطبيق')
                          ? Icons.settings_outlined
                          : section.title.contains('فوائد')
                          ? Icons.spa_outlined
                          : Icons.menu_book_outlined,
                    ),
                if (item.type == 'dua')
                  ReligiousSectionCard(title: 'المصدر', text: item.source),
                if (name && item.related.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'أسماء ذات صلة',
                    style: rText(context, 14, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final id in item.related)
                        if (host.catalog.byId[id] case final related?)
                          ActionChip(
                            label: Text(
                              related.title,
                              style: rText(context, 14),
                            ),
                            onPressed: () => host.openItem(related),
                          ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: rTeal,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    if (['dua', 'quran'].contains(item.type)) {
                      host.controller.toggleAdhkar(item.id);
                    } else {
                      host.controller.toggleFavorite(item.id);
                    }
                  },
                  icon: Icon(
                    ['dua', 'quran'].contains(item.type)
                        ? Icons.front_hand_outlined
                        : Icons.bookmark_border,
                    size: 20,
                  ),
                  label: Text(
                    ['dua', 'quran'].contains(item.type)
                        ? host.controller.customAdhkar.contains(item.id)
                              ? 'إزالة من أذكاري'
                              : 'حفظ الدعاء في أذكاري'
                        : saved
                        ? 'إزالة من المفضلة'
                        : 'إضافة إلى المفضلة',
                    style: rText(
                      context,
                      14,
                      color: Colors.white,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
  Widget _detailAction(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool filled = false,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ReligiousRoundButton(
        icon: icon,
        label: label,
        onTap: onTap,
        size: 34,
        filled: filled,
      ),
      Text(label, style: rText(context, 10)),
    ],
  );
}

class _ReligiousListeningPage extends StatefulWidget {
  const _ReligiousListeningPage({required this.host, required this.item});
  final ReligiousHostState host;
  final ReligiousItem item;
  @override
  State<_ReligiousListeningPage> createState() =>
      _ReligiousListeningPageState();
}

class _ReligiousListeningPageState extends State<_ReligiousListeningPage> {
  int tab = 0;
  ReligiousHostState get host => widget.host;
  ReligiousItem get item => widget.item;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      host.controller,
      host.controller.media,
      host.controller.media.downloads,
    ]),
    builder: (context, _) {
      final parts = [for (final id in item.related) ?host.catalog.byId[id]];
      final downloads = host.controller.media.downloads;
      return ListView(
        padding: EdgeInsets.zero,
        key: const PageStorageKey('religious-listening'),
        children: [
          ReligiousHeader(
            title: item.title,
            subtitle:
                'مجموعة من الآيات والأدعية المأثورة\nللشفاء والحفظ بإذن الله',
            image: 'ruqya',
            onBack: host.back,
            onSaved: () => host.controller.toggleFavorite(item.id),
            onShare: () => host.share(context, item),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 105),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    for (final (i, title) in [
                      'الاستماع',
                      'القراءة',
                      'معلومات',
                    ].indexed)
                      Expanded(
                        child: ReligiousPill(
                          text: title,
                          selected: tab == i,
                          onTap: () => setState(() => tab = i),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (tab == 0) ...[
                  ReligiousCard(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: rText(
                                      context,
                                      15,
                                      weight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    host.controller.media.current?.reciter ??
                                        'تلاوة الآيات المختارة',
                                    style: rText(context, 11),
                                  ),
                                ],
                              ),
                            ),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: Image.asset(
                                rAsset('mosque'),
                                width: 62,
                                height: 65,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ],
                        ),
                        if (host.controller.media.current == null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: rTeal,
                              ),
                              onPressed: () => host.play(context, item),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('بدء الاستماع'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ReligiousPlayer(host: host),
                  const SizedBox(height: 16),
                  Text(
                    'محتويات الرقية',
                    style: rText(context, 15, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  for (final (index, part) in parts.indexed)
                    ReligiousCard(
                      margin: const EdgeInsets.only(bottom: 7),
                      onTap: () => host.openItem(part),
                      child: Row(
                        children: [
                          Text(
                            '${index + 1}',
                            style: rText(context, 11, color: rGold),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  part.title,
                                  style: rText(
                                    context,
                                    13,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  part.source,
                                  style: rText(
                                    context,
                                    9,
                                    color: ReligiousColors(context).muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ReligiousRoundButton(
                            icon: Icons.play_arrow,
                            label: 'تشغيل ${part.title}',
                            onTap: () => host.play(context, part),
                            filled: true,
                            size: 28,
                          ),
                          const Icon(Icons.expand_more, color: rTeal, size: 18),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: rTeal),
                    onPressed: () async {
                      await host.controller.download(item);
                      if (context.mounted) {
                        host.message(
                          context,
                          host.controller.error ??
                              'أضيفت الملفات إلى قائمة التنزيل',
                        );
                      }
                    },
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('تحميل الرقية كاملة'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => host.controller.toggleQueue(item.id),
                    icon: const Icon(Icons.playlist_add),
                    label: Text(
                      host.controller.listeningQueue.contains(item.id)
                          ? 'إزالة من قائمة الاستماع'
                          : 'إضافة إلى قائمة الاستماع',
                    ),
                  ),
                  for (final entry in downloads.entries.values.where(
                    (d) => host.controller
                        .tracks(item)
                        .any((t) => t.id == d.track.id),
                  ))
                    ListTile(
                      dense: true,
                      title: Text(entry.track.title, style: rText(context, 11)),
                      subtitle: Text(
                        entry.error ??
                            const {
                              'queued': 'في الانتظار',
                              'downloading': 'جارٍ التحميل',
                              'paused': 'متوقف مؤقتًا',
                              'failed': 'تعذّر التنزيل',
                              'complete': 'تم التنزيل',
                            }[entry.state.name]!,
                        style: rText(context, 9),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (entry.total > 0)
                            Text(
                              '${(entry.received / entry.total * 100).round()}%',
                            ),
                          if (entry.state.name != 'complete')
                            IconButton(
                              tooltip: entry.state.name == 'downloading'
                                  ? 'إيقاف مؤقت'
                                  : 'إعادة المحاولة',
                              icon: Icon(
                                entry.state.name == 'downloading'
                                    ? Icons.pause
                                    : Icons.refresh,
                              ),
                              onPressed: () => entry.state.name == 'downloading'
                                  ? downloads.pause(entry.track.id)
                                  : downloads.enqueue(entry.track),
                            ),
                          IconButton(
                            tooltip: 'إزالة التنزيل',
                            icon: const Icon(Icons.close),
                            onPressed: () => downloads.remove(entry.track.id),
                          ),
                        ],
                      ),
                    ),
                ] else if (tab == 1) ...[
                  for (final part in parts)
                    ReligiousSectionCard(
                      title: part.title,
                      text: part.text,
                      source: part.source,
                    ),
                ] else ...[
                  ReligiousSectionCard(
                    title: 'مصدر المحتوى',
                    text: item.source,
                  ),
                  for (final section in item.sections)
                    ReligiousSectionCard(
                      title: section.title,
                      text: section.text,
                      source: section.source,
                    ),
                ],
              ],
            ),
          ),
        ],
      );
    },
  );
}
