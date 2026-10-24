# تنفيذ خطة حق — 2026-10-24

## قواعد التنفيذ

- نسخة Flutter المعتمدة: `C:\flutter_projects\haq_app`؛ الباك: `C:\laragon\www\haq-foundation`.
- المرجع الوظيفي: توثيق أذكاري، والمرجع البصري: هوية حق والتصاميم المعتمدة. الرئيسية تبقى بتصميمها الحالي.
- الحفاظ على القرآن والقارئ والمشغل والتنزيلات وتفاصيل المحتوى الديني الحالية؛ لا استبدال تصميم قائم دون قرار صريح عند وجود اختلاف غير محسوم.
- إكمال الموجود وإعادة استخدام الحالة والمشغل. لا محاكاة نجاح حساب أو موقع أو اشتراك أو مزامنة غير منفذة.
- كوميت مستقل لكل مرحلة مكتملة في كل مستودع تغيّر. لا تضمين تعديلات سابقة ضمن كوميت المرحلة.
- بطلب المستخدم: لا `flutter run` ولا بناء APK أثناء التنفيذ الحالي. التحقق بالتحليل والاختبارات المعزولة؛ دليل الجهاز والإصدار يبقى مؤجلًا.

## P00 — خط الأساس

بداية Flutter: `0251f262967f86ef47d31ac15b4cb90bfe1b4f91`.
بداية Laravel: `13cde775857c1fd19ad69300e99f4310587cb55a`.

التعديلات السابقة التي تُحفظ خارج كوميتاتنا: `assets/fonts/Cairo-OFL.txt` و`assets/fonts/Tajawal-OFL.txt` و`tool/quran_sources/quran-metadata.xml` و`docs/multilingual-implementation-plan.md`.

أُعيد توليد إعداد الحزم من نسخة C بدل مسارات مستخدم hp المفقودة. احتاج SDK المثبت تغيير أربع تبعيات انتقالية فقط: matcher إلى 0.12.20، meta إلى 1.19.0، test_api إلى 0.7.12، vector_math إلى 2.4.3. لم يُشغّل upgrade عام. أضاف Flutter استثناء مجلدات البناء والمنصات إلى إعداد التحليل تلقائيًا.

صُحّح اقتران مفتاح `UIApplicationSupportsIndirectInputEvents` بقيمته في `Info.plist` مع إبقاء وضع الصوت في الخلفية. أداة `tool/check_platform_config.py` تفحص XML وplist دون تشغيل أو بناء التطبيق.

نتيجة Flutter: تحليل نظيف، و73 اختبارًا ناجحًا عبر ملفات الاختبار الأربعة عشر (شُغّلت بمجموعات)، وفحص 17 ملف XML/plist. ظهرت أربعة إخفاقات في اختبارات الإعدادات بسبب تحقق ListTile الجديد؛ عولجت بطبقة Material شفافة داخل البطاقة، وأعيدت اختبارات الإعدادات السبعة ونجحت. لا تغيير على أبعاد البطاقة أو ألوانها.

على Windows لم تنجح محاولة تحميل مكتبة Rive من مسار debug؛ نجحت اختبارات البداية الستة عند إتاحة مكتبة release الموجودة عبر PATH للعملية وحدها. لم يُعد بناء Rive أو التطبيق. مخرجات اختبارات الواجهات آلية، وليست إثبات تشغيل على هاتف أو iOS.

تأكد تطابق ملفات الخطوط الثنائية مع HEAD، وعدم تغيير مصادر الرئيسية والقرآن والمحتوى الديني وبدء التشغيل ضمن المرحلة. تُغلق P00 بعد اكتمال فحص الباك أيضًا؛ المراحل P01–P13 لم تُنفذ ضمن هذا التغيير.

### أوامر التحقق دون تشغيل أو APK

من جذر Flutter، باستخدام SDK الحالي:

```powershell
flutter pub get --enforce-lockfile
python tool/check_platform_config.py
flutter analyze --no-pub
flutter test --no-pub test/quran_account_test.dart test/quran_sync_test.dart test/quran_downloads_test.dart test/quran_page_downloads_test.dart test/quran_audio_handler_test.dart test/quran_media_test.dart test/quran_content_test.dart --reporter expanded
flutter test --no-pub test/widget_test.dart test/home_design_test.dart test/religious_content_test.dart test/quran_reader_interaction_test.dart --reporter expanded
flutter test --no-pub test/quran_test.dart test/quran_screens_test.dart --reporter expanded
# Windows: use the existing release DLL when the debug DLL cannot load.
$env:Path=(Join-Path (Get-Location) 'build\rive_native\native\build\windows\bin\lib\release') + ';' + $env:Path
flutter test --no-pub test/startup_test.dart --reporter expanded
```

أول استعادة مع SDK مختلف قد ترفض `--enforce-lockfile`؛ يُراجع فرق lock قبل قبول الحزم التي يفرضها SDK. لا تُعدّل `package_config.json` يدويًا. اختبار Rive الحقيقي يحتاج مكتبته الأصلية على Windows؛ لا يستبدل الاختبار ملف الشعار الأصلي.

### المنجز الذي نحميه والفجوات المعروفة

اللقطات السابقة للواجهة في `build/home-preview` و`build/quran-preview` و`build/religious-preview` و`build/startup-preview` محفوظة أيضًا خارج المستودع ضمن حزمة خطة التنفيذ. لقطات build قابلة لإعادة التوليد وليست جزءًا من المصدر.

قبل تنفيذ الميزات: تبويبا الأذكار والقبلة يعرضان جسم الرئيسية؛ بعض بطاقات المزيد وأزرار البحث والملف والإشعارات وأذكار الرئيسية والإعدادات العامة بلا وظيفة. مواقيت الصلاة والتقدم والمقالات بيانات عرض. هذا توثيق للفجوات، وليس اعتمادًا لها كميزات مكتملة.

حزمة الخطة التفصيلية: `C:\Users\Hazem\Documents\Haq-Designs\HAQ_Implementation_Plan_2026-10-24`. حزمة التصاميم: `C:\Users\Hazem\Documents\Haq-Designs\HAQ_Complete_Design_2026-10-24`.
