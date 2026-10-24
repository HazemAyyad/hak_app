"""Report explicit parenthetical counts that disagree with official REPEAT.

Reports require source review. Compound instructions are not automatically
split or treated as an individual repeated phrase.
"""
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1] / 'tool/religious_sources/hisn-api'
words = {'ثلاث': 3, 'ثلاثا': 3, 'اربع': 4, 'سبع': 7, 'عشر': 10, 'مائة': 100, 'مئة': 100}
for path in sorted(root.glob('*.json')):
    if path.name in {'manifest.json', 'husn_ar.json'}:
        continue
    for row in next(iter(json.loads(path.read_text(encoding='utf-8-sig'), strict=False).values())):
        plain = re.sub('[\u0610-\u061a\u064b-\u065f\u0670\u0640]', '', row['ARABIC_TEXT']).replace('أ', 'ا').replace('إ', 'ا')
        explicit = [(word, count) for word, count in words.items() if re.search(r'[([]\s*' + word + r'\s+مر', plain)]
        if explicit and any(count != row['REPEAT'] for _, count in explicit):
            print(path.stem, row['ID'], row['REPEAT'], explicit)
