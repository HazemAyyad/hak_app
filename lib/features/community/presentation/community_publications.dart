part of 'community_page.dart';

const publicationKinds = <String?, String>{
  null: 'إظهار الكل',
  'quran': 'قرآن',
  'hadith': 'حديث',
  'dua': 'دعاء',
  'dhikr': 'ذكر',
  'tasbih': 'تسبيح',
  'video': 'فيديو',
  'link': 'رابط',
};

String publicationText(Map row) {
  final content = row['content'] as Map?;
  return content == null
      ? (row['body'] as String? ?? '')
      : '${content['text']}\n\n${content['source']}';
}

Future<void> _messageOptions(
  BuildContext context,
  CommunityController c,
  Future<void> Function() refresh,
) async {
  final scope = c.scope, token = c.quran.account.token;
  bool current() =>
      context.mounted && c.scope == scope && c.quran.account.token == token;
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('تنبيه رسائل حق'),
            subtitle: Text(c.messageSound ? 'تنبيه مع صوت' : 'صامت'),
            onTap: () => Navigator.pop(ctx, 'sound'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('حذف كافة الرسائل من هذا الجهاز'),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || !current()) return;
  if (choice == 'delete' &&
      await _confirm(
        context,
        'حذف كافة الرسائل؟',
        'سيُخفى كل ما سبق من الرسائل عن هذا الحساب على هذا الجهاز. لا يؤثر على رسائل الآخرين أو الرسائل الجديدة لاحقًا.',
      )) {
    if (current()) await c.hideAll();
  }
  if (choice == 'sound') {
    if (!context.mounted) return;
    final sound = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('تنبيه رسائل حق'),
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'هذا اختيار التنبيه عند تحديث القسم وهو مفتوح. إشعارات التطبيق المغلق لها خيار مستقل أعلى صفحة الرسائل، وتحتاج تهيئة الخدمة وإذن النظام؛ تصل بصمت للمحتوى العام.',
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('صامت'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تنبيه مع صوت'),
          ),
        ],
      ),
    );
    if (sound != null && current()) await c.setSound(sound);
  }
}

class _PublicationCard extends StatelessWidget {
  const _PublicationCard({
    required this.c,
    required this.row,
    required this.story,
    required this.onOpen,
  });
  final CommunityController c;
  final Map<String, dynamic> row;
  final bool story;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return _CommunityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                story
                    ? Icons.auto_stories_outlined
                    : Icons.mark_email_read_outlined,
                color: p.gold,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  row['title'] as String,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'خيارات الرسالة',
                onSelected: (value) async {
                  final scope = c.scope, token = c.quran.account.token;
                  try {
                    if (value == 'copy') {
                      await Clipboard.setData(
                        ClipboardData(text: publicationText(row)),
                      );
                    }
                    if (value == 'share') {
                      await SharePlus.instance.share(
                        ShareParams(text: publicationText(row)),
                      );
                    }
                    if (value == 'save') await c.toggleSave(row['id'] as int);
                    if (value == 'delete' &&
                        context.mounted &&
                        await _confirm(
                          context,
                          'حذف الرسالة؟',
                          'تُخفى هذه الرسالة محليًا لهذا الحساب فقط.',
                        )) {
                      if (context.mounted &&
                          c.scope == scope &&
                          c.quran.account.token == token) {
                        await c.hide(row['id'] as int);
                      }
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تعذّر إكمال الإجراء المحلي'),
                        ),
                      );
                    }
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'copy', child: Text('نسخ')),
                  const PopupMenuItem(value: 'share', child: Text('مشاركة')),
                  PopupMenuItem(
                    value: 'save',
                    child: Text(
                      c.saved.contains(row['id']) ? 'إلغاء الحفظ' : 'حفظ',
                    ),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('حذف محلي')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            publicationKinds[row['kind']] ?? 'محتوى',
            style: TextStyle(
              color: row['kind'] == 'video' ? p.gold : p.muted,
              fontSize: 12,
            ),
          ),
          if (publicationText(row).isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                publicationText(row),
                style: TextStyle(
                  fontSize: 19,
                  height: 1.9,
                  color: p.tealHeading,
                ),
              ),
            ),
          if (row['media_url'] != null && row['kind'] != 'video')
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                row['media_url'] as String,
                height: 190,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 100,
                  child: Center(child: Text('تعذّر تحميل الصورة')),
                ),
              ),
            ),
          if (row['kind'] == 'video')
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('تشغيل الفيديو'),
            ),
          if (row['kind'] == 'link' && row['link'] != null)
            OutlinedButton.icon(
              onPressed: () =>
                  openCommunityLink(context, row['link'] as String),
              icon: const Icon(Icons.open_in_new),
              label: const Text('فتح الرابط'),
            ),
          if (story && row['kind'] != 'video')
            TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.auto_stories_outlined),
              label: const Text('مشاهدة القصة'),
            ),
        ],
      ),
    );
  }
}

