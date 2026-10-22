# Ride anywhere: the plan from here

Written 22 October 2026. Replaces stages 5 and 6 of `docs/real_world_plan.md`, which were written when the magazine
still existed and every adventure was a baked single road. Stages 0 to 4 of that plan are built and the game has
changed shape since, so the remaining steps are redesigned here.

## Where we are

- Every adventure is a journey the crew plans on a shed TV (the Route planner channel, `RouteTv`): pins on a real
  region's map, a style of ride, forks to vote on, the host's Start. Every machine plans the same road from the same
  pins (`RoutePlanner`, `AdventurePlans`) and a hash proves it. The made-up roads and the magazine are gone.
- A region is a baked folder (`tools/region_bake.py`): the roads of an area as a graph, the land at three levels, the
  buildings, places, stops and landmarks beside any road. Two are bundled (Shodoshima, 9 MB zipped; the Yorkshire
  Dales, 23 MB). `RegionStore` can download a zipped region and check its hash, but nothing calls it and nothing is
  hosted; the TV shows the first region the game has and there is no way to choose another.
- The baker is Python: Overture Maps (GeoParquet on S3, read anonymously with pyarrow) for roads, land cover, water,
  buildings, places and divisions; Mapterhorn tiles (AWS Terrain Tiles as a fallback) for heights. A bake needs the
  network and takes minutes per region.

## The goal, restated

The crew stands at the shed TV, finds anywhere on Earth, drops pins, and rides it together. The first ride somewhere
new may wait a little while the place arrives; a place ridden once rides again offline; everyone on the ride has the
same bytes.

## Facts that shape the design

- **Heights are the bytes.** Of the Dales' 36 MB, 35 MB is height tiles and 1.2 MB is everything else (4,800 roads,
  12,000 buildings, 331 stops, 208 landmarks, 78 places). Roughly 50 KB per km² with heights, 2.5 KB per km² without.
- **Mapterhorn is made for fetching.** It serves Terrarium height tiles over HTTP on a CDN
  (`tiles.mapterhorn.com/{z}/{x}/{y}.webp`, 512 px, z0 to z17), and the web-mercator pyramid is already a
  fine/coarse/ridge scheme. It states no usage limits; we would ask, cache on disk, back off on 429 and keep the
  public-domain AWS tiles as the fallback.
- **Overture's own tiles are not for us.** Its PMTiles are "for data inspection only... don't use these tiles in
  production" ([Overture cloud sources](https://docs.overturemaps.org/getting-data/cloud-sources/)). Roads,
  buildings and places have to come from the parquet, through our baker, or from tiles we cut ourselves.
- **A bake is minutes, not seconds.** Each Overture query scans partitioned parquet on S3. Nothing we do makes a
  fresh place arrive in the seconds a ride-along stream needs; it has to be baked ahead, or while the crew plans.
- **Static files are cheap; services are not free.** Cloudflare R2 costs about $0.015 per GB a month with no egress
  charge: the whole UK with heights (about 12 GB) is under a pound a month. GitHub release assets are free for a
  handful of regions. A compute service costs money and attention whenever it runs.

## The design

### Cells, not regions

The world is cut into a fixed grid of **cells**, 0.25° of latitude by 0.25° of longitude (28 km square at the
equator, 28 by 16 km in the Dales). A cell is what a region is today (`region.json`, `roads.json`, tiles at three
levels, buildings, places, stops, landmarks), baked by the same baker for the cell's box, with these changes:

- A road that crosses the cell's edge is cut there, with a node on the boundary. The matching node in the next cell
  has the same geographic position, so cells stitch by position.
- Everything is stored in geographic coordinates (lat, lon as fixed-point integers), not a frame of the cell's own, so
  cells can be projected into any frame. Height tiles stay rasters in the cell's local frame, as now.
- The index names each cell by its grid position, hash, bytes, Overture release and baker version. A country is a few
  hundred cells (the UK about 530 with roads in them; Shikoku about 50).

The two bundled regions are re-cut into cells so there is one format and one code path, and the tests ride cells.

### A journey has its own frame

