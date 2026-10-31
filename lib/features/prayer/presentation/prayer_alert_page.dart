part of 'prayer_page.dart';

class PrayerAlertPage extends StatefulWidget {
  const PrayerAlertPage({
    super.key,
    required this.controller,
    required this.prayer,
    this.library,
    this.beforeAudio,
    this.enableReminders,
    this.general = false,
  });
  final bool general;
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
  final _voicesScroll = ScrollController();
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
    draft = widget.general
        ? widget.controller.config.defaultAlert
        : widget.controller.config.alert(widget.prayer);
    enabled = widget.general
        ? widget.controller.config.notifications
        : widget.controller.config.notifications &&
              widget.controller.config.enabledPrayers.contains(
                widget.prayer.name,
              );
    _initial = snapshot;
  }

  Future<void> _status() async {
    try {
      final state = await AdhanLibrary.bridge.invokeMapMethod<String, dynamic>(
        'adhanStatus',
      );
      final permissions = await AdhanLibrary.bridge
          .invokeMapMethod<String, dynamic>('status');
      if (mounted) setState(() => device = {...?state, ...?permissions});
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
              Text(
                context.prayerLabel('التغييرات غير محفوظة'),
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                context.prayerLabel(
                  'احفظ إعدادات هذا الوقت أو اخرج دون تطبيق التعديلات.',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.prayerLabel('احفظ التغييرات')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.prayerLabel('تجاهل التغييرات')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.prayerLabel('متابعة التعديل')),
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
          SnackBar(
            content: Text(
              context.prayerLabel(
                'امنح إذن التنبيه الدقيق لتشغيل الأذان بالخلفية، أو اختر نغمة التنبيه.',
              ),
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
          SnackBar(
            content: Text(
              context.prayerLabel(
                'تعذّر تفعيل التذكيرات. أعد المحاولة قبل حفظ تنبيه الصلاة.',
              ),
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
    if (widget.general) {
      selection.addAll(current.enabledPrayers);
    } else if (enabled) {
      selection.add(widget.prayer.name);
    } else {
      selection.remove(widget.prayer.name);
    }
    final ok = await widget.controller.save(
      current.copyWith(
        notifications: widget.general ? enabled : selection.isNotEmpty,
        enabledPrayers: selection.toList(),
        defaultAlert: widget.general ? draft : current.defaultAlert,
        alerts: widget.general
            ? {
                ...current.alerts,
                for (final name in PrayerName.values.where(
                  (p) => p != PrayerName.sunrise,
                ))
                  name.name: draft,
              }
            : {...current.alerts, widget.prayer.name: draft},
      ),
    );
    if (!mounted || owner != _owner || generation != _generation) return;
    setState(() => _saving = false);
    if (ok) await _close();
  }

  @override
  void dispose() {
    _voicesScroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_account);
    if (widget.library == null) {
      library.dispose();
    } else {
      unawaited(library.stop());
    }
    super.dispose();
  }

  Widget _voiceList(BuildContext context) {
    final p = AppPalette.of(context);
    final shown = adhanVoices
        .where(
          (v) => normalizePlaceQuery(
            '${v.name} ${v.englishName ?? ''}',
          ).contains(normalizePlaceQuery(search)),
        )
        .toList();
    final selected = adhanVoiceById(draft.voice)!;
    return _panel(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.prayerLabel(
              'صوتان مرفقان بدون إنترنت، وباقي الأصوات تُنزّل عند الطلب.',
            ),
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'prayer.selectedVoice',
              args: {'voice': selected.displayLabel(context)},
            ),
            style: TextStyle(
              color: p.tealHeading,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('prayer.recordingCount', args: {'count': shown.length}),
            style: TextStyle(color: p.muted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: (MediaQuery.sizeOf(context).height * .42).clamp(
              220.0,
              360.0,
            ),
            child: Scrollbar(
              controller: _voicesScroll,
              child: ListView.separated(
                key: const ValueKey('compact-adhan-voices'),
                controller: _voicesScroll,
                primary: false,
                itemCount: shown.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: p.border),
                itemBuilder: (context, i) {
                  final voice = shown[i];
                  return InkWell(
                    key: ValueKey('adhan-voice-${voice.id}'),
                    onTap: _saving
                        ? null
                        : () => setState(
                            () => draft = draft.copyWith(voice: voice.id),
                          ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          Icon(
                            draft.voice == voice.id
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: draft.voice == voice.id
                                ? p.tealHeading
                                : p.muted,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  voice.displayLabel(context),
                                  style: TextStyle(
                                    color: p.heading,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  voice.bundled
                                      ? context.prayerLabel(
                                          'مرفق مع التطبيق • بدون إنترنت',
                                        )
                                      : library.downloaded.contains(voice.id)
                                      ? context.prayerLabel('محفوظ على الجهاز')
                                      : context.tr(
                                          'prayer.downloadSize',
                                          args: {
                                            'size':
                                                (voice.downloadBytes / 1048576)
                                                    .toStringAsFixed(1),
                                          },
                                        ),
                                  style: TextStyle(
                                    color: p.muted,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: library.playing == voice.id
                                ? context.prayerLabel('إيقاف المعاينة')
                                : context.tr(
                                    'prayer.previewVoice',
                                    args: {
                                      'voice': voice.displayLabel(context),
                                    },
                                  ),
                            onPressed: _saving
                                ? null
                                : () => library.preview(voice),
                            icon: Icon(
                              library.playing == voice.id
                                  ? Icons.pause_circle
                                  : Icons.play_circle_outline,
                              color: p.tealHeading,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            tooltip: context.tr(
                              'prayer.downloadVoice',
                              args: {'voice': voice.displayLabel(context)},
                            ),
                            onPressed:
                                _saving ||
                                    library.downloading != null ||
                                    library.downloaded.contains(voice.id)
                                ? null
                                : () => library.download(voice),
                            visualDensity: VisualDensity.compact,
                            icon: library.downloading == voice.id
                                ? SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      value: library.progress,
                                    ),
                                  )
                                : Icon(
                                    library.downloaded.contains(voice.id)
                                        ? Icons.download_done
                                        : Icons.download_outlined,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(selected.sourceUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(context.prayerLabel('مصدر التسجيل المختار')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Directionality(
      textDirection:
          LocalizationScope.maybeOf(context)?.language.direction ??
          TextDirection.rtl,
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
                    title: widget.general
                        ? context.prayerLabel('المؤذّن ونمط الأذان العام')
                        : context.tr(
                            'prayer.alertFor',
                            args: {
                              'prayer': widget.prayer.displayLabel(context),
                            },
                          ),
                    subtitle: context.prayerLabel(
                      'نداء الصلاة… بالصوت الذي تختاره',
                    ),
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
                            title: Text(
                              context.tr(
                                'prayer.notificationsFor',
                                args: {
                                  'prayer': widget.prayer.displayLabel(context),
                                },
                              ),
                            ),
                            subtitle: Text(
                              context.prayerLabel('تفعيل التنبيه لهذا الوقت'),
                            ),
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
                                Text(
                                  context.prayerLabel('تفضيلات الإشعارات'),
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
                                    title: Text(mode.displayLabel(context)),
                                    subtitle: Text(switch (mode) {
                                      PrayerAlertMode.chime =>
                                        context.prayerLabel(
                                          'صوت تنبيه الجهاز عند حلول الوقت',
                                        ),
                                      PrayerAlertMode.adhan =>
                                        context.prayerLabel(
                                          'اختر المؤذن وعاين صوته قبل الحفظ',
                                        ),
                                      PrayerAlertMode.vibration =>
                                        context.prayerLabel(
                                          'يهتز الجهاز دون صوت، بحسب إعداداته',
                                        ),
                                      PrayerAlertMode.silent =>
                                        context.prayerLabel(
                                          'إشعار مرئي دون صوت أو اهتزاز',
                                        ),
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
                                    title: Text(
                                      context.prayerLabel('الأذان الكامل'),
                                    ),
                                    subtitle: Text(
                                      device['platform'] == 'ios'
                                          ? context.prayerLabel(
                                              'iPhone: التنبيه مقطع قصير؛ المعاينة كاملة داخل التطبيق',
                                            )
                                          : context.prayerLabel(
                                              'Android: يحتاج التنبيه الدقيق والصوت المنزّل',
                                            ),
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
                                      label: Text(
                                        context.prayerLabel(
                                          'إعداد إذن التنبيه الدقيق',
                                        ),
                                      ),
                                    ),
                                  if (device['platform'] == 'android') ...[
                                    Text(
                                      device['fullScreen'] == true
                                          ? context.prayerLabel(
                                              'عند الموعد تظهر شاشة الأذان حسب حالة الجهاز. أوقفه بلمسها أو بأزرارها أو بقلب الهاتف.',
                                            )
                                          : context.prayerLabel(
                                              'لظهور شاشة الأذان فوق القفل، اسمح بإشعارات ملء الشاشة. يبقى التنبيه ظاهرًا إن منع النظام فتحها.',
                                            ),
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
                                                SnackBar(
                                                  content: Text(
                                                    context.prayerLabel(
                                                      'تعذّر فتح إعدادات الشاشة الكاملة',
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        icon: const Icon(Icons.fullscreen),
                                        label: Text(
                                          context.prayerLabel(
                                            'إذن شاشة الأذان فوق القفل',
                                          ),
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
                                context.prayerLabel('صوت المؤذن'),
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                  color: p.heading,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              decoration: InputDecoration(
                                hintText: context.prayerLabel(
                                  'ابحث عن المؤذن…',
                                ),
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (v) => setState(() {
                                search = v.trim();
                                if (_voicesScroll.hasClients) {
                                  _voicesScroll.jumpTo(0);
                                }
                              }),
                            ),
                            const SizedBox(height: 14),
                            _voiceList(context),
                            if (!adhanVoices.any(
                              (v) => normalizePlaceQuery(
                                '${v.name} ${v.englishName ?? ''}',
                              ).contains(normalizePlaceQuery(search)),
                            ))
                              _notice(
                                context,
                                context.prayerLabel('لا يوجد مؤذن يطابق البحث'),
                              ),
                            Text(
                              context.prayerLabel(
                                'تسجيلات المؤذنين من نسك. الأصوات المنزّلة تُحفظ على جهازك وتعمل بدون إنترنت.',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                          _notice(
                            context,
                            context.prayerLabel(
                              'يلزم تفعيل التذكيرات العامة وإذن الإشعارات. إعدادات الصوت والبطارية في الجهاز قد تؤثر في التنبيه.',
                            ),
                          ),
                          if (device['allowed'] == true)
                            ListTile(
                              leading: Icon(Icons.check_circle_outline),
                              title: Text(
                                context.prayerLabel('إذن الإشعارات مفعّل'),
                              ),
                            )
                          else
                            TextButton.icon(
                              onPressed: () async {
                                await AdhanLibrary.bridge.invokeMethod<void>(
                                  'requestPermission',
                                );
                                await _status();
                              },
                              icon: const Icon(Icons.notifications_outlined),
                              label: Text(
                                context.prayerLabel('إذن إشعارات الجهاز'),
                              ),
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
                              _saving
                                  ? 'جارٍ الحفظ…'
                                  : context.prayerLabel('احفظ التغييرات'),
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
