part of 'settings_pages.dart';

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
                  const _NoticeBox(
                    'تعذّر تجهيز الإعدادات',
                    'أعد المحاولة لتحميل إعدادات الحساب وجدولة تذكيراته.',
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() => _load = widget.load()),
                    child: const Text('إعادة المحاولة'),
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
          title: Text(title),
          children: [
            for (final option in options.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, option.key),
                child: Row(
                  children: [
                    Expanded(child: Text(option.value)),
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
      helpText: title,
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
    subtitle: 'يُحفظ الاختيار فوراً',
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
    subtitle: 'يُحفظ الاختيار فوراً',
    value: options[_settings!.text(key, initial)],
    onTap: () => _choose(key, title, options, _settings!.text(key, initial)),
  );

  Widget _deviceStatus() {
    final c = widget.reminders;
    final state = c?.device;
    return Column(
      children: [
        _InfoBox(
          'حالة الجهاز',
          state?.supported != true
              ? 'الجدولة غير متاحة في بيئة العرض الحالية. التفضيلات تبقى محفوظة.'
              : !state!.allowed
              ? 'الإشعارات غير مسموحة. امنح الإذن من الزر أدناه.'
              : '${state.pending} تذكير في الخطة • ${state.platform == 'android' ? (state.exact ? 'المواعيد المحددة مجدولة بدقة' : 'قد تتأخر المواعيد حتى تسمح بالتنبيه الدقيق') : 'تنبيهات iOS المحلية'}',
        ),
        if (c?.error case final error?)
          _NoticeBox('الجدولة تحتاج متابعة', error),
        if (c != null)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!c.device.allowed)
                OutlinedButton.icon(
                  onPressed: () => c.action('requestPermission'),
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('طلب إذن الإشعارات'),
                ),
              TextButton(
                onPressed: () => c.action('notificationSettings'),
                child: const Text('إعدادات الإشعارات في الجهاز'),
              ),
              TextButton(
                onPressed: () => c.reconcile(force: true),
                child: const Text('تحديث الحالة والجدولة'),
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
        'تفعيل التذكيرات',
        'لا يُطلب الإذن إلا باختيارك',
        Icons.notifications_none,
      ),
      _deviceStatus(),
      if (widget.reminders case final c?
          when c.device.platform == 'android') ...[
        const _InfoBox(
          'منبّه أذكار الصباح والمساء والنوم',
          'يظهر بشاشة مثل الأذان، ثم تبدأ تسجيلات أذكار المجموعة تلقائيًا بعد النداء. يمكنك فتح الأذكار ومتابعة الاستماع، أو إيقافه وتأجيله من الإشعار.',
        ),
        if (!c.device.exact)
          OutlinedButton(
            onPressed: () => c.action('exactAlarmPermission'),
            child: const Text('السماح بالتنبيه في الموعد'),
          ),
        if (!c.device.fullScreen)
          OutlinedButton(
            onPressed: () => c.action('fullScreenPermission'),
            child: const Text('السماح بشاشة التذكير عند القفل'),
          ),
        _switchTile(
          'sound',
          'صوت التذكيرات',
          'نداء عربي مولّد ثم تسجيلات حصن المسلم، محفوظة دون إنترنت',
          Icons.volume_up_outlined,
        ),
        const _InfoBox(
          'القراءة الصوتية',
          'يُقرأ كل تسجيل من المصدر مرة واحدة، وأعداد التكرار ظاهرة في القارئ. الاستماع لا يسجّل إنجازًا تلقائيًا، ويستمر عند إطفاء الشاشة حتى توقفه.',
        ),
      ],
      const _SectionTitle('تذكيرات الأذكار'),
      for (final entry in const {
        'morning': 'أذكار الصباح',
        'evening': 'أذكار المساء',
        'sleep': 'أذكار النوم',
      }.entries) ...[
        _switchTile(
          entry.key,
          entry.value,
          'تذكير يومي اختياري',
          entry.key == 'morning'
              ? Icons.light_mode_outlined
              : Icons.dark_mode_outlined,
        ),
        _SettingsTile(
          icon: Icons.access_time,
          title: 'موعد ${entry.value}',
          subtitle: 'التوقيت المحلي للجهاز',
          value: AppSettings.clockLabel(_settings!.time(entry.key)),
          onTap: () => _time(entry.key, entry.value),
        ),
      ],
      const _NoticeBox(
        'أذكار ما بعد الصلاة',
        'تحتاج مواقيت محسوبة للموقع؛ تُربط في مرحلة الصلاة والقبلة.',
      ),
      const _SectionTitle('الورد والختمة والمحتوى'),
      for (final entry in const {
        'dailyWird': 'الورد اليومي',
        'friday': 'تذكير الجمعة',
        'messages': 'المحتوى الإيماني',
      }.entries) ...[
        _switchTile(
          entry.key,
          entry.value,
          entry.key == 'friday'
              ? 'يوم الجمعة فقط'
              : 'تذكير يومي بزيارة المحتوى المحفوظ',
          Icons.menu_book_outlined,
        ),
        _SettingsTile(
          icon: Icons.access_time,
          title: 'موعد ${entry.value}',
          subtitle: 'التوقيت المحلي للجهاز',
          value: AppSettings.clockLabel(_settings!.time(entry.key)),
          onTap: () => _time(entry.key, entry.value),
        ),
      ],
      const _InfoBox(
        'تذكير الختمة',
        'يُضبط الموعد من كل ختمة. تُلغى تذكيرات الختمة عند إكمالها أو أرشفتها أو حذفها، ويجب تفعيل التذكيرات العامة هنا.',
      ),
      if (kDebugMode && widget.reminders?.device.platform == 'android') ...[
        const _SectionTitle('اختبار التذكيرات على الجهاز'),
        const _InfoBox(
          'اختبار بعد 10 ثوانٍ',
          'يمكنك قفل الشاشة أو تصغير التطبيق. الاختبار لا يغيّر مواعيدك أو يفعّل التذكيرات المعطلة، ولا يسجل إنجازًا.',
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
                          content: Text('اختبار ${entry.value} بعد 10 ثوانٍ'),
                        ),
                      );
                    }
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'تحقق من إذن الإشعارات والتنبيه الدقيق',
                          ),
                        ),
                      );
                    }
                  }
                },
                child: Text('اختبار ${entry.value}'),
              ),
          ],
        ),
        TextButton(
          onPressed: () => widget.reminders!.action('clearReminderTests'),
          child: const Text('إلغاء الاختبار وإزالة إشعاراته'),
        ),
      ],
      const _InfoBox(
        'المحتوى الإيماني',
        'هذا تذكير محلي لفتح المكتبة؛ إشعارات الرسائل الجديدة من الخادم تُنفذ في مرحلة الرسائل.',
      ),
      _switchTile(
        'startup',
        'استعادة التذكيرات بعد تشغيل الجهاز',
        'Android: يعيد الجدولة دون تشغيل التنبيه العائم تلقائياً',
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
              'تفعيل التذكيرات',
              'المفتاح العام لتذكيرات حق',
              Icons.notifications_none,
            ),
            _switchTile(
              'smart',
              'تفعيل الأذكار المتكررة',
              'أذكار تختارها وتتكرر خلال اليوم',
              Icons.eco_outlined,
            ),
            _SettingsTile(
              icon: Icons.menu_book_outlined,
              title: 'محتوى التنبيهات',
              subtitle: 'اختر الأذكار أو حدّدها كلها',
              value: '${_settings!.content.length} محدد',
              onTap: c == null ? null : _selectContent,
            ),
            _numberChoice('frequency', 'تكرار ظهور الذكر', {
              for (final v in AppSettings.frequencies)
                v: v < 60
                    ? 'كل $v دقيقة'
                    : v == 60
                    ? 'كل ساعة'
                    : 'كل ${v ~/ 60} ساعات',
            }, 5),
            _textChoice('type', 'مكان التنبيه', const {
              'center': 'مركز الإشعارات',
              'overlay': 'فوق التطبيقات • Android',
            }, 'center'),
            _switchTile(
              'ordered',
              'عرض الأذكار بالترتيب',
              'أوقفه للاختيار العشوائي على Android',
              Icons.format_list_numbered,
            ),
            if (!overlay)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'تصل الأذكار كإشعارات عادية، دون خدمة عائمة أو إشعار تشغيل ثابت.',
                ),
              ),
            if (overlay && android && c != null) ...[
              if (!c.device.overlay)
                _SettingsTile(
                  icon: Icons.layers_outlined,
                  title: 'السماح بالظهور فوق التطبيقات',
                  subtitle: 'إذن مطلوب لعرض فقاعة الذكر',
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
                            ? 'إعادة بدء التنبيه العائم'
                            : 'بدء التنبيه العائم',
                      ),
                    ),
                  ),
                  if (c.device.overlayRunning) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => c.action('stopOverlay'),
                      child: const Text('إيقاف'),
                    ),
                  ],
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'التشغيل العائم يحتاج إشعار خدمة صامتًا من Android مع زر إيقاف. يمكنك إدارة ظهوره من إعدادات قناته. لا يظهر الذكر فوق شاشة القفل.',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
              ),
              TextButton(
                onPressed: () => c.action('overlayNotificationSettings'),
                child: const Text('خيارات إشعار التشغيل في الجهاز'),
              ),
            ],
            if (overlay && !android && c?.device.platform == 'ios')
              const _NoticeBox(
                'متاح على Android فقط',
                'يستخدم iPhone مركز الإشعارات بالنص الأول المحدد، دون نافذة فوق التطبيقات أو نطق في الخلفية.',
              ),
            if (overlay)
              ExpansionTile(
                key: const PageStorageKey('smart-overlay-appearance'),
                tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text('مظهر الذكر العائم'),
                subtitle: const Text('الموضع، مدة الظهور، الخط والألوان'),
                children: [
                  _textChoice('position', 'موضع التنبيه العائم', const {
                    'top': 'أعلى الشاشة',
                    'center': 'وسط الشاشة',
                    'bottom': 'أسفل الشاشة',
                  }, 'top'),
                  _numberChoice('hide', 'إخفاء الذكر تلقائياً', const {
                    -1: 'حسب عدد الكلمات',
                    0: 'بالضغط فقط',
                    5: '5 ثوانٍ',
                    10: '10 ثوانٍ',
                    20: '20 ثانية',
                    30: '30 ثانية',
                  }, -1),
                  _switchTile(
                    'transparent',
                    'شفافية الخلفية',
                    'مع بقاء الإطار والنص',
                    Icons.palette_outlined,
                  ),
                  _numberChoice('fontSize', 'حجم خط التنبيه', {
                    for (final v in [12, 15, 20, 25, 30, 35, 40, 45, 50])
                      v: '$v',
                  }, 20),
                  _textChoice('font', 'خط التنبيه', const {
                    'Cairo': 'القاهرة',
                    'Tajawal': 'تجوال',
                    'Amiri': 'أميري',
                  }, 'Cairo'),
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
                    'حركة الظهور',
                    'يمكن إيقافها لعرض ثابت',
                    Icons.animation,
                  ),
                  if (_settings!.flag('effects'))
                    _textChoice('animation', 'نوع الحركة', const {
                      'zoom': 'تكبير',
                      'fade': 'تلاشي',
                      'height': 'امتداد طولي',
                      'width': 'امتداد عرضي',
                      'vertical': 'انزلاق عمودي',
                      'horizontal': 'انزلاق أفقي',
                      'bounce': 'ارتداد',
                    }, 'zoom'),
                  _overlayPreview(),
                ],
              ),
            ExpansionTile(
              key: const PageStorageKey('smart-sound-options'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('الصوت والتفاعل'),
              children: [
                _switchTile(
                  'sound',
                  'صوت التذكيرات',
                  'يتبع أيضًا إعدادات قنوات الجهاز',
                  Icons.volume_up_outlined,
                ),
                if (overlay && android)
                  _switchTile(
                    'speech',
                    'نطق الذكر العائم',
                    'يحتاج صوتًا عربيًا مثبتًا على الجهاز',
                    Icons.record_voice_over_outlined,
                  ),
                _numberChoice('snooze', 'التأجيل السريع', {
                  for (final v in AppSettings.snoozes) v: '$v دقيقة',
                }, 10),
                if (c != null)
                  OutlinedButton.icon(
                    onPressed: c.device.allowed
                        ? () => c.action('preview')
                        : null,
                    icon: const Icon(Icons.notifications_outlined),
                    label: const Text('إرسال إشعار معاينة للجهاز'),
                  ),
              ],
            ),
            ExpansionTile(
              key: const PageStorageKey('smart-permissions'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('حالة الجهاز والأذونات'),
              subtitle: Text(
                c?.device.allowed == true
                    ? 'الإشعارات مسموحة'
                    : 'تحقق من إذن الإشعارات',
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
        chosen ?? 'معاينة تنبيه حق — اختر محتوى التنبيهات',
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
          title: 'الظهور فوق التطبيقات',
          subtitle: 'إذن مستقل عن إذن الإشعارات',
          value: c.device.platform == 'ios'
              ? 'غير متاح على iOS'
              : c.device.overlay
              ? 'مسموح'
              : 'غير مسموح',
          onTap: c.device.platform == 'android'
              ? () => c.action('overlayPermission')
              : null,
        ),
        _SettingsTile(
          icon: Icons.battery_saver_outlined,
          title: 'إعدادات البطارية',
          subtitle: 'افتح إعدادات النظام إذا تأخرت التذكيرات',
          value: 'فتح',
          onTap: () => c.action('batterySettings'),
        ),
      ],
      const _NoticeBox(
        'الصلاحيات بيدك',
        'فتح إعدادات الجهاز لا يمنح الإذن تلقائياً. يمكن استخدام التطبيق مع رفض الإشعارات أو الظهور فوق التطبيقات. لا تُرسل أذكارك الشخصية إلى الخادم من هذا القسم.',
      ),
      const _InfoBox(
        'الإعدادات والحساب',
        'تُحفظ تفضيلات التذكير لكل حساب على الجهاز. عند تغيير الحساب تُستبدل خطته وتُزال تنبيهاته القديمة. إعدادات القرآن والمظهر تستخدم مخازنها الحالية.',
      ),
      TextButton(
        onPressed: () async {
          final owner = _settings!;
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('إعادة إعدادات التذكير؟'),
              content: const Text(
                'تلغي التذكيرات وتخصيصاتها لهذا الحساب فقط. تبقى الأذكار والتقدم وإعدادات القرآن محفوظة.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('إعادة الضبط'),
                ),
              ],
            ),
          );
          if (mounted && confirm == true && _settings == owner) {
            await owner.reset();
          }
        },
        child: const Text('إعادة ضبط إعدادات التذكير'),
      ),
    ],
  );
}
