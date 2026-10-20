class_name ShedPump
extends RefCounted
## The shed's own petrol pump, on the outside of the front wall beside the roller door, on the
## business's trade account: ride or wheel a bike up to it, get off, lift the nozzle off the
## pump (its hose follows your hand, up to HOSE metres from where it comes out of the pump),
## hold the work button on the bike to pour, and hang the nozzle back up when you're done.
## The pump's little display counts the litres and the cost as it goes, and the nozzle cuts off
## by itself when the tanks are full. The petrol is the town's price a litre (Shed.PUMP_PRICE,
## as at the High Street's pumps), charged to the garage's account (Shed.charge_garage) each
## time you let go of the trigger; like any other purchase, the business can't run up an
## overdraft for it, so the pump won't start, or stops, when the account can't pay.
##
## Everything here is the host's: Shed.pump holds who has the nozzle, the bike it's pouring
## into and this sale's litres and cost, and the "pump_*" requests are checked (check) and
## applied (apply) by the host like any other. The pouring itself runs in the host's frame
## (process), so the crew all see the same litres go in. ShedPumpView draws it.
##
## Shed.pump: {by: who has the nozzle (0: it's on the pump), bike: the bike it's pouring into
## (0: not pouring), litres and cost: this sale so far (from lifting the nozzle), charged: what
## of that the account has already paid (whole pounds)}.

## The pump: on the outside face of the shed's front wall, west of the roller door, its
## cabinet's middle (x) and the wall's face (z).
const X := -3.6
const WALL_Z := Workshop.CENTER.z + Workshop.HALF.y + 0.3
## Where the hose comes out of the bottom of the cabinet, and where the nozzle hangs.
const HOSE_ROOT := Vector3(X - 0.14, 0.86, WALL_Z + 0.2)
const HOLSTER := Vector3(X + 0.17, 1.14, WALL_Z + 0.3)
## The hose's length: a bike's filler has to be this close to where it comes out of the pump,
## and carried further than HOSE + ARM (on the level) the nozzle's pulled out of your hand.
const HOSE := 3.4
const ARM := 0.6
## Litres a second out of the nozzle (as the town's pumps).
const FILL_RATE := FuelStop.FILL_RATE
## Where a bike's filler cap is when its model isn't to hand to say (bike space).
const FILLER_GUESS := Vector3(0.0, 1.0, -0.2)
## What the player's told the nozzle can't reach.
const NO_REACH := "The hose won't reach that far. Bring the bike closer to the pump."


## A fresh pump: the nozzle hung up, nothing poured.
static func defaults() -> Dictionary:
	return {"by": 0, "bike": 0, "litres": 0.0, "cost": 0.0, "charged": 0}


## The pump from a save or a sync, made safe.
static func sanitize(d) -> Dictionary:
	var out := defaults()
	if d is Dictionary:
		out["by"] = int(d.get("by", 0))
		out["bike"] = int(d.get("bike", 0))
		out["litres"] = maxf(0.0, float(d.get("litres", 0.0)))
		out["cost"] = maxf(0.0, float(d.get("cost", 0.0)))
		out["charged"] = maxi(0, int(d.get("charged", 0)))
	return out


## Pounds a litre at the shed's pump.
static func price() -> float:
	return Shed.PUMP_PRICE


## Who has the nozzle in their hand, or 0.
static func holder() -> int:
	return int(Shed.pump.get("by", 0))


## The bike the nozzle's pouring into, or 0.
static func pouring() -> int:
	return int(Shed.pump.get("bike", 0))


## Where a bike's filler cap is in the world: its model's cap when the shed is drawn, else
## about where a cap is on a bike standing where it's parked.
static func filler_point(bike_id: int) -> Vector3:
	if not Shed.bikes.has(bike_id):
		return Vector3(0.0, -100.0, 0.0)
	var ws = Shed.get_tree().get_first_node_in_group("workshop") if Shed.is_inside_tree() else null
	if ws is Workshop and (ws as Workshop).bike_views.has(bike_id):
		var model := (ws as Workshop).bike_model(bike_id)
		if model != null and model.is_inside_tree() and model.filler != Vector3.ZERO:
			return model.global_transform * model.filler
	var xf = Shed.bikes[bike_id].get("xf")
	return (xf as Transform3D) * FILLER_GUESS if xf is Transform3D else Vector3(0.0, -100.0, 0.0)


## Whether a bike's filler is within the hose's reach.
static func reaches(bike_id: int) -> bool:
	return filler_point(bike_id).distance_to(HOSE_ROOT) <= HOSE


