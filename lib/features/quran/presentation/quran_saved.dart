import 'package:flutter/material.dart';

import '../../../app_appearance.dart';
import '../data/quran_controller.dart';
import '../data/quran_repository.dart';
import 'quran_widgets.dart';

class QuranSavedPage extends StatefulWidget {
  const QuranSavedPage({
    super.key,
    required this.controller,
    required this.onRead,
    this.initialBookmarks = false,
  });
  final QuranController controller;
  final ValueChanged<QuranVerse> onRead;
  final bool initialBookmarks;
  @override
  State<QuranSavedPage> createState() => _QuranSavedPageState();
}

class _QuranSavedPageState extends State<QuranSavedPage> {
  late int tab;
  bool newest = true;
  String query = '';
  int? surah;
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    tab = widget.initialBookmarks ? 1 : 0;
  }

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
      final saved = tab == 0
          ? widget.controller.favorites
          : widget.controller.bookmarks;
      final entries =
          saved.entries.where((entry) {
            final verse = repo.byKey[entry.key]!;
            return (surah == null || verse.surah == surah) &&
                (verse.searchText.contains(normalizeQuranSearch(query)) ||
                    normalizeQuranSearch(
                      repo.surah(verse.surah).name,
                    ).contains(normalizeQuranSearch(query)));
          }).toList()..sort(
            (a, b) => newest
                ? b.value.compareTo(a.value)
                : a.value.compareTo(b.value),
          );
      return CustomScrollView(
        controller: scroll,
        slivers: [
          SliverToBoxAdapter(
            child: QuranHeader(
              title: 'المفضلة والعلامات',
              subtitle: 'احفظ الآيات والمواضع التي تهمك',
              height: 150,
              onBack: () => Navigator.pop(context),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  QSegments(
                    labels: const ['المفضلة', 'العلامات المرجعية'],
                    selected: tab,
                    onSelect: (value) => setState(() => tab = value),
                  ),
                  const SizedBox(height: 12),
                  QSearchField(
                    hint: 'ابحث في المحفوظات ...',
                    onChanged: (value) => setState(() => query = value),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() => newest = !newest),
                        icon: const Icon(Icons.sort, color: qNavy, size: 18),
                        label: Text(
                          'الترتيب: ${newest ? 'الأحدث' : 'الأقدم'}',
                          style: qText(context, size: 11),
                        ),
                      ),
                      const Spacer(),
                      PopupMenuButton<int>(
                        onSelected: (value) =>
                            setState(() => surah = value == 0 ? null : value),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 0,
                            child: Text('كل السور'),
                          ),
                          ...repo.surahs.map(
                            (s) => PopupMenuItem(
                              value: s.id,
                              child: Text('سورة ${s.name}'),
                            ),
                          ),
                        ],
                        child: Row(
                          children: [
                            Text(
                              surah == null
                                  ? 'كل السور'
                                  : 'سورة ${repo.surah(surah!).name}',
                              style: qText(context, size: 11),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.filter_alt_outlined,
                              color: qNavy,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (entries.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  children: [
                    Icon(
                      tab == 0 ? Icons.favorite_border : Icons.bookmark_outline,
                      size: 55,
                      color: qGold,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'لا توجد آيات محفوظة هنا',
                      style: qText(context, size: 18, weight: FontWeight.w800),
                    ),
                    Text(
                      'احفظ آية من خياراتها أثناء القراءة',
                      style: qText(
                        context,
                        size: 12,
                        color: AppPalette.of(context).muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 105),
            sliver: SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final verse = repo.byKey[entry.key]!;
                final date = DateTime.tryParse(entry.value)?.toLocal();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: QCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    onTap: () => widget.onRead(verse),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Icon(
                              tab == 0 ? Icons.favorite : Icons.bookmark,
                              color: qTeal,
                              size: 20,
                            ),
                            const SizedBox(height: 8),
                            const Icon(Icons.chevron_right, color: qNavy),
                          ],
                        ),
                        const SizedBox(width: 8),
                        QMedallion(number: verse.ayah, size: 32),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'سورة ${repo.surah(verse.surah).name}',
                                style: qText(
                                  context,
                                  size: 14,
                                  weight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                verse.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'AmiriQuran',
                                  fontSize: 19,
                                  height: 1.55,
                                  color: AppPalette.of(context).heading,
                                ),
                              ),
                              if (date != null)
                                Text(
                                  'تم الحفظ في ${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}',
                                  style: qText(
                                    context,
                                    size: 10,
                                    color: AppPalette.of(context).muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          iconSize: 20,
                          tooltip: 'خيارات المحفوظ',
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'remove',
                              child: Text(
                                tab == 0 ? 'إزالة من المفضلة' : 'إزالة العلامة',
                              ),
                            ),
                          ],
                          onSelected: (_) => tab == 0
                              ? widget.controller.toggleFavorite(verse.key)
                              : widget.controller.toggleBookmark(verse.key),
                        ),
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
