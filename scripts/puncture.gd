class_name Puncture
extends RefCounted
## Punctures: a tyre picks up a nail or a thorn (now and then on the road, more off it, and from
## a hard hit on a kerb or pothole), some bikes come in with one, and an MOT or service job may
## have one to find. A punctured tyre lets its air out, slowly or quickly, as it's ridden.
##
## Kept on the tyre item (Shed state, so the crew all see it and it's saved):
##   puncture  how fast it leaks, bar per km ridden (absent or 0: it holds its air)
##   deflate   how much air it has lost, bar, from the pressure it's set to (absent: none)
##   plug      how well a puncture was plugged, 0..1, once it has been (for the part info)
## The pressure it's set to (its tune, see Shed.TUNE_HOME) stays the rider's choice; the air line
## puts back what was lost. Soft, a tyre squirms and grips less (BikeBuild._pressure_grip); nearly
## flat it rolls on the rim: it wallows, grips badly, drags, squashes down and damages itself.

## Leak rates, bar per km: a slow puncture takes a ride or two to let a tyre down, a fast one
## goes flat within a mile or so.
const SLOW := 0.12
const FAST := 1.4
## Chance of a puncture per km ridden on each surface (per tyre). The road is mostly clean;
## tracks and fields have thorns, flints and old fence wire. On an adventure a tyre is the only
## thing that can go wrong (see Roadside).
const PER_KM := {"tarmac": 0.0003, "concrete": 0.0003, "dirt": 0.0012, "gravel": 0.0014, "grass": 0.0008, "sand": 0.0006, "snow": 0.0004}
## Chance a hard hit (the suspension bottoming at speed: a kerb, a pothole) pinches a tyre.
const PER_HIT := 0.04
const HIT_SPEED := 9.0          # m/s: slower knocks don't pinch
const HIT_CLOSING := 1.5        # m/s: nor does the wheel coming up on to its stop any slower than this
## Below this share of its best pressure the tyre starts to fold and roll on the rim.
const FOLD_AT := 0.55
## How much of the tyre's height a fully flat tyre squashes down by.
const SQUASH := 0.6
## A tyre with no air grips this share of what it would with some (on top of being soft).
const FLAT_GRIP := 0.45
## Extra rolling drag on a flat tyre (times the normal).
const FLAT_DRAG := 3.0
## Riding on a flat: tyre and wheel wear per km at fully flat.
const FLAT_TYRE_WEAR := 0.05
const FLAT_RIM_WEAR := 0.015
## A plug this good (0..1) seals the hole; worse, it still weeps air (a slow leak at this share).
const PLUG_SEALS := 0.5
const PLUG_WEEP := 0.25
## Chance a bike arriving is on a punctured tyre, by where it came from.
const ARRIVE := {"barn": 0.35, "crash": 0.3, "project": 0.12, "mot": 0.3, "maint": 0.15}


## The leak rate of a tyre item, bar per km (0 when it holds its air).
static func rate(item: Dictionary) -> float:
	return maxf(float(item.get("puncture", 0.0)), 0.0)


static func punctured(item: Dictionary) -> bool:
	return rate(item) > 0.0


## The air a tyre has lost, bar.
static func lost(item: Dictionary) -> float:
	return maxf(float(item.get("deflate", 0.0)), 0.0)


## How flat a tyre is from its pressure now and its best pressure: 0 while it still holds its
## shape (above FOLD_AT of its best), 1 with no air in it at all.
static func flat_of(psi: float, best: float) -> float:
	var fold := maxf(best, 0.1) * FOLD_AT
	return clampf((fold - psi) / fold, 0.0, 1.0)


## The grip a tyre keeps for being `flat` (0..1): rolling on the rim it hardly grips.
static func flat_grip(flat: float) -> float:
	return lerpf(1.0, FLAT_GRIP, clampf(flat, 0.0, 1.0))


## Whether a hard hit at `speed` m/s pinches the tyre, given a roll 0..1: `closing` is how fast
## the wheel was knocked up into the bump stop (m/s). A fork sinking on to its stop under the
## brakes is no hit at all.
static func hit_punctures(speed: float, roll: float, closing := INF) -> bool:
	return absf(speed) >= HIT_SPEED and closing >= HIT_CLOSING and roll < PER_HIT


## Whether `km` ridden on `surface` picks up a puncture, given a roll 0..1.
static func ride_punctures(surface: String, km: float, roll: float) -> bool:
	return roll < float(PER_KM.get(surface, 0.003)) * km


## "slow" or "fast": what kind of puncture, from a roll 0..1 (most are slow).
static func kind_of_roll(roll: float) -> String:
	return "fast" if roll < 0.25 else "slow"


static func rate_of_kind(kind: String) -> float:
	return FAST if kind == "fast" else SLOW


## The line for the part info: "Puncture: losing air fast (0.8 bar down)", or a plug's quality,
## or "" for a tyre that has never had one.
static func text(item: Dictionary) -> String:
	var out := ""
	if punctured(item):
		out = "Puncture: %s" % ("losing air fast" if rate(item) >= 0.5 * FAST else "a slow leak")
		if item.has("plug"):
			out = "Puncture: the plug weeps air (a slow leak)"
		out += ". Plug it with a puncture repair kit, or change the tyre."
	elif item.has("plug"):
		out = "Puncture plugged (%d%%): holds its air" % roundi(float(item["plug"]) * 100.0)
	if lost(item) > 0.05:
		out += ("\n" if out != "" else "") + Controls.hint("Pressure low: %.1f bar down. Pump it up from the air line ({work2}, empty-handed)." % lost(item))
	return out
