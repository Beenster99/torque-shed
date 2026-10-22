# Ride anywhere: the plan from here

Written 22 October 2026. Replaces stages 5 and 6 of `docs/real_world_plan.md`, which were written when the magazine
still existed and every adventure was a baked single road. Stages 0 to 4 of that plan are built and the game has
changed shape since, so the remaining steps are redesigned here.

## The goal

The whole world is on the shed TV. The crew moves about the map together, drops pins anywhere, the game plans the
road, the crew agrees to it, and they ride. There is no "region" the player has to pick, download or know about: a
place that nobody has ridden before takes a little while to arrive the first time, and that is all. Everyone on the
ride has the same bytes, and a place ridden once rides again offline.

## Where we are

- Every adventure is a journey planned on a shed TV (the Route planner channel, `RouteTv`): pins on a real region's
  map, a style of ride, forks to vote on, the host's Start. Every machine plans the same road from the same pins
  (`RoutePlanner`, `AdventurePlans`) and a hash proves it. The made-up roads and the magazine are gone.
- A region is a baked folder (`tools/region_bake.py`): the roads of a box as a graph, the land at three levels, the
  buildings, places, stops and landmarks beside any road. Two are bundled (Shodoshima, 9 MB zipped; the Dales,
  23 MB). The TV shows the first region the game has; `RegionStore` can download a zipped region and check its
  hash, but nothing calls it and nothing is hosted.
- The baker is Python: Overture Maps (GeoParquet on S3, read anonymously with pyarrow) for roads, land cover,
  water, buildings, places and divisions; Mapterhorn tiles (AWS Terrain Tiles as a fallback) for heights. A bake
  needs the network and takes minutes for a region.

## Facts that shape the design

- **Heights are the bytes.** Of the Dales' 36 MB, 35 MB is height tiles and 1.2 MB is everything else (4,800 roads,
  12,000 buildings, 331 stops, 208 landmarks, 78 places). About 50 KB per km².
- **A bake is minutes, not seconds.** Each Overture query scans partitioned parquet on S3, and the heights are a
  few hundred tile fetches. A fresh place cannot arrive in the seconds a ride needs; it has to be made while the
  crew is still planning, and kept once made.
- **Overture's own tiles are not for us.** Its PMTiles are "for data inspection only... don't use these tiles in
  production" ([Overture cloud sources](https://docs.overturemaps.org/getting-data/cloud-sources/)). Roads,
  buildings and places come from the parquet through our baker.
- **The planet cannot be baked blind.** At 50 KB per km² the world's roads and land are several terabytes, and most
  of it would never be ridden. The world has to be baked where people point.
- **Reads of Overture's bucket are free from `us-west-2`**, where it lives. Anywhere else pays egress for every scan.

## The design

### Cells: the unit nobody sees

Inside the game the world is a fixed grid of **cells**, 0.25° of latitude by 0.25° of longitude (28 km square at the
equator, 28 by 16 km in the Dales). A cell is what a region is today (`region.json`, `roads.json`, tiles at three
levels, buildings, places, stops, landmarks), baked by the same baker for the cell's box, with these changes:

- A road that crosses the cell's edge is cut there with a node on the boundary; the matching node in the next cell has
  the same geographic position, so cells stitch by position.
- Everything is stored in geographic coordinates (lat, lon as fixed-point integers), not a frame of the cell's own,
  so a cell can be projected into any journey's frame. Height tiles stay rasters in the cell's local frame.
- A cell is named by its grid position and carries its Overture release, baker version and content hash.

The player never meets a cell. The two bundled regions are re-cut into cells so there is one format and one code
path, and the game plays Shodoshima and the Dales offline out of the box.

### The bake service

A small web service in `us-west-2` runs the Python baker on request: `GET /cell/<lat>/<lon>` returns the cell when it
is in the cache, else starts a bake and answers "making it, about N minutes" until it is done. Baked cells go to an
object store keyed by grid position and release, and are served from there (through a CDN) ever after: the second
crew to ride the Peak District waits for nothing.

