"""Fetch the exact Hisn Muslim recordings already referenced by Haq's catalog.

Build-time only. Decode every file, retain its source/digest, and generate
ordered playlists matching the three daily groups. Each source recording is
played once; devotional repetition counts remain in the reader.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

def prepare(runtime):
    sys.path.insert(0, str(Path(runtime).resolve()))
    import av
    catalog_path = ROOT / 'assets/religious/adhkar.json'
    catalog = json.loads(catalog_path.read_text(encoding='utf-8'))
    items = {item['id']: item for item in catalog['items']}
    groups = {group['id'].split(':')[1]: group['item_ids'] for group in catalog['groups']
              if group['id'] in ('daily:morning', 'daily:evening', 'daily:sleep')}
    keys = sorted({key for group in groups.values() for key in group})
    target = ROOT / 'assets/prayer/dhikr_recitations'
    target.mkdir(parents=True, exist_ok=True)

    def recording(key):
        item = items[key]
        url = item['audio_url']
        assert re.fullmatch(r'https://www\.hisnmuslim\.com/audio/ar/[0-9]+\.mp3', url)
        path = target / f'{key}.mp3'
        if not path.exists():
            for attempt in range(3):
                try:
                    endpoint = url if attempt != 1 else url.replace('www.hisnmuslim.com', 'hisnmuslim.com')
                    request = urllib.request.Request(endpoint, headers={'User-Agent': 'Haq-Catalog-Audio/1.0'})
                    with urllib.request.urlopen(request, timeout=45) as response:
                        assert re.match(r'https://(www\.)?hisnmuslim\.com/', response.geturl())
                        data = response.read(10000001)
                    break
                except Exception:
                    if attempt == 2:
                        raise
                    print(f'{key}: retry {attempt + 1}', flush=True)
                    time.sleep(1)
            assert 1000 <= len(data) <= 10000000
            temp = path.with_suffix('.part')
            temp.write_bytes(data)
            temp.replace(path)
        with av.open(str(path)) as media:
            duration = sum(frame.samples / frame.sample_rate for frame in media.decode(media.streams.audio[0]))
        assert 1 < duration < 360
        print(f'{key}: {duration:.2f}s / {path.stat().st_size} bytes', flush=True)
        return key, {'asset': path.relative_to(ROOT).as_posix(), 'source': url,
                     'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'duration_seconds': round(duration, 3),
                     'play_count': 1, 'reader_target': item['target']}

    with ThreadPoolExecutor(max_workers=4) as pool:
        recordings = dict(pool.map(recording, keys))
    manifest = {'schema_version': 1, 'source': 'https://www.hisnmuslim.com/api/ar/husn_ar.json',
                'catalog_sha256': hashlib.sha256(catalog_path.read_bytes()).hexdigest(),
                'policy': 'Each unmodified source recording once, no automatic completion events.',
                'groups': groups, 'recordings': recordings}
    (ROOT / 'assets/prayer/reminders/dhikr-playlists.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'recordings': len(recordings), 'bytes': sum((ROOT / r['asset']).stat().st_size for r in recordings.values()),
                      'group_seconds': {key: round(sum(recordings[item]['duration_seconds'] for item in values), 2) for key, values in groups.items()}}), flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime', required=True)
    prepare(parser.parse_args().runtime)
