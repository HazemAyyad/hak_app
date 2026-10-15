# تنفيذ الأدعية والمحتوى الديني

مرجع الشكل والسلوك هو مجلد `F:\laragon\www\جمعية حق\جمعية حق\الأدعية والمحتوى الديني` وصوره التسع عشرة ووثيقة الفلو. التنفيذ واجهات Flutter تفاعلية، مع API وإدارة محتوى ومزامنة في Laravel. لا تُستخدم صورة شاشة كاملة مكان الواجهة.

## نطاق التنفيذ

- الأقسام السبعة: الأدعية القرآنية والنبوية، سنن النبي، سنن الجمعة، الأربعون النووية، الرقية الشرعية، والأسماء الحسنى.
- 310 سجلات محتوى و22 قسمًا وتصنيفًا؛ بينها 42 حديثًا و99 اسمًا. العدد المعروض يأتي من البيانات، ولا تُستخدم الأعداد التجريبية في التصاميم.
- رئيسية القسم، القوائم والتصنيفات والبحث العربي دون تشكيل، فلاتر الموضوع والمفضلة، التفاصيل، النسخ والمشاركة مع المصدر، أذكاري وقائمة الاستماع.
- المداخل من الرئيسية والمزيد واختصار الجمعة، مع مداخل مباشرة للمحتوى الشخصي والأدعية حسب الحالة. صفحة المواضيع تستخدم نصوص الكتالوج نفسه؛ لا تنشئ أدعية جديدة.
- رجوع يحافظ على البحث والفلتر والتمرير، ورجوع النظام من جذر الوحدة إلى المزيد. يبقى ترتيب التبويبات الحالي للتطبيق كما تقرر في تنفيذ القرآن، مع لوحة ألوان القسم أثناء عرضه.
- القراءة والبحث والمحفوظات المحلية دون إنترنت. نسخة محتوى من Laravel تُفحص بإصدار وبصمة SHA256 قبل استبدال النسخة المحلية؛ فشل الشبكة لا يمنع القراءة.
- الآيات ترتبط بمعرفاتها مثل `2:201` من ملف القرآن نفسه. فتح المصحف والتفسير يستخدم الوحدة الحالية ويحافظ على طريق الرجوع.
- قراءة الرقية والاستماع والمعلومات، وقائمة استماع شخصية، وتنزيل مع الإيقاف وإعادة المحاولة والإزالة، وسرعة ومؤقت نوم واستئناف موضع المقطع.

## المحتوى والمصادر

نصوص الآيات مطابقة حرفيًا لنسخة القرآن الموجودة بالتطبيق. البيانات الأصلية للأدعية والأحاديث والأسماء محفوظة في `tool/religious_sources/`، ويعيد `tool/build_religious_catalog.py` بناء نسخة Flutter ونسخة Laravel.

