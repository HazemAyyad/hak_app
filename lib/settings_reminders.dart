part of 'settings_pages.dart';

String _settingNumber(BuildContext context, int value) =>
    LocalizationScope.maybeOf(context)?.formats.integer(value) ??
    value.toString();
String _settingDuration(BuildContext context, String kind, int count) =>
    LocalizationScope.maybeOf(context)?.pluralText('settings.$kind', count) ??
    (kind == 'everyMinutes'
        ? 'كل $count دقيقة'
        : kind == 'everyHours'
        ? 'كل $count ساعات'
        : '$count دقيقة');

class _LoadReminderSettings extends StatefulWidget {
  const _LoadReminderSettings({
    required this.kind,
    required this.load,
    required this.section,
    this.onDestinationSelected,
  });
  final SettingKind kind;
  final Future<ReminderController?> Function() load;
  final AppSection section;
  final ValueChanged<int>? onDestinationSelected;
  @override
  State<_LoadReminderSettings> createState() => _LoadReminderSettingsState();
}

class _LoadReminderSettingsState extends State<_LoadReminderSettings> {
  late Future<ReminderController?> _load = widget.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<ReminderController?>(
    future: _load,
    builder: (context, snapshot) {
      if (snapshot.data case final controller?) {
        return SettingsDetailPage(
          kind: widget.kind,
          reminders: controller,
          section: widget.section,
          onDestinationSelected: widget.onDestinationSelected,
        );
      }
      return _SettingsShell(
        title: widget.kind.title,
        subtitle: widget.kind.subtitle,
        icon: widget.kind.icon,
        section: widget.section,
        onDestinationSelected: widget.onDestinationSelected,
        child: snapshot.connectionState != ConnectionState.done
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _NoticeBox(
                    context.settingsLabel('تعذّر تجهيز الإعدادات'),
                    context.settingsLabel(
                      'أعد المحاولة لتحميل إعدادات الحساب وجدولة تذكيراته.',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() => _load = widget.load()),
                    child: Text(context.settingsLabel('إعادة المحاولة')),
                  ),
                ],
              ),
      );
    },
  );
}

class _EmptySettings extends Listenable {
  const _EmptySettings();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

extension _ReminderSettingsUI on _SettingsDetailPageState {
  Future<void> _choose<T>(
    String key,
    String title,
    Map<T, String> options,
    T current,
  ) async {
    final owner = _settings!;
    final value = await showDialog<T>(
      context: context,
      builder: (context) {
        _activeDialog = context;
        return SimpleDialog(
          title: Text(context.settingsLabel(title)),
          children: [
            for (final option in options.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, option.key),
                child: Row(
                  children: [
                    Expanded(child: Text(context.settingsLabel(option.value))),
                    if (option.key == current)
                      Icon(Icons.check, color: appAccent(context, _teal)),
                  ],
                ),
              ),
          ],
        );
      },
    );
    _activeDialog = null;
    if (mounted && value != null && _settings == owner) {
      await owner.set(key, value as Object);
    }
  }

