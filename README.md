# Torque Shed

A co-op motorbike restoration game: walk round the shed with friends, strip rusty project bikes down, clean and restore every part, fit better ones, then ride them out of the roller door.

Current milestone, **The Shed**: a snug first-person workshop with four bike bays, a workbench, a wheeled engine stand, a parts computer that orders parts and equipment, a parts washer, a repair bench, wall dashboards for every bike and the crew, a radio everyone hears, and the riding map outside. Bikes are made of 29 parts from 23 kinds (119 parts in all, at least 5 of each), and every part has its own colour, rust, dirt and wear. Skills, XP and money come later.

### What a bike is made of

| Area | Parts |
| --- | --- |
| Chassis | Frame, front fork, rear suspension (type, travel, bump and rebound damping, adjustability) |
| Wheels | Front and rear wheel (spoked, wire, cast, carbon; 17" to 21"), front and rear tyre (type, compound, width) |
| Brakes, front and rear | Disc (type, diameter), caliper (pistons), pads (compound), master cylinder (axial or radial) |
| Body and controls | Fuel tank (capacity, style), saddle, handlebars (style, width), dashboard |
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
| Pick a tool (hands, wrench, brush, grinder, spray can) | 1-5, Q / E, mouse wheel | LB / RB |
| Work on what you're looking at, or put a held part down anywhere | Hold left mouse | Hold RT or A |
| Spray can colour / finish | R or right mouse / T or middle mouse | X / B |
| Get on a finished bike, use the parts computer, switch the radio on or off | F | Y |
| Unpack a delivery box; take hold of or let go of an engine stand or shelving unit | F | Y |
| Change radio station | Hold left mouse on the radio | Hold RT or A |
| Menu | Esc | Start |

Look at any part to see its spec, condition, rust, dirt, wear and colour. With your **hands** you take parts off (once unbolted and once the parts mounted on them are off), carry them, fit them and put them down anywhere: the floor, a bench top, a shelf or an engine stand. The **wrench** bolts and unbolts. The **brush** scrubs off dirt from every part around where it lands; the parts washer does it on its own. The **grinder and welder** restores rust and wear, on the repair bench. The **spray can** paints a part in the colour and finish shown above the tool bar (16 colours; gloss, matte, metallic flake, chrome or old patina); the part has to be free of rust first. Hold a part while looking at a bike or engine to see how fitting it would change power, top speed, weight and braking.

Filters and spark plugs can be changed with the engine in the frame. Everything else on the engine needs it on the **engine stand**: take the exhaust and chain off, unbolt the engine, carry it to the stand, and work on it there. The **parts computer** orders any part (free for now), shed equipment (more engine stands, shelving units) or a new project bike. Deliveries are left in the painted bay outside the roller door: parts come boxed (F unpacks a box, and boxed stock can go straight onto shelves), equipment comes ready to push in. Take hold of an engine stand or shelving unit with F, walk it where you want it (it turns with you) and press F to let go; whatever is on it goes with it. Write on a shelving unit's label plate by holding the work button on it. What you're looking at is described in the panel on the right. A bike can be ridden once every slot is filled and bolted up. What the speedo shows depends on the dashboard fitted.

The **radio** on the shelf above the workbench streams internet radio stations (SomaFM and Radio Paradise). Everyone in the shed hears the same station; each player's PC streams it, so it needs an internet connection. The Esc menu has volume sliders for sound effects and the radio. Stations live in `data/radio.json`.

### Riding

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Throttle | W / Up | Right trigger |
| Front brake | S / Down | Left trigger |
| Rear brake | Space | B |
| Lean left / right | A / D | Left stick |
| Weight back (wheelie) / forward | Shift / Ctrl | LB / RB |
| Shift up / down | E / Q | A / X |
| Toggle auto-shift | T | |
| Reset after a crash | R | View |
| Camera | C | Right stick click |
| Get off (when stopped) | F | Y |

You steer by leaning: the rider counter-steers for you, like on a real bike. The **rider assist** setting goes from 0 (full sim) to 1 (most help with balance, wheelspin and wheelies). The Esc menu has a **Controller check** tab that shows exactly what the game reads from your pad.

### Co-op

One player picks **Host a co-op shed**; the others enter the host's IP address and pick **Join**. The game uses UDP port **24680**. The host's shed is the shared one: everyone works on the same bikes.

- Same network: use the host's local address, which the Esc menu shows.
- Over the internet: the host forwards UDP port 24680 on their router to their PC, and friends join with the host's public IP. (Steam invites are planned for later.)

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
