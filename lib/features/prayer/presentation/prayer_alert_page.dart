part of 'prayer_page.dart';

class PrayerAlertPage extends StatefulWidget {
  const PrayerAlertPage({
    super.key,
    required this.controller,
    required this.prayer,
    this.library,
    this.beforeAudio,
    this.enableReminders,
  });
  final PrayerController controller;
  final PrayerName prayer;
  final AdhanLibrary? library;
  final Future<void> Function()? beforeAudio;
  final Future<bool> Function()? enableReminders;
  @override
  State<PrayerAlertPage> createState() => _PrayerAlertPageState();
}

class _PrayerAlertPageState extends State<PrayerAlertPage>
    with WidgetsBindingObserver {
  late final library =
      widget.library ?? AdhanLibrary(beforePlay: widget.beforeAudio);
  late PrayerAlert draft;
  late bool enabled;
  late String _owner, _initial;
  bool _saving = false, _leaving = false, _mayPop = false;
  int _generation = 0;
  String search = '';
  Map<String, dynamic> device = {};
  String get snapshot => jsonEncode({'enabled': enabled, ...draft.toJson()});
  bool get dirty => snapshot != _initial;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _owner = widget.controller.scope;
    _fill();
    widget.controller.addListener(_account);
    unawaited(library.initialize());
    unawaited(_status());
  }

  void _fill() {
    draft = widget.controller.config.alert(widget.prayer);
    enabled =
        widget.controller.config.notifications &&
        widget.controller.config.enabledPrayers.contains(widget.prayer.name);
    _initial = snapshot;
  }

  Future<void> _status() async {
    try {
      final state = await AdhanLibrary.bridge.invokeMapMethod<String, dynamic>(
        'adhanStatus',
      );
      if (mounted) setState(() => device = state ?? {});
    } catch (_) {
      /* Unsupported platforms retain an explicit unavailable state. */
    }
  }

  void _account() {
    if (_owner == widget.controller.scope) return;
    _owner = widget.controller.scope;
    _saving = false;
    ++_generation;
    unawaited(library.stop());
    if (mounted) setState(_fill);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_status());
    } else {
      unawaited(library.stop());
    }
  }

  Future<void> _close() async {
    setState(() => _mayPop = true);
    await library.stop();
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _leave() async {
    if (_leaving || _saving) return;
    if (!dirty) {
      await _close();
      return;
    }
    _leaving = true;
    final owner = _owner;
    final generation = _generation;
    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline,
                color: AppPalette.of(context).gold,
                size: 38,
              ),
              const SizedBox(height: 16),
              const Text(
                'التغييرات غير محفوظة',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'احفظ إعدادات هذا الوقت أو اخرج دون تطبيق التعديلات.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('احفظ التغييرات'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('تجاهل التغييرات'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('متابعة التعديل'),
              ),
            ],
          ),
        ),
      ),
    );
    _leaving = false;
    if (!mounted || owner != _owner || generation != _generation) return;
    if (save == true) {
      await _save();
    } else if (save == false) {
      await _close();
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final owner = _owner;
    final generation = _generation;
    setState(() => _saving = true);
    if (enabled && draft.mode == PrayerAlertMode.adhan) {
      if (device['platform'] == 'android' && device['exact'] != true) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'امنح إذن التنبيه الدقيق لتشغيل الأذان بالخلفية، أو اختر نغمة التنبيه.',
            ),
          ),
        );
        return;
      }
      if (!await library.prepareVoice(draft.voice)) {
        if (mounted) setState(() => _saving = false);
        return;
      }
    }
    if (!mounted || owner != _owner || generation != _generation) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (enabled && widget.enableReminders != null) {
      final ready = await widget.enableReminders!();
      if (!mounted || owner != _owner || generation != _generation) return;
      if (!ready) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذّر تفعيل التذكيرات. أعد المحاولة قبل حفظ تنبيه الصلاة.',
            ),
          ),
        );
        return;
      }
    }
    final current = widget.controller.config;
    final selection = current.notifications
        ? current.enabledPrayers.toSet()
        : <String>{};
    if (enabled) {
      selection.add(widget.prayer.name);
    } else {
      selection.remove(widget.prayer.name);
    }
    final ok = await widget.controller.save(
      current.copyWith(
        notifications: selection.isNotEmpty,
        enabledPrayers: selection.toList(),
        alerts: {...current.alerts, widget.prayer.name: draft},
        beforeMinutes: 15,
      ),
    );
    if (!mounted || owner != _owner || generation != _generation) return;
    setState(() => _saving = false);
    if (ok) await _close();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_account);
    if (widget.library == null) {
      library.dispose();
    } else {
      unawaited(library.stop());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: _mayPop || !dirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_leave());
        },
        child: Scaffold(
          backgroundColor: p.background,
          body: ListenableBuilder(
            listenable: library,
            builder: (context, _) => CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: DirectoryHeader(
                    title: 'إعدادات ${widget.prayer.label}',
                    subtitle: 'نداء الصلاة… بالصوت الذي تختاره',
                    onBack: _leave,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 35),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _panel(
                          context,
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('إشعارات ${widget.prayer.label}'),
                            subtitle: const Text('تفعيل التنبيه لهذا الوقت'),
                            value: enabled,
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => enabled = v),
                          ),
                        ),
                        if (enabled) ...[
                          _panel(
                            context,
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'تفضيلات الإشعارات',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                for (final mode in PrayerAlertMode.values.where(
                                  (m) =>
                                      widget.prayer != PrayerName.sunrise ||
                                      m != PrayerAlertMode.adhan,
                                ))
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(mode.label),
                                    subtitle: Text(switch (mode) {
                                      PrayerAlertMode.chime =>
                                        'صوت تنبيه الجهاز عند حلول الوقت',
                                      PrayerAlertMode.adhan =>
                                        'اختر المؤذن وعاين صوته قبل الحفظ',
                                      PrayerAlertMode.vibration =>
                                        'يهتز الجهاز دون صوت، بحسب إعداداته',
                                      PrayerAlertMode.silent =>
                                        'إشعار مرئي دون صوت أو اهتزاز',
                                    }),
                                    leading: Icon(
                                      draft.mode == mode
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      color: draft.mode == mode
                                          ? p.gold
                                          : p.muted,
                                    ),
                                    onTap: _saving
                                        ? null
                                        : () => setState(
                                            () => draft = draft.copyWith(
                                              mode: mode,
                                              full:
                                                  mode ==
                                                          PrayerAlertMode
                                                              .adhan &&
                                                      device['platform'] ==
                                                          'android'
                                                  ? true
                                                  : draft.full,
                                            ),
                                          ),
                                  ),
                                if (draft.mode == PrayerAlertMode.adhan) ...[
                                  const Divider(),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('الأذان الكامل'),
                                    subtitle: Text(
                                      device['platform'] == 'ios'
                                          ? 'iPhone: التنبيه مقطع قصير؛ المعاينة كاملة داخل التطبيق'
                                          : 'Android: يحتاج التنبيه الدقيق والصوت المنزّل',
                                    ),
                                    value: draft.full,
                                    onChanged:
                                        device['platform'] == 'android' &&
                                            device['exact'] == true &&
                                            !_saving
                                        ? (v) => setState(
                                            () =>
                                                draft = draft.copyWith(full: v),
                                          )
                                        : null,
                                  ),
                                  if (device['platform'] == 'android' &&
                                      device['exact'] != true)
                                    TextButton.icon(
                                      onPressed: () async {
                                        await AdhanLibrary.bridge
                                            .invokeMethod<void>(
                                              'exactAlarmPermission',
                                            );
                                      },
                                      icon: const Icon(Icons.alarm),
                                      label: const Text(
                                        'إعداد إذن التنبيه الدقيق',
                                      ),
                                    ),
                                  if (device['platform'] == 'android') ...[
                                    Text(
                                      device['fullScreen'] == true
                                          ? 'عند الموعد تظهر شاشة الأذان حسب حالة الجهاز. أوقفه بلمسها أو بأزرارها أو بقلب الهاتف.'
                                          : 'لظهور شاشة الأذان فوق القفل، اسمح بإشعارات ملء الشاشة. يبقى التنبيه ظاهرًا إن منع النظام فتحها.',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    if (device['fullScreen'] != true)
                                      TextButton.icon(
                                        onPressed: () async {
                                          try {
                                            await AdhanLibrary.bridge
                                                .invokeMethod<void>(
                                                  'fullScreenPermission',
                                                );
                                          } catch (_) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'تعذّر فتح إعدادات الشاشة الكاملة',
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        icon: const Icon(Icons.fullscreen),
                                        label: const Text(
                                          'إذن شاشة الأذان فوق القفل',
                                        ),
                                      ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                          if (draft.mode == PrayerAlertMode.adhan) ...[
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                'صوت المؤذن',
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                  color: p.heading,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              decoration: const InputDecoration(
                                hintText: 'ابحث عن المؤذن…',
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (v) =>
                                  setState(() => search = v.trim()),
                            ),
                            const SizedBox(height: 14),
                            for (final voice in adhanVoices.where(
                              (v) => v.name.contains(search),
                            ))
                              _panel(
                                context,
                                Column(
                                  children: [
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      selected: draft.voice == voice.id,
                                      selectedColor: p.tealHeading,
                                      title: Text(voice.name),
                                      subtitle: Text(
                                        library.downloaded.contains(voice.id)
                                            ? 'محفوظ على الجهاز'
                                            : 'معاينة عبر الإنترنت • تنزيل للتنبيه',
                                      ),
                                      leading: Icon(
                                        draft.voice == voice.id
                                            ? Icons.check_circle
                                            : Icons.circle_outlined,
                                        color: p.gold,
                                      ),
                                      onTap: _saving
                                          ? null
                                          : () => setState(
                                              () => draft = draft.copyWith(
                                                voice: voice.id,
                                              ),
                                            ),
                                    ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        IconButton(
                                          tooltip: library.playing == voice.id
                                              ? 'إيقاف المعاينة'
                                              : 'معاينة ${voice.name}',
                                          onPressed: () =>
                                              library.preview(voice),
                                          icon: Icon(
                                            library.playing == voice.id
                                                ? Icons.pause_circle
                                                : Icons.play_circle_outline,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'تنزيل ${voice.name}',
                                          onPressed:
                                              library.downloading != null ||
                                                  library.downloaded.contains(
                                                    voice.id,
                                                  )
                                              ? null
                                              : () => library.download(voice),
                                          icon: library.downloading == voice.id
                                              ? SizedBox.square(
                                                  dimension: 22,
                                                  child:
                                                      CircularProgressIndicator(
                                                        value: library.progress,
                                                      ),
                                                )
                                              : Icon(
                                                  library.downloaded.contains(
                                                        voice.id,
                                                      )
                                                      ? Icons.download_done
                                                      : Icons.download_outlined,
                                                ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            if (!adhanVoices.any(
                              (v) => v.name.contains(search),
                            ))
                              _notice(context, 'لا يوجد مؤذن يطابق البحث'),
                            const Text(
                              'مصدر التسجيلات: AlAdhan / Islamic Network',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12),
                            ),
                            TextButton(
                              onPressed: () => launchUrl(
                                Uri.parse(
                                  'https://aladhan.com/download-adhans',
                                ),
                                mode: LaunchMode.externalApplication,
                              ),
                              child: const Text('المصدر والتسجيلات'),
                            ),
                          ],
                          _notice(
                            context,
                            'يلزم تفعيل التذكيرات العامة وإذن الإشعارات. إعدادات الصوت والبطارية في الجهاز قد تؤثر في التنبيه.',
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await AdhanLibrary.bridge.invokeMethod<void>(
                                'requestPermission',
                              );
                            },
                            icon: const Icon(Icons.notifications_outlined),
                            label: const Text('إذن إشعارات الجهاز'),
                          ),
                        ],
                        if (library.error case final error?)
                          _notice(context, error),
                        if (widget.controller.error case final error?)
                          _notice(context, error),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: const Icon(Icons.check),
                            label: Text(
                              _saving ? 'جارٍ الحفظ…' : 'احفظ التغييرات',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
