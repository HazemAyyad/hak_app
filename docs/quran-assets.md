# أصول شاشات القرآن

استُخدمت أداة `image_gen` المدمجة لإنتاج ثلاث خلفيات وصورة غلاف مشتقة من مرجع التصميم، مع إزالة النصوص والأزرار. الصور لا تُستخدم كشاشات كاملة؛ العناوين والأزرار والقوائم وعناصر القراءة Flutter فعلية. بقيت ملفات المرجع الأصلية دون تعديل.

## الخلفية الفاتحة

الملف المستخدم: `assets/quran/header_light.png`.

مرجع التحرير: `كل السور.png` في مجلد التصميم. النص المرسل إلى الأداة:

> Use case: precise-object-edit. Asset type: reusable Flutter Quran section header background. Edit target is the provided full app screenshot. Extract ONLY its top mosque/open-Quran header region, excluding all white list UI below it. Output a wide landscape header approximately 3.1:1. Preserve the original mosque, open Quran on wooden stand on the lower LEFT, gold outlined teal ornamental arch frame at both upper sides, soft cream light and blurry mosque interior on the RIGHT. Exact matching of source scene is essential; do not redesign or add objects. REMOVE and inpaint only all Arabic title and subtitle, status bar/time/battery, white circular navigation buttons and icons. No text, no symbols, no UI, no white cards, no bottom navigation. Keep the original light cream empty space on the RIGHT for programmatically rendered dark navy text. The output must be the reusable background image only, no mockup or phone frame.

## الخلفية الداكنة

الملف المستخدم: `assets/quran/header_dark.png`.

مرجع التحرير: `فهرس الأجزاء الثلاثين.png` في مجلد التصميم. النص المرسل إلى الأداة:

> Use case: precise-object-edit. Extract ONLY the top decorative header scene from the provided screenshot as a reusable background asset. Output wide landscape 2.4:1. Keep precisely the source scene: open Quran on wooden stand at lower LEFT, glowing warm gold mosque columns and chandeliers in the center-left, dark emerald/teal empty area on the RIGHT, greenery on the far left, ornate carved mosque in the background. Remove status bar/time/battery, all Arabic text, all circular buttons and icons, and all white panel/list UI below the scene. Inpaint only the UI areas to the underlying scene, preserve objects/light/color/composition. No phone frame, no text, no icons, no UI, no additional objects. This is a background asset only, not a new screen design. Source scene fidelity is essential.

## الخطوط والزخارف

الخلفية المركزية: `assets/quran/header_home.png`، من مرجع `السور.png`، بالنص:

> Use case: precise-object-edit. Asset type: home header background for this exact Quran app. Extract only the TOP hero scene above the white search field of this screenshot as a clean wide 2.15:1 landscape image. Preserve its teal and thin gold ornamental mosque arches at BOTH edges, soft sunlit cream mosque interior, and the open Quran on a wooden stand in the LOWER CENTER. This source differs from the Surah-list header: book must stay centered and low so Arabic title can be rendered above it. REMOVE/inpaint all text, subtitle, status bar, time, battery, icons and circular buttons; remove the search box and all app content below the hero. Preserve the source composition, lighting, patterns and objects, do not redesign. No text, no UI, no mockup or phone frame. Background asset only.

صورة الغلاف: `assets/quran/quran_cover.png`، من المرجع نفسه، بالنص:

> Use case: background-extraction. Extract ONLY the closed Quran book thumbnail from the LEFT side of the 'آخر قراءة' white card in the supplied screenshot (the upright deep teal/blue closed book with ornate thin gold floral borders and central gold medallion, approximately x70-220 y535-710 in the source). Do not extract the open Quran in the top header. Output a clean isolated upright closed book cutout with genuinely transparent background, tall portrait aspect ratio approximately 0.65:1. Preserve the photographed cover, original navy/teal and gold colors, book proportions, slight perspective and ornament details exactly. No white card, no app text, no additional objects, no border or phone frame.

