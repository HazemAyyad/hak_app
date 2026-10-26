import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../app_appearance.dart';
import '../../../navigation/more_page.dart';
import '../../account/presentation/account_hub.dart';
import '../../religious_content/data/religious_controller.dart';
import '../data/community_controller.dart';
import 'community_media.dart';

part 'community_forms.dart';
part 'community_publications.dart';

String communityTitle(CommunitySection section) => switch (section) {
  CommunitySection.circles => 'حلقات الذكر',
  CommunitySection.prayers => 'ادعُ معي',
  CommunitySection.messages => 'رسائل حق',
  CommunitySection.stories => 'قصص حق',
};

class CommunityPage extends StatefulWidget {
  const CommunityPage({
    super.key,
    required this.religious,
    required this.section,
    this.controller,
  });
  final ReligiousController religious;
  final CommunitySection section;
  final CommunityController? controller;
  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  late final c =
      widget.controller ?? CommunityController(widget.religious.quran);
  late String owner;
  late String? credential;
  GlobalKey<NavigatorState> navigation = GlobalKey();
  @override
  void initState() {
    super.initState();
    owner = c.scope;
    credential = c.quran.account.token;
    c.addListener(_owner);
    unawaited(c.load(widget.section));
  }

  void _owner() {
    if (!mounted || owner == c.scope && credential == c.quran.account.token) {
      return;
    }
    setState(() {
      owner = c.scope;
      credential = c.quran.account.token;
      navigation = GlobalKey();
    });
    unawaited(c.load(widget.section));
  }

  @override
  void dispose() {
    c.removeListener(_owner);
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final handled = await navigation.currentState?.maybePop() ?? false;
        if (!handled && context.mounted) Navigator.of(context).pop();
      },
      child: Navigator(
        key: navigation,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (nested) => _CommunityDirectory(
            c: c,
            religious: widget.religious,
            section: widget.section,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    ),
  );
}

class _CommunityDirectory extends StatefulWidget {
  const _CommunityDirectory({
    required this.c,
    required this.religious,
    required this.section,
    required this.onClose,
  });
  final CommunityController c;
  final ReligiousController religious;
  final CommunitySection section;
  final VoidCallback onClose;
  @override
  State<_CommunityDirectory> createState() => _CommunityDirectoryState();
}

