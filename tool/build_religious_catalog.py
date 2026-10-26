"""Reproducible offline catalog. Read downloaded sources; never OCR scripture."""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--backend-root', type=Path, help='Explicit existing Laravel checkout to update as well')
args = parser.parse_args()
ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'tool/religious_sources'
QURAN = json.loads((ROOT / 'assets/quran/quran.json').read_text(encoding='utf-8'))
VERSES = {v['key']: v for v in QURAN['verses']}
CATEGORIES = []
ITEMS = []

def category(id, title, description, image='quran', header='sunnah', parent=None, kind='list'):
    CATEGORIES.append(dict(id=id, title=title, description=description,
        image=image, header=header, parent=parent, kind=kind, published=True))

category('prophetic-duas','الأدعية النبوية','أدعية من سنة النبي ﷺ في مختلف شؤون الحياة','prophetic','medina')
category('quran-duas','الأدعية القرآنية','أدعية من القرآن الكريم في مختلف المواقف والأحوال','quran','medina')
category('friday','سنن الجمعة','الأعمال المستحبة في يوم الجمعة قبلها وأثناءها وبعدها','kaaba')
category('sunnah','سنن النبي ﷺ','هدي نبينا في أقواله وأفعاله وما أُثر عنه من أعمال','beads',kind='categories')
category('names','أسماء الله الحسنى','أسماء الله الحسنى وصفاته العلى كما وردت في القرآن الكريم والسنة النبوية','names','reading',kind='names')
category('ruqya','الرقية الشرعية','أدعية وآيات من القرآن الكريم والسنة النبوية للشفاء والحفظ بإذن الله','ruqya','ruqya',kind='ruqya')
category('nawawi','الأربعون النووية','أربعون حديثًا من جوامع كلم النبي ﷺ في العقيدة والعبادات والأخلاق والمعاملات','books','sunnah')
for id,title,img in [('prayer','سنن الصلاة','hall'),('recitation','سنن قراءة القرآن','open_quran'),('supplication','سنن الدعاء والذكر','prayer'),('fasting','سنن الصيام','lantern'),('pilgrimage','سنن الحج والعمرة','kaaba'),('manners','سنن المعاملات','beads'),('daily-life','سنن الحياة اليومية','madina'),('other','سنن متفرقة','minbar')]:
    category('sunnah-'+id,title,'من هدي النبي ﷺ في '+title.replace('سنن ',''),img,parent='sunnah')
for id,title,desc in [('protection','آيات الحفظ','للتحصين من كل سوء'),('healing','آيات الشفاء','آيات القرآن الكريم'),('eye','الرقية من العين والحسد','الاستعاذة بالله من الشر'),('magic','الرقية من السحر','آيات القرآن في إبطال السحر'),('children','الرقية للأطفال','الدعاء والحفظ'),('duas','أدعية الحفظ والتحصين','من القرآن والسنة'),('various','أدعية متنوعة','للحاجات المختلفة')]:
    category('ruqya-'+id,title,desc,'ruqya','reading',parent='ruqya',kind='verses' if id not in ['duas','children','various'] else 'list')

def item(id,type,title,text,source,url,categories,**extra):
    record=dict(id=id,type=type,title=title,text=text,source=source,sourceUrl=url,
        categories=categories,tags=[],sections=[],published=True,**extra)
    ITEMS.append(record)
    return record

def qitem(id,title,keys,categories,tags,image='quran',sections=None):
    first=VERSES[keys[0]]
    surah=QURAN['surahs'][first['surah']-1]['name']
    ref=f"سورة {surah} • الآية {first['ayah']}"
    if len(keys)>1: ref=f"سورة {surah} • الآيات {first['ayah']}–{VERSES[keys[-1]]['ayah']}"
    r=item(id,'quran',title,'\n'.join(VERSES[k]['text'] for k in keys),ref,
        f"https://quran.com/{first['surah']}/{first['ayah']}",categories,
        verseKeys=keys,image=image)
    r['tags']=tags
    if sections:r['sections']=sections
    return r

