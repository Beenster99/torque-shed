# Road block: interface (T6), version 4

Owner: T6 Road network core. Readers: T7 Satnav and journeys, T8 Regional kits (markings, buildings), T9 Co-op,
T10 Life on the network, and T5 Terrain around the rider (the ground under the roads).
Change requests go to T6 through the coordinator. Adding a field is free; renaming or removing one, or changing
what any machine builds, bumps `RoadBlock.VERSION` (and so every block's hash).

Pinned by `tests/road_block_tests.gd` (`_test_road_block_interface` in tests/run_tests.gd): every name below is
checked there, with its type, on a small fixture graph. If that test changes, this note changes with it. The same
file tests the kinds of junction (`_test_road_kinds`), locate (`_test_road_locate`), heights and ground_at
(`_test_road_heights`), seams between blocks (`_test_road_blocks`) and a real Dales cell (`_test_road_cell`).

## The idea in one paragraph

The ride's region (`RealRegion`, one stitched area of cells) is the road graph. `RoadNet` wraps it once per ride
and answers questions about the roads anywhere in it: which road am I on, how high is the road here, how is the
land shaped round it. `RoadBlock` is the roads of one 512 m square of the region: every road piece and every
junction in it, laid out as plain data on a worker, the same on every machine. The streamer (T6's, in
`AdventureWorld`) builds the blocks round each rider and commits them to the scene a piece at a time.

## Frames and keys

- Everything is in the **region frame**: metres from the region's frame point, +x east, -z north, y metres above
  sea level (RealRegion's own). The floating origin is the streamer's business; nothing here is in local space.
- A block is the square `[bx * 512, (bx + 1) * 512) x [bz * 512, (bz + 1) * 512)`; its key is
  `Vector2i(bx, bz)` = `RoadBlock.key_of(x, z)`. Edges are in every block they cross, each block owning the stretch
  inside it (pieces overlap a seam by `RoadBlock.SEAM` m so the deck has no crack). A junction belongs to the block
  its node is in.
- Along an edge, `s` is metres from its `a` node (RealRegion.edge_a) towards `b`, along `net.line_of(edge)`: the
  map's line (RealRegion.edge_line) smoothed as the planned road is (RoutePlanner.smooth_line, by class), so no
  corner the map drew stays a corner and the planned road and the network's lie one on the other. It's smoothed a
  strand at a time (edges joined end to end through plain joins), so a junction's or a dead end's node stays put
  and a plain join's moves onto the curve; a roundabout's ring stays as the map drew it. `net.length_of(edge)` is
  its length (a little under RealRegion.edge_len). `lat` is metres to the right of the centre line looking from a
  to b.

## RoadNet (scripts/road_net.gd)

```
RoadNet.new(region: RealRegion, height: Callable, ready := Callable())
    # height(x, z) -> float: bare ground; ready(area: Rect2) -> bool: is it final there. In the game:
    # RoadNet.new(region, terrain.height, terrain.ready), terrain being T5's RealTerrain (interfaces/terrain.md).
net.region: RealRegion
net.version_hash -> String                          # 12 hex: RoadBlock.VERSION and the region's hash
net.line_of(edge: int) -> PackedVector2Array       # its centre line a to b, smoothed (above), region frame (x, z)
net.length_of(edge: int) -> float                   # its length along line_of (m)
net.width_of(edge: int) -> float                    # the carriageway's full width (m), by class (RoutePlanner.WIDTH)
net.lanes_of(edge: int) -> int                      # 1 or 2 (one-way roads and narrow lanes have 1)
net.profile(edge: int) -> PackedFloat32Array        # road height at each of net.samples_of(edge) even steps a to b (about RoadNet.STEP m)
net.road_y(edge: int, s: float) -> float            # the road's height at s (centre line, before the crown)
net.bridges_of(edge: int) -> PackedInt32Array       # its bridges (the map's), as samples [first, last, ...]
net.bridge_at(edge: int, s: float) -> float         # how far out on a bridge it is at s: 1 over what it crosses, 0 off one
net.junction_of(node: int) -> Dictionary            # the junction at node (below), {} for a plain join (two roads)
net.mouth(edge: int, node: int) -> float            # how far from node (m along the edge) the plain road starts
net.locate(x: float, z: float, hint := -1) -> Dictionary   # which road am I on (below)
net.ground_at(x: float, z: float, bare: float) -> float    # the land with the roads cut in (below)
net.block(key: Vector2i) -> RoadBlock               # builds the block (pure: call it on a worker)
net.dress: Dictionary                               # {terrain: RealTerrain, look: the place's look}: what blocks plant trees by
                                                    # ({} plants none; the ride sets it)
```

The net is read-only once made apart from its caches, which are locked, so one net is shared by every worker.
Heights come only from `height(x, z)`: the net asks the terrain by position and nothing else (T5's rule).
Everything it returns is the same on every machine for the same region and the same heights.

The road's height anywhere depends only on the ground within about 80 m of it (smoothed over some 50 m, eased over
the last 40 m into each junction, which every road meeting there shares). The net keeps a height only once
`ready` says the ground there is final, so it never holds on to a coarse guess. The streamer builds a block only
once `terrain.ready(block.rect.grow(128), 0)` is true, and so every machine with the fine tiles builds the same
block. Where a road crosses into a block whose ground isn't in yet, nothing is built there until it is.

### Bridges

The map's bridges (the region's spans of kind 0, from Overture's is_bridge flag) are the net's bridges too: the
road runs straight from the land at one end to the land at the other, over the valley or river rather than down
into it. Where a bridge crosses another road without meeting it (an overpass), its deck climbs to leave
`RoadNet.HEADROOM` m (16 ft 6 in) over that road, level for `RoadNet.CROWN_FLAT` m either side of it and falling
away at `RoadNet.RAMP` (one in twenty) on banks of its own, so a dual carriageway's overbridges and the slip roads
up to them are ridden as they are. Such a bridge runs on past the map's ends of it (often its abutments' faces)
until it clears the road under it, that road's verges and the land held level with it. The road under it stays on
the land. Out on a bridge `ground_at` leaves the land
as it is, only ever `RoadNet.BRIDGE_DEPTH` m or more under the deck; the block draws a stone parapet each side (walls
to ride into), the deck's sides and underside, and piers down to the land where it's well below, and no verges.

### locate: "which road am I on"

`net.locate(x, z, hint)` gives the nearest road to (x, z) within `RoadNet.REACH` m of its edge, or `{}`:

| key | type | meaning |
|---|---|---|
| edge | int | the RealRegion edge |
| s | float | metres along it from its a node |
| lat | float | metres right of its centre line (a to b) |
| y | float | the road surface's height there (crown included; at a junction, the junction's surface) |
| width | float | net.width_of(edge) |
| heading | float | the way a to b runs there, radians clockwise from north (-z): 0 north, PI/2 east |
| on_road | bool | inside the carriageway or a junction's surface |
| node | int | the junction node when (x, z) is inside a junction's area, else -1 |

