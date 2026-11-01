part of 'community_page.dart';

Future<bool> _confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.communityLabel('إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.communityLabel('تأكيد')),
          ),
        ],
      ),
    ) ??
    false;

Future<void> _compose(
  BuildContext context,
  CommunityController c, {
  int? parent,
  required Future<void> Function() onSent,
}) async {
  final scope = c.scope, token = c.quran.account.token;
  final pending = c.pending['entry:${parent ?? 0}'];
  var text = pending?['body'] as String? ?? '';
  String? error;
  bool busy = false;
  await showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: Text(
            parent == null
                ? context.communityLabel('مشاركة دعاء')
                : context.communityLabel('إضافة تعليق'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: text,
                  onChanged: (value) => text = value,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 180,
                  readOnly: pending != null,
                  decoration: InputDecoration(
                    labelText: parent == null
                        ? context.communityLabel('الدعاء')
                        : context.communityLabel('التعليق'),
                    helperText: context.communityLabel(
                      'تظهر المشاركة للآخرين بعد المراجعة',
                    ),
                  ),
                ),
                if (error != null) Text(context.communityLabel(error!)),
                if (pending != null)
                  Text(
                    context.communityLabel(
                      'المشاركة السابقة بانتظار التأكيد؛ تُرسل بنفس المعرّف.',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: Text(context.communityLabel('إلغاء')),
            ),
            if (pending != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        await c.discard('entry:${parent ?? 0}');
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                child: Text(context.communityLabel('إلغاء إعادة الإرسال')),
              ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (c.scope != scope ||
                          c.quran.account.token != token ||
                          text.trim().isEmpty) {
                        return;
                      }
                      update(() => busy = true);
                      final result = await c.publish(text, parent: parent);
                      if (!ctx.mounted) return;
                      if (result != null) {
                        Navigator.pop(ctx);
                        await onSent();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                result['status'] == 'pending'
                                    ? context.communityLabel(
                                        'وصلت المشاركة وهي بانتظار المراجعة',
                                      )
                                    : context.communityLabel(
                                        'تم تأكيد حالة المشاركة',
                                      ),
                              ),
                            ),
                          );
                        }
                      } else {
                        update(() {
                          busy = false;
                          error = c.error;
                        });
                      }
                    },
              child: Text(
                busy
                    ? context.communityLabel('جارٍ الإرسال…')
                    : pending != null
                    ? context.communityLabel('إعادة المحاولة')
                    : context.communityLabel('إرسال للمراجعة'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _entryAction(
  BuildContext context,
  CommunityController c,
  Map<String, dynamic> row,
  String action,
  Future<void> Function() refresh,
) async {
  final owner = c.scope, credential = c.quran.account.token;
  bool current() =>
      context.mounted &&
      c.scope == owner &&
      c.quran.account.token == credential;
  if (action == 'copy') {
    await Clipboard.setData(ClipboardData(text: row['body'] as String));
    return;
  }
  if (action == 'share') {
    await chooseContentShare(
      context,
      ShareCardContent.message(row['body'] as String),
    );
    return;
  }
  if (action == 'delete') {
    if (await _confirm(
      context,
      context.communityLabel('حذف المشاركة؟'),
      context.communityLabel('ستُحذف مشاركتك وتعليقاتها من العرض العام.'),
    )) {
      if (!current()) return;
      await c.mutate('DELETE', '/entries/${row['id']}');
      await refresh();
    }
    return;
  }
  if (action == 'block') {
    if (await _confirm(
      context,
      context.communityLabel('حظر الحساب؟'),
      context.communityLabel(
        'تختفي مشاركات هذا الحساب عنك وتتعطل المشاركة المتبادلة. يمكنك إلغاء الحظر من قائمة الحسابات المحظورة.',
      ),
    )) {
      if (!current()) return;
      await c.mutate(
        'PUT',
        '/blocks/${row['account_id']}',
        data: {'blocked': true},
      );
      await refresh();
    }
    return;
  }
  var reason = '';
  final send = await showDialog<bool>(
    context: context,
    useRootNavigator: false,
    builder: (ctx) => AlertDialog(
      title: Text(
        action == 'report'
            ? context.communityLabel('شكاية منشور')
            : context.communityLabel('شكاية الحساب'),
      ),
      content: TextFormField(
        onChanged: (value) => reason = value,
        maxLength: 180,
        decoration: InputDecoration(
          labelText: context.communityLabel('سبب الشكاية'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(context.communityLabel('إلغاء')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, reason.trim().isNotEmpty),
          child: Text(context.communityLabel('إرسال البلاغ')),
        ),
      ],
    ),
  );
  if (send == true && current()) {
    final result = await c.mutate(
      'POST',
      '/reports',
      data: {
        'type': action == 'report' ? 'entry' : 'account',
        'target_id': action == 'report' ? row['id'] : row['account_id'],
        'reason': reason.trim(),
      },
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == null
                ? c.error ?? context.communityLabel('تعذّر الإرسال')
                : context.communityLabel('وصل البلاغ للمراجعة'),
          ),
        ),
      );
    }
  }
}

