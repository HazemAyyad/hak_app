# الرئيسية وخيارات الخط

المرجع: الصورة المرفقة التي تجمع الوضع الفاتح والداكن. تنفيذ البطاقات والنصوص والأزرار Flutter فعلي في `lib/home_widgets.dart`، وتبقى متابعة القراءة مرتبطة بموضع القرآن المحفوظ. لا تُضاف آية 255 كقراءة وهمية للمستخدم الجديد؛ تظهر في لقطات الاختبار لأنها بيانات اختبار محفوظة.

الخط الافتراضي القاهرة Cairo، مع تجوال Tajawal وخط الجهاز في المزيد ← الإعدادات ← المظهر وإعدادات العرض ← نوع الخط. الخطوط العربية ملفات محلية، والتفضيل يحفظ عبر SharedPreferences. يستخدم نص القرآن Amiri Quran مستقلًا عن خط الواجهة للحفاظ على الحركات. اسم الخط الأصلي غير معطى في المرجع؛ القاهرة اختيار بصري قريب، وليس إثباتًا أن الملف الأصلي يستخدم هذا الخط.

الصور الناتجة من تشغيل Flutter في الاختبارات: `build/home-preview/light.png` و`build/home-preview/dark.png`. المراجعة تشمل ترتيب الأقسام والمحتوى والألوان والمسافات؛ الخلفيات مشتقة مولدة وليست ضمان تطابق كل بكسل. اختبار عرض 320 بكسل مع حجم خط 120% يغطي القاهرة وتجوال في الوضعين.

## الصور

استُخدمت أداة image_gen المدمجة بمهارة imagegen. الملفات المختارة نُسخت إلى المشروع، ولم تُستبدل الأصول القديمة:

- `assets/home/header_light.png`
- `assets/home/header_dark.png`
- `assets/home/reading.png`
- `assets/home/dawn.png`
- `assets/home/lantern.png`

التعليمات المرسلة للأداة، باستخدام الصورة المرفقة كهدف تحرير:

### الخلفية الفاتحة

> Use case precise-object-edit. Edit target supplied app screenshot. Extract and reconstruct ONLY the top LIGHT MODE header background from the LEFT phone (top x0-412, y0-260). Output standalone landscape background about 1.55:1. Precisely retain thin gold outlined teal ornamental arch along top and sides, pale cream cloudy blue sky inside arch, mosque with minarets and dome at bottom LEFT, foliage lower left. Preserve scene and composition closely. Remove ALL logo, Arabic text, status time battery, notification/search/profile circular buttons. Inpaint UI to underlying scene. No text or logos or icons or phone borders. Right lower region should stay light cream suitable for navy Arabic greeting, center upper region empty for app logo. This is a reusable Flutter asset, NOT a screenshot. Do not add objects or reinterpret style.

### الخلفية الداكنة

> Use case precise-object-edit. Edit target supplied screenshot. Extract and reconstruct ONLY top DARK MODE header background from RIGHT phone (x427-837 y0-260). Output standalone landscape 1.55:1 background. Match original scene closely: gold thin outlined dark teal ornamental arch top and sides, deep navy cloudy night sky, warm golden illuminated mosque dome and minarets LOWER LEFT with foliage, small golden crescent upper right of center. Remove ALL logo, Arabic text, status time battery, circular buttons, cards. Inpaint to underlying scene. Dark right lower region empty for white greeting, center upper empty for app logo. No text symbols icons phone borders. Do not invent new objects. Background only for Flutter.

### متابعة القراءة

> Use case precise-object-edit. Edit target is provided screenshot. Extract only background photograph from the 'continue reading' Quran card, RIGHT phone x442-822 y878-1040. Reconstruct a standalone 2.25:1 landscape image: closed ornately embossed golden brown Quran tilted on a dark wooden reading stand on the lower LEFT, warmly lit hanging lanterns and bokeh upper left, wooden table foreground, dark navy teal empty area on the RIGHT for Flutter text. Exact source subject and lighting, composition: book occupies left 48%, right remains empty. Remove ALL text icons buttons progressbars borders and phone UI, inpaint beneath them. No symbols/text/logos anywhere, no UI. Photographic premium Islamic scene faithful to reference, do not substitute open Quran.

### أذكار الصباح

> Use case precise-object-edit. Reconstruct ONLY photograph background of MORNING ADHKAR card in RIGHT phone (x442-822 y680-860), standalone landscape 2.1:1. Preserve precisely source scene: small warm sun rising at upper LEFT above layered misty mountain ridges, beautiful mosque dome and minaret and cypress trees lower LEFT, deep blue teal sky RIGHT 55% empty. Warm dawn muted orange pale golden light on left, navy teal on right. No lanterns, no additional buildings or objects. REMOVE ALL Arabic text, sun icon, share circle, buttons, borders; inpaint only UI. Reusable photograph asset, NOT app screenshot. Match scene composition and light, no text/icons/logos/UI.

### مقالة الصدقة

> Use case precise-object-edit. Extract and reconstruct ONLY photograph background of charity ARTICLE thumbnail in screenshot lower LEFT x22-221 y1645-1745 (also dark version x445-650). Standalone landscape 1.85:1. Faithful source: ornate brass lantern emitting warm amber glow at LEFT, dark warm brown gold bokeh leafy background, blurred old wooden surface. Right half dark and empty for Flutter title. Remove ALL Arabic text and gold article tag, UI, rounded borders, phone. No text logos buttons symbols. Do not add Quran or mosque. Background photograph only faithful to source.

تجوال من مستودع [Google Fonts الرسمي](https://github.com/google/fonts/tree/main/ofl/tajawal)، مع الرخصة المحلية `assets/fonts/Tajawal-OFL.txt`. القاهرة وAmiri موجودان سابقًا مع رخصهما.

بطاقات الصلاة والتقدم اليومي تستبقي بيانات العرض الموجودة في النموذج؛ لم يُضف في هذه المهمة حساب مواقيت حي أو ربط خدمات جديدة. زر التفسير يوضح عدم توفر المصدر المعتمد بدل إنشاء تفسير غير موثق. بعض خدمات الأذكار والمقالات كانت واجهات فقط وما زالت تتطلب تنفيذ وظائفها ضمن مهمة منفصلة.