## Whether someone on foot at `at` has pulled the hose further than it goes.
static func overstretched(at: Vector3) -> bool:
	return Vector2(at.x - HOSE_ROOT.x, at.z - HOSE_ROOT.z).length() > HOSE + ARM


## Whether a bike at `at` is stopped by the shed's pump (for the rider's hint).
static func near(at: Vector3) -> bool:
	return Vector2(at.x - X, at.z - WALL_Z).length() < HOSE


## Litres the business can still pay for in this sale.
static func affordable() -> float:
	return (float(Shed.garage_money) + float(Shed.pump.get("charged", 0))) / maxf(price(), 0.01) - float(Shed.pump.get("litres", 0.0))


## Why `peer` can't do a "pump_*" request, or "".
static func check(peer: int, action: Dictionary) -> String:
	match str(action.get("a", "")):
		"pump_nozzle":
			match str(action.get("to", "")):
				"held":
					if holder() != 0:
						return "You've got the nozzle already." if holder() == peer else "%s has the nozzle." % str(Shed.crew.get(holder(), {}).get("name", "Someone"))
					if Shed.riding(peer) != 0:
						return "Get off the bike first."
					if Shed.held_by(peer) != 0:
						return "Put the part down first."
					if Shed.pushing_bike(peer) != 0 or Shed.moving(peer) != 0:
						return "Let go of what you're moving first."
					if Shed.hose_holder() == peer:
						return "Your hands are full of exhaust hose."
					if CoffeeShop.carrying(peer) or PaintBay.carrying(peer):
						return "Put down what you're carrying first."
				"pump":
					if holder() != peer:
						return "You're not holding the nozzle."
				_:
					return "Put it where?"
		"pump_pour":
			if holder() != peer:
				return "Lift the nozzle off the pump first."
			if not bool(action.get("on", true)):
				return ""
			var bike := int(action.get("bike", 0))
			if not Shed.bikes.has(bike):
				return "That bike has gone."
			if int(Shed.bikes[bike].get("rider", 0)) != 0:
				return "Someone is riding that bike."
			if int(Shed.bikes[bike].get("pusher", 0)) != 0:
				return "Someone is wheeling that bike about."
			if Shed.item_on(bike, "tank") == 0:
				return "There's no tank fitted to fill."
			if Shed.fuel_space(bike) < 0.05:
				return "The tank's full."
			if not reaches(bike):
				return NO_REACH
			if affordable() < 0.05:
				return "The business can't afford petrol: it has %s." % TvChannels.money_text(Shed.garage_money)
		_:
			return "The pump doesn't do that."
	return ""


## Does a "pump_*" request (already checked) and says what happened ("" for nothing to say).
static func apply(peer: int, action: Dictionary) -> String:
	var p: Dictionary = Shed.pump
	match str(action.get("a", "")):
		"pump_nozzle":
			if str(action["to"]) == "held":
				# A new sale: the display goes back to nought.
				p["by"] = peer
				p["bike"] = 0
				p["litres"] = 0.0
				p["cost"] = 0.0
				p["charged"] = 0
				return "Lifted the nozzle off the pump. Hold the work button on a bike's tank to fill it."
			var said := _stop()
			p["by"] = 0
			var sale := float(p["litres"])
			if sale < 0.05:
				return "Hung the nozzle back on the pump."
			return "Hung the nozzle back up: %.2f litres for %s, on the business." % [sale, TvChannels.money_text(int(p["charged"]))] \
				if said == "" else said
		"pump_pour":
			if not bool(action.get("on", true)):
				return _stop()
			var bike := int(action["bike"])
			if pouring() != bike:
				_stop()
				p["bike"] = bike
	return ""


## Host, every frame: the petrol goes in while the trigger's held, until the tanks are full
## (the nozzle cuts off), the business can't pay for any more, or the bike's gone out of reach.
static func process(delta: float) -> void:
	var bike := pouring()
	if bike == 0:
		return
	var p: Dictionary = Shed.pump
	var peer := holder()
	if peer == 0 or not Shed.bikes.has(bike) or int(Shed.bikes[bike].get("rider", 0)) != 0 \
			or int(Shed.bikes[bike].get("pusher", 0)) != 0 or not reaches(bike):
		_tell(peer, _stop("The nozzle's out of the tank: stopped."))
		return
	var room := Shed.fuel_space(bike)
	var can := affordable()
	var add := minf(minf(FILL_RATE * delta, room), maxf(can, 0.0))
	if add > 0.0:
		var put := Shed._fill_tanks(bike, add)
		p["litres"] = float(p["litres"]) + put
		p["cost"] = float(p["litres"]) * price()
		Shed._mark_dirty()
	if Shed.fuel_space(bike) < 0.01:
		# The nozzle's sensor in the filler neck: the petrol's reached it, and it clicks off.
		_tell(peer, _stop("Click: the nozzle cut off. %s is brimmed." % str(Shed.bikes[bike]["name"])))
	elif affordable() < 0.01:
		_tell(peer, _stop("The business has run out of money: the pump's stopped."))


