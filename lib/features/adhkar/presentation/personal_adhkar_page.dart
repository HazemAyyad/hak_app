part of 'adhkar_host.dart';

class _PersonalAdhkarPage extends StatefulWidget {
  const _PersonalAdhkarPage({
    required this.host,
    required this.repository,
    required this.activity,
  });
  final AdhkarSectionPageState host;
  final AdhkarRepository repository;
  final ReligiousActivityController activity;
  @override
  State<_PersonalAdhkarPage> createState() => _PersonalAdhkarPageState();
}

class _PersonalAdhkarPageState extends State<_PersonalAdhkarPage> {
  late final PersonalAdhkar editor;
  late Future<AdhkarLibrary> _library;
  bool groups = false;
  String query = '';
  @override
  void initState() {
    super.initState();
    editor = PersonalAdhkar(widget.activity);
    _load();
    widget.activity.addListener(_changed);
  }

  void _load() {
    _library = widget.repository.library(widget.activity.store, editor.scope);
  }

  void _changed() {
    if (mounted) setState(_load);
  }

  @override
  void dispose() {
    widget.activity.removeListener(_changed);
    super.dispose();
  }

  Future<void> _delete(DhikrEntry item) async {
    if (!await _confirm(
          context,
          'حذف الذكر الشخصي؟',
          'يُحذف من مجموعاتك، ويبقى تاريخ قراءتك محفوظًا.',
          accept: 'حذف',
        ) ||
        !mounted) {
      return;
    }
    try {
      await editor.deleteDhikr(item.id.substring('dhikr:'.length));
    } catch (_) {
      widget.host._message('تعذّر الحذف؛ أعد المحاولة');
    }
  }