dua_specs=[('goodness','ربنا آتنا في الدنيا حسنة وفي الآخرة حسنة وقنا عذاب النار',['2:201'],'أدعية عامة'),('parents','رب اغفر لي ولوالدي وللمؤمنين يوم يقوم الحساب',['14:41'],'أدعية المغفرة'),('ease','رب اشرح لي صدري ويسر لي أمري',['20:25','20:26','20:27','20:28'],'أدعية التوفيق'),('acceptance','ربنا تقبل منا إنك أنت السميع العليم',['2:127'],'أدعية عامة'),('offspring','رب هب لي من لدنك ذرية طيبة',['3:38'],'أدعية الذرية'),('knowledge','رب زدني علمًا',['20:114'],'أدعية العلم'),('forgiveness','ربنا ظلمنا أنفسنا',['7:23'],'أدعية الاستغفار'),('mercy','ربنا لا تزغ قلوبنا',['3:8'],'أدعية الهداية'),('need','رب إني لما أنزلت إلي من خير فقير',['28:24'],'أدعية الرزق'),('distress','لا إله إلا أنت سبحانك إني كنت من الظالمين',['21:87'],'أدعية الاستغفار'),('patience','ربنا أفرغ علينا صبرًا',['2:250'],'أدعية الصبر'),('family','ربنا هب لنا من أزواجنا وذرياتنا قرة أعين',['25:74'],'أدعية الذرية'),('reliance','حسبي الله لا إله إلا هو',['9:129'],'أدعية التوكل'),('thankfulness','رب أوزعني أن أشكر نعمتك',['27:19'],'أدعية الشكر'),('prayer','رب اجعلني مقيم الصلاة ومن ذريتي',['14:40'],'أدعية الهداية'),('protection','وقل رب أعوذ بك من همزات الشياطين',['23:97','23:98'],'أدعية الوقاية')]
for i,(slug,title,keys,tag) in enumerate(dua_specs,1):
    qitem('qdua-'+slug,title,keys,['quran-duas'],[tag],['open_quran','mosque','madina','kaaba','madina','lantern'][(i-1)%6])['number']=i

hisn=json.loads((SOURCES/'hisn.json').read_text(encoding='utf-8-sig'))
for chapter_index,(title,chapter) in enumerate(list(hisn.items())[2:],1):
    texts=chapter.get('text',[])
    if not texts: continue
    tags=['أدعية متفرقة']
    if 'الصباح' in title or 'المساء' in title:tags=['أذكار الصباح والمساء']
    elif any(t in title for t in ['استغفار','التوبة','أذنب']):tags=['أدعية الاستغفار']
    elif any(t in title for t in ['الهم','الكرب','خوف','المريض']):tags=['أدعية عامة']
    extra_categories=['prophetic-duas']
    if any(t in title for t in ['المسجد','الوضوء','الركوع','السجود','الصلاة','التشهد']):extra_categories.append('sunnah-prayer')
    if any(t in title for t in ['الصائم','إفطار']):extra_categories.append('sunnah-fasting')
    if any(t in title for t in ['الطواف','الصفا','عرفة','الجمرات','الحجر','المشعر']):extra_categories.append('sunnah-pilgrimage')
    if any(t in title for t in ['الثوب','الطعام','العطاس','النوم','المنزل']):extra_categories.append('sunnah-daily-life')
    if any(t in title for t in ['الضيف','الزواج','المولود','الدين','التعزية']):extra_categories.append('sunnah-manners')
    extra_categories.append('sunnah-supplication')
    if 'المريض' in title:extra_categories+=['ruqya-duas','ruqya-various']
    if 'الأولاد' in title:extra_categories+=['ruqya-children','ruqya-duas']
    # Each chapter is one sourced record, shared with all applicable categories.
    r=item(f'hisn-{chapter_index:03d}','dua',title,'\n\n'.join(texts).replace('*',''),
        'حصن المسلم • سعيد بن علي بن وهف القحطاني • '+title,
        'https://www.hisnmuslim.com/',extra_categories,number=chapter_index,
        image=['lantern','open_quran','mosque','prayer','beads'][chapter_index%5])
    r['tags']=tags
    r['sections']=[dict(title='المصادر والتخريج',text='\n'.join(chapter.get('footnote',[])),source='حصن المسلم')]
    if chapter_index==1:
        r['audioUrl']='https://www.hisnmuslim.com/audio/ar/1.mp3'
        r['reciter']='حصن المسلم • التسجيل الأصلي'
        # Official audio 1 recites only the first supplication, so keep its text aligned.
        r['text']=texts[0].replace('*','').strip()
        r['title']='الدعاء عند الاستيقاظ من النوم'
        r['sections']=[dict(title='المصادر والتخريج',text='صحيح البخاري • 6312',source='حصن المسلم • أذكار الاستيقاظ من النوم')]

