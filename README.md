# Torque Shed

A co-op motorbike restoration game: walk round the shed with friends, strip rusty project bikes down, clean and restore every part, fit better ones, then ride them out of the roller door.

Current milestone, **The Shed**: a snug first-person workshop with four bike bays, a workbench, a wheeled engine stand, a parts computer that orders parts and equipment, a parts washer, a repair bench, posters, seats and TVs to buy, wall dashboards for every bike and the crew, a radio everyone hears, a wash bay with a pressure washer beside the shed, and the riding map outside. Bikes are made of 38 parts from 32 kinds (stands, headlight, horn, ECU, panniers, top box and fog lights are optional), at least 5 of each and 15 wheels, plus petrol, oil, brake fluid and chain lube, and every part has its own colour, rust, dirt and wear. Skills, XP and money come later.

### What a bike is made of

| Area | Parts |
| --- | --- |
| Chassis | Frame, front fork, rear suspension (type, travel, bump and rebound damping, adjustability) |
| Wheels | Front and rear wheel (spoked, wire, cast, carbon; 17" to 21"), front and rear tyre (type, compound, width) |
| Brakes, front and rear | Disc (type, diameter), caliper (pistons), pads (compound), master cylinder (axial or radial) |
| Body and controls | Fuel tank (capacity, style), saddle, handlebars (style, width), dashboard, headlight (style, lumens), horn (10 types, from a disc horn to a train horn or a musical one), fog lights |
| Electronics | ECU (stock, remap, ABS, sport with traction control, race with all of it): more power and revs, and rider aids for ABS, traction control, stability and anti-wheelie |
| Luggage | Panniers and top boxes; they add drag |
| Stands | Side stand (length, lean), centre stand (lift). Without either, a bike left anywhere but a paddock stand falls over |
| Fluids | Petrol in the tank, oil in the engine, brake fluid in each master cylinder. Each has 3 grades and ages with use |
| Engine, built on the stand | Block (single, twin, parallel twin, V-twin, boxer, two-stroke or inline four; 50 to 1200 cc), cylinder head, fuel system, air filter, oil filter, spark plugs, cooling, gearbox |
| Drivetrain | Exhaust, sprockets, chain (slack and lube matter) |

Engine parts have to suit each other: one carb can't feed a big four, a race head needs a radiator, worn plugs misfire and a poor oil filter lets a tired engine wear faster. The bay screens list anything that doesn't suit.

## Playing

Unzip `TorqueShed-windows.zip` and run `TorqueShed.exe`. No install is needed.

**Saving**: the shed saves itself every minute, when you leave to the title and when you close the game, and the Esc menu has a **Save now** button. Everything is kept: the bikes and every part, where things were left (bikes out on the road included), equipment, the time of day and where you stood. The title screen's solo and host buttons **Continue** the saved shed; **New shed** starts again (after asking). In co-op the host's shed is the one saved. Saves live in `%APPDATA%\Godot\app_userdata\Torque Shed\saves`.

### In the shed

| Action | Keyboard and mouse | Gamepad |
| --- | --- | --- |
| Walk / look | W A S D / mouse | Left stick / right stick |
| Run | Shift | Left stick click |
| Crouch (low parts such as stands, oil filter and chain need it) | C or Ctrl | Right stick click |
| Pick a tool (hands, wrench, brush, grinder, spray can, pressure washer, spray gun, stopwatch) | 1-8, Q / E, mouse wheel | LB / RB |
| Work on what you're looking at, or put a held part down anywhere | Hold left mouse | Hold RT or A |
| Spray colour / finish (can or gun) | R or right mouse / T | X / B |
| Ping what you're looking at for the crew | G or middle mouse | D-pad right |
| Stopwatch start / stop (lap or reset: right mouse with the stopwatch out) | P | D-pad left |
| Name the bike you're looking at | N | |
| Roller door, shed lights (switches by the door) | F | Y |
| Drain a fluid (holding a drain pan, empty can or bleed bottle); with the wrench at a chain, set its tension | Hold R or right mouse | Hold X |
| Get on a finished bike (tap), or wheel it about on foot (hold) | F | Y |
| Use the parts computer, switch the radio on or off | F | Y |
| Unpack a delivery box; take hold of or let go of equipment (posters and TVs hang on the wall you look at) | F | Y |
| Sit on a seat (tap), or move it (hold) | F | Y |
| Change radio station | Hold left mouse on the radio | Hold RT or A |
| Whiteboard: draw / rub out; pen colour, eraser, thickness; text; undo; wipe it all | Hold left / right mouse; 1-6, 7, wheel; T; Z; hold X | Hold RT / LT; B colour; LB / RB thickness; D-pad left undo |
| Menu | Esc | Start |

**Building from scratch**: hold a frame and look at an empty bay floor (bay 4 is free in a new shed), then hold the work button to stand the frame up in the bay. Fit the fork, wheels, engine and the rest onto it from there. Taking the bare frame off again frees the bay.

