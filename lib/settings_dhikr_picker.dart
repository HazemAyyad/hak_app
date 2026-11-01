part of 'settings_pages.dart';

String _dhikrSearch(String value) => value
    .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .trim();

class _DhikrContentPicker extends StatefulWidget {
  const _DhikrContentPicker({required this.content, required this.initial});
  final Map<String, String> content;
  final List<String> initial;
  @override
  State<_DhikrContentPicker> createState() => _DhikrContentPickerState();
}

class _DhikrContentPickerState extends State<_DhikrContentPicker> {
  late final selected = widget.initial.toSet();
  final search = TextEditingController();
  late final entries = widget.content.entries.toList();
  late final normalized = {
    for (final e in entries) e.key: _dhikrSearch(e.value),
  };
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _dhikrSearch(search.text);
    final shown = entries
        .where((e) => normalized[e.key]!.contains(query))
        .toList();
    final allSelected =
        shown.isNotEmpty && shown.every((e) => selected.contains(e.key));
    final palette = AppPalette.of(context);
    return Dialog(
      key: const ValueKey('dhikr-content-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 720,
        height:
            (MediaQuery.sizeOf(context).height * .9 -
                    MediaQuery.viewInsetsOf(context).bottom)
                .clamp(240, 1000),
        child: Directionality(
          textDirection: Directionality.of(context),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.settingsLabel('محتوى التنبيهات'),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: palette.heading,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.settingsLabel('إلغاء الاختيار'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  key: const ValueKey('dhikr-content-search'),
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: context.settingsLabel('ابحث في الأذكار'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: context.settingsLabel('مسح البحث'),
                            onPressed: () => setState(search.clear),
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      context.tr(
                        'settings.selectionCount',
                        args: {
                          'selected':
                              LocalizationScope.maybeOf(
                                context,
                              )?.formats.integer(selected.length) ??
                              selected.length,
                          'total':
                              LocalizationScope.maybeOf(
                                context,
                              )?.formats.integer(entries.length) ??
                              entries.length,
                        },
                      ),
                      key: const ValueKey('dhikr-selection-count'),
                    ),
                    TextButton.icon(
                      key: const ValueKey('dhikr-select-all'),
                      icon: Icon(
                        allSelected ? Icons.deselect : Icons.select_all,
                      ),
                      label: Text(
                        allSelected
                            ? (query.isEmpty
                                  ? context.settingsLabel('إلغاء تحديد الكل')
                                  : context.settingsLabel(
                                      'إلغاء تحديد النتائج',
                                    ))
                            : (query.isEmpty
                                  ? context.settingsLabel('تحديد الكل')
                                  : context.settingsLabel('تحديد كل النتائج')),
                      ),
                      onPressed: shown.isEmpty
                          ? null
                          : () => setState(() {
                              if (allSelected) {
                                selected.removeAll(shown.map((e) => e.key));
                              } else {
                                selected.addAll(
                                  shown
                                      .map((e) => e.key)
                                      .where((id) => !selected.contains(id))
                                      .take(
                                        AppSettings.maxContent -
                                            selected.length,
                                      ),
                                );
                              }
                            }),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Text(
                          context.settingsLabel('لا توجد أذكار تطابق البحث'),
                        ),
                      )
                    : Scrollbar(
                        child: ListView.separated(
                          key: const ValueKey('dhikr-content-list'),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: shown.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                          ),
                          itemBuilder: (context, index) {
                            final e = shown[index];
                            return CheckboxListTile(
                              key: ValueKey('select-dhikr-${e.key}'),
                              controlAffinity: ListTileControlAffinity.leading,
                              value: selected.contains(e.key),
                              title: Text(
                                e.value,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.7,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              onChanged: (value) => setState(() {
                                if (value == false) {
                                  selected.remove(e.key);
                                } else if (selected.length <
                                    AppSettings.maxContent) {
                                  selected.add(e.key);
                                }
                              }),
                            );
                          },
                        ),
                      ),
              ),
              const Divider(height: 1),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey('save-dhikr-content'),
                          onPressed: () =>
                              Navigator.pop(context, selected.toList()),
                          child: Text(
                            context.tr(
                              'settings.saveSelection',
                              args: {
                                'count':
                                    LocalizationScope.maybeOf(
                                      context,
                                    )?.formats.integer(selected.length) ??
                                    selected.length,
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(context.settingsLabel('إلغاء')),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
