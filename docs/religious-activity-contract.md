# عقد الأقسام الدينية — schema 3

## التخزين والملكية

`haq_religious_activity_v1.sqlite` ملف مستقل عن تخزين القرآن والتنزيلات. يُفتح عند حاجة قسم ديني أو بطاقة «رحلتك اليوم» عبر `ReligiousController.activity`. لكل صف نطاق `guest` أو `account.<id>`، ومعرّف UUID للجهاز محفوظ مرة واحدة. العمليات والسجلات ثابتة الهوية عند إعادة الإرسال.

| النوع | القيمة |
| --- | --- |
| group | id، title، item_ids المرتبة والفريدة، sort_order |
| dhikr | id، text، target الموجب، source الاختياري, preface (optional) |
| session | id، group_id، day، epoch، targets المرتبة، mode، catalog_version، auto_advance، cursor |
| habit | id، title، weekdays من1 إلى7، target، enabled؛ icon وepoch اختياريان |
| khatma | id، title، start_date، end_date، first_page، last_page حتى604؛ epoch وarchived وreminder_minutes اختياريًا |
| tasbih | id, text, benefit, goal, epoch, style (six values), sort_order |

الهوية في المزامنة `kind:UUID`؛ لا تُرسل قيم JSON حرة خارج هذه الحقول. وضع القراءة cards/list/focus. الجلسة تحتفظ بأهداف نسختها من المحتوى؛ عدد المتبقي يُحسب من الأحداث ولا يُخزّن كنسخة ثانية متعارضة.

الحدث: `id, device_id, session_id, subject_id, epoch, kind, amount, occurred_at, day, utc_offset_minutes, reverses`. الوقت UTC بثلاث خانات للميلي ثانية وZ، واليوم المحلي مستقل مع الإزاحة. الأنواع count/undo/complete/reset/habit/quranPage/breathing. العدّ موجب؛ undo/complete/reset مقدارها صفر. التراجع يشير إلى حدث موجب من الجلسة والعنصر والدورة نفسها، مرة واحدة فقط. إعادة البدء تستخدم epoch جديدة وتحافظ على التاريخ.

فحص الهدف وإضافة الضغطة معاملة واحدة لمنع تجاوز الصفر مع الضغط السريع. التاريخ مفهرس بحسب الحساب والجلسة واليوم؛ ليست كل ضغطة إعادة كتابة ملف JSON متنامٍ.

## التوافق مع البيانات السابقة

تبقى مفاتيح القرآن والمحتوى الديني القديمة فعالة دون إعادة كتابة. قبل أول تعديل، تُحفظ نسخة `legacy.v1` من قيم النطاق مع SHA-256. معرّفات «أذكاري» القديمة مراجع للمحتوى؛ لا تُحوّل إلى نصوص شخصية أو أعداد تكرار مخترعة. فشل قراءة قاعدة أو رد مزامنة لا يسبب مسح البيانات.

استيراد بيانات الضيف لا يحدث إلا عند اختيار دمجها في تسجيل الدخول؛ تُحفظ الموافقة لكل حساب. أولًا تُجلب بيانات الحساب وعلامات الحذف وكامل صفحات تاريخه، ثم يحدث دمج واحد دون نسخ حساب آخر. لا تعود العناصر المحذوفة من نسخة الضيف. تراجع الخادم المقبول يستبدل تراجعًا محليًا معلقًا عن الضغطة نفسها عند تعارض جهازين.

## API

المسارات تحت `/api/v1/religious`:

| المسار | العقد |
| --- | --- |
| GET capabilities | schema_version، personal_sync، activity_sync، max_batch250، activity_page_size500 |
| POST personal/sync | operations بصيغة دفتر المزامنة الحالي؛ جواب entities/revision/acknowledged/conflicts |
| POST activity/sync | events حتى250 وcursor؛ جواب events بصيغة revision/event، وcursor وrevision وhas_more وacknowledged |

اختير personal/sync بدل مسار مخصص للأذكار وحدها حتى تشترك المجموعات والعادات والختمات في العقد المعرّف نفسه. يبقى `/sync` القديم للمفضلة والمحفوظات والاستماع كما هو، وكذلك مزامنة القرآن.

تحتاج الكتابة حسابًا دينيًا ورمز Sanctum بصلاحية quran:sync. يحدد الخادم المالك من الرمز، ولا يقبل مالكًا ضمن البيانات. لكل حساب مسارا revision مستقلان personal/activity؛ لا تعديل لمراجعات القرآن أو المحتوى القديمة. قفل صف الحساب والمعاملة يمنعان تعارض مراجعات جهازين. تكرار UUID بنفس القيمة يُقرّ دون إعادة العدّ؛ إعادة استخدامه ببيانات مختلفة409، والقيمة غير الصحيحة422. الشخصية القديمة تتعارض وتُعتمد نسخة الحساب؛ الحذف يبقى علامة صريحة.

صفحات الأحداث مرتبة ومتتابعة، حتى500؛ يُحفظ المؤشر والإقرارات والأحداث في معاملة واحدة. لا يتقدم المؤشر فوق صفحة ناقصة. يُعاد إرسال المعلق بعد فقد الرد، وتُفصل ردود تسجيل دخول سابق عن الحساب الحالي. الخدمة غير المتاحة تبقي المعلق محليًا وتعرض حالة عدم المزامنة.

## تفعيل الباك وحدود التحقق