The service is stateless apart from its cache and queue; one container does it, scaled out if ever needed. Its
release is pinned: every cell served between releases is from the same Overture data, so neighbours stitch. When a
new release is taken up, cells are rebaked as they are next asked for (the old ones stay valid for saved adventures,
which name their cells by hash).

Pre-baking is only warming the cache: the UK, Japan and wherever else is run through the service before launch so
the places people go first are instant. It changes nothing in the game.

### A journey has its own frame

Today the route frame is the region's. From here the planner makes a frame for each journey (metres from the first
pin, +x east, -z north, scaled by the cosine of its latitude: the baker's `Frame`), and projects the cells the
journey touches into it on load: `RealRegion.stitch(cells, frame)` returns one `RealRegion`, so `RoutePlanner`,
`RealPack` and everything downstream are unchanged. `RealTerrain` holds each cell's tiles with that cell's frame
and converts a sample point through it.

Which cells a journey needs: those under the pins' bounding box plus a margin of one cell, planned; then any cell the
planned road enters that was not loaded, and planned again (two rounds settle it). A journey far longer than a cell
is fine: the Dales to the coast is a dozen cells, fetched before the ride, not during it.

### The TV: the world

The Route planner channel becomes a map of the world:

- **The globe down to the county**: a basemap bundled with the game from Natural Earth (public domain: coastlines,
  countries, rivers, lakes; a few MB simplified), the game's own place index cut from Overture divisions (towns the
  world over with name, country and position: about 2 MB) for search and labels, and a sketch of the world's main
  roads (motorways, trunk and primary roads, baked once from Overture: a few hundred MB hosted, fetched as tiles) so
  the map reads as a map between the county and the cell.
- **Close in**: the cell view is today's region view, with every road, place and stop, the planned road, pins and
  forks. As the view closes in on somewhere, the game asks the service for the cells in view; cached ones appear in a
  second or two, fresh ones show "surveying this area, about 4 minutes" and fill in when done. Pins can be dropped on
  the sketch of the main roads straight away and snap onto the real roads when the cell arrives.
- **Moving about together**: the view (centre and zoom) is part of the shared journey state, so the crew looks at the
  same map; anyone can move it and anyone can pin, as today. Search, zoom and move are buttons for the touch cursor,
  as now, and a paste box takes a map link's coordinates (a Google Maps share link gives its coordinates only; the
  road is always ours).

### Consensus

Pins are already anyone's, and forks are already voted on the road. Agreeing the route works the same way: each
rider on the TV has an **"I'm in"** mark beside their name for the journey as it stands; moving a pin clears
everyone's. Start lights up when everyone is in (the host can start with a majority if someone has wandered off),
and Start also runs the **ready-check**: every machine fetches any cell of the journey it lacks, the TV shows who is
ready, and the ride begins when everyone is. The road is planned on every machine from the same cells and pins, and
the hash check stays as it is. A machine that cannot fetch (offline) says so on the TV.

### Kept and shared

Cells live under `user://cells/` with a least-recently-used cap (1 GB by default; a saved adventure's cells are never
evicted; a settings button clears the rest). The Route TV lists the crew's past journeys from the diary to pin again
with one press, and a journey is a **code** (release, pins, style) the crew can paste to each other.

### Heights live from Mapterhorn (kept open)

