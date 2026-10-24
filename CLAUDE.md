# Torque Shed: notes for Claude

A Godot 4.6 (GDScript) co-op motorbike restoration game. See README.md for the game itself.

## Branches: never work on main

- **Every piece of work goes on its own new branch.** Never commit or push directly to `main`.
- Before making any change, check the current branch (`git branch --show-current`). If it is `main`,
  create a branch first: `git checkout -b claude/<short-description>` from an up-to-date `main`.
- If a session already names a branch to work on, use that branch (and create it if it doesn't exist),
  but still never `main`.
- One piece of work per branch: start a new branch from the latest `main` for each new task rather than
  stacking unrelated work on an old branch. If the branch's pull request has already been merged, start
  a fresh branch from the latest `main` for the follow-up.
- When a piece of work is finished and its tests pass, push the branch and open a pull request into
  `main` without waiting to be asked.
- Never merge a pull request yourself. The user merges, or asks for a merge, when they are ready.
- If new work depends on a branch whose pull request isn't merged yet, branch from that branch and say
  so in the new pull request.
- Never force-push to `main`, and never rewrite history on a branch someone else is working on.

## Project layout

- `scripts/`: game code. `parts_db.gd` loads `data/parts.json` and holds the bike styles
  (`STYLE_NAMES`); `bike_build.gd` turns a bike's parts into its performance; `bike.gd` rides it.
- `data/parts.json`: the parts catalogue. Parts are tagged with the `styles` they suit.
- `tests/`: the test suite (`run_tests.gd`, run by `test_runner.tscn`) and a multiplayer test (`mp_test.sh`).

## Tests

CI (`.github/workflows/ci.yml`) runs on every pull request and push to main, with Godot 4.6.2: the suite spread over eight
machines and the multiplayer pairs over three, all at once (about six minutes):

```
godot --headless --path . --import
godot --headless --fixed-fps 120 --path . res://tests/test_runner.tscn -- --shard=K/8
tests/mp_test.sh [pair ...]
```

Before pushing, run the tests the change touches (`-- --only=_test_a,_test_b`) and the multiplayer pairs it could
affect (`tests/mp_test.sh mp_journey`); the whole suite runs on the pull request, and runs locally only for a change
that reaches across the game. The suite lists its slowest tests at the end; `tests/test_times.json` (each test's time,
from CI's `test-times-*` artifacts) is what the shards are dealt out by, so refresh it when tests are added or slow
down. Add or update tests when behaviour changes.

## Style

- Match the surrounding code: tabs, typed GDScript, `##` doc comments in plain English.
- Commit messages and in-game text use plain British English ("tyre", "colour", "mpg" in imperial gallons).
