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

`RealTerrain` fetches height tiles itself: fine from z15 (2.8 m a pixel in the Dales), coarse from z12, the skyline
from z9, each level bilinear in the tile's own pixels, the finer level eased into the coarser in a band near its
edge, the skyline pushed down near the road as the baker does now. Tiles are fetched on a worker as the planner and
the chunks ask for ground ahead, kept on disk under `user://heights/` with a size cap, and the bundled areas' tiles
ship with the game so Shodoshima and the Dales play offline out of the box and the tests never touch the network.

Mapterhorn updates tiles as national sources arrive, so two machines could in time hold slightly different land. The
road is what matters: the host's plan carries the planned road's knot heights (about 30 KB for 60 km) and every
machine lays the road on those, so the ride is identical; the land beside it may differ by centimetres, which only an
off-road crash would notice. We attribute Mapterhorn in the credits, ask them about the load, back off on 429, and
fall back to AWS's tiles.

### Cells: the unit nobody sees

Inside the game the world is a fixed grid of **cells**, 0.25° of latitude by 0.25° of longitude (28 km square at the
equator, 28 by 16 km in the Dales). A cell is a region without its heights: `roads.json`, buildings, places, stops,
landmarks and cover at 16 m, baked by today's baker for the cell's box, with these changes:

- A road that crosses the cell's edge is cut there with a node on the boundary; the matching node in the next cell has
  the same geographic position, so cells stitch by position.
- Everything is stored in geographic coordinates (lat, lon as fixed-point integers), so a cell can be projected into
  any journey's frame.
- A cell is named by its grid position and carries its Overture release, baker version and content hash.

The player never meets a cell. The two bundled regions are re-cut into cells so there is one format and one code path.

### Cells baked by GitHub Actions, served as release assets

A public **data repository** (`torque-shed-world`) holds the baker's workflow and nothing else of size. A workflow
takes a list of cells and bakes them in a matrix (20 at a time, a few minutes each; the UK's 530 cells in an
afternoon), uploads each as a release asset named by grid position and hash, and rewrites `index.json` (cell, hash,
bytes, release, url). The game fetches cells by URL, checks the hash and keeps them under `user://cells/` with a
least-recently-used cap (1 GB by default; a saved adventure's cells are never evicted; a settings button clears the
rest).

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

**Plays.** The same rides, the regions a third of the size (their height tiles gone), the land a little truer where
Mapterhorn has improved since the bake.

**Builds.** `RealTerrain` over mercator tiles at three zooms with the eased edges and the pushed-down skyline; the
fetch worker, disk cache and cap; the bundled areas' tiles shipped; the road's knot heights in the host's plan and
laid on by every machine; a two-player test that the client rides the host's heights; the AWS fallback.

**Size.** About two weeks. The risk to settle first: frame time with tiles decoded on the fly, and whether the
skyline from z9 looks as good as the baked ridge level.

### Step 2: cells, and a journey across them

**Plays.** A journey can cross from one baked area into the next: the Dales into the Lake District.

**Builds.** The baker cuts cells (boundary nodes, geographic coordinates, cover at 16 m, the cell index);
`RealRegion.stitch` and the journey frame; the bundled regions re-cut; the planner's two rounds of cell loading;
the tests on cells. Measure load time: the Dales' roads and buildings are 1.2 MB of JSON and a journey may load a
dozen cells, so a binary form may be needed here.

**Size.** About three weeks.

### Step 3: the world baked and served

**Plays.** A cell the game lacks arrives from GitHub. The host's Start waits until everyone has the journey's cells
and heights, with progress on the TV.

**Builds.** The data repository and its bake workflow (matrix, release assets, the index); `CellStore` in the game
(fetch queue, hash check, progress, the cache cap); the ready-check in the adventure state and on the TV; a
two-player test where the client lacks a cell and gets it from a local file server standing in for GitHub; the UK
and Japan baked.

**Size.** About two weeks, plus the afternoons of baking.

### Step 4: the world on the TV

**Plays.** Search for Settle or Takamatsu, or move the map there; the crew sees the same view; close in and the
roads arrive; pin anywhere; press Survey where nobody has been.

**Builds.** The basemap and place index bundled; the main-roads sketch baked and served; the shared view in the
journey state; cells fetched for the view; the Survey button and its worker; the paste box; credits generated from the
cells and tiles a journey used.

**Size.** About three weeks.

### Step 5: consensus, and journeys kept

**Plays.** "I'm in" marks, Start when everyone is in; past journeys to ride again; journey codes.

**Size.** About a week.

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
