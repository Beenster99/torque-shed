# Scenery from the map: interface (phase D round 0, D0), format 1

Owner: D0 Scenery pipeline (`tools/feature_bake.py`, `scripts/scenery_streamer.gd`, `data/scenery_kits.json`, the
features hooks in `real_region.gd` and `cell_store.gd`). Readers: the phase D round threads (D1 Skyline, D2 Rail, D3
Water and coast, D4 Mountains, D5 Land texture, D6 History and buildings, D7 Ferries, D8 Borders, D9 Furniture).
Change requests go to D0 through the coordinator. A copy lives in the shared folder as
`ride-anywhere-v2/interfaces/scenery.md`; this file in the repo is the one that is kept up to date.

Pinned by `tests/scenery_tests.gd` (`_test_scenery_*` in tests/run_tests.gd) and `tools/test_feature_bake.py`.

## Simon's two rules, as code

1. **Nothing disturbs what is built.** Scenery stands beside and above the road, never in it. `SceneryStreamer` adds no
   collision at all, never changes a road, the land under one or a road block's seeds, and stands a thing the map
   puts on a carriageway or its verge just off it (`SceneryStreamer.off_road`: `CLEAR` m past the verge, on the side
   it was; inside a junction it is left out). The features are hashed apart from the region (`RealRegion.features_hash`,
   never `RealRegion.hash`, which seeds the road blocks' trees and roadside), and `features.json` is outside a bundled
   region's folder hash (`RegionStore.UNHASHED`, `region_bake.region_hash`). A round that needs a terrain cut, a
   road paint or a building change asks that file's owner.
2. **The whole world.** The baker keeps every kind wherever Overture has it, in every cell the world's store bakes;
   the kit library has a row for every kind with a default that serves every region, and a region's row only lays
   fields over it. Nothing is keyed to a place.

## The data: features per cell

`tools/feature_bake.py` reads Overture's `base/infrastructure`, `base/land`, `base/water`, `base/land_use`,
`transportation/segment` (rail and water only: never a road) and `divisions/division_boundary`, keeps only the
classes in its `CLASSES` table (all nine rounds' kinds, 141 of them, named for the game), and writes one file a cell:

```
{"format": 1, "cell": "ROW_COL", "release": R, "classes": CLASSES_HASH, "kinds": [...], "names": ["", ...],
 "points": [[kind, lat, lon, height, elevation, heading, name, id], ...],
 "lines":  [[kind, height, width, flags, name, id, lat, lon, dlat, dlon, ...], ...],
 "areas":  [[kind, height, elevation, name, id, lat, lon, dlat, dlon, ...], ...],
 "words": ["", ...], "buildings": [[dlat, dlon, class, roof_shape, roof_color, roof_material, facade_material,
                                    facade_color], ...]}   (the last two only where a building's look is mapped)
```

- lat/lon in 1e-5 degrees; after a line's or area's first point each is the step from the one before.
- height, elevation, width in metres, heading in degrees clockwise from north; `null` where the map says nothing.
- line flags: 1 bridge, 2 tunnel, 4 disused or abandoned, 8 being built (a railway is cut where they change).
- id: 12 hex of the SHA-1 of the Overture id; `null` for the small near-road things (walls, gates, poles, benches).
- Lines and areas are cut to the cell's box (they meet at the edges, never twice); an area is its outer ring only.
- The small things (`CLASSES` rows marked near) are kept within about `NEAR_M` (80 m) of a road a ride can take;
  everything else wherever it is in the cell.
- A generator is a `wind_turbine` or `solar` where OpenStreetMap says what drives it.
- Places (Overture's `places/place`, its taxonomy's primary category, only those it is `PLACE_CONFIDENCE` sure of) give
  named `monument` and `castle` points (D6).
- **Building looks** (D6): where the map says how a building looks (`LOOKS`: roof shape, roof colour and material,
  facade material and colour) or what it is (`BUILDING_CLASSES`: a church, a mosque, a hangar, a trullo), the file also
  has `"words": ["", word, ...]` and `"buildings": [[dlat, dlon, class, roof_shape, roof_color, roof_material,
  facade_material, facade_color], ...]` (each building's outline's middle, a step from the one before, the rest
  indexes into `words`, 0 for nothing said). The format stays 1: a game that doesn't read them reads the rest as
  before. `RealRegion.add_features` puts them in `features["buildings"]` as `[x, z, class, roof_shape, roof_color,
  roof_material, facade_material, facade_color]` (strings, "" for nothing said), and `BuildingLooks` matches each to the
  `RealRegion.buildings` row it stands in, so a town's roofs are its own without a cell being baked again or a road
  block's seeds moving.

Where the files live:

- World cells: the store's `feature/cROW_COL.json`, its hash in `index.json` `"features"`, fetched with the cell
  (`CellStore.features`, kept and pruned beside the cell). Baked with every new cell (`bake.yml`), and for the cells
  baked before by **Map the features** (`features.yml`, `scripts/feature_backfill.py`), which only makes a cell's
  again when its release or `classes` hash differs: adding a kind is one incremental pass.
- Bundled regions: `data/regions/<id>/features.json`, its cells merged (`feature_bake.py --box`): the Dales and
  Shodoshima carry one.

## In the game

`RealRegion.features` (both kinds of region, in the region frame, x east and z south):

```
points: [[kind, x, z, height, elevation, heading, name, id], ...]
lines:  [[kind, PackedVector2Array, height, width, flags, name, id], ...]
areas:  [[kind, PackedVector2Array (outer ring), height, elevation, name, id], ...]
```

`RealRegion.features_hash` goes into the crew's ride hash (`AdventureCrew.ride_hash`, a region with none keeps the
hash it had), and `SceneryStreamer.VERSION` with the kit library's MD5 into the builder hash, so a crew whose games
place different scenery finds out at the lobby.

`SceneryStreamer` (one per network ride, `AdventureWorld.scenery`) files the points, lines and areas by road block
key (`RoadBlock.key_of`; a line or area in every block its box touches, `FILE_MOST` a side at most), lays out each
block within `REACH` (2 km) of a rider on a JobPool worker once its ground is final (`RoadNet.ready`), puts it in one
block a frame as one MultiMesh per model, frees it past `KEEP`, and lays it out again when the ground sharpens. A block
holding a kind whose kit `reach` is past `REACH` (turbines, pylons, masts) is wanted out to that reach (`FAR_MOST`,
8 km, at most), laid out on whatever ground is known there and again once it's near and final. Reaches (drawing and
the far blocks') scale with Settings' draw distance (0.5 to 2), as the roads' do.

## The model hook: scripts/scenery/SCRIPT.gd

A kit row's `"model"` is `"SCRIPT:MODEL"`. The streamer loads `res://scripts/scenery/SCRIPT.gd` once (on the main
thread, before any block) and calls its static functions; a round adds its script and its kit rows and never edits
the streamer.