`hint` is the edge from last time (cheap to follow a rider along); any edge or -1 works, the answer doesn't
depend on it.

### ground_at: the roads cut into the land (for T5)

`net.ground_at(x, z, bare)` takes the bare ground height at (x, z) and returns the land's height with the roads
in it: just under the deck (`RoadNet.UNDER` m) across the carriageway and its verges (the lowest deck's, where two
overlap), then eased back to `bare` over a cutting or embankment whose width grows with the height to make up
(1 in 3 slopes, `RoadNet.BANK_MIN` to `RoadNet.BANK_MAX` m). Where the land rises past the road (a cutting) it's
held level with the road `RoadNet.LAND_PAD` m further past the verge before its bank starts, so that no 8 m cell
of the land lies over the deck; where it falls away (an embankment), `RoadNet.FALL_PAD` m, so the verge's skirt is
never left in the air. Where several roads are near, the one whose bank it's nearest the top of has its way.
Away from every road it returns `bare` unchanged. T5's land blocks call it for every
vertex near a road (`net.roads_near(rect: Rect2) -> bool` says whether a rectangle has any within reach); the
road blocks draw only the deck, junctions, verges and their kerbs, so land and road meet without a strip owned
by either. A verge is left out wherever it would lie on another road's carriageway or a junction's surface (not one
crossing over or under it). Nowhere within `RoadNet.LAND_PAD` m of a road's verge is the land higher than that
road, whatever other road is near (a dual carriageway's other half, a roundabout's ring), so no land stands up
through a deck.

## RoadBlock (scripts/road_block.gd)

```
RoadBlock.VERSION: int          # bump when what a block holds or how it's laid out changes
RoadBlock.SIZE := 512.0
RoadBlock.key_of(x, z) -> Vector2i
block.key: Vector2i
block.rect: Rect2               # in the region frame
block.hash: String              # 12 hex of VERSION, the region's hash and the key: co-op compares these
block.pieces: Array[Dictionary] # the roads (below)
block.junctions: Array[Dictionary]
block.buildings: Array          # RealRegion.buildings rows standing in the block, with their ground "y" appended
                                # (none on a road, its verge or a junction: the map's line for the road wins)
block.trees: Dictionary         # kind (AdventureProps.mesh) -> Array of Transform3D from the block's corner: the trees
                                # and bushes on its land (net.dress), none on a road or its verge
block.locate(x, z) -> Dictionary   # the same as net.locate
block.arrays: Dictionary        # the mesh and collision arrays the streamer commits (T6's own; may change freely)
block.ms: float                 # how long the build took on its worker
```

### A piece: one edge's stretch inside the block

| key | type | meaning |
|---|---|---|
| edge | int | RealRegion edge |
| s0, s1 | float | the stretch along the edge it covers (s0 < s1), already trimmed back to the junction mouths |
| points | PackedVector3Array | centre line every RoadNet.STEP m from s0 to s1, region frame, y = road height |
| width | float | carriageway width (m) |
| lanes | int | 1 or 2 |
| class | String | RealRegion class ("primary", "residential", "track", ...) |
| surface | String | RealRegion surface ("tarmac", "gravel", ...) |
| name | String | RealRegion.name_of(edge) |
| oneway | int | RealRegion.edge_oneway: 0 both ways, 1 a to b only, -1 b to a only |
| a, b | int | the edge's end nodes |
| ring | bool | part of a roundabout's carriageway |
| at | PackedFloat32Array | how far along the edge (m) each of its points is |