nawawi=json.loads((SOURCES/'nawawi.json').read_text(encoding='utf-8-sig'))
titles=['الأعمال بالنيات','الإسلام والإيمان والإحسان','أركان الإسلام','مراحل الخلق','النهي عن الابتداع','الحلال والحرام','الدين النصيحة','حرمة دم المسلم وماله','اجتناب النواهي','طيب الكسب','دع ما يريبك','ترك ما لا يعنيك','حب الخير للمسلمين','حرمة دم المسلم','إكرام الضيف والجار','لا تغضب','الإحسان في كل شيء','تقوى الله وحسن الخلق','احفظ الله يحفظك','الحياء من الإيمان','قل آمنت بالله ثم استقم','الطريق إلى الجنة','الطهور شطر الإيمان','تحريم الظلم','فضل الذكر','كثرة طرق الخير','البر والإثم','لزوم السنة','أبواب الخير','حدود الله','الزهد في الدنيا','لا ضرر ولا ضرار','البينة على المدعي','تغيير المنكر','أخوة الإسلام','قضاء حوائج المسلمين','فضل الله وعدله','أولياء الله','التجاوز عن الخطأ والنسيان','كن في الدنيا كأنك غريب','اتباع النبي ﷺ','سعة مغفرة الله']
assert len(nawawi)==42
for i,n in enumerate(nawawi,1):
    text=n['hadith'].split('\n\n',1)[-1].strip()
    reference=None
    if i==1:
        text,reference=text.rsplit(' (رواه ',1)
        reference='رواه '+reference.rstrip(').')
    r=item(f'nawawi-{i:02d}','hadith',titles[i-1],text,
        f'الأربعون النووية • الإمام النووي • الحديث {i}',
        f'https://sunnah.com/nawawi40:{i}',['nawawi'],number=i,image=['hall','open_quran','quran','prayer','madina'][i%5])
    r['tags']=['العقيدة' if i in [2,3,4,19,24,37,38] else 'العبادات' if i in [1,5,8,9,21,22,23,25,26,28,29] else 'الأخلاق' if i in [7,11,12,13,15,16,17,18,20,27,31,35,36] else 'المعاملات']
    r['sections']=[dict(title='شرح الحديث',text=n['description'],source='شرح المجموعة كما ورد في المصدر الرقمي osamayy/40-hadith-nawawi-db')]
    if reference:r['sections'].append(dict(title='التخريج',text=reference,source='المصدر الرقمي للأربعين النووية'))
    if i==1:
        r['title']='إنما الأعمال بالنيات'
        # The supplied design has concise learning cards. Preserve the complete
        # imported commentary below them as an independently expandable section.
        r['sections']=[
            dict(title='شرح الحديث',text='يبين النبي ﷺ أن قبول العمل ووزنه عند الله تعالى يتعلق بالنية. فهي الأساس في صحة العمل وقيمته، فالمؤمن يعمل لله خالصًا، ويبتعد عن الرياء وطلب الدنيا، لأن الجزاء من جنس النية.',source='فوائد موجزة كما في مرجع التصميم المقدم'),
            dict(title='فوائد الحديث',text='• تجديد النية في جميع الأعمال.\n• إخلاص العمل لله تعالى.\n• التمييز بين العمل المقبول والمردود.\n• الدلالة على عظم منزلة الإخلاص.',source='فوائد موجزة كما في مرجع التصميم المقدم'),
            dict(title='ما يستفاد منه في الحياة اليومية',text='١. استحضار النية قبل البدء بأي عمل.\n٢. مراقبة النية أثناء العمل وتجديدها.\n٣. الحرص على تصحيح النية إذا اختلطت بغير الله.',source='فوائد موجزة كما في مرجع التصميم المقدم'),
            dict(title='الشرح المطول',text=n['description'],source='شرح المجموعة كما ورد في المصدر الرقمي osamayy/40-hadith-nawawi-db'),
            dict(title='التخريج',text=reference,source='المصدر الرقمي للأربعين النووية'),
        ]

def sunnah(slug,title,text,ref,url,image,tags,time,application,cats):
    r=item('sunnah-'+slug,'sunnah',title,text,ref,url,cats,image=image,summary=application)
    r['tags']=tags
    r['sections']=[dict(title='شرح السنة',text=application,source=ref),dict(title='وقت العمل بها',text=time,source=ref),dict(title='كيفية التطبيق',text=application,source=ref)]
    return r