Today the route frame is the region's. From here the planner makes a frame for each journey (metres from the first
pin's cell centre, +x east, -z north, scaled by the cosine of its latitude: the baker's `Frame`), and projects the
cells the journey touches into it on load: `RealRegion.stitch(cells, frame)` returns one `RealRegion`, so
`RoutePlanner`, `RealPack` and everything downstream are unchanged. `RealTerrain` holds each cell's tiles with that
cell's frame and converts a sample point through it; the conversion is a handful of multiplications, on the worker
threads that already sample it.

Which cells a journey needs: those under the pins' bounding box plus a margin of one cell, planned, then any cell the
planned road enters that was not loaded, then planned again (two rounds settle it). The road's run-out and forks
stay within the loaded set.

### Cells arrive as static files

Cells are hosted as plain files on an object store (R2 recommended; GitHub release assets for the first few), named
by grid position and content hash, with one index file per release. There is no service: the game fetches
`cells/<release>/<lat>_<lon>-<hash>.zip`, checks the hash, and unpacks it into `user://cells/`. `RegionStore` grows
into `CellStore`: a queue of fetches with progress, a least-recently-used cap (1 GB by default; the cells of a saved
adventure are never evicted; a settings button clears the rest).

**Pre-baking a country** is a one-off: the baker runs over every cell of a box, in parallel, and uploads. A country
is a day or two of a single machine's time. The UK, then the areas the crew asks for, then wherever anyone wants, in
the order people ask. Shodoshima and the Dales stay bundled so the game plays offline out of the box.

**Streaming** is at the cell level: a long journey downloads its cells before Start (the ready-check below), and the
ride streams chunks from them as it does today. A ride never waits on the network.

### Co-op: the ready-check

The adventure state carries the journey's cell list (grid positions, release, hashes). When the host presses Start,
every machine that lacks a cell fetches it; the TV shows who is ready; the ride begins when everyone is. Everyone
plans the same road from the same cells and the same pins, and the hash check stays as it is. A machine that cannot
fetch (offline, or the host's cells are a release it cannot get) says so on the TV and the host decides.

### The TV at world scale

The Route planner channel gets a world view above the cell view:

- A **basemap** from Natural Earth (public domain: coastlines, countries, lakes at 1:10m, a few MB simplified) and a
  bundled **place index** cut from Overture divisions (towns of some size the world over, name, country and position:
  about 2 MB), so the crew can search "Settle" or "Takamatsu" with nothing downloaded.
- Search or step to a place, and the TV shows which cells round it are **available** (in the index), **installed**
  (on this machine) or **not baked yet**. A "Get this area" button fetches the available ones; pins can only go on
  installed cells, and snap to the nearest road as now.
- Zoomed in, the cell view is today's region view: roads, places, the planned road, pins, forks.

A paste box for a map link (a Google Maps share link gives only its coordinates; the road is always ours) is a small
addition once the world view exists.

### Keeping journeys

With the magazine gone, "the feed" is simply the crew's own journeys: the Route TV lists journeys the crew has
ridden (from the diary, which already keeps the route and the pins), and any of them can be pinned again with one
press. A journey is also a **code**: the cell release, the pins and the style packed into a short string the crew
can paste to each other or post, so a journey someone else planned can be ridden exactly.

### Heights live from Mapterhorn (the step after, if wanted)

If the game fetched heights itself, straight from Mapterhorn's pyramid (fine from z15, coarse from z12, the skyline
from z9, cached on disk), our cells would shrink to the 2.5 KB per km² of roads and buildings, and the whole world's
vector cells would be about 400 GB: still too much to pre-bake blind, but a country would be 600 MB and any area the
crew asked for could be baked in minutes rather than hours. It also makes heights available anywhere on Earth today.

The cost is determinism: Mapterhorn updates tiles as national sources arrive, so two machines can hold different
heights for the same hill, and the road's own heights come from the land. The fix is that the host's plan carries the
planned road's knot heights (about 30 KB for a 60 km ride) and every machine lays the road on those; the land beside
it may differ by centimetres between machines, which only off-road crashes would notice. This step is worth doing
only once pre-baked countries are not enough; it is designed here so the cell format leaves room for it (cells
without height tiles are valid), and not scheduled.

## The steps

Each step is a playable change on its own and lands as one or two pull requests.

### Step 1: choose a region, download a region

