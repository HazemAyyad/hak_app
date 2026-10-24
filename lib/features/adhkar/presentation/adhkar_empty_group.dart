part of 'adhkar_host.dart';

class _EmptyDhikrGroup extends StatefulWidget {
  const _EmptyDhikrGroup({
    required this.host,
    required this.repository,
    required this.activity,
    required this.group,
    required this.library,
    required this.owner,
  });
  final AdhkarSectionPageState host;
  final AdhkarRepository repository;
  final ReligiousActivityController activity;
  final DhikrGroup group;
  final AdhkarLibrary library;
  final String owner;
  @override
  State<_EmptyDhikrGroup> createState() => _EmptyDhikrGroupState();
}

class _EmptyDhikrGroupState extends State<_EmptyDhikrGroup> {
  bool busy = false;
  bool get saved => widget.group.id == 'group:${AdhkarRepository.savedGroupId}';
  Future<void> add() async {
    if (busy) return;
    if (saved) {
      Navigator.pop(context);
      return;
    }
    setState(() => busy = true);
    try {
      final editor = PersonalAdhkar(widget.activity);
      if (editor.scope != widget.owner) throw StateError('Account changed');
      if (widget.group.id == 'personal:all') {
        await _editDhikrDialog(context, editor);
      } else {
        final daily = widget.group.id.startsWith('daily:');
        final model =
            widget.group.personal ??
            PersonalDhikrGroup(
              id: daily
                  ? adhkarIdentity('override:${widget.group.id}')
                  : widget.group.id.substring('group:'.length),
              title: widget.group.title,
              itemIds: const [],
            );
        await showDialog<bool>(
          context: context,
          useRootNavigator: false,
          builder: (_) => _GroupEditDialog(
            editor: editor,
            library: widget.library,
            group: model,
            readOnlyTitle: daily,
          ),
        );
      }
      if (!mounted || widget.activity.scope != widget.owner) return;
      final library = await widget.repository.library(
        widget.activity.store,
        widget.owner,
      );
      final group = library.groups
          .where((g) => g.id == widget.group.id)
          .firstOrNull;
      if (!mounted || group == null || group.itemIds.isEmpty) return;
      Navigator.pop(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.host.mounted) unawaited(widget.host.openGroup(group.id));
      });
    } catch (_) {
      widget.host._message('تعذّر تحديث المجموعة؛ أعد المحاولة');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    if (widget.activity.scope != widget.owner) {
      return _notice(context, 'تغيّر الحساب؛ ارجع لفتح أذكارك الحالية');
    }
    return ColoredBox(
      color: colors.background,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 112),
        children: [
          Stack(
            children: [
              DirectoryHeader(
                title: widget.group.title,
                subtitle: 'اذكر الله واطمئن',
                maxTitleLines: 2,
              ),
              Positioned(
                left: 12,
                top: MediaQuery.paddingOf(context).top + 12,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'العودة للأذكار',
                  icon: const Icon(
                    Icons.arrow_forward,
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: _card(
              context,
              child: Column(
                children: [
                  Icon(
                    saved ? Icons.favorite_border : Icons.eco_outlined,
                    size: 58,
                    color: colors.gold,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    saved ? 'لم تحفظ أذكارًا بعد' : 'هذه المجموعة خالية',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: colors.heading,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    saved
                        ? 'اضغط «حفظ» داخل قارئ الأذكار لتجدها هنا.'
                        : 'أضف ذكرًا شخصيًا أو اختر من الأذكار الجاهزة.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.muted, height: 1.8),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: busy ? null : add,
                    icon: const Icon(Icons.add),
                    label: Text(
                      busy
                          ? 'جارٍ الفتح...'
                          : saved
                          ? 'تصفّح الأذكار'
                          : 'إضافة ذكر',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