sunnah('wash','الاغتسال يوم الجمعة','إِذَا أَرَادَ أَحَدُكُمْ أَنْ يَأْتِيَ الْجُمُعَةَ فَلْيَغْتَسِلْ.','صحيح مسلم • 844a','https://sunnah.com/muslim:844a','wash',['قبل الجمعة'],'قبل الذهاب إلى صلاة الجمعة.','الاغتسال استعدادًا لحضور صلاة الجمعة.',['friday','sunnah-prayer'])
sunnah('perfume','التطيب ولبس أحسن الثياب','لَا يَغْتَسِلُ رَجُلٌ يَوْمَ الْجُمُعَةِ، وَيَتَطَهَّرُ مَا اسْتَطَاعَ مِنْ طُهْرٍ، وَيَدَّهِنُ مِنْ دُهْنِهِ، أَوْ يَمَسُّ مِنْ طِيبِ بَيْتِهِ ثُمَّ يَخْرُجُ، فَلَا يُفَرِّقُ بَيْنَ اثْنَيْنِ، ثُمَّ يُصَلِّي مَا كُتِبَ لَهُ، ثُمَّ يُنْصِتُ إِذَا تَكَلَّمَ الْإِمَامُ، إِلَّا غُفِرَ لَهُ مَا بَيْنَهُ وَبَيْنَ الْجُمُعَةِ الْأُخْرَى.','صحيح البخاري • 883','https://sunnah.com/bukhari:883','perfume',['قبل الجمعة'],'عند الاستعداد للجمعة.','التطهر والتطيب، وعدم التفريق بين الجالسين، والإنصات للإمام.',['friday','sunnah-daily-life'])
sunnah('early','التبكير إلى المسجد','مَنِ اغْتَسَلَ يَوْمَ الْجُمُعَةِ غُسْلَ الْجَنَابَةِ ثُمَّ رَاحَ فَكَأَنَّمَا قَرَّبَ بَدَنَةً، وَمَنْ رَاحَ فِي السَّاعَةِ الثَّانِيَةِ فَكَأَنَّمَا قَرَّبَ بَقَرَةً، وَمَنْ رَاحَ فِي السَّاعَةِ الثَّالِثَةِ فَكَأَنَّمَا قَرَّبَ كَبْشًا أَقْرَنَ، وَمَنْ رَاحَ فِي السَّاعَةِ الرَّابِعَةِ فَكَأَنَّمَا قَرَّبَ دَجَاجَةً، وَمَنْ رَاحَ فِي السَّاعَةِ الْخَامِسَةِ فَكَأَنَّمَا قَرَّبَ بَيْضَةً، فَإِذَا خَرَجَ الْإِمَامُ حَضَرَتِ الْمَلَائِكَةُ يَسْتَمِعُونَ الذِّكْرَ.','صحيح البخاري • 881','https://sunnah.com/bukhari:881','mosque',['قبل الجمعة'],'قبل خروج الإمام.','المبادرة إلى حضور الجمعة قبل الخطبة.',['friday','sunnah-prayer'])
sunnah('salawat','كثرة الصلاة على النبي ﷺ','إِنَّ مِنْ أَفْضَلِ أَيَّامِكُمْ يَوْمَ الْجُمُعَةِ، فِيهِ خُلِقَ آدَمُ، وَفِيهِ قُبِضَ، وَفِيهِ النَّفْخَةُ، وَفِيهِ الصَّعْقَةُ، فَأَكْثِرُوا عَلَيَّ مِنَ الصَّلَاةِ فِيهِ، فَإِنَّ صَلَاتَكُمْ مَعْرُوضَةٌ عَلَيَّ.','سنن أبي داود • 1047 • صحيح عند الألباني','https://sunnah.com/abudawud:1047','hall',['قبل الجمعة','بعد الجمعة'],'يوم الجمعة.','الإكثار من الصلاة على النبي ﷺ.',['friday','sunnah-supplication'])
sunnah('listen','الإنصات للخطبة','إِذَا قُلْتَ لِصَاحِبِكَ يَوْمَ الْجُمُعَةِ أَنْصِتْ، وَالْإِمَامُ يَخْطُبُ، فَقَدْ لَغَوْتَ.','صحيح البخاري • 934','https://sunnah.com/bukhari:934','minbar',['أثناء الجمعة'],'أثناء خطبة الجمعة.','الاستماع للخطبة وترك الكلام أثناءها.',['friday','sunnah-prayer'])
sunnah('answer','ساعة الإجابة','فِيهِ سَاعَةٌ لَا يُوَافِقُهَا عَبْدٌ مُسْلِمٌ، وَهُوَ قَائِمٌ يُصَلِّي، يَسْأَلُ اللَّهَ تَعَالَى شَيْئًا، إِلَّا أَعْطَاهُ إِيَّاهُ.','صحيح البخاري • 935','https://sunnah.com/bukhari:935','prayer',['قبل الجمعة','بعد الجمعة'],'يوم الجمعة.','الاجتهاد في الدعاء وتحري ساعة الإجابة.',['friday','sunnah-supplication'])
sunnah('walk','المشي إلى الجمعة','مَنْ غَسَّلَ يَوْمَ الْجُمُعَةِ وَاغْتَسَلَ، ثُمَّ بَكَّرَ وَابْتَكَرَ، وَمَشَى وَلَمْ يَرْكَبْ، وَدَنَا مِنَ الْإِمَامِ فَاسْتَمَعَ وَلَمْ يَلْغُ، كَانَ لَهُ بِكُلِّ خُطْوَةٍ عَمَلُ سَنَةٍ أَجْرُ صِيَامِهَا وَقِيَامِهَا.','سنن أبي داود • 345 • صحيح عند الألباني','https://sunnah.com/abudawud:345','madina',['قبل الجمعة'],'عند الذهاب إلى الجمعة.','المشي إلى الجمعة مع التبكير والاستماع للخطبة.',['friday','sunnah-prayer'])
sunnah('after-friday','الصلاة بعد الجمعة','إِذَا صَلَّى أَحَدُكُمُ الْجُمُعَةَ فَلْيُصَلِّ بَعْدَهَا أَرْبَعًا.','صحيح مسلم • 881a','https://sunnah.com/muslim:881a','hall',['بعد الجمعة'],'بعد صلاة الجمعة.','صلاة أربع ركعات بعد الجمعة كما جاء في هذا الحديث.',['friday','sunnah-prayer'])
sunnah('wudu','الوضوء وإسباغه','مَنْ تَوَضَّأَ فَأَحْسَنَ الْوُضُوءَ خَرَجَتْ خَطَايَاهُ مِنْ جَسَدِهِ حَتَّى تَخْرُجَ مِنْ تَحْتِ أَظْفَارِهِ.','صحيح مسلم • 245','https://sunnah.com/muslim:245','wash',['قبل الصلاة'],'عند الوضوء للصلاة.','إحسان الوضوء وإتمامه.',['sunnah-prayer'])
sunnah('hands','رفع اليدين في الصلاة','كَانَ يَرْفَعُ يَدَيْهِ حَذْوَ مَنْكِبَيْهِ إِذَا افْتَتَحَ الصَّلَاةَ، وَإِذَا كَبَّرَ لِلرُّكُوعِ، وَإِذَا رَفَعَ رَأْسَهُ مِنَ الرُّكُوعِ رَفَعَهُمَا كَذَلِكَ أَيْضًا وَقَالَ: سَمِعَ اللَّهُ لِمَنْ حَمِدَهُ، رَبَّنَا وَلَكَ الْحَمْدُ. وَكَانَ لَا يَفْعَلُ ذَلِكَ فِي السُّجُودِ.','صحيح البخاري • 735 • عن ابن عمر','https://sunnah.com/bukhari:735','prayer',['أثناء الصلاة'],'عند افتتاح الصلاة، وعند الركوع والرفع منه.','رفع اليدين حذو المنكبين في المواضع المذكورة في الحديث.',['sunnah-prayer'])
sunnah('mosque-walk','المشي إلى الصلاة','أَعْظَمُ النَّاسِ أَجْرًا فِي الصَّلَاةِ أَبْعَدُهُمْ فَأَبْعَدُهُمْ مَمْشًى.','صحيح البخاري • 651','https://sunnah.com/bukhari:651','hall',['قبل الصلاة'],'عند الذهاب إلى الصلاة.','المشي إلى المسجد للصلاة.',['sunnah-prayer'])
# A real Quran reading record; no fabricated hadith or promise is attached.
qitem('kahf-reading','قراءة سورة الكهف',[f'18:{i}' for i in range(1,111)],['sunnah-recitation'],['قراءة القرآن'],'open_quran')

