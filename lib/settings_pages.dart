import 'package:flutter/material.dart';
import 'app_appearance.dart';

const _teal = Color(0xFF0A8B80);

ThemeMode _themeMode(String label) => switch (label) {
  'فاتح' => ThemeMode.light,
  'داكن' => ThemeMode.dark,
  _ => ThemeMode.system,
};

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.onQuranSettings});
  final VoidCallback? onQuranSettings;

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
    onTap: kind == SettingKind.quran && onQuranSettings != null
        ? onQuranSettings
        : () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SettingsDetailPage(kind: kind),
            ),
          ),
  );
}

enum SettingKind {
  account('الحساب والمزامنة', 'احتفظ بتقدمك وإعداداتك', Icons.person_outline),
  appearance(
    'المظهر وإعدادات العرض',
    'خصص الألوان وحجم النص',
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
  const SettingsDetailPage({required this.kind, super.key});
  final SettingKind kind;

  @override
  State<SettingsDetailPage> createState() => _SettingsDetailPageState();
}

class _SettingsDetailPageState extends State<SettingsDetailPage> {
  final Map<String, bool> _switches = {};
  int _hijriOffset = 0;
  String _mushafMode = 'صفحات';

  bool _value(String key, [bool initial = true]) =>
      _switches.putIfAbsent(key, () => initial);

  void _toggle(String key, bool value) =>
      setState(() => _switches[key] = value);

  @override
  Widget build(BuildContext context) => _SettingsShell(
    title: widget.kind.title,
    subtitle: widget.kind.subtitle,
    icon: widget.kind.icon,
    child: _body(),
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
        return _reminders();
      case SettingKind.notifications:
        return _notifications();
      case SettingKind.hijri:
        return _hijri();
      case SettingKind.storage:
        return _storage();
      case SettingKind.privacy:
        return _privacy();
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

  Widget _quran() => Column(
    children: [
      _SectionTitle('عرض المصحف'),
      Row(
        children: ['نص متصل', 'صفحات', 'آية بآية']
            .map(
              (mode) => Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: _ChoiceCard(
                    label: mode,
                    icon: mode == 'صفحات'
                        ? Icons.folder_outlined
                        : Icons.menu_book_outlined,
                    selected: _mushafMode == mode,
                    onTap: () => setState(() => _mushafMode = mode),
                  ),
                ),
              ),
            )
            .toList(),
      ),
      _SettingsTile(
        icon: Icons.text_fields,
        title: 'حجم الخط داخل المصحف',
        subtitle: 'التحكم في حجم نص القراءة',
        value: 'متوسط',
      ),
      _SectionTitle('الصوت والتفسير'),
      _SettingsTile(
        icon: Icons.headphones_outlined,
        title: 'القارئ الافتراضي',
        subtitle: 'اختيار الصوت المستخدم في التلاوة',
        value: 'اختيار القارئ',
      ),
      _SettingsTile(
        icon: Icons.menu_book_outlined,
        title: 'التفسير الافتراضي',
        subtitle: 'اختيار أحد المصادر المعتمدة',
        value: 'اختيار المصدر',
      ),
      _SettingsTile(
        icon: Icons.sync,
        title: 'التلاوة والتكرار',
        subtitle: 'خيارات تشغيل الآيات وتكرارها',
        value: 'إعدادات',
      ),
      _SectionTitle('القراءة دون اتصال'),
      _SettingsTile(
        icon: Icons.download_outlined,
        title: 'التلاوات المحملة',
        subtitle: 'عرض وإدارة الصوتيات المحفوظة',
        value: 'إدارة الملفات',
      ),
      _InfoBox(
        'حفظ آخر قراءة',
        'يُحفظ موضعك الأخير للعودة إليه من الصفحة الرئيسية تلقائياً.',
      ),
    ],
  );

  Widget _prayer() => Column(
    children: [
      _SectionTitle('الموقع وطريقة الحساب'),
      _SettingsTile(
        icon: Icons.location_on_outlined,
        title: 'الموقع المعتمد',
        subtitle: 'تحديد المواقيت حسب موقع المستخدم',
        value: 'نابلس، فلسطين',
      ),
      _SettingsTile(
        icon: Icons.light_mode_outlined,
        title: 'طريقة حساب الصلاة',
        subtitle: 'قابلة للاختيار بين الطرق المعتمدة',
        value: 'اختيار الطريقة',
      ),
      _SettingsTile(
        icon: Icons.access_time,
        title: 'تعديل المواقيت يدوياً',
        subtitle: 'عند الحاجة وحسب الطريقة المختارة',
        value: 'تخصيص',
      ),
      _SectionTitle('تنبيهات الصلاة'),
      _switchTile(
        'prayerOnTime',
        'التنبيه عند دخول الوقت',
        'إشعارات الصلوات المفروضة',
        Icons.notifications_none,
      ),
      _SettingsTile(
        icon: Icons.access_time,
        title: 'التنبيه قبل الصلاة',
        subtitle: 'تحديد المدة بالدقائق',
        value: '10 دقائق',
      ),
      _SettingsTile(
        icon: Icons.volume_up_outlined,
        title: 'صوت الأذان',
        subtitle: 'اختيار الصوت أو تنبيه صامت',
        value: 'اختيار الصوت',
      ),
      _NoticeBox(
        'دقة المواقيت',
        'قد تختلف المواقيت بحسب الموقع وطريقة الحساب المختارة؛ تُحدّث عند تغيير الإعدادات.',
      ),
    ],
  );

