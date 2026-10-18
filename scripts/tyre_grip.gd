class_name TyreGrip
extends RefCounted
## How each kind of tyre grips on each surface, wet or dry (data/tyre_grip.json): road, slick,
## dual sport, 50/50 adventure, knobbly, winter and studded tyres on tarmac, gravel, sand and
## snow. A tyre's own "grip" in data/parts.json is its figure for the town's tarmac, dirt and
## grass; this scales it for the adventure surfaces and for what its tread makes of them. 1.0 is
## a tyre on dry tarmac, so every tyre the town always had grips there just as it did.
##
## The surface under a wheel comes from the world: the collider's own "surface" meta (the town's
## tarmac, dirt tracks and grass), or for tarmac whatever `surface_provider` says is really there
## (the adventure world's gravel, sand and snow). See surface_at.

const PATH := "res://data/tyre_grip.json"
## The surfaces the table knows, in the order the spec lines list them.
const SURFACES: Array[String] = ["tarmac", "gravel", "sand", "snow"]

## The world's say on what's under a wheel: a Callable(at: Vector3) -> String ("tarmac",
## "gravel", "sand", "snow", or "" when it doesn't know). The adventure world sets it while one
## is running; with none set, an AdventureWorld class with a static surface_at(at) is asked if
## the game has one, and otherwise the ground is what its collider says.
static var surface_provider := Callable()

static var _kinds := {}
static var _adventure: Script = null
static var _adventure_checked := false


## The table, loaded once.
static func kinds() -> Dictionary:
	if _kinds.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var data = JSON.parse_string(f.get_as_text())
			if data is Dictionary and data.get("kinds") is Dictionary:
				_kinds = data["kinds"]
		if _kinds.is_empty():
			_kinds = {"road": {"name": "road"}}
	return _kinds


## How much `tyre_kind` grips on `surface` with the ground `wet` (0 dry .. 1 soaked), as a share
## of its own grip on dry tarmac. Unknown kinds grip as road tyres; surfaces the table doesn't
## list (the town's dirt and grass, which the tyre's own figures cover) give 1.0.
static func factor(tyre_kind: String, surface: String, wet: float) -> float:
	var k: Dictionary = kinds().get(tyre_kind, kinds().get("road", {}))
	var dry := float(k.get(surface, 1.0))
	var w: Dictionary = k.get("wet", {})
	return dry * lerpf(1.0, float(w.get(surface, 1.0)), clampf(wet, 0.0, 1.0))


## The kind of a tyre (its catalogue entry): its own "grip_kind", or for the tyres from before
## there were kinds, what its style says (a slick, a road tyre, or off-road ones: dual sports
## that grip as well on tarmac, knobblies that don't).
static func kind_of(p: Dictionary) -> String:
	if p.has("grip_kind"):
		return str(p["grip_kind"])
	match str(p.get("style", "road")):
		"slick":
			return "slick"
		"offroad":
			var g: Dictionary = p.get("grip", {})
			return "dual" if float(g.get("tarmac", 1.0)) >= 0.95 else "knobbly"
	return "road"


## "50/50 adventure", "winter" and so on.
static func kind_name(tyre_kind: String) -> String:
	return str(kinds().get(tyre_kind, {}).get("name", tyre_kind))


## A tyre's grip on `surface` before the tread's say: its own figure where it has one (the town's
## tarmac, dirt and grass), else for gravel, sand and snow its tarmac figure (that `factor`
## scales). Anything else (a steel ramp) is 0.7, as it always was.
static func base_grip(grip: Dictionary, surface: String) -> float:
	if grip.has(surface):
		return float(grip[surface])
	return float(grip.get("tarmac", 0.7)) if surface in SURFACES else 0.7


## The tyre's grip (catalogue "grip" table and kind) on `surface`, `wet` 0..1.
static func grip_on(grip: Dictionary, tyre_kind: String, surface: String, wet: float) -> float:
	return base_grip(grip, surface) * factor(tyre_kind, surface, wet)


## What's under a wheel at `at`: the collider's own `collider_surf` where it says it's loose
## ground (the town's dirt tracks and grass), else what the world says is there (the adventure
## world's gravel, sand and snow), else tarmac.
static func surface_at(collider_surf: String, at: Vector3) -> String:
	if collider_surf != "" and collider_surf != "tarmac":
		return collider_surf
	var s := ""
	if surface_provider.is_valid():
		s = str(surface_provider.call(at))
	else:
		var adv := _adventure_world()
		if adv != null:
			s = str(adv.call("surface_at", at))
	return s if s in SURFACES else "tarmac"


## The adventure world's script, if the game has one with a static surface_at (looked up once).
static func _adventure_world() -> Script:
	if _adventure_checked:
		return _adventure
	_adventure_checked = true
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == "AdventureWorld":
			var script := load(str(c["path"])) as Script
			if script != null and script.get_script_method_list().any(func(m): return str(m.get("name", "")) == "surface_at"):
				_adventure = script
	return _adventure


## Each table surface and how the tyre kind grips there dry and wet, for the parts computer:
## "tarmac 100% (wet 100%), gravel 88% ...".
static func table_text(tyre_kind: String) -> String:
	var bits := []
	for s in SURFACES:
		bits.append("%s %d%%" % [s, roundi(factor(tyre_kind, s, 0.0) * 100.0)])
	return ", ".join(bits)