ruqya=[('fatiha','سورة الفاتحة',[f'1:{i}' for i in range(1,8)],['protection','healing'],['للرقية','للشفاء']),('kursi','آية الكرسي',['2:255'],['protection','eye'],['آية الكرسي','آيات الطمأنينة']),('baqara-end','خواتيم سورة البقرة',['2:285','2:286'],['protection'],['آيات الطمأنينة']),('ikhlas','سورة الإخلاص',[f'112:{i}' for i in range(1,5)],['protection','eye'],['من العين والحسد']),('falaq','سورة الفلق',[f'113:{i}' for i in range(1,6)],['protection','eye','magic'],['من العين والحسد','من السحر']),('nas','سورة الناس',[f'114:{i}' for i in range(1,7)],['protection','eye'],['من الشيطان']),('yunus','آيات إبطال السحر من سورة يونس',['10:81','10:82'],['magic'],['من السحر']),('shifa','وننزل من القرآن ما هو شفاء ورحمة للمؤمنين',['17:82'],['healing'],['للشفاء'])]
for i,(slug,title,keys,cats,tags) in enumerate(ruqya,1):
    qitem('ruqya-'+slug,title,keys,['ruqya-'+c for c in cats],tags,'ruqya')['number']=i
r=item('ruqya-complete','playlist','الرقية الشرعية الكاملة','مجموعة من آيات القرآن الكريم للقراءة والاستماع: الفاتحة، وآية الكرسي، وخواتيم البقرة، والإخلاص، والفلق، والناس.','النص القرآني المعتمد بالتطبيق • آيات مختارة للرقية','https://quran.com',['ruqya'],image='mosque',related=['ruqya-'+s for s in ['fatiha','kursi','baqara-end','ikhlas','falaq','nas']])
r['sections']=[dict(title='معلومات الرقية',text='الرقية بالدعاء والقرآن، وهذه قائمة آيات مختارة وليست تسجيلًا واحدًا ذا مدة ثابتة. يُعرض اسم القارئ والمدة من الصوت الفعلي. الرقية لا تُغني عن الرعاية الطبية عند الحاجة.')]

