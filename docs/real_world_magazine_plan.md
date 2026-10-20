# Making real-world roads the new magazine: how they plug into the adventure system

Written 20 October 2026, after merging `main` (which has its own adventure mode) into the real-route branch.

## The end goal

The crew stands in front of a screen in the shed, plans a road journey together on a map (Google Maps or similar), tells
the game "this is the adventure we want", and the game makes the adventure and streams it in while they ride. No
pre-baked issue is needed; the magazine becomes a set of hand-picked starting points.

This changes one conclusion in the feasibility report. A baked pack per issue was right when issues were curated by us.
With live planning, the data has to be turned into a rideable road **on demand and ahead of the riders**, so something
has to do what the baker does while the crew rides.

### The pieces

1. **Planning screen in the shed.** A map on a shed screen (the satnav computer, or a TV channel) where the crew picks a
   start and end and waypoints, with search. Three ways in, in order of effort:
   - *Paste a link.* Plan on Google Maps on a phone, copy the link, paste it into the game. A share link carries the
     start, waypoints and end as coordinates. Google's own road geometry is not used (its terms forbid building a game
     from it); only the coordinates the crew chose are, and the road itself comes from open data.
   - *Pick on an in-game map* of open map tiles (OpenStreetMap-based) with place search (Nominatim or Photon).
   - *Pick from the magazine*: hand-picked routes, pre-baked so they start instantly and are known to ride well.
2. **A route planner.** Turns the chosen points into a road along real roads (shortest path with class costs, what
   `route_bake.py` already does for one start and end, extended to waypoints), with turn instructions for the satnav.
3. **A tile service that makes the road as the crew rides.** For each stretch ahead of the riders it makes heights,
   road lines and buildings for that stretch. This is the baker's job, run continuously and ahead of the bikes, and it
   must give every player identical results.
4. **Streaming in the game.** Main's `AdventureWorld` already streams chunks with a floating origin, so the game side
   asks the service for the next stretch a few km ahead (as its chunk builder already does from the route) and keeps a
   disk cache.

### The big decision: where step 3 runs

The data (Overture roads as GeoParquet on S3, Mapterhorn heights) cannot be read from Godot directly in a practical way:
there is no Parquet reader in the engine and Overpass is not for production use. So something outside the game does the
conversion:

| Option | How | For | Against |
| --- | --- | --- | --- |
| A. A service we host | Stateless web service running the baker code, game calls it for a stretch and gets a small pack; CDN and cache in front | identical results for everyone, thin client, nothing to install, works on any PC, one place to fix data problems | hosting and running cost, an online dependency, our uptime is the game's uptime |
| B. The host's PC does it | A bundled Python or native baker the host runs, relaying packs to the crew over the game's network | no servers of ours | heavy install, antivirus friction, a slow host PC slows everyone, packs relayed over ENet |
| C. A native converter in the game | GDExtension or a small bundled executable that reads the open data directly | no service, no Python | the most engineering, and still needs the data's own hosts to stay up |

Recommendation: **A**, with the hand-picked magazine routes pre-baked and shipped or cached so the crew can ride
without the service, and a disk cache so a route ridden once rides offline. Co-op stays simple: the host asks the service
once, pins the data release, and sends the crew the route hash; every machine fetches the same stretches from the service.

### What "stream during the ride" needs from the road data

Stretches of about 1 to 2 km of corridor (2 km wide) at a time, ready when the riders are 3 km from them, each a few
hundred KB. The baker currently takes about 40 seconds per 4 km window, mostly waiting on Overture's cloud files and
terrain tiles; the service would keep the Overture release and a heights cache warm, so a stretch should come in a few
seconds. That needs measuring before promising it.

## What main's adventure mode already is

Main's "Adventure Rider" magazine (`AdventureMag`) lists issues of articles (`title`, `theme`, `len`, `seed`, `dest`, `blurb`).
Starting one sends `adventure_start {seed, km, theme, dest, title, mag}` to the shed's shared state, and every player's
game then calls `AdventureWorld.setup(seed, km, theme, dest)`, which makes an `AdventureRoute` and plans the **whole road**
from the seed:

- the road is a line of **knots every 4 m** in doubles (`px`, `pz`, `ph` height, `hd` heading, `curv`, `width`), with
  per-stretch surfaces, sites (fuel stations, stops, start, finish, destination set piece, forks, junctions) and tunnels;
- the **land** is made from the route alone: `land_height(i, lat, x, z)` blends the road's height out to
  `natural_height()`, which is noise (hills, dunes, mountains) around the road, kept clear of other stretches of road;
- `AdventureWorld` **streams it in 128 m chunks** (`AdventureChunk`, built on worker threads, one committed per frame)
  with a **floating origin** that shifts as you ride, so the length is unlimited;