## Stops pouring (if it was) and charges the account for what's gone in since it last paid.
## Returns what the player's told: `why` (or how much went in), or "" when it wasn't pouring.
static func _stop(why := "") -> String:
	var p: Dictionary = Shed.pump
	var bike := int(p.get("bike", 0))
	if bike == 0:
		return ""
	p["bike"] = 0
	var owed := ceili(float(p["litres"]) * price() - 0.0001) - int(p["charged"])
	if owed > 0:
		var who := str(Shed.bikes.get(bike, {}).get("name", "a bike"))
		if Shed.charge_garage(owed, "Petrol for %s" % who):
			p["charged"] = int(p["charged"]) + owed
		else:
			# Never more than it can pay (see affordable), but if the account's been spent
			# meanwhile it pays what's there.
			var have := Shed.garage_money
			if have > 0 and Shed.charge_garage(have, "Petrol for %s" % who):
				p["charged"] = int(p["charged"]) + have
	Shed._mark_dirty()
	var sale := "%.2f litres, %s on the business" % [float(p["litres"]), TvChannels.money_text(int(p["charged"]))]
	return "%s %s." % [why, sale] if why != "" else "Stopped at %s." % sale


static func _tell(peer: int, text: String) -> void:
	if peer != 0 and text != "":
		Shed._tell(peer, text, true)


## Keeps the pump straight: whoever had the nozzle has gone, so it's back on the pump (and
## paid for).
static func tidy() -> void:
	var by := holder()
	if by != 0 and not Shed.crew.has(by):
		_stop()
		Shed.pump["by"] = 0


## A save just opened, or a new session: nobody has the nozzle.
static func after_load() -> void:
	Shed.pump["by"] = 0
	Shed.pump["bike"] = 0


# ---------------------------------------------------------------------------- for the player

## What the work button does at the pump, or anywhere with the nozzle in your hand: {action,
## time, verb}, or {}. `target` is the walker's.
static func plan_for(target: Dictionary, peer: int) -> Dictionary:
	var kind := str(target.get("kind", ""))
	if holder() == peer:
		if kind == "part" and int(target.get("bike", 0)) != 0:
			var bike := int(target["bike"])
			return {"action": {"a": "pump_pour", "on": true, "bike": bike}, "time": 0.0, "pour": true,
				"verb": "fill %s with petrol (%dp a litre, on the business)" % [str(Shed.bikes[bike]["name"]), roundi(price() * 100.0)]}
		if kind == "shed_pump":
			return {"action": {"a": "pump_nozzle", "to": "pump"}, "time": 0.3, "verb": "hang the nozzle back on the pump"}
		return {}
	if kind == "shed_pump":
		return {"action": {"a": "pump_nozzle", "to": "held"}, "time": 0.3, "verb": "lift the nozzle off the pump"}
	return {}


## The info panel's lines at the pump, and while carrying the nozzle.
static func describe(target: Dictionary, peer: int) -> Array:
	var lines := []
	var p: Dictionary = Shed.pump
	if str(target.get("kind", "")) == "shed_pump":
		lines.append("The shed's petrol pump")
		lines.append("Unleaded at %dp a litre, on the business's account (it has %s)." % [roundi(price() * 100.0), TvChannels.money_text(Shed.garage_money)])
		if float(p.get("litres", 0.0)) > 0.0:
			lines.append("Last sale: %.2f litres, %s" % [float(p["litres"]), TvChannels.money_text(ceili(float(p["cost"]) - 0.0001))])
		var by := holder()
		if by != 0 and by != peer:
			lines.append("%s has the nozzle." % str(Shed.crew.get(by, {}).get("name", "Someone")))
	if holder() == peer:
		if lines.is_empty():
			lines.append("Petrol nozzle")
		if pouring() != 0:
			lines.append("Pouring: %.2f litres, %s" % [float(p["litres"]), TvChannels.money_text(ceili(float(p["cost"]) - 0.0001))])
		lines.append("Holding the nozzle: hold {work} on a bike near the pump to fill its tank, and hang it back on the pump when you're done.")
	return lines
