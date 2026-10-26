# Place profile: interface (T1), format 1

Owner: T1 Place profiles. Readers: T3 Sound of place now, T4 Climate look and T8 Regional kits later.
Change requests go to T1 through the coordinator. Adding a field is free; renaming or removing one bumps `format`.

## Where it lives

- One profile per cell (the 0.25 degree grid, "ROW_COL" as in the world index), every cell in the index, empty ones too.
- World repo: `profile/cROW_COL.json`, its hash (first 12 of the sha1 of the text) in index.json under `"profiles"`,
  exactly like `streams` and `trees`. Cell zips and road hashes are untouched.
- Bundled regions (Dales, Shodoshima): `data/profiles/<region id>.json` in the game repo (not inside the region's
  folder, which would change its hash).
- Test fixtures in the game repo: `tests/fixtures/profiles/c576_712.json` (Dales) and `c484_688.json` (High Atlas).
  Copies here: `profile-example-dales.json`, `profile-example-atlas.json`. The numbers are realistic but hand-made.

## Reading it in the game (scripts/place_profile.gd, class PlaceProfile)

```
PlaceProfile.of_cell(cell: Vector2i) -> Dictionary          # cached; fetched if needed (worker); guessed if none
PlaceProfile.at(lat: float, lon: float) -> Dictionary        # of_cell(RealRegion.cell_of(lat, lon))
PlaceProfile.of_region(region: RealRegion) -> Dictionary     # a bundled region's own, else the cell at the frame middle
PlaceProfile.guess(lat: float, lon: float, meta := {}) -> Dictionary   # no network; meta = a region.json if you have it
PlaceProfile.parse(d: Dictionary) -> Dictionary              # fills any missing field with its default (below)
PlaceProfile.month(p: Dictionary, month: int) -> Dictionary  # {temp_c, temp_min_c, temp_max_c, rain_mm, rain_days, sun_h}, month 1..12
```

Every function returns a Dictionary with all the fields below present (parse fills gaps), so readers never need
`.get(..., default)`. `of_cell` blocks on the network only the first time for a cell: call it from a worker, or call
`guess` on the main thread.

## Fields

| field | type | meaning | default |
|---|---|---|---|
| format | int | 1 | 1 |
| cell | String | "ROW_COL" | "" |
| lat, lon | float | the cell's middle, degrees | 0.0 |
| guessed | bool | true when made by `guess` (no baked profile) | true |
| country | String | ISO 3166-1 alpha-2, upper case ("GB", "MA", "JP"); "" over open sea | "" |
| country_name | String | English short name | "" |
| countries | Array [[code, share], ...] | every country in the cell by share of its land, biggest first (border cells) | [] |
| region | String | Natural Earth's first-level subdivision, English name ("North Yorkshire", "Bavaria", "Oaxaca", "Kagawa Prefecture"); "" if none | "" |
| region_code | String | ISO 3166-2 ("GB-NYK", "DE-BY") or "" | "" |
| koppen | String | Köppen-Geiger code, 1 to 3 letters ("Af", "BSk", "Cfb", "Dfc", "ET", "EF") | "Cfb" |
| cover | Dictionary String -> float | share of the cell's land in each cover class, sums to 1; keys exactly land_bake.COVER: grass, forest, crop, shrub, barren, urban, sand, wetland, water, rock | grass 1.0 |
| sea | float 0..1 | share of the cell that is sea | 0.0 |
| coast | bool | the cell has a sea coast (0 < sea < 1, or sea within 2 km) | false |
| altitude | Dictionary {min, mean, max} | ints, metres above sea level, over the cell's land | {0, 100, 200} |
| altitude_band | String | from altitude.mean: lowland (< 300), upland (300 to 1000), mountain (1000 to 2500), high (2500 and up) | "lowland" |
| built | float 0..1 | share of the cell's land that is built up (= cover.urban) | 0.0 |
| density | String | from built: wild (< 0.0005), rural (< 0.01), village (< 0.05), town (< 0.2), city (cover is read at 160 m, which misses much of a scattered village, hence the low limits) | "rural" |
| climate | Dictionary of 12-entry Arrays, January first (null in the file for open sea; the loader fills it from latitude) | temp_c, temp_min_c, temp_max_c (°C, monthly means of daily mean/min/max), rain_mm (monthly total), rain_days (days with rain, ≥ 0.1 mm), sun_h (bright sunshine hours in the month) | a mild temperate year |
| tint | null or Dictionary {size, rgb, png} | low-resolution true colour of the ground: size px a side (16), rgb the mean [r, g, b] 0..255, png base64 of a size x size PNG, north up; from ESA WorldCover's Sentinel-2 2021 composite (agreed 26 October); null over open sea | null |
| sources | Dictionary String -> String | which data each field came from (credits screen) | {} |
| bake_key | String | what the profile was made from (baker version and sources): the baker skips a cell whose key is unchanged | "" |
| hash | String | 12 hex, the profile's own hash; co-op can compare it | "" |

