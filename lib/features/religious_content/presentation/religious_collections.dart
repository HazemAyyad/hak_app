part of 'religious_host.dart';

class _RamadanDaysPage extends StatelessWidget {
  const _RamadanDaysPage({required this.host});
  final ReligiousHostState host;
  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.zero,
    children: [
      ReligiousHeader(
        title: context.religiousLabel('الأدعية الرمضانية'),
        subtitle: context.religiousLabel('القرآن والدعاء في أيام الشهر'),
        image: 'medina',
        light: true,
        onBack: host.back,
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          host.catalog.ramadanDaysNote,
          textDirection: contentTextDirection(host.catalog.ramadanDaysNote),
          style: rText(context, 12, color: ReligiousColors(context).muted),
        ),
      ),
      for (var day = 1; day <= 30; day++)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: ReligiousCard(
            onTap: host.catalog.byId.containsKey(host.catalog.ramadanDays[day])
                ? () => host.openItem(
                    host.catalog.byId[host.catalog.ramadanDays[day]]!,
                  )
                : null,
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).paleTeal,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    religiousNumber(context, day),
                    style: rText(context, 20, weight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(
                          'religious.day',
                          args: {'day': religiousNumber(context, day)},
                        ),
                        style: rText(context, 14, weight: FontWeight.w800),
                      ),
                      Text(
                        host
                                .catalog
                                .byId[host.catalog.ramadanDays[day]]
                                ?.title ??
                            context.religiousLabel(
                              'لا يوجد مقترح منشور لهذا اليوم',
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: rText(context, 12),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_left,
                  textDirection: TextDirection.ltr,
                  color: rAccent(context),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 110),
    ],
  );
}

class _HadithLibraryPage extends StatefulWidget {
  const _HadithLibraryPage({required this.host});
  final ReligiousHostState host;
  @override
  State<_HadithLibraryPage> createState() => _HadithLibraryPageState();
}

class _HadithLibraryPageState extends State<_HadithLibraryPage> {
  final _search = TextEditingController();
  String _category = 'hadith';
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _sources() => showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (context) => AlertDialog(
      title: Text(context.religiousLabel('مصادر مكتبة الحديث')),
      content: SingleChildScrollView(
        child: SelectableText(context.tr('religious.hadithSources')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.religiousLabel('إغلاق')),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final host = widget.host,
        items = widget.host.catalog.search(
          category: _category,
          query: _search.text,
        );
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ReligiousHeader(
          title: context.religiousLabel('الأحاديث النبوية'),
          subtitle: context.religiousLabel('المتن والشرح والمصدر'),
          image: 'reading',
          onBack: host.back,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ReligiousSearch(
                      controller: _search,
                      hint: context.religiousLabel('ابحث في الأحاديث…'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    onPressed: _sources,
                    icon: const Icon(Icons.info_outline),
                    tooltip: context.religiousLabel('مصدر الأحاديث'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ReligiousPill(
                      text: context.tr(
                        'religious.allCount',
                        args: {
                          'count': religiousNumber(
                            context,
                            host.catalog.search(category: 'hadith').length,
                          ),
                        },
                      ),
                      selected: _category == 'hadith',
                      onTap: () => setState(() => _category = 'hadith'),
                    ),
                    for (final category in host.catalog.children('hadith'))
                      ReligiousPill(
                        text: context.tr(
                          'religious.categoryCount',
                          args: {
                            'title': category.interfaceTitle(context),
                            'count': religiousNumber(
                              context,
                              host.catalog.search(category: category.id).length,
                            ),
                          },
                        ),
                        selected: _category == category.id,
                        onTap: () => setState(() => _category = category.id),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                ReligiousEmpty(
                  text: context.religiousLabel('لا توجد أحاديث مطابقة'),
                  icon: Icons.search_off,
                ),
              for (final item in items)
                ReligiousCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  onTap: () => host._push(
                    _ReligiousDetailsPage(
                      host: host,
                      item: item,
                      hadithTabs: true,
                    ),
                    '/religious/hadith/${item.id}',
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppPalette.of(context).notice,
                        child: Text(
                          religiousNumber(
                            context,
                            item.number > 0
                                ? item.number
                                : items.indexOf(item) + 1,
                          ),
                          style: rText(context, 14),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              textDirection: contentTextDirection(item.title),
                              style: rText(
                                context,
                                15,
                                weight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.source,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: rText(
                                context,
                                10,
                                color: ReligiousColors(context).muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_left,
                        textDirection: TextDirection.ltr,
                        color: rAccent(context),
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
