"""Cache the official Hisn al-Muslim Arabic API for a reproducible offline build.

No network unless --refresh is explicitly supplied. Raw responses and checksums
are retained; the upstream JSON contains literal newlines inside string values.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import time
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'tool/religious_sources/hisn-api'
BASE = 'https://www.hisnmuslim.com/api/ar/'


def read(raw):
    return json.loads(raw.decode('utf-8-sig'), strict=False)


def fetch(name):
    for attempt in range(3):
        try:
            with urlopen(Request(BASE + name, headers={'User-Agent': 'Haq-Source-Archive/1.0'}), timeout=25) as response:
                raw = response.read(1024 * 1024 + 1)
            assert len(raw) <= 1024 * 1024
            data = read(raw)
            assert isinstance(data, dict) and len(data) == 1
            return raw
        except Exception:
            if attempt == 2:
                raise
            time.sleep(attempt + 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh', action='store_true')
    args = parser.parse_args()
    if not args.refresh:
        manifest = json.loads((DEST / 'manifest.json').read_text(encoding='utf-8'))
        for name, record in manifest['files'].items():
            assert hashlib.sha256((DEST / name).read_bytes()).hexdigest() == record['sha256'], name
        print(f"Verified {len(manifest['files'])} cached official source files; no network")
        return
    DEST.mkdir(parents=True, exist_ok=True)
    index = fetch('husn_ar.json')
    chapters = next(iter(read(index).values()))
    ids = [chapter['ID'] for chapter in chapters]
    assert len(ids) == len(set(ids)) and all(isinstance(i, int) and 1 <= i <= 200 for i in ids)
    files = {'husn_ar.json': index}
    with ThreadPoolExecutor(max_workers=4) as pool:
        for name, raw in zip((f'{i}.json' for i in ids), pool.map(lambda i: fetch(f'{i}.json'), ids)):
            records = next(iter(read(raw).values()))
            assert records and all(isinstance(r['ID'], int) and isinstance(r['REPEAT'], int) and 1 <= r['REPEAT'] <= 1000000 and r['ARABIC_TEXT'].strip() for r in records)
            files[name] = raw
    for name, raw in files.items():
        (DEST / name).write_bytes(raw)
    manifest = {'source': BASE + 'husn_ar.json', 'retrieved_at': datetime.now(timezone.utc).isoformat(),
                'files': {name: {'url': BASE + name, 'sha256': hashlib.sha256(raw).hexdigest()} for name, raw in files.items()}}
    (DEST / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Archived {len(ids)} official chapters with explicit REPEAT fields; {sum(len(v) for v in files.values())} bytes')


if __name__ == '__main__':
    main()
