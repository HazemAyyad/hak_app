part of 'adhkar_host.dart';

class _AdhkarReader extends StatefulWidget {
  const _AdhkarReader({required this.host, required this.controller});
  final AdhkarSectionPageState host;
  final AdhkarSessionController controller;
  @override
  State<_AdhkarReader> createState() => _AdhkarReaderState();
}

class _AdhkarReaderState extends State<_AdhkarReader>
    with WidgetsBindingObserver, RouteAware {
  final volume = AdhkarVolumeControls();
  bool _allowPop = false,
      _completionShown = false,
      _resumed = true,
      _saved = false;
  int _dialogs = 0;
  Set<String> _savedItems = {};
  bool _routeVisible = true;
  ModalRoute<dynamic>? _route;
  AdhkarSessionController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _completionShown = c.completed;
    c.addListener(_changed);
    widget.host.visible.addListener(_visibilityChanged);
    _visibilityChanged();
    unawaited(_loadSaved());
  }

  @override
  void dispose() {
    widget.host.routes.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_changed);
    widget.host.visible.removeListener(_visibilityChanged);
    unawaited(volume.dispose());
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      widget.host.routes.unsubscribe(this);
      _route = route;
      widget.host.routes.subscribe(this, route);
    }
  }

  @override
  void didPush() {
    _routeVisible = true;
    _visibilityChanged();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _visibilityChanged();
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _visibilityChanged();
  }

  @override
  void didPop() {
    _routeVisible = false;
    _visibilityChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _visibilityChanged();
    if (_resumed) unawaited(c.refresh());
  }

  void _visibilityChanged() {
    final enabled =
        mounted &&
        widget.host.visible.value &&
        _resumed &&
        _routeVisible &&
        _dialogs == 0 &&
        c.available &&
        c.settings.mode == DhikrReadingMode.focus &&
        c.settings.volumeKeys;
    unawaited(
      volume
          .setEnabled(enabled, () {
            if (mounted &&
                widget.host.visible.value &&
                _resumed &&
                _routeVisible &&
                _dialogs == 0 &&
                c.available) {
              unawaited(_count(c.current));
            }
          })
          .catchError((Object _) {}),
    );
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _visibilityChanged();
    unawaited(_loadSaved());
    if (!c.completed) _completionShown = false;
    if (c.completed &&
        c.available &&
        !_completionShown &&
        _dialogs == 0 &&
        _routeVisible &&
        widget.host.visible.value &&
        _resumed) {
      _completionShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            c.available &&
            _routeVisible &&
            widget.host.visible.value &&
            _resumed) {
          unawaited(_completion());
        } else {
          _completionShown = false;
        }
      });
    }
  }

  Future<void> _loadSaved() async {
    if (!c.available) return;
    try {
      final value = await c.activity.store.entity(
        c.scope,
        'group:${AdhkarRepository.savedGroupId}',
      );
      final group = value is PersonalDhikrGroup ? value : null;
      if (mounted) {
        setState(() {
          _savedItems = group?.itemIds.toSet() ?? {};
          _saved = _savedItems.contains(c.current.id);
        });
      }
    } catch (_) {
      if (mounted) {
        widget.host._message('تعذّر قراءة الأذكار المحفوظة؛ أعد المحاولة');
      }
    }
  }

  Future<T?> _overlay<T>(Future<T?> Function() action) async {
    _dialogs++;
    _visibilityChanged();
    try {
      return await action();
    } finally {
      _dialogs--;
      if (mounted) _visibilityChanged();
    }
  }

  Future<void> _leave() async {
    if (_dialogs > 0) return;
    final leave =
        !c.settings.confirmExit ||
        !c.available ||
        await _overlay(
              () => _confirm(
                context,
                context.adhkarLabel('مغادرة الأذكار؟'),
                context.adhkarLabel('تقدّمك محفوظ، ويمكنك استكماله لاحقًا.'),
                accept: context.adhkarLabel('مغادرة'),
              ),
            ) ==
            true;
    if (!leave || !mounted) return;
    await c.flush();
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  Future<void> _completion() async {
    await _overlay(
      () => showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          icon: Icon(
            Icons.check_circle_outline,
            size: 46,
            color: AppPalette.of(context).tealHeading,
          ),
          title: Text(
            context.adhkarLabel('تقبّل الله منك'),
            textAlign: TextAlign.center,
          ),
          content: Text(
            context.adhkarLabel('أتممت أذكار هذه الجلسة، وحُفظ تقدمك.'),
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await c.undo();
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(context.adhkarLabel('تراجع')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.adhkarLabel('تم')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _count(DhikrEntry item) async {
    final before = c.remaining(item.id);
    await c.count(item.id);
    if (!mounted || c.remaining(item.id) >= before) return;
    if (c.settings.hapticZero && c.remaining(item.id) == 0) {
      unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
    } else if (c.settings.hapticEvery) {
      unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
    }
  }

  Future<void> _favorite([DhikrEntry? item]) async {
    try {
      await PersonalAdhkar(c.activity).toggleSaved(item?.id ?? c.current.id);
      await _loadSaved();
    } catch (_) {
      widget.host._message('تعذّر حفظ الذكر؛ أعد المحاولة');
    }
  }

  void _share(DhikrEntry item) {
    unawaited(
      _overlay(
        () => chooseContentShare(context, ShareCardContent.adhkar(item.text)),
      ),
    );
  }

  Future<void> _options(String action, DhikrEntry item) async {
    switch (action) {
      case 'share':
        _share(item);
      case 'save':
        await _favorite(item);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: item.text));
        widget.host._message('تم نسخ الذكر');
      case 'complete':
        await c.count(item.id, complete: true);
      case 'restart':
        if (await _overlay(
              () => _confirm(
                context,
                context.adhkarLabel('بدء العدّ من جديد؟'),
                context.adhkarLabel(
                  'يبدأ عدّ جديد، ويبقى تاريخ الجلسة محفوظًا.',
                ),
                accept: context.adhkarLabel('ابدأ من جديد'),
              ),
            ) ==
            true) {
          await c.restart();
        }
      case 'source':
        await _overlay(
          () => showDialog<void>(
            context: context,
            useRootNavigator: false,
            builder: (context) => AlertDialog(
              title: Text(context.adhkarLabel('مصدر الذكر')),
              content: SingleChildScrollView(
                child: SelectableText(
                  context.tr(
                    'adhkar.sourceNotice',
                    args: {'source': item.source, 'url': item.sourceUrl ?? ''},
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.adhkarLabel('تم')),
                ),
              ],
            ),
          ),
        );
      case 'edit':
        final edited = await _overlay(
          () =>
              _editDhikrDialog(context, PersonalAdhkar(c.activity), item: item),
        );
        if (edited == true && item.personal) await _reopen();
      case 'delete':
        if (item.personal &&
            await _overlay(
                  () => _confirm(
                    context,
                    context.adhkarLabel('حذف الذكر الشخصي؟'),
                    context.adhkarLabel(
                      'يُحذف من مجموعاتك، ويبقى تاريخ قراءتك محفوظًا.',
                    ),
                    accept: context.adhkarLabel('حذف'),
                  ),
                ) ==
                true) {
          await PersonalAdhkar(
            c.activity,
          ).deleteDhikr(item.id.substring('dhikr:'.length));
          await _reopen();
        }
      case 'group':
        final repository = await widget.host.source;
        final library = await repository.library(c.activity.store, c.scope);
        if (!mounted || !c.available) return;
        final isDaily = c.group.id.startsWith('daily:');
        final model =
            c.group.personal ??
            PersonalDhikrGroup(
              id: isDaily
                  ? adhkarIdentity('override:${c.group.id}')
                  : c.group.id.substring('group:'.length),
              title: c.group.title,
              itemIds: c.group.itemIds,
            );
        final changed = await _overlay(
          () => showDialog<bool>(
            context: context,
            useRootNavigator: false,
            builder: (_) => _GroupEditDialog(
              editor: PersonalAdhkar(c.activity),
              library: library,
              group: model,
              readOnlyTitle:
                  isDaily || model.id == AdhkarRepository.savedGroupId,
            ),
          ),
        );
        if (changed == true && mounted) {
          await c.flush();
          if (!mounted) return;
          setState(() => _allowPop = true);
          Navigator.pop(context);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (widget.host.mounted) {
              unawaited(widget.host.openGroup(c.group.id));
            }
          });
        }
    }
  }

  Future<void> _reopen() async {
    _routeVisible = false;
    _visibilityChanged();
    await c.flush();
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.host.mounted) unawaited(widget.host.openGroup(c.group.id));
    });
  }

  Widget _listMenu(DhikrEntry item) => PopupMenuButton<String>(
    tooltip: context.adhkarLabel('خيارات الذكر'),
    onSelected: (value) => _options(value, item),
    itemBuilder: (_) => [
      for (final (id, label) in [
        ('copy', context.adhkarLabel('نسخ النص')),
        ('share', context.adhkarLabel('مشاركة')),
        (
          'save',
          _savedItems.contains(item.id)
              ? context.adhkarLabel('إزالة من المحفوظات')
              : context.adhkarLabel('حفظ الذكر'),
        ),
        ('complete', context.adhkarLabel('إكمال هذا الذكر')),
        (
          'edit',
          item.personal
              ? context.adhkarLabel('تعديل الذكر الشخصي')
              : context.adhkarLabel('حفظ نسخة شخصية'),
        ),
        if (item.personal) ('delete', context.adhkarLabel('حذف الذكر الشخصي')),
        if (c.group.id != 'personal:all')
          ('group', context.adhkarLabel('تعديل المجموعة وترتيب الأذكار')),
      ])
        PopupMenuItem(value: id, child: Text(label)),
    ],
  );

  Future<void> _settings() async {
    await _overlay(
      () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .82,
          maxChildSize: .95,
          builder: (context, scroll) => StatefulBuilder(
            builder: (context, update) {
              final settings = c.settings;
              void change(VoidCallback action) {
                update(action);
                unawaited(c.saveSettings());
              }

              Widget toggle(
                String key,
                String label,
                bool value,
                ValueChanged<bool> changeValue, {
                bool enabled = true,
              }) => SwitchListTile(
                key: ValueKey('adhkar-setting-$key'),
                title: Text(label),
                value: value,
                onChanged: enabled ? (v) => change(() => changeValue(v)) : null,
                contentPadding: EdgeInsets.zero,
              );
              return ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                children: [
                  Text(
                    context.adhkarLabel('عرض الأذكار والجلسة'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: settings.font,
                    decoration: _input(context, context.adhkarLabel('الخط')),
                    items: [
                      for (final (id, label) in [
                        ('QuranUI', context.adhkarLabel('القاهرة')),
                        ('Tajawal', context.adhkarLabel('تجوال')),
                        ('AmiriQuran', context.adhkarLabel('أميري')),
                      ])
                        DropdownMenuItem(value: id, child: Text(label)),
                    ],
                    onChanged: (v) {
                      if (v != null) change(() => settings.font = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.tr(
                      'adhkar.fontSize',
                      args: {
                        'size': adhkarNumber(context, settings.size.round()),
                      },
                    ),
                  ),
                  Slider(
                    value: settings.size,
                    min: 16,
                    max: 42,
                    divisions: 26,
                    onChanged: (v) => change(() => settings.size = v),
                  ),
                  toggle(
                    'zero',
                    context.adhkarLabel('اهتزاز عند الصفر'),
                    settings.hapticZero,
                    (v) => settings.hapticZero = v,
                  ),
                  toggle(
                    'every',
                    context.adhkarLabel('اهتزاز عند كل ضغطة'),
                    settings.hapticEvery,
                    (v) => settings.hapticEvery = v,
                  ),
                  toggle(
                    'hide',
                    context.adhkarLabel('إخفاء الذكر عند الصفر'),
                    settings.hideCompleted,
                    (v) => settings.hideCompleted = v,
                  ),
                  toggle(
                    'tap',
                    context.adhkarLabel('العدّ بالضغط على نص الذكر'),
                    settings.tapText,
                    (v) => settings.tapText = v,
                  ),
                  const Divider(),
                  toggle(
                    'auto',
                    context.adhkarLabel('الانتقال التلقائي في الجلسة'),
                    settings.autoAdvance,
                    (v) => settings.autoAdvance = v,
                  ),
                  toggle(
                    'dim',
                    context.adhkarLabel('الوضع الخافت أثناء الجلسة'),
                    settings.dim,
                    (v) => settings.dim = v,
                  ),
                  toggle(
                    'volume',
                    context.adhkarLabel('العدّ بأزرار الصوت في جلسة أندرويد'),
                    settings.volumeKeys,
                    (v) => settings.volumeKeys = v,
                    enabled: volume.supported,
                  ),
                  toggle(
                    'exit',
                    context.adhkarLabel('تأكيد مغادرة الأذكار'),
                    settings.confirmExit,
                    (v) => settings.confirmExit = v,
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.adhkarLabel('تم')),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _entry(BuildContext context, DhikrEntry item, {required bool list}) {
    final colors = AppPalette.of(context), remaining = c.remaining(item.id);
    final translated = item.presentation(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          context,
          onTap: c.settings.tapText && c.available ? () => _count(item) : null,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.displayTitle(context),
                      textDirection: adhkarTextDirection(
                        item.displayTitle(context),
                      ),
                      style: TextStyle(
                        color: colors.gold,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (list) _listMenu(item),
                ],
              ),
              const SizedBox(height: 22),
              if (item.preface.isNotEmpty && translated == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    item.preface,
                    textDirection: adhkarTextDirection(item.preface),
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 14,
                      height: 1.7,
                    ),
                  ),
                ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: list
                      ? double.infinity
                      : MediaQuery.sizeOf(context).height * .30,
                ),
                child: SingleChildScrollView(
                  key: ValueKey('dhikr-text-scroll-${item.id}'),
                  child: translated != null && !item.hasScripture
                      ? PresentedSourceText(
                          translated,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.tealHeading,
                            fontSize: c.settings.size,
                            height: 1.7,
                          ),
                        )
                      : Text(
                          item.text,
                          textDirection: item.contentDirection,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: c.settings.font,
                            color: colors.tealHeading,
                            fontSize: c.settings.size,
                            height: 1.95,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              if (translated != null && item.hasScripture)
                PresentedSourceText(
                  translated,
                  style: TextStyle(
                    color: colors.tealHeading,
                    fontSize: c.settings.size,
                    height: 1.7,
                  ),
                ),
              if (translated != null)
                PresentedSourceFooter(translated)
              else
                Text(
                  item.source,
                  textDirection: adhkarTextDirection(item.source),
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 11,
                    height: 1.8,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          context,
          padding: EdgeInsets.symmetric(vertical: list ? 10 : 15),
          child: Column(
            children: [
              Semantics(
                button: true,
                label: context.tr(
                  'adhkar.remaining',
                  args: {
                    'count': adhkarNumber(context, remaining),
                    'total': adhkarNumber(context, c.session.targets[item.id]!),
                  },
                ),
                child: Material(
                  color: remaining == 0
                      ? const Color(0xFFB84949)
                      : const Color(0xFF278B83),
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: ValueKey('count-${item.id}'),
                    customBorder: const CircleBorder(),
                    onTap: c.available ? () => _count(item) : null,
                    child: SizedBox.square(
                      dimension: list ? 82 : 116,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              adhkarNumber(context, remaining),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: list ? 30 : 42,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ),
                          Text(
                            remaining == 0
                                ? context.adhkarLabel('تمّ')
                                : context.adhkarLabel('متبقّي'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      key: ValueKey('item-progress-${item.id}'),
                      value: 1 - remaining / c.session.targets[item.id]!,
                      minHeight: 4,
                      color: colors.tealHeading,
                      backgroundColor: colors.border,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.tr(
                        'adhkar.counterProgress',
                        args: {
                          'percent': adhkarPercent(
                            context,
                            (1 - remaining / c.session.targets[item.id]!).clamp(
                              0,
                              1,
                            ),
                          ),
                          'count': adhkarNumber(
                            context,
                            c.session.targets[item.id]! - remaining,
                          ),
                          'total': adhkarNumber(
                            context,
                            c.session.targets[item.id]!,
                          ),
                        },
                      ),
                      style: TextStyle(fontSize: 12, color: colors.muted),
                    ),
                  ],
                ),
              ),
              if (!list)
                Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Text(
                    context.adhkarLabel('اضغط على الرقم للعدّ'),
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        if (!list) ...[
          const SizedBox(height: 12),
          _card(
            context,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: _action(
                    context,
                    Icons.settings_outlined,
                    context.adhkarLabel('العرض'),
                    _settings,
                  ),
                ),
                Expanded(
                  child: _action(
                    context,
                    _saved ? Icons.favorite : Icons.favorite_border,
                    context.adhkarLabel('حفظ'),
                    _favorite,
                  ),
                ),
                Expanded(
                  child: _action(
                    context,
                    Icons.share_outlined,
                    context.adhkarLabel('مشاركة'),
                    () => _share(item),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: context.adhkarLabel('خيارات الذكر'),
                  onSelected: (value) => _options(value, item),
                  itemBuilder: (_) => [
                    for (final (id, label) in [
                      ('copy', context.adhkarLabel('نسخ النص')),
                      ('source', context.adhkarLabel('المصدر')),
                      ('complete', context.adhkarLabel('إكمال هذا الذكر')),
                      (
                        'edit',
                        item.personal
                            ? context.adhkarLabel('تعديل الذكر الشخصي')
                            : context.adhkarLabel('حفظ نسخة شخصية'),
                      ),
                      ('restart', context.adhkarLabel('بدء العدّ من جديد')),
                      if (c.group.id != 'personal:all')
                        (
                          'group',
                          context.adhkarLabel('تعديل المجموعة وترتيب الأذكار'),
                        ),
                    ])
                      PopupMenuItem(value: id, child: Text(label)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (c.activity.scope != c.scope) {
      return ColoredBox(
        color: AppPalette.of(context).background,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.adhkarLabel('تغيّر الحساب؛ افتح أذكار الحساب الحالي'),
                ),
                TextButton(
                  onPressed: _leave,
                  child: Text(context.adhkarLabel('العودة للأذكار')),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final dim = c.settings.mode == DhikrReadingMode.focus && c.settings.dim;
    final content = Builder(
      builder: (context) {
        final colors = AppPalette.of(context);
        final entries = c.settings.mode == DhikrReadingMode.list
            ? c.items
                  .where(
                    (e) => !c.settings.hideCompleted || c.remaining(e.id) > 0,
                  )
                  .toList()
            : [c.current];
        return ColoredBox(
          color: colors.background,
          child: ListView.builder(
            key: PageStorageKey(
              'reader-${c.session.id}-${c.settings.mode.name}',
            ),
            padding: const EdgeInsets.only(bottom: 112),
            itemCount: entries.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Stack(
                  children: [
                    DirectoryHeader(
                      title: c.group.displayTitle(context),
                      maxTitleLines: 2,
                      subtitle: context.adhkarLabel('اذكر الله واطمئن'),
                    ),
                    Positioned(
                      left: 12,
                      top: MediaQuery.paddingOf(context).top + 12,
                      child: IconButton.filledTonal(
                        tooltip: context.adhkarLabel('العودة للأذكار'),
                        onPressed: _leave,
                        icon: const Icon(
                          Icons.arrow_forward,
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                    ),
                  ],
                );
              }
              if (index == 1) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Column(
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final (mode, label) in [
                            (
                              DhikrReadingMode.cards,
                              context.adhkarLabel('أفقي'),
                            ),
                            (
                              DhikrReadingMode.list,
                              context.adhkarLabel('عمودي'),
                            ),
                            (
                              DhikrReadingMode.focus,
                              context.adhkarLabel('جلسة'),
                            ),
                          ])
                            ChoiceChip(
                              key: ValueKey('adhkar-mode-${mode.name}'),
                              selected: c.settings.mode == mode,
                              showCheckmark: false,
                              selectedColor: const Color(0xFF278B83),
                              backgroundColor: colors.neutral,
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              labelStyle: TextStyle(
                                color: c.settings.mode == mode
                                    ? Colors.white
                                    : colors.muted,
                              ),
                              label: Text(label),
                              onSelected: (_) {
                                c.settings.mode = mode;
                                unawaited(c.saveSettings());
                              },
                            ),
                          ActionChip(
                            avatar: const Icon(Icons.undo, size: 18),
                            label: Text(context.adhkarLabel('تراجع')),
                            onPressed: c.available ? c.undo : null,
                          ),
                          ActionChip(
                            avatar: const Icon(
                              Icons.settings_outlined,
                              size: 18,
                            ),
                            label: Text(context.adhkarLabel('العرض')),
                            onPressed: _settings,
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.tr(
                                'adhkar.sessionProgress',
                                args: {
                                  'index': adhkarNumber(context, c.cursor + 1),
                                  'total': adhkarNumber(
                                    context,
                                    c.items.length,
                                  ),
                                },
                              ),
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            context.tr(
                              'adhkar.completed',
                              args: {
                                'count': adhkarNumber(
                                  context,
                                  c.completedItems,
                                ),
                              },
                            ),
                            style: TextStyle(color: colors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: c.progress,
                          minHeight: 6,
                          color: colors.tealHeading,
                          backgroundColor: colors.border,
                        ),
                      ),
                      if (c.completed)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            context.adhkarLabel(
                              'تقبّل الله منك • اكتملت الجلسة',
                            ),
                            style: TextStyle(
                              color: colors.tealHeading,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      if (c.error != null || !c.available)
                        _notice(
                          context,
                          c.error ??
                              context.adhkarLabel(
                                'تغيّر الحساب أو اليوم؛ ارجع لفتح أذكارك الحالية',
                              ),
                        ),
                      if (c.activity.syncError case final message?)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            message,
                            style: TextStyle(
                              color: colors.muted,
                              fontSize: 11,
                              height: 1.7,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }
              final item = entries[index - 2];
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: GestureDetector(
                  onHorizontalDragEnd: c.settings.mode == DhikrReadingMode.list
                      ? null
                      : (details) {
                          final velocity = details.primaryVelocity ?? 0;
                          if (velocity.abs() > 120) {
                            unawaited(
                              c.select(c.cursor + (velocity > 0 ? 1 : -1)),
                            );
                          }
                        },
                  child: Column(
                    children: [
                      _entry(
                        context,
                        item,
                        list: c.settings.mode == DhikrReadingMode.list,
                      ),
                      if (c.settings.mode != DhikrReadingMode.list) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              onPressed: c.cursor > 0
                                  ? () => c.select(c.cursor - 1)
                                  : null,
                              icon: const Icon(
                                Icons.chevron_right,
                                textDirection: TextDirection.ltr,
                              ),
                              label: Text(context.adhkarLabel('السابق')),
                            ),
                            TextButton.icon(
                              onPressed: c.cursor < c.items.length - 1
                                  ? () => c.select(c.cursor + 1)
                                  : null,
                              icon: const Icon(
                                Icons.chevron_left,
                                textDirection: TextDirection.ltr,
                              ),
                              label: Text(context.adhkarLabel('التالي')),
                            ),
                          ],
                        ),
                        if (item.audioUrl != null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.headphones_outlined),
                            label: Text(context.adhkarLabel('استماع')),
                            onPressed: c.available
                                ? () async {
                                    await widget.host.widget.controller
                                        .playExternal([
                                          QuranAudioTrack(
                                            id: 'adhkar:${item.id}',
                                            recitation: 'hisn-ar',
                                            reciter: context.adhkarLabel(
                                              'حصن المسلم • التسجيل الأصلي',
                                            ),
                                            title: item.title,
                                            surah: 0,
                                            url: item.audioUrl!,
                                            version: c.session.catalogVersion,
                                            quality: 'المصدر الأصلي',
                                          ),
                                        ]);
                                    if (mounted) setState(() {});
                                  }
                                : null,
                          ),
                        QuranPlayerPanel(
                          media: widget.host.widget.controller.media,
                          repository: c.activity.quran.repository!,
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
    return PopScope<Object?>(
      canPop: _allowPop || !c.settings.confirmExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: dim
          ? Theme(
              data: Theme.of(context).copyWith(
                brightness: Brightness.dark,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF278B83),
                  brightness: Brightness.dark,
                ),
              ),
              child: content,
            )
          : content,
    );
  }
}

Widget _action(
  BuildContext context,
  IconData icon,
  String label,
  VoidCallback onTap,
) => InkWell(
  onTap: onTap,
  borderRadius: BorderRadius.circular(15),
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppPalette.of(context).tealHeading),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(color: AppPalette.of(context).muted, fontSize: 11),
        ),
      ],
    ),
  ),
);
