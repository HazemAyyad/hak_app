# مراجعة حق البصرية — P21

التفاصيل في [changes.md](changes.md)، ومصفوفة المقارنات في [review.json](review.json). يحتوي [artifact-summary.json](artifact-summary.json) نتيجة التوليد وعدد الصور والمسارات المفقودة.

المعرض المحلي: C:/Users/Hazem/Documents/Haq-Designs/HAQ_Visual_Review_2026-10-27/index.html. يدعم الفاتح والداكن وقبل/بعد والبحث. توجد 52 مقارنة صريحة عبر الأقسام العشرين؛ فهرس 309 حالات للتتبع وليس شهادة قبول فردي لكل حالة. نصوص ومحتوى المعاينات من بيانات اختبار معلنة، ولا تُنشر على خادم.

لإعادة معاينات الاختبارات، استخدم المشغّل العادي مع --dart-define=HAQ_VISUAL_AUDIT=true وملفات اختبارات الأقسام. تكتب إلى build/visual-audit/current، ولا تُعدّل بيانات أو إعدادات التطبيق المثبت. اختبارات الإتاحة العادية تبقى دون هذا العلم. build/visual-audit/before يحوي لقطات ما قبل التعديل حين تتوفر؛ غيابها ظاهر في المعرض ولا يُعوّض بلقطة حديثة.

لتوليد المعرض بعد تحديث الصور:

```powershell
python tool/build_visual_review.py --designs 'C:/Users/Hazem/Documents/Haq-Designs/HAQ_Complete_Design_2026-10-24' --output 'C:/Users/Hazem/Documents/Haq-Designs/HAQ_Visual_Review_2026-10-27'
```

الأداة تقرأ المرجع وتنسخ الصور إلى مجلد المعرض مع بصماتها، ولا تشغّل تطبيقًا أو خدمة. تحتاج Pillow المتوفر في Python المرفق ببيئة العمل. أي مسار مفقود يفشل التوليد؛ ملفات PNG داخل المعرض مستقلة عن build حتى لا تفقدها عند تنظيف المشروع. روابط الحالات المرجعية الـ309 تتجه إلى مجلد التصاميم الأصلي وتحتاج بقاءه.

التحقق: build/p21-final-full.log وbuild/p21-visual-verified.log وbuild/p21-final-analyze.log، مع اختبارات المصمم والمحتوى المذكورة في changes.md. فحص المعرض في المتصفح لا يعوّض فحص التطبيق على هاتف.
