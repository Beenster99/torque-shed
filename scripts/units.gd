class_name Units
extends RefCounted
## Numbers shown to the player in their chosen units: metric (km/h, km, kg, L/100 km) or
## imperial (mph, miles, lb, UK mpg). The simulation itself always works in metric.

const KM_PER_MILE := 1.609344
const LB_PER_KG := 2.20462
const LITRES_PER_GALLON := 4.54609   # UK gallon


static func imperial() -> bool:
	return Settings.units == "imperial"


## Speed from metres per second, as a whole number in the chosen unit.
static func speed_value(mps: float) -> int:
	var kmh := absf(mps) * 3.6
	return roundi(kmh / KM_PER_MILE if imperial() else kmh)


static func speed_unit() -> String:
	return "mph" if imperial() else "km/h"


## "84 km/h" or "52 mph", from km/h.
static func kmh(value: float) -> String:
	return "%d %s" % [roundi(value / KM_PER_MILE if imperial() else value), speed_unit()]


## "12.5 km" or "7.8 miles".
static func distance(km: float, decimals := 1) -> String:
	var v := km / KM_PER_MILE if imperial() else km
	return ("%." + str(decimals) + "f %s") % [v, "miles" if imperial() else "km"]


static func distance_value(km: float) -> float:
	return km / KM_PER_MILE if imperial() else km


static func distance_unit() -> String:
	return "mi" if imperial() else "km"


## "184 kg" or "406 lb".
static func mass(kg: float, decimals := 0) -> String:
	var v := kg * LB_PER_KG if imperial() else kg
	return ("%." + str(decimals) + "f %s") % [v, "lb" if imperial() else "kg"]


static func mass_unit() -> String:
	return "lb" if imperial() else "kg"


static func mass_value(kg: float) -> float:
	return kg * LB_PER_KG if imperial() else kg


## Fuel economy from kilometres per litre: "52 mpg" or "5.4 L/100 km". "--" when unknown.
static func economy(km_per_l: float) -> String:
	if km_per_l <= 0.0 or is_inf(km_per_l) or is_nan(km_per_l):
		return "-- " + economy_unit()
	if imperial():
		return "%d mpg" % roundi(km_per_l / KM_PER_MILE * LITRES_PER_GALLON)
	return "%.1f L/100 km" % (100.0 / km_per_l)


static func economy_unit() -> String:
	return "mpg" if imperial() else "L/100 km"


## Higher is better in both units, for comparing economy before and after a change.
static func economy_value(km_per_l: float) -> float:
	if km_per_l <= 0.0:
		return 0.0
	return km_per_l / KM_PER_MILE * LITRES_PER_GALLON if imperial() else 100.0 / km_per_l
