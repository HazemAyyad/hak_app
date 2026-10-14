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
