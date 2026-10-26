"""Build a read-only traceability audit, never run Flutter, SQL, deployment or paid APIs.

The original design/plan JSON stays immutable. Evidence means a section-level
source/test mapping, not 309 individually executed visual or device checks.
"""
from __future__ import annotations

import argparse
import csv
import html
import json
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


SECTIONS = {
    "01": ("P01", ["lib/main.dart", "lib/navigation"], ["test/home_design_test.dart", "test/navigation_test.dart"], "docs/startup-and-navigation.md", "مقارنة جهاز نهائية؛ الرئيسية محفوظة"),
    "02": ("P03", ["lib/features/adhkar"], ["test/adhkar_session_test.dart", "test/adhkar_screens_test.dart", "test/adhkar_volume_test.dart"], "docs/adhkar-implementation.md", "أزرار صوت الجهاز والاهتزاز والمزامنة الحية"),
    "03": ("P02", ["lib/features/quran"], ["test/quran_reader_interaction_test.dart", "test/quran_content_test.dart", "test/quran_audio_handler_test.dart", "test/quran_page_downloads_test.dart"], "docs/quran-implementation-status.md", "API ووسائط فعلية وصوت القفل والتنزيل على جهاز"),
    "04": ("P06", ["lib/features/progress", "lib/features/religious_activity"], ["test/progress_test.dart", "test/progress_screens_test.dart"], "docs/progress-implementation.md", "مزامنة جهازين والتذكير الأصلي"),
    "05": ("P05", ["lib/features/religious_content"], ["test/religious_curated_test.dart", "test/religious_content_test.dart"], "docs/content-and-sharing-implementation.md", "تشغيل المحتوى الحي والمشاركة الأصلية"),
    "06": ("P04", ["lib/features/tasbih"], ["test/tasbih_test.dart", "test/tasbih_screens_test.dart"], "docs/tasbih-implementation.md", "التعرف الصوتي والاهتزاز والميكروفون الحقيقي"),
    "07": ("P05", ["lib/features/religious_content/presentation/religious_moods.dart"], ["test/religious_curated_test.dart", "test/religious_content_test.dart"], "docs/content-and-sharing-implementation.md", "مراجعة نهائية على جهاز"),
    "08": ("P05", ["lib/features/religious_content"], ["test/religious_curated_test.dart", "test/religious_content_test.dart", "test/settings_test.dart"], "docs/content-and-sharing-implementation.md", "التذكير الأصلي يوم الجمعة"),
    "09": ("P05", ["lib/features/religious_content"], ["test/religious_curated_test.dart", "test/religious_content_test.dart"], "docs/content-and-sharing-implementation.md", "المحتوى الحالي موثق؛ فحص العرض النهائي"),
    "10": ("P05", ["lib/features/religious_content"], ["test/religious_curated_test.dart", "test/religious_content_test.dart"], "docs/content-and-sharing-implementation.md", "مراجعة المصدر والمحتوى المنشور"),
    "11": ("P07", ["lib/features/sakinah"], ["test/sakinah_test.dart", "test/sakinah_screens_test.dart"], "docs/sakinah-implementation.md", "الخلفية والاهتزاز ومقاطعات الجهاز"),
    "12": ("P06", ["lib/features/progress", "lib/features/religious_activity"], ["test/progress_test.dart", "test/progress_screens_test.dart", "test/religious_activity_sync_test.dart"], "docs/progress-implementation.md", "خادم منشور وتعارض جهازين"),
    "13": ("P11", ["lib/features/community"], ["test/community_test.dart", "test/community_screens_test.dart"], "docs/community-implementation.md", "تهيئة الخادم والمحتوى؛ تزامن MySQL وجهاز"),
    "14": ("P11", ["lib/features/community"], ["test/community_test.dart", "test/community_screens_test.dart"], "docs/community-implementation.md", "تهيئة المجتمع والمراجعة والاختبار الحي"),
    "15": ("P11", ["lib/features/community"], ["test/community_test.dart", "test/community_screens_test.dart"], "docs/community-implementation.md", "وسائط HTTPS وفيديو/YouTube على جهاز؛ Push الخلفي غير منفذ"),
    "16": ("P09", ["lib/features/prayer"], ["test/prayer_test.dart", "test/prayer_screens_test.dart"], "docs/prayer-qibla-implementation.md", "مصدر مساجد حي ومعايرة الحساس والموقع والمواقيت"),
    "17": ("P08", ["lib/features/settings", "lib/app_appearance.dart"], ["test/settings_test.dart", "test/settings_screens_test.dart", "test/widget_test.dart"], "docs/settings-and-reminders-implementation.md", "أذونات وإقلاع وقفل وMIUI وSwift؛ نافذة Android دون مماثل iOS"),
    "18": ("P10", ["lib/features/account", "lib/features/quran/data/quran_sync.dart"], ["test/account_identity_test.dart", "test/account_hub_test.dart", "test/haq_backup_test.dart", "test/quran_sync_test.dart"], "docs/account-and-backup-implementation.md", "OAuth والبريد والملفات الأصلية وإعداد الحسابات مؤجلة"),
    "19": ("P12", ["lib/features/assistant"], ["test/assistant_test.dart", "test/assistant_screens_test.dart"], "docs/assistant-subscription-implementation.md", "حسابات ومفاتيح ومنتجات متجر وSandbox وتقييم نموذج فعلي مؤجلة"),
    "20": ("P05", ["lib/features/sharing/share_card.dart", "lib/features/religious_content"], ["test/share_card_test.dart", "test/religious_content_test.dart"], "docs/content-and-sharing-implementation.md", "واجهة حفظ/مشاركة النظام على جهاز"),
}


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def head(root: Path) -> str:
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True).stdout.strip()


