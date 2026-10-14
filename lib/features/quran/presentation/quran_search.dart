import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_appearance.dart';
import '../data/quran_controller.dart';
import '../data/quran_repository.dart';
import 'quran_widgets.dart';

class QuranSearchPage extends StatefulWidget {
  const QuranSearchPage({
    super.key,
    required this.controller,
    required this.onRead,
    this.initialQuery = '',
  });
  final QuranController controller;
  final void Function(QuranVerse, String) onRead;
  final String initialQuery;
  @override
  State<QuranSearchPage> createState() => _QuranSearchPageState();
}

class _QuranSearchPageState extends State<QuranSearchPage> {
  late final TextEditingController query;
  final scroll = ScrollController();
  Timer? debounce;
  int? surahId, juzId;
  bool group = true, fullText = true;
  List<QuranVerse> results = [];
  String executedQuery = '';

  @override
  void initState() {
    super.initState();
    query = TextEditingController(text: widget.initialQuery);
    _search();
  }

  @override
  void dispose() {
    debounce?.cancel();
    query.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _search() {
    debounce?.cancel();
    setState(() {
      executedQuery = query.text.trim();
      results = widget.controller.repository!.search(
        executedQuery,
        surahId: surahId,
        juzId: juzId,
      );
    });
  }

  void _changed(String _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), _search);
  }

  Future<void> _filters() async {
    var scope = surahId != null
        ? 1
        : juzId != null
        ? 2
        : 0;
    var surah = surahId ?? 1;
    var juz = juzId ?? 1;
    var grouped = group;
    var full = fullText;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).surface,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'تصفية نتائج البحث',
                  style: qText(
                    context,
                    size: 21,
                    weight: FontWeight.w800,
                    color: AppPalette.of(context).tealHeading,
                  ),
                ),
                Text(
                  'حدد معايير البحث لعرض نتائج أكثر دقة',
                  style: qText(context, size: 12),
                ),
                const SizedBox(height: 20),
                QCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'نطاق البحث',
                        style: qText(
                          context,
                          size: 17,
                          weight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      QSegments(
                        labels: const ['كل القرآن', 'سورة محددة', 'جزء محدد'],
                        selected: scope,
                        onSelect: (value) => update(() => scope = value),
                      ),
                    ],
                  ),
                ),
                if (scope == 1) ...[
                  const SizedBox(height: 12),
                  QCard(
                    child: DropdownButtonFormField<int>(
                      initialValue: surah,
                      decoration: InputDecoration(
                        labelText: 'اختر السورة',
                        labelStyle: qText(context, size: 12),
                      ),
                      items: widget.controller.repository!.surahs
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.id,
                              child: Text('سورة ${s.name}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => update(() => surah = value!),
                    ),
                  ),
                ],
                if (scope == 2) ...[
                  const SizedBox(height: 12),
                  QCard(
                    child: DropdownButtonFormField<int>(
                      initialValue: juz,
                      decoration: InputDecoration(
                        labelText: 'اختر الجزء',
                        labelStyle: qText(context, size: 12),
                      ),
                      items: widget.controller.repository!.juzs
                          .map(
                            (j) => DropdownMenuItem(
                              value: j.id,
                              child: Text(juzName(j.id)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => update(() => juz = value!),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                QCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'خيارات إضافية',
                        style: qText(
                          context,
                          size: 17,
                          weight: FontWeight.w800,
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: qTeal,
                        title: Text(
                          'تجميع النتائج حسب السور',
                          style: qText(context, size: 12),
                        ),
                        value: grouped,
                        onChanged: (value) => update(() => grouped = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: qTeal,
                        title: Text(
                          'عرض نص الآية بالكامل',
                          style: qText(context, size: 12),
                        ),
                        value: full,
                        onChanged: (value) => update(() => full = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: QPrimaryButton(
                        label: 'عرض النتائج',
                        icon: Icons.search,
                        onTap: () => Navigator.pop(context, true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton.icon(
                      onPressed: () => update(() {
                        scope = 0;
                        grouped = true;
                        full = true;
                      }),
                      icon: const Icon(Icons.restart_alt, color: qGold),
                      label: Text(
                        'إعادة الضبط',
                        style: qText(context, color: qGold, size: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied != true || !mounted) return;
    surahId = scope == 1 ? surah : null;
    juzId = scope == 2 ? juz : null;
    group = grouped;
    fullText = full;
    _search();
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.controller.repository!;
    return CustomScrollView(
      controller: scroll,
      slivers: [
        SliverToBoxAdapter(
          child: QuranHeader(
            title: 'البحث في القرآن الكريم',
            subtitle: 'ابحث في آيات القرآن الكريم',
            dark: true,
            height: 164,
            onBack: () => Navigator.pop(context),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                QSearchField(
                  controller: query,
                  hint: 'ابحث بكلمة أو عبارة ...',
                  onChanged: _changed,
                  onSubmit: (_) => _search(),
                  trailing: IconButton(
                    tooltip: 'تصفية نتائج البحث',
                    icon: const Icon(Icons.tune, color: qTeal),
                    onPressed: _filters,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        executedQuery.isEmpty
                            ? 'البحث يعمل دون إنترنت'
                            : 'نتائج البحث: ${results.length}',
                        style: qText(
                          context,
                          size: 12,
                          color: AppPalette.of(context).muted,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _filters,
                      icon: const Icon(Icons.filter_alt_outlined, size: 17),
                      label: Text(
                        surahId != null
                            ? 'سورة ${repo.surah(surahId!).name}'
                            : juzId != null
                            ? juzName(juzId!)
                            : 'كل القرآن',
                        style: qText(context, size: 11, color: qTeal),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (executedQuery.isNotEmpty && results.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 35),
              child: QCard(
                child: Column(
                  children: [
                    const Icon(Icons.search_off, size: 66, color: qGold),
                    const SizedBox(height: 12),
                    Text(
                      'لا توجد نتائج بحث',
                      style: qText(context, size: 22, weight: FontWeight.w800),
                    ),
                    Text(
                      'جرّب كلمة أخرى أو أعد ضبط نطاق البحث',
                      textAlign: TextAlign.center,
                      style: qText(
                        context,
                        size: 13,
                        color: AppPalette.of(context).muted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    QPrimaryButton(
                      label: 'إعادة ضبط التصفية',
                      onTap: () {
                        surahId = null;
                        juzId = null;
                        _search();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 105),
          sliver: SliverList.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final verse = results[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (group &&
                      (index == 0 || results[index - 1].surah != verse.surah))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'سورة ${repo.surah(verse.surah).name}',
                        style: qText(
                          context,
                          size: 17,
                          weight: FontWeight.w800,
                          color: AppPalette.of(context).tealHeading,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: QCard(
                      onTap: () {
                        debounce?.cancel();
                        widget.onRead(verse, executedQuery);
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.chevron_right, color: qTeal),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'سورة ${repo.surah(verse.surah).name} • الآية ${verse.ayah}',
                                  style: qText(
                                    context,
                                    size: 12,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  verse.text,
                                  maxLines: fullText ? null : 3,
                                  overflow: fullText
                                      ? null
                                      : TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'AmiriQuran',
                                    fontSize: 20,
                                    height: 1.8,
                                    color: AppPalette.of(context).heading,
                                  ),
                                ),
                                Text(
                                  '${juzName(verse.juz)} • الصفحة ${verse.page}',
                                  style: qText(
                                    context,
                                    size: 10,
                                    color: AppPalette.of(context).muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          QMedallion(number: verse.ayah, size: 36),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
