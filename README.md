# Torque Shed

A multiplayer motorbike building and riding game: build bikes and engines part by part, then ride them with friends.

This is the first playable milestone, **Garage to trail**: a test map with a Build Yard and a 1 km loop of tarmac and dirt, 15 swappable parts, a dyno, blueprints, and 2 to 8 players riding together.

## Playing

Download `TorqueShed.exe` from the latest successful **CI** run (the `TorqueShed-windows` artifact) and run it. No install is needed.

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Throttle | W / Up | Right trigger |
| Front brake | S / Down | Left trigger |
| Rear brake | Space | B |
| Lean left / right | A / D | Left stick |
| Weight back (wheelie) / forward | Shift / Ctrl | LB / RB |
| Shift up / down | E / Q | A / X |
| Toggle auto-shift | T | |
| Reset bike | R | Y |
| Garage (when stopped) | G | Back |
| Camera | C | Right stick click |
| Menu | Esc | Start |

You steer by leaning: the rider counter-steers for you, like on a real bike. The **rider assist** slider in the menu goes from 0 (full sim) to 1 (most help with balance and wheelspin).

### Multiplayer

One player picks **Host a game**; the others enter the host's IP address and pick **Join**. The game uses UDP port **24680**.

- Same network: use the host's local address, which the pause menu shows.
- Over the internet: the host forwards UDP port 24680 on their router to their PC, and friends join with the host's public IP. (Steam invites are planned for later.)

## The garage

Stop the bike and press **G**. Pick a frame, fork, shock, wheels and tyres, engine, gearbox and final drive. The spec sheet and dyno graph update as you go. **Build it and ride** swaps the bike in place. Save builds as blueprints and load them later.

Parts live in `data/parts.json`. Every number there (mass, travel, spring rate, displacement, gear ratios, tyre grip per surface) feeds the physics directly.

## How it works

| File | What it does |
| --- | --- |
| `scripts/bike.gd` | Rigid-body bike with ray-cast suspension, slip-based tyre model, engine, clutch and gearbox, and a rider who balances by counter-steering |
| `scripts/bike_build.gd` | Turns a parts list into stats: mass, geometry, torque curve, gearing, top speed |
| `scripts/bike_model.gd` | Builds the visible bike and rider from the chosen parts |
| `scripts/world.gd` | Generates the map: terrain, road loop, Build Yard, garage, trees |
| `scripts/net.gd` | ENet multiplayer: host or join, player info, state streaming |
| `scripts/remote_bike.gd` | Other players' bikes, interpolated from their streamed state |
| `scripts/garage_ui.gd`, `dyno_graph.gd`, `hud.gd`, `main_menu.gd` | Interface |

Built with [Godot 4.6](https://godotengine.org) and Jolt physics.

## Development

```sh
godot --headless --path . --import
godot --headless --fixed-fps 120 --path . res://tests/test_runner.tscn   # physics, world and session tests
tests/mp_test.sh                                                          # host and client on one machine
godot --headless --path . --export-release "Windows Desktop" build/windows/TorqueShed.exe
```
