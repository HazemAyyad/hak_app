import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/localization/app_localization.dart';
import '../../../core/localization/ui_text.dart';
import '../../../core/localization/locale_formats.dart';
import '../../../core/localization/content_presentation.dart';
import '../../sharing/share_card.dart';
import '../../../app_appearance.dart';
import '../../../navigation/more_page.dart';
import '../../quran/data/quran_sync.dart' show operationId;
import '../../religious_activity/data/activity_controller.dart';
import '../../religious_activity/data/activity_models.dart';
import '../../religious_content/data/religious_controller.dart';
import '../data/tasbih_controller.dart';
import '../data/tasbih_preferences.dart';
import '../data/tasbih_voice.dart';

part 'tasbih_counter_face.dart';

LocaleFormats _tasbihFormats(BuildContext context) =>
    LocalizationScope.maybeOf(context)?.formats ?? const LocaleFormats('ar');
String _tasbihNumber(BuildContext context, num value) =>
    _tasbihFormats(context).number(value);

PresentedSourceContent? _tasbihMeaning(
  BuildContext context,
  PersonalTasbih item,
) {
  final locale = LocalizationScope.maybeOf(context)?.contentCode ?? 'ar';
  if (!['en', 'tr'].contains(locale)) return null;
  final defaults = TasbihController.defaults();
  final index = defaults.indexWhere(
    (original) => original.id == item.id && original.text == item.text,
  );
  if (index < 0) {
    return null; // Personal or edited text is never translated by matching its words.
  }
  final source = ContentPresentationScope.libraryOf(
    context,
  ).cached(locale, 'dhikr');
  if (source == null) return null;
  final id = ['hisn-api-091', 'hisn-api-257', 'hisn-api-241'][index];
  final row = (source.data['entries'] as Map)[id] as Map;
  final excerpts = locale == 'en'
      ? [
          'How perfect Allah is and I praise Him.',
          'all praise is for Allah.',
          'Allah is the greatest.',
        ]
      : [
          "Allah'a hamd ederek O'nu tüm noksanlıklardan tenzih ederim.",
          "Hamd Allah'adır.",
          'Allah en büyüktür.',
        ];
  final excerpt = excerpts[index];
  final published = (row['text'] as String).replaceAll(RegExp(r'\s+'), ' ');
  if (!published.contains(excerpt)) return null;
  return PresentedSourceContent(
    locale: locale,
    kind: 'dhikr',
    source: source.source,
    records: [
      {...Map<String, dynamic>.from(row), 'text': excerpt},
    ],
  );
}

String _tasbihDisplayText(BuildContext context, PersonalTasbih item) =>
    _tasbihMeaning(context, item)?.text ?? item.text;

class _TasbihReadingText extends StatelessWidget {
  const _TasbihReadingText(this.item, {required this.style});
  final PersonalTasbih item;
  final TextStyle style;
  @override
  Widget build(BuildContext context) {
    final source = _tasbihMeaning(context, item);
    final text = source?.text ?? item.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text,
          textDirection: contentTextDirection(text),
          textAlign: TextAlign.center,
          style: style,
        ),
        if (source != null) ...[
          const SizedBox(height: 8),
          PresentedSourceFooter(source),
        ],
      ],
    );
  }
}

const tasbihStyleNames = [
  'أزرار',
  'ملء الشاشة',
  'دائرية',
  'أفقية',
  'تقليدية',
  'خاتم رقمي',
];

class TasbihPage extends StatefulWidget {
  const TasbihPage({super.key, required this.controller, this.speech});
  final ReligiousController controller;
  final TasbihSpeech? speech;
  @override
  State<TasbihPage> createState() => _TasbihPageState();
}

class _TasbihPageState extends State<TasbihPage> {
  final _navigator = GlobalKey<NavigatorState>();
  final _routes = RouteObserver<ModalRoute<dynamic>>();
  ReligiousActivityController? _activity;
  String? _scope;
  late Future<ReligiousActivityController> _load = _prepare();
  Future<ReligiousActivityController> _prepare() async {
    final value = await widget.controller.activity;
    if (mounted) {
      _activity = value;
      _scope = value.scope;
      value.addListener(_account);
    }
    return value;
  }

