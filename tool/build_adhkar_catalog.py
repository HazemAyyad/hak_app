"""Build daily dhikr from archived official Hisn records and canonical Haq Quran.

No network and no count inferred from a mockup. Explicit source corrections are
listed below; the original text and raw source checksums remain available.
"""
import argparse
from difflib import SequenceMatcher
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tool/religious_sources/hisn-api'


def read(name):
    return json.loads((SOURCE / name).read_text(encoding='utf-8-sig'), strict=False)


def normalized(text):
    chars, indexes = [], []
    for index, char in enumerate(text):
        if '\u0621' <= char <= '\u064a' and char != '\u0640' or char == '\u0671':
            char = {'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا', 'ى': 'ي', 'ؤ': 'و', 'ئ': 'ي'}.get(char, char)
            # Orthographic/alif differences locate a block only inside its
            # explicitly reviewed verse keys. Output is always canonical text.
            if char in 'اء':
                continue
            if char == 'و' and chars and chars[-1] == char:
                continue
            chars.append(char)
            indexes.append(index)
    return ''.join(chars), indexes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend-root', type=Path)
    args = parser.parse_args()
    manifest = read('manifest.json')
    for name, entry in manifest['files'].items():
        assert hashlib.sha256((SOURCE / name).read_bytes()).hexdigest() == entry['sha256'], name
    quran = json.loads((ROOT / 'assets/quran/quran.json').read_text(encoding='utf-8'))
    verses = {v['key']: v['text'] for v in quran['verses']}
    surahs = lambda: [[f'{s}:{a}' for a in range(1, {112: 4, 113: 5, 114: 6}[s] + 1)] for s in [112, 113, 114]]
    scripture = {4: [[f'3:{a}' for a in range(190, 201)]], 50: [['23:14']], 70: surahs(), 71: [['2:255']],
                 74: [['3:159']], 75: [['2:255']], 76: surahs(), 99: surahs(), 100: [['2:255']],
                 101: [['2:285', '2:286']], 110: [['32:1']], 135: [['57:3']],
                 206: [['43:13', '43:14']], 207: [['43:13', '43:14']], 235: [['2:201']], 236: [['2:158']]}
    records, chapters = {}, {}
    for chapter in next(iter(read('husn_ar.json').values())):
        number, title = chapter['ID'], chapter['TITLE']
        ids = []
        for raw in next(iter(read(f'{number}.json').values())):
            identity = raw['ID']
            key = f'hisn-api-{identity:03}'
            text = raw['ARABIC_TEXT']
            blocks = list(re.finditer('﴿(.*?)﴾', text, re.S))
            mapping = scripture.get(identity, [])
            assert len(blocks) == len(mapping), (identity, len(blocks), len(mapping))
            replacements = []
            citations = []
            for block, keys in zip(blocks, mapping):
                canonical = ' '.join(verses[k] for k in keys)
                needle, _ = normalized(block.group(1))
                haystack, positions = normalized(canonical)
                if identity in {4, 70, 71, 75, 76, 99, 100, 101, 110, 135}:
                    # These reviewed mappings quote entire verses. Do not copy
                    # upstream spelling omissions into Haq's canonical Quran.
                    assert SequenceMatcher(None, needle, haystack, autojunk=False).ratio() > .9, identity
                    replacements.append((block.start(1), block.end(1), canonical))
                    citations.append({'keys': keys, 'text': canonical})
                    continue
                start = haystack.find(needle)
                assert start >= 0, (identity, keys, needle[:50])
                first, last = positions[start], positions[start + len(needle) - 1] + 1
                while first > 0 and not canonical[first - 1].isspace():
                    first -= 1
                while last < len(canonical) and not canonical[last].isspace():
                    last += 1
                exact = canonical[first:last]
                assert exact in canonical
                replacements.append((block.start(1), block.end(1), exact))
                citations.append({'keys': keys, 'text': exact})
            for first, last, replacement in reversed(replacements):
                text = text[:first] + replacement + text[last:]
            # Official REPEAT for #83 is 1, but its own text and the existing
            # approved Hisn source explicitly say seven. Retain this correction.
            target = {83: 7, 130: 3, 148: 7}.get(identity, raw['REPEAT'])
            audio = raw['AUDIO'].replace('http://', 'https://', 1)
            if not re.fullmatch(r'https://www\.hisnmuslim\.com/audio/ar/[0-9]+\.mp3', audio):
                assert identity == 153 and audio.endswith('/.mp3')
                audio = None  # The official source supplies no recording here.
            record = {'id': key, 'source_id': identity, 'chapter': number, 'title': title,
                      'text': text.strip(), 'target': target, 'audio_url': audio,
                      'source': f'حصن المسلم • الباب {number} • الذكر {identity}',
                      'source_url': f'https://www.hisnmuslim.com/api/ar/{number}.json',
                      'haq_content_id': f'hisn-{number:03}', 'scripture': citations}
            assert key not in records
            records[key] = record
            ids.append(key)
        chapters[number] = {'id': f'hisn-chapter-{number:03}', 'title': title, 'item_ids': ids}
    definition = [
        ('morning', 'أذكار الصباح', 'sun', [27]), ('evening', 'أذكار المساء', 'moon', [27]),
        ('after-prayer', 'أذكار بعد الصلاة', 'mosque', [25]), ('prayer', 'أذكار الصلاة', 'mosque', list(range(16, 25)) + [26]),
        ('sleep', 'أذكار النوم', 'moon', [28, 29, 30]), ('adhan', 'أذكار سماع الأذان', 'leaf', [15]),
        ('mosque', 'أذكار المسجد', 'mosque', [12, 13, 14]), ('awakening', 'أذكار الاستيقاظ', 'sun', [1]),
        ('home', 'أذكار المنزل', 'home', [10, 11]), ('wudu', 'أذكار الوضوء', 'leaf', [8, 9]),
        ('toilet', 'أذكار الخلاء', 'leaf', [6, 7]), ('food', 'أذكار الطعام والشراب', 'leaf', list(range(68, 77))),
        ('travel', 'أذكار السفر', 'compass', [95, 96, 97, 99, 100, 101, 102, 103, 104, 105]),
    ]
    allocated = {c for _, _, _, cs in definition for c in cs}
    definition.append(('other', 'أذكار أخرى', 'leaf', sorted(set(chapters) - allocated)))
    groups = []
    for key, title, icon, numbers in definition:
        items = [item for n in numbers for item in chapters[n]['item_ids']]
        # The source explicitly distinguishes these morning/evening-only texts.
        exclude = {'hisn-api-097'} if key == 'morning' else {'hisn-api-093', 'hisn-api-094', 'hisn-api-095'} if key == 'evening' else set()
        groups.append({'id': f'daily:{key}', 'title': title, 'icon': icon,
                       'chapter_ids': numbers, 'item_ids': [i for i in items if i not in exclude]})
    payload = {'schema_version': 1, 'version': '2026-10-24.1', 'source': manifest['source'], 'source_sha256': manifest['files']['husn_ar.json']['sha256'],
               'quran_source': {'url': quran.get('sourceUrl', 'https://tanzil.net'), 'license': quran['textLicense']},
               'groups': groups, 'chapters': list(chapters.values()), 'items': list(records.values()),
               'corrections': [{'id': f'hisn-api-{i:03}', 'upstream_repeat': 1, 'target': n,
                                'evidence': 'التكرار منصوص عليه صراحة في نص الذكر الأصلي نفسه.'} for i, n in {83: 7, 130: 3, 148: 7}.items()]}
    targets = [ROOT / 'assets/religious/adhkar.json']
    if args.backend_root:
        backend = args.backend_root.resolve(strict=True)
        assert (backend / 'composer.json').is_file() and (backend / 'resources/religious').is_dir()
        targets.append(backend / 'resources/religious/adhkar.json')
    output = json.dumps(payload, ensure_ascii=False, indent=2) + '\n'
    for target in targets:
        target.write_text(output, encoding='utf-8')
    print(f'Built {len(groups)} daily groups, {len(chapters)} chapters, {len(records)} sourced dhikr; canonical Quran blocks verified')


if __name__ == '__main__':
    main()
