`page2.json` is the unmodified Quran.com public API response verified again on 2026-10-14:
https://api.quran.com/api/v4/verses/by_page/2?mushaf=19&words=true&word_fields=code_v2,text_qpc_hafs,page_number,line_number&per_page=50

The page has the five canonical verses 2:1..2:5. The V4 request was compared with the earlier physical-layout fixture: word glyph codes and line numbers were identical. The fixture verifies physical grouping against canonical Tanzil identifiers. Original QCF V4 colored glyphs belong to King Fahd Quran Complex. Runtime fonts are loaded from Quran Foundation into session memory; fonts are not bundled in this fixture or the application.

`offline001.svg` and `offline001.json` are unmodified page 1 artwork and ayah polygons from Quran.ws quran-svg v1.1.1, pinned to revision `3ff27b46cecb0c0519d77531d9c868a579d1f623`:

- [Original SVG](https://raw.githubusercontent.com/quran-ws/quran-svg/3ff27b46cecb0c0519d77531d9c868a579d1f623/mushafs/hafs/kfqc/svg/001.svg): 185309 bytes, Git blob `38a3ee9fc4880258b2aec899e5189474219044fa`.
- [Original metadata](https://raw.githubusercontent.com/quran-ws/quran-svg/3ff27b46cecb0c0519d77531d9c868a579d1f623/mushafs/hafs/kfqc/json/001.json): 1424 bytes, Git blob `7e31e76a24b4e2c56099f35d65a894307238e160`.

Metadata copyright 2026 Quran.ws, licensed CC BY 4.0. Original Mushaf al-Madinah artwork belongs to King Fahd Glorious Quran Printing Complex. Their respective terms are preserved in `assets/quran/offline-page-LICENSE.txt` and `assets/quran/offline-page-NOTICE.md`. This fixture tests actual SVG rendering, ayah hit detection, and offline playback of the page without a font or content request. No scripture or polygon data has been edited.