```
static func lay_out(net: RoadNet, key: Vector2i, rows: Dictionary) -> Dictionary     # on a worker
    rows: {"points": [[row, kit], ...], "lines": [...], "areas": [...]}: the RealRegion.features rows filed in block
          `key` whose kit names this script, each with its kit row (the default with the point's region laid over it,
          plus "round"). A line or area is passed to every block it touches: place only its things in this block.
    returns {"items": {MODEL: [Transform3D in the block's frame (its corner: x - key.x * 512, z - key.y * 512)]},
             "dress": anything (optional, handed to dress), "moved": int, "skipped": int (optional counts)}
static func mesh(model: String) -> Mesh                  # once a model: what each of its MultiMeshes draws
static func dress(node: Node3D, data) -> void            # optional, main thread, once the block's node is in the world:
                                                         # what isn't instanced (wires, lamps, moving parts)
```

- An item is drawn to the farthest `reach` of the kit rows naming `SCRIPT:MODEL` (a MODEL no row names, to the
  script's rows' farthest), times the draw distance. A model's mesh is made once and shared by every block.
- `net.region` is the region; `net.region.features` all its rows, for a script that needs a whole line (a pylon line
  over several blocks): keep any cache of your own static, keyed by region, built under a Mutex on the worker.
- Helpers, all safe on a worker:
  - `SceneryStreamer.stand(net, p, memo = null, sea = false) -> Vector3`: where a thing the map puts at region point
    `p` stands, on the land and off any road (region frame, y the land's less 0.1 m). NAN where it can't: inside a
    junction, or ground not known yet (sea level instead when `sea`, for things offshore or far off; the kit's
    `"sea"` is the way to say so). `memo`: pass one `{}` for a block's calls once it has a few dozen.
  - `SceneryStreamer.off_road(net, p) -> Vector2`: `p` pushed `CLEAR` m past the verge of a road it's on, NAN in a
    junction.
  - `SceneryStreamer.in_block(key, p) -> bool`: whether region point `p` is in block `key`.
  - `SceneryStreamer.kit(kind, region_id)`, `SceneryStreamer.kind_reach(kind)`.
- A canal's locks are `canal_lock`: its lines tagged `lock=yes` (named from `lock_name`) and the water polygons
  tagged `water=lock` (Overture has no lock class: they're in the rows' OpenStreetMap tags, `TAGGED` in the baker).
- Rail pieces meet end to end: where a line is cut at a cell's edge or a flag change, the pieces either side share
  that point exactly (the same 1e-5 degrees, so the same region-frame point), as do Overture segments that meet.
- Round 0's script is `standin` (`"standin:post"`): a post at each point (and a line's or area's first point in the
  block), coloured by its kit's round, laid out only while `show_standins` is on (Esc > Debug > Scenery markers; the
  tests), so an ordinary ride lays out nothing until a round's kit row names its own model.

## The kit library: data/scenery_kits.json

```
{"format": 1, "kinds": {kind: {"round": "D1", "default": {"model": "standin:post", "reach": 4000, ...},
                               "regions": {region_kit_id: {fields laid over the default}}}}}
```

Region ids are the regional kits' thirteen (`RegionKit.regions()`), chosen per point by its cell's place profile
(`RegionKit.at_frame`). A round thread owns its kinds' rows. Fields the streamer reads: `model`, `reach` (m), `sea`
(true: may stand offshore); anything else is the model's own.

## The postcards' features sheet

The postcards (tests/postcards) carry each place's features (`world/feature/`, `bake.py --features`). On the road
network each place also draws `features-sheet.png` (`tests/postcards/features.gd`): the map of the 3 km square round
its road view, every feature in its round's colour, beside the road from above with the scenery drawn (stand-ins
included), and how many things there are by round and kind. It is in the Postcards workflow's "postcards" artifact
beside the contact sheet, so a round's pull request shows what it places in eight places on five continents.

## What a round thread does

1. Add `scripts/scenery/<round>.gd` with `lay_out`, `mesh` and, if it wants, `dress` (above). Never edit
   `scenery_streamer.gd`; ask D0 for a change to it.
2. Set its kinds' rows in the kit library to its models (`"<script>:<model>"`), with any region rows.
3. Give the script a `const VERSION := 1` and bump it when its `lay_out` changes what a block holds: each model
   script's VERSION is in the builder hash (`SceneryStreamer.script_versions`), as is the kit library's MD5.
4. Only when the map has a class not in `CLASSES`: add the row and its kit row, and run **Map the features** once.
5. Keep the budget: a block under 2 ms on a worker once its roads' heights are known, and one draw call a model a
   block.