class _CommentsPage extends StatefulWidget {
  const _CommentsPage({required this.c, required this.parent});
  final CommunityController c;
  final Map<String, dynamic> parent;
  @override
  State<_CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<_CommentsPage> {
  final rows = <Map<String, dynamic>>[];
  int? next;
  bool loading = false;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load({bool more = false}) async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final page = CommunityPageData.parse(
        await widget.c.request(
          'GET',
          '/entries',
          query: {
            'parent_id': widget.parent['id'],
            'limit': 20,
            if (more && next != null) 'cursor': next,
          },
        ),
      );
      if (mounted) {
        setState(() {
          if (!more) rows.clear();
          rows.addAll(page.items);
          next = page.next;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = widget.c.message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.of(context).background,
    appBar: AppBar(title: Text(context.communityLabel('التعليقات'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CommunityCard(
          child: Text(
            widget.parent['body'] as String,
            textDirection: contentTextDirection(
              widget.parent['body'] as String,
            ),
            style: const TextStyle(fontSize: 20),
          ),
        ),
        const SizedBox(height: 16),
        if (loading) const LinearProgressIndicator(),
        if (error != null) _CommunityNotice(error!, onRetry: load),
        if (!loading && error == null && rows.isEmpty)
          _CommunityCard(
            child: Text(context.communityLabel('لا تعليقات معتمدة بعد')),
          ),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CommunityCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row['author'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    row['body'] as String,
                    textDirection: contentTextDirection(row['body'] as String),
                  ),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: () => _entryAction(
                          context,
                          widget.c,
                          row,
                          row['mine'] == true ? 'delete' : 'report',
                          load,
                        ),
                        child: Text(
                          row['mine'] == true
                              ? context.communityLabel('حذف')
                              : context.communityLabel('إبلاغ'),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            _entryAction(context, widget.c, row, 'copy', load),
                        child: Text(context.communityLabel('نسخ')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (next != null)
          TextButton(
            onPressed: loading ? null : () => load(more: true),
            child: Text(context.communityLabel('المزيد')),
          ),
        FilledButton.icon(
          onPressed: loading
              ? null
              : () => _compose(
                  context,
                  widget.c,
                  parent: widget.parent['id'] as int,
                  onSent: load,
                ),
          icon: const Icon(Icons.add_comment_outlined),
          label: Text(context.communityLabel('إضافة تعليق')),
        ),
      ],
    ),
  );
}

class _BlockedAccounts extends StatefulWidget {
  const _BlockedAccounts({required this.c});
  final CommunityController c;
  @override
  State<_BlockedAccounts> createState() => _BlockedAccountsState();
}

class _BlockedAccountsState extends State<_BlockedAccounts> {
  final rows = <Map<String, dynamic>>[];
  int? next;
  String? error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load({bool more = false}) async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final page = CommunityPageData.parse(
        await widget.c.request(
          'GET',
          '/blocks',
          query: {if (more && next != null) 'cursor': next},
        ),
      );
      if (mounted) {
        setState(() {
          if (!more) rows.clear();
          rows.addAll(page.items);
          next = page.next;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = widget.c.message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.communityLabel('الحسابات المحظورة'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (loading) const LinearProgressIndicator(),
        if (error != null) _CommunityNotice(error!, onRetry: load),
        if (!loading && error == null && rows.isEmpty)
          Text(context.communityLabel('لا حسابات محظورة')),
        for (final row in rows)
          ListTile(
            title: Text(row['author'] as String),
            trailing: TextButton(
              onPressed: loading
                  ? null
                  : () async {
                      await widget.c.mutate(
                        'PUT',
                        '/blocks/${row['account_id']}',
                        data: {'blocked': false},
                      );
                      await load();
                    },
              child: Text(context.communityLabel('إلغاء الحظر')),
            ),
          ),
        if (next != null)
          TextButton(
            onPressed: loading ? null : () => load(more: true),
            child: Text(context.communityLabel('المزيد')),
          ),
      ],
    ),
  );
}
