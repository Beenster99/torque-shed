class_name TyreGrip
extends RefCounted
## How each kind of tyre grips on each surface, wet or dry (data/tyre_grip.json): road, slick,
## dual sport, 50/50 adventure, knobbly, winter and studded tyres on tarmac, gravel, sand and
## snow. A tyre's own "grip" in data/parts.json is its figure for the town's tarmac, dirt and
## grass; this scales it for the adventure surfaces and for what its tread makes of them. 1.0 is
## a tyre on dry tarmac, so every tyre the town always had grips there just as it did.
##
## The surface under a wheel is its collider's "surface" meta: the town's tarmac, dirt tracks and
## grass, and the adventure road's gravel, sand and snow (AdventureSurface).

const PATH := "res://data/tyre_grip.json"
## The surfaces the table knows, in the order the spec lines list them.
const SURFACES: Array[String] = ["tarmac", "gravel", "sand", "snow"]

static var _kinds := {}


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


## Each table surface and how the tyre kind grips there dry and wet, for the parts computer:
## "tarmac 100% (wet 100%), gravel 88% ...".
static func table_text(tyre_kind: String) -> String:
	var bits := []
	for s in SURFACES:
		bits.append("%s %d%%" % [s, roundi(factor(tyre_kind, s, 0.0) * 100.0)])
	return ", ".join(bits)