names=json.loads((SOURCES/'names.json').read_text(encoding='utf-8-sig'))['data']
meanings='ذو الرحمة الواسعة|الرحيم بعباده|الملك المدبر|المنزه عن النقص|السالم من كل نقص|واهب الأمن|الرقيب الحافظ|ذو العزة والقوة|ذو الجبروت|المتعالي عن النقص|خالق كل شيء|موجد الخلق|مصور المخلوقات|كثير المغفرة|القاهر لكل شيء|كثير العطاء|رازق العباد|فاتح أبواب الخير|العالم بكل شيء|القابض بحكمته|الباسط بفضله|الخافض بحكمته|الرافع بفضله|واهب العزة|المذل من يشاء|السامع لكل شيء|المبصر لكل شيء|الحاكم بين عباده|العادل في حكمه|اللطيف بعباده|الخبير بكل شيء|ذو الحلم|ذو العظمة|واسع المغفرة|المثيب على الشكر|العلي فوق خلقه|الكبير المتعالي|الحافظ لكل شيء|مقدر الأقوات|الكافي لعباده|ذو الجلال|واسع الكرم|الرقيب على عباده|مجيب الدعاء|واسع الفضل|ذو الحكمة|المحب لعباده|ذو المجد|باعث الخلق|الشاهد على كل شيء|الحق الثابت|الكفيل بأمور عباده|ذو القوة|شديد القوة|ولي المؤمنين|المستحق للحمد|المحيط بعدد كل شيء|المبتدئ للخلق|المعيد للخلق|واهب الحياة|مقدر الموت|دائم الحياة|القائم بتدبير كل شيء|الغني الذي لا يفتقر|ذو المجد والكرم|الواحد المتفرد|الأحد الذي لا نظير له|المقصود في الحوائج|القادر على كل شيء|تام القدرة|المقدم بحكمته|المؤخر بحكمته|الأول بلا ابتداء|الآخر بلا انتهاء|الظاهر فوق كل شيء|الباطن الذي لا يخفى عليه شيء|مدبر الأمور|المتعالي عن كل نقص|واسع الإحسان|كثير قبول التوبة|المجازي بالعدل|كثير العفو|شديد الرأفة|مالك الملك كله|صاحب الجلال والإكرام|العادل المقسط|جامع الخلق|الغني عن كل شيء|المغني بفضله|المانع بحكمته|مقدر الضر بحكمته|واهب النفع|نور السماوات والأرض|الهادي إلى الحق|مبدع السماوات والأرض|الدائم الباقي|الباقي بعد فناء الخلق|المرشد إلى الصواب|الذي لا يعجل بالعقوبة'.split('|')
assert len(meanings)==99
def norm(t):return re.sub('[\u0610-\u061a\u064b-\u065f\u0670\u06d6-\u06ed\u0640]','',t).replace('ٱ','ا').replace('أ','ا').replace('إ','ا').replace('آ','ا')
for i,n in enumerate(names):
    title=n['name']; simple=norm(title)
    matches=[v for v in QURAN['verses'] if simple in norm(v['text']).split()]
    sections=[dict(title='المعنى المختصر',text=meanings[i],source='صياغة عربية لمعنى الاسم الموجز المنشور في AlAdhan')]
    if matches:
        v=matches[0];sections.append(dict(title='من القرآن الكريم',text=v['text'],source=f"سورة {QURAN['surahs'][v['surah']-1]['name']} • الآية {v['ayah']}"))
    r=item(f'name-{n["number"]:02d}','name',title,title,'قائمة الأسماء • AlAdhan • المعنى الموجز مترجم إلى العربية','https://aladhan.com/asma-al-husna',['names'],number=n['number'],image='names',summary=meanings[i],transliteration=n['transliteration'],related=[f'name-{((i+1)%99)+1:02d}',f'name-{((i+2)%99)+1:02d}'])
    r['sections']=sections
    r['tags']=['الرحمة' if i in [0,1,15,29,41,43,44,46,78,79,81,82] else 'المغفرة' if i in [13,33,79,81] else 'القوة' if i in [7,8,14,19,20,52,53,68,69] else 'الصفات']