Climate normals are 1991 to 2020. Months are calendar months everywhere; southern-hemisphere readers flip seasons
themselves from `lat`.

## Guessed profiles (cells baked before profiles, or offline)

`guess` uses only what the game has offline: the nearest of the world's towns (data/world/places.json, with
data/world/countries.json for the code) for the country; the cell's region.json `sea` and road rules where the game has
the cell; latitude for a smooth climate model and a rough Köppen zone from it; a cover mix by zone. It always sets `guessed: true`, so a reader can tone down anything bold.

## Versioning

`format` is the shape. The baker's `PROFILE_VERSION` goes into every profile's hash, so a re-bake with new sources
changes the hash and the game refetches. Readers should ignore fields they don't know. Data sources and licences: profile-sources.md (in the game repo,

## Data sources and licences

Every source here allows commercial use with attribution (or is public domain), so nothing blocks a paid release.
All are global, fetched once into /mnt/project-files/torque-shed/ride-anywhere-v2/cache/ and reused by every re-bake.

| field | source | resolution | licence | credit line |
|---|---|---|---|---|
| country, countries, region, region_code, sea, coast | Natural Earth 10m admin 0 and admin 1, land | 1:10m | public domain | Made with Natural Earth |
| koppen | Beck et al. (2023) Köppen-Geiger maps, 1991-2020 | 1 km | CC BY 4.0 | Beck, H.E. et al. (2023), Scientific Data 10, 724 |
| cover, built, density | ESA WorldCover 2021 v200 (read at its 160 m overview) | 10 m | CC BY 4.0 | © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium |
| altitude, altitude_band | Mapterhorn terrain tiles (AWS Terrain Tiles fallback), as the cells already use | ~300 m sampled | per Mapterhorn attribution.json (open) | as the game's credits already say |
| climate (temp, min, max, rain, rain days, sun hours) | CRU TS 4.09, 1991-2020 means; sun hours from cloud cover and day length | 0.5° | Open Government Licence v3 | Climatic Research Unit (University of East Anglia) and Met Office |
| tint | ESA WorldCover Sentinel-2 median L2A RGBNIR composite 2021 (cloud-free yearly median) | 10 m, read at 160 m, kept 16 x 16 px a cell | CC BY 4.0 (in the file's own licence tag) | as WorldCover above |

### Rejected

- WorldClim 2.1: non-commercial only, no redistribution without permission.
- TerraClimate: built on WorldClim's climatology; server not reachable from the bake machines anyway.
- EOX Sentinel-2 cloudless (2017 onward): CC BY-NC-SA, non-commercial.
- Copernicus Data Space Sentinel-2 global mosaics: free and open under the Copernicus licence, but quarterly 10 m mosaics
  behind an account and an API; far more than a 16 px tint needs.
- Sentinel Hub 120 m mosaic (CC BY 4.0, also fine): in UTM tiles, more work to cut to cells than WorldCover's degree tiles.
