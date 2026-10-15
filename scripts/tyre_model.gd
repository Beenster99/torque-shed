class_name TyreModel
extends RefCounted
## A motorcycle tyre as a simplified Pacejka "Magic Formula" with combined slip.
##
## Each tyre has a peak grip per surface (the catalogue's grip table) and a shape set by its
## construction (radial or bias ply), its profile (how round the crown is), how stiff its
## compound and carcass are, and how much grip is left once it slides. Longitudinal slip
## (braking and drive) and lateral slip (slip angle plus camber thrust) are normalised by the
## slips where each peaks and added as a vector, so a tyre that is braking hard has less left
## for cornering, and one past its peak slides with the force turning towards the slip.
## Grip saturates with load: twice the load gives less than twice the force.

## Defaults by tyre style, for any tyre (or an old catalogue entry) without the fields.
## construction: "radial" or "bias"; profile: crown radius as a share of half the section width
## (1 = a round profile, more = flatter, less = a pointier sport profile); stiffness: how
## sharply it builds force with slip (carcass and compound); slide: grip left once it slides,
## as a share of the peak.
const STYLE_DEFAULTS := {
	"road": {"construction": "radial", "profile": 1.0, "stiffness": 1.0, "slide": 0.8},
	"slick": {"construction": "radial", "profile": 0.9, "stiffness": 1.15, "slide": 0.72},
	"offroad": {"construction": "bias", "profile": 1.05, "stiffness": 0.8, "slide": 0.86},
}
## Slip at peak grip for each construction: [longitudinal slip ratio, slip angle (rad)],
## camber thrust (N per N of load per radian), relaxation length (m) and load sensitivity.
const CONSTRUCTION := {
	"radial": {"kappa": 0.11, "alpha": 0.105, "camber": 0.85, "relax": 0.16, "load": 0.16},
	"bias": {"kappa": 0.14, "alpha": 0.15, "camber": 0.95, "relax": 0.24, "load": 0.12},
}
const MAX_SLIP_ANGLE := deg_to_rad(80.0)


## The tyre's numbers from its catalogue entry, filling in anything missing from its style.
static func params_of(tyre: Dictionary) -> Dictionary:
	var style := str(tyre.get("style", "road"))
	var d: Dictionary = STYLE_DEFAULTS.get(style, STYLE_DEFAULTS["road"])
	var construction := str(tyre.get("construction", d["construction"]))
	if not CONSTRUCTION.has(construction):
		construction = str(d["construction"])
	var c: Dictionary = CONSTRUCTION[construction]
	var stiffness := clampf(float(tyre.get("stiffness", d["stiffness"])), 0.4, 2.0)
	var slide := clampf(float(tyre.get("slide", d["slide"])), 0.4, 0.98)
	var profile := clampf(float(tyre.get("profile", d["profile"])), 0.5, 2.0)
	var width := float(tyre.get("width", 140.0)) / 1000.0
	var p := {
		"construction": construction,
		"profile": profile,
		"stiffness": stiffness,
		"slide": slide,
		"kappa_peak": float(c["kappa"]) / stiffness,
		"alpha_peak": float(c["alpha"]) / stiffness,
		"camber": float(c["camber"]),
		"relax": float(c["relax"]) * lerpf(1.25, 0.9, clampf((stiffness - 0.7) / 0.6, 0.0, 1.0)),
		"load_sens": float(c["load"]),
		# The crown's radius: half the section width, rounder or flatter by the profile.
		"crown": clampf(width * 0.5 * profile, 0.02, 0.16),
	}
	shape_into(p)
	return p


## Sets the curve's C and B so the force peaks at a normalised slip of 1 and settles at
## `slide` of the peak far past it.
static func shape_into(p: Dictionary) -> void:
	var slide := clampf(float(p.get("slide", 0.8)), 0.4, 0.98)
	var c := 2.0 - 2.0 * asin(slide) / PI
	p["C"] = c
	p["B"] = tan(PI / (2.0 * c))


## The Magic Formula's shape at normalised slip `s` (>= 0): 0 at no slip, 1 at the peak (s = 1),
## easing down to the sliding share beyond it.
static func shape(s: float, p: Dictionary) -> float:
	var b: float = p["B"]
	var c: float = p["C"]
	return sin(c * atan(b * s))


## Slope of shape() at no slip: how many "peaks" of force per unit of normalised slip.
static func stiffness_at_zero(p: Dictionary) -> float:
	return float(p["B"]) * float(p["C"])


## Peak friction coefficient at a load, with load sensitivity about the tyre's nominal load.
static func mu_at(mu: float, fz: float, fz0: float, p: Dictionary) -> float:
	var over := fz / maxf(fz0, 1.0) - 1.0
	return mu * clampf(1.0 - float(p["load_sens"]) * over, 0.72, 1.12)


## Combined-slip forces for normalised slips `sx` (longitudinal) and `sy` (lateral, slip angle and
## camber together): Vector2(fx share, fy share) of mu * load, each signed like its slip.
static func combined(sx: float, sy: float, p: Dictionary) -> Vector2:
	var rho := sqrt(sx * sx + sy * sy)
	if rho < 1e-6:
		return Vector2.ZERO
	var f := shape(rho, p)
	return Vector2(sx, sy) * (f / rho)
