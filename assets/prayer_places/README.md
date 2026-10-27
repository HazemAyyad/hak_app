# Prayer location search data

`cities.json.gz` is a compact, local GeoNames cities1000 extract (WGS84),
with source city IDs, coordinates, IANA timezone IDs, population ranking,
English/ASCII names and Arabic-script search aliases. Country names use
Unicode CLDR 48 Arabic and English short names where available.

Source datasets retrieved on the date in `manifest.json`; each source and
the generated asset have SHA-256 receipts. Refresh with
`python tool/build_prayer_places.py` from the project root. Downloads remain
in ignored `build/prayer-geodata/`; remove only those cache files when a
fresh daily snapshot is intended. The generator does not access a database.

Arabic display names use language-tagged, nonhistoric Arabic entries from
GeoNames country-partitioned alternate-name exports for countries whose
source language list includes Arabic, plus GB. Other cities retain the
primary source name, while their Arabic-script aliases remain searchable.
The full global alternate-name export is deliberately unnecessary.

The dataset covers settlements over 1,000 people or administrative seats
through PPLA3. It does not include every village, address, or neighborhood.
The map supports exact points outside the search catalog. A nearby-city
label explicitly says "near"; it is not a claimed country/city boundary.
No prayer time is inferred from a country's center or the nearest city.

Data © [GeoNames](https://www.geonames.org/), licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
Modified here by selecting/reformatting fields and joining country names.
Country translations © Unicode, Inc.; see `UNICODE-LICENSE.txt`.
Source data is supplied as-is, with no completeness/accuracy guarantee.

The separate `timezone_finder` dependency embeds unmodified land timezone
boundaries. Time zone boundary data © OpenStreetMap contributors, available
under the [Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/1-0/).
Boundaries built by [Timezone Boundary Builder](https://github.com/evansiroky/timezone-boundary-builder).
The upstream package includes `LICENSE-DATA`, copied here as
`TIMEZONE-DATA-LICENSE.txt`; this app shows the attribution in the picker
and retains this notice with the redistributed asset docs.

Map tiles © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright).
Tile requests occur only after explicitly opening the map. Normal viewport
requests use an identifying User-Agent and flutter_map's HTTP-aware disk
cache. No bulk download, prefetch, autocomplete API, or location API is used.