overrides=json.loads((SOURCES/'catalog-editorial-overrides.json').read_text(encoding='utf-8'))
for record in ITEMS:
    record.update(overrides.get(record['id'], {}))

# P05 selections are reviewed stable IDs, never runtime keyword matches.
legacy_item_ids={r['id'] for r in ITEMS}
legacy_category_ids={r['id'] for r in CATEGORIES}
curation=json.loads((SOURCES/'haq-content-curation.json').read_text(encoding='utf-8'))
for slug,title,key in [
    ('believers','دعاء المؤمنين بالمغفرة','3:16'),
    ('steadfastness','دعاء الثبات والنصر','3:147'),
    ('faithful','دعاء المؤمنين بتمام المغفرة','3:193'),
    ('promise','دعاء المؤمنين بوعد الله','3:194'),
    ('safety','الدعاء بالسلامة من الظلم','7:47'),
    ('justice','الدعاء بالحق','7:89'),
    ('trust','دعاء التوكل والثبات','10:85'),
    ('deliverance','الدعاء بالنجاة والرحمة','10:86'),
    ('yusuf','دعاء يوسف عليه السلام','12:101'),
    ('ibrahim','دعاء إبراهيم بالأمن','14:35'),
    ('entrance','دعاء الصدق في الدخول والخروج','17:80'),
    ('mercy-believers','دعاء عباد الله المؤمنين','23:109'),
    ('angels','دعاء الملائكة للمؤمنين','40:7'),
    ('brothers','الدعاء للمؤمنين وصفاء القلوب','59:10'),
    ('isa','دعاء عيسى عليه السلام','5:114'),
]:
    qitem('qdua-'+slug,title,[key],['quran-duas'],['أدعية قرآنية'])
qitem('ramadan-quran-verse','شهر رمضان ونزول القرآن',['2:185'],['quran-duas'],['رمضان'])
qitem('ramadan-fasting-verse','وقت السحور والإفطار والاعتكاف',['2:187'],['quran-duas'],['رمضان'])
qitem('ramadan-qadr-verses','سورة القدر',[f'97:{n}' for n in range(1,6)],['quran-duas'],['رمضان'])
qadr=json.loads((SOURCES/'ramadan-qadr-dua.json').read_text(encoding='utf-8'))
item(qadr['id'],'dua',qadr['title'],qadr['text'],qadr['source'],qadr['source_url'],['prophetic-duas'],image='lantern')
ramadan_hadiths=json.loads((SOURCES/'ramadan-hadiths.json').read_text(encoding='utf-8'))
for hadith in ramadan_hadiths['items']:
    record=item(hadith['id'],'hadith',hadith['title'],hadith['text'],hadith['source'],hadith['source_url'],['sunnah-fasting'],image='lantern')
    record['sections']=[dict(title='المعنى الموجز',text=hadith['explanation'],source='تلخيص لمعنى المتن المرفق، وليس نصًا منسوبًا للمصدر')]