- خط واجهات القسم Cairo من [Google Fonts](https://github.com/google/fonts/tree/main/ofl/cairo)، محفوظ في `assets/fonts/Cairo.ttf` مع رخصة OFL.
- نص القرآن بخط Amiri Quran من [مستودع Amiri الرسمي](https://github.com/aliftype/amiri)، محفوظ في `assets/fonts/AmiriQuran.ttf` مع رخصة OFL.
- زخرفة رقم السورة والآية مرسومة بـ Flutter CustomPainter؛ لم تُنسخ أرقام الصور أو نصوصها.

الخطوط والزخارف والخلفيات تحتاج مراجعة واعتماد بصري مقابل المرجع؛ التشابه لا يُعد إثبات تطابق بكسلات. صور المقارنة الناتجة من تشغيل الواجهات تُحفظ في `build/quran-preview/`.

## مصادر المحتوى والصوت المضافة في الدفعة الثانية

- QCF V4 الملوّن: [دليل توزيع الصفحات](https://api-docs.quran.com/docs/tutorials/fonts/page-layout/)، [دليل الخطوط](https://api-docs.quran.com/docs/tutorials/fonts/font-rendering/). كل صفحة تُطلب بخطها من `https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/ttf/p{page}.ttf`. خطوط المصدر تحتوي COLRv0 وCPAL ولا تُلوّن الكلمات يدويًا. تُحمّل الخطوط مؤقتًا في ذاكرة الجلسة ولا تُحفظ داخل التطبيق. بيانات الكلمات تستخدم `mushaf=19` و`code_v2`. ملكية الخط لمجمع الملك فهد؛ لا تُعدّل ملفات الخط ولا تُحزّم جميع الخطوط في التطبيق. بيانات الكلمات الأصلية تحمل رقم الصفحة والسطر، وتُجمع الكلمات على مستوى السطر مع استبعاد كلمات الصفحة الأخرى.
- تفاسير Quran.com: السعدي 91، الطبري 15، ابن كثير 14، القرطبي 90. تُخزّن استجابة المصدر الأصلية، مع HTML ونطاق الآيات؛ العرض يزيل وسوم التنسيق فقط. لا يوجد نص تفسير مُولّد.
- معاني الكلمات: [QuranEnc API](https://quranenc.com/en/home/api)، `arabic_seraj`، «السراج في بيان غريب القرآن». تُخزّن الاستجابة وfootnotes كما هي. رقم corpus مستقل غير معلن في استجابة هذا المسار؛ الإسناد يذكر API v1 ورابط المصدر وتاريخ الاسترجاع ولا يخترع رقم نسخة.
- السور الصوتية: [MP3Quran API](https://www.mp3quran.net/ar/api)، كتالوج حفص `language=ar&rewaya=1`، snapshot بتاريخ 2026-10-13 في `assets/quran/audio_catalog.json`. [سياسة إتاحة المادة والربط](https://apiquran.mp3quran.net/ar/privacy). أسماء القراء وأرقام المصاحف وقائمة السور والسيرفر مأخوذة من API، بما فيها CDN الجديد؛ لا يُفترض توافر 114 سورة لكل قارئ.
- ملفات الآيات: [EveryAyah recitations](https://everyayah.com/data/recitations.js). العفاسي `Alafasy_128kbps`، السديس `Abdurrahmaan_As-Sudais_192kbps`، عبد الباسط `Abdul_Basit_Murattal_192kbps`، المعيقلي `MaherAlMuaiqly128kbps`. ملفات الآيات مستقلة عن ملفات سور MP3Quran، ولا يُربط توقيتها بالسورة من مصدر مختلف.
- نطق الكلمة: `audio_url` من استجابة كلمات Quran.com، ويُحل فقط ضمن `https://audio.qurancdn.com/wbw/`.
- صور القراء روابط مصدرية من صفحات [العفاسي](https://quran.com/reciters/7)، [السديس](https://quran.com/reciters/3)، [عبد الباسط](https://quran.com/reciters/1)، [الغامدي](https://quran.com/reciters/13). روابط الصور واسم الشخص تحققت من `alt` في الصفحة. لم تُستخدم صور مولّدة للقراء ولم تُعدّل الوجوه. تظهر أيقونة عند عدم إتاحة الصورة.

شاشة اختبار المصحف تستخدم استجابة صفحة 2 الأصلية في `test/fixtures/quran/page2.json`. خطوط الاختبار البصري المحملة في `build/quran-fixtures` محلية ومهملة من Git. نص القرآن الأساسي بقي بنفس البصمة المعتمدة.

## إطار المصحف وتحسين الخلفية — 14 أكتوبر 2026

استُخدمت أداة `image_gen` المدمجة لتحسين `assets/quran/header_light.png` من المرجع نفسه، وإنتاج `assets/quran/mushaf_frame.png` من `عرض سور القران الكريم  _ 3.png`. بقيت الصور المرجعية دون تغيير. إطار المصحف PNG بخلفية شفافة حول الزخرفة وداخل متن القراءة وعنوان السورة؛ لم يُرسم أي نص قرآني داخل الأصل النقطي.

تعليمات الإطار:

> Use case: background-extraction. Extract the ornate Mushaf page frame and blank Surah title cartouche from the supplied approved Quran reader screenshot. Preserve the dense forest-green, rust-red, gold and cream floral ornament, exact rectangular page composition and corner decorations. Remove all scripture, verse medallions, Surah name, app controls, header and player. Produce only the reusable ornamental frame, portrait 1024x1536, with genuinely transparent outside margins, page center and title cartouche. No Quran text, no numbers, no UI, no phone frame, no invented objects. Flutter will render every word and title as live text.

الخلفية الفاتحة 2048×683، والإطار 1024×1536؛ العرض يضبطهما ضمن قياسات الشاشة. الشفافية تحققت من قناة alpha ثم من لقطة Flutter. ملف الخط الأصلي للاختبار موجود مؤقتًا في `build/quran-fixtures/v4-p2.ttf` ولا يُضم إلى Git أو أصول التطبيق. تُعرض إشعارات Tanzil وQuran Foundation داخل القسم، وتبقى مشاركة الآية مقتصرة على النص ومرجعه.

سياسة المحتوى: تخزين استجابات JSON العادية سبعة أيام فقط، مع إزالة القديم واستبعاد الاستجابات المنتهية من البحث المحفوظ. تحميل خطوط الجلسة من CDN يطابق مسار العرض وقت التشغيل في دليل المصدر؛ لا يشكّل هذا توثيقًا لحق تحزيم أو تخزين دائم للخطوط.

## صفحات المصحف المحفوظة — 14 أكتوبر 2026

تنزيل الصور يستخدم رسومات SVG الأصلية لمصحف المدينة برواية حفص من مجمع الملك فهد، عبر [Quran.ws quran-svg](https://github.com/quran-ws/quran-svg). النسخة v1.1.1 مثبتة على commit `3ff27b46cecb0c0519d77531d9c868a579d1f623` في مسار `mushafs/hafs/kfqc`. هذه صور أحادية اللون، مستقلة عن خطوط QCF الملوّنة المؤقتة. لا تُحزّم الصفحات الـ604 في التطبيق؛ تُنزّل السورة أو المصحف باختيار المستخدم.

يُنزل كل ملف SVG مع JSON الأصلي الذي يحدد مناطق الآيات. يظهر الرسم نفسه دون طلب خط أو API عند غياب الشبكة، ويظل اختيار الآية والنسخ والتفسير مرتبطًا بمعرف الآية المحلي. الملفات الأصلية محفوظة دون تعديل؛ قص المساحات الفارغة في صفحتي الافتتاح والتلوين للمظهر يتمان وقت العرض. الأصول تخضع للتحقق من الحجم وبصمة Git blob المثبتة، وبصمة SHA256 المحلية عند الاستعادة والقراءة. الاستئناف يقبل فقط استجابة `206` بنطاق مطابق؛ استجابة `200` تعيد الملف من البداية.

شروط المصدر محفوظة كما وردت في `assets/quran/offline-page-LICENSE.txt` و`assets/quran/offline-page-NOTICE.md`. ترخيص CC BY 4.0 يغطي بيانات Quran.ws ومناطق الضغط؛ ملكية الرسوم تبقى للمجمع وتخضع لشروطه المبينة في NOTICE. نموذج الصفحة الأولى في الاختبارات يحفظ المصدر الأصلي مع الإسناد في `test/fixtures/quran/README.md`.
