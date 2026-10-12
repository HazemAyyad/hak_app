# تطبيق حق

تطبيق Flutter عربي باتجاه RTL للمحتوى الديني وخدمات جمعية حق.

## المظهر

`AppAppearance` هو مصدر إعدادات المظهر وحجم الخط لجميع المسارات. تُحفظ التفضيلات محلياً عبر `shared_preferences`. الوضع التلقائي يتبع `ThemeMode.system` ويتحدث عند تغيير مظهر الجهاز.

عند إضافة صفحة، استخدم `Theme.of(context)` و`AppPalette.of(context)` لألوان الخلفيات والبطاقات والنصوص والحدود. احتفظ بالألوان الثابتة فقط لعناصر الهوية والأيقونات والنصوص فوق الصور أو الأزرار الملونة. لا تنشئ حالة مستقلة للمظهر داخل الصفحة.

افتح إعدادات المظهر من المزيد ← الإعدادات ← المظهر وإعدادات العرض، أو من المزيد ← مظهر التطبيق.

الصفحات الفرعية الأخرى تنفذ التصميم حالياً؛ ربط الحساب والإشعارات والصلاحيات والتحميل بخدماتها الفعلية مرحلة لاحقة.

## القرآن الكريم

تتضمن الدفعة الأولى القراءة دون إنترنت والبحث وفهرس السور والأجزاء والمفضلة والعلامات وحفظ موضع القراءة. بقي شريط التنقل الأصلي كما هو.

راجع [حالة التنفيذ وحدود التحقق](docs/quran-implementation-status.md)، و[الخطة](docs/quran-implementation-plan.md)، و[مصادر الصور والخطوط](docs/quran-assets.md). النص والفهارس ومصادرها وإشعارات الحقوق في `tool/quran_sources/`.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