- القرآن: نسخة Tanzil الموجودة مسبقًا، مع إشعارها ومصادرها في وحدة القرآن.
- حصن المسلم: [الكتاب وموقعه](https://www.hisnmuslim.com/) و[النسخة الرقمية rn0x](https://github.com/rn0x/hisn_almuslim_json). التخريج الموجود في المصدر مرفق بالمحتوى، وليس مستخرجًا من الصورة.
- الأربعون النووية: [النسخة الرقمية والنص والشرح](https://github.com/osamayy/40-hadith-nawawi-db)، مع رقم الحديث ورابطه. لم يُعَد تأليف الشرح بالذكاء الاصطناعي.
- الأسماء: [قائمة AlAdhan](https://aladhan.com/asma-al-husna). المعاني العربية الموجزة صياغة عربية لمعاني المصدر الإنجليزية، ومميزة بهذا الوصف في بيانات المصدر؛ لا تُقدَّم باعتبارها تفسيرًا مطولًا معتمدًا. ترتيب هذه القائمة يتبع مصدرها، ويختلف عن المثال المصور الذي يبدأ بلفظ الجلالة.
- السنن المضافة: البخاري 735 و883 و881 و934 و935 و651، مسلم 844a و245 و881a، وأبو داود 1047 و345؛ يرافق كل نص رابطه وتخريجه.

الشاشات المصورة ليست مصدرًا شرعيًا. أضيفت الأربعون النووية للرئيسية وصُحح مثال رفع اليدين بحديث البخاري 735، مع إبقاء الوضوء سجلًا مستقلًا. اعتماد المحتوى للنشر العام ومراجعة معاني الأسماء والشروح يبقيان قرار صاحب المحتوى، ولا يثبتان بمجرد نجاح الاختبارات البرمجية.

الرقية الكاملة في هذه النسخة قائمة آيات مختارة، وليست التسجيل التجريبي في الصورة ذي 45:20. الآيات تُشغَّل بواسطة كتالوج التلاوات الحالي، ويُعرض القارئ والمدة من الملف الفعلي. دعاء الاستيقاظ مرتبط بتسجيله الأصلي من حصن المسلم. تظهر حالة واضحة للمواد التي لا يوجد لها تسجيل؛ لم تُخترع روابط أو مدد أو تسجيلات للأحاديث والأسماء.

## Laravel والإدارة

المسارات العامة تحت `/api/v1/religious`: `manifest` و`dataset` و`categories` و`content` و`content/{id}`. المزامنة تحت `POST /sync` وتستخدم حساب التطبيق الديني الحالي، مع منع حسابات موظفي الإدارة من استخدامها.

الإدارة تحت `/admin/religious-content`، ومحمية بـ`auth` ودور `superadmin`، ولها مدخل بالقائمة الجانبية. تشمل النص والمصدر والنشر والتصنيفات وترتيبها والأدلة والشروح والصوت. يمنع التحقق تعديل نص الآيات بما يخالف المرجع، ويمنع حلقات التصنيفات وروابط المحتوى غير الصالحة. لا يمكن إخفاء الأقسام الأساسية السبعة.

المحتوى الأساسي ملف مرفق في `resources/religious/catalog.json`. تعديلات الإدارة تُحفظ في `storage/app/religious/catalog.json` مع قفل وكتابة نسخة مؤقتة كاملة قبل الاستبدال. يجب الحفاظ على هذا المجلد في النسخ الاحتياطية والنشر، وإتاحة الكتابة له لخادم PHP. لا يتطلب استيراد المحتوى تعديل قاعدة البيانات.

المحفوظات وأذكاري وقائمة الاستماع وتقدم الصوت لها نطاق مستقل للضيف ولكل حساب. عند الدخول تُسحب نسخة الحساب أولًا ثم يُدمج حفظ الضيف مرة واحدة، مع احترام سجلات الحذف على الخادم. المزامنة تستخدم معرف عملية وإصدار خادم، وتختبر إعادة إرسال العملية والتعارض وعزل الحسابات.

مهاجرة المزامنة الجديدة هي `2026_10_15_000001_create_religious_content_sync.php`، وتأتي بعد مهاجرة الحساب الديني الموجودة. لم تُشغّل مهاجرات على قاعدة العمل أو السيرفر ضمن التنفيذ. يلزم نشر الملفات وتشغيل المهاجرة على السيرفر لتفعيل المزامنة هناك. النص المحلي يعمل قبل ذلك.

## الأصول والمطابقة البصرية

كل الأصول داخل `assets/religious/`. الصور الفوتوغرافية الصغيرة مستخرجة من مناطق الصور في المراجع نفسها. الخلفيات السبع أُعيد تجهيزها بأداة `image_gen` المدمجة عبر مهارة imagegen لإزالة النصوص وحالة الهاتف والأزرار؛ الملفات الأصلية المنفصلة وملف التصميم والخط الأصلي غير موجودة في المجلد المقدم.

تُولد لقطات Flutter عند 426×922، وتُحفظ في `build/religious-preview/D01…D19*.png`. الاختبارات تغطي كذلك عرض 320 مع تكبير 130% والوضعين الفاتح والداكن. اللقطات من Flutter لا تحتوي حالة الهاتف الأصلية أو شريط إيماءات النظام؛ ليست تسجيلًا من هاتف فعلي.

المراجعة البصرية تقارن التكوين والألوان والصور والمسافات والقوالب. لم يُثبَت تطابق كل بكسل بنسبة 100%؛ الخلفيات المعاد تجهيزها والخط والمحتوى المصحح وترتيب التبويبات الحالي اختلافات معلنة. لا يُستخدم نجاح الاختبارات كدليل على تطابق بصري حرفي أو على تشغيل الصوت على جهاز فعلي.

## تعليمات الصور المستخدمة

النمط: أداة `image_gen` المدمجة، مع الصور الأصلية كأهداف تحرير وبدون شفافية. النواتج النهائية المستهلكة في المشروع هي `header_home.png` و`header_ruqya.png` و`header_sunnah.png` و`header_quran.png` و`header_reading.png` و`header_medina.png` و`header_sleep.png` داخل `assets/religious/`.

### خلفية الرئيسية

> Use case: precise-object-edit. Edit target: supplied Arabic app screenshot. Output ONE standalone WIDE LANDSCAPE reusable HEADER BACKGROUND, approximately 2.15:1. Extract and reconstruct ONLY the top header area (original x0-853, y0-335). Preserve the EXACT original scene composition: ornate mosque courtyard, arches framing top, warm lantern and foliage on LEFT, mosque dome in center-left, tall slim minarets, palms, pale blue golden sunrise sky, wet reflective floor. Pale ivory-white mist across bottom RIGHT and right edge for dark text overlay. Remove ALL Arabic words, time, battery, network icons, buttons, cards and UI. Inpaint the areas covered by text/status symbols with the same underlying scene. No text, logos, UI or border. Match the original architecture, lighting and composition as closely as possible. Output only the rectangular photo background, not the screenshot or phone.

### خلفية الرقية

> Use case precise-object-edit. Edit target supplied app screenshot. Extract/reconstruct ONLY HEADER PHOTO from x0-851 y0-396 as one standalone wide rectangular photograph approximately 2.15:1. Preserve original photograph exactly: warm glowing brass hanging lantern on LEFT, closed richly decorated Quran on stand lower LEFT, patterned carpet, stone arches and carved sunlit window at center, dark deep green gradient RIGHT 45% for white text. Remove only all status bar time/battery/network symbols, Arabic words, share/bookmark/back buttons and UI. Inpaint matching underlying background. No text, calligraphy, logos, controls, frame or phone. Keep original book, lighting, positioning and architecture; do not substitute an open book. Output only clean reusable landscape header photo.

### خلفية السنن

> Use case precise-object-edit. Extract/reconstruct ONLY top HEADER PHOTOGRAPH from supplied screenshot (x0-853 y0-391). ONE reusable rectangular LANDSCAPE header about 2.15:1. Match exactly original: large mosque hall with elaborate cream stone arches LEFT and center, warm sunbeams, bright ornate hanging chandelier center-upper, OPEN Quran on wooden stand lower LEFT on green patterned carpet, deep emerald teal dark gradient on RIGHT 40%. REMOVE all time/status icons, back/bookmark/share buttons, Arabic title and subtitle, and UI below. Inpaint only removed UI keeping architecture, carpet, chandelier, Quran positioning, original lighting and warm color palette. No new objects, writing, logos, symbols, controls, phone or border. Output only clean photo background.

### خلفية الدعاء القرآني

> Use case precise-object-edit. Edit target supplied Arabic app screenshot. Extract and reconstruct ONLY HEADER BACKGROUND (x0-853 y0-435) as ONE wide landscape rectangular photo roughly 2:1. Keep EXACT original arch and composition: ornate deep green arabesque wall and arch, golden carved stone arch on LEFT, mosque minaret and green dome in background through arch, foliage left foreground, hanging golden glowing lantern just left of center. RIGHT 60% must remain deep dark emerald patterned wall suitable for white Flutter title. Remove all time, battery, network status, white circle buttons, Arabic title/subtitle/reference pill, decorative UI line, and phone UI. Inpaint underneath removed elements, preserve architecture texture light and original color composition closely. No text/logos/buttons/controls/phone border. Output only clean background photo.

### خلفيات القراءة والقوائم والاستيقاظ

أُعيد تجهيز ثلاث خلفيات مستقلة من مراجعها مع إزالة كل النصوص والأزرار وأيقونات الهاتف، والحفاظ على التكوين والضوء:

- القراءة: مصحف مفتوح على حامل وفانوس يسارًا، ونافذة مزخرفة مضاءة وسطًا، ومساحة خضراء داكنة يمينًا.
- قوائم الأدعية: مسجد ومآذن ونخيل عند الغروب، وفانوس وقوس يسارًا، وتدرج عاجي يمينًا للعناوين الداكنة.
- الاستيقاظ: سرير يسارًا وفانوس مضاء في الوسط وكتب مزخرفة يمينًا، مع مساحة مظلمة لعنوان الصفحة.

حجم القراءة محفوظ لكل نوع مادة بصورة مستقلة؛ يبدأ الحديث بخط أصغر من الدعاء الطويل ويظل قابلًا للتكبير. تخريج الحديث الأول الطويل محفوظ في قسم مستقل دون حذفه من البيانات.

## التحقق

أوامر التحقق المستخدمة، مع النتائج النهائية في سجلات `build/religious-*.log`:

```text
flutter analyze --no-pub
flutter test --no-pub --timeout=120s
flutter test --no-pub --dart-define=RELIGIOUS_PREVIEWS=true test/religious_content_test.dart
flutter build apk --debug --no-pub
php artisan test --compact --filter=ReligiousContentTest|QuranApiTest|QuranContentTest|QuranSync
git diff --check
```

اختبارات المزامنة الجديدة تستخدم اتصال SQLite مستقلًا اسمه `religious_testing` بقاعدة `:memory:` فقط؛ لا تُستورد بيانات ولا تُشغّل مهاجرات في قاعدة العمل. فحص الصوت والتنزيل على هاتف فعلي ونشر Laravel على السيرفر يظلان تحققين منفصلين عن التحليل والاختبارات والبناء المحلي.

نتيجة التحقق بتاريخ 15 أكتوبر 2026: التحليل النهائي دون ملاحظات، المجموعة الكاملة 73 اختبار Flutter ناجحًا، وأعيدت اختبارات القسم الثمانية بعد ضبط الخط والخلفيات بعرض 320 و426 والوضعين. اختبارات Laravel المرتبطة بالقسم والقرآن 23 ناجحة مع 126 تحققًا. بناء Android التجريبي النهائي نجح؛ الملف في `build/app/outputs/flutter-apk/app-debug.apk`. بصمة ملف الكتالوج المرفق متطابقة بين المشروعين. التغييرات محلية ولم يُنشر السيرفر أو تُشغّل مهاجرة قاعدة العمل.
