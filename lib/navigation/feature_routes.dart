import 'package:flutter/material.dart';

/// Stable destinations shared by the directory, home shortcuts and section tabs.
/// Planned services have an explicit unavailable route until their own stage.
enum AppFeature {
  religiousLibrary(
    'الأدعية والمحتوى الديني',
    Icons.front_hand_outlined,
    ready: true,
  ),
  duaTogether('ادعُ معي', Icons.people_alt_outlined),
  circles('حلقات الذكر', Icons.auto_awesome_outlined),
  settings('الإعدادات', Icons.settings_outlined, ready: true),
  tasbih(
    'المسبحة الإلكترونية',
    Icons.radio_button_checked,
    subtitle: 'المسبحة الإلكترونية لذكرك الدائم',
    image: 'beads',
    ready: true,
  ),
  names(
    'أسماء الله الحسنى',
    Icons.brightness_7_outlined,
    category: 'names',
    ready: true,
    image: 'names',
  ),
  feelings(
    'بماذا تشعر؟',
    Icons.favorite_border,
    category: 'feelings',
    ready: true,
    subtitle: 'دعمك النفسي والروحي',
    image: 'hands',
  ),
  adhkar(
    'أذكار المسلم',
    Icons.eco_outlined,
    subtitle: 'أذكار من الكتاب والسنة',
    image: 'beads',
    ready: true,
  ),
  statistics('إحصائيات', Icons.query_stats_outlined, ready: true),
  personalAdhkar(
    'أذكاري',
    Icons.edit_note_outlined,
    category: 'personal-adhkar',
    ready: true,
  ),
  quran(
    'القرآن الكريم',
    Icons.menu_book_outlined,
    ready: true,
    subtitle: 'تلاوة واستماع وتفسير',
    image: 'quran',
  ),
  qibla('بوصلة القبلة', Icons.explore_outlined),
  habits('متعقب العادة', Icons.fact_check_outlined, ready: true),
  ruqya(
    'الرقية الشرعية',
    Icons.health_and_safety_outlined,
    category: 'ruqya',
    ready: true,
    image: 'ruqya',
  ),
  istighfar(
    'استغفار',
    Icons.self_improvement_outlined,
    category: 'istighfar',
    ready: true,
  ),
  praise('الحمد', Icons.front_hand_outlined, category: 'praise', ready: true),
  glorification(
    'تسبيح',
    Icons.radio_button_checked,
    category: 'glorification',
    ready: true,
  ),
  nawawi(
    'الأربعون النووية',
    Icons.book_outlined,
    category: 'nawawi',
    ready: true,
    image: 'books',
  ),
  prophets(
    'أدعية الأنبياء',
    Icons.self_improvement_outlined,
    category: 'prophets',
    ready: true,
  ),
  propheticDuas(
    'أدعية نبوية',
    Icons.volunteer_activism_outlined,
    category: 'prophetic-duas',
    ready: true,
    image: 'prophetic',
  ),
  quranDuas(
    'أدعية قرآنية',
    Icons.auto_stories_outlined,
    category: 'quran-duas',
    ready: true,
    image: 'quran',
  ),
  khatma(
    'الختمة',
    Icons.menu_book_rounded,
    subtitle: 'متابعة ختمة القرآن الكريم',
    image: 'kaaba',
    ready: true,
  ),
  friday(
    'سنن الجمعة',
    Icons.groups_outlined,
    category: 'friday',
    ready: true,
    image: 'minbar',
  ),
  ramadan('رمضان', Icons.nightlight_outlined, category: 'ramadan', ready: true),
  sunnah(
    'سنن النبي ﷺ',
    Icons.import_contacts_outlined,
    category: 'sunnah',
    ready: true,
    image: 'madina',
  ),
  appearance('مظهر التطبيق', Icons.palette_outlined, ready: true),
  sakinah(
    'سكينة',
    Icons.air_outlined,
    subtitle: 'تمارين التنفس والطمأنينة',
    image: 'sakinah',
    ready: true,
  ),
  hadith(
    'الأحاديث النبوية',
    Icons.menu_book_outlined,
    category: 'hadith',
    ready: true,
  ),
  mosques('أقرب المساجد', Icons.mosque_outlined),
  ourApps('تطبيقاتنا', Icons.account_balance_outlined);

  const AppFeature(
    this.title,
    this.icon, {
    this.category,
    this.ready = false,
    this.subtitle,
    this.image,
  });
  final String title;
  final IconData icon;
  final String? category, subtitle, image;
  final bool ready;

  String get routeName => '/services/$name';
  String? get imageAsset => image == null
      ? null
      : image == 'sakinah'
      ? 'assets/navigation/sakinah.png'
      : 'assets/religious/$image.png';

  static const featured = [quran, adhkar, khatma, tasbih, sakinah, feelings];
}
