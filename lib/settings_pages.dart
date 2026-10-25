import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_appearance.dart';
import 'features/settings/data/app_settings.dart';
import 'features/settings/data/reminder_controller.dart';

part 'settings_reminders.dart';

const _teal = Color(0xFF0A8B80);

ThemeMode _themeMode(String label) => switch (label) {
  'فاتح' => ThemeMode.light,
  'داكن' => ThemeMode.dark,
  _ => ThemeMode.system,
};

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    this.onQuranSettings,
    this.onQuranAccount,
    this.onQuranDownloads,
    this.reminders,
    this.loadReminders,
  });
  final VoidCallback? onQuranSettings;
  final VoidCallback? onQuranAccount, onQuranDownloads;
  final ReminderController? reminders;
  final Future<ReminderController?> Function()? loadReminders;

  @override
  Widget build(BuildContext context) => _SettingsShell(
    title: 'إعدادات التطبيق',
    subtitle: 'خصص تجربتك بما يناسبك',
    icon: Icons.settings_outlined,
    child: Column(
      children: [
        _section('الحساب والبيانات'),
        _link(context, SettingKind.account),
        _section('المظهر والقراءة'),
        _link(context, SettingKind.appearance),
        _link(context, SettingKind.quran),
        _section('الصلاة والتذكيرات'),
        _link(context, SettingKind.prayer),
        _link(context, SettingKind.reminders),
        _link(context, SettingKind.notifications),
        _section('إعدادات إضافية'),
        _link(context, SettingKind.hijri),
        _link(context, SettingKind.storage),
        _link(context, SettingKind.privacy),
        _link(context, SettingKind.about),
      ],
    ),
  );

  Widget _section(String text) => _SectionTitle(text);

  Widget _link(BuildContext context, SettingKind kind) => _SettingsTile(
    icon: kind.icon,
    title: kind.title,
    subtitle: kind.subtitle,
    onTap: kind == SettingKind.account && onQuranAccount != null
        ? onQuranAccount
        : kind == SettingKind.storage && onQuranDownloads != null
        ? onQuranDownloads
        : kind == SettingKind.quran && onQuranSettings != null
        ? onQuranSettings
        : () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  reminders == null &&
                      loadReminders != null &&
                      [
                        SettingKind.reminders,
                        SettingKind.notifications,
                        SettingKind.privacy,
                        SettingKind.hijri,
                      ].contains(kind)
                  ? _LoadReminderSettings(kind: kind, load: loadReminders!)
                  : SettingsDetailPage(kind: kind, reminders: reminders),
            ),
          ),
  );
}

enum SettingKind {
  account('الحساب والمزامنة', 'احتفظ بتقدمك وإعداداتك', Icons.person_outline),
  appearance(
    'المظهر وإعدادات العرض',
    'خصص الألوان ونوع الخط وحجمه',
    Icons.palette_outlined,
  ),
  quran(
    'إعدادات القرآن الكريم',
    'القراءة والتلاوة والتفسير',
    Icons.menu_book_outlined,
  ),
  prayer(
    'مواقيت الصلاة والأذان',
    'الموقع والحساب والتنبيهات',
    Icons.access_time,
  ),
  reminders('الأذكار والتذكيرات', 'خصص أوقات الذكر والورد', Icons.eco_outlined),
  notifications(
    'التنبيهات الذكية',
    'الصوت والمظهر وطريقة التفاعل',
    Icons.notifications_none,
  ),
  hijri(
    'التاريخ الهجري',
    'تصحيح اليوم وعرض التاريخ',
    Icons.calendar_month_outlined,
  ),
  storage(
    'التخزين دون إنترنت',
    'إدارة المواد المحملة',
    Icons.download_outlined,
  ),
  privacy(
    'الصلاحيات والخصوصية',
    'موقعك وإشعاراتك وبياناتك',
    Icons.shield_outlined,
  ),
  about('حول تطبيق حق', 'المساعدة والمعلومات الرسمية', Icons.info_outline);

