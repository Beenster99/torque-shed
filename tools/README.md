# Tools

## Real-world route baker (experimental)

`route_bake.py` turns a real place into a **route pack** that the game can ride instead of the hand-laid map.
It is the proof of concept from `docs/real_world_roads_report.md` (phase 1, static load), kept on its own
branch and off by default.

```
python3 -m venv .venv && .venv/bin/pip install numpy pillow pyarrow
.venv/bin/python tools/route_bake.py --name shodoshima --title "Shodoshima" \
    --lat 34.5184 --lon 134.2693 --out data/routes/shodoshima
.venv/bin/python tools/pack_preview.py data/routes/shodoshima preview.png      # a look at the bake
godot --path . -- --route=res://data/routes/shodoshima                          # ride it
```

No API keys. It reads:

| What | From | Licence |
| --- | --- | --- |
| Heights | [Mapterhorn](https://mapterhorn.com) terrain tiles (AWS Terrain Tiles if a tile is missing) | each national source's open licence |
| Roads | [Overture Maps](https://overturemaps.org) transportation segments, read from its public S3 bucket | ODbL, (c) OpenStreetMap contributors |

Downloads are cached under `~/.cache/torque-shed-bake`. A bake takes about 25 seconds.

### What a pack is

A folder of three files, in the game's own frame (+x east, -z north, the shed at the origin, the map 4096 m
square at 4 m spacing, as `WorldTerrain`):

- `pack.json`: name, anchor, where the start lands, credits and a content hash.
- `heights.u16`: 1025 x 1025 little-endian uint16 heights, scaled by `height.min` and `height.scale`.
- `roads.json`: road definitions in the shape of `WorldLayout.ROADS`.

`scripts/route_pack.gd` loads it. When `WorldLayout.pack` is set, `WorldTerrain` takes its heights from the
pack and `WorldRoads` lays the shed's own loop first, then the pack's roads. Everything else (road grading,
meshes, collision, surfaces, props, traffic) is the existing code.

### How the baker chooses things

- **Start point.** Give a latitude and longitude on a road. It lands 800 m east of the shed. Heights are
  metres above the start, so it sits near level with the shed.
- **Shed.** The land fades to level ground over 380 to 800 m from the shed, and real roads are kept 380 m
  clear of it, so the yard and its loop are untouched. A straight **link road** joins the loop's east side to
  the real road nearest the start. Pick a start on gentle ground: a mountain start leaves a plateau round the shed.
- **Roads.** Overture's road, residential, track and larger classes (not footpaths, cycleways or steps).
  Segments that meet end to end are joined into long roads, thinned to 1.5 m, and ordered best class first.
  At every junction the lesser roads join the first road that touches it, using the game's existing
  "start/end on another road" snapping, so junctions are flush. Unpaved roads and tracks become dirt.
- **Heights.** Bilinear from the terrain tiles at the first zoom whose pixels are 4 m or finer.

### Known limits of the proof of concept

- The map is one 4 km square: no streaming, no origin shift yet (phases 2 and 3).
- No sea: low ground is just low terrain. Bridges and tunnels ride as plain road.
- No buildings, no villages: the props are the existing woods and rocks placed by the existing noise, not real land cover.
- Roads that cross without a shared connector (a bridge over a road) are two unconnected roads at nearly the same height.
- Heights where there is no lidar are 30 m Copernicus, a surface model: buildings and trees stand in it.
- Co-op does not check that every player has the same pack yet; the pack's hash is there for that.
- Needs a start on a road within 150 m, or it stops.

### Tests

```
python3 -m unittest discover -s tools -p 'test_*.py'     # the baker, offline
```

The game side is covered by "Route packs" in `tests/run_tests.gd`.