class _CommunityDirectoryState extends State<_CommunityDirectory>
    with WidgetsBindingObserver {
  CommunityController get c => widget.c;
  Timer? _poll;
  bool _reading = false, _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_read);
    _startPolling();
  }

  void _startPolling() {
    _poll?.cancel();
    if (widget.section == CommunitySection.messages) {
      _poll = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          unawaited(refresh());
        }
      });
    }
  }

  void _read() {
    if (_reading ||
        !mounted ||
        !_foreground ||
        ModalRoute.of(context)?.isCurrent != true ||
        widget.section != CommunitySection.messages ||
        c.loading ||
        c.error != null ||
        c.items.isEmpty) {
      return;
    }
    final newest = c.items
        .map((e) => e['id'] as int)
        .reduce((a, b) => a > b ? a : b);
    if (newest <= c.readThrough) return;
    _reading = true;
    final owner = c.scope, token = c.quran.account.token;
    final earlier = c.readThrough;
    unawaited(() async {
      try {
        if (earlier > 0) await c.notifyNewMessage(newest);
        if (!mounted ||
            !_foreground ||
            c.scope != owner ||
            c.quran.account.token != token) {
          return;
        }
        await c.markRead();
      } catch (_) {
        if (mounted) setState(() => notice = 'تعذّر حفظ حالة قراءة الرسائل');
      } finally {
        _reading = false;
      }
    }());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      if (widget.section == CommunitySection.messages) unawaited(refresh());
    } else {
      _poll?.cancel();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_read);
    super.dispose();
  }

  bool mine = false, savedOnly = false;
  String? filter, notice;
  Future<void> refresh({bool more = false}) async {
    await c.load(
      widget.section,
      more: more,
      mine: mine,
      savedOnly: savedOnly,
      filter: filter,
    );
  }

  bool get private =>
      widget.section == CommunitySection.circles ||
      widget.section == CommunitySection.prayers;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final palette = AppPalette.of(context);
      final entries = c.items
          .where(
            (e) => widget.section == CommunitySection.messages
                ? c.visible(e) && (!savedOnly || c.saved.contains(e['id']))
                : true,
          )
          .toList();
      return Scaffold(
        backgroundColor: palette.background,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 30),
              children: [
                DirectoryHeader(
                  title: communityTitle(widget.section),
                  subtitle: switch (widget.section) {
                    CommunitySection.circles => 'نجتمع على ذكر الله',
                    CommunitySection.prayers => 'دعوة طيبة من القلب',
                    _ => 'محتوى موثق يقرّبك من الله',
                  },
                  onBack: widget.onClose,
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (private && !c.signedIn)
                        _CommunityCard(
                          child: Column(
                            children: [
                              Icon(
                                Icons.lock_outline,
                                color: palette.gold,
                                size: 42,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'سجّل الدخول للمتابعة',
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'الحلقات والمشاركة تحتاج حساب حق. يمكنك متابعة بقية الأقسام كضيف.',
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(
                                      context,
                                      rootNavigator: true,
                                    ).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => Scaffold(
                                          body: SafeArea(
                                            child: AccountHubPage(
                                              controller: widget.religious,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                child: const Text('تسجيل الدخول أو إنشاء حساب'),
                              ),
                              TextButton(
                                onPressed: widget.onClose,
                                child: const Text('المتابعة كضيف'),
                              ),
                            ],
                          ),
                        ),
                      if (!private || c.signedIn) ...[
                        if (widget.section == CommunitySection.prayers)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('ادع معي'),
                                selected: !mine,
                                onSelected: (_) {
                                  setState(() => mine = false);
                                  refresh();
                                },
                              ),
                              ChoiceChip(
                                label: const Text('أدعيتي'),
                                selected: mine,
                                onSelected: (_) {
                                  setState(() => mine = true);
                                  refresh();
                                },
                              ),
                              ActionChip(
                                label: const Text('الحسابات المحظورة'),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => _BlockedAccounts(c: c),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (widget.section == CommunitySection.messages) ...[
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final kind in publicationKinds.entries)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      end: 8,
                                    ),
                                    child: ChoiceChip(
                                      label: Text(kind.value),
                                      selected: filter == kind.key,
                                      onSelected: (_) {
                                        setState(() => filter = kind.key);
                                        refresh();
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilterChip(
                                label: const Text('المحفوظة'),
                                selected: savedOnly,
                                onSelected: (v) {
                                  setState(() => savedOnly = v);
                                  refresh();
                                },
                              ),
                              TextButton.icon(
                                onPressed: () =>
                                    _messageOptions(context, c, refresh),
                                icon: const Icon(Icons.more_horiz),
                                label: const Text('خيارات الرسائل'),
                              ),
                            ],
                          ),
                        ],
                        if (c.enabled == false)
                          _CommunityCard(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.cloud_off_outlined,
                                  color: palette.gold,
                                  size: 40,
                                ),
                                const SizedBox(height: 12),
                                const Text('خدمات المجتمع غير متاحة حاليًا'),
                                const SizedBox(height: 8),
                                const Text(
                                  'لا توجد أعداد أو منشورات تجريبية. أعد المحاولة عند تفعيل الخدمة.',
                                ),
                                TextButton(
                                  onPressed: refresh,
                                  child: const Text('إعادة المحاولة'),
                                ),
                              ],
                            ),
                          ),
                        if (c.loading)
                          const Padding(
                            padding: EdgeInsets.all(18),
                            child: LinearProgressIndicator(),
                          ),
                        if (c.error != null)
                          _CommunityNotice(c.error!, onRetry: refresh),
                        if (c.localError != null)
                          _CommunityNotice(c.localError!),
                        if (c.enabled == true &&
                            !c.loading &&
                            c.error == null &&
                            entries.isEmpty)
                          _CommunityCard(
                            child: Text(switch (widget.section) {
                              CommunitySection.circles =>
                                'لا حلقات منشورة حاليًا',
                              CommunitySection.prayers =>
                                mine
                                    ? 'لم تشارك دعاءً بعد'
                                    : 'لا مشاركات معتمدة حاليًا',
                              _ =>
                                savedOnly
                                    ? 'لا رسائل محفوظة ضمن النتائج'
                                    : 'لا محتوى منشور حاليًا',
                            }, textAlign: TextAlign.center),
                          ),
                        for (final row in entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: switch (widget.section) {
                              CommunitySection.circles => _CircleCard(
                                row: row,
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => _CircleReader(
                                        c: c,
                                        id: row['id'] as int,
                                        initial: row,
                                      ),
                                    ),
                                  );
                                  if (mounted) await refresh();
                                },
                              ),
                              CommunitySection.prayers => _PrayerCard(
                                c: c,
                                row: row,
                                onChanged: refresh,
                              ),
                              _ => _PublicationCard(
                                c: c,
                                row: row,
                                story:
                                    widget.section == CommunitySection.stories,
                                onOpen: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => CommunityStoryPage(
                                      c: c,
                                      rows: entries,
                                      index: entries.indexOf(row),
                                      beforeMedia: () async {
                                        await widget.religious.media.stop();
                                        await widget.religious.quran.audio
                                            .stop();
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            },
                          ),
                        if (c.next != null)
                          OutlinedButton(
                            onPressed: c.loading
                                ? null
                                : () => refresh(more: true),
                            child: const Text('تحميل المزيد'),
                          ),
                        if (widget.section == CommunitySection.prayers &&
                            c.enabled == true)
                          FilledButton.icon(
                            onPressed: c.working
                                ? null
                                : () => _compose(context, c, onSent: refresh),
                            icon: const Icon(Icons.add),
                            label: const Text('مشاركة دعاء'),
                          ),
                        if (notice != null) _CommunityNotice(notice!),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: p.heading, height: 1.7),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _CommunityNotice extends StatelessWidget {
  const _CommunityNotice(this.text, {this.onRetry});
  final String text;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppPalette.of(context).heading, height: 1.7),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    ),
  );
}