  Future<void> _deleteGroup(PersonalDhikrGroup group) async {
    if (!await _confirm(
          context,
          'حذف المجموعة؟',
          'تبقى أذكارها الشخصية في «كل أذكاري الشخصية».',
          accept: 'حذف',
        ) ||
        !mounted) {
      return;
    }
    try {
      await editor.deleteGroup(group.id);
    } catch (_) {
      widget.host._message('تعذّر حذف المجموعة');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return ColoredBox(
      color: colors.background,
      child: FutureBuilder<AdhkarLibrary>(
        future: _library,
        builder: (context, snapshot) {
          final library = snapshot.data;
          final custom =
              library?.groups
                  .where(
                    (g) => g.personal != null && !g.id.startsWith('daily:'),
                  )
                  .toList() ??
              [];
          final entries =
              library?.entries.values
                  .where(
                    (e) =>
                        e.personal &&
                        normalizeQuranSearch(
                          e.text,
                        ).contains(normalizeQuranSearch(query)),
                  )
                  .toList() ??
              [];
          return ListView(
            padding: const EdgeInsets.only(bottom: 112),
            children: [
              Stack(
                children: [
                  const DirectoryHeader(
                    title: 'أذكاري',
                    subtitle: 'أذكارك ومجموعاتك\nكما تحبّها',
                  ),
                  Positioned(
                    left: 12,
                    top: MediaQuery.paddingOf(context).top + 12,
                    child: IconButton.filledTonal(
                      tooltip: 'العودة للأذكار',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_forward,
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.activity.scope != editor.scope)
                      _notice(
                        context,
                        'تغيّر الحساب؛ ارجع لفتح أذكار الحساب الحالي',
                      )
                    else ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('الأذكار الشخصية'),
                            selected: !groups,
                            onSelected: (_) => setState(() => groups = false),
                          ),
                          ChoiceChip(
                            label: const Text('مجموعاتي'),
                            selected: groups,
                            onSelected: (_) => setState(() => groups = true),
                          ),
                          ActionChip(
                            label: const Text('الأذكار الجاهزة'),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('add-personal-dhikr'),
                            onPressed: () => _editDhikrDialog(context, editor),
                            icon: const Icon(Icons.add),
                            label: const Text('إضافة ذكر'),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey('add-personal-group'),
                            onPressed: library == null
                                ? null
                                : () => showDialog<void>(
                                    context: context,
                                    useRootNavigator: false,
                                    builder: (_) => _GroupEditDialog(
                                      editor: editor,
                                      library: library,
                                    ),
                                  ),
                            icon: const Icon(Icons.create_new_folder_outlined),
                            label: const Text('إنشاء مجموعة'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (snapshot.hasError)
                        _notice(
                          context,
                          'تعذّر قراءة المحفوظات',
                          action: _changed,
                        ),
                      if (library == null && !snapshot.hasError)
                        const Center(child: CircularProgressIndicator()),
                      if (library != null && !groups) ...[
                        TextField(
                          onChanged: (v) => setState(() => query = v),
                          decoration: _input(
                            context,
                            'ابحث في أذكارك...',
                            icon: Icons.search,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (entries.isEmpty)
                          _notice(
                            context,
                            query.isEmpty
                                ? 'لم تضف أذكارًا شخصية بعد؛ ابدأ بذكر تحبّه.'
                                : 'لا توجد نتائج لهذا البحث',
                          ),
                        if (entries.isNotEmpty)
                          TextButton.icon(
                            onPressed: () =>
                                widget.host.openGroup('personal:all'),
                            icon: const Icon(Icons.auto_stories_outlined),
                            label: const Text('قراءة كل أذكاري الشخصية'),
                          ),
                        for (final entry in entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _card(
                              context,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    entry.text,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.heading,
                                      fontSize: 17,
                                      height: 1.8,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${entry.target} مرة${entry.source.isEmpty ? '' : ' • ${entry.source}'}',
                                    style: TextStyle(
                                      color: colors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        tooltip: 'تعديل الذكر',
                                        onPressed: () => _editDhikrDialog(
                                          context,
                                          editor,
                                          item: entry,
                                        ),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'حذف الذكر',
                                        onPressed: () => _delete(entry),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                      if (library != null && groups) ...[
                        if (custom.isEmpty)
                          _notice(
                            context,
                            'أنشئ مجموعة واجمع فيها أذكارك المختارة.',
                          ),
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: custom.length,
                          onReorderItem: (oldIndex, newIndex) async {
                            final ordered = custom
                                .map((g) => g.personal!)
                                .toList();
                            final value = ordered.removeAt(oldIndex);
                            ordered.insert(newIndex, value);
                            try {
                              await editor.reorderGroups(ordered);
                            } catch (_) {
                              widget.host._message('تعذّر حفظ الترتيب');
                            }
                          },
                          itemBuilder: (context, index) {
                            final group = custom[index],
                                model = group.personal!;
                            return Padding(
                              key: ValueKey(group.id),
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _card(
                                context,
                                onTap: () => widget.host.openGroup(group.id),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      group.title,
                                      style: TextStyle(
                                        color: colors.heading,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '${group.itemIds.length} ذكر',
                                      style: TextStyle(color: colors.muted),
                                    ),
                                    Row(
                                      children: [
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: Padding(
                                            padding: const EdgeInsets.all(10),
                                            child: Icon(
                                              Icons.drag_handle,
                                              color: colors.muted,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          tooltip: 'تعديل المجموعة والترتيب',
                                          onPressed: () => showDialog<void>(
                                            context: context,
                                            useRootNavigator: false,
                                            builder: (_) => _GroupEditDialog(
                                              editor: editor,
                                              library: library,
                                              group: model,
                                            ),
                                          ),
                                          icon: const Icon(Icons.edit_outlined),
                                        ),
                                        IconButton(
                                          tooltip: 'حذف المجموعة',
                                          onPressed: () => _deleteGroup(model),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<bool?> _editDhikrDialog(
  BuildContext context,
  PersonalAdhkar editor, {
  DhikrEntry? item,
}) async {
  return showDialog<bool>(
    context: context,
    useRootNavigator: false,
    builder: (_) => _DhikrEditDialog(editor: editor, item: item),
  );
}

class _DhikrEditDialog extends StatefulWidget {
  const _DhikrEditDialog({required this.editor, this.item});
  final PersonalAdhkar editor;
  final DhikrEntry? item;
  @override
  State<_DhikrEditDialog> createState() => _DhikrEditDialogState();
}

class _DhikrEditDialogState extends State<_DhikrEditDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController text, count, note, preface;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    text = TextEditingController(text: widget.item?.text);
    count = TextEditingController(text: '${widget.item?.target ?? 1}');
    note = TextEditingController(text: widget.item?.source);
    preface = TextEditingController(text: widget.item?.preface);
  }

  @override
  void dispose() {
    text.dispose();
    count.dispose();
    note.dispose();
    preface.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.editor.saveDhikr(
        id: widget.item?.personal == true
            ? widget.item!.id.substring('dhikr:'.length)
            : null,
        text: text.text,
        target: count.text,
        source: note.text,
        preface: preface.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'تعذّر الحفظ؛ تأكد من الحساب والبيانات وأعد المحاولة';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.item == null
          ? 'إضافة ذكر'
          : widget.item!.personal
          ? 'تعديل الذكر'
          : 'حفظ نسخة شخصية',
    ),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: preface,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                decoration: _input(context, 'ما قبل الذكر (اختياري)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('dhikr-text'),
                controller: text,
                minLines: 3,
                maxLines: 6,
                maxLength: 10000,
                decoration: _input(context, 'نص الذكر'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'اكتب نص الذكر' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('dhikr-target'),
                controller: count,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  TextInputFormatter.withFunction(
                    (old, next) => next.copyWith(text: adhkarDigits(next.text)),
                  ),
                ],
                decoration: _input(context, 'عدد التكرار'),
                validator: (v) {
                  final n = int.tryParse(adhkarDigits(v ?? '').trim());
                  return n == null || n < 1 || n > 1000000
                      ? 'اكتب عددًا صحيحًا من1 إلى1000000'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: note,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                decoration: _input(context, 'ملاحظة أو مصدر (اختياري)'),
              ),
              if (widget.item?.personal == false)
                const Text(
                  'تُحفظ نسخة في أذكارك الشخصية، ويبقى نص المصدر المعتمد محفوظًا.',
                  style: TextStyle(fontSize: 12),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        key: const ValueKey('save-dhikr'),
        onPressed: saving ? null : save,
        child: Text(saving ? 'جارٍ الحفظ...' : 'حفظ'),
      ),
    ],
  );
}

class _GroupEditDialog extends StatefulWidget {
  const _GroupEditDialog({
    required this.editor,
    required this.library,
    this.group,
    this.readOnlyTitle = false,
  });
  final PersonalAdhkar editor;
  final AdhkarLibrary library;
  final PersonalDhikrGroup? group;
  final bool readOnlyTitle;
  @override
  State<_GroupEditDialog> createState() => _GroupEditDialogState();
}

class _GroupEditDialogState extends State<_GroupEditDialog> {
  late final TextEditingController title;
  late final List<String> selected;
  late final Map<String, DhikrEntry> entries;
  String query = '';
  String? error;
  bool ordering = false, saving = false;
  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.group?.title);
    selected = [...?widget.group?.itemIds];
    entries = {...widget.library.entries};
  }

  Future<void> _newDhikr() async {
    final before = entries.keys.toSet();
    await _editDhikrDialog(context, widget.editor);
    if (!mounted || widget.editor.activity.scope != widget.editor.scope) return;
    final records = await widget.editor.activity.store.entities(
      widget.editor.scope,
      kind: PersonalEntityKind.dhikr,
    );
    if (!mounted) return;
    setState(() {
      for (final value in records.whereType<PersonalDhikr>()) {
        entries[value.key] = DhikrEntry(
          id: value.key,
          title: 'ذكر شخصي',
          text: value.text,
          target: value.target,
          source: value.source,
          preface: value.preface,
          personal: true,
        );
        if (!before.contains(value.key) && !selected.contains(value.key)) {
          selected.add(value.key);
        }
      }
    });
  }

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (title.text.trim().isEmpty) {
      setState(() => error = 'اكتب اسم المجموعة');
      return;
    }
    setState(() => saving = true);
    try {
      await widget.editor.saveGroup(
        id: widget.group?.id,
        title: title.text,
        items: selected,
        order: widget.group?.order,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'تعذّر حفظ المجموعة؛ أعد المحاولة';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context), needle = normalizeQuranSearch(query);
    final options = entries.values
        .where(
          (e) => normalizeQuranSearch(
            '${e.title} ${e.text} ${e.source}',
          ).contains(needle),
        )
        .toList();
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(context).height * .85,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.group == null ? 'إنشاء مجموعة' : 'تعديل المجموعة',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('group-title'),
                readOnly: widget.readOnlyTitle,
                controller: title,
                maxLength: 160,
                decoration: _input(context, 'اسم المجموعة'),
              ),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('الأذكار (${selected.length})'),
                    selected: !ordering,
                    onSelected: (_) => setState(() => ordering = false),
                  ),
                  ChoiceChip(
                    label: const Text('الترتيب'),
                    selected: ordering,
                    onSelected: (_) => setState(() => ordering = true),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('ذكر جديد'),
                    onPressed: saving ? null : _newDhikr,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!ordering)
                TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: _input(
                    context,
                    'ابحث لإضافة ذكر...',
                    icon: Icons.search,
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: ordering
                    ? ReorderableListView.builder(
                        itemCount: selected.length,
                        onReorderItem: (old, index) => setState(() {
                          final id = selected.removeAt(old);
                          selected.insert(index, id);
                        }),
                        itemBuilder: (context, index) {
                          final entry = entries[selected[index]];
                          return ListTile(
                            key: ValueKey(selected[index]),
                            title: Text(
                              entry?.text ?? 'عنصر محفوظ',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            leading: Text('${index + 1}'),
                            trailing: const Icon(Icons.drag_handle),
                          );
                        },
                      )
                    : ListView.builder(
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final entry = options[index];
                          return CheckboxListTile(
                            value: selected.contains(entry.id),
                            onChanged: saving
                                ? null
                                : (v) => setState(() {
                                    if (v == true) {
                                      if (selected.length < 1000) {
                                        selected.add(entry.id);
                                      }
                                    } else {
                                      selected.remove(entry.id);
                                    }
                                  }),
                            title: Text(
                              entry.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.heading,
                                fontSize: 14,
                                height: 1.6,
                              ),
                            ),
                            subtitle: Text(
                              entry.title,
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 11,
                              ),
                            ),
                            contentPadding: EdgeInsets.zero,
                          );
                        },
                      ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('save-group'),
                    onPressed: saving ? null : save,
                    child: Text(saving ? 'جارٍ الحفظ...' : 'حفظ المجموعة'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
