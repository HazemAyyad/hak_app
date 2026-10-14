`page2.json` is the unmodified Quran.com public API response verified again on 2026-10-14:
https://api.quran.com/api/v4/verses/by_page/2?mushaf=19&words=true&word_fields=code_v2,text_qpc_hafs,page_number,line_number&per_page=50

The page has the five canonical verses 2:1..2:5. The V4 request was compared with the earlier physical-layout fixture: word glyph codes and line numbers were identical. The fixture verifies physical grouping against canonical Tanzil identifiers. Original QCF V4 colored glyphs belong to King Fahd Quran Complex. Runtime fonts are loaded from Quran Foundation into session memory; fonts are not bundled in this fixture or the application.