  void _account() {
    if (!mounted || _scope == _activity?.scope) return;
    _scope = _activity?.scope;
    _navigator.currentState?.popUntil((route) => route.isFirst);
    setState(() {});
  }

  @override
  void dispose() {
    _activity?.removeListener(_account);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection:
        LocalizationScope.maybeOf(context)?.language.direction ??
        TextDirection.rtl,
    child: FutureBuilder<ReligiousActivityController>(
      future: _load,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text(context.tasbihLabel('المسبحة'))),
            body: Center(
              child: snapshot.hasError
                  ? TextButton(
                      onPressed: () => setState(() => _load = _prepare()),
                      child: Text(
                        context.tasbihLabel(
                          'تعذّر فتح المسبحة؛ إعادة المحاولة',
                        ),
                      ),
                    )
                  : const CircularProgressIndicator(),
            ),
          );
        }
        return NavigatorPopHandler<void>(
          onPopWithResult: (_) => _navigator.currentState!.pop(),
          child: Navigator(
            key: _navigator,
            observers: [_routes],
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => _TasbihLibrary(
                key: ValueKey(_scope),
                activity: snapshot.data!,
                onClose: () => Navigator.of(context).pop(),
                onOpen: (counter) => _navigator.currentState!.push(
                  MaterialPageRoute<void>(
                    builder: (_) => TasbihReaderPage(
                      counter: counter,
                      routes: _routes,
                      controller: widget.controller,
                      speech: widget.speech,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _TasbihLibrary extends StatefulWidget {
  const _TasbihLibrary({
    super.key,
    required this.activity,
    required this.onOpen,
    required this.onClose,
  });
  final ReligiousActivityController activity;
  final Future<void> Function(TasbihController) onOpen;
  final VoidCallback onClose;
  @override
  State<_TasbihLibrary> createState() => _TasbihLibraryState();
}

class _TasbihLibraryState extends State<_TasbihLibrary> {
  late Future<List<PersonalTasbih>> _items = _loadItems();
  Map<String, int> _totals = {};
  Future<List<PersonalTasbih>> _loadItems() async {
    final scope = widget.activity.scope;
    final list = await TasbihController.library(widget.activity);
    final totals = <String, int>{};
    for (final item in list) {
      totals[item.id] = (await widget.activity.store.counts(
        scope,
        item.id,
        item.epoch,
      )).values.fold(0, (a, b) => a + b);
    }
    if (mounted && widget.activity.scope == scope) _totals = totals;
    return list;
  }

  bool _busy = false;
  late String _scope = widget.activity.scope;
  DateTime? _lastSync;
  @override
  void initState() {
    super.initState();
    widget.activity.addListener(_accountChanged);
  }

  void _accountChanged() {
    final lastSync = widget.activity.syncClient.lastSync[widget.activity.scope];
    if (!mounted || _scope == widget.activity.scope && _lastSync == lastSync) {
      return;
    }
    _lastSync = lastSync;
    _scope = widget.activity.scope;
    setState(() => _items = _loadItems());
  }

  @override
  void dispose() {
    widget.activity.removeListener(_accountChanged);
    super.dispose();
  }

  Future<void> _open(PersonalTasbih definition) async {
    if (_busy) return;
    _busy = true;
    final scope = widget.activity.scope;
    try {
      final counter = await TasbihController.open(widget.activity, definition);
      if (!mounted || widget.activity.scope != scope) {
        counter.dispose();
        return;
      }
      await widget.onOpen(counter);
      if (mounted && widget.activity.scope == scope) {
        setState(() => _items = _loadItems());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tasbihLabel('تعذّر فتح الذكر؛ حاول مجددًا')),
          ),
        );
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _create() async {
    final scope = widget.activity.scope;
    final result = await _editTasbih(context);
    if (result == null || !mounted || widget.activity.scope != scope) return;
    final next = PersonalTasbih(
      id: operationId(),
      text: result.$1,
      benefit: result.$2,
      goal: result.$3,
      epoch: operationId(),
      order: 100,
    );
    try {
      await widget.activity.store.save(scope, next);
      widget.activity.changed(scope);
      if (mounted && widget.activity.scope == scope) {
        setState(() => _items = _loadItems());
        await _open(next);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tasbihLabel('تعذّر حفظ الذكر'))),
        );
      }
    }
  }

  Future<void> _delete(PersonalTasbih item) async {
    final scope = widget.activity.scope;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(context.tasbihLabel('حذف الذكر من المسبحة؟')),
        content: Text(
          context.tasbihLabel(
            'تُحذف بطاقة الذكر وتبقى أحداث العدّ السابقة محفوظة.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tasbihLabel('إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tasbihLabel('حذف')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || widget.activity.scope != scope) return;
    try {
      await widget.activity.store.remove(
        scope,
        PersonalEntityKind.tasbih,
        item.id,
      );
      widget.activity.changed(scope);
      if (mounted && widget.activity.scope == scope) {
        setState(() => _items = _loadItems());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tasbihLabel('تعذّر حذف الذكر؛ حاول مجددًا')),
          ),
        );
      }
    }
  }

  Future<void> _menu(PersonalTasbih item, String action) async {
    if (action == 'delete') return _delete(item);
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: item.text));
      return;
    }
    if (action == 'share') {
      await _shareTasbih(context, item.text);
      return;
    }
    if (action == 'benefit') {
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: Text(context.tasbihLabel('فائدة الذكر / ملاحظتك')),
          content: Text(
            item.benefit.isEmpty
                ? context.tasbihLabel('لم تضف ملاحظة بعد.')
                : item.benefit,
            textDirection: item.benefit.isEmpty
                ? null
                : contentTextDirection(item.benefit),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tasbihLabel('إغلاق')),
            ),
          ],
        ),
      );
      return;
    }
    final scope = widget.activity.scope;
    final result = await _editTasbih(context, initial: item);
    if (result == null || !mounted || widget.activity.scope != scope) return;
    TasbihController? counter;
    try {
      counter = await TasbihController.open(widget.activity, item);
      await counter.edit(text: result.$1, benefit: result.$2, goal: result.$3);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tasbihLabel('تعذّر حفظ التعديل؛ حاول مجددًا'),
            ),
          ),
        );
      }
    } finally {
      counter?.dispose();
    }
    if (mounted && widget.activity.scope == scope) {
      setState(() => _items = _loadItems());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Scaffold(
      backgroundColor: p.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                DirectoryHeader(
                  title: context.tasbihLabel('المسبحة'),
                  subtitle: context.tasbihLabel('ذكر يدوم معك'),
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 12,
                  left: 16,
                  child: IconButton.filledTonal(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.arrow_back),
                    tooltip: context.tasbihLabel('رجوع'),
                  ),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tasbihLabel('اختر ذكرك'),
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: p.heading,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('tasbih-add'),
                      onPressed: _create,
                      icon: const Icon(Icons.add),
                      label: Text(context.tasbihLabel('إضافة')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  context.tasbihLabel('أهداف العدّ قابلة للتعديل حسب اختيارك.'),
                  style: TextStyle(color: p.muted),
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<PersonalTasbih>>(
                  future: _items,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return TextButton(
                        onPressed: () => setState(() => _items = _loadItems()),
                        child: Text(context.tasbihLabel('إعادة المحاولة')),
                      );
                    }
                    if (!snapshot.hasData ||
                        snapshot.connectionState != ConnectionState.done) {
                      return Center(child: CircularProgressIndicator());
                    }
                    return Column(
                      children: [
                        for (final item in snapshot.data!)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _card(
                              context,
                              ListTile(
                                key: ValueKey('tasbih-${item.id}'),
                                leading: Icon(
                                  Icons.radio_button_checked,
                                  color: p.tealHeading,
                                ),
                                title: Text(
                                  _tasbihDisplayText(context, item),
                                  textDirection: contentTextDirection(
                                    _tasbihDisplayText(context, item),
                                  ),
                                  style: TextStyle(
                                    color: p.heading,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  context.tr(
                                    'tasbih.itemSummary',
                                    args: {
                                      'goal': _tasbihNumber(context, item.goal),
                                      'total': _tasbihNumber(
                                        context,
                                        _totals[item.id] ?? 0,
                                      ),
                                    },
                                  ),
                                ),
                                trailing: PopupMenuButton<String>(
                                  tooltip: context.tasbihLabel('خيارات الذكر'),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text(context.tasbihLabel('تعديل')),
                                    ),
                                    PopupMenuItem(
                                      value: 'benefit',
                                      child: Text(
                                        context.tasbihLabel('الفائدة'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'copy',
                                      child: Text(context.tasbihLabel('نسخ')),
                                    ),
                                    PopupMenuItem(
                                      value: 'share',
                                      child: Text(
                                        context.tasbihLabel('مشاركة'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(context.tasbihLabel('حذف')),
                                    ),
                                  ],
                                  onSelected: (action) => _menu(item, action),
                                ),
                                onTap: () => _open(item),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class TasbihReaderPage extends StatefulWidget {
  const TasbihReaderPage({
    super.key,
    required this.counter,
    required this.routes,
    this.controller,
    this.speech,
  });
  final TasbihController counter;
  final RouteObserver<ModalRoute<dynamic>> routes;
  final ReligiousController? controller;
  final TasbihSpeech? speech;
  @override
  State<TasbihReaderPage> createState() => _TasbihReaderPageState();
}

class _TasbihReaderPageState extends State<TasbihReaderPage>
    with WidgetsBindingObserver, RouteAware {
  TasbihController get c => widget.counter;
  late final _settings = TasbihPreferences(
    c.activity.quran.preferences!,
    c.scope,
  );
  late final _voice = TasbihVoice(widget.speech ?? DeviceTasbihSpeech.shared);
  Timer? _auto;
  bool _tickPending = false, _visible = true;
  int? _completedRound;
  ModalRoute<dynamic>? _route;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_changed);
    _voice.addListener(_voiceChanged);
  }

  void _voiceChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!c.available) _stop();
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route) {
      widget.routes.unsubscribe(this);
      _route = route;
      if (route != null) widget.routes.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _visible = false;
    _stop();
  }

  @override
  void didPopNext() {
    _visible = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible =
        state == AppLifecycleState.resumed && (_route?.isCurrent ?? false);
    if (!_visible) _stop();
  }

  void _stop() {
    _auto?.cancel();
    _auto = null;
    unawaited(_voice.stop());
  }

  Future<void> _increment() async {
    if (!_visible || !c.available) return;
    final before = c.total, rounds = c.rounds;
    await c.increment();
    if (!mounted || !c.available || c.total == before) return;
    setState(() => _completedRound = c.rounds > rounds ? c.rounds : null);
    if (_settings.haptic) unawaited(HapticFeedback.selectionClick());
    if (_settings.countSound || _settings.goalSound && c.rounds > rounds) {
      unawaited(SystemSound.play(SystemSoundType.click));
    }
  }

  void _hold() {
    unawaited(_voice.stop());
    if (!_settings.autoCount) {
      unawaited(c.undo());
      return;
    }
    _auto?.cancel();
    _auto = Timer.periodic(const Duration(milliseconds: 180), (_) async {
      if (_tickPending || !_visible || !c.available) return;
      _tickPending = true;
      try {
        await _increment();
      } finally {
        _tickPending = false;
      }
    });
  }

  Future<T?> _dialog<T>(WidgetBuilder builder) async {
    _stop();
    final result = await showDialog<T>(
      context: context,
      useRootNavigator: false,
      builder: builder,
    );
    return result;
  }

  Future<void> _reset(bool all) async {
    final approved = await _dialog<bool>(
      (context) => AlertDialog(
        title: Text(
          all
              ? context.tasbihLabel('تصفير الإجمالي؟')
              : context.tasbihLabel('تصفير الحالي؟'),
        ),
        content: Text(
          all
              ? context.tasbihLabel(
                  'يبدأ عدّ جديد من الصفر. يبقى سجل الجلسات السابقة محفوظًا في الإحصائيات.',
                )
              : context.tasbihLabel(
                  'يعود العدّ الحالي للصفر مع الاحتفاظ بالإجمالي والجولات المكتملة.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tasbihLabel('إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tasbihLabel('تصفير')),
          ),
        ],
      ),
    );
    if (approved == true && mounted && c.available) {
      setState(() => _completedRound = null);
      if (all) {
        await c.resetAll();
      } else {
        await c.resetCurrent();
      }
    }
  }

  Future<void> _styles() => _dialog<void>(
    (context) => SimpleDialog(
      title: Text(context.tasbihLabel('شكل المسبحة')),
      children: [
        RadioGroup<TasbihStyle>(
          groupValue: c.definition.style,
          onChanged: (style) {
            Navigator.pop(context);
            if (style != null) unawaited(c.style(style));
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final style in TasbihStyle.values)
                RadioListTile<TasbihStyle>(
                  key: ValueKey('style-${style.name}'),
                  value: style,
                  title: Text(
                    context.tasbihLabel(tasbihStyleNames[style.index]),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  Future<void> _settingsDialog() => _dialog<void>(
    (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(context.tasbihLabel('إعدادات المسبحة')),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (key, label, value) in [
                  (
                    'haptic',
                    context.tasbihLabel('اهتزاز عند العدّ'),
                    _settings.haptic,
                  ),
                  (
                    'auto',
                    context.tasbihLabel('عدّ تلقائي عند الضغط المطوّل'),
                    _settings.autoCount,
                  ),
                  (
                    'countSound',
                    context.tasbihLabel('صوت عند كل ضغطة'),
                    _settings.countSound,
                  ),
                  (
                    'goalSound',
                    context.tasbihLabel('صوت عند اكتمال الجولة'),
                    _settings.goalSound,
                  ),
                ])
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    value: value,
                    subtitle: key == 'auto'
                        ? Text(
                            context.tasbihLabel(
                              'يتطلب تفعيل الاهتزاز؛ يتوقف عند رفع إصبعك',
                            ),
                          )
                        : null,
                    onChanged: key == 'auto' && !_settings.haptic
                        ? null
                        : (next) async {
                            await _settings.set(key, next);
                            if (context.mounted) update(() {});
                          },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tasbihLabel('تم')),
          ),
        ],
      ),
    ),
  );
  Future<void> _edit() async {
    _stop();
    final result = await _editTasbih(context, initial: c.definition);
    if (result != null && mounted && c.available) {
      await c.edit(text: result.$1, benefit: result.$2, goal: result.$3);
    }
  }

  Future<void> _stats() async {
    _stop();
    final events = await c.activity.store.events(
      c.scope,
      sessionId: c.definition.id,
    );
    if (!mounted || !c.available) return;
    final reversed = {for (final event in events) ?event.reverses};
    final days = <String, int>{};
    for (final event in events) {
      if (event.kind == ActivityKind.count && !reversed.contains(event.id)) {
        days.update(
          event.day,
          (value) => value + event.amount,
          ifAbsent: () => event.amount,
        );
      }
    }
    final list = days.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    await _dialog<void>(
      (context) => AlertDialog(
        title: Text(context.tasbihLabel('سجل المسبحة')),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr(
                    'tasbih.allSessions',
                    args: {
                      'count': _tasbihNumber(
                        context,
                        days.values.fold<int>(0, (a, b) => a + b),
                      ),
                    },
                  ),
                ),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  Text(context.tasbihLabel('ابدأ العدّ لعرض إحصائياتك')),
                for (final day in list)
                  ListTile(
                    title: Text(
                      _tasbihFormats(
                        context,
                      ).gregorianDate(DateTime.parse(day.key)),
                    ),
                    trailing: Text(_tasbihNumber(context, day.value)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tasbihLabel('إغلاق')),
          ),
        ],
      ),
    );
  }

  Future<void> _microphone() async {
    _auto?.cancel();
    if (_voice.active || _voice.starting) {
      await _voice.stop();
      return;
    }
    // Pause an existing owner through its own façade. Speech never resumes it.
    final media = widget.controller?.quran.audio;
    if (media?.playing == true) await media!.toggle();
    final religiousMedia = widget.controller?.media;
    if (religiousMedia?.playing == true) await religiousMedia!.toggle();
    if (!mounted || !_visible || !c.available) return;
    await _voice.start(c.definition.text, _increment);
  }

  @override
  void dispose() {
    _auto?.cancel();
    widget.routes.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _voice.removeListener(_voiceChanged);
    _voice.dispose();
    c.removeListener(_changed);
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    if (!c.available) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(context.tasbihLabel('افتح المسبحة مجددًا للحساب الحالي')),
        ),
      );
    }
    if (c.definition.style == TasbihStyle.fullscreen &&
        MediaQuery.sizeOf(context).height >= 600) {
      return Scaffold(
        backgroundColor: p.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: context.tasbihLabel('رجوع'),
                    ),
                    Expanded(
                      child: Text(
                        context.tasbihLabel('المسبحة'),
                        style: TextStyle(
                          color: p.heading,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _styles,
                      icon: const Icon(Icons.palette_outlined),
                      tooltip: context.tasbihLabel('الشكل'),
                    ),
                    IconButton(
                      onPressed: _settingsDialog,
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: context.tasbihLabel('الإعدادات'),
                    ),
                  ],
                ),
                SizedBox(
                  height: 116,
                  child: SingleChildScrollView(
                    child: _TasbihReadingText(
                      c.definition,
                      style: TextStyle(
                        color: p.tealHeading,
                        fontSize: 24,
                        height: 1.7,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _CounterFace(
                    counter: c,
                    increment: _increment,
                    undo: () => c.undo(),
                    onHold: _hold,
                    onRelease: () {
                      _auto?.cancel();
                      _auto = null;
                    },
                    onReset: () => _reset(false),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    context.tasbihLabel('اضغط للزيادة • اضغط مطوّلًا للنقصان'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 12),
                  ),
                ),
                Text(
                  context.tr(
                    'tasbih.totals',
                    args: {
                      'total': _tasbihNumber(context, c.total),
                      'rounds': _tasbihNumber(context, c.rounds),
                      'goal': _tasbihNumber(context, c.definition.goal),
                    },
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.tealHeading),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: c.canUndo ? () => c.undo() : null,
                      icon: const Icon(Icons.undo),
                      label: Text(context.tasbihLabel('تراجع')),
                    ),
                    TextButton.icon(
                      onPressed: () => _reset(false),
                      icon: const Icon(Icons.restart_alt),
                      label: Text(context.tasbihLabel('تصفير الحالي')),
                    ),
                  ],
                ),
                if (_completedRound != null) _completion(context),
                if (c.error != null)
                  Text(
                    context.tasbihLabel(c.error!),
                    style: const TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: p.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                DirectoryHeader(
                  title: context.tasbihLabel('المسبحة'),
                  subtitle: context.tasbihLabel('ذكر يدوم معك'),
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 12,
                  left: 16,
                  child: IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    tooltip: context.tasbihLabel('رجوع'),
                  ),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _card(
                  context,
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 24,
                    ),
                    child: Center(
                      child: _TasbihReadingText(
                        c.definition,
                        style: TextStyle(
                          color: p.tealHeading,
                          fontSize: 26,
                          height: 1.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _CounterFace(
                  counter: c,
                  increment: _increment,
                  undo: () => c.undo(),
                  onHold: _hold,
                  onRelease: () {
                    _auto?.cancel();
                    _auto = null;
                  },
                  onReset: () => _reset(false),
                ),
                const SizedBox(height: 10),
                Text(
                  c.definition.style == TasbihStyle.circular ||
                          c.definition.style == TasbihStyle.horizontal
                      ? context.tasbihLabel(
                          'اسحب لليمين للزيادة ولليسار للنقصان',
                        )
                      : context.tasbihLabel(
                          'اضغط للزيادة • اضغط مطوّلًا للنقصان',
                        ),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
                if (_completedRound != null) _completion(context),
                if (c.error != null)
                  Text(
                    context.tasbihLabel(c.error!),
                    style: const TextStyle(color: Colors.red),
                  ),
                const SizedBox(height: 14),
                FilledButton(
                  key: const ValueKey('tasbih-count'),
                  onPressed: _increment,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: appAccentFill(
                      context,
                      const Color(0xFF2A8C82),
                    ),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    context.tasbihLabel('اضغط للذكر'),
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: c.canUndo ? () => c.undo() : null,
                      icon: const Icon(Icons.undo),
                      label: Text(context.tasbihLabel('تراجع')),
                    ),
                    TextButton.icon(
                      onPressed: () => _reset(false),
                      icon: const Icon(Icons.restart_alt),
                      label: Text(context.tasbihLabel('تصفير الحالي')),
                    ),
                    TextButton.icon(
                      onPressed: _settingsDialog,
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(context.tasbihLabel('الإعدادات')),
                    ),
                  ],
                ),
                _card(
                  context,
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 8,
                    ),
                    child: Row(
                      children: [
                        for (final (label, value) in [
                          ('الإجمالي', c.total),
                          ('الجولات', c.rounds),
                          ('عدد الحبات', c.definition.goal),
                        ])
                          Expanded(
                            child: Column(
                              children: [
                                FittedBox(
                                  child: Text(
                                    _tasbihNumber(context, value),
                                    key: ValueKey('tasbih-stat-$label'),
                                    style: TextStyle(
                                      color: p.tealHeading,
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text(
                                  context.tasbihLabel(label),
                                  style: TextStyle(
                                    color: p.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _styles,
                      icon: const Icon(Icons.palette_outlined),
                      label: Text(context.tasbihLabel('الشكل')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _edit,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(context.tasbihLabel('تعديل')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _stats,
                      icon: const Icon(Icons.query_stats),
                      label: Text(context.tasbihLabel('الإحصائيات')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: c.definition.text),
                      ),
                      icon: const Icon(Icons.copy_outlined),
                      label: Text(context.tasbihLabel('نسخ')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        _stop();
                        unawaited(_shareTasbih(context, c.definition.text));
                      },
                      icon: const Icon(Icons.share_outlined),
                      label: Text(context.tasbihLabel('مشاركة')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _dialog<void>(
                        (context) => AlertDialog(
                          title: Text(
                            context.tasbihLabel('فائدة الذكر / ملاحظتك'),
                          ),
                          content: SingleChildScrollView(
                            child: Text(
                              c.definition.benefit.isEmpty
                                  ? context.tasbihLabel(
                                      'لم تضف ملاحظة لهذا الذكر بعد.',
                                    )
                                  : c.definition.benefit,
                              textDirection: c.definition.benefit.isEmpty
                                  ? null
                                  : contentTextDirection(c.definition.benefit),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(context.tasbihLabel('إغلاق')),
                            ),
                          ],
                        ),
                      ),
                      icon: const Icon(Icons.info_outline),
                      label: Text(context.tasbihLabel('الفائدة')),
                    ),
                    TextButton(
                      onPressed: () => _reset(true),
                      child: Text(context.tasbihLabel('تصفير الإجمالي')),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _card(
                  context,
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('tasbih-mic'),
                          onPressed: _microphone,
                          icon: Icon(
                            _voice.active || _voice.starting
                                ? Icons.mic_off
                                : Icons.mic_none,
                          ),
                          label: Text(
                            _voice.starting
                                ? context.tasbihLabel('جارٍ تجهيز الميكروفون…')
                                : _voice.active
                                ? context.tasbihLabel('إيقاف الاستماع')
                                : context.tasbihLabel('العدّ بالصوت'),
                          ),
                        ),
                        Text(
                          (_voice.message == null
                                  ? null
                                  : context.tasbihLabel(_voice.message!)) ??
                              context.tasbihLabel(
                                'استماع قصير للذكر المختار. قد تعالج خدمة التعرف في جهازك الصوت عبر الإنترنت. لا نحفظ تسجيلًا أو نصًّا صوتيًا.',
                              ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: p.muted,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _completion(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.of(context).notice,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr(
              'tasbih.roundComplete',
              args: {'round': _tasbihNumber(context, _completedRound!)},
            ),
            style: TextStyle(
              color: AppPalette.of(context).heading,
              fontWeight: FontWeight.bold,
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: () => setState(() => _completedRound = null),
                child: Text(context.tasbihLabel('تم')),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _completedRound = null);
                  unawaited(_increment());
                },
                child: Text(context.tasbihLabel('متابعة التسبيح')),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Future<void> _shareTasbih(BuildContext context, String text) async {
  await chooseContentShare(context, ShareCardContent.adhkar(text));
}

Widget _card(BuildContext context, Widget child) {
  final p = AppPalette.of(context);
  return Container(
    decoration: BoxDecoration(
      color: p.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: p.border),
      boxShadow: p.dark
          ? []
          : [
              BoxShadow(
                color: p.border.withValues(alpha: .5),
                offset: const Offset(0, 3),
                blurRadius: 2,
              ),
            ],
    ),
    child: Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
}

Future<(String, String, int)?> _editTasbih(
  BuildContext context, {
  PersonalTasbih? initial,
}) async {
  final text = TextEditingController(text: initial?.text),
      benefit = TextEditingController(text: initial?.benefit),
      goal = TextEditingController(text: '${initial?.goal ?? 100}');
  final form = GlobalKey<FormState>();
  int? parse() {
    var raw = goal.text.trim();
    const arabic = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      raw = raw.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
    }
    return int.tryParse(raw);
  }

  try {
    return await showDialog<(String, String, int)>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(
          initial == null
              ? context.tasbihLabel('ذكر جديد')
              : context.tasbihLabel('تعديل الذكر'),
        ),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: text,
                    builder: (context, value, _) => TextFormField(
                      controller: text,
                      textDirection: contentTextDirection(value.text),
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: context.tasbihLabel('نص الذكر'),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? context.tasbihLabel('أدخل نص الذكر')
                          : null,
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: benefit,
                    builder: (context, value, _) => TextFormField(
                      controller: benefit,
                      textDirection: contentTextDirection(value.text),
                      maxLength: 2000,
                      minLines: 2,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: context.tasbihLabel(
                          'فائدة أو ملاحظة شخصية (اختياري)',
                        ),
                      ),
                    ),
                  ),
                  TextFormField(
                    controller: goal,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tasbihLabel('عدد الحبات في الجولة'),
                    ),
                    validator: (_) =>
                        parse() == null || parse()! < 1 || parse()! > 1000000
                        ? context.tasbihLabel(
                            'أدخل عددًا صحيحًا من 1 إلى 1000000',
                          )
                        : null,
                  ),
                  if (initial != null)
                    Text(
                      context.tasbihLabel(
                        'تغيير عدد الحبات يبدأ عدًّا حاليًا جديدًا ويحفظ الإجمالي والجولات المكتملة.',
                      ),
                      style: TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tasbihLabel('إلغاء')),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, (
                  text.text.trim(),
                  benefit.text.trim(),
                  parse()!,
                ));
              }
            },
            child: Text(context.tasbihLabel('حفظ')),
          ),
        ],
      ),
    );
  } finally {
    // Dialog exit animations still reference controllers for a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      text.dispose();
      benefit.dispose();
      goal.dispose();
    });
  }
}
