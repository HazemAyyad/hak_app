part of 'main.dart';

class _HomeSearchPage extends StatefulWidget {
  const _HomeSearchPage({
    required this.quran,
    required this.religious,
    this.initialQuery = '',
  });
  final String initialQuery;
  final QuranController quran;
  final ReligiousController religious;
  @override
  State<_HomeSearchPage> createState() => _HomeSearchPageState();
}

class _HomeSearchPageState extends State<_HomeSearchPage> {
  late String query;
  late TextEditingController text;
  @override
  void initState() {
    super.initState();
    query = widget.initialQuery;
    text = TextEditingController(text: query);
    widget.quran.addListener(_refresh);
    widget.religious.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.quran.removeListener(_refresh);
    widget.religious.removeListener(_refresh);
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = normalizeQuranSearch(query);
    final features = AppFeature.values
        .where(
          (f) =>
              normalizeQuranSearch(f.title).contains(needle) ||
              normalizeQuranSearch(f.localizedTitle(context)).contains(needle),
        )
        .toList();
    final verses = needle.isEmpty
        ? <QuranVerse>[]
        : (widget.quran.repository?.search(query).take(20).toList() ??
              <QuranVerse>[]);
    final items = needle.isEmpty
        ? <ReligiousItem>[]
        : (widget.religious.catalog?.search(query: query).take(20).toList() ??
              <ReligiousItem>[]);
    final surahs = needle.isEmpty
        ? <QuranSurah>[]
        : (widget.quran.repository?.surahs
                  .where(
                    (s) =>
                        normalizeQuranSearch(s.name).contains(needle) ||
                        normalizeQuranSearch(
                          s.localizedName(context),
                        ).contains(needle),
                  )
                  .toList() ??
              <QuranSurah>[]);
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: AppPalette.of(context).background,
        appBar: AppBar(title: Text(context.homeLabel('البحث في حق'))),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const ValueKey('haq-global-search'),
                controller: text,
                textDirection: contentTextDirection(query),
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.homeLabel('ابحث عن خدمة أو آية أو محتوى…'),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (features.isNotEmpty)
                    ListTile(title: Text(context.homeLabel('خدمات حق'))),
                  for (final f in features)
                    ListTile(
                      key: ValueKey('search-feature-${f.name}'),
                      leading: Icon(f.icon),
                      title: Text(f.localizedTitle(context)),
                      onTap: () => Navigator.pop(context, f),
                    ),
                  for (final surah in surahs)
                    ListTile(
                      title: Text(surah.localizedTitle(context)),
                      onTap: () => Navigator.pop(
                        context,
                        widget.quran.repository!.byKey['${surah.id}:1'],
                      ),
                    ),
                  if (verses.isNotEmpty)
                    ListTile(title: Text(context.homeLabel('القرآن الكريم'))),
                  for (final v in verses)
                    ListTile(
                      title: Text(
                        v.text,
                        textDirection: TextDirection.rtl,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        quranVerseTitle(
                          context,
                          widget.quran.repository!.surah(v.surah),
                          v.ayah,
                        ),
                      ),
                      onTap: () => Navigator.pop(context, v),
                    ),
                  if (items.isNotEmpty)
                    ListTile(title: Text(context.homeLabel('المحتوى الديني'))),
                  for (final item in items)
                    ListTile(
                      title: Text(
                        item.title,
                        textDirection: contentTextDirection(item.title),
                      ),
                      subtitle: Text(
                        item.text,
                        textDirection: contentTextDirection(item.text),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(context, item),
                    ),
                  if (features.isEmpty &&
                      verses.isEmpty &&
                      items.isEmpty &&
                      surahs.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(30),
                      child: Text(
                        context.homeLabel('لا توجد نتائج تطابق بحثك'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Home topics display the bundled Quran text and link to its sourced tafsir.
class _HomeArticlePage extends StatelessWidget {
  const _HomeArticlePage({
    required this.title,
    required this.verse,
    required this.surah,
  });
  final String title, surah;
  final QuranVerse verse;
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: Directionality.of(context),
    child: Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            context.homeLabel('من القرآن الكريم'),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          _Surface(
            child: Text(
              verse.text,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'AmiriQuran',
                fontSize: 24,
                height: 2,
                color: AppPalette.of(context).heading,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr(
              'search.verse',
              args: {
                'name': context.tr(
                  'quran.surah.${verse.surah}',
                  fallback: surah,
                ),
                'ayah': quranNumber(context, verse.ayah),
              },
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            context.homeLabel(
              'تأمّل الآية، واقرأ معناها من مصدر التفسير المتاح في قارئ القرآن.',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(context.homeLabel('قراءة التفسير')),
          ),
        ],
      ),
    ),
  );
}
