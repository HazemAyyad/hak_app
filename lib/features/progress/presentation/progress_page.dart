import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app_appearance.dart';
import '../../../navigation/more_page.dart';
import '../../quran/data/quran_repository.dart';
import '../../quran/data/quran_sync.dart' show operationId;
import '../../quran/presentation/quran_reader.dart';
import '../../religious_activity/data/activity_controller.dart';
import '../../religious_activity/data/activity_models.dart';
import '../../religious_content/data/religious_controller.dart';
import '../data/progress_controller.dart';

part 'progress_forms.dart';
part 'khatma_reader.dart';

enum ProgressSection { khatma, habits, statistics }

class ProgressPage extends StatefulWidget {
  const ProgressPage({
    super.key,
    required this.controller,
    required this.section,
  });
  final ReligiousController controller;
  final ProgressSection section;
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage>
    with WidgetsBindingObserver {
  ProgressController? _progress;
  ReligiousActivityController? _activity;
  late Future<ProgressController> _load = _prepare();
  GlobalKey<NavigatorState> _navigation = GlobalKey();
  Timer? _midnight;
  String? _day;
  Future<ProgressController> _prepare() async {
    final activity = await widget.controller.activity;
    if (!mounted) throw StateError('Closed');
    if (_activity != activity) {
      _activity?.removeListener(_account);
      _activity = activity..addListener(_account);
    }
    final c = await ProgressController.open(
      activity,
      widget.controller.quran.repository!,
    );
    if (!mounted || activity.scope != c.scope) {
      c.dispose();
      throw StateError('Account changed');
    }
    _progress = c;
    _day = c.day;
    return c;
  }

  void _account() {
    if (!mounted || _progress == null || _activity!.scope == _progress!.scope) {
      return;
    }
    _progress!.dispose();
    _progress = null;
    setState(() {
      _navigation = GlobalKey();
      _load = _prepare();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _midnight = Timer.periodic(const Duration(seconds: 30), (_) => _checkDay());
  }

  void _checkDay() {
    final c = _progress;
    if (c != null && c.available && _day != c.day) {
      _day = c.day;
      unawaited(c.refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDay();
      unawaited(_progress?.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    _activity?.removeListener(_account);
    _progress?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: FutureBuilder<ProgressController>(
      key: ValueKey(_navigation),
      future: _load,
      builder: (context, snapshot) {
        final c = snapshot.data;
        if (c == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('رحلتك مع حق')),
            body: Center(
              child: snapshot.hasError
                  ? TextButton(
                      onPressed: () => setState(() => _load = _prepare()),
                      child: const Text('تعذّر فتح التقدم؛ أعد المحاولة'),
                    )
                  : const CircularProgressIndicator(),
            ),
          );
        }
        return ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            if (!c.available) return const Scaffold(body: SizedBox.shrink());
            return NavigatorPopHandler<Object?>(
              onPopWithResult: (_) => _navigation.currentState?.maybePop(),
              child: Navigator(
                key: _navigation,
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => _ProgressHome(
                    c: c,
                    section: widget.section,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class _ProgressShell extends StatelessWidget {
  const _ProgressShell({
    required this.c,
    required this.title,
    required this.subtitle,
    required this.children,
    this.onBack,
  });
  final ProgressController c;
  final String title, subtitle;
  final List<Widget> children;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    if (!c.available) return const SizedBox.shrink();
    return Scaffold(
      backgroundColor: p.background,
      body: ListView(
        children: [
          Stack(
            children: [
              DirectoryHeader(
                title: title,
                subtitle: subtitle,
                maxTitleLines: 2,
              ),
              Positioned(
                top: 12,
                left: 16,
                child: IconButton.filledTonal(
                  tooltip: 'رجوع',
                  onPressed: onBack ?? () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(c.error!, style: TextStyle(color: p.heading)),
            ),
          for (final child in children)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: child,
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

Widget _panel(BuildContext context, Widget child, {bool tinted = false}) {
  final p = AppPalette.of(context);
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: tinted ? p.paleTeal : p.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: p.border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .025),
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class _ProgressHome extends StatefulWidget {
  const _ProgressHome({
    required this.c,
    required this.section,
    required this.onClose,
  });
  final ProgressController c;
  final ProgressSection section;
  final VoidCallback onClose;
  @override
  State<_ProgressHome> createState() => _ProgressHomeState();
}

class _ProgressHomeState extends State<_ProgressHome> {
  int _offset = 0;
  bool _allStats = false;
  ProgressController get c => widget.c;
  String _selectedDay() =>
      progressDay(civilDate(c.day).add(Duration(days: _offset)));
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final title = switch (widget.section) {
        ProgressSection.khatma => 'الختمة',
        ProgressSection.habits => 'عاداتي',
        ProgressSection.statistics => 'إحصائياتي',
      };
      return _ProgressShell(
        c: c,
        title: title,
        subtitle: 'خطوات صغيرة، وأثر طيب',
        onBack: widget.onClose,
        children: switch (widget.section) {
          ProgressSection.khatma => _khatmas(context),
          ProgressSection.habits => _habits(context),
          ProgressSection.statistics => _statistics(context),
        },
      );
    },
  );
  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  List<Widget> _khatmas(BuildContext context) => [
    FilledButton.icon(
      onPressed: () => _push(_KhatmaForm(c: c)),
      icon: const Icon(Icons.add),
      label: const Text('إنشاء ختمة جديدة'),
    ),
    const SizedBox(height: 16),
    if (c.khatmas.isEmpty)
      _panel(
        context,
        const Text(
          'لا توجد ختمة بعد. أنشئ خطة تناسب وقتك، ثم تابع وردك في قارئ القرآن.',
        ),
      ),
    for (final k in c.khatmas)
      _panel(
        context,
        InkWell(
          onTap: () => _push(_KhatmaDetails(c: c, id: k.id)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.menu_book_outlined,
                    color: Color(0xFF2A8C82),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      k.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_left),
                ],
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: c.fraction(k),
                minHeight: 7,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 10),
              Text(
                '${c.readPages(k).length} من ${k.lastPage - k.firstPage + 1} صفحة • ${c.completed(k)
                    ? 'مكتملة'
                    : k.archived == true
                    ? 'متوقفة'
                    : 'جارية'}',
              ),
              Text(
                '${k.startDate}  ←  ${k.endDate}',
                style: TextStyle(
                  color: AppPalette.of(context).muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        tinted: k.archived != true && !c.completed(k),
      ),
    const SizedBox(height: 8),
    const Text(
      'سجل الختمات يحتفظ بالخطط المكتملة والمتوقفة. إعادة البدء تحفظ تاريخ القراءة السابق.',
    ),
  ];
  List<Widget> _habits(BuildContext context) {
    final date = _selectedDay();
    final list = c.habits.where((h) => c.due(h, date)).toList();
    return [
      Row(
        children: [
          IconButton(
            tooltip: 'اليوم السابق',
            onPressed: () => setState(() => _offset--),
            icon: const Icon(Icons.chevron_right),
          ),
          Expanded(
            child: Text(
              _offset == 0 ? 'اليوم • $date' : date,
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            tooltip: 'اليوم التالي',
            onPressed: _offset == 0 ? null : () => setState(() => _offset++),
            icon: const Icon(Icons.chevron_left),
          ),
        ],
      ),
      Wrap(
        spacing: 6,
        children: [
          for (final i in [7, 1, 2, 3, 4, 5, 6])
            ChoiceChip(
              label: Text(_weekday(i)),
              selected: civilDate(date).weekday == i,
              onSelected: (_) {
                final sunday = civilDate(
                  date,
                ).subtract(Duration(days: civilDate(date).weekday % 7));
                final selected = sunday.add(Duration(days: i % 7));
                final offset = selected.difference(civilDate(c.day)).inDays;
                if (offset <= 0) setState(() => _offset = offset);
              },
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (list.isEmpty)
        _panel(context, const Text('لا توجد عادات مجدولة لهذا اليوم.')),
      for (final h in list)
        _panel(
          context,
          Column(
            children: [
              Row(
                children: [
                  Icon(_habitIcon(h.icon), color: const Color(0xFF2A8C82)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      h.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'تعديل العادة',
                    onPressed: () => _push(_HabitForm(c: c, value: h)),
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: c.habitCount(h, date) / h.target,
                minHeight: 6,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text('${c.habitCount(h, date)} / ${h.target}'),
                  ),
                  FilledButton.tonalIcon(
                    key: ValueKey('habit-count-${h.id}'),
                    onPressed: _offset != 0 || c.habitCount(h) >= h.target
                        ? null
                        : () => c.countHabit(h.id),
                    icon: Icon(
                      c.habitCount(h, date) >= h.target
                          ? Icons.check
                          : Icons.add,
                    ),
                    label: Text(
                      c.habitCount(h, date) >= h.target
                          ? 'مكتملة'
                          : 'تسجيل مرة',
                    ),
                  ),
                  IconButton(
                    tooltip: 'تراجع',
                    onPressed: _offset == 0 && c.habitCount(h) > 0
                        ? () => c.undoHabit(h.id)
                        : null,
                    icon: const Icon(Icons.undo),
                  ),
                ],
              ),
            ],
          ),
        ),
      FilledButton.icon(
        onPressed: () => _push(_HabitForm(c: c)),
        icon: const Icon(Icons.add),
        label: const Text('إضافة عادة'),
      ),
      for (final h in c.habits.where((h) => !c.due(h, date)))
        ListTile(
          title: Text(h.title),
          subtitle: Text(h.enabled ? 'غير مجدولة لهذا اليوم' : 'متوقفة'),
          trailing: IconButton(
            tooltip: 'تعديل العادة',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _push(_HabitForm(c: c, value: h)),
          ),
        ),
      const SizedBox(height: 8),
      const Text(
        'الأيام حسب التاريخ المحلي عند التسجيل. الأيام الماضية للعرض؛ لا تُضاف لها إنجازات بأثر رجعي.',
      ),
    ];
  }

  List<Widget> _statistics(BuildContext context) {
    final totals = c.totals(date: _allStats ? null : c.day);
    return [
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('اليوم')),
          ButtonSegment(value: true, label: Text('كل الوقت')),
        ],
        selected: {_allStats},
        onSelectionChanged: (v) => setState(() => _allStats = v.first),
      ),
      const SizedBox(height: 16),
      for (final (title, value, unit, icon) in [
        ('الأذكار', totals.adhkar, 'قراءة مسجلة', Icons.eco_outlined),
        ('التسبيح', totals.tasbih, 'تسبيحة', Icons.radio_button_checked),
        ('قراءة القرآن', totals.pages, 'صفحة مؤكدة', Icons.menu_book_outlined),
        ('العادات', totals.habits, 'مرة مسجلة', Icons.fact_check_outlined),
        ('سكينة', totals.breathingSeconds, 'ثانية مسجلة', Icons.air),
      ])
        _panel(
          context,
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: const Color(0xFF2A8C82)),
            title: Text(title),
            subtitle: Text('$value $unit'),
            onTap: title != 'الأذكار'
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('تفاصيل الأذكار'),
                      content: Text(
                        'أذكار الصباح: ${totals.morning}\nأذكار المساء: ${totals.evening}\nالأذكار الأخرى: ${totals.otherAdhkar}',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('تم'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      const Text(
        'القرآن يحتسب الصفحات التي أكّدت قراءتها في الختمة. لا تُحتسب مدة القراءة من فتح الشاشة، ولا يظهر وقت تقديري كأنه وقت مسجّل.',
      ),
      TextButton.icon(
        onPressed: () async {
          if (await _confirm(
            context,
            'تصفير عرض الإحصائيات؟',
            'يبدأ عرض الإحصائيات من الآن. يبقى تقدم العادات والختمات وتاريخ النشاط محفوظًا.',
          )) {
            await c.resetStatistics();
          }
        },
        icon: const Icon(Icons.restart_alt),
        label: const Text('تصفير الإحصائيات'),
      ),
    ];
  }
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    ) ??
    false;

String _weekday(int day) => [
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
][day - 1];
IconData _habitIcon(String? icon) => switch (icon) {
  'beads' => Icons.radio_button_checked,
  'moon' => Icons.nightlight_outlined,
  'sun' => Icons.wb_sunny_outlined,
  'heart' => Icons.favorite_border,
  'water' => Icons.water_drop_outlined,
  'learn' => Icons.school_outlined,
  'give' => Icons.volunteer_activism_outlined,
  'prayer' => Icons.mosque_outlined,
  'activity' => Icons.directions_walk,
  'sleep' => Icons.bedtime_outlined,
  'read' => Icons.auto_stories_outlined,
  _ => Icons.menu_book_outlined,
};