Look at any part to see its spec, condition, rust, dirt, wear and colour. With your **hands** you take parts off (once unbolted and once the parts mounted on them are off), carry them, fit them and put them down anywhere: the floor, a bench top, a shelf or an engine stand. The **wrench** bolts and unbolts. The **brush** scrubs off dirt from every part around where it lands; the parts washer does it on its own. The **grinder and welder** restores rust and wear on a repair machine, every part on the machine at once. The **spray can** paints a part in the colour and finish shown above the tool bar (16 colours; gloss, matte, metallic flake, chrome or old patina); the part has to be free of rust first. Painting and chain lube are hand work: hold the button and sweep the can over the whole part. The panel shows how much is covered; missed patches make a patchy job and going over one spot too long leaves runs (or flings lube off), and the part's info shows how good the job was. Hold a part while looking at a bike or engine to see how fitting it would change power, top speed, weight and braking.

Chains stretch and lose their lube as you ride, faster off-road: crouch by the chain with the wrench and hold the second button to set the tension, and spray it with **chain lube** (hold the can, crouch, sweep it along the chain). A slack or dry chain wastes power and the bay screen says so.

**Fluids** come in containers from the parts computer. Hold one and look at a bike's tank, engine or brake master cylinder to pour it in; hold an empty container (jerry can, drain pan, bleed bottle) and hold the alt button to drain it out, then tip old fluid away at the bin. Draining the oil means crouching under the bike. Low or old oil costs power and wears the engine, stale fuel loses power, and old brake fluid makes the brakes spongy. Bikes pick up dirt as they're ridden, more on the dirt road. Wheel a muddy bike into the **wash bay** beside the shed and use the **pressure washer** (tool 6). With your hands, look at a bike with a stand bolted on to put it on its side or centre stand.

Filters and spark plugs can be changed with the engine in the frame. Everything else on the engine needs it on the **engine stand**: take the exhaust and chain off, unbolt the engine, carry it to the stand, and work on it there. The **parts computer** orders any part (free for now), equipment or a new project bike. Equipment comes in several models, with compact ones for a full shed: engine stands, shelving (8 to 20 places), parts washers (1 to 4 parts, some faster), repair machines (1 to 4 parts at once, some faster), workbenches, wall posters, seats (stool, creeper, camp chair, bench, sofa) and wall TVs that show whoever is out riding live, or the crew board. Parts marked "light" save weight; the bay screens show power to weight. Deliveries are left in the painted bay outside the roller door: parts come boxed (F unpacks a box, and boxed stock can go straight onto shelves), equipment comes ready to push in. Take hold of equipment with F, walk it where you want it (it turns with you) and press F to let go; whatever is on it goes with it. Posters and TVs hang flat on whichever wall you look at. Write on a shelving unit's label plate by holding the work button on it. What you're looking at is described in the panel on the right. A bike can be ridden once every slot is filled and bolted up. What the speedo shows depends on the dashboard fitted.

The **parts computer** is split into three aisles, **Shed**, **Bike** and **Outdoors**, and has a search box that finds any part or piece of kit by name, kind or spec.

The **paint booth** (three sizes, 2 to 6 hooks) is for proper paint jobs: hang parts on its hooks and sweep the **spray gun** over them. The gun's wide, even fan coats every part it passes, and a booth adds a better finish. With the can or the gun, the wet paint shows on the part as you go, so you can see the patches you've missed, and too much in one place runs. Fluid containers are see-through or have a sight strip, so you can see how full they are.

**Ping** (G or middle mouse) outlines whatever you're pointing at, with your name and what it is, for everyone in the shed. The **stopwatch** is for timing whatever runs you dream up; it keeps running while you ride. Press N while looking at a bike to give it a name. The roller door and the shed lights have switches beside the door. A day and night cycle runs outside; its speed (or a fixed time of day) is in the Esc menu.

The **whiteboard** on the front wall, left of the roller door, is for the crew's plans and lists. Walk up and look at it: hold left mouse to draw where you're looking and right mouse to rub out; 1–6 pick the pen colour (black, blue, red, green, orange, purple), 7 the eraser, and the scroll wheel the thickness (fine, medium, thick, marker). T types a line of text at the crosshair (Enter starts the next line under it), Z or Ctrl+Z undoes your own last mark, and holding X wipes the whole board. Everyone sees it as it's drawn, and it's kept with the shed.

The **radio** on the shelf above the workbench streams internet radio stations (SomaFM and Radio Paradise). Everyone in the shed hears the same station; each player's PC streams it, so it needs an internet connection. The Esc menu has volume sliders for sound effects and the radio. Stations live in `data/radio.json`.

