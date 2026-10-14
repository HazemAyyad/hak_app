"""Build the shared, unmodified Tanzil text dataset from official XML sources."""
import argparse
import bisect
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET


def build(source_dir):
    text_path = source_dir / 'quran-uthmani.xml'
    metadata_path = source_dir / 'quran-metadata.xml'
    search_path = source_dir / 'quran-simple-clean.xml'
    raw = text_path.read_text(encoding='utf-8')
    copyright_notice = raw.split('<!--', 1)[1].split('-->', 1)[0].strip()
    text = ET.fromstring(raw)
    metadata = ET.parse(metadata_path).getroot()
    search_raw = search_path.read_text(encoding='utf-8')
    search_source = ET.fromstring(search_raw)
    search_license = search_raw.split('<!--', 1)[1].split('-->', 1)[0].strip()
    chapters = list(metadata.find('suras'))
    assert len(chapters) == len(list(text)) == 114
    starts = {int(c.attrib['index']): int(c.attrib['start']) for c in chapters}

    def boundaries(tag):
        rows = []
        for item in metadata.find(tag):
            surah, ayah = int(item.attrib['sura']), int(item.attrib['aya'])
            rows.append((starts[surah] + ayah, int(item.attrib['index'])))
        return rows

    pages, parts = boundaries('pages'), boundaries('juzs')
    assert len(pages) == 604 and len(parts) == 30

    def partition(rows, number):
        return rows[bisect.bisect_right([x[0] for x in rows], number) - 1][1]

    verses, surahs = [], []
    for source, chapter, search_chapter in zip(text, chapters, search_source):
        number = int(chapter.attrib['index'])
        assert int(source.attrib['index']) == number
        assert len(list(source)) == int(chapter.attrib['ayas'])
        assert len(list(search_chapter)) == len(list(source))
        for index, aya in enumerate(source, 1):
            assert int(aya.attrib['index']) == index
            ordinal = starts[number] + index
            verses.append(dict(key=f'{number}:{index}', surah=number,
                               ayah=index, text=aya.attrib['text'],
                               searchText=search_chapter[index - 1].attrib['text'],
                               page=partition(pages, ordinal),
                               juz=partition(parts, ordinal)))
        surahs.append(dict(id=number, name=chapter.attrib['name'],
                           revelation=chapter.attrib['type'],
                           ayahCount=int(chapter.attrib['ayas']),
                           start=starts[number],
                           startPage=partition(pages, starts[number] + 1),
                           basmala=source[0].attrib.get('bismillah')))
    assert len(verses) == 6236
    juzs = []
    for index, (start, number) in enumerate(parts):
        end = parts[index + 1][0] - 1 if index < 29 else len(verses)
        first, last = verses[start - 1], verses[end - 1]
        juzs.append(dict(id=number, startKey=first['key'], endKey=last['key'],
                         startSurah=first['surah'], endSurah=last['surah'],
                         startAyah=first['ayah'], endAyah=last['ayah'],
                         startPage=first['page'], ayahCount=end - start + 1))
    return dict(version='tanzil-uthmani-1.1-metadata-1.0',
                source='Tanzil Project', sourceUrl='https://tanzil.net',
                textLicense=copyright_notice,
                searchTextLicense=search_license,
                metadataLicense=metadata.attrib.get('license'),
                sourceHashes={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in (text_path, metadata_path, search_path)},
                surahs=surahs, juzs=juzs, verses=verses)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, action='append', required=True)
    args = parser.parse_args()
    dataset = build(args.source_dir)
    payload = (json.dumps(dataset, ensure_ascii=False, separators=(',', ':')) + '\n').encode('utf-8')
    for output in args.output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(payload)
    print(f"Verified {len(dataset['surahs'])} surahs, {len(dataset['verses'])} verses, 30 juz, 604 pages")
