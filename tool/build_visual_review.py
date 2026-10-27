"""Package explicit visual comparisons without changing references or running apps."""
from __future__ import annotations

import argparse
import hashlib
import html
import json
from pathlib import Path
import shutil
import subprocess

from PIL import Image, ImageDraw


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--designs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    profile = read_json(root / "docs/visual-review/review.json")
    original = read_json(root / "docs/release-audit/audit.json")["design_states"]
    references = {row["code"]: row for row in original}
    current = root / "build/visual-audit/current"
    before = root / "build/visual-audit/before"
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    images = out / "images"
    images.mkdir(exist_ok=True)
    missing, receipts, comparisons = [], [], []

    def copy_image(path, filename):
        if not path.is_file():
            missing.append(str(path))
            return None
        destination = images / filename
        shutil.copyfile(path, destination)
        with Image.open(destination) as image:
            size = list(image.size)
        receipts.append({"path": "images/" + filename, "source": str(path),
                         "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(), "pixels": size})
        return "images/" + filename

    for index, row in enumerate(profile["comparisons"]):
        item = {**row, "images": {}}
        for theme in ("light", "dark"):
            path = row.get(theme)
            if not path:
                continue
            reference = args.designs / references[row["code"]][theme]
            capture = (root / "build" / path) if row.get("standard_suite_capture") else (current / path)
            item["images"][theme] = {
                "reference": copy_image(reference, f"{index:02d}-{theme}-reference.png"),
                "current": copy_image(capture, f"{index:02d}-{theme}-current.png"),
            }
            item["images"][theme]["continuations"] = [
                copy_image(continuation, f"{index:02d}-{theme}-scroll-{number}.png")
                for number, continuation in enumerate(sorted(
                    (current / path).parent.glob((current / path).stem + "-scroll-*.png")
                ), 1)
            ]
            if (before / path).is_file():
                item["images"][theme]["before"] = copy_image(before / path, f"{index:02d}-{theme}-before.png")
        comparisons.append(item)

    # Every original state remains visible in the index. No generic section
    # screenshot is promoted to acceptance of an unrendered dialog/state.
    explicit_codes = {row["code"] for row in comparisons}
    states = [{"code": row["code"], "section": row["section"], "title": row["title"],
               "explicit_comparison": row["code"] in explicit_codes,
               "individual_visual_acceptance": False,
               "light": (args.designs / row["light"]).resolve().as_uri(),
               "dark": (args.designs / row["dark"]).resolve().as_uri()} for row in original]
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, check=True,
                          capture_output=True, text=True).stdout.strip()
    result = {**profile, "comparisons": comparisons, "states": states,
              "source_head_before_review_commit": head, "receipts": receipts, "missing": missing,
              "capture_note": "Widget-test PNG exports; normal text scale. Some retained Quran/home views use their existing viewport. Not device screenshots."}
    (out / "review.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # Six comparisons per sheet, equal image width, never stretch text. Tall
    # originals are cropped for the overview only; the HTML retains full PNGs.
    for start in range(0, len(comparisons), 6):
        sheet = Image.new("RGB", (1320, 1320), "#e9e5dc")
        draw = ImageDraw.Draw(sheet)
        for offset, row in enumerate(comparisons[start:start + 6]):
            pair = row["images"].get("light", {})
            for column, kind in enumerate(("reference", "current")):
                path = pair.get(kind)
                x = (offset % 3) * 440 + column * 220
                y = (offset // 3) * 660
                draw.text((x + 4, y + 8), f'{row["code"]} {kind}', fill="#102a43")
                if path:
                    with Image.open(out / path) as raw:
                        image = raw.convert("RGB")
                        image = image.resize((210, round(image.height * 210 / image.width)))
                        sheet.paste(image.crop((0, 0, 210, min(610, image.height))), (x, y + 34))
        sheet.save(out / f"overview-{start // 6 + 1}.jpg", quality=90)

    labels = {"updated": "عُدّل بعد المقارنة", "preserved": "التصميم القائم محفوظ",
              "aligned": "نفس اتجاه التصميم", "adapted": "تكييف مع الوظائف والبيانات",
              "superseded": "مرجع أحدث بطلبك"}
    esc = html.escape
    content = []
    for section in profile["sections"]:
        cards = []
        for index, row in enumerate(comparisons):
            if row["section"] != section["section"]:
                continue
            cards.append(f'<article data-entry="{index}"><h3>{esc(row["title"])} <small>{row["code"]}</small></h3>'
                         f'<p>{esc(row["note"])}</p><div class="pair"></div><details><summary>معاينات التمرير المتاحة</summary>'
                         '<div class="continuations"></div></details></article>')
        content.append(f'<section id="s{section["section"]}" data-search="{esc(section["title"])} {section["section"]}">'
                       f'<div class="section-title"><h2>{section["section"]} · {esc(section["title"])}</h2>'
                       f'<span class="badge">{labels[section["status"]]}</span></div><p>{esc(section["note"])}</p>' + "".join(cards) + '</section>')

    page = '''<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>حق — مراجعة التصميم والتنفيذ</title>
<style>*{box-sizing:border-box}body{margin:0;background:#f8f5ee;color:#102a43;font:16px/1.8 system-ui}header,main{max-width:1200px;margin:auto;padding:28px}header{padding-bottom:12px}h1{font-size:32px;margin:0}h2{font-size:24px;margin:0}h3{margin:0}p{margin:8px 0 18px}.intro{border-right:4px solid #c7a45a;padding:12px 18px;background:#fffdf8;border-radius:12px}nav{position:sticky;top:0;z-index:2;display:flex;flex-wrap:wrap;gap:10px;background:#f8f5eef5;border-bottom:1px solid #ddd;padding:12px;backdrop-filter:blur(10px)}input,select,button{font:inherit;padding:9px 14px;border:1px solid #ccd5d6;border-radius:12px;background:white;color:#102a43}input{flex:1;min-width:190px}button{cursor:pointer}section{scroll-margin-top:90px;margin-bottom:34px;border-radius:24px;padding:24px;background:white;border:1px solid #e9e5dc}.section-title{display:flex;gap:12px;align-items:center;flex-wrap:wrap}.badge{background:#edf6f3;color:#075c57;border-radius:100px;padding:4px 12px;font-size:13px}article{border-top:1px solid #eee;padding:20px 0}small{color:#6b7280;font-size:13px}.pair{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px;direction:ltr}.shot{direction:rtl;background:#f4f1eb;padding:12px;border-radius:18px}.shot label{display:block;font-weight:700;margin-bottom:10px}.viewport{height:620px;overflow:auto;border-radius:12px;background:#e9e5dc;text-align:center}.viewport img{width:100%;max-width:390px;height:auto;display:block;margin:auto}.empty{padding:60px 16px;text-align:center;color:#6b7280}.continuations{display:flex;gap:12px;overflow:auto}.continuations img{width:200px;height:auto}.catalog{max-height:420px;overflow:auto}a{color:#08796f}details{margin-top:12px}table{width:100%;border-collapse:collapse}td,th{padding:10px;text-align:right;border-bottom:1px solid #eee}[hidden]{display:none!important}@media(max-width:650px){header,main{padding:14px}h1{font-size:25px}section{padding:15px}.pair{gap:8px}.shot{padding:5px}.viewport{height:420px}nav{position:static}}
</style><header><h1>حق · التصميم مقابل التنفيذ</h1><p>مراجعة بصرية — 27–28 أكتوبر 2026 · 20 قسمًا · 52 مقارنة صريحة</p>
<div class="intro">المعاينات من Flutter Widget Tests بالنص الطبيعي، وليست صور هاتف محدّث. المقارنة على عرض موحّد لا تعني تطابق البكسلات. الرئيسية والقرآن والمظهر وتفاصيل المحتوى محفوظة وفق قرارك السابق. الفهرس يتتبع 309 حالات؛ لا يدعي اعتماد كل حالة منها بصريًا بشكل فردي.</div></header>
<main><nav><input id="search" placeholder="ابحث عن قسم أو اسم شاشة…" aria-label="بحث"><select id="theme" aria-label="المظهر"><option value="light">فاتح</option><option value="dark">داكن</option></select><select id="version" aria-label="نسخة التنفيذ"><option value="current">بعد المراجعة</option><option value="before">قبل المراجعة إن توفرت</option></select><button id="reset">إظهار الكل</button></nav>''' + "".join(content) + '''<section><h2>فهرس الحالات الأصلية</h2><p>وجود مقارنة لعائلة الشاشة لا يعتمد تلقائيًا قوائمها ونوافذها وكل حالاتها. الحالات بلا مقارنة صريحة موضّحة هنا، مع بقاء المصدر والاختبارات مرتبطين بها في تقرير التتبع السابق.</p><div class="catalog"><table><thead><tr><th>الرمز</th><th>الحالة</th><th>الدليل البصري</th><th>المرجع</th></tr></thead><tbody id="states"></tbody></table></div></section></main><script>
const DATA = __DATA__;
function render(){const theme=document.querySelector('#theme').value,version=document.querySelector('#version').value;document.querySelectorAll('article').forEach(el=>{const row=DATA.comparisons[Number(el.dataset.entry)],images=row.images[theme];const parts=[['المرجع المعتمد',images?.reference],['التنفيذ '+(version==='before'?'قبل المراجعة':'بعد المراجعة'),images?.[version]]];el.querySelector('.pair').innerHTML=parts.map(([label,path])=>'<div class="shot"><label>'+label+'</label><div class="viewport">'+(path?'<a href="'+path+'" target="_blank"><img loading="lazy" src="'+path+'" alt="'+label+'"></a>':'<div class="empty">لا توجد لقطة منفصلة لهذه الحالة أو النسخة. راجع ملاحظة المقارنة.</div>')+'</div></div>').join('');const more=images?.continuations??[];el.querySelector('.continuations').innerHTML=more.map(path=>'<a href="'+path+'" target="_blank"><img loading="lazy" src="'+path+'" alt="تكملة التمرير"></a>').join('');});}
function filter(){const q=document.querySelector('#search').value.trim();document.querySelectorAll('section[data-search]').forEach(s=>s.hidden=!s.textContent.includes(q));}
document.querySelector('#theme').onchange=render;document.querySelector('#version').onchange=render;document.querySelector('#search').oninput=filter;document.querySelector('#reset').onclick=()=>{document.querySelector('#search').value='';filter();};
document.querySelector('#states').innerHTML=DATA.states.map(s=>'<tr><td>'+s.code+'</td><td>'+s.title+'</td><td>'+(s.explicit_comparison?'مقارنة صريحة لتركيب الواجهة':'تتبع ضمن القسم؛ دون اعتماد فردي')+'</td><td><a href="'+s.light+'">فاتح</a> · <a href="'+s.dark+'">داكن</a></td></tr>').join('');render();
</script></html>'''
    # Keep the HTML self-contained apart from copied PNGs; no CDN/fonts/network.
    data = json.dumps(result, ensure_ascii=False).replace("<", "\\u003c")
    (out / "index.html").write_text(page.replace("__DATA__", data), encoding="utf-8")
    summary = {"sections": len(profile["sections"]), "comparisons": len(comparisons),
               "reference_states": len(states), "copied_images": len(receipts), "missing": missing,
               "artifact": str(out / "index.html"), "individual_309_visual_acceptance": False}
    (root / "docs/visual-review/artifact-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=True))
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
