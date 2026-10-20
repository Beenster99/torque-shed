# Tools

## Real-world route baker (experimental)

`route_bake.py` turns a real place into a **route**: a long road along real roads, baked as a chain of 4 km legs the
game rides instead of the hand-laid map. See "Real-world routes" in the main README for what you get in the game, and
`docs/real_world_roads_report.md` for why it is built this way. It is off by default and lives on its own branch.

```
python3 -m venv .venv && .venv/bin/pip install numpy pillow pyarrow
.venv/bin/python tools/route_bake.py --name shodoshima --title "Shodoshima" \
    --lat 34.5184 --lon 134.2693 --length-km 25 --out data/routes/shodoshima
.venv/bin/python tools/pack_preview.py data/routes/shodoshima preview     # a look at every leg
godot --path . -- --route=res://data/routes/shodoshima                     # ride it
```

**Setting the length from an issue.** Give it a JSON file and the same thing happens (this is the hook for the
magazine, whose issue data should write this file):

```
{"name": "shodoshima", "title": "Shodoshima", "start": {"lat": 34.5184, "lon": 134.2693},
 "end": {"lat": 34.4994, "lon": 134.3479}, "length_km": 25, "seed": 0}
.venv/bin/python tools/route_bake.py --issue issue.json
```

`end` is optional; without it the route ends about `length_km` away, at the node that gives the nicest roads (more
main road for the distance), and `seed` breaks ties. If the roads here do not run that far it says so and ends at the
furthest point it can reach. `--no-buildings` leaves buildings out (quicker, for trying a start point).

No API keys. It reads:

| What | From | Licence |
| --- | --- | --- |
| Heights | [Mapterhorn](https://mapterhorn.com) terrain tiles (AWS Terrain Tiles if a tile is missing) | each national source's open licence |
| Roads, names, buildings | [Overture Maps](https://overturemaps.org), read from its public S3 bucket | ODbL, (c) OpenStreetMap contributors |

Downloads are cached under `~/.cache/torque-shed-bake`. A 25 km route of 5 legs takes about 3 minutes and is 11 MB.

### What a route is

A folder, in the game's own frame (+x east, -z north, metres; each leg's map is 4096 m square at 4 m spacing):

- `pack.json`: name, credits, content hash, and each leg: where its origin is on the route, how its heights are
  scaled, its sea level (if it has sea), the distance along the route at which to hand over to the next leg, and the
  shift from this leg's frame to the next's.
- `route.json`: the planned route line (25 m points) and its turn-by-turn instructions, for the satnav.
- `legs/legNN/heights.u16`, `roads.json`, `buildings.json`: the land the game builds for that leg.

`scripts/route_journey.gd` and `route_pack.gd` load it; `main.gd` makes the next leg on a thread and swaps to it.

### How the baker chooses things

- **Route.** The nearest road node to the start point to the end (or the best node about `length_km` away), by
  shortest path with each road class costing a different amount per metre (motorway cheapest, tracks dearest). Turn
  instructions are made at every junction where the route leaves a road that other roads join (going straight on at
  a junction is left out of the satnav).
- **Legs.** Cut along the route so each leg's stretch stays within 1.7 km of its middle, and each starts 300 m before
  the last one ended; the hand-over is in the middle of the overlap. Leg 0 has the shed at its origin and the start
  point 800 m from it, with real roads kept 380 m clear and the land faded flat round the shed, and a straight link
  road from the shed's loop to the real road nearest the start.
- **Roads.** Overture's road, residential, track and larger classes (not footpaths, cycleways or steps). Segments that
  meet end to end are joined into long roads, thinned to 1.5 m and ordered best class first; at every junction the
  lesser roads join the first road that touches it, using the game's "start/end on another road" snapping, so
  junctions are flush. Unpaved roads and tracks become dirt. Roads take their English name, else their route number,
  else their own name, else their kind ("Main road").
- **Sea.** Ground at sea level is sea (a pond is not). The baker gives it a floor that slopes down to 35 m away from
  the shore, and the game draws a water sheet at sea level with a sand beach.
- **Buildings.** Overture footprints turned into their smallest enclosing rectangle, 22 to 2500 m2, clear of every
  road, the 1400 nearest the route per leg. Short ones are sheds, big or long ones barns, the rest houses. The ground
  under each is levelled and feathered into the land.
- **Heights.** Bilinear from the terrain tiles at the first zoom whose pixels are 4 m or finer.

### Known limits

- No real villages (shops, churches), land cover (forests are still placed from noise), bridges and tunnels as such
  (they ride as plain road), street lights, or one-way and turn restrictions in the satnav.
- Roads that cross without a shared connector (a bridge over a road) are two unconnected roads at nearly the same height.
- Where there is no lidar the heights are 30 m Copernicus, a surface model: buildings and trees stand in it.
- Road names in kanji need a font that has them (Windows does).
- Joining a co-op session that has already ridden out of the first leg is refused.
- Needs a start within 500 m of a road, or it stops.

### Tests

```
python3 -m unittest discover -s tools -p 'test_*.py'     # the baker, offline
tests/mp_route_test.sh                                   # co-op route handshake (two game processes)
```

The game side is covered by "Route packs" in `tests/run_tests.gd`.