- on top sit forks (2 or 3 ways every 20 to 30 km that the crew votes on), junctions, traffic streams, police, fuel and
  needs, a satnav (`Satnav`, `SatnavScreen`), a paper map, a trip computer and the diary.

That is the streaming you asked about, already built. It makes my own long-route machinery (4 km legs, a swap with a fade,
a second satnav panel) redundant for the magazine. What is not redundant is everything that produces **real data**.

## What real data replaces, and what stays

| Main's adventure system | Real-world version |
| --- | --- |
| `AdventureRoute.plan(seed, km, theme, sites)` makes the road from noise | `plan_real(route, km, ...)` fills the same arrays from a baked route: knots resampled to 4 m from the real road line, height from the DEM along it (smoothed, grade-limited), width and surface from the road class |
| `natural_height()` is noise | a read-only `RealTerrain` sampler of baked height tiles (in the route frame, thread safe, tiles loaded on demand) |
| the sea is a theme constant (`SEA_Y`) | the real coast: height frame offset so real sea level is `SEA_Y`, so the existing sea and `_coast()` shaping can be replaced by real shore heights |
| fuel stations, stops, destination set piece | fuel stations from Overture places, destination site chosen per article; stops from real villages later |
| forks (random alternative ways) | real alternatives between two nodes of the route (a second shortest path), later |
| junctions (random T, crossroads, roundabouts) | the real junction nodes along the route, with real side roads as the arms, later |
| props (random trees, houses, barns) | real building footprints in the same style, trees from land cover later |
| an article is a `seed` | an article is a baked route (start, end or length, a seed for tie-breaks) and `km` truncates it: the host picks any length up to what was baked, and the finish and destination are placed there |

Unchanged and reused as is: chunk building, floating origin, traffic streams and police, fuel and needs, forks voting,
the satnav and paper map (given the real route's turns), the trip computer, the diary, co-op state, the magazine UI.

## What this means for the work done so far on `claude/laughing-brahmagupta-l269oq`

Keep: the **baker** (heights, roads, names, buildings, sea, route and turns, the issue file), the licensing and data
research, the signs and guard rail fixes if main's adventure props do not already cover them, the co-op handshake idea
(compare a route hash), and the tests of the baker.

Replace: the 4 km **legs and their swap**, `RouteJourney`/`RoutePack` as the way the game reads a route, and my
`SatnavPanel`/`RouteGuide` (main's satnav already guides a route; it needs the real turns fed in).

The shed-side route mode (`--route=...` on the town map) stays working meanwhile as an experiment, so nothing is lost.

## Phases

0. **Route planning from coordinates** (about 1 week). Extend the baker's route planning from one start and end to a list
   of waypoints, and write a Google Maps link parser (a link in, a list of coordinates out). Gate: paste a link, get a
   route and turn list.

1. **Plan a real road in the adventure system** (about 2 weeks). The baker writes one continuous corridor instead of legs:
   `route.json` (line, turns), heights as 512 m tiles along the corridor, roads and buildings per tile. `AdventureRoute.plan_real`
   fills the knot arrays; `natural_height` reads the tiles. Gate: ride 25 km of Shodoshima in an adventure, no forks, no sites
   except start and finish, existing tests green.
2. **Magazine articles from real routes** (1 week). An article carries a route id instead of a seed; `km` truncates;
   the destination goes at the chosen length; route hash in the co-op handshake. Gate: the host picks 10 km then 25 km from
   the magazine page for the same article and everyone rides it.
3. **Real details** (2 to 3 weeks). Sea and coast from real heights, buildings, fuel stations from real places,
   real junction arms, real turns into the satnav, real alternative ways as forks, land cover for trees.
4. **Steep and narrow roads** (ongoing). Real mountain roads exceed main's `MAX_GRADE` (15.5 %) and width limits; the
   plan clamps and flags them, and a baked route gets a curation pass.

## Risks to settle early

- **Grades and widths.** The road planner assumes grades under 15.5 % and widths between 3.3 and 7.4 m. Real Japanese
  mountain roads break both. Clamp and accept a flatter road than the real one, or lift the limits for real routes.
- **Land beside the road** is built out to 1000 m from the centre line per chunk. Real terrain needs the corridor's heights
  that far out (about 2 km wide); the tile store gets large for 100 km routes (roughly 4 MB per km at 4 m, so about 400 MB;
  coarser tiles beyond 200 m from the road cut that to under 100 MB).
- **Determinism in co-op** is by seed today; here it is by route hash plus truncation length, which is simpler.
- **Tunnels and bridges** exist as a notion in main (`AdventureTunnels`) but are procedural; real ones come from road flags
  and are a later detail.

## After phase 4: the live version

5. **The tile service and streaming** (3 to 5 weeks). Run the baker as a service that makes a stretch of corridor on
   request; the game requests stretches ahead of the riders and caches them. Measure latency first.
6. **The planning screen** (2 to 3 weeks). A shed screen with the map, search, link paste, and "start this adventure".
