part of 'prayer_page.dart';

/// The single entry for prayer alerts, shared by Home, Qibla and Settings.
class PrayerAdhanSettingsPage extends StatefulWidget {
  const PrayerAdhanSettingsPage({
    super.key,
    required this.controller,
    this.beforeAudio,
    this.enableReminders,
    this.onOpenRoute,
  });
  final ValueChanged<String>? onOpenRoute;
  final PrayerController controller;
  final Future<void> Function()? beforeAudio;
  final Future<bool> Function()? enableReminders;
  @override
  State<PrayerAdhanSettingsPage> createState() =>
      _PrayerAdhanSettingsPageState();
}

class _PrayerAdhanSettingsPageState extends State<PrayerAdhanSettingsPage>
    with WidgetsBindingObserver {
  Map<String, dynamic> device = {};
  bool busy = false;
  int? volumeDraft;
  String? volumeOwner;
  PrayerController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_status());
  }

  Future<void> _status() async {
    try {
      final status = await AdhanLibrary.bridge.invokeMapMethod<String, dynamic>(
        'status',
      );
      final alarm = await AdhanLibrary.bridge.invokeMapMethod<String, dynamic>(
        'adhanStatus',
      );
      if (mounted) setState(() => device = {...?status, ...?alarm});
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_status());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _save(PrayerConfig next) async {
    if (busy) return;
    final owner = c.scope;
    setState(() => busy = true);
    try {
      if (next.notifications &&
          widget.enableReminders != null &&
          !await widget.enableReminders!()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.prayerLabel('تعذّر تفعيل التذكيرات؛ أعد المحاولة'),
              ),
            ),
          );
        }
        return;
      }
      if (c.scope == owner) await c.save(next);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _testPrayer(String kind) async {
    if (busy || !kDebugMode) return;
    final owner = c.scope;
    setState(() => busy = true);
    AdhanLibrary? library;
    try {
      await widget.beforeAudio?.call();
      final voice = c.config.alert(PrayerName.dhuhr).voice;
      if (kind == 'adhan' &&
          !(device['preparedVoices'] as List? ?? []).contains(voice)) {
        library = AdhanLibrary();
        await library.initialize();
        final choice = adhanVoiceById(voice)!;
        final ready = library.downloaded.contains(voice)
            ? await library.prepareVoice(voice)
            : await library.download(choice);
        if (!ready) throw StateError('audio');
      }
      if (!mounted || owner != c.scope) return;
      await AdhanLibrary.bridge.invokeMethod<Object>('schedulePrayerTest', {
        'kind': kind,
        'voice': voice,
        'variant': c.reminderVariant,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.prayerLabel(
                'سيبدأ اختبار الظهر بعد 10 ثوانٍ؛ يمكنك تصغير التطبيق أو قفل الشاشة',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.prayerLabel(
                'تعذّر تجهيز الاختبار؛ تحقق من أذونات الإشعار والتنبيه الدقيق والصوت المحفوظ',
              ),
            ),
          ),
        );
      }
    } finally {
      library?.dispose();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _editor({
    PrayerName prayer = PrayerName.fajr,
    bool general = false,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PrayerAlertPage(
          controller: c,
          prayer: prayer,
          general: general,
          beforeAudio: widget.beforeAudio,
          enableReminders: widget.enableReminders,
        ),
      ),
    );
    await _status();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection:
        LocalizationScope.maybeOf(context)?.language.direction ??
        TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppPalette.of(context).background,
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final config = c.config, p = AppPalette.of(context);
          final voice = adhanVoiceById(config.defaultAlert.voice)!;
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              DirectoryHeader(
                title: 'إعدادات الأذان',
                subtitle: context.prayerLabel(
                  'مؤذّنك وتنبيهات صلواتك في مكان واحد',
                ),
                onBack: () => Navigator.maybePop(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                child: Column(
                  children: [
                    if (c.error case final error?) _notice(context, error),
                    _panel(
                      context,
                      Column(
                        children: [
                          SwitchListTile(
                            key: const ValueKey('adhan-master'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              context.prayerLabel('تفعيل تنبيهات الصلاة'),
                            ),
                            value: config.notifications,
                            onChanged: busy
                                ? null
                                : (v) =>
                                      _save(config.copyWith(notifications: v)),
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
                              key: const ValueKey(
                                'adhan-notification-permission',
                              ),
                              icon: const Icon(
                                Icons.notifications_active_outlined,
                              ),
                              label: Text(
                                context.prayerLabel('السماح بإشعارات الصلاة'),
                              ),
                              onPressed: () async {
                                await AdhanLibrary.bridge.invokeMethod<void>(
                                  'requestPermission',
                                );
                                await _status();
                              },
                            ),
                          if (kDebugMode && device['platform'] == 'android')
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                OutlinedButton(
                                  key: const ValueKey('test-dhuhr-reminder'),
                                  onPressed: busy
                                      ? null
                                      : () => _testPrayer('reminderVoice'),
                                  child: Text(
                                    context.prayerLabel(
                                      'اختبار تذكير الظهر (10ث)',
                                    ),
                                  ),
                                ),
                                OutlinedButton(
                                  key: const ValueKey('test-dhuhr-adhan'),
                                  onPressed: busy
                                      ? null
                                      : () => _testPrayer('adhan'),
                                  child: Text(
                                    context.prayerLabel(
                                      'اختبار أذان الظهر (10ث)',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ListTile(
                            title: Text(
                              context.prayerLabel('المؤذّن ونمط الأذان العام'),
                            ),
                            subtitle: Text(
                              '${voice.displayLabel(context)} • ${config.defaultAlert.mode.displayLabel(context)}',
                            ),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: () => _editor(general: true),
                          ),
                          Text(
                            context.prayerLabel(
                              'الاختيار العام يطبق على الصلوات الخمس؛ يمكنك تخصيص أي صلاة من القائمة أدناه.',
                            ),
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    _panel(
                      context,
                      Column(
                        children: [
                          Text(
                            context.tr(
                              'prayer.volume',
                              args: {
                                'volume': volumeDraft ?? config.adhanVolume,
                              },
                            ),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: p.heading,
                            ),
                          ),
                          Slider(
                            key: const ValueKey('adhan-volume'),
                            min: 0,
                            max: 100,
                            divisions: 10,
                            value: (volumeDraft ?? config.adhanVolume)
                                .toDouble(),
                            label: '${volumeDraft ?? config.adhanVolume}٪',
                            onChangeStart: (_) => volumeOwner = c.scope,
                            onChanged: busy
                                ? null
                                : (v) =>
                                      setState(() => volumeDraft = v.round()),
                            onChangeEnd: (v) async {
                              if (volumeOwner != c.scope) {
                                setState(() => volumeDraft = null);
                                return;
                              }
                              await _save(
                                config.copyWith(adhanVolume: v.round()),
                              );
                              if (mounted) setState(() => volumeDraft = null);
                            },
                          ),
                          Text(
                            context.prayerLabel(
                              'على Android يُرفع صوت المنبّه وقت الأذان للمستوى المختار ثم يعود كما كان. قيود النظام وعدم الإزعاج تبقى فعّالة.',
                            ),
                            style: TextStyle(fontSize: 12),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              context.prayerLabel('شاشة الأذان الكاملة'),
                            ),
                            subtitle: Text(
                              device['platform'] == 'ios'
                                  ? context.prayerLabel(
                                      'على iPhone يظهر إشعار بصوت قصير حسب قيود النظام',
                                    )
                                  : context.prayerLabel(
                                      'بدل الاكتفاء بالإشعار، عندما يسمح الجهاز',
                                    ),
                            ),
                            value: config.showAdhanScreen,
                            onChanged: busy || device['platform'] == 'ios'
                                ? null
                                : (v) => _save(
                                    config.copyWith(showAdhanScreen: v),
                                  ),
                          ),
                          if (device['platform'] == 'android' &&
                              config.showAdhanScreen &&
                              device['fullScreen'] != true)
                            TextButton(
                              onPressed: () => AdhanLibrary.bridge
                                  .invokeMethod<void>('fullScreenPermission'),
                              child: Text(
                                context.prayerLabel('السماح بالشاشة الكاملة'),
                              ),
                            ),
                          if ([
                            'xiaomi',
                            'redmi',
                            'poco',
                          ].contains(device['vendor']))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.phonelink_lock_outlined,
                              ),
                              title: Text(
                                context.prayerLabel(
                                  'إدارة أذونات شاشة القفل على Xiaomi',
                                ),
                              ),
                              subtitle: Text(
                                context.prayerLabel(
                                  'فعّل Show on Lock screen وفتح النوافذ أثناء العمل بالخلفية لظهور شاشة الأذان',
                                ),
                              ),
                              onTap: () => AdhanLibrary.bridge
                                  .invokeMethod<void>('vendorAlarmPermissions'),
                            ),
                          if (device['platform'] == 'android' &&
                              device['exact'] != true)
                            TextButton(
                              onPressed: () => AdhanLibrary.bridge
                                  .invokeMethod<void>('exactAlarmPermission'),
                              child: Text(
                                context.prayerLabel('السماح بالتنبيه الدقيق'),
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final route = await Navigator.push<String>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      AdhanScreenPreview(controller: c),
                                ),
                              );
                              if (!context.mounted ||
                                  route == null ||
                                  route == 'prayer-settings') {
                                return;
                              }
                              if (widget.onOpenRoute != null) {
                                Navigator.pop(context);
                                widget.onOpenRoute!(route);
                              }
                            },
                            icon: const Icon(Icons.preview_outlined),
                            label: Text(
                              context.prayerLabel('معاينة شاشة الأذان'),
                            ),
                          ),
                          DropdownButtonFormField<int>(
                            key: ValueKey('iqama-${config.iqamaMinutes}'),
                            initialValue: config.iqamaMinutes,
                            decoration: InputDecoration(
                              labelText: context.prayerLabel(
                                'عدّ الإقامة بعد الأذان',
                              ),
                            ),
                            items: [
                              for (final n in {
                                0,
                                5,
                                10,
                                15,
                                20,
                                25,
                                30,
                                45,
                                60,
                                config.iqamaMinutes,
                              }.toList()..sort())
                                DropdownMenuItem(
                                  value: n,
                                  child: Text(
                                    n == 0
                                        ? context.prayerLabel('إخفاء العدّ')
                                        : context.tr(
                                            'prayer.minutes',
                                            args: {'count': n},
                                          ),
                                  ),
                                ),
                            ],
                            onChanged: busy
                                ? null
                                : (v) {
                                    if (v != null) {
                                      _save(config.copyWith(iqamaMinutes: v));
                                    }
                                  },
                          ),
                          Text(
                            context.prayerLabel(
                              'مدة الإقامة اختيارك الشخصي، وليست موعدًا رسميًا للمسجد.',
                            ),
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    _panel(
                      context,
                      Column(
                        children: [
                          ListTile(
                            title: Text(
                              context.prayerLabel(
                                'الصلوات التي يصدر لها تنبيه',
                              ),
                            ),
                          ),
                          for (final prayer in PrayerName.values.where(
                            (p) => p != PrayerName.sunrise,
                          ))
                            SwitchListTile(
                              key: ValueKey('adhan-enabled-${prayer.name}'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(prayer.displayLabel(context)),
                              value: config.enabledPrayers.contains(
                                prayer.name,
                              ),
                              subtitle: Text(
                                '${config.alert(prayer).mode.displayLabel(context)} • ${adhanVoiceById(config.alert(prayer).voice)!.displayLabel(context)}',
                              ),
                              secondary: IconButton(
                                tooltip: context.tr(
                                  'prayer.customize',
                                  args: {
                                    'prayer': prayer.displayLabel(context),
                                  },
                                ),
                                icon: const Icon(Icons.tune),
                                onPressed: () => _editor(prayer: prayer),
                              ),
                              onChanged: busy
                                  ? null
                                  : (v) {
                                      final selection = config.enabledPrayers
                                          .toSet();
                                      v
                                          ? selection.add(prayer.name)
                                          : selection.remove(prayer.name);
                                      _save(
                                        config.copyWith(
                                          enabledPrayers: selection.toList(),
                                        ),
                                      );
                                    },
                            ),
                        ],
                      ),
                    ),
                    _panel(
                      context,
                      Column(
                        children: [
                          DropdownButtonFormField<int>(
                            key: ValueKey('before-${config.beforeMinutes}'),
                            initialValue: config.beforeMinutes,
                            decoration: InputDecoration(
                              labelText: context.prayerLabel(
                                'التذكير قبل الصلاة',
                              ),
                            ),
                            items: [
                              for (final n in {
                                0,
                                5,
                                10,
                                15,
                                20,
                                30,
                                45,
                                60,
                                config.beforeMinutes,
                              }.toList()..sort())
                                DropdownMenuItem(
                                  value: n,
                                  child: Text(
                                    n == 0
                                        ? context.prayerLabel('بدون تذكير مسبق')
                                        : context.tr(
                                            'prayer.minutes',
                                            args: {'count': n},
                                          ),
                                  ),
                                ),
                            ],
                            onChanged: busy
                                ? null
                                : (v) {
                                    if (v != null) {
                                      _save(config.copyWith(beforeMinutes: v));
                                    }
                                  },
                          ),
                          const SizedBox(height: 12),
                          Text(
                            context.prayerLabel(
                              'التذكير الصوتي: «اقتربت صلاة الفجر/الظهر/العصر/المغرب/العشاء».',
                            ),
                          ),
                          Text(
                            context.prayerLabel(
                              'ثلاث لهجات عربية وصوت إنجليزي مضمّنة، ويمكن إضافة تسجيلك.',
                            ),
                            style: TextStyle(fontSize: 12),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => PrayerReminderRecordingsPage(
                                  controller: c,
                                  beforeAudio: widget.beforeAudio,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.record_voice_over),
                            label: Text(
                              context.prayerLabel('أصوات التذكير قبل الصلاة'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            key: ValueKey('after-${config.afterMinutes}'),
                            initialValue: config.afterMinutes,
                            decoration: InputDecoration(
                              labelText: context.prayerLabel(
                                'أذكار بعد الصلاة',
                              ),
                            ),
                            items: [
                              for (final n in {
                                0,
                                1,
                                5,
                                10,
                                15,
                                20,
                                30,
                                config.afterMinutes,
                              }.toList()..sort())
                                DropdownMenuItem(
                                  value: n,
                                  child: Text(
                                    n == 0
                                        ? context.prayerLabel('غير مفعّل')
                                        : context.tr(
                                            'prayer.afterMinutes',
                                            args: {'count': n},
                                          ),
                                  ),
                                ),
                            ],
                            onChanged: busy
                                ? null
                                : (v) {
                                    if (v != null) {
                                      _save(config.copyWith(afterMinutes: v));
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                    _panel(
                      context,
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          context.prayerLabel('الموقع وحساب المواقيت'),
                        ),
                        subtitle: Text(
                          config.location?.label ??
                              context.prayerLabel('حدّد المدينة والدولة'),
                        ),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => PrayerSettingsPage(controller: c),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