  const SettingKind(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;
}

class SettingsDetailPage extends StatefulWidget {
  const SettingsDetailPage({required this.kind, this.reminders, super.key});
  final SettingKind kind;
  final ReminderController? reminders;

  @override
  State<SettingsDetailPage> createState() => _SettingsDetailPageState();
}

class _SettingsDetailPageState extends State<SettingsDetailPage> {
  AppSettings? _standalone;
  BuildContext? _activeDialog;
  String? _owner;
  AppSettings? get _settings => widget.reminders?.settings ?? _standalone;
  int get _hijriOffset => _settings?.number('hijriOffset', 0) ?? 0;
  @override
  void initState() {
    super.initState();
    _owner = widget.reminders?.settings.scope;
    widget.reminders?.addListener(_ownerChanged);
    if (widget.reminders == null) {
      SharedPreferences.getInstance().then((prefs) {
        if (mounted) setState(() => _standalone = AppSettings(prefs, 'guest'));
      });
    }
  }

  @override
  void dispose() {
    widget.reminders?.removeListener(_ownerChanged);
    _standalone?.dispose();
    super.dispose();
  }

  void _ownerChanged() {
    final next = widget.reminders?.settings.scope;
    if (next == _owner) return;
    _owner = next;
    final dialog = _activeDialog;
    if (dialog != null &&
        dialog.mounted &&
        ModalRoute.of(dialog)?.isCurrent == true) {
      Navigator.pop(dialog);
    }
    _activeDialog = null;
  }

  bool _value(String key, [bool initial = true]) =>
      _settings?.flag(key) ?? false;

  void _toggle(String key, bool value) => unawaited(_settings!.set(key, value));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.reminders ?? _settings ?? const _EmptySettings(),
    builder: (context, _) => _SettingsShell(
      title: widget.kind.title,
      subtitle: widget.kind.subtitle,
      icon: widget.kind.icon,
      child: Column(
        children: [
          if (_settings?.error case final error?)
            _NoticeBox('لم يكتمل الحفظ', error),
          if (_settings == null && widget.kind != SettingKind.appearance)
            const CircularProgressIndicator()
          else
            _body(),
        ],
      ),
    ),
  );

  Widget _body() {
    switch (widget.kind) {
      case SettingKind.account:
        return _account();
      case SettingKind.appearance:
        return _appearance();
      case SettingKind.quran:
        return _quran();
      case SettingKind.prayer:
        return _prayer();
      case SettingKind.reminders:
        return _reminderControls();
      case SettingKind.notifications:
        return _notificationControls();
      case SettingKind.hijri:
        return _hijri();
      case SettingKind.storage:
        return _storage();
      case SettingKind.privacy:
        return _permissionControls();
      case SettingKind.about:
        return _about();
    }
  }

  Widget _account() => Column(
    children: [
      _FeatureCard(
        icon: Icons.person_outline,
        title: 'حسابك وبياناتك',
        subtitle: 'تستخدم الجزء الديني حالياً كضيف',
        badge: 'ضيف — حفظ محلي',
      ),
      _SectionTitle('تسجيل الدخول'),
      _PrimaryButton('تسجيل الدخول أو إنشاء حساب', Icons.person_outline),
      _InfoBox(
        'يمكنك الاستمرار كضيف',
        'تبقى أذكارك وإعداداتك وتقدمك محفوظة على هذا الجهاز فقط، دون مزامنة بين الأجهزة.',
      ),
      _SectionTitle('حفظ البيانات والمزامنة'),
      _SettingsTile(
        icon: Icons.sync,
        title: 'مزامنة التقدم والإعدادات',
        subtitle: 'تعمل بعد تسجيل الدخول وربط الحساب',
        value: 'يتطلب حساب',
      ),
      _SettingsTile(
        icon: Icons.storage_outlined,
        title: 'بيانات الضيف المحفوظة',
        subtitle: 'الأذكار والعلامات المرجعية وتقدم القراءة',
        value: 'على هذا الجهاز',
      ),
      _SettingsTile(
        icon: Icons.restore,
        title: 'استعادة البيانات',
        subtitle: 'استرجاع التقدم المتزامن للحساب',
        value: 'تسجيل الدخول',
      ),
      _NoticeBox(
        'نقل بيانات الضيف عند التسجيل',
        'تحدد آلية دمج أو نقل بيانات الضيف إلى الحساب في السياسة التنفيذية قبل البرمجة.',
      ),
    ],
  );

