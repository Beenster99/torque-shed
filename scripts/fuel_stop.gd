class_name FuelStop
extends RefCounted
## Filling up while you ride, and the low fuel warning. Stop beside any pump (a node in the
## "fuel_pump" group, see FuelPump) and hold {interact}: the petrol goes in at FILL_RATE,
## the tanks (and any auxiliary tank) filling until they're full, you let go, or your own money
## runs out. When you let go you pay for what went in, out of your own pocket, and the shed is
## told (Shed "refuel"), so the crew sees the tank full and it's saved.
##
## As the petrol gets low the rider is told once, with how far it'll go; at empty the engine
## cuts out (Bike).

## Litres a second from the pump nozzle.
const FILL_RATE := 1.5
## The share of the tanks left when the low fuel warning comes on (the reserve), and when it's
## off again after filling up.
const LOW := 0.15
const LOW_CLEAR := 0.25
## Slower than this (m/s) you're stopped at the pump.
const STOPPED := 0.8

var bike: Bike
var filling := false
var litres := 0.0           # put in so far this fill
var pump: Node3D            # the pump filling from
var warned := false         # told about low fuel this time round


func _init(ridden: Bike = null) -> void:
	bike = ridden


## The nearest pump within `reach` of `at`, or null.
static func nearest_pump(tree: SceneTree, at: Vector3, reach := FuelPump.REACH) -> Node3D:
	var best: Node3D = null
	var best_d := reach
	for n in tree.get_nodes_in_group(FuelPump.GROUP):
		var p := n as Node3D
		if p == null or not p.is_inside_tree():
			continue
		var d := Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length()
		if d < best_d and absf(p.global_position.y - at.y) < 3.0:
			best = p
			best_d = d
	return best


## A pump's price a litre (its own, else the town's).
static func price_of(p: Node) -> float:
	if p != null and p.has_method("price_per_litre"):
		return float(p.price_per_litre())
	return Shed.PUMP_PRICE


## The pump the bike is stopped at, or null.
func pump_here() -> Node3D:
	if bike == null or not bike.is_inside_tree() or absf(bike.speed) > STOPPED or bike.is_crashed:
		return null
	return nearest_pump(bike.get_tree(), bike.global_position)


## Room left in the tanks, litres.
func space() -> float:
	return maxf(bike.build.fuel_capacity - bike.fuel_litres, 0.0) if bike else 0.0


## What a pump would let you have with `money` pounds: litres.
static func affordable(money: int, price: float) -> float:
	return float(money) / maxf(price, 0.01)


## Starts filling at the pump here. "" when it's started, else why not.
func start() -> String:
	var p := pump_here()
	if p == null:
		return "Stop beside a pump to fill up."
	if space() < 0.05:
		return "The tank's full."
	if Progress.money() < ceili(price_of(p)):
		return "You haven't the money for petrol."
	filling = true
	litres = 0.0
	pump = p
	return ""


## Keeps filling while `held`; stops (and pays) when let go, full, out of money or moved off.
## Returns a message for the rider when it stops, else "".
func update(delta: float, held: bool) -> String:
	if not filling:
		return ""
	var p := pump_here()
	var price := price_of(pump)
	var can_pay := affordable(Progress.money(), price) - litres
	if not held or p == null or p != pump or space() < 0.01 or can_pay <= 0.01:
		return finish()
	var add := minf(minf(FILL_RATE * delta, space()), can_pay)
	litres += add
	bike.fuel_litres += add
	return ""


## Stops filling and pays for it. Returns what the rider is told.
func finish() -> String:
	if not filling:
		return ""
	filling = false
	if litres < 0.05:
		return ""
	var price := price_of(pump)
	var cost := maxi(1, ceili(litres * price))
	var paid := cost if Progress.spend(cost, "Petrol") else 0
	Shed.request({"a": "refuel", "litres": litres, "paid": paid})
	var text := "Filled up: %.1f L for %s." % [litres, TvChannels.money_text(cost)]
	if bike.fuel_litres >= bike.build.fuel_capacity - 0.05:
		text = "Brimmed: %.1f L for %s." % [litres, TvChannels.money_text(cost)]
	litres = 0.0
	if bike.fuel_litres / maxf(bike.build.fuel_capacity, 0.1) > LOW_CLEAR:
		warned = false
	return text


## How full the tanks are, 0..1.
func level() -> float:
	return clampf(bike.fuel_litres / maxf(bike.build.fuel_capacity, 0.1), 0.0, 1.0) if bike else 1.0


## Whether the low fuel light is on.
func low() -> bool:
	return bike != null and level() < LOW


## The low fuel warning, once as it comes on: "" the rest of the time.
func warning() -> String:
	if bike == null:
		return ""
	if not low():
		if level() > LOW_CLEAR:
			warned = false
		return ""
	if warned or not bike.engine_on:
		return ""
	warned = true
	var km := bike.fuel_litres * bike.build.cruise_economy()
	return "Low fuel: %.1f L left, about %s. Find a pump." % [bike.fuel_litres, Units.distance(km, 0)]
