"""Build the small Palestinian neighborhood fallback from public GeoNames data.

No boundary polygons are supplied: these are nearby-name hints, not containment.
Python 3 standard library only; input ZIPs stay in ignored build/prayer-geodata.
"""
import gzip
import hashlib
import io
import json
import math
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'build/prayer-geodata'
OUTPUT = ROOT / 'assets/prayer_places'
CACHE.mkdir(parents=True, exist_ok=True)
sources = {
    'PS.zip': 'https://download.geonames.org/export/dump/PS.zip',
    'alternates-PS.zip': 'https://download.geonames.org/export/dump/alternatenames/PS.zip',
}
data = {}
for filename, url in sources.items():
    target = CACHE / filename
    if not target.exists():
        request = urllib.request.Request(url, headers={'User-Agent': 'HaqApp-Geodata-Refresh/1.0'})
        with urllib.request.urlopen(request, timeout=120) as response:
            target.write_bytes(response.read())
    data[filename] = target.read_bytes()

with zipfile.ZipFile(io.BytesIO(data['PS.zip'])) as archive:
    rows = [line.split('\t') for line in archive.read('PS.txt').decode('utf-8').splitlines()]
districts = [row for row in rows if len(row) == 19 and row[6:9] == ['P', 'PPLX', 'PS']]
ids = {row[0] for row in districts}
names = {}
with zipfile.ZipFile(io.BytesIO(data['alternates-PS.zip'])) as archive:
    for line in archive.read('PS.txt').decode('utf-8').splitlines():
        fields = line.split('\t')
        if len(fields) >= 8 and fields[1] in ids and fields[2] == 'ar' and fields[7] != '1':
            rank = (fields[4] == '1', fields[6] != '1', fields[5] == '1')
            if fields[1] not in names or rank > names[fields[1]][0]:
                names[fields[1]] = (rank, fields[3])

catalog = json.loads(gzip.decompress((OUTPUT / 'cities.json.gz').read_bytes()))
cities = [city for city in catalog['cities'] if city[4] == 'PS' and city[8] >= 10000]
def distance(row, city):
    dy = (float(row[4]) - city[5]) * 111.2
    dx = (float(row[5]) - city[6]) * 111.2 * math.cos(math.radians(float(row[4])))
    return math.hypot(dx, dy)

entries = []
for row in districts:
    parent = min(cities, key=lambda city: distance(row, city))
    entries.append({
        'id': int(row[0]), 'name': names.get(row[0], (None, row[1]))[1],
        'english': row[1], 'countryCode': 'PS',
        'city': parent[1] if distance(row, parent) <= 20 else None,
        'latitude': float(row[4]), 'longitude': float(row[5]),
    })
entries.sort(key=lambda item: item['id'])
payload = (json.dumps({'version': 1, 'districts': entries}, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
(OUTPUT / 'districts.json').write_bytes(payload)
manifest = {
    'version': 1, 'districtCount': len(entries),
    'sources': {name: {'url': sources[name], 'sha256': hashlib.sha256(value).hexdigest()} for name, value in data.items()},
    'assetSha256': hashlib.sha256(payload).hexdigest(), 'bytes': len(payload),
    'parentCitiesAssetSha256': hashlib.sha256((OUTPUT / 'cities.json.gz').read_bytes()).hexdigest(),
    'license': 'GeoNames CC BY 4.0',
    'scope': 'Palestinian PPLX neighborhood points; nearby city names are distance hints, not administrative boundaries.',
}
(OUTPUT / 'districts-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'districtCount': len(entries), 'bytes': len(payload), 'sheikhIjlin': [x for x in entries if x['id'] == 8041220]}))