  Widget _appearance() => Column(
    children: [
      _SectionTitle('وضع التطبيق'),
      Row(
        children: ['فاتح', 'داكن', 'تلقائي']
            .map(
              (mode) => Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: _ChoiceCard(
                    label: mode,
                    icon: mode == 'فاتح'
                        ? Icons.light_mode_outlined
                        : mode == 'داكن'
                        ? Icons.dark_mode_outlined
                        : Icons.sync,
                    selected:
                        !AppearanceScope.of(context).timed &&
                        AppearanceScope.of(context).mode == _themeMode(mode),
                    onTap: () =>
                        AppearanceScope.of(context).setMode(_themeMode(mode)),
                  ),
                ),
              ),
            )
            .toList(),
      ),
      _InfoBox(
        'الوضع التلقائي',
        'يتبع مظهر الجهاز تلقائياً، ويتغير عند تغيير إعداداته.',
      ),
      _SettingsTile(
        icon: Icons.schedule,
        title: 'المظهر حسب الوقت',
        subtitle: 'نهار فاتح وليل داكن حسب وقت الجهاز',
        trailing: Switch(
          value: AppearanceScope.of(context).timed,
          onChanged: AppearanceScope.of(context).setTimed,
        ),
      ),
      if (AppearanceScope.of(context).timed) ...[
        for (final day in [true, false])
          _SettingsTile(
            icon: day ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            title: day ? 'بداية النهار' : 'بداية الليل',
            subtitle: 'التوقيت المحلي للجهاز',
            value: AppSettings.clockLabel(
              day
                  ? AppearanceScope.of(context).dayStart
                  : AppearanceScope.of(context).nightStart,
            ),
            onTap: () async {
              final appearance = AppearanceScope.of(context);
              final minute = day ? appearance.dayStart : appearance.nightStart;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
              );
              if (!mounted || time == null) return;
              final value = time.hour * 60 + time.minute;
              if (value ==
                  (day ? appearance.nightStart : appearance.dayStart)) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('اختر وقتين مختلفين للنهار والليل'),
                    ),
                  );
                }
                return;
              }
              await appearance.setSchedule(
                day: day ? value : appearance.dayStart,
                night: day ? appearance.nightStart : value,
              );
            },
          ),
      ],
      _SectionTitle('نوع الخط'),
      _Panel(
        child: RadioGroup<AppFont>(
          groupValue: AppearanceScope.of(context).font,
          onChanged: (value) {
            if (value != null) AppearanceScope.of(context).setFont(value);
          },
          child: Column(
            children: [
              for (final font in AppFont.values)
                RadioListTile<AppFont>(
                  title: Text(
                    font.label,
                    style: TextStyle(fontFamily: font.family),
                  ),
                  subtitle: Text(
                    'تقبّل الله طاعاتك وجعلنا وإياك من أهل القرآن',
                    style: TextStyle(fontFamily: font.family, fontSize: 12),
                  ),
                  value: font,
                  activeColor: _teal,
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
      ),
      _InfoBox(
        'خط التطبيق',
        'يُطبق الاختيار فورًا على الواجهة ويُحفظ على الجهاز. يبقى نص المصحف بخط قرآني مخصص لضبط الحركات.',
      ),
      _SectionTitle('حجم الخط'),
      _Panel(
        child: Column(
          children: [
            _PanelHeading(
              'نصوص المحتوى الديني',
              'اضبط حجم الخط بما يناسب القراءة',
            ),
            Slider(
              value: AppearanceScope.of(context).fontScale,
              min: .85,
              max: 1.2,
              onChanged: AppearanceScope.of(context).setFontScale,
              activeColor: _teal,
            ),
            Row(
              children: [
                for (final choice in [
                  ('صغير', .85),
                  ('متوسط', 1.0),
                  ('كبير', 1.2),
                ])
                  Expanded(
                    child: TextButton(
                      onPressed: () =>
                          AppearanceScope.of(context).setFontScale(choice.$2),
                      child: Text(
                        choice.$1,
                        style: TextStyle(
                          fontWeight:
                              (AppearanceScope.of(context).fontScale -
                                          choice.$2)
                                      .abs() <
                                  .04
                              ? FontWeight.w900
                              : FontWeight.w400,
                          color: AppPalette.of(context).tealHeading,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      _SectionTitle('معاينة العرض'),
      _Panel(
        child: Column(
          children: [
            Text(
              'مثال على حجم الخط',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppPalette.of(context).tealHeading,
              ),
            ),
            SizedBox(height: 12),
            Text(
              '﴿ أَلَا بِذِكْرِ اللَّهِ تَطْمَئِنُّ الْقُلُوبُ ﴾',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 23,
                color: AppPalette.of(context).tealHeading,
              ),
            ),
            Text(
              'سورة الرعد — الآية 28 (مقتطف)',
              style: TextStyle(color: AppPalette.of(context).muted),
            ),
          ],
        ),
      ),
      _SectionTitle('تفضيلات العرض'),
      _SettingsTile(
        title: 'تطبيق المظهر على جميع الصفحات',
        subtitle: 'يُطبق فوراً ويحفظ الجهاز التفضيل المختار',
        icon: Icons.palette_outlined,
        trailing: Icon(
          Icons.check_circle_outline,
          color: AppPalette.of(context).tealHeading,
        ),
      ),
    ],
  );

  Widget _quran() => const _InfoBox(
    'إعدادات القرآن الكريم',
    'افتح إعدادات القرآن من القائمة الرئيسية للإعدادات؛ تُستخدم إعدادات القارئ الأصلية دون نسخة مكررة.',
  );

  Widget _prayer() => const _NoticeBox(
    'مواقيت الصلاة',
    'لم يُحدد موقع أو أسلوب حساب بعد. سيُربط هذا القسم بالمواقيت في مرحلة الصلاة والقبلة؛ لا تُجدول تنبيهات من مواقيت افتراضية.',
  );
  Widget _storage() => Column(
    children: [
      _SectionTitle('مساحة المحتوى'),
      _Panel(
        child: Column(
          children: [
            _PanelHeading(
              'المحتوى المحفوظ على الجهاز',
              'مثال توضيحي — الأرقام الفعلية من الجهاز',
            ),
            SizedBox(height: 22),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: .52,
                minHeight: 12,
                backgroundColor: Color(0xFFE4E6E3),
                color: _teal,
              ),
            ),
            SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(
                  '• التلاوات والقرآن',
                  style: TextStyle(color: AppPalette.of(context).tealHeading),
                ),
                Text(
                  '• الأذكار والملفات',
                  style: TextStyle(color: AppPalette.of(context).gold),
                ),
              ],
            ),
          ],
        ),
      ),
      _SectionTitle('الملفات المحفوظة'),
      _SettingsTile(
        icon: Icons.headphones_outlined,
        title: 'إدارة التلاوات الصوتية',
        subtitle: 'تصفح أو حذف الملفات المحملة',
        value: 'فتح',
      ),
      _SettingsTile(
        icon: Icons.menu_book_outlined,
        title: 'المحتوى الديني المحلي',
        subtitle: 'الآيات والأذكار المتاحة دون إنترنت',
        value: 'عرض',
      ),
      _SettingsTile(
        icon: Icons.download_outlined,
        title: 'تنزيلات قيد الانتظار',
        subtitle: 'المتابعة أو إعادة المحاولة',
        value: 'إدارة',
      ),
      _SectionTitle('التحكم في التخزين'),
      _SettingsTile(
        icon: Icons.delete_outline,
        title: 'حذف ما تم تحميله',
        subtitle: 'الحذف بعد تأكيد المستخدم',
        value: 'اختيار الملفات',
      ),
      _InfoBox(
        'المزامنة والتنزيل',
        'يبقى المحتوى المحمل متاحاً دون اتصال حينما تسمح خصائصه ومصادره.',
      ),
    ],
  );

  Widget _hijri() => Column(
    children: [
      _SectionTitle('التاريخ المعروض'),
      _Panel(
        child: Column(
          children: [
            Text(
              'التاريخ الهجري الحالي',
              style: TextStyle(color: AppPalette.of(context).muted),
            ),
            SizedBox(height: 18),
            Text(
              'وفق تقويم الجهاز',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w900,
                color: AppPalette.of(context).tealHeading,
              ),
            ),
            SizedBox(height: 18),
            Text(
              'يمكن تصحيح اليوم يدوياً عند الحاجة',
              style: TextStyle(color: AppPalette.of(context).muted),
            ),
          ],
        ),
      ),
      _SectionTitle('تصحيح التاريخ الهجري'),
      _Panel(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _CircleAction(
                  Icons.remove,
                  () => _settings!.set(
                    'hijriOffset',
                    (_hijriOffset - 1).clamp(-3, 3),
                  ),
                ),
                Column(
                  children: [
                    Text(
                      '$_hijriOffset',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.of(context).tealHeading,
                      ),
                    ),
                    Text(
                      'يوم',
                      style: TextStyle(color: AppPalette.of(context).muted),
                    ),
                  ],
                ),
                _CircleAction(
                  Icons.add,
                  () => _settings!.set(
                    'hijriOffset',
                    (_hijriOffset + 1).clamp(-3, 3),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            Text(
              'مقدار الإزاحة عن التاريخ المحسوب',
              style: TextStyle(color: AppPalette.of(context).muted),
            ),
          ],
        ),
      ),
      _SettingsTile(
        icon: Icons.refresh,
        title: 'إعادة القيمة الافتراضية',
        subtitle: 'إزالة التصحيح اليدوي',
        value: 'إعادة الضبط',
        onTap: () => _settings!.set('hijriOffset', 0),
      ),
      _SectionTitle('تطبيق التصحيح'),
      _switchTile(
        'correctHijri',
        'استخدام التاريخ المصحح',
        'في التاريخ الهجري المعروض داخل التطبيق',
        Icons.calendar_month_outlined,
      ),
      const _InfoBox(
        'الحفظ تلقائي',
        'يُحفظ التصحيح بين -3 و+3 أيام فور تغييره. يُربط بعرض التقويم في مرحلة المواقيت.',
      ),
      _NoticeBox(
        'تنبيه',
        'هذا التعديل يغيّر العرض الهجري داخل التطبيق، ولا يغيّر تاريخ الهاتف نفسه.',
      ),
    ],
  );

  Widget _about() => Column(
    children: [
      _FeatureCard(
        icon: Icons.image_outlined,
        title: 'تطبيق حق',
        subtitle: 'المحتوى الديني والخدمات المرتبطة بجمعية حق',
        badge: 'الإصدار: يُعرض من التطبيق',
        showLogo: true,
      ),
      _SectionTitle('المعلومات الرسمية'),
      _SettingsTile(
        icon: Icons.info_outline,
        title: 'عن جمعية حق',
        subtitle: 'معلومات الجمعية ورسالتها',
        value: 'فتح',
      ),
      _SettingsTile(
        icon: Icons.menu_book_outlined,
        title: 'الشروط والأحكام',
        subtitle: 'المستند القانوني المعتمد',
        value: 'عرض',
      ),
      _SettingsTile(
        icon: Icons.shield_outlined,
        title: 'سياسة الخصوصية',
        subtitle: 'بيانات المستخدم وحقوقه',
        value: 'عرض',
      ),
      _SectionTitle('المساعدة والتواصل'),
      _SettingsTile(
        icon: Icons.help_outline,
        title: 'الأسئلة الشائعة',
        subtitle: 'إجابات عن الاستخدام والتذكيرات',
        value: 'فتح',
      ),
      _SettingsTile(
        icon: Icons.headset_mic_outlined,
        title: 'التواصل مع الدعم',
        subtitle: 'قنوات التواصل التي تعتمدها الجمعية',
        value: 'فتح',
      ),
      _SettingsTile(
        icon: Icons.edit_outlined,
        title: 'إرسال ملاحظة',
        subtitle: 'اقتراح أو مشكلة في التطبيق',
        value: 'فتح',
      ),
    ],
  );

  Widget _switchTile(
    String key,
    String title,
    String subtitle,
    IconData icon, [
    bool initial = true,
  ]) => _SettingsTile(
    icon: icon,
    title: title,
    subtitle: subtitle,
    trailing: Switch(
      value: _value(key, initial),
      onChanged: (v) => _toggle(key, v),
      activeTrackColor: _teal,
    ),
  );
}

class _SettingsShell extends StatelessWidget {
  const _SettingsShell({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppPalette.of(context).background,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(title: title, subtitle: subtitle, icon: icon),
                ),
                SliverToBoxAdapter(
                  child: Container(
                    transform: Matrix4.translationValues(0, -22, 0),
                    padding: EdgeInsets.fromLTRB(18, 28, 18, 125),
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).background,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(30),
                      ),
                    ),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _SettingsBottomBar()),
        ],
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    height: 265,
    padding: EdgeInsets.fromLTRB(
      18,
      MediaQuery.paddingOf(context).top + 12,
      18,
      20,
    ),
    decoration: BoxDecoration(
      image: DecorationImage(
        image: AssetImage('assets/images/home_header.png'),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        colorFilter: Theme.of(context).brightness == Brightness.dark
            ? const ColorFilter.mode(Color(0xB3102A43), BlendMode.darken)
            : null,
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          right: 0,
          top: 0,
          child: Material(
            color: AppPalette.of(context).surface,
            elevation: 2,
            shape: CircleBorder(),
            child: InkWell(
              customBorder: CircleBorder(),
              onTap: () => Navigator.maybePop(context),
              child: SizedBox(
                width: 60,
                height: 60,
                child: Icon(
                  Icons.arrow_back_ios_new,
                  color: AppPalette.of(context).tealHeading,
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppPalette.of(context).paleTeal,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: _teal, size: 31),
              ),
              SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppPalette.of(context).tealHeading,
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  subtitle,
                  maxLines: 1,
                  style: TextStyle(
                    color: AppPalette.of(context).heading,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(6, 13, 6, 8),
    child: Align(
      alignment: Alignment.centerRight,
      child: Text(
        text,
        style: TextStyle(
          color: AppPalette.of(context).gold,
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 9),
    child: Material(
      color: AppPalette.of(context).surface,
      elevation: .5,
      shadowColor: AppPalette.of(context).heading.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: BoxConstraints(minHeight: 82),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            border: Border.all(color: AppPalette.of(context).border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppPalette.of(context).paleTeal,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: _teal, size: 27),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppPalette.of(context).tealHeading,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppPalette.of(context).muted,
                        fontSize: 12.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else ...[
                if (value != null)
                  Flexible(
                    child: Text(
                      value!,
                      textAlign: TextAlign.left,
                      style: TextStyle(color: Color(0xFF9C875B), fontSize: 12),
                    ),
                  ),
                SizedBox(width: 5),
                Icon(
                  Icons.chevron_left,
                  color: AppPalette.of(context).tealHeading,
                  size: 19,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: EdgeInsets.only(bottom: 9),
    padding: EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppPalette.of(context).surface,
      border: Border.all(color: AppPalette.of(context).border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading(this.title, this.subtitle);
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            color: AppPalette.of(context).tealHeading,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      Flexible(
        child: Text(
          subtitle,
          style: TextStyle(color: AppPalette.of(context).muted, fontSize: 11),
        ),
      ),
    ],
  );
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    this.showLogo = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final bool showLogo;
  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      children: [
        showLogo
            ? Image.asset(
                'assets/branding/haq_logo_transparent.png',
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppPalette.of(context).heading
                    : null,
                width: 100,
                height: 100,
              )
            : Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: AppPalette.of(context).paleTeal,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: _teal, size: 45),
              ),
        SizedBox(height: 10),
        Text(
          title,
          style: TextStyle(
            color: AppPalette.of(context).tealHeading,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 9),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppPalette.of(context).muted),
        ),
        SizedBox(height: 9),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppPalette.of(context).notice,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            badge,
            style: TextStyle(color: AppPalette.of(context).gold),
          ),
        ),
      ],
    ),
  );
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      height: 125,
      decoration: BoxDecoration(
        color: selected
            ? AppPalette.of(context).paleTeal
            : AppPalette.of(context).neutral,
        border: Border.all(
          color: selected ? _teal : AppPalette.of(context).border,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        children: [
          if (selected)
            Positioned(
              right: 9,
              top: 9,
              child: CircleAvatar(
                radius: 10,
                backgroundColor: _teal,
                child: Icon(Icons.check, size: 13, color: Colors.white),
              ),
            ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: selected ? _teal : AppPalette.of(context).gold,
                  size: 30,
                ),
                SizedBox(height: 13),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? AppPalette.of(context).tealHeading
                        : AppPalette.of(context).heading,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _InfoBox extends StatelessWidget {
  const _InfoBox(this.title, this.text);
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: EdgeInsets.symmetric(vertical: 10),
    padding: EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: AppPalette.of(context).paleTeal,
      borderRadius: BorderRadius.circular(17),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppPalette.of(context).tealHeading,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 5),
        Text(
          text,
          style: TextStyle(
            color: AppPalette.of(context).muted,
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    ),
  );
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox(this.title, this.text);
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: EdgeInsets.symmetric(vertical: 10),
    padding: EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: AppPalette.of(context).notice,
      borderRadius: BorderRadius.circular(17),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppPalette.of(context).gold,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 5),
        Text(
          text,
          style: TextStyle(
            color: AppPalette.of(context).muted,
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    ),
  );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton(this.text, this.icon);
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 8),
    child: SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton.icon(
        onPressed: () {},
        icon: Icon(icon),
        label: Text(
          text,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: Color(0xFF075C57),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    ),
  );
}

class _CircleAction extends StatelessWidget {
  const _CircleAction(this.icon, this.onTap);
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    icon: Icon(icon),
    color: _teal,
    style: IconButton.styleFrom(
      backgroundColor: AppPalette.of(context).paleTeal,
      fixedSize: Size(58, 58),
    ),
  );
}

class _SettingsBottomBar extends StatelessWidget {
  const _SettingsBottomBar();
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      12,
      8,
      12,
      12 + MediaQuery.paddingOf(context).bottom,
    ),
    decoration: BoxDecoration(
      color: AppPalette.of(context).surface.withValues(alpha: .97),
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      boxShadow: [
        BoxShadow(
          color: AppPalette.of(context).heading.withValues(alpha: .09),
          blurRadius: 18,
        ),
      ],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Expanded(child: _BottomItem(Icons.home_outlined, 'الرئيسية')),
        Expanded(child: _BottomItem(Icons.menu_book_outlined, 'القرآن')),
        Expanded(child: _BottomItem(Icons.eco_outlined, 'الأذكار')),
        Expanded(child: _BottomItem(Icons.explore_outlined, 'القبلة')),
        Expanded(
          child: _BottomItem(Icons.more_horiz, 'المزيد', selected: true),
        ),
      ],
    ),
  );
}

class _BottomItem extends StatelessWidget {
  const _BottomItem(this.icon, this.label, {this.selected = false});
  final IconData icon;
  final String label;
  final bool selected;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      color: selected ? AppPalette.of(context).notice : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: selected ? _teal : AppPalette.of(context).heading,
          size: 27,
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: selected ? _teal : AppPalette.of(context).heading,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}