class _CircleCard extends StatelessWidget {
  const _CircleCard({required this.row, required this.onTap});
  final Map<String, dynamic> row;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return _CommunityCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.paleTeal,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.eco_outlined, color: p.tealHeading, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['title'] as String,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${row['participants']} مشاركين • ${row['total']} من ${row['goal']}',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: ((row['total'] as num) / (row['goal'] as num))
                      .clamp(0, 1)
                      .toDouble(),
                  color: p.tealHeading,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.chevron_left, color: p.muted),
        ],
      ),
    );
  }
}

class _CircleReader extends StatefulWidget {
  const _CircleReader({
    required this.c,
    required this.id,
    required this.initial,
  });
  final CommunityController c;
  final int id;
  final Map<String, dynamic> initial;
  @override
  State<_CircleReader> createState() => _CircleReaderState();
}

class _CircleReaderState extends State<_CircleReader> {
  late Map<String, dynamic> row = widget.initial;
  String? error;
  bool refreshing = false;
  CommunityController get c => widget.c;
  Future<void> refresh() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    try {
      final next = await c.request('GET', '/circles/${widget.id}');
      if (mounted) {
        setState(() {
          row = next;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = c.message(e));
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Future<void> mutate(Future<Map<String, dynamic>?> Function() action) async {
    final next = await action();
    if (mounted) {
      setState(() {
        if (next != null) row = next;
        error = c.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final p = AppPalette.of(context), content = row['content'] as Map;
      final pending = c.pending.containsKey('count:${widget.id}');
      return Scaffold(
        backgroundColor: p.background,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              DirectoryHeader(
                title: row['title'] as String,
                subtitle: 'مساهمة جماعية محفوظة على حسابك',
                onBack: () => Navigator.pop(context),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CommunityCard(
                      child: Column(
                        children: [
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              Text('العدد العام ${row['total']}'),
                              Text('المشاركون ${row['participants']}'),
                            ],
                          ),
                          const Divider(height: 28),
                          Text(
                            content['text'] as String,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 27,
                              height: 2,
                              color: p.tealHeading,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            content['source'] as String,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: p.muted),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'مساهمتك ${row['mine']}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'هدف الحلقة ${row['goal']} • هدف جماعي تنظيمي',
                            style: TextStyle(color: p.muted, fontSize: 12),
                          ),
                          const SizedBox(height: 20),
                          if (row['joined'] != true)
                            FilledButton.icon(
                              onPressed: c.working
                                  ? null
                                  : () => mutate(
                                      () => c.membership(widget.id, true),
                                    ),
                              icon: const Icon(Icons.group_add_outlined),
                              label: const Text('الانضمام للحلقة'),
                            )
                          else ...[
                            SizedBox(
                              width: 180,
                              height: 170,
                              child: FilledButton(
                                onPressed:
                                    c.working ||
                                        refreshing ||
                                        ((row['total'] as int) >=
                                                (row['goal'] as int) &&
                                            !pending)
                                    ? null
                                    : () => mutate(() => c.count(widget.id)),
                                style: FilledButton.styleFrom(
                                  backgroundColor: p.tealHeading,
                                  foregroundColor: p.dark
                                      ? Colors.black
                                      : Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(36),
                                  ),
                                ),
                                child: c.working
                                    ? const CircularProgressIndicator()
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            pending ? Icons.sync : Icons.add,
                                            size: 36,
                                          ),
                                          Text(
                                            pending
                                                ? 'إعادة إرسال المساهمة'
                                                : 'مساهمة واحدة',
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            TextButton(
                              onPressed: c.working
                                  ? null
                                  : () => mutate(
                                      () => c.membership(widget.id, false),
                                    ),
                              child: const Text('مغادرة الحلقة'),
                            ),
                          ],
                          if (pending)
                            const Text(
                              'هناك مساهمة بانتظار التأكيد. إعادة المحاولة تستخدم العملية نفسها حتى لا يتضاعف العدد.',
                              textAlign: TextAlign.center,
                            ),
                          if (pending)
                            TextButton(
                              onPressed: c.working
                                  ? null
                                  : () async {
                                      final confirmed = await _confirm(
                                        context,
                                        'إيقاف إعادة المحاولة؟',
                                        'قد تكون المساهمة وصلت للخادم. سيبقى العدد المؤكد على الخادم؛ لن تُرسل هذه العملية مجددًا.',
                                      );
                                      if (confirmed) {
                                        await c.discard('count:${widget.id}');
                                        await refresh();
                                      }
                                    },
                              child: const Text('إلغاء إعادة الإرسال'),
                            ),
                        ],
                      ),
                    ),
                    if (error != null) _CommunityNotice(error!),
                    OutlinedButton.icon(
                      onPressed: c.working || refreshing ? null : refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('تحديث الأعداد من الخادم'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _PrayerCard extends StatelessWidget {
  const _PrayerCard({
    required this.c,
    required this.row,
    required this.onChanged,
  });
  final CommunityController c;
  final Map<String, dynamic> row;
  final Future<void> Function() onChanged;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return _CommunityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, color: p.gold, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  row['author'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'خيارات المشاركة',
                onSelected: (value) =>
                    _entryAction(context, c, row, value, onChanged),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'copy', child: Text('نسخ')),
                  const PopupMenuItem(value: 'share', child: Text('مشاركة')),
                  if (row['mine'] == true)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('حذف مشاركتي'),
                    )
                  else ...[
                    const PopupMenuItem(
                      value: 'report',
                      child: Text('شكاية منشور'),
                    ),
                    const PopupMenuItem(
                      value: 'reportAccount',
                      child: Text('شكاية الحساب'),
                    ),
                    const PopupMenuItem(
                      value: 'block',
                      child: Text('حظر الحساب'),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (row['status'] != 'approved')
            Text(
              row['status'] == 'pending'
                  ? 'بانتظار المراجعة'
                  : 'غير معتمدة للنشر',
              style: TextStyle(color: p.gold, fontSize: 12),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Text(
              row['body'] as String,
              style: TextStyle(fontSize: 22, height: 1.9, color: p.tealHeading),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.spaceAround,
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: c.working || row['status'] != 'approved'
                    ? null
                    : () async {
                        await c.mutate(
                          'PUT',
                          '/entries/${row['id']}/like',
                          data: {'liked': row['liked'] != true},
                        );
                        await onChanged();
                      },
                icon: Icon(
                  row['liked'] == true ? Icons.favorite : Icons.favorite_border,
                ),
                label: Text('${row['likes']}'),
              ),
              TextButton.icon(
                onPressed: row['status'] != 'approved'
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => _CommentsPage(c: c, parent: row),
                        ),
                      ),
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text('${row['comments']}'),
              ),
              IconButton(
                onPressed: () => SharePlus.instance.share(
                  ShareParams(text: row['body'] as String),
                ),
                tooltip: 'مشاركة',
                icon: const Icon(Icons.share_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
