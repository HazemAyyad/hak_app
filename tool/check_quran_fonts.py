"""Check unchanged bundled font receipts and cmap coverage of canonical Quran.

Reads public OpenType table metadata only; never converts or modifies fonts.
"""
import bisect
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]


def glyph_lookup(data):
    tables = {}
    for i in range(struct.unpack_from('>H', data, 4)[0]):
        tag, _, offset, length = struct.unpack_from('>4sIII', data, 12 + 16 * i)
        tables[tag] = (offset, length)
    base, _ = tables[b'cmap']
    records = []
    for i in range(struct.unpack_from('>H', data, base + 2)[0]):
        platform, _, offset = struct.unpack_from('>HHI', data, base + 4 + 8 * i)
        if platform in (0, 3):
            records.append(base + offset)

    def contains(cp):
        for q in records:
            fmt = struct.unpack_from('>H', data, q)[0]
            if fmt == 4 and cp <= 65535:
                n = struct.unpack_from('>H', data, q + 6)[0] // 2
                ends = struct.unpack_from('>' + str(n) + 'H', data, q + 14)
                i = bisect.bisect_left(ends, cp)
                if i == n:
                    continue
                starts = q + 16 + 2 * n
                start = struct.unpack_from('>H', data, starts + 2 * i)[0]
                if cp < start:
                    continue
                delta = struct.unpack_from('>h', data, starts + 2 * n + 2 * i)[0]
                r = starts + 4 * n + 2 * i
                offset = struct.unpack_from('>H', data, r)[0]
                glyph = cp if offset == 0 else struct.unpack_from('>H', data, r + offset + 2 * (cp - start))[0]
                if glyph and ((glyph + delta) & 65535):
                    return True
            if fmt == 12:
                n = struct.unpack_from('>I', data, q + 12)[0]
                for i in range(n):
                    start, end, glyph = struct.unpack_from('>III', data, q + 16 + i * 12)
                    if start <= cp <= end and glyph + cp - start:
                        return True
        return False
    return contains


def texts(value):
    if isinstance(value, dict):
        if isinstance(value.get('text'), str):
            yield value['text']
        for child in value.values():
            yield from texts(child)
    elif isinstance(value, list):
        for child in value:
            yield from texts(child)


canonical = list(texts(json.loads((ROOT / 'assets/quran/quran.json').read_text(encoding='utf-8'))))
characters = {ord(c) for text in canonical for c in text if not c.isspace()}
manifest = json.loads((ROOT / 'docs/quran-fonts.json').read_text(encoding='utf-8'))
results = []
for font in manifest['fonts']:
    data = (ROOT / 'assets/fonts' / font['file']).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    assert digest == font['sha256'], font['file'] + ' checksum'
    assert (ROOT / 'assets/fonts' / font['license']).is_file()
    has_glyph = glyph_lookup(data)
    missing = [f'U+{cp:04X}' for cp in sorted(characters) if not has_glyph(cp)]
    results.append({'font': font['family'], 'characters': len(characters), 'missing': missing})
report = {'verses': len(canonical), 'fonts': results}
(ROOT / 'build/p20-font-coverage.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report))
assert len(canonical) == 6236 and all(not row['missing'] for row in results)
