# Ride anywhere: the plan from here

Written 22 October 2026. Replaces stages 5 and 6 of `docs/real_world_plan.md`, which were written when the magazine
still existed and every adventure was a baked single road. Stages 0 to 4 of that plan are built and the game has
changed shape since, so the remaining steps are redesigned here.

## The goal

The whole world is on the shed TV. The crew moves about the map together, drops pins anywhere, the game plans the
road, the crew agrees to it, and they ride. There is no "region" the player has to pick, download or know about.
Everyone on the ride has the same bytes, a place ridden once rides again offline, and **nothing costs money month
to month**: no server, no metered hosting.

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

- **Heights are the bytes.** Of the Dales' 36 MB, 24 MB is height tiles and 8.5 MB is land cover at 4 m; roads,
  buildings, places and stops are 1.2 MB. Without heights, and with cover at 16 m, a cell is about 5 KB per km²: the
  UK about a gigabyte, Japan one and a half.
- **Mapterhorn already serves the world's heights for free.** Terrarium tiles over HTTP on Cloudflare's CDN
  (`tiles.mapterhorn.com/{z}/{x}/{y}.webp`, 512 px, z0 to z17, [data access](https://mapterhorn.com/data-access/)),
  no key, no stated limits; AWS Terrain Tiles are a public dataset behind it. The web-mercator pyramid is already a
  fine/coarse/ridge scheme. We fetch what the baker fetches today, in the game instead.
- **Overture's own tiles are not for us.** Its PMTiles are "for data inspection only... don't use these tiles in
  production" ([Overture cloud sources](https://docs.overturemaps.org/getting-data/cloud-sources/)). Roads,
  buildings and places come from the parquet through our baker.
- **A bake is minutes, not seconds**, and the planet cannot be baked blind (several terabytes with heights, 400 GB
  without). The world is baked where people point, ahead of the ride.
- **The repository is public**, so GitHub Actions minutes are free and unlimited, and release assets are free (2 GB
  a file). Cloudflare Workers' free tier is 100,000 requests a day. These are the free compute and hosting the
  design rests on; the road data is ODbL and has to be published anyway.

## The design

### Heights straight from Mapterhorn

`RealTerrain` reads height tiles itself (`HeightTiles`): fine from z14 (2.8 m a pixel in the Dales, 3.9 m on
Shodoshima), middle from z11, the skyline from z9, each level bilinear in the tile's own pixels and eased into the next
over 48 pixels where the ride's tiles end, the sea given a floor sloping down from the shore, the ground levelled
under each building, and the skyline pushed down near the road, all as the baker does them. Measured: a tile decodes
in 9 ms, a height costs a few microseconds (a baked one about 7), and the 68 km Dales tour needs 103 tiles, 9 MB,
fetched in about 3.5 s, eight at a time. Tiles are fetched on the planner's worker once the road's line is known, kept on
disk under `user://heights/`, and decoded into memory as they are sampled (the 160 most recently used are kept).
The bundled regions keep their baked heights, so the game plays offline out of the box and its tests never touch the
network (they ride on a few megabytes of tiles in `tests/fixtures/heights`).

The same road gets the same heights on every machine: the tiles a ride uses are those within a set reach of its road
(and of its forks' other ways), fixed by the road alone, never by what else a machine has on disk; and with live
heights the plan's hash takes in the road's heights to the 10 cm, so a machine that was given a different tile (Mapterhorn
updates tiles as national sources arrive) is told it planned a different road rather than riding one. We attribute
Mapterhorn in the credits, ask them about the load, and fall back to AWS's tiles.

### Cells: the unit nobody sees

Inside the game the world is a fixed grid of **cells**, 0.25° of latitude by 0.25° of longitude (28 km square at the
equator, 28 by 16 km in the Dales). A cell is a region in today's format, baked by today's baker for the cell's box
(`region_bake.py --cell LAT LON`) with live heights and its own frame at its middle, with two changes:

- Every bit of road is kept (a stub at the edge is part of a network in the next cell), and each junction and road
  carries a short id from its Overture connector and segment. A road that crosses the edge is in both cells, whole,
  with the same ids, so the game joins them up by id: no cutting, no matching positions.
- Its frame is its own, but every frame is the baker's flat one, so moving a cell into an area's frame is a scale and a
  shift of x, and of z (`RealRegion.stitch`). Buildings, places and stops on an edge both cells have are kept once.

A region the game plans over is an **area**: the cells a box covers, stitched into one region in a frame of its
choosing (`RealRegion.area`); a named one (`areas.json` beside the cells) is listed with the regions as `area:<name>`.
The planner, the plan cache, co-op's hash and everything downstream are unchanged. The player never meets a cell.

Measured on the Dales: a cell bakes in about two minutes and is 9.7 MB, 8 MB of it the land's cover at 4 m (cutting
that to 16 m, before the world is served, brings a cell to about 2 MB); two cells stitch in about 0.4 s. The road from
Gunnerside to Grinton over the two cells either side of 2° W is the bundled Dales region's road to 14 cm, its heights
to 8 cm on average.

The bundled regions stay as they are: re-cutting them into cells would move every road the tests know, for no gain to
the player. Cells come to the game from step 3 on.

### Cells baked by GitHub Actions, served as release assets

A public **data repository** ([`torque-shed-world`](https://github.com/Beenster99/torque-shed-world)) holds the bake
workflow and the index, nothing else of size. The workflow (**Bake cells**, run on request) takes points or boxes,
leaves out the cells the index already has, bakes the rest with the game's own `region_bake.py --cell` 20 at a time
(about a minute and a half each), uploads each as a release asset (`cROW_COLUMN-HASH.zip`, one release per 5° block,
so no release holds too many), and adds them to `index.json` (hash, bytes and download for each cell, or that it has no
roads). Zipped, a Dales cell is 0.4 to 0.6 MB. The game fetches cells by URL (`CellStore`, following the download's
redirect), checks the hash and keeps them under `user://cells/`; the index is kept there too, so a crew offline still
has what it fetched before. (A cap on what's kept, and a button to clear it, are still to come.)

Nothing runs between bakes and nothing is metered: Actions are free on a public repository, release assets are free,
and GitHub's CDN serves them. A new Overture release is a new GitHub release; cells are rebaked by the same workflow
and old cells stay valid for saved adventures, which name their cells by hash.

**Warming the world** is running the workflow over boxes: the UK and Japan first, then wherever is asked for.

### Asking for somewhere new

A place nobody has baked shows on the TV as "not surveyed yet" with a **Survey** button. The button calls a
Cloudflare Worker (free tier) that holds the one secret the game must not: a token that fires the data repository's
bake workflow for that cell. The worker rate-limits (a few cells a minute, the world over) and refuses what the index
already has. Ten minutes later the index has the cell and the TV shows it. This is the only moving part, and it
stops working, not costing, if the free tier ever goes.

Without the worker the design still stands: the world is wherever we have baked, and asking is a message to us.

### A journey has its own frame

Today the route frame is the region's. From here the planner makes a frame for each journey (metres from the first
pin, +x east, -z north, scaled by the cosine of its latitude: the baker's `Frame`), and projects the cells the
journey touches into it on load: `RealRegion.stitch(cells, frame)` returns one `RealRegion`, so `RoutePlanner`,
`RealPack` and everything downstream are unchanged. `RealTerrain` answers in the journey's frame by converting the
point to a tile pixel.

Which cells a journey needs: those under the pins' bounding box plus a margin of one cell, planned; then any cell the
planned road enters that was not loaded, and planned again (two rounds settle it). A journey far longer than a cell
is fine: the Dales to the coast is a dozen cells, a few megabytes, fetched before the ride, not during it.

### The TV: the world

The Route planner channel becomes a map of the world:

- **The globe down to the county**: a basemap bundled with the game from Natural Earth (public domain: coastlines,
  countries, rivers, lakes; a few MB simplified), the game's own place index cut from Overture divisions (towns the
  world over with name, country and position: about 2 MB) for search and labels, and a sketch of the world's main
  roads (motorways, trunk and primary roads, baked once by Actions and served as release-asset tiles, a few hundred
  MB in all) so the map reads as a map between the county and the cell.
- **Close in**: the cell view is today's region view, with every road, place and stop, the planned road, pins and
  forks. As the view closes in on somewhere, the game fetches the cells in view; baked ones appear in a second or
  two, unbaked ones say "not surveyed yet" with the Survey button. Pins can be dropped on the sketch of the main
  roads straight away and snap onto the real roads when the cell arrives.
- **Moving about together**: the view (centre and zoom) is part of the shared journey state, so the crew looks at the
  same map; anyone can move it and anyone can pin, as today. Search, zoom and move are buttons for the touch cursor,
  as now, and a paste box takes a map link's coordinates (a Google Maps share link gives its coordinates only; the
  road is always ours).

### Consensus

Pins are already anyone's, and forks are already voted on the road. Agreeing the route works the same way: each
rider on the TV has an **"I'm in"** mark beside their name for the journey as it stands; moving a pin clears
everyone's. Start lights up when everyone is in (the host can start with a majority if someone has wandered off),
and Start also runs the **ready-check**: every machine fetches any cell or height tile of the journey it lacks, the
TV shows who is ready, and the ride begins when everyone is. The road is planned on every machine from the same
cells and pins, laid on the host's heights, and the hash check stays. A machine that cannot fetch (offline) says so.

### Kept and shared

The Route TV lists the crew's past journeys from the diary to pin again with one press, and a journey is a **code**
(release, pins, style) the crew can paste to each other.

## The steps

Each step is a playable change on its own and lands as one or two pull requests. Sizes are guesses to plan around.

### Step 1: heights from Mapterhorn

**Plays.** Nothing new to see yet: a region baked with `--heights live` (a third of the size, no height tiles) rides
like a baked one, its land read from Mapterhorn's tiles; the bundled regions stay baked.

**Builds.** `HeightTiles` (mercator maths, decode, the disk cache, fetching with the AWS fallback); `RealTerrain`'s
live levels with the eased edges, the sea floor and the building pads; a ride's own view of the land (`for_road`,
`widen` for forks) and the heights in the plan's hash; the skyline pushed down by the road in `RealRidges`; the map's
picture of a live region; `region_bake.py --heights live`; tests on fixture tiles checking the live road and land
against the baked ones.

**Status.** Built (`claude/live-heights`). On Shodoshima the live road's heights are 4 cm from the baked road's on
average (0.6 m at most), and the land beside it the same.

### Step 2: cells, and a journey across them

**Plays.** A journey can cross from one cell into the next; an area of cells is a region like any other.

**Builds.** `region_bake.py --cell`; `RealRegion.stitch` and `area`, named areas; cover read from each cell's own tiles
(`RealTerrain.add_cover_cell`); tests on two Dales cells against the bundled Dales region.

**Status.** Built (`claude/cells`). Left for step 3: the cover at 16 m, and loading a dozen cells off the main thread
(the route planner TV loads its region when it is shown).

### Step 3: the world baked and served

**Plays.** A cell the game lacks arrives from GitHub. Riders on the road wait at the start, held there, until the
whole crew has the road (its cells and land fetched and planned), 90 seconds at most.

**Builds.** The data repository, its bake workflow and index; cells' cover at 16 m (a cell about 2 MB, half a megabyte
zipped); `CellStore` (the index, fetching with the hash checked); planning an area fetches its cells first, on the
planner's worker; a plan for an area is checked against its box, so a mate without the cells can take the host's
plan; entering a ride waits for the road a frame at a time instead of holding the game up; the wait at the start
(`AdventureTrip.crew_waiting`). Tests fetch the Dales cells from a stand-in for GitHub on the machine.

**Status.** Built (`claude/world-served`), and the workflow has baked its first two cells. Still to do: the UK and
Japan baked; a cap on the cells kept; progress on the TV while an area's cells come.

### Step 4: the world on the TV

**Plays.** Search for Settle or Takamatsu, or move the map there; the crew sees the same view; close in and the
roads arrive; pin anywhere; press Survey where nobody has been.

**Builds.** The basemap and place index bundled; the main-roads sketch baked and served; the shared view in the
journey state; cells fetched for the view; the Survey button and its worker; the paste box; credits generated from the
cells and tiles a journey used.

**Size.** About three weeks.

**Status.** Part built. `claude/world-tv`: the view is the crew's (`Shed.route_tv`, changed through the host by
`adventure_view`), so every Route planner screen on every player's game shows the same; the Dyno Room has a wall-sized
planning TV. `claude/world-map`: the world on the TV (`WorldView`: Natural Earth's land, lakes, rivers, borders and
7,342 towns and cities, `data/world` by `tools/world_bake.py`, 7.8 MB), the view as latitude, longitude and metres
across, a search with the TV's own keyboard, the roads of the cells in view fetched and stitched on a worker under
60 km across, and pins anywhere there are roads: a journey is an area of listed cells (`area:@...`, the cells along
the pins' line and one either side, the frame at the first pin's cell), worked out by the host from the pins' latitude
and longitude. `claude/survey`: the Survey button over cells nobody has baked, the host asking the survey worker
(`torque-shed-world/worker/survey.js`, a Cloudflare Worker on the free plan, with the only secret: a token that can run
the bake workflow and nothing else; "busy" while three bake runs are going), the crew's survey in the shared view, and
the TVs looking at the index every minute until the cells come. `claude/map-links`: Paste a map link (Google, Apple,
OpenStreetMap, short links followed, plain lat, lon), the map data credited under a planned road, and the Esc menu's
planner the TVs' planner full screen (the region-by-region map gone). `claude/main-roads`: the sketch of the main
roads (motorways, trunk and A roads, joined through their junctions and simplified to 40 m by `tools/sketch_bake.py`,
about 12 KB a cell) made as each cell is baked and merged into a file per 5 degree block in the world's repo
(`sketch/bR_C.json`, named by its hash in `index.json`), drawn between 60 km and 1,500 km across and kept on disk; the
cells baked before were sketched by its "Sketch the main roads" workflow. Still to do: a better coast close in
(Natural Earth's is coarse beside the roads). Pins still go down only where the roads are fetched, not on the sketch.

### Step 5: consensus, and journeys kept

**Plays.** "I'm in" marks, Start when everyone is in; past journeys to ride again; journey codes.

**Size.** About a week.

**Status.** Built. `claude/journeys-kept`: the "I'm in" marks (`Shed.journey["in"]`, `adventure_in`, cleared when a
pin moves or the style changes, and when a ride starts), the TV's line of who is in, and the host's Start waiting for
everyone in the shed or a majority. The ready-check was already the trip's "Getting the road ready". Journeys kept: each
diary keeps its ride's pins and style (and the bundled map it was planned on), the TV's Past rides pins one again for
the crew (`adventure_load`), and a journey on the board copies as a code (`TS1.` and the journey, base64) to paste on
another crew's TV.

### Step 6: real roads that look right

The polish the old plan left in stages 2 and 3, now that there is one renderer to polish, interleaved with the steps
above as rides turn up the ugliest cases: bridges and tunnels from the road flags (a river valley gets a bridge, not
a cutting); water for rivers and lakes beside the road; the planner's cusp at a pin (queued); trees with species and
height from the cover and canopy data.

**Size.** About three weeks in all.

## What is dropped from the old plan

- **Regions as a thing**: the picker, the index of named regions, "download the Dales". Cells are internal.
- **Baked heights**: Mapterhorn serves them; the baker stops writing tiles and the levels code moves into the game.
- **The route service** (stage 5): it would cost money every month. Actions bake ahead of the ride instead.
- **The magazine feed**: there is no magazine. Past journeys and journey codes are what remains of it.
- **The hand-edit overlay and the standalone viewer**: hand edits do not scale to anywhere on Earth. The baker's
  report becomes warnings the TV can show for a cell ("thin height data here", "no fuel for 60 km").
- **The staged, cached pipeline with budgets**: per-chunk budgets are enforced in the game's tests (`test_budget`),
  and the index is the cache.
- **Traffic lights from data**: the data has none; a town crossroads keeps its lights.

## Decisions

Recommended, and taken unless you say otherwise:

- Heights live from Mapterhorn, the road's heights from the host.
- Cells of 0.25°, an internal unit only, baked by GitHub Actions in a public data repository and served as release
  assets.
- A Cloudflare Worker on the free tier for the Survey button; the design stands without it.

Yours to make:

- **The data repository** has to be created under your account (public; I can set it up once it exists), and the
  **Cloudflare account** for the worker, if you want Survey. Both free.
- **Which places to bake first.** The plan says the UK and Japan.

## Risks

| Risk | Where it is settled |
| --- | --- |
| Tiles decoded on the fly cost frame time, or the z9 skyline looks worse than the baked ridge | step 1, measured first |
| Mapterhorn's load from a game, or its terms, or its availability | step 1: ask them; cache; AWS fallback; the bundled areas ship their tiles |
| Cell load time and memory with a dozen cells of JSON | step 2, measured; binary files if needed |
| GitHub's fair use for release storage as the world grows | step 3: a country is about a gigabyte; the world is baked as asked, not whole |
| A free tier changes its terms | each piece stops working rather than costing; the bundled areas always play |
| Cells from different releases don't stitch | the index is per release; a journey's cells are one release |
| GSI terms for Japanese heights | moot: nothing is redistributed, the game fetches from Mapterhorn as any map does |
| A thin place (no lidar, few roads) rides badly | the cell's warnings on the TV; the planner avoids it where it can |