by_id={r['id']:r for r in ITEMS}
def attach(ids, category_id):
    for id in ids:
        assert id in by_id, f'Unknown curated record {id}'
        if category_id not in by_id[id]['categories']:
            by_id[id]['categories'].append(category_id)

category('feelings','بماذا تشعر؟','اختر شعورك في هذه اللحظة','hands','medina',kind='categories')
assert len(curation['moods'])==17
for mood in curation['moods']:
    cid='mood-'+mood['id']
    category(cid,mood['title'],'دعاء وذكر يرافقان لحظتك','hands','medina',parent='feelings')
    attach(mood['item_ids'],cid)
for collection in curation['collections']:
    category(collection['id'],collection['title'],'نصوص موثقة من القرآن والسنة',collection['image'],'medina')
    attach(collection['item_ids'],collection['id'])
category('ramadan','رمضان','القرآن والدعاء وأعمال الشهر','lantern','medina',kind='categories')
for section in curation['ramadan']:
    cid='ramadan-'+section['id']
    category(cid,section['title'],'نصوص من القرآن والسنة مع المصدر','lantern','medina',parent='ramadan')
    attach(section['item_ids'],cid)
category('hadith','الأحاديث النبوية','مكتبة حق الموثقة: المتن والشرح والمصدر','books',kind='categories')
hadith_groups=[
    ('creed','العقيدة',[2,3,4,19,21,22,38,41,42]),
    ('worship','العبادات',[1,3,5,9,10,23,25,26,28,29,30,37]),
    ('dealings','المعاملات',[6,8,11,12,13,14,24,32,33,35,39]),
    ('ethics','الأخلاق والآداب',[7,13,15,16,17,18,20,27,31,34,35,36,40]),
    ('sciences','الحديث وعلومه',[1,5,9,28]),
    ('comprehensive','جوامع الكلم',list(range(1,43))),
]
for slug,title,numbers in hadith_groups:
    cid='hadith-'+slug
    category(cid,title,'أحاديث من الكتالوج الموثق الموجود في حق','books',parent='hadith')
    attach([f'nawawi-{n:02d}' for n in numbers],cid)
attach([entry['id'] for entry in ramadan_hadiths['items']],'hadith-worship')

payload=dict(version='2026-10-24.1',sources=[dict(name='القرآن الكريم',url=QURAN.get('sourceUrl','https://tanzil.net'),license=QURAN['textLicense']),dict(name='حصن المسلم',url='https://github.com/rn0x/hisn_almuslim_json'),dict(name='الأربعون النووية',url='https://github.com/osamayy/40-hadith-nawawi-db',license='CC0 - see upstream LICENSE'),dict(name='قائمة الأسماء ومعانيها الموجزة',url='https://aladhan.com/asma-al-husna')],categories=CATEGORIES,items=ITEMS)
assert len({r['id'] for r in ITEMS})==len(ITEMS)
payload['schema_version']=2
payload['version']=curation['version']
payload['bundled_extensions']={'category_ids':[r['id'] for r in CATEGORIES if r['id'] not in legacy_category_ids],
    'item_ids':[r['id'] for r in ITEMS if r['id'] not in legacy_item_ids]}
payload['moods']=curation['moods']
daily_ids=[r['id'] for r in ITEMS if r['id'].startswith('qdua-')][:30]
assert len(daily_ids)==30
payload['ramadan_days']=[dict(day=n+1,item_id=id) for n,id in enumerate(daily_ids)]
payload['ramadan_days_note']='مقترحات لتنظيم القراءة والدعاء؛ لا تثبت سنة تخصيص كل يوم بدعاء بعينه أو فضل خاص.'
payload['sources'].append(dict(name=qadr['source'],url=qadr['source_url'],checked_at=qadr['checked_at']))
payload['sources'].extend(dict(name=entry['source'],url=entry['source_url'],checked_at=ramadan_hadiths['checked_at']) for entry in ramadan_hadiths['items'])
targets = [ROOT/'assets/religious/catalog.json']
if args.backend_root is not None:
    backend = args.backend_root.resolve(strict=True)
    if not (backend/'composer.json').is_file() or not (backend/'resources/religious').is_dir():
        parser.error('--backend-root must point to the intended existing Laravel checkout')
    targets.append(backend/'resources/religious/catalog.json')
for p in targets:
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'Built {len(CATEGORIES)} categories and {len(ITEMS)} sourced records')
