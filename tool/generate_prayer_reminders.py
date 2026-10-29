"""Generate synthetic reminder assets. Never generates/imitates a muezzin.

Requires edge-tts and ffmpeg in a task-local runtime. Does not use app keys.
Palestinian wording uses the available Jordanian Arabic Taim neural voice;
it is not represented as an actual Palestinian human speaker.
"""
import argparse
import asyncio
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PRAYERS = {
    "fajr": ("الفَجْر", "Fajr"), "dhuhr": ("الظُّهْر", "Dhuhr"),
    "asr": ("العَصْر", "Asr"), "maghrib": ("المَغْرِب", "Maghrib"),
    "isha": ("العِشاء", "Isha"),
}
VARIANTS = {
    "ar-ps": ("ar-JO-TaimNeural", "قَرَّب وَقْت صَلاة {ar}. يَلَّا نْجَهِّز حالْنا لِلصَّلاة."),
    "ar-eg": ("ar-EG-ShakirNeural", "قَرَّب مِيعاد صَلاة {ar}. يَلَّا نِسْتَعِدّ لِلصَّلاة."),
    "ar-gulf": ("ar-SA-HamedNeural", "قَرَّب وَقْت صَلاة {ar}. خَلّنا نِسْتَعِدّ لِلصَّلاة."),
    "en": ("en-US-GuyNeural", "It is almost time for {en} prayer. Please get ready to pray."),
}


async def generate(args):
    sys.path.insert(0, str(Path(args.runtime).resolve()))
    import edge_tts
    staging = ROOT / "build/p23-generated-reminders"
    staging.mkdir(parents=True, exist_ok=True)
    output = ROOT / "assets/prayer/reminders"
    ios = ROOT / "ios/Runner/PrayerReminders"
    ios.mkdir(parents=True, exist_ok=True)
    manifest = {"type": "synthetic", "provider": "Microsoft Edge speech via edge-tts",
                "source": "https://github.com/rany2/edge-tts", "clips": {},
                "palestinian_note": "Palestinian wording using ar-JO-TaimNeural; not a human recording."}
    semaphore = asyncio.Semaphore(1)

    async def clip(variant, key, ar, en):
        voice, template = VARIANTS[variant]
        text = template.format(ar=ar, en=en)
        raw = staging / f"{variant}-{key}.mp3"
        target = output / variant / f"{key}.mp3"
        if not target.exists():
            async with semaphore:
                for attempt in range(3):
                    try:
                        await asyncio.wait_for(edge_tts.Communicate(text, voice, rate="-8%").save(str(raw)), 50)
                        break
                    except Exception:
                        if attempt == 2:
                            raise
                        await asyncio.sleep(2)
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            subprocess.run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(raw),
                        "-af", "loudnorm=I=-16:TP=-1.5:LRA=7", "-ar", "24000", "-b:a", "64k", str(target)], check=True)
        caf = ios / f"haq-reminder-{variant}-{key}.caf"
        subprocess.run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(target),
                        "-c:a", "pcm_s16le", str(caf)], check=True)
        manifest["clips"][f"{variant}/{key}"] = {"text": text, "voice": voice,
            "asset": target.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(target.read_bytes()).hexdigest()}
        print(f"{variant}/{key}: {target.stat().st_size} bytes", flush=True)

    await asyncio.gather(*(clip(v, k, ar, en) for v in VARIANTS for k, (ar, en) in PRAYERS.items()))
    (output / "provenance.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--ffmpeg", required=True)
    asyncio.run(generate(parser.parse_args()))
