# Torque Shed

A co-op motorbike restoration game: walk round the shed with friends, strip rusty project bikes down, clean and restore every part, fit better ones, then ride them out of the roller door.

Current milestone, **The Shed**: a snug first-person workshop with four bike bays, a workbench, a wheeled engine stand, a parts computer that orders parts and equipment, a parts washer, a repair bench, wall dashboards for every bike and the crew, a radio everyone hears, a wash bay with a pressure washer beside the shed, and the riding map outside. Bikes are made of 32 parts from 26 kinds (side and centre stands and the headlight are optional), at least 5 of each, plus petrol, oil and brake fluid, and every part has its own colour, rust, dirt and wear. Skills, XP and money come later.

### What a bike is made of

| Area | Parts |
| --- | --- |
| Chassis | Frame, front fork, rear suspension (type, travel, bump and rebound damping, adjustability) |
| Wheels | Front and rear wheel (spoked, wire, cast, carbon; 17" to 21"), front and rear tyre (type, compound, width) |
| Brakes, front and rear | Disc (type, diameter), caliper (pistons), pads (compound), master cylinder (axial or radial) |
| Body and controls | Fuel tank (capacity, style), saddle, handlebars (style, width), dashboard, headlight (style, lumens) |
| Stands | Side stand (length, lean), centre stand (lift). Without either, a bike left anywhere but a paddock stand falls over |
| Fluids | Petrol in the tank, oil in the engine, brake fluid in each master cylinder. Each has 3 grades and ages with use |
| Engine, built on the stand | Block (single to inline four, 250 to 1000 cc), cylinder head, fuel system, air filter, oil filter, spark plugs, cooling, gearbox |
| Drivetrain | Exhaust, final drive |

Engine parts have to suit each other: one carb can't feed a big four, a race head needs a radiator, worn plugs misfire and a poor oil filter lets a tired engine wear faster. The bay screens list anything that doesn't suit.

## Playing

Unzip `TorqueShed-windows.zip` and run `TorqueShed.exe`. No install is needed.

### In the shed

| Action | Keyboard and mouse | Gamepad |
| --- | --- | --- |
| Walk / look | W A S D / mouse | Left stick / right stick |
| Run | Shift | Left stick click |
| Crouch (low parts such as stands, oil filter and chain need it) | C or Ctrl | Right stick click |
| Pick a tool (hands, wrench, brush, grinder, spray can, pressure washer) | 1-6, Q / E, mouse wheel | LB / RB |
| Work on what you're looking at, or put a held part down anywhere | Hold left mouse | Hold RT or A |
| Spray can colour / finish | R or right mouse / T or middle mouse | X / B |
| Drain a fluid (holding a drain pan, empty can or bleed bottle) | Hold R or right mouse | Hold X |
| Get on a finished bike (tap), or wheel it about on foot (hold) | F | Y |
| Use the parts computer, switch the radio on or off | F | Y |
| Unpack a delivery box; take hold of or let go of an engine stand or shelving unit | F | Y |
| Change radio station | Hold left mouse on the radio | Hold RT or A |
| Menu | Esc | Start |

Look at any part to see its spec, condition, rust, dirt, wear and colour. With your **hands** you take parts off (once unbolted and once the parts mounted on them are off), carry them, fit them and put them down anywhere: the floor, a bench top, a shelf or an engine stand. The **wrench** bolts and unbolts. The **brush** scrubs off dirt from every part around where it lands; the parts washer does it on its own. The **grinder and welder** restores rust and wear, on the repair bench. The **spray can** paints a part in the colour and finish shown above the tool bar (16 colours; gloss, matte, metallic flake, chrome or old patina); the part has to be free of rust first. Hold a part while looking at a bike or engine to see how fitting it would change power, top speed, weight and braking.

**Fluids** come in containers from the parts computer. Hold one and look at a bike's tank, engine or brake master cylinder to pour it in; hold an empty container (jerry can, drain pan, bleed bottle) and hold the alt button to drain it out, then tip old fluid away at the bin. Draining the oil means crouching under the bike. Low or old oil costs power and wears the engine, stale fuel loses power, and old brake fluid makes the brakes spongy. Bikes pick up dirt as they're ridden, more on the dirt road. Wheel a muddy bike into the **wash bay** beside the shed and use the **pressure washer** (tool 6). With your hands, look at a bike with a stand bolted on to put it on its side or centre stand.

Filters and spark plugs can be changed with the engine in the frame. Everything else on the engine needs it on the **engine stand**: take the exhaust and chain off, unbolt the engine, carry it to the stand, and work on it there. The **parts computer** orders any part (free for now), shed equipment (more engine stands, shelving units) or a new project bike. Deliveries are left in the painted bay outside the roller door: parts come boxed (F unpacks a box, and boxed stock can go straight onto shelves), equipment comes ready to push in. Take hold of an engine stand or shelving unit with F, walk it where you want it (it turns with you) and press F to let go; whatever is on it goes with it. Write on a shelving unit's label plate by holding the work button on it. What you're looking at is described in the panel on the right. A bike can be ridden once every slot is filled and bolted up. What the speedo shows depends on the dashboard fitted.

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
| Get off (when stopped) | F | Y |

You get on with the engine off: press I to start it. The speedo shows a fuel gauge, and economy and range are on the bay screens. If the tank runs dry the engine stalls. Getting off puts the bike on its side stand (or centre stand), unless you stop by a bay's paddock stand. Bikes have no reverse gear, so hold F next to a bike to wheel it about on foot. The Esc menu switches units between metric (km/h, km, kg, L/100 km) and imperial (mph, miles, lb, UK mpg).

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