def safe_cell(value):
    text = str(value)
    return "'" + text if text.startswith(("=", "+", "-", "@")) else text


def write_csv(path: Path, rows: list[dict], columns: list[str]):
    with path.open("w", newline="", encoding="utf-8-sig") as output:
        writer = csv.DictWriter(output, fieldnames=columns)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: safe_cell("; ".join(map(str, row[k])) if isinstance(row[k], list) else row[k]) for k in columns})


def log_result(path: Path, kind: str) -> dict:
    content = path.read_text(encoding="utf-8-sig", errors="replace")
    if kind == "flutter":
        match = re.search(r"\+(\d+): All tests passed!", content)
        return {"path": str(path), "passed": bool(match), "tests": int(match.group(1)) if match else None}
    match = re.search(r"OK \((\d+) tests, (\d+) assertions\)", content)
    return {"path": str(path), "passed": bool(match), "tests": int(match.group(1)) if match else None, "assertions": int(match.group(2)) if match else None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--designs", type=Path, required=True)
    parser.add_argument("--backend", type=Path, required=True)
    parser.add_argument("--flutter-log", type=Path, required=True)
    parser.add_argument("--backend-log", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("docs/release-audit"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = (root / args.output).resolve()
    if not output.is_relative_to(root):
        raise ValueError("Audit output must stay inside the Flutter checkout")
    plan = read_json(args.plan / "خطة التنفيذ.json")
    states = read_json(args.plan / "تغطية حالات التصميم.json")["states"]
    if len(plan["features"]) != 50 or len(states) != 309 or len({s["code"] for s in states}) != 309:
        raise ValueError("Unexpected or duplicate reference coverage")
    missing = []
    features, designs = [], []
    for section, (_, sources, tests, document, _) in SECTIONS.items():
        for relative in [*sources, *tests, document]:
            if not (root / relative).exists():
                missing.append(f"{section}: {relative}")
    feature_by_code = {}
    for feature in plan["features"]:
        section = str(feature["module"]).zfill(2)
        _, sources, tests, document, gate = SECTIONS[section]
        features.append({"number": feature["number"], "title": feature["title"], "section": section, "phase": feature["phase"], "evidence_level": "source_and_section_tests", "sources": sources, "tests": tests, "document": document, "remaining_gate": gate, "design_codes": feature["design_codes"]})
        for code in feature["design_codes"]:
            feature_by_code.setdefault(code, []).append(feature["number"])
    for state in states:
        section = str(state["section"]).zfill(2)
        phase, sources, tests, document, gate = SECTIONS[section]
        for theme in ("light", "dark"):
            image = (args.designs / state[theme]).resolve()
            if not image.is_relative_to(args.designs.resolve()) or not image.is_file():
                missing.append(f"{state['code']}: {theme} image")
        designs.append({"code": state["code"], "title": state["title"], "section": section, "kind": state["kind"], "phase": phase, "evidence_level": "section_mapping_not_individual_visual_acceptance", "sources": sources, "tests": tests, "document": document, "feature_numbers": feature_by_code.get(state["code"], []), "remaining_gate": gate, "light": state["light"], "dark": state["dark"]})
    evidence = {"flutter": log_result(args.flutter_log.resolve(), "flutter"), "backend": log_result(args.backend_log.resolve(), "backend")}
    summary = {"generated_utc": datetime.now(timezone.utc).isoformat(), "flutter_head": head(root), "backend_head": head(args.backend.resolve()), "features": len(features), "design_states": len(designs), "section_counts": dict(Counter(d["section"] for d in designs)), "missing_evidence_paths": missing, "suite_evidence": evidence,
               "scope": "Read-only mapping of the original reference to current source and section tests. No individual 309-case visual/device acceptance, native build, staging, migration, purchase, provider request or release is certified.", "release_ready": False}
    output.mkdir(parents=True, exist_ok=True)
    (output / "audit.json").write_text(json.dumps({"summary": summary, "features": features, "design_states": designs}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_csv(output / "features.csv", features, ["number", "title", "section", "phase", "evidence_level", "sources", "tests", "document", "remaining_gate", "design_codes"])
    write_csv(output / "design-states.csv", designs, ["code", "title", "section", "kind", "phase", "evidence_level", "sources", "tests", "document", "feature_numbers", "remaining_gate", "light", "dark"])
    rows = "".join("<tr>" + "".join("<td>" + html.escape(str(row[key])) + "</td>" for key in ("code", "title", "section", "phase", "document", "remaining_gate")) + "</tr>" for row in designs)
    page = """<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>تدقيق تسليم حق</title><style>body{font:16px/1.8 system-ui;background:#f7f4e0;color:#102a43;margin:24px}main{max-width:1400px;margin:auto}input{padding:14px;width:min(500px,90%);border:1px solid #c7a45a;border-radius:12px}table{border-collapse:collapse;background:white;width:100%;margin-top:20px}td,th{padding:12px;border:1px solid #ddd;text-align:right}th{background:#102a43;color:white}.scroll{overflow:auto}.note{padding:18px;background:#fff4d8;border-radius:16px}td:nth-child(5){direction:ltr;text-align:left;font-size:13px}</style><main><h1>تدقيق تسليم حق — P13</h1><p>50 ميزة • 309 حالات تصميم • ربط بالمصدر واختبارات القسم.</p><p class="note">هذا فهرس تتبع للمصدر واختبارات الأقسام، وليس إثبات اختبار كل لقطة أو نجاح الهاتف والخادم والمتجر. الإطلاق لم يُعتمد بعد، والحسابات والمفاتيح وتجارب التفعيل مؤجلة بقرار المستخدم.</p><input id="search" placeholder="ابحث برمز الشاشة أو القسم أو الحالة…" aria-label="بحث"><div class="scroll"><table><thead><tr><th>الرمز</th><th>الحالة</th><th>القسم</th><th>المرحلة</th><th>دليل التنفيذ</th><th>التحقق المتبقي</th></tr></thead><tbody>""" + rows + """</tbody></table></div></main><script>document.getElementById('search').addEventListener('input',function(){const q=this.value.toLocaleLowerCase();document.querySelectorAll('tbody tr').forEach(r=>r.hidden=!r.textContent.toLocaleLowerCase().includes(q));});</script></html>"""
    (output / "index.html").write_text(page, encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=True))
    return 1 if missing or not all(r["passed"] for r in evidence.values()) else 0


if __name__ == "__main__":
    sys.exit(main())
