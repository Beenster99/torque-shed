class_name BikeGhost
extends RefCounted
## Respawn protection: for TIME seconds after a respawn the rider and bike are a ghost. They're
## drawn see-through, fading back to solid towards the end with a gentle flicker in the last
## second, and nothing can knock them off: other bikes and the traffic pass through them (see
## Bike.start_ghost and Bike._update_passing). The time left rides in the bike's snapshot, so the
## crew see the ghost too (see RemoteBike).

## How long the ghost lasts after a respawn (s).
const TIME := 5.0
## How see-through the ghost is at its faintest (GeometryInstance3D.transparency: 0 solid, 1 gone).
const FAINT := 0.6
## Over its last this many seconds it fades back to solid...
const FADE := 1.5
## ... and in its last this many it flickers, this many times a second.
const FLICKER := 1.0
const FLICKER_RATE := 4.0


## How see-through a ghost with `left` seconds to go is drawn (0 solid).
static func look(left: float) -> float:
	if left <= 0.0:
		return 0.0
	var t := FAINT * clampf(left / FADE, 0.0, 1.0)
	if left < FLICKER:
		# A gentle flicker as it comes back: never quite solid, never fainter than it was.
		t *= 0.55 + 0.45 * (0.5 + 0.5 * cos(left * TAU * FLICKER_RATE))
	return t


## Draws everything in `model` (a bike and its rider) at `transparency`, skipping the work when
## it's already drawn that way.
static func apply(model: Node3D, transparency: float) -> void:
	if model == null:
		return
	var was := float(model.get_meta("ghost_look", 0.0))
	if absf(was - transparency) < 0.005 and not (transparency == 0.0 and was != 0.0):
		return
	model.set_meta("ghost_look", transparency)
	for n in model.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).transparency = transparency


## How see-through `model` is drawn now (0 solid).
static func drawn(model: Node3D) -> float:
	return float(model.get_meta("ghost_look", 0.0)) if model else 0.0
