# Terrain by position: interface (T5), format 1

Owner: T5 Terrain around the rider (scripts/real_terrain.gd, height_tiles.gd, real_land.gd, real_ridges.gd).
Readers: T6 Road network core now, T7, T9 and T10 later. Change requests go to T5 through the coordinator.

**The rule: terrain is asked by position and nothing else.** No reader passes a road, a knot, a plan or a chunk
index. Ask for a point (or a box) in the ride's frame and you get the ground there. Which map tiles hold it, and
when they are fetched, is T5's business: they follow the riders, not the planned road.

## The object

`RealTerrain` (scripts/real_terrain.gd), one per ride: `AdventureWorld.route.real.terrain` (the pack's,
`RealPack.terrain`). For a baked region it is the baked land; for a live one ("heights": "live", every world cell)
it reads Mapterhorn's map tiles through `HeightTiles`. Readers never need to know which.

## The frame

Route frame, metres, floats: **x east, z south**, from the region's frame middle `(lat0, lon0)`; y is metres above
sea level. The same frame the road, the cell graph (RealRegion) and the land blocks use. The floating origin
(AdventureWorld.origin) is not in it: add `world.origin` to a local position first.

```
terrain.to_geo(x, z) -> PackedFloat64Array   # [lat, lon] degrees (doubles: a Vector2 is half a metre out)
terrain.from_geo(lat, lon) -> Vector2    # (x, z) route frame
```

## Asking (any thread)

```
terrain.height(x: float, z: float) -> float      # metres above sea level, bilinear; NAN where nothing is known yet
terrain.ready(area: Rect2, level := 0) -> bool    # every tile of `level` under `area` is in: its heights are final
terrain.sea_at(x: float, z: float) -> bool        # open sea there (not a lake, not land below sea level)
terrain.cover(x: float, z: float) -> int          # unchanged: RealPack.COVER id, -1 where no cover is baked
```

- `height` is safe from worker threads (road blocks are laid out on them). It never blocks on the network.
- Levels: 0 fine (about 3 m a pixel), 1 middle (about 22 m), 2 ridge (about 90 m). `height` answers from the finest
  level that has the point; where a finer level's tiles end it is eased into the next over 48 px, so there is no step.
- Sea: below the shore the ground is given a floor sloping down to -35 m, **only where the cell's place profile has
  sea** (`profile.sea > 0` or `profile.coast`). Land below sea level in a cell with no sea (the Beemster, the Fens'
  inland cells) is land at its real height, negative or not. `sea_at` gives the same answer as the heights do.
- Road heights (bridges, cuttings, the road's own blend into the land) are not here: they belong to whoever builds
  the road. This is the bare ground. (AdventureRoute.ground_at adds rivers' beds and becks' troughs on top.)

## Before a tile arrives

- A point whose fine tile isn't in yet gets the middle level's height there, and failing that the ridge level's. So
  the ground is there, coarse, nearly everywhere round a rider from the first frame; it only sharpens later.
- `NAN` only where no level has anything: in practice more than 18 km from every rider and from the planned road,
  or a live ride with no network and nothing on disk. A reader that gets NAN builds nothing there yet.
- `ready(area, 0)` false means "you can build here, but it will change": a road block may wait for it (recommended
  for anything with collision), or build now and rebuild on `ground_arrived`.
- When tiles come in, `terrain.ground_arrived(area: Rect2, level: int)` is emitted **on the main thread** (route
  frame, the area whose heights may have changed, a tile's box grown by the easing; `level` the live level that came
  in). Rebuild what you built inside it. It never fires for a baked region (everything is ready from the start).
- Heights never change for any other reason during a ride. Once `ready(area, 0)` is true it stays true while a rider
  is within `KEEP` of it.

## Who drives the fetching

```
terrain.follow_riders(riders: Array[Vector4])   # main thread; Vector4(x, z, vx, vz) per rider, route frame, m and m/s
```

RealLand calls it as the land follows the rider (AdventureWorld.follow), with every rider in the crew (the world's
`focus` points; your own rider first). **Readers do not call it.** It is cheap to call every frame (it only works
when a rider has moved 64 m or turned).

The fetch rule, per rider, per level:

| level | ring round the rider | ahead along its direction of travel (over 2 m/s) | kept until a rider is further than |
|---|---|---|---|
| 0 fine | 1 km | 3 km | 1.5 km |
| 1 middle | 6 km | 6 km | 9 km |
| 2 ridge | 18 km | none | 27 km |

- Tiles are fetched on one worker, nearest first, the ring before the ahead strip; tiles on disk are taken at once.
- The planned road's own tiles (RealTerrain.for_road, fetched when the ride is planned) stay for the whole ride, so
  the single-line ride is unchanged.
- Memory is held flat: tiles past the keep distance of every rider leave the ride's set; HeightTiles keeps at most 160
  decoded tiles and 10,000 on disk.
- Co-op: every machine fetches round every rider, so the ground under a mate is the same on each machine once its
  tiles are in. Before that, a machine may have a coarser level there for a moment.

## The land in network mode (asked for by T6)

```
land.set_roads(net)        # RealLand (AdventureWorld.land): net = RoadNet, or null to go back to the planned road
RealLand.roam := true      # riders may leave the road: AdventureTrip doesn't put a bike back while land holds it up
land.holds(x, z) -> bool   # a near land block, with collision, is laid out under (x, z)
```

With a net set, no strip beside the planned road is left out: every block is drawn, and where
`net.roads_near(block rect)` is true each vertex takes `net.ground_at(x, z, bare)`. Blocks within 1.1 km of the rider
are at the near level (8 m cells), and every near block (within about 560 m, and all of those within 1.1 km in
network mode) carries collision (a StaticBody3D "Ground", layer 1, surface "grass"). T6's Esc > Debug toggle should
call `set_roads` and set `RealLand.roam`.

## Pinned by

- tests/terrain_ring_tests.gd: `_test_terrain_by_position` (this interface: height, ready, ground_arrived, before and
  after a tile arrives, any thread), `_test_terrain_ring` (the fetch rule: ring, ahead, keep, flat memory),
  `_test_terrain_polder` (sea against land below sea level), `_test_terrain_off_plan` (one ride off the plan: the
  ground keeps coming and holds the bike up; and network mode cutting a road in).
