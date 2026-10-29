"""Generate three synthetic Arabic reminder announcements, never human recordings.

Uses the existing task-local edge-tts runtime. The app plays bundled MP3s
offline; no text or user data is sent from the phone.
"""
import argparse
import asyncio
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
TEXTS = {
    'morning': 'حانَ وَقْتُ أَذْكارِ الصَّباح. اِفْتَحْ أَذْكارَكَ، وَابْدَأْ يَوْمَكَ بِذِكْرِ الله.',
    'evening': 'حانَ وَقْتُ أَذْكارِ المَساء. خُذْ لَحَظاتٍ لِذِكْرِ الله، وَاقْرَأْ أَذْكارَ المَساء.',
    'sleep': 'حانَ وَقْتُ أَذْكارِ النَّوْم. قَبْلَ أَنْ تَنام، اِفْتَحْ أَذْكارَكَ، وَاخْتِمْ يَوْمَكَ بِذِكْرِ الله.',
}

async def generate(runtime):
    sys.path.insert(0, str(Path(runtime).resolve()))
    import edge_tts
    target = ROOT / 'assets/prayer/reminders'
    manifest = {'type': 'synthetic', 'provider': 'Microsoft Edge speech via edge-tts',
                'voice': 'ar-JO-TaimNeural', 'clips': {}}
    for kind, text in TEXTS.items():
        path = target / f'dhikr-{kind}.mp3'
        if not path.exists():
            temp = ROOT / f'build/p24-device/dhikr-{kind}.part.mp3'
            await asyncio.wait_for(edge_tts.Communicate(text, manifest['voice'], rate='-8%').save(str(temp)), 50)
            temp.replace(path)
        manifest['clips'][kind] = {'text': text, 'asset': path.relative_to(ROOT).as_posix(),
                                   'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        print(f'{kind}: {path.stat().st_size} bytes', flush=True)
    (target / 'dhikr-provenance.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime', required=True)
    asyncio.run(generate(parser.parse_args().runtime))
