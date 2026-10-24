"""Validate native XML/plist files without running Flutter or building an app."""

from pathlib import Path
import plistlib
import sys
import xml.etree.ElementTree as ET


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    paths = sorted((root / "android" / "app" / "src").rglob("*.xml"))
    paths += sorted((root / "ios").rglob("*.plist"))
    failures = [
        f"Missing native configuration: {path}"
        for path in ("android/app/src/main/AndroidManifest.xml", "ios/Runner/Info.plist")
        if not (root / path).is_file()
    ]
    for path in paths:
        try:
            if path.suffix == ".plist":
                plistlib.loads(path.read_bytes())
            else:
                ET.parse(path)
        except (ValueError, ET.ParseError, plistlib.InvalidFileException) as error:
            failures.append(f"{path.relative_to(root)}: {error}")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"Validated {len(paths)} native XML/plist files; no app run or build.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