### Riding

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Engine on / off | I | D-pad up |
| Throttle | W / Up | Right trigger |
| Front brake | S / Down | Left trigger |
| Rear brake | Space | B |
| Lean left / right | A / D | Left stick |
| Weight back (wheelie) / forward | Shift / Ctrl | LB / RB |
| Shift up / down | E / Q | A / X |
| Toggle auto-shift | T | |
| Reset after a crash | R | View |
| Camera (chase, first person) | C | Right stick click |
| Horn | H | D-pad down |
| Paddle backwards with your feet (when stopped) | Hold S | Hold left trigger |
| Burnout | Hold S, then throttle | Left then right trigger |
| Ping / stopwatch | G or middle mouse / P | D-pad right / left |
| Get off (when stopped) | F | Y |

You get on with the engine off: press I to start it. The speedo shows a fuel gauge, and economy and range are on the bay screens. If the tank runs dry the engine stalls. Getting off puts the bike on its side stand (or centre stand), unless you stop by a bay's paddock stand. Bikes have no reverse gear: stopped, hold the front brake for a moment and you paddle backwards with your feet, steering as you go (or hold F next to a bike to wheel it about on foot). Hold the front brake and open the throttle to light up a burnout. The front tyre doesn't lock or skid any more; the back one does unless the ECU has ABS. The engine sound now follows the engine: cylinders, capacity, the exhaust and the gearbox's whine. The Esc menu switches units between metric (km/h, km, kg, L/100 km) and imperial (mph, miles, lb, UK mpg).

Hold weight back (Shift / LB) to lift and hold a wheelie; the bike now eases the throttle and dabs the back brake for you near the balance point, and a stoppie on the front brake is easier to hold. In the air, throttle tips the bike back and closing it (or the back brake) tips the nose down, so you can set up the landing. Skids screech and leave black marks on tarmac (and ruts on dirt). The clocks face the rider and their needles, rev lights and screens show live speed, revs, gear and fuel; first person sits at eye height.

The **yard** past the drag strip has movable kit: small, medium and large ramps with a landing ramp, a tabletop, cones, posts, flags, barrels, a log, hay bales, a tyre stack, an old car, concrete and brick walls and fences. Take hold of any of it with F and push it where you want. Order more from the parts computer's **Yard:** categories; it's dropped in the yard.

You steer by leaning: the rider counter-steers for you, like on a real bike. The **rider assist** setting goes from 0 (full sim) to 1 (most help with balance, wheelspin and wheelies). The Esc menu has a **Controller check** tab that shows exactly what the game reads from your pad.

### Co-op

One player picks **Host a co-op shed**; the others type the host's address into the box and pick **Join**. The game uses UDP port **24680**. The host's shed is the shared one: everyone works on the same bikes. The host's Esc menu shows exactly which address to give friends.

- Same network: use the host's local address (192.168.x.x or similar).
- Over the internet: friends use the host's public IP address. When hosting, the game asks the host's router to open UDP port 24680 itself (UPnP), and the Esc menu says whether that worked. If it didn't, forward UDP port 24680 on the router to the host's PC by hand. The first time the game hosts, Windows asks whether to let it through the firewall: tick both Private and Public networks.
- The join box takes `81.2.3.4`, `81.2.3.4:24680`, an IPv6 address or a host name.
- If the host's internet provider shares one public address between many homes (carrier-grade NAT), port forwarding can't work; Steam invites are planned for later.

## How it works

| File | What it does |
| --- | --- |
| `data/parts.json` | Every part and its numbers, which feed the physics directly |
| `scripts/shed_state.gd` | The shared shed: bikes, parts, who holds what. The host checks and applies every action |
| `scripts/workshop.gd` | Builds the shed, its stations and dashboards, and draws parked bikes and loose parts |
| `scripts/walker.gd` | First-person player, tools, targeting and hold-to-work |
| `scripts/whiteboard.gd`, `board_data.gd` | The shared whiteboard: drawing on it, and its marks kept in the shed state |
| `scripts/bike_build.gd` | Turns parts and their condition into stats: mass, torque curve, grip, brakes, top speed |
| `scripts/bike_model.gd` | Builds the visible bike part by part, with rust and grime |
| `scripts/bike.gd` | Rigid-body bike with ray-cast suspension, slip-based tyres, engine, clutch and gearbox |
| `scripts/controls.gd` | Gamepad sticks and triggers, calibrated against stuck axes |
| `scripts/net.gd`, `remote_player.gd`, `remote_bike.gd` | Multiplayer and other players |
| `scripts/world.gd` | The map outside: terrain, road loop, Build Yard, trees |
| `scripts/sfx.gd` | Tool, footstep and workshop sounds, synthesised at start-up, and the volume buses |
| `scripts/shed_radio.gd`, `radio_stream.gd`, `mp3_stream_decoder.gd` | The shed radio: streams an MP3 station over HTTP(S) and decodes it gaplessly |

Built with [Godot 4.6](https://godotengine.org) and Jolt physics.

## Development

```sh
godot --headless --path . --import
godot --headless --fixed-fps 120 --path . res://tests/test_runner.tscn   # physics, world and session tests
tests/mp_test.sh                                                          # host and client on one machine
godot --headless --path . --export-release "Windows Desktop" build/windows/TorqueShed.exe
```
