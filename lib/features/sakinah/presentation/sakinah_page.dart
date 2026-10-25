import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app_appearance.dart';
import '../../../navigation/more_page.dart';
import '../../quran/data/quran_sync.dart' show operationId;
import '../../religious_activity/data/activity_controller.dart';
import '../../religious_activity/data/activity_models.dart';
import '../../religious_content/data/religious_controller.dart';
import '../data/breathing_session.dart';
import '../data/sakinah_record.dart';

part 'sakinah_session_page.dart';

class SakinahPage extends StatefulWidget {
  const SakinahPage({super.key, required this.controller, this.monotonicClock});
  final ReligiousController controller;
  final Duration Function()? monotonicClock;
  @override
  State<SakinahPage> createState() => _SakinahPageState();
}

class _SakinahPageState extends State<SakinahPage> {
  ReligiousActivityController? _activity;
  String? _scope;
  GlobalKey<NavigatorState> _navigator = GlobalKey();
  final _routes = RouteObserver<ModalRoute<dynamic>>();
  late Future<ReligiousActivityController> _load = _prepare();
  Future<ReligiousActivityController> _prepare() async {
    final activity = await widget.controller.activity;
    if (!mounted) throw StateError('Closed');
    _activity = activity;
    _scope = activity.scope;
    activity.removeListener(_account);
    activity.addListener(_account);
    return activity;
  }

  void _account() {
    if (!mounted || _scope == _activity?.scope) return;
    setState(() {
      _scope = _activity?.scope;
      _navigator = GlobalKey();
    });
  }

