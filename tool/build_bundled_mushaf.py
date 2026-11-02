"""Build a lossless, offline Mushaf from pinned source bytes.

Font outlines and palettes are never edited. Brotli compresses each original
font losslessly; decoding must reproduce its original SHA-256.
Only the required page is restored in memory by the Flutter reader.
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.request import Request, urlopen
import argparse
import csv
import gzip
import hashlib
import io
import json
import struct
import time
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'build/mushaf-build-tools'))
import brotli
from collections import defaultdict

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'build/bundled-mushaf-source'
OUTPUT = ROOT / 'assets/quran/mushaf'
FONT_BASE = 'https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/ttf'
LAYOUT_REVISION = 'f84ccb5688d5404748a0d38e6c53e09df4469ec9'
SOURCES = {
    'words.csv': f'https://raw.githubusercontent.com/hussainsajib/qpc-v4-mushaf-bundle/{LAYOUT_REVISION}/data/words.csv',
    'lines.csv': f'https://raw.githubusercontent.com/hussainsajib/qpc-v4-mushaf-bundle/{LAYOUT_REVISION}/data/page_lines.csv',
    'mapping.csv': f'https://raw.githubusercontent.com/hussainsajib/qpc-v4-mushaf-bundle/{LAYOUT_REVISION}/data/qpc_mapping.csv',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def acquire(name, url, expected=None):
    path = CACHE / name
    if path.exists():
        data = path.read_bytes()
        if expected is None or digest(data) == expected:
            return data
        raise ValueError(f'Cached source differs: {name}')
    for attempt in range(3):
        try:
            request = Request(url, headers={'User-Agent': 'HaqMushafBuild/1.0', 'Accept-Encoding': 'identity'})
            with urlopen(request, timeout=45) as response:
                data = response.read()
            if expected is not None and digest(data) != expected:
                raise ValueError(f'Source digest differs: {name}')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            return data
        except Exception:
            if attempt == 2:
                raise
            time.sleep(2 * (attempt + 1))


def acquire_fonts():
    receipts = json.loads((ROOT / 'tool/quran_sources/mushaf-fonts.json').read_text())
    def get(row):
        page = row['page']
        data = acquire(f'fonts/p{page}.ttf', row['url'], row['sha256'])
        assert len(data) == row['bytes']
        return page
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(get, row) for row in receipts]
        for count, future in enumerate(as_completed(futures), 1):
            future.result()
            if count % 50 == 0 or count == 604:
                print(f'Verified {count}/604 original fonts', flush=True)
    return receipts


def pack_fonts(receipts):
    def pack(row):
        page = row['page']
        raw = (CACHE / f'fonts/p{page}.ttf').read_bytes()
        assert digest(raw) == row['sha256']
        target = OUTPUT / f'font-{page:03}.qbr'
        packed = target.read_bytes() if target.exists() else b''
        if not packed or brotli.decompress(packed) != raw:
            packed = brotli.compress(raw, quality=11, mode=brotli.MODE_FONT)
        assert brotli.decompress(packed) == raw
        target.write_bytes(packed)
        return len(packed)
    with ThreadPoolExecutor(max_workers=8) as pool:
        sizes = list(pool.map(pack, receipts))
    return {'fonts': [[r['bytes'], r['sha256']] for r in receipts]}, {
        'original_font_bytes': sum(row['bytes'] for row in receipts),
        'packed_font_bytes': sum(sizes),
        'font_count': len(receipts),
        'compression': 'Brotli 1.2.0, quality 11, FONT mode; byte-identical TTF restoration',
    }


def pack_pages():
    def rows(name):
        return list(csv.DictReader(io.StringIO((CACHE / name).read_text(encoding='utf8'))))
    words = {int(row['id']): row for row in rows('words.csv')}
    mappings = {int(row['word_id']): row for row in rows('mapping.csv')}
    assert len(words) == len(mappings) == 83668
    pages = defaultdict(list)
    seen, verses = set(), set()
    for line in rows('lines.csv'):
        if line['line_type'] != 'ayah':
            continue
        page, number = int(line['page_number']), int(line['line_number'])
        for word_id in range(int(line['first_word_id']), int(line['last_word_id']) + 1):
            assert word_id not in seen
            seen.add(word_id)
            word, mapping = words[word_id], mappings[word_id]
            assert int(mapping['page_number']) == page
            key = f"{word['surah']}:{word['ayah']}"
            verses.add(key)
            glyphs = ''.join(chr(int(cp)) for cp in mapping['code'].split())
            if word['text'].startswith('۞ '):
                glyphs = glyphs[0] + ' ' + glyphs[1:]
            pages[page].append([key, int(word['word']), number,
                                glyphs, word['text']])
    assert len(seen) == 83668 and len(verses) == 6236
    assert set(pages) == set(range(1, 605))
    specs = []
    for page in range(1, 605):
        # Verify that both upstream page/word assignments and the existing
        # Quran.com fixture yield exactly the same glyphs, words and lines.
        if page in (2, 42):
            fixture = ROOT / f'build/quran-fixtures/page{page}{"-v4" if page == 2 else ""}.json'
            if fixture.exists():
                expected = json.loads(fixture.read_text(encoding='utf8'))
                flat = [[v['verse_key'], w['position'], w['line_number'], w['code_v2'], w['text_qpc_hafs']]
                        for v in expected['verses'] for w in v['words'] if w['page_number'] == page]
                assert pages[page] == flat, f'Existing page {page} reference differs'
        raw = json.dumps(pages[page], ensure_ascii=False, separators=(',', ':')).encode()
        packed = gzip.compress(raw, compresslevel=9, mtime=0)
        (OUTPUT / f'page-{page:03}.qgz').write_bytes(packed)
        specs.append([len(raw), digest(raw)])
    return specs, {'page_count': 604, 'word_count': len(seen), 'verse_count': len(verses),
                   'packed_page_bytes': sum((OUTPUT / f'page-{p:03}.qgz').stat().st_size for p in pages)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--acquire-only', action='store_true')
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    receipts = acquire_fonts()
    hashes = json.loads((ROOT / 'tool/quran_sources/mushaf-layout-sources.json').read_text())
    for name, url in SOURCES.items():
        acquire(name, url, hashes[name])
    if args.acquire_only:
        return
    OUTPUT.mkdir(parents=True, exist_ok=True)
    index, report = pack_fonts(receipts)
    index['pages'], page_report = pack_pages()
    report.update(page_report)
    index['version'] = 2
    (OUTPUT / 'font-index.qgz').write_bytes(gzip.compress(json.dumps(index, separators=(',', ':')).encode(), mtime=0))
    report['packed_index_bytes'] = (OUTPUT / 'font-index.qgz').stat().st_size
    (CACHE / 'size-report.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