### A junction

| key | type | meaning |
|---|---|---|
| node | int | its node (for a roundabout: the lowest node of its ring) |
| nodes | PackedInt32Array | every node it covers (one, or a roundabout's ring) |
| kind | String | "end" (dead end), "tee", "fork" (Y), "cross", "staggered" (a tee with another tee on the other side within RoadNet.STAGGER m), "multi" (5 or more arms), "roundabout", "mini" (a roundabout too small for an island) |
| pos | Vector3 | its middle; y is the junction's surface height |
| radius | float | how far its surface reaches from pos (m) |
| arms | Array[Dictionary] | the roads out of it, clockwise from north (below) |
| island | float | a roundabout's island radius (m), 0 otherwise |
| pair | int | a staggered junction's other node, else -1 |
| outline | PackedVector2Array | its surface's edge, clockwise, region frame (x, z): across each arm's mouth, then a curved kerb (`RoadNet.KERB_STEPS` pieces) round to the next arm, or a straight one where the two arms' edges don't meet (a tee's far side); a roundabout's is the circle round its ring's outer edge |

An arm: `{edge: int, node: int (the node it leaves from), heading: float (out of the junction, as locate's; a
roundabout's is the bearing from its middle),
width: float, class: String, mouth: Vector3 (where its plain road starts, on its centre line), main: bool (one of
the two arms of the junction's through road: the widest pair nearest straight on)}`.

### Markings and signs (T8's RoadMarkings)

`RoadMarkings.paint(block, kit) -> {"lines": AdventureProps arrays, "signs": AdventureProps arrays}`, from the
block's anchor; `{}` when `kit` is (the place's country isn't known). `_lay_out` asks for it first, with
`RegionKit.at_frame` of the block's middle. When it gives something, the block draws its `lines` as its paint (in
place of the plain white lines: `AdventureSurface.line_material` takes the paint's own colours, so a country's
yellow shows) and its `signs` with its buildings; otherwise the plain white lines as before. It reads only what this
note lists: pieces (points, at, width, lanes, class, surface, oneway, a, b, ring, edge), junctions (kind, arms with
main, radius, pos), `net.mouth`, `net.junction_of`, `net.length_of` and the block's building count. It's pure, so it
runs on the worker and every machine paints the same.

What it paints, from the country's facts (data/countries.json) and its markings' style (data/road_marks.json):
centre and edge lines in the country's colours and patterns (and in town, Britain's double yellows or the kerb
paint), a give-way or a stop across the lanes coming in on every side road's mouth and every roundabout entry, the
stop word painted before a stop where the country does, Britain's give-way triangle and mini roundabout disc; and
on poles beside them the give-way, stop (its word in the local script: SignWords, data/sign_glyphs.json) and
roundabout signs, and a junction warning `WARN_AHEAD` m up each main road into one.

## What each thread uses

- **T7 satnav.** `locate` for where a rider is on the graph (edge, s, which way they face from heading); the
  graph itself is RealRegion's (RoutePlanner already routes on it). A junction's arms are its exits, clockwise, so
  "second exit" is counting arms; `main` says which way is straight on.
- **T8 markings and buildings.** Pieces carry width, lanes, class, surface and oneway; junctions carry kind, arms
  with their mouths, outline and island, which is everything a stop line, give-way, hatching, a roundabout's
  arrows or a kerb needs. T8's markings (RoadMarkings, below) paint them in the country's way; where the country isn't known, T6's plain white edge and centre lines. Buildings: the
  block hands over its rows with their ground; T8's kits replace how they're drawn, not which ones stand.
- **T9 co-op.** Blocks are keyed and hashed in the region frame, so two machines on the same region build the same
  block and can compare `hash`. Positions on the wire stay as AdventureWorld tags them today.
- **T10 traffic.** Pieces' points are lane-ready centre lines (a lane's centre is at lat = +-width / 4 on a
  two-lane road, the side from the country's driving side); junction arms and oneway say where a car may turn.
- **T5 terrain.** Gives the net its `height(x, z)`, and asks `ground_at` / `roads_near` back for the land near
  roads.

## The toggle

Esc > Debug > "Road network (test)". Off (the default), the ride is v1's single line, unchanged. On, a new ride
streams road blocks round each rider instead of the line's chunks, and the planned route is drawn on the map only.
It's per machine for now (co-op on the network is T9's). The streamer is `RoadStreamer` (scripts/road_streamer.gd,
`AdventureWorld.roads`): blocks within 1.1 km of any rider, kept to 1.5 km, laid out on two workers, one put in a
frame, laid out again on the terrain's `ground_arrived`. The land round the roads is T5's RealLand in its network
mode (`land.set_roads(net)`, `RealLand.roam`).
