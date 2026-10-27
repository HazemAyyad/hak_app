"""Refresh the bundled GeoNames city search (public data; no API key).

Raw downloads stay in ignored build/. Output is deterministic for these inputs.
Run with Python 3. No third-party Python dependencies.
"""
import datetime
from concurrent.futures import ThreadPoolExecutor
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'build' / 'prayer-geodata'
OUTPUT = ROOT / 'assets' / 'prayer_places'
CACHE.mkdir(parents=True, exist_ok=True)
OUTPUT.mkdir(parents=True, exist_ok=True)
SOURCES = {
    'cities1000.zip': 'https://download.geonames.org/export/dump/cities1000.zip',
    'countryInfo.txt': 'https://download.geonames.org/export/dump/countryInfo.txt',
    'territories.json': 'https://raw.githubusercontent.com/unicode-org/cldr-json/48.0.0/cldr-json/cldr-localenames-full/main/ar/territories.json',
    'territories-en.json': 'https://raw.githubusercontent.com/unicode-org/cldr-json/48.0.0/cldr-json/cldr-localenames-full/main/en/territories.json',
    'UNICODE-LICENSE.txt': 'https://raw.githubusercontent.com/unicode-org/cldr-json/48.0.0/LICENSE',
}


def fetch(name):
    path = CACHE / name
    if not path.exists():
        req = urllib.request.Request(SOURCES[name], headers={'User-Agent': 'HaqApp-Geodata-Refresh/1.0'})
        with urllib.request.urlopen(req, timeout=180) as response:
            path.write_bytes(response.read())
    return path.read_bytes()


raw = {name: fetch(name) for name in SOURCES}
arabic = json.loads(raw['territories.json'])['main']['ar']['localeDisplayNames']['territories']
english = json.loads(raw['territories-en.json'])['main']['en']['localeDisplayNames']['territories']
countries = {}
arabic_countries = []
for line in raw['countryInfo.txt'].decode('utf-8').splitlines():
    if not line or line.startswith('#'):
        continue
    parts = line.split('\t')
    code = parts[0]
    countries[code] = [arabic.get(code + '-alt-short', arabic.get(code, parts[4])), parts[4], english.get(code + '-alt-short', english.get(code, parts[4]))]
    if any(language.split('-')[0] == 'ar' for language in parts[15].split(',')):
        arabic_countries.append(code)

# Country-partitioned language-tagged names avoid downloading the ~200 MB
# global alternate-name export. Elsewhere use the primary source city name;
# all Arabic-script aliases remain searchable regardless of display language.
for code in sorted(set(arabic_countries + ['GB'])):
    SOURCES[f'alternates-{code}.zip'] = f'https://download.geonames.org/export/dump/alternatenames/{code}.zip'
alternate_files = [name for name in SOURCES if name.startswith('alternates-')]
with ThreadPoolExecutor(max_workers=4) as pool:
    for name, content in zip(alternate_files, pool.map(fetch, alternate_files)):
        raw[name] = content

cities = []
with zipfile.ZipFile(io.BytesIO(raw['cities1000.zip'])) as archive:
    for line in archive.read('cities1000.txt').decode('utf-8').splitlines():
        p = line.split('\t')
        if len(p) != 19 or p[8] not in countries or not p[17]:
            continue
        # The convenience alias field has no language tags. Keep Arabic-script
        # aliases for matching; a city without one retains its source name.
        aliases = list(dict.fromkeys(a for a in p[3].split(',') if re.search('[\u0600-\u06ff]', a)))
        cities.append([int(p[0]), p[1], p[1], p[2], p[8], float(p[4]), float(p[5]), p[17], int(p[14]), aliases])
cities.sort(key=lambda row: (-row[8], row[0]))
by_id = {str(city[0]): city for city in cities}
preferred = {}
for filename in alternate_files:
    with zipfile.ZipFile(io.BytesIO(raw[filename])) as archive:
        with archive.open(filename.removeprefix('alternates-').replace('.zip', '.txt')) as stream:
            for line in io.TextIOWrapper(stream, encoding='utf-8'):
                p = line.rstrip('\n').split('\t')
                if len(p) < 8 or p[2] != 'ar' or p[1] not in by_id or p[7] == '1':
                    continue
                # Language-tagged Arabic names, avoiding Urdu/Persian/Kurdish
                # aliases which also use Arabic script. Prefer official names.
                rank = (p[4] == '1', p[6] != '1', p[5] == '1')
                if p[1] not in preferred or rank > preferred[p[1]][0]:
                    preferred[p[1]] = (rank, p[3])
for city_id, city in by_id.items():
    city[1] = preferred.get(city_id, (None, city[2]))[1]
payload = json.dumps({'version': 1, 'countries': countries, 'cities': cities}, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
compressed = gzip.compress(payload, compresslevel=9, mtime=0)
(OUTPUT / 'cities.json.gz').write_bytes(compressed)
(OUTPUT / 'UNICODE-LICENSE.txt').write_bytes(raw['UNICODE-LICENSE.txt'])
manifest = {
    'retrieved': datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
    'cityCount': len(cities), 'countryCount': len(countries),
    'sources': {name: {'url': SOURCES[name], 'sha256': hashlib.sha256(value).hexdigest()} for name, value in raw.items()},
    'assetSha256': hashlib.sha256(compressed).hexdigest(),
    'uncompressedBytes': len(payload), 'compressedBytes': len(compressed),
    'license': 'GeoNames CC BY 4.0; Unicode License V3 for country translations',
    'scope': 'GeoNames cities1000: settlements over 1000 residents or administrative seats through PPLA3; not every village/address.',
}
(OUTPUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print(json.dumps({key: manifest[key] for key in ['cityCount', 'countryCount', 'compressedBytes']}))