  @override
  void dispose() {
    _activity?.removeListener(_account);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: FutureBuilder<ReligiousActivityController>(
      future: _load,
      builder: (context, snapshot) {
        final activity = snapshot.data;
        if (activity == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('سكينة')),
            body: Center(
              child: snapshot.hasError
                  ? TextButton(
                      onPressed: () => setState(() => _load = _prepare()),
                      child: const Text('تعذّر فتح سكينة؛ أعد المحاولة'),
                    )
                  : const CircularProgressIndicator(),
            ),
          );
        }
        return NavigatorPopHandler<Object?>(
          onPopWithResult: (_) => _navigator.currentState?.maybePop(),
          child: Navigator(
            key: _navigator,
            observers: [_routes],
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => _SakinahLayout(
                title: 'سكينة',
                subtitle: 'لحظات من الطمأنينة',
                onBack: () => Navigator.of(this.context).pop(),
                children: [
                  _sPanel(
                    context,
                    const Text(
                      'مساحة للتنفس والذكر بهدوء، وليست بديلًا عن المساعدة المختصة. اختر الإيقاع والمدة المناسبين لك.',
                    ),
                    tinted: true,
                  ),
                  for (var i = 0; i < sakinahPaths.length; i++)
                    _sPanel(
                      context,
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          [
                            Icons.air,
                            Icons.spa_outlined,
                            Icons.favorite_border,
                            Icons.eco_outlined,
                            Icons.wb_sunny_outlined,
                          ][i],
                          color: const Color(0xFF2A8C82),
                        ),
                        title: Text(
                          sakinahNames[i],
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: const Text('اختر النمط والمدة ثم ابدأ'),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => _SakinahSetup(
                              controller: widget.controller,
                              activity: activity,
                              scope: _scope!,
                              path: i,
                              routes: _routes,
                              clock: widget.monotonicClock,
                            ),
                          ),
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            _SakinahHistory(activity: activity, scope: _scope!),
                      ),
                    ),
                    icon: const Icon(Icons.history),
                    label: const Text('سجل الجلسات'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _SakinahLayout extends StatelessWidget {
  const _SakinahLayout({
    required this.title,
    required this.subtitle,
    required this.children,
    this.onBack,
  });
  final String title, subtitle;
  final List<Widget> children;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.of(context).background,
    body: ListView(
      children: [
        Stack(
          children: [
            DirectoryHeader(
              title: title,
              subtitle: subtitle,
              imageAsset: 'assets/navigation/sakinah.png',
              maxTitleLines: 2,
            ),
            Positioned(
              top: 14,
              left: 16,
              child: IconButton.filledTonal(
                tooltip: 'رجوع',
                onPressed: onBack ?? () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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

Widget _sPanel(BuildContext context, Widget child, {bool tinted = false}) {
  final p = AppPalette.of(context);
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: tinted ? p.paleTeal : p.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: p.border),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class _SakinahSetup extends StatefulWidget {
  const _SakinahSetup({
    required this.controller,
    required this.activity,
    required this.scope,
    required this.path,
    required this.routes,
    this.clock,
  });
  final ReligiousController controller;
  final ReligiousActivityController activity;
  final String scope;
  final int path;
  final RouteObserver<ModalRoute<dynamic>> routes;
  final Duration Function()? clock;
  @override
  State<_SakinahSetup> createState() => _SakinahSetupState();
}

class _SakinahSetupState extends State<_SakinahSetup> {
  int _pattern = 0, _minutes = 1;
  List<int> _custom = [4, 0, 4, 0];
  bool _reduced = false, _haptic = false, _record = true, _starting = false;
  String? _error;
  static const names = [
    'تنفّس الاسترخاء',
    'التنفّس الصندوقي',
    'التنفّس المتناغم',
    'نمط مخصص',
  ];
  @override
  void initState() {
    super.initState();
    try {
      final data =
          jsonDecode(
                widget.controller.quran.preferences!.getString(
                      'sakinah.settings.${widget.scope}',
                    ) ??
                    '{}',
              )
              as Map;
      final pattern = data['pattern'] as int? ?? 0,
          minutes = data['minutes'] as int? ?? 1;
      final custom = List<int>.from(data['custom'] as List? ?? [4, 0, 4, 0]);
      if (custom.length != 4 ||
          pattern < 0 ||
          pattern > 3 ||
          ![1, 3, 5].contains(minutes)) {
        throw const FormatException('Settings');
      }
      BreathingPattern(custom[0], custom[1], custom[2], custom[3]);
      _pattern = pattern;
      _minutes = minutes;
      _custom = custom;
      _reduced = data['reduced'] as bool? ?? false;
      _haptic = data['haptic'] as bool? ?? false;
      _record = data['record'] as bool? ?? true;
    } catch (_) {
      /* Invalid optional preferences never replace the saved value. */
    }
  }

  BreathingPattern get _selected => switch (_pattern) {
    0 => BreathingPattern.relaxing,
    1 => BreathingPattern.box,
    2 => BreathingPattern.coherent,
    _ => BreathingPattern(_custom[0], _custom[1], _custom[2], _custom[3]),
  };
  Future<void> _start() async {
    if (_starting || widget.activity.scope != widget.scope) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final saved = await widget.controller.quran.preferences!.setString(
        'sakinah.settings.${widget.scope}',
        jsonEncode({
          'pattern': _pattern,
          'minutes': _minutes,
          'custom': _custom,
          'reduced': _reduced,
          'haptic': _haptic,
          'record': _record,
        }),
      );
      if (!saved) throw StateError('Preferences');
      if (!mounted || widget.activity.scope != widget.scope) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => _SakinahSessionPage(
            controller: widget.controller,
            activity: widget.activity,
            scope: widget.scope,
            path: widget.path,
            pattern: _selected,
            minutes: _minutes,
            routes: widget.routes,
            reduced: _reduced,
            haptic: _haptic,
            record: _record,
            clock: widget.clock,
          ),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذّر بدء الجلسة؛ أعد المحاولة');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SakinahLayout(
    title: sakinahNames[widget.path],
    subtitle: 'اختر إيقاعك وخذ لحظة هادئة',
    children: [
      RadioGroup<int>(
        groupValue: _pattern,
        onChanged: (v) => setState(() => _pattern = v!),
        child: Column(
          children: [
            for (var i = 0; i < names.length; i++)
              _sPanel(
                context,
                Column(
                  children: [
                    RadioListTile<int>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(names[i]),
                      subtitle: Text(
                        i == 0
                            ? '4 / 7 / 8 / 0 ثوانٍ'
                            : i == 1
                            ? '4 / 4 / 4 / 4 ثوانٍ'
                            : i == 2
                            ? '5 / 0 / 5 / 0 ثوانٍ'
                            : 'عدّل مدة كل مرحلة',
                      ),
                      value: i,
                    ),
                    TextButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        useRootNavigator: false,
                        builder: (context) => AlertDialog(
                          title: Text(names[i]),
                          content: const Text(
                            'الترتيب: شهيق، حبس بعد الشهيق، زفير، ثم حبس بعد الزفير. تتجاوز الجلسة أي مرحلة مدتها صفر. المدد بالثواني؛ اختر نمطًا مريحًا ويمكنك الوقف أو الإنهاء في أي وقت.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('تم'),
                            ),
                          ],
                        ),
                      ),
                      icon: const Icon(Icons.info_outline),
                      label: const Text('عن النمط'),
                    ),
                    if (i == 3 && _pattern == 3) ...[
                      for (var step = 0; step < 4; step++)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                [
                                  'الشهيق',
                                  'حبس بعد الشهيق',
                                  'الزفير',
                                  'حبس بعد الزفير',
                                ][step],
                              ),
                            ),
                            IconButton(
                              key: ValueKey('breath-minus-$step'),
                              tooltip: 'تقليل المرحلة ${step + 1}',
                              onPressed: _custom[step] <= (step.isEven ? 1 : 0)
                                  ? null
                                  : () => setState(() => _custom[step]--),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text('${_custom[step]}'),
                            IconButton(
                              key: ValueKey('breath-plus-$step'),
                              tooltip: 'زيادة المرحلة ${step + 1}',
                              onPressed: _custom[step] >= 20
                                  ? null
                                  : () => setState(() => _custom[step]++),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
      _sPanel(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'مدة الجلسة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final minute in [1, 3, 5])
                  ChoiceChip(
                    label: Text('$minute ${minute == 1 ? 'دقيقة' : 'دقائق'}'),
                    selected: _minutes == minute,
                    onSelected: (_) => setState(() => _minutes = minute),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تقليل الحركة'),
              value: _reduced,
              onChanged: (v) => setState(() => _reduced = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('اهتزاز عند تغير المرحلة'),
              value: _haptic,
              onChanged: (v) => setState(() => _haptic = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('حفظ مدة الجلسة في سجلي'),
              value: _record,
              onChanged: (v) => setState(() => _record = v),
            ),
            const Text(
              'التمهيد ثلاث ثوانٍ خارج مدة الجلسة. عند مغادرة الشاشة أو انتقال التطبيق للخلفية تتوقف الجلسة، والمتابعة باختيارك. الذكر اختياري دون عدد مرتبط بالتنفّس.',
            ),
          ],
        ),
      ),
      if (_error != null) Text(_error!),
      FilledButton.icon(
        onPressed: _starting ? null : _start,
        icon: const Icon(Icons.play_arrow),
        label: Text(_starting ? 'جارٍ التحضير…' : 'ابدأ الجلسة'),
      ),
    ],
  );
}

class _SakinahHistory extends StatefulWidget {
  const _SakinahHistory({required this.activity, required this.scope});
  final ReligiousActivityController activity;
  final String scope;
  @override
  State<_SakinahHistory> createState() => _SakinahHistoryState();
}

String _historyTitle(String subject) {
  final index = sakinahPaths.indexOf(subject.substring('breathing:'.length));
  return index < 0 ? 'جلسة تنفّس' : sakinahNames[index];
}

class _SakinahHistoryState extends State<_SakinahHistory> {
  late Future<List<ReligiousActivityEvent>> _load = widget.activity.store
      .events(widget.scope);
  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<ReligiousActivityEvent>>(
    future: _load,
    builder: (context, snapshot) {
      final events = snapshot.data ?? [];
      final complete = events
          .where(
            (e) =>
                e.kind == ActivityKind.complete &&
                e.subjectId.startsWith('breathing:'),
          )
          .map((e) => e.sessionId)
          .toSet();
      final sessions =
          events
              .where(
                (e) =>
                    e.kind == ActivityKind.breathing &&
                    e.subjectId.startsWith('breathing:'),
              )
              .toList()
            ..sort((a, b) {
              final time = b.occurredAt.compareTo(a.occurredAt);
              return time == 0 ? b.id.compareTo(a.id) : time;
            });
      return _SakinahLayout(
        title: 'سجل الجلسات',
        subtitle: 'لحظاتك المحفوظة كما سجّلتها',
        children: [
          if (snapshot.hasError)
            TextButton(
              onPressed: () => setState(
                () => _load = widget.activity.store.events(widget.scope),
              ),
              child: const Text('تعذّر فتح السجل؛ أعد المحاولة'),
            ),
          if (!snapshot.hasData && !snapshot.hasError)
            const Center(child: CircularProgressIndicator()),
          if (snapshot.hasData && sessions.isEmpty)
            const Text('لا توجد جلسات محفوظة بعد.'),
          for (final e in sessions)
            _sPanel(
              context,
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  complete.contains(e.sessionId)
                      ? Icons.check_circle_outline
                      : Icons.stop_circle_outlined,
                ),
                title: Text(_historyTitle(e.subjectId)),
                subtitle: Text(
                  '${e.day} • ${e.amount} ثانية • ${complete.contains(e.sessionId) ? 'مكتملة' : 'انتهت مبكرًا'}',
                ),
              ),
            ),
        ],
      );
    },
  );
}
