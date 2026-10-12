# Torque Shed

A co-op motorbike restoration game: walk round the shed with friends, strip rusty project bikes down, clean and restore every part, fit better ones, then ride them out of the roller door.

Current milestone, **The Shed**: a first-person workshop with four bike bays, a workbench, parts washer, repair bench, a rack of 50 new parts (10 slots, 5 variants each), wall dashboards for every bike and the crew, and the riding map outside. Skills, XP and money come later.

## Playing

Unzip `TorqueShed-windows.zip` and run `TorqueShed.exe`. No install is needed.

### In the shed

| Action | Keyboard and mouse | Gamepad |
| --- | --- | --- |
| Walk / look | W A S D / mouse | Left stick / right stick |
| Run | Shift | Left stick click |
| Pick a tool (hands, wrench, brush, grinder) | 1-4, Q / E, mouse wheel | LB / RB |
| Work on what you're looking at | Hold left mouse | Hold RT or A |
| Get on a finished bike | F | Y |
| Menu | Esc | Start |

Look at any part to see its condition, rust, dirt and wear. With your **hands** you take parts off (once unbolted and once the parts mounted on them are off), carry them, fit them, put them on a bench, and take new ones from the rack. The **wrench** bolts and unbolts. The **brush** scrubs off dirt; the parts washer does it on its own. The **grinder and welder** restores rust and wear, on the repair bench. Hold a part while looking at a bike to see how fitting it would change power, top speed and weight. A bike can be ridden once every slot is filled and bolted up. Order more project bikes from the Esc menu.

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

Built with [Godot 4.6](https://godotengine.org) and Jolt physics.

## Development

```sh
godot --headless --path . --import
godot --headless --fixed-fps 120 --path . res://tests/test_runner.tscn   # physics, world and session tests
tests/mp_test.sh                                                          # host and client on one machine
godot --headless --path . --export-release "Windows Desktop" build/windows/TorqueShed.exe
```