الترحيل المصدر `2026_10_24_120000_create_religious_module_storage.php` ينشئ أربع جداول جديدة فقط. لم يُشغّل على قاعدة الجمعية أو قاعدة محلية فعلية. الافتراضي `RELIGIOUS_MODULE_SYNC_ENABLED=false`؛ التشغيل على السيرفر يتطلب نشر الترحيل المخصص وتفعيله ضمن مرحلة نشر منفصلة. لا تعديل لـ.env هنا.

اختبارات SQLite FFI على Windows تستخدم قاعدة في الذاكرة وملفًا مؤقتًا لاختبار إعادة الفتح. اختبارات HTTP محول محلي بلا اتصال خارجي؛ اختبارات Laravel تعمل على اتصال SQLite مسمى في الذاكرة بعد فحص اسمه ونوعه. هذه أدلة آلية، ولا تثبت جهاز Android أو سيرفرًا منشورًا.

## الكتالوج والصوت

النسختان المضمّنتان متطابقتان في2026-10-24.1: 310 عناصر و22 قسمًا. حُلّ اختلاف16 صورة باستبقاء صور Flutter المعتمدة، وحُفظ تحرير الباك الموجود لعنوان وشرح الحديث الأول. النصوص القرآنية والمصادر الأصلية دون تغيير. ملف editorial-overrides يحفظ التحرير عند إعادة التوليد. مولّد الكتالوج يكتب Flutter فقط افتراضيًا؛ تحديث الباك يحتاج --backend-root صريحًا إلى checkout موجود، دون أي مسار F ثابت.

القرآن والمحتوى الديني يستخدمان المشغل الأصلي المشترك مع ملكية واضحة: أوامر ومؤقت القسم السابق لا تتحكم بالتلاوة الجديدة، والتحميل السابق لا يبدأ صوتًا متأخرًا بعد سحب ملكيته. طول Future التشغيل لا يحبس أمر الإيقاف المؤقت. غياب صوت حقيقي يعطّل أزرار الاستماع والتنزيل والإضافة للقائمة قبل تهيئة المشغل؛ إزالة عنصر قديم من القائمة تبقى ممكنة.

## P04 protocol and ordering

Capabilities now require schema_version=2 for the sixth typed entity. The old Quran/content sync endpoints remain unchanged. The backend is still disabled by default; no deployment or real database migration was performed.
SQLite version2 retains the existing filename and all records. Upgrade adds nullable remote_revision and rewinds activity.cursor to zero for one safe backfill. Server revisions precede local pending sequence; reset/count folding therefore converges across devices. Personal definitions and reset markers can commit atomically.
Tasbih current-reset keeps totals and completed rounds. A new overall epoch resets visible totals while retaining historical events. Goal changes start a new segment. See docs/tasbih-implementation.md for UI behavior and voice validation boundaries.

## P06 — schema3 والختمات والعادات

schema_version3 هو العقد الحالي. يُعلن لأن عميل schema2 لا يحتفظ بامتدادات التعريفات عند تحريرها؛ العميل الجديد يمتنع عن إرسال المعلق إلى خادم2، والعميل القديم يمتنع عند3. الحقول الاختيارية لا تضاف عند قراءة سجل قديم، لتبقى عمليات P02/P04 وبصمات إيصالاتها صالحة. icon واحد من12 رمزًا معروفًا، وepoch UUID؛ archived قيمة منطقية وreminder_minutes بين0 و1439. لا ترحيل أو عمود جديد، والتفعيل الافتراضي ما زال false.

جلسة العادة هي UUID تعريفها، ودورتها epoch أو UUID التعريف القديم، وعنوان الحدث `habit:<id>:<target>`. يحتسب الإنجاز بحسب اليوم المحلي، مع سقف الهدف بعد دمج أحداث الجهازين وتطبيق التراجع. تغيير الهدف يبدأ epoch جديدة ويحفظ التاريخ. التعريفات والأحداث تستعمل مساري personal/activity الحاليين؛ لا نسخة إحصاءات قابلة للكتابة من العميل.

جلسة الختمة هي UUID تعريفها. `quran-verse:<surah>:<ayah>` يحفظ آخر آية مؤكدة بمقدار رقم الصفحة؛ لا يُجمع هذا المقدار كعدد صفحات. `quran-page:<page>` بمقدار1 يحفظ الصفحة المكتملة فقط بعد بلوغ آخر آية فيها. عند الدمج تُختار أبعد آية وتُحتسب الصفحات الفريدة في الدورة، فلا يكررها جهازان. تنسب الصفحة في التقارير اليومية لأول تأكيد زمني، مع UUID لكسر التعادل. الدورة الجديدة تترك القديمة في السجل. تأكيد قارئ من epoch قديمة لا يكتب تقدم الدورة الجديدة.

`statistics:all` مع reset يحدد بدء عرض جديد حسب ترتيب السجل (مراجعات الخادم ثم المعلق) ولا يحذف الأحداث أو تقدم العادات والختمات. بيانات القراءة والتسبيح محسوبة من الأحداث الفعلية بعد التراجع؛ لا مدة قراءة مستنتجة من فتح الشاشة. الموعد المحفوظ للختمة إعداد فقط؛ جدولة إشعار الجهاز ضمن P08 ولم تُفعّل هنا. تفاصيل الخطة اليومية والتقسيم والتصميم في docs/progress-implementation.md.