The game could fetch heights itself from Mapterhorn's tile pyramid (fine from z15, coarse from z12, the skyline from
z9), which would cut a cell to the 2.5 KB per km² of roads and buildings and make a fresh bake much faster. The cost
is determinism (Mapterhorn updates tiles, so two machines could hold different land; the host would have to send the
road's knot heights with the plan, about 30 KB). With the service baking heights into cached cells, everyone gets the
same bytes for free, so this is not built; the cell format leaves room for it (a cell without height tiles is valid).

## The steps

Each step is a playable change on its own and lands as one or two pull requests. Sizes are guesses to plan around.

### Step 1: cells, and a journey across them

**Plays.** As today, but a journey can cross from one baked area into the next, and the two bundled regions are
cells like any other.

**Builds.** The baker cuts cells (boundary nodes, geographic coordinates, the cell index); `RealRegion.stitch` and
the journey frame; `RealTerrain` with per-cell frames; the bundled regions re-cut; the planner's two rounds of cell
loading; the tests on cells. Measure load time: the Dales' 36 MB of JSON takes seconds to parse and a journey may
load a dozen cells, so `roads.json` and `buildings.json` likely move to a binary form here.

**Size.** About three weeks.

### Step 2: the service, and the ready-check

**Plays.** A cell the game lacks arrives from the service. The host's Start waits until everyone has the journey's
cells, with progress on the TV.

**Builds.** The service (the baker in a container, a queue, the cache bucket, the "making it" reply); `CellStore`
in the game (fetch queue, hash check, progress, the cache cap); the ready-check in the adventure state and on the TV;
a two-player test where the client lacks a cell and gets it from a local file server standing in for the service;
the UK warmed into the cache.

**Size.** About three weeks, plus setting up the hosting.

### Step 3: the world on the TV

**Plays.** Search for Settle or Takamatsu, or move the map there; the crew sees the same view; close in and the
roads arrive; pin anywhere.

**Builds.** The basemap and place index bundled; the main-roads sketch baked and hosted; the shared view in the
journey state; cells fetched for the view with the "surveying" state; the paste box; credits generated from the cells
a journey used.

**Size.** About three weeks.

### Step 4: consensus, and journeys kept

**Plays.** "I'm in" marks, Start when everyone is in; past journeys to ride again; journey codes.

**Size.** About a week.

### Step 5: real roads that look right

The polish the old plan left in stages 2 and 3, now that there is one renderer to polish, interleaved with the steps
above as rides turn up the ugliest cases:

- Bridges and tunnels from the road flags: a river valley gets a bridge, not a cutting.
- Water for rivers and lakes beside the road (the sea exists).
- The planner's cusp at a pin (queued).
- Trees: species and height from the cover and canopy data, and a better look.

**Size.** About three weeks in all.

## What is dropped from the old plan

- **Regions as a thing**: the picker, the index of named regions, "download the Dales". Cells are internal.
- **The magazine feed**: there is no magazine. Past journeys and journey codes are what remains of it.
- **The hand-edit overlay and the standalone viewer**: hand edits do not scale to anywhere on Earth. The baker's
  report becomes warnings the TV can show for a cell ("thin height data here", "no fuel for 60 km").
- **The staged, cached pipeline with budgets**: per-chunk budgets are enforced in the game's tests (`test_budget`),
  and the service's cache is the pipeline's cache.
- **Traffic lights from data**: the data has none; a town crossroads keeps its lights.

## Decisions

Recommended, and taken unless you say otherwise:

- Cells of 0.25°, an internal unit only.
- A bake service in AWS `us-west-2` from step 2 (free reads of Overture's bucket), its cache served through a CDN.
  One container, a queue, an object store: the smallest thing that works.
- Heights stay baked in cells; heights live from Mapterhorn stays open for later.

Yours to make:

- **Hosting account.** The service needs an AWS account in your name (or another host, paying Overture egress). I can
  set out the steps and the expected monthly cost once we have measured a cell bake.
- **Which places to warm first.** The plan says the UK and Japan.

## Risks

| Risk | Where it is settled |
| --- | --- |
| Cell load time and memory with a dozen cells of JSON | step 1, measured first; binary files if needed |
| A fresh bake takes longer than a crew will wait | step 2, measured on the first ten cells; warm the cache; bake the cells in view while they plan |
| Service cost at the bake's CPU and memory | step 2, measured; the cache means each cell is baked once per release |
| Cells from different releases don't stitch | the service pins one release; a journey's cells are one release |
| Mapterhorn or GSI terms for redistributing heights (Japan) | before Japanese cells are warmed, as before |
| A thin place (no lidar, few roads) rides badly | the cell's warnings on the TV; the planner avoids it where it can |
