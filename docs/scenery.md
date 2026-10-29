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
 "areas":  [[kind, height, elevation, name, id, lat, lon, dlat, dlon, ...], ...]}
```

- lat/lon in 1e-5 degrees; after a line's or area's first point each is the step from the one before.
- height, elevation, width in metres, heading in degrees clockwise from north; `null` where the map says nothing.
- line flags: 1 bridge, 2 tunnel, 4 disused or abandoned, 8 being built (a railway is cut where they change).
- id: 12 hex of the SHA-1 of the Overture id; `null` for the small near-road things (walls, gates, poles, benches).
- Lines and areas are cut to the cell's box (they meet at the edges, never twice); an area is its outer ring only.
- The small things (`CLASSES` rows marked near) are kept within about `NEAR_M` (80 m) of a road a ride can take;
  everything else wherever it is in the cell.
- A generator is a `wind_turbine` or `solar` where OpenStreetMap says what drives it.

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

`SceneryStreamer` (one per network ride, `AdventureWorld.scenery`): files the points by road block key
(`RoadBlock.key_of`), lays out each block within `REACH` of a rider on a JobPool worker once its ground is final
(`RoadNet.ready`), stands each point on the land (`RoadNet.ground_at`), puts it in one block a frame as one
MultiMesh per model and round (drawn to the kind's reach), frees it past `KEEP`, lays it out again when the ground
sharpens. Pure and testable: `SceneryStreamer.lay_out(net, filed, key)`, `off_road(net, p)`, `kit(kind, region)`.

## The kit library: data/scenery_kits.json

```
{"format": 1, "kinds": {kind: {"round": "D1", "default": {"model": "standin", "reach": 4000, ...},
                               "regions": {region_kit_id: {fields laid over the default}}}}}
```

Region ids are the regional kits' thirteen (`RegionKit.regions()`), chosen per point by its cell's place profile
(`RegionKit.at_frame`). A round thread owns its kinds' rows. Round 0 has one model, `standin`: a post coloured by
the round that will model the kind, shown only with Esc > Debug > Scenery markers on (`show_standins`), so an
ordinary ride shows nothing until a round adds a real model.

## What a round thread does

1. Add its model(s): a name in `SceneryStreamer.MODELS` and its mesh (a script of its own under `scripts/scenery/`,
   called from `model_mesh` and, for moving parts or lines, from `lay_out`). Points work today; lines and areas are
   in `RealRegion.features` and filed per block by the round that first places one (add `file_lines` next to
   `file_points`, keep one owner: ask D0).
2. Set its kinds' rows in the kit library to the new model, with any region rows.
3. Bump `SceneryStreamer.VERSION` if what a block lays out changes (the kit library's own change is hashed already).
4. Only when the map has a class not in `CLASSES`: add the row, and run **Map the features** once.
5. Keep the budget: a block under 2 ms on a worker once its roads' heights are known (the first block round a new
   place waits on them, as the road blocks do), and at most one draw call a kind a block.