  Widget _reminders() => Column(
    children: [
      _SectionTitle('تذكيرات الأذكار'),
      _switchTile(
        'morning',
        'أذكار الصباح',
        'موعد التذكير: 06:30 ص — مثال',
        Icons.light_mode_outlined,
      ),
      _switchTile(
        'evening',
        'أذكار المساء',
        'موعد التذكير: 05:30 م — مثال',
        Icons.dark_mode_outlined,
      ),
      _switchTile(
        'sleep',
        'أذكار النوم',
        'موعد التذكير: 10:00 م — مثال',
        Icons.access_time,
      ),
      _switchTile(
        'afterPrayer',
        'أذكار بعد الصلاة',
        'تذكير اختياري بعد الصلوات',
        Icons.touch_app_outlined,
        false,
      ),
      _SectionTitle('الورد والختمة'),
      _switchTile(
        'dailyWird',
        'تذكير الورد اليومي',
        'وقت التذكير قابل للتغيير',
        Icons.menu_book_outlined,
      ),
      _switchTile(
        'friday',
        'رسائل يوم الجمعة',
        'سنن الجمعة وسورة الكهف',
        Icons.calendar_month_outlined,
      ),
      _SectionTitle('ضبط أوقات التذكير'),
      _PrimaryButton('اختيار المواعيد والتكرار', Icons.access_time),
      _InfoBox(
        'إشعارات منتظمة',
        'يمكن تعديل كل وقت من صفحة التذكير، وتحترم صلاحيات الإشعارات في الجهاز.',
      ),
    ],
  );

  Widget _notifications() => Column(
    children: [
      _SectionTitle('إشعارات الأذكار الذكية'),
      _switchTile(
        'smart',
        'تفعيل الإشعارات الذكية',
        'تذكيرات أثناء استخدام التطبيقات',
        Icons.notifications_none,
      ),
      _SettingsTile(
        icon: Icons.menu_book_outlined,
        title: 'إظهار المحتوى المخصص',
        subtitle: 'اختيار الأذكار التي تظهر',
        value: 'تحديد المحتوى',
      ),
      _SectionTitle('المظهر أثناء العرض'),
      _SettingsTile(
        icon: Icons.tune,
        title: 'موضع الإشعار',
        subtitle: 'أعلى الشاشة أو الموضع المتاح',
        value: 'أعلى الشاشة',
      ),
      _switchTile(
        'transparent',
        'شفافية الخلفية',
        'خلفية شفافة عند دعم النظام',
        Icons.palette_outlined,
        false,
      ),
      _SettingsTile(
        icon: Icons.text_fields,
        title: 'حجم الخط والألوان',
        subtitle: 'تخصيص إطار ونص التنبيه',
        value: 'تخصيص',
      ),
      _SectionTitle('الصوت والتفاعل'),
      _switchTile(
        'sound',
        'الصوت والاهتزاز',
        'تشغيل أو تعطيل المؤثرات',
        Icons.volume_up_outlined,
      ),
      _SettingsTile(
        icon: Icons.access_time,
        title: 'التأجيل السريع',
        subtitle: 'إجراء اقرأ لاحقاً / إخفاء',
        value: '5 دقائق',
      ),
      _NoticeBox(
        'قدرات النظام',
        'الظهور فوق التطبيقات والأوقات الدقيقة يتوقفان على إصدار Android أو iOS والصلاحيات المتاحة.',
      ),
    ],
  );

  Widget _privacy() => Column(
    children: [
      _SectionTitle('أذونات الجهاز'),
      _SettingsTile(
        icon: Icons.location_on_outlined,
        title: 'الموقع الجغرافي',
        subtitle: 'ضروري لحساب المواقيت والقبلة',
        value: 'من إعدادات الجهاز',
      ),
      _SettingsTile(
        icon: Icons.notifications_none,
        title: 'الإشعارات',
        subtitle: 'السماح بالتذكيرات والتنبيهات',
        value: 'من إعدادات الجهاز',
      ),
      _SettingsTile(
        icon: Icons.tune,
        title: 'المظهر فوق التطبيقات',
        subtitle: 'قد يلزم للتنبيهات الذكية على Android',
        value: 'حسب النظام',
      ),
      _SectionTitle('حماية بياناتك'),
      _SettingsTile(
        icon: Icons.lock_outline,
        title: 'بيانات الحساب والمزامنة',
        subtitle: 'تطبيق سياسة الخصوصية المعتمدة',
        value: 'عرض المعلومات',
      ),
      _SettingsTile(
        icon: Icons.shield_outlined,
        title: 'سياسة الخصوصية',
        subtitle: 'الاطلاع على حقوقك وطريقة استخدام البيانات',
        value: 'فتح السياسة',
      ),
      _SettingsTile(
        icon: Icons.storage_outlined,
        title: 'بيانات الضيف',
        subtitle: 'تخزن محلياً ما لم تسجل الدخول',
        value: 'عرض التفاصيل',
      ),
      _NoticeBox(
        'إدارة الصلاحيات',
        'حالات السماح الفعلية تُقرأ من نظام الجهاز، وليس من شكل هذا التصميم التوضيحي.',
      ),
    ],
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
                  () => setState(() => _hijriOffset--),
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
                _CircleAction(Icons.add, () => setState(() => _hijriOffset++)),
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
        onTap: () => setState(() => _hijriOffset = 0),
      ),
      _SectionTitle('تطبيق التصحيح'),
      _switchTile(
        'correctHijri',
        'استخدام التاريخ المصحح',
        'في التاريخ الهجري المعروض داخل التطبيق',
        Icons.calendar_month_outlined,
      ),
      _PrimaryButton('حفظ تصحيح التاريخ', Icons.check),
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
          left: 0,
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
    child: child,
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