class CommunityStoryPage extends StatefulWidget {
  const CommunityStoryPage({
    super.key,
    required this.c,
    required this.rows,
    required this.index,
    this.beforeMedia,
  });
  final CommunityController c;
  final List<Map<String, dynamic>> rows;
  final int index;
  final Future<void> Function()? beforeMedia;
  @override
  State<CommunityStoryPage> createState() => _CommunityStoryPageState();
}

class _CommunityStoryPageState extends State<CommunityStoryPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late int index = widget.index;
  late final progress = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..addStatusListener(_completed);
  bool paused = false;
  String? mediaError;
  Map<String, dynamic> get row => widget.rows[index];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    progress.reset();
    if (row['kind'] != 'video' &&
        !paused &&
        row['channel'] == 'story' &&
        !MediaQueryData.fromView(
          WidgetsBinding.instance.platformDispatcher.views.first,
        ).disableAnimations) {
      progress.forward();
    }
  }

  void _completed(AnimationStatus state) {
    if (state == AnimationStatus.completed) _next();
  }

  void _next() {
    if (index + 1 >= widget.rows.length) {
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() => index++);
    _start();
  }

  void _previous() {
    if (index == 0) return;
    setState(() => index--);
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      progress.stop();
      if (mounted) setState(() => paused = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: AnimatedBuilder(
                      animation: progress,
                      builder: (_, _) => LinearProgressIndicator(
                        value: row['kind'] == 'video' ? null : progress.value,
                        color: p.tealHeading,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      row['title'] as String,
                      style: TextStyle(
                        color: p.heading,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (row['kind'] == 'video')
                      CommunityMediaView(
                        key: ValueKey(row['id']),
                        row: row,
                        beforePlay: widget.beforeMedia,
                        onEnded: () =>
                            row['channel'] == 'story' ? _next() : null,
                      ),
                    if (row['media_url'] != null && row['kind'] != 'video')
                      Image.network(
                        row['media_url'] as String,
                        errorBuilder: (_, _, _) =>
                            const Text('تعذّر تحميل الصورة'),
                      ),
                    SelectableText(
                      publicationText(row),
                      style: TextStyle(
                        fontSize: 25,
                        height: 2,
                        color: p.tealHeading,
                      ),
                    ),
                    if (row['kind'] == 'link')
                      OutlinedButton(
                        onPressed: () =>
                            openCommunityLink(context, row['link'] as String),
                        child: const Text('فتح الرابط'),
                      ),
                  ],
                ),
              ),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                IconButton(
                  tooltip: 'السابق',
                  onPressed: index == 0 ? null : _previous,
                  icon: const Icon(Icons.skip_next),
                ),
                if (row['kind'] != 'video')
                  IconButton(
                    tooltip: paused ? 'متابعة' : 'إيقاف مؤقت',
                    onPressed: () {
                      setState(() => paused = !paused);
                      if (paused) {
                        progress.stop();
                      } else {
                        progress.forward();
                      }
                    },
                    icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                  ),
                IconButton(
                  tooltip: 'التالي',
                  onPressed: _next,
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton(
                  tooltip: 'مشاركة',
                  onPressed: () async {
                    progress.stop();
                    setState(() => paused = true);
                    await SharePlus.instance.share(
                      ShareParams(text: publicationText(row)),
                    );
                  },
                  icon: const Icon(Icons.share_outlined),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