**Plays.** The Route TV lists the regions the game knows of; one press downloads one that isn't installed, with
progress; the crew's ready-check holds Start until everyone has the region. Six to ten regions people would want to
ride (Snowdonia, the Lake District, the Peak District, Skye, the Cairngorms, Shikoku's coast, the Noto peninsula...)
are baked with today's baker and hosted as release assets.

**Builds.** A region picker on the TV; `RegionStore` wired to it with progress; the ready-check in the adventure
state and on the TV; `tools/region_zip.py` writing the hosted index; a `tests/mp_*` scene where the client lacks
the region and gets it from a local file server before the ride.

**Size.** About a week, plus bake time.

### Step 2: cells

**Plays.** The same, but a journey can cross from one region into the next: the Dales into the Lake District.

**Builds.** The baker cuts cells (boundary nodes, geographic coordinates, the cell index); `RealRegion.stitch` and
the journey frame; `RealTerrain` with per-cell frames; the two bundled regions re-cut into cells; `CellStore` with
the cache cap; the planner's two rounds of cell loading; the tests on cells. Measure load time: the Dales' 36 MB of
JSON takes seconds to parse, and a journey may load eight cells, so `roads.json` and `buildings.json` likely move to
a binary form in this step.

**Size.** About three weeks.

### Step 3: the world on the TV, and a country of cells

**Plays.** Search for any town in the UK, get the area, pin, ride.

**Builds.** The world view (basemap, place index, cell availability, Get this area); the UK pre-baked to R2 with
`tools/cells_bake.py` driving `region_bake.py` over a box in parallel; the index per release; credits generated from
the cells a journey used.

**Size.** About three weeks, plus a day or two of baking.

### Step 4: real roads that look right

The polish the old plan left in stages 2 and 3, now that there is one renderer to polish:

- Bridges and tunnels from the road flags: a river valley gets a bridge, not a cutting (today the road is cut into
  the land everywhere).
- Water for rivers and lakes beside the road (the sea exists).
- The planner's cusp at a pin (queued).
- Trees: species and height from the cover and canopy data, and a better look.

Interleaved with steps 2 and 3 as rides turn up the ugliest cases. About three weeks in all.

### Step 5: journeys kept and shared

**Plays.** The Route TV lists the crew's past journeys to ride again; a journey can be shared as a code.

**Builds.** The journeys list from the diary; journey codes; a paste box for a code or a map link.

**Size.** About a week.

### Step 6 (optional): the rest of the world

Either more countries pre-baked as people ask (no new code), or heights live from Mapterhorn and vector cells baked
on request by a small service in `us-west-2` (where Overture's bucket is, so its reads are free). Decide when step 3
is in people's hands and we know where they want to ride.

## What is dropped from the old plan

- **The magazine feed** (stage 6): there is no magazine. Journeys kept and shared (step 5) is what remains of it.
- **The hand-edit overlay and the standalone viewer** (stage 2): hand edits do not scale to anywhere on Earth. In their
  place the baker's report becomes warnings the TV can show for a cell ("thin height data here", "no fuel for 60 km").
- **The staged, cached pipeline with budgets** (stage 2): the per-chunk budgets are enforced in the game's tests
  instead (`test_budget`), and a cell bake is already cached by content hash.
- **Traffic lights from data**: the data has none; the game keeps giving a town crossroads its lights.

## Decisions

Recommended, and taken unless you say otherwise:

- Cells of 0.25°, hosted as static files; no bake service until step 6 if ever.
- Heights stay baked in the cells (deterministic, offline, the code we have); heights live from Mapterhorn is kept
  open as the planet-scale route, not built now.
- Cloudflare R2 for cells (free egress; a country for pennies a month); GitHub release assets for step 1's regions.

Yours to make:

- **Which regions for step 1**, and **which country first** for step 3 (the plan says the UK).
- **Hosting account**: an R2 bucket needs a Cloudflare account in your name; I can set out the steps.

## Risks

| Risk | Where it is settled |
| --- | --- |
| Cell load time and memory with several cells of JSON | step 2, measured first; binary files if needed |
| Cells baked from different Overture releases don't stitch | the index is per release; a journey's cells are one release |
| Mapterhorn or GSI terms for redistributing heights (Japan) | before the first hosted Japanese cells, as before |
| Bake time per cell (minutes) makes a country days | step 3, run in parallel on one machine; measured on the first ten cells |
| A thin place (no lidar, few roads) rides badly | the cell's warnings on the TV; the planner avoids it where it can |