  Future<void> _time(String key, String title) async {
    final owner = _settings!;
    final value = owner.time(key);
    final time = await showTimePicker(
      context: context,
      helpText: context.settingsLabel(title),
      initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60),
    );
    if (mounted && time != null && _settings == owner) {
      await owner.set('$key.time', time.hour * 60 + time.minute);
    }
  }

  Widget _numberChoice(
    String key,
    String title,
    Map<int, String> options,
    int initial, {
    IconData icon = Icons.tune,
  }) => _SettingsTile(
    icon: icon,
    title: title,
    subtitle: context.settingsLabel('يُحفظ الاختيار فوراً'),
    value: options[_settings!.number(key, initial)] ?? options[initial],
    onTap: () => _choose(key, title, options, _settings!.number(key, initial)),
  );
  Widget _textChoice(
    String key,
    String title,
    Map<String, String> options,
    String initial,
  ) => _SettingsTile(
    icon: Icons.tune,
    title: title,
    subtitle: context.settingsLabel('يُحفظ الاختيار فوراً'),
    value: options[_settings!.text(key, initial)],
    onTap: () => _choose(key, title, options, _settings!.text(key, initial)),
  );

  Widget _deviceStatus() {
    final c = widget.reminders;
    final state = c?.device;
    return Column(
      children: [
        _InfoBox(
          context.settingsLabel('حالة الجهاز'),
          state?.supported != true
              ? context.settingsLabel(
                  'الجدولة غير متاحة في بيئة العرض الحالية. التفضيلات تبقى محفوظة.',
                )
              : !state!.allowed
              ? context.settingsLabel(
                  'الإشعارات غير مسموحة. امنح الإذن من الزر أدناه.',
                )
              : context.tr(
                  'settings.scheduleStatus',
                  args: {
                    'count': _settingNumber(context, state.pending),
                    'status': state.platform == 'android'
                        ? (state.exact
                              ? context.settingsLabel(
                                  'المواعيد المحددة مجدولة بدقة',
                                )
                              : context.settingsLabel(
                                  'قد تتأخر المواعيد حتى تسمح بالتنبيه الدقيق',
                                ))
                        : context.settingsLabel('تنبيهات iOS المحلية'),
                  },
                ),
        ),
        if (c?.error case final error?)
          _NoticeBox(context.settingsLabel('الجدولة تحتاج متابعة'), error),
        if (c != null)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!c.device.allowed)
                OutlinedButton.icon(
                  onPressed: () => c.action('requestPermission'),
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: Text(context.settingsLabel('طلب إذن الإشعارات')),
                ),
              TextButton(
                onPressed: () => c.action('notificationSettings'),
                child: Text(
                  context.settingsLabel('إعدادات الإشعارات في الجهاز'),
                ),
              ),
              TextButton(
                onPressed: () => c.reconcile(force: true),
                child: Text(context.settingsLabel('تحديث الحالة والجدولة')),
              ),
            ],
          ),
      ],
    );
  }

  Widget _reminderControls() => Column(
    children: [
      _switchTile(
        'enabled',
        context.settingsLabel('تفعيل التذكيرات'),
        context.settingsLabel('لا يُطلب الإذن إلا باختيارك'),
        Icons.notifications_none,
      ),
      _deviceStatus(),
      if (widget.reminders case final c?
          when c.device.platform == 'android') ...[
        _InfoBox(
          context.settingsLabel('منبّه أذكار الصباح والمساء والنوم'),
          context.settingsLabel(
            'يظهر بشاشة مثل الأذان، ثم تبدأ تسجيلات أذكار المجموعة تلقائيًا بعد النداء. يمكنك فتح الأذكار ومتابعة الاستماع، أو إيقافه وتأجيله من الإشعار.',
          ),
        ),
        if (!c.device.exact)
          OutlinedButton(
            onPressed: () => c.action('exactAlarmPermission'),
            child: Text(context.settingsLabel('السماح بالتنبيه في الموعد')),
          ),
        if (!c.device.fullScreen)
          OutlinedButton(
            onPressed: () => c.action('fullScreenPermission'),
            child: Text(
              context.settingsLabel('السماح بشاشة التذكير عند القفل'),
            ),
          ),
        _switchTile(
          'sound',
          context.settingsLabel('صوت التذكيرات'),
          context.settingsLabel(
            'نداء عربي مولّد ثم تسجيلات حصن المسلم، محفوظة دون إنترنت',
          ),
          Icons.volume_up_outlined,
        ),
        _InfoBox(
          context.settingsLabel('القراءة الصوتية'),
          context.settingsLabel(
            'يُقرأ كل تسجيل من المصدر مرة واحدة، وأعداد التكرار ظاهرة في القارئ. الاستماع لا يسجّل إنجازًا تلقائيًا، ويستمر عند إطفاء الشاشة حتى توقفه.',
          ),
        ),
      ],
      _SectionTitle(context.settingsLabel('تذكيرات الأذكار')),
      for (final entry in const {
        'morning': 'أذكار الصباح',
        'evening': 'أذكار المساء',
        'sleep': 'أذكار النوم',
      }.entries) ...[
        _switchTile(
          entry.key,
          entry.value,
          context.settingsLabel('تذكير يومي اختياري'),
          entry.key == 'morning'
              ? Icons.light_mode_outlined
              : Icons.dark_mode_outlined,
        ),
        _SettingsTile(
          icon: Icons.access_time,
          title: context.tr(
            'settings.reminderTime',
            args: {'name': context.settingsLabel(entry.value)},
          ),
          subtitle: 'التوقيت المحلي للجهاز',
          value: AppSettings.clockLabel(_settings!.time(entry.key)),
          onTap: () => _time(entry.key, entry.value),
        ),
      ],
      _NoticeBox(
        context.settingsLabel('أذكار ما بعد الصلاة'),
        context.settingsLabel(
          'تحتاج مواقيت محسوبة للموقع؛ تُربط في مرحلة الصلاة والقبلة.',
        ),
      ),
      _SectionTitle(context.settingsLabel('الورد والختمة والمحتوى')),
      for (final entry in const {
        'dailyWird': 'الورد اليومي',
        'friday': 'تذكير الجمعة',
        'messages': 'المحتوى الإيماني',
      }.entries) ...[
        _switchTile(
          entry.key,
          entry.value,
          entry.key == 'friday'
              ? context.settingsLabel('يوم الجمعة فقط')
              : context.settingsLabel('تذكير يومي بزيارة المحتوى المحفوظ'),
          Icons.menu_book_outlined,
        ),
        _SettingsTile(
          icon: Icons.access_time,
          title: context.tr(
            'settings.reminderTime',
            args: {'name': context.settingsLabel(entry.value)},
          ),
          subtitle: 'التوقيت المحلي للجهاز',
          value: AppSettings.clockLabel(_settings!.time(entry.key)),
          onTap: () => _time(entry.key, entry.value),
        ),
      ],
      _InfoBox(
        context.settingsLabel('تذكير الختمة'),
        context.settingsLabel(
          'يُضبط الموعد من كل ختمة. تُلغى تذكيرات الختمة عند إكمالها أو أرشفتها أو حذفها، ويجب تفعيل التذكيرات العامة هنا.',
        ),
      ),
      if (kDebugMode && widget.reminders?.device.platform == 'android') ...[
        _SectionTitle(context.settingsLabel('اختبار التذكيرات على الجهاز')),
        _InfoBox(
          context.settingsLabel('اختبار بعد 10 ثوانٍ'),
          context.settingsLabel(
            'يمكنك قفل الشاشة أو تصغير التطبيق. الاختبار لا يغيّر مواعيدك أو يفعّل التذكيرات المعطلة، ولا يسجل إنجازًا.',
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const {
              'morning': 'الصباح',
              'evening': 'المساء',
              'sleep': 'النوم',
              'dailyWird': 'الورد',
              'friday': 'الجمعة',
              'khatma': 'الختمة',
            }.entries)
              OutlinedButton(
                onPressed: () async {
                  try {
                    await widget.reminders!.channel.invokeMethod<Object>(
                      'scheduleReminderTest',
                      {'kind': entry.key},
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            context.tr(
                              'settings.testReminderScheduled',
                              args: {
                                'name': context.settingsLabel(entry.value),
                              },
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
                            context.settingsLabel(
                              'تحقق من إذن الإشعارات والتنبيه الدقيق',
                            ),
                          ),
                        ),
                      );
                    }
                  }
                },
                child: Text(
                  context.tr(
                    'settings.testReminder',
                    args: {'name': context.settingsLabel(entry.value)},
                  ),
                ),
              ),
          ],
        ),
        TextButton(
          onPressed: () => widget.reminders!.action('clearReminderTests'),
          child: Text(context.settingsLabel('إلغاء الاختبار وإزالة إشعاراته')),
        ),
      ],
      _InfoBox(
        context.settingsLabel('المحتوى الإيماني'),
        context.settingsLabel(
          'هذا تذكير محلي لفتح المكتبة؛ إشعارات الرسائل الجديدة من الخادم تُنفذ في مرحلة الرسائل.',
        ),
      ),
      _switchTile(
        'startup',
        context.settingsLabel('استعادة التذكيرات بعد تشغيل الجهاز'),
        context.settingsLabel(
          'Android: يعيد الجدولة دون تشغيل التنبيه العائم تلقائياً',
        ),
        Icons.restart_alt,
      ),
    ],
  );

  Widget _notificationControls() {
    final c = widget.reminders;
    final overlay = _settings!.text('type', 'center') == 'overlay';
    final android = c?.device.platform == 'android';
    return _CompactSmartSettings(
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            _switchTile(
              'enabled',
              context.settingsLabel('تفعيل التذكيرات'),
              context.settingsLabel('المفتاح العام لتذكيرات حق'),
              Icons.notifications_none,
            ),
            _switchTile(
              'smart',
              context.settingsLabel('تفعيل الأذكار المتكررة'),
              context.settingsLabel('أذكار تختارها وتتكرر خلال اليوم'),
              Icons.eco_outlined,
            ),
            _SettingsTile(
              icon: Icons.menu_book_outlined,
              title: context.settingsLabel('محتوى التنبيهات'),
              subtitle: context.settingsLabel('اختر الأذكار أو حدّدها كلها'),
              value: context.tr(
                'settings.selectedCount',
                args: {
                  'count': _settingNumber(context, _settings!.content.length),
                },
              ),
              onTap: c == null ? null : _selectContent,
            ),
            _numberChoice(
              'frequency',
              context.settingsLabel('تكرار ظهور الذكر'),
              {
                for (final v in AppSettings.frequencies)
                  v: v < 60
                      ? _settingDuration(context, 'everyMinutes', v)
                      : v == 60
                      ? 'كل ساعة'
                      : _settingDuration(context, 'everyHours', v ~/ 60),
              },
              5,
            ),
            _textChoice('type', context.settingsLabel('مكان التنبيه'), const {
              'center': 'مركز الإشعارات',
              'overlay': 'فوق التطبيقات • Android',
            }, 'center'),
            _switchTile(
              'ordered',
              context.settingsLabel('عرض الأذكار بالترتيب'),
              context.settingsLabel('أوقفه للاختيار العشوائي على Android'),
              Icons.format_list_numbered,
            ),
            if (!overlay)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  context.settingsLabel(
                    'تصل الأذكار كإشعارات عادية، دون خدمة عائمة أو إشعار تشغيل ثابت.',
                  ),
                ),
              ),
            if (overlay && android && c != null) ...[
              if (!c.device.overlay)
                _SettingsTile(
                  icon: Icons.layers_outlined,
                  title: context.settingsLabel('السماح بالظهور فوق التطبيقات'),
                  subtitle: context.settingsLabel('إذن مطلوب لعرض فقاعة الذكر'),
                  onTap: () => c.action('overlayPermission'),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          c.device.overlay &&
                              c.device.allowed &&
                              _settings!.flag('enabled') &&
                              _settings!.flag('smart') &&
                              _settings!.content.isNotEmpty
                          ? () => c.action('startOverlay')
                          : null,
                      icon: Icon(
                        c.device.overlayRunning
                            ? Icons.refresh
                            : Icons.play_arrow,
                      ),
                      label: Text(
                        c.device.overlayRunning
                            ? context.settingsLabel('إعادة بدء التنبيه العائم')
                            : context.settingsLabel('بدء التنبيه العائم'),
                      ),
                    ),
                  ),
                  if (c.device.overlayRunning) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => c.action('stopOverlay'),
                      child: Text(context.settingsLabel('إيقاف')),
                    ),
                  ],
                ],
              ),
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  context.settingsLabel(
                    'التشغيل العائم يحتاج إشعار خدمة صامتًا من Android مع زر إيقاف. يمكنك إدارة ظهوره من إعدادات قناته. لا يظهر الذكر فوق شاشة القفل.',
                  ),
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
              ),
              TextButton(
                onPressed: () => c.action('overlayNotificationSettings'),
                child: Text(
                  context.settingsLabel('خيارات إشعار التشغيل في الجهاز'),
                ),
              ),
            ],
            if (overlay && !android && c?.device.platform == 'ios')
              _NoticeBox(
                context.settingsLabel('متاح على Android فقط'),
                context.settingsLabel(
                  'يستخدم iPhone مركز الإشعارات بالنص الأول المحدد، دون نافذة فوق التطبيقات أو نطق في الخلفية.',
                ),
              ),
            if (overlay)
              ExpansionTile(
                key: const PageStorageKey('smart-overlay-appearance'),
                tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(context.settingsLabel('مظهر الذكر العائم')),
                subtitle: Text(
                  context.settingsLabel('الموضع، مدة الظهور، الخط والألوان'),
                ),
                children: [
                  _textChoice(
                    'position',
                    context.settingsLabel('موضع التنبيه العائم'),
                    const {
                      'top': 'أعلى الشاشة',
                      'center': 'وسط الشاشة',
                      'bottom': 'أسفل الشاشة',
                    },
                    'top',
                  ),
                  _numberChoice(
                    'hide',
                    context.settingsLabel('إخفاء الذكر تلقائياً'),
                    const {
                      -1: 'حسب عدد الكلمات',
                      0: 'بالضغط فقط',
                      5: '5 ثوانٍ',
                      10: '10 ثوانٍ',
                      20: '20 ثانية',
                      30: '30 ثانية',
                    },
                    -1,
                  ),
                  _switchTile(
                    'transparent',
                    context.settingsLabel('شفافية الخلفية'),
                    context.settingsLabel('مع بقاء الإطار والنص'),
                    Icons.palette_outlined,
                  ),
                  _numberChoice(
                    'fontSize',
                    context.settingsLabel('حجم خط التنبيه'),
                    {
                      for (final v in [12, 15, 20, 25, 30, 35, 40, 45, 50])
                        v: '$v',
                    },
                    20,
                  ),
                  _textChoice(
                    'font',
                    context.settingsLabel('خط التنبيه'),
                    const {
                      'Cairo': 'القاهرة',
                      'Tajawal': 'تجوال',
                      'Amiri': 'أميري',
                    },
                    'Cairo',
                  ),
                  for (final entry in const {
                    'background': 'لون الخلفية',
                    'border': 'لون الإطار',
                    'textColor': 'لون النص',
                  }.entries)
                    _numberChoice(
                      entry.key,
                      entry.value,
                      const {
                        0xFF2A8C82: 'فيروزي',
                        0xFF102A43: 'كحلي',
                        0xFFC7A45A: 'ذهبي',
                        0xFFFFFCF7: 'عاجي',
                      },
                      entry.key == 'background'
                          ? 0xFF2A8C82
                          : entry.key == 'border'
                          ? 0xFFC7A45A
                          : 0xFFFFFCF7,
                      icon: Icons.color_lens_outlined,
                    ),
                  _switchTile(
                    'effects',
                    context.settingsLabel('حركة الظهور'),
                    context.settingsLabel('يمكن إيقافها لعرض ثابت'),
                    Icons.animation,
                  ),
                  if (_settings!.flag('effects'))
                    _textChoice(
                      'animation',
                      context.settingsLabel('نوع الحركة'),
                      const {
                        'zoom': 'تكبير',
                        'fade': 'تلاشي',
                        'height': 'امتداد طولي',
                        'width': 'امتداد عرضي',
                        'vertical': 'انزلاق عمودي',
                        'horizontal': 'انزلاق أفقي',
                        'bounce': 'ارتداد',
                      },
                      'zoom',
                    ),
                  _overlayPreview(),
                ],
              ),
            ExpansionTile(
              key: const PageStorageKey('smart-sound-options'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(context.settingsLabel('الصوت والتفاعل')),
              children: [
                _switchTile(
                  'sound',
                  context.settingsLabel('صوت التذكيرات'),
                  context.settingsLabel('يتبع أيضًا إعدادات قنوات الجهاز'),
                  Icons.volume_up_outlined,
                ),
                if (overlay && android)
                  _switchTile(
                    'speech',
                    context.settingsLabel('نطق الذكر العائم'),
                    context.settingsLabel(
                      'يحتاج صوتًا عربيًا مثبتًا على الجهاز',
                    ),
                    Icons.record_voice_over_outlined,
                  ),
                _numberChoice(
                  'snooze',
                  context.settingsLabel('التأجيل السريع'),
                  {
                    for (final v in AppSettings.snoozes)
                      v: _settingDuration(context, 'minutes', v),
                  },
                  10,
                ),
                if (c != null)
                  OutlinedButton.icon(
                    onPressed: c.device.allowed
                        ? () => c.action('preview')
                        : null,
                    icon: const Icon(Icons.notifications_outlined),
                    label: Text(
                      context.settingsLabel('إرسال إشعار معاينة للجهاز'),
                    ),
                  ),
              ],
            ),
            ExpansionTile(
              key: const PageStorageKey('smart-permissions'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(context.settingsLabel('حالة الجهاز والأذونات')),
              subtitle: Text(
                c?.device.allowed == true
                    ? context.settingsLabel('الإشعارات مسموحة')
                    : context.settingsLabel('تحقق من إذن الإشعارات'),
              ),
              children: [_deviceStatus()],
            ),
          ],
        ),
      ),
    );
  }

  Widget _overlayPreview() {
    final s = _settings!, c = widget.reminders;
    final chosen = s.content
        .map((id) => c?.content[id])
        .whereType<String>()
        .firstOrNull;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: s.flag('transparent')
            ? Colors.transparent
            : Color(s.number('background', 0xFF2A8C82)),
        border: Border.all(color: Color(s.number('border', 0xFFC7A45A))),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        chosen ??
            context.settingsLabel('معاينة تنبيه حق — اختر محتوى التنبيهات'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: s.number('fontSize', 20).toDouble(),
          color: Color(s.number('textColor', 0xFFFFFCF7)),
          fontFamily: switch (s.text('font', 'Cairo')) {
            'Tajawal' => 'Tajawal',
            'Amiri' => 'AmiriQuran',
            _ => 'QuranUI',
          },
        ),
      ),
    );
  }

  Future<void> _selectContent() async {
    final owner = _settings!, c = widget.reminders!;
    final value = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) {
        _activeDialog = dialogContext;
        return _DhikrContentPicker(
          content: Map.of(c.content),
          initial: owner.content,
        );
      },
    );
    _activeDialog = null;
    if (mounted && value != null && _settings == owner) {
      await owner.set('content', value);
    }
  }

  Widget _permissionControls() => Column(
    children: [
      _deviceStatus(),
      if (widget.reminders case final c?) ...[
        _SettingsTile(
          icon: Icons.layers_outlined,
          title: context.settingsLabel('الظهور فوق التطبيقات'),
          subtitle: context.settingsLabel('إذن مستقل عن إذن الإشعارات'),
          value: c.device.platform == 'ios'
              ? context.settingsLabel('غير متاح على iOS')
              : c.device.overlay
              ? context.settingsLabel('مسموح')
              : context.settingsLabel('غير مسموح'),
          onTap: c.device.platform == 'android'
              ? () => c.action('overlayPermission')
              : null,
        ),
        _SettingsTile(
          icon: Icons.battery_saver_outlined,
          title: context.settingsLabel('إعدادات البطارية'),
          subtitle: context.settingsLabel(
            'افتح إعدادات النظام إذا تأخرت التذكيرات',
          ),
          value: 'فتح',
          onTap: () => c.action('batterySettings'),
        ),
      ],
      _NoticeBox(
        context.settingsLabel('الصلاحيات بيدك'),
        context.settingsLabel(
          'فتح إعدادات الجهاز لا يمنح الإذن تلقائياً. يمكن استخدام التطبيق مع رفض الإشعارات أو الظهور فوق التطبيقات. لا تُرسل أذكارك الشخصية إلى الخادم من هذا القسم.',
        ),
      ),
      _InfoBox(
        context.settingsLabel('الإعدادات والحساب'),
        context.settingsLabel(
          'تُحفظ تفضيلات التذكير لكل حساب على الجهاز. عند تغيير الحساب تُستبدل خطته وتُزال تنبيهاته القديمة. إعدادات القرآن والمظهر تستخدم مخازنها الحالية.',
        ),
      ),
      TextButton(
        onPressed: () async {
          final owner = _settings!;
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(context.settingsLabel('إعادة إعدادات التذكير؟')),
              content: Text(
                context.settingsLabel(
                  'تلغي التذكيرات وتخصيصاتها لهذا الحساب فقط. تبقى الأذكار والتقدم وإعدادات القرآن محفوظة.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.settingsLabel('إلغاء')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.settingsLabel('إعادة الضبط')),
                ),
              ],
            ),
          );
          if (mounted && confirm == true && _settings == owner) {
            await owner.reset();
          }
        },
        child: Text(context.settingsLabel('إعادة ضبط إعدادات التذكير')),
      ),
    ],
  );
}
