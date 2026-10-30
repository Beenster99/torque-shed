class_name Adventure
extends RefCounted
## An adventure ride in the shed's shared state (Shed.adventure): the host starts one for the
## whole crew along the journey they planned on the map (AdventureJourney, AdventurePlans), every
## player's game plans the same road from it (AdventureWorld) and puts them on a bike at the start;
## reaching the last pin, or the host ending it, brings everyone back to the shed with their bikes
## as they were (the fuel burnt, the muck and the tyres' wear kept; nothing else on the bike wears
## out there, see Roadside).
##
## Shed.adventure: {} when there's none, else {id, seed (for the stops along it), km, plan (see
## AdventurePlans), real and real_hash (the planned road's id and hash), theme (the look of its
## land), dest (the last pin's place, see AdventureDest), title, by (the host's name),
## riders {peer: bike id, 0 when there was none for them}, arrived (the first peer to reach the
## destination, 0 till then), arrived_name, photo (the crew's photo there, once arrived), network (whether it's
## ridden on the road network: the host's Esc > Debug toggle when they set off, the same for everyone), builds and
## ride_hash (the host's builder and ride hashes, see AdventureCrew: on the network every machine must match them),
## route (the crew's agreed route and its "leave the route?" call, see AdventureCrew), left (the guests who've
## left the ride for the shed, see adventure_leave)}. Never
## carried over in a save: loading one finds everybody back at the shed.
##
## Actions (Shed.request): adventure_start {plan, seed, title} (the host, from the route planner:
## any shed TV tuned to the Route planner channel, see RouteTv) and adventure_end (the host: "Ride home"
## once everyone's at the destination; it ends for everyone), adventure_leave (a guest: back to the shed on their
## own, the rest riding on), adventure_join {bike: the one you'd like, or home: one of
## their own from their collection, or foot: true to walk} (each player, on loading it, from AdventureBikePicker) and adventure_arrive (the first there: everyone's brought to the destination, gets
## XP, and the photo goes in the diary on the bookshelf, not on the shed wall);
## adventure_resume (the host) carries on the one a night's sleep put away (Shed.adventure_save,
## see AdventureNeeds), everyone back where they slept.
## adventure_highlight (see
## AdventureDiary, which keeps the crew's highlights here as "log").
## adventure_builds {builds} (each player as they join the shed: their game's builder hash, kept in Shed.crew, and
## the crew told when it isn't the host's); adventure_route_call {kind: "leave" or "rejoin"} (any rider: asks the
## crew), adventure_route_vote {id, yes} (any rider: their answer) and adventure_route_tick (the host, settling a
## call whose time is up): see AdventureCrew. adventure_ferry_board {id, from, to, seconds} (a rider at a ferry's ramp:
## aboard), adventure_ferry_landed {sail} (a rider off on the far side) and adventure_ferry_tick (the host: lets it go
## when the crew's aboard, clears it once they've all landed): the crew's sailing is Shed.adventure "ferry"
## (AdventureCrew, FerryCrossing).

const MIN_KM := 5.0
const MAX_KM := 400.0
## Real minutes for a whole day and night out on an adventure (the shed's own day is the
## Settings' length): fast enough to ride through a night in a session.
const DAY_MINUTES := 75.0


static func active() -> bool:
	return int(Shed.adventure.get("id", 0)) != 0


## The state as received or loaded: a running adventure kept as it is, anything else none.
static func sanitize(v) -> Dictionary:
	if not (v is Dictionary) or int(v.get("id", 0)) == 0:
		return {}
	if not (v.get("plan") is Dictionary):
		return {}
	var out: Dictionary = v.duplicate(true)
	out["seed"] = int(out.get("seed", 1))
	out["km"] = clampf(float(out.get("km", MIN_KM)), MIN_KM, MAX_KM)
	out["theme"] = str(out.get("theme", "varied"))
	if not (out.get("riders") is Dictionary):
		out["riders"] = {}
	out["arrived"] = int(out.get("arrived", 0))
	out["dest"] = str(out.get("dest", "")).left(48)
	out["title"] = str(out.get("title", ""))
	out["real"] = str(out.get("real", ""))
	out["real_hash"] = str(out.get("real_hash", ""))
	out["network"] = bool(out.get("network", false))
	out["builds"] = str(out.get("builds", ""))
	out["ride_hash"] = str(out.get("ride_hash", ""))
	out["route"] = AdventureCrew.sanitize_route(out.get("route"))
	var left := []
	if out.get("left") is Array:
		for p in out["left"]:
			left.append(int(p))
	out["left"] = left
	# Planned here too (the host's road if all is well; if not, what was said is kept, for AdventureTrip.real_mismatch
	# to turn down).
	var plan := AdventurePlans.clean(out["plan"])
	if not plan.is_empty():
		out["plan"] = plan
		AdventurePlans.pack_for(plan)
	return out


## Hours of game time a real second, out on an adventure.
static func day_rate() -> float:
	return 24.0 / (DAY_MINUTES * 60.0)


static func _is_host(peer: int) -> bool:
	return not Net.is_online() or peer == 1


## Whether the ride on now is ridden on the road network (the host's choice, everyone's).
static func network() -> bool:
	return active() and bool(Shed.adventure.get("network", false))


## The crew's route mode: "route" while it rides the route it agreed, "free" once it's agreed to leave it (see
## AdventureCrew). The sat nav reads it.
static func route_mode() -> String:
	return str((Shed.adventure["route"] as Dictionary).get("mode", "route")) if Shed.adventure.get("route") is Dictionary else "route"


## One more each time the crew changes its route mode.
static func route_version() -> int:
	return int((Shed.adventure["route"] as Dictionary).get("version", 0)) if Shed.adventure.get("route") is Dictionary else 0


## The crew's open "leave the route?" call ({} when there's none): {id, by, kind, votes {peer: bool}, ends}.
static func route_call() -> Dictionary:
	return (Shed.adventure["route"] as Dictionary).get("call", {}) if Shed.adventure.get("route") is Dictionary else {}


## Whether `peer` has left the ride on now for the shed (see adventure_leave): they stay at home till the next one.
static func has_left(peer: int) -> bool:
	return active() and Shed.adventure.get("left") is Array and (Shed.adventure["left"] as Array).has(peer)


## The peers out on the ride now (joined it and still in the crew).
static func riders_out() -> Array:
	var out := []
	var riders = Shed.adventure.get("riders", {})
	if riders is Dictionary:
		for p in riders:
			if Shed.crew.has(int(p)) or Shed.crew.has(p):
				out.append(int(p))
	out.sort()
	return out


static func check(peer: int, action: Dictionary) -> String:
	match str(action.get("a", "")):
		"adventure_pin", "adventure_unpin", "adventure_mode", "adventure_in", "adventure_load", "adventure_clear", "adventure_view", "adventure_survey":
			return AdventureJourney.check(peer, action)
		"adventure_start":
			if not _is_host(peer):
				return "Only the host can start an adventure."
			if active():
				return "There's an adventure on already."
			if AdventureWorld.network:
				var odd := AdventureCrew.odd_ones(Shed.crew, AdventureCrew.builds())
				if not odd.is_empty():
					return "%s on a different version of the game: everyone needs the same one to ride the road network together." % (
						" and ".join(odd) + (" is" if odd.size() == 1 else " are"))
			return AdventureJourney.start_check(action)
		"adventure_resume":
			if not _is_host(peer):
				return "Only the host can carry on an adventure."
			if active():
				return "There's an adventure on already."
			if Shed.adventure_save.is_empty():
				return "There's no adventure put away to carry on."
		"adventure_end":
			if not _is_host(peer):
				return "Only the host can end the adventure."
			if not active():
				return "There's no adventure on."
		"adventure_leave":
			if not active():
				return "There's no adventure on."
			if _is_host(peer):
				return "The host ends the adventure for everyone."
			if has_left(peer):
				return "You've left this adventure already."
		"adventure_join", "adventure_arrive":
			if not active():
				return "There's no adventure on."
			if has_left(peer):
				return "You've left this adventure."
		"adventure_highlight":
			return AdventureDiary.check(peer, action)
		"adventure_builds":
			return ""
		"adventure_route_call":
			if not active():
				return "There's no adventure on."
			return AdventureCrew.call_check(_route(), peer, str(action.get("kind", "")), riders_out())
		"adventure_route_vote":
			if not active():
				return "There's no adventure on."
			return AdventureCrew.vote_check(_route(), peer, int(action.get("id", 0)), riders_out())
		"adventure_route_tick", "adventure_ferry_tick":
			if not _is_host(peer) or not active():
				return "Only the host keeps time."
		"adventure_ferry_landed":
			if not active():
				return "There's no adventure on."
		"adventure_ferry_board":
			if not active():
				return "There's no adventure on."
			return AdventureCrew.board_check(AdventureCrew.sanitize_ferry(Shed.adventure.get("ferry", {})), peer,
				str(action.get("id", "")), int(action.get("from", -1)), riders_out())
		_:
			return "Unknown adventure action."
	return ""


## Applies a checked action; returns what to tell the player (or, starting with "*", the whole crew).
static func apply(peer: int, action: Dictionary) -> String:
	var who := str(Shed.crew.get(peer, {}).get("name", "Someone"))
	match str(action.get("a", "")):
		"adventure_pin", "adventure_unpin", "adventure_mode", "adventure_in", "adventure_load", "adventure_clear", "adventure_view", "adventure_survey":
			return AdventureJourney.apply(peer, action, who)
		"adventure_start":
			var planned: Dictionary = AdventureJourney.start_info(action)
			var km := float(planned["km"])
			var dest := str(planned["dest"])
			var title := str(action.get("title", "")).left(48)
			Shed.adventure = {"id": 1 + randi() % 1000000000, "seed": int(action.get("seed", randi())), "km": km,
				"theme": planned["theme"], "dest": dest, "title": title if title != "" else "Ride to %s" % dest,
				"plan": planned["plan"], "real": planned["real"], "real_hash": planned["real_hash"],
				"by": who, "riders": {}, "left": [], "arrived": 0, "arrived_name": "", "network": AdventureWorld.network,
				"builds": AdventureCrew.builds(), "ride_hash": "", "route": AdventureCrew.sanitize_route({})}
			if AdventureWorld.network:
				var plan: Dictionary = planned["plan"]
				Shed.adventure["ride_hash"] = AdventureCrew.ride_hash(RealRegion.get_region(str(plan.get("region", ""))))
			Shed.adventure_save = {}   # a new adventure: any put away overnight is forgotten
			Shed.journey.erase("in")   # (said for this ride: the next is to be agreed afresh)
			AdventureDiary.started(true)
			return "*%s is off on an adventure ride: %s, %d km to %s. Everyone to the start!" % [who, str(Shed.adventure["title"]),
				roundi(km), dest]
		"adventure_resume":
			var save := Shed.adventure_save
			Shed.adventure = (save["adventure"] as Dictionary).duplicate(true)
			Shed.adventure["id"] = 1 + randi() % 1000000000
			Shed.adventure["riders"] = {}
			Shed.adventure["arrived"] = 0
			Shed.adventure["arrived_name"] = ""
			Shed.adventure["by"] = who
			Shed.adventure["left"] = []
			Shed.adventure["route"] = AdventureCrew.sanitize_route(Shed.adventure.get("route"))
			(Shed.adventure["route"] as Dictionary)["call"] = {}   # (a call left open overnight is forgotten)
			Shed.adventure["resume"] = (save["at"] as Dictionary).duplicate()
			Shed.adventure["resume_at"] = (save.get("where", {}) as Dictionary).duplicate(true)
			if Daylight.current:
				Daylight.current.set_time(float(save.get("hours", AdventureNeeds.MORNING)))
			AdventureDiary.started(false)
			return "*%s carries on the adventure: %.1f of %d km done. Everyone back on the road!" % [who,
				AdventureNeeds.save_s(save) / 1000.0, roundi(float(Shed.adventure.get("km", 0.0)))]
		"adventure_end":
			Shed.adventure = {}
			return "*The adventure's over: back to the shed."
		"adventure_leave":
			# Off the ride: their game takes them home (AdventureTrip.sync), parking the bike they're on in the shed. One
			# of theirs left at the roadside comes home too.
			var riders: Dictionary = Shed.adventure["riders"]
			var bike := int(riders.get(peer, riders.get(str(peer), 0)))
			riders.erase(peer)
			riders.erase(str(peer))
			if not (Shed.adventure.get("left") is Array):
				Shed.adventure["left"] = []
			(Shed.adventure["left"] as Array).append(peer)
			if Shed.bikes.has(bike):
				var b: Dictionary = Shed.bikes[bike]
				b.erase("push")
				b.erase("tow")
				if b.has("roadside") and int(b.get("rider", 0)) == 0:
					b.erase("roadside")
					b["xf"] = Roadside.home_spot(bike)
					b["stand"] = ""
			return "*%s has left the adventure and gone back to the shed." % who
		"adventure_join":
			var riders: Dictionary = Shed.adventure["riders"]
			var bike := Shed.riding(peer)
			var preferred := int(action.get("bike", 0))
			var cid := int(action.get("home", 0))
			if bike == 0 and cid != 0 and Collection.check(peer, {"a": "home_take", "bike": cid}) == "":
				# One of their own from home: out of the collection for the ride (as home_take).
				Collection.apply(peer, {"a": "home_take", "bike": cid})
				Shed.homes_touched()
				preferred = int(Collection.entry(cid).get("out", 0))
			if bike == 0 and not bool(action.get("foot", false)):
				bike = _bike_for(peer, preferred, riders)
				if bike != 0:
					Shed.bikes[bike]["rider"] = peer
					Shed.bikes[bike]["stand"] = ""
					Shed.bikes[bike]["pusher"] = 0
					if Shed.crew.has(peer):
						Shed.crew[peer]["riding"] = bike
			riders[peer] = bike
			if AdventureNeeds.of(peer).is_empty():
				AdventureNeeds.joined(peer)
			if bike == 0:
				return "There's no bike ready to ride for you, so you've come along on foot."
			return ""
		"adventure_arrive":
			if int(Shed.adventure.get("arrived", 0)) != 0:
				return ""
			Shed.adventure["arrived"] = peer
			Shed.adventure["arrived_name"] = who
			Shed.adventure_save = {}   # there: nothing left to carry on
			AdventureDiary.arrived(peer)
			return "*" + _arrive(who)
		"adventure_highlight":
			return AdventureDiary.apply(peer, action)
		"adventure_builds":
			var b := str(action.get("builds", "")).left(16)
			if Shed.crew.has(peer):
				Shed.crew[peer]["builds"] = b
			if peer != Shed.me() and b != AdventureCrew.builds():
				return "*%s's game is a different version from the host's: fine in the shed, but you'll all need the same one to ride the road network together." % who
			return ""
		"adventure_route_call":
			var route := _route()
			var kind := str(action.get("kind", ""))
			AdventureCrew.open_call(route, peer, kind, Time.get_ticks_msec())
			var done := _settle_route(route)
			if done != "":
				return done
			return "*%s asks: %s? Everyone out on the ride, answer yes or no." % [who, AdventureCrew.ASKS[kind]]
		"adventure_route_vote":
			var route := _route()
			(route["call"]["votes"] as Dictionary)[peer] = bool(action.get("yes", false))
			return _settle_route(route)
		"adventure_route_tick":
			return _settle_route(_route())
		"adventure_ferry_board":
			var ferry := AdventureCrew.sanitize_ferry(Shed.adventure.get("ferry", {}))
			var sail := int(Shed.adventure.get("ferry_sails", 0)) + (1 if ferry.is_empty() else 0)
			Shed.adventure["ferry_sails"] = sail
			Shed.adventure["ferry"] = AdventureCrew.board(ferry, peer, str(action.get("id", "")), int(action.get("from", -1)),
				int(action.get("to", -1)), float(action.get("seconds", 0.0)), sail, Time.get_ticks_msec())
			return _ferry_tick()
		"adventure_ferry_tick":
			return _ferry_tick()
		"adventure_ferry_landed":
			var ferry := AdventureCrew.sanitize_ferry(Shed.adventure.get("ferry", {}))
			if not ferry.is_empty() and int(ferry["sail"]) == int(action.get("sail", 0)):
				(ferry["landed"] as Dictionary)[peer] = true
				Shed.adventure["ferry"] = ferry
			return _ferry_tick()
	return ""


## The host lets the ferry go when the crew's aboard (AdventureCrew.should_sail), and clears a sailing that's over.
static func _ferry_tick() -> String:
	var ferry := AdventureCrew.sanitize_ferry(Shed.adventure.get("ferry", {}))
	if ferry.is_empty():
		return ""
	var now := Time.get_ticks_msec()
	if int(ferry["departs"]) != 0:
		if AdventureCrew.sailing_over(ferry, riders_out(), now, FerryCrossing.total_of(ferry)):
			Shed.adventure["ferry"] = {}
		return ""
	if AdventureCrew.should_sail(ferry, riders_out(), now):
		ferry["departs"] = maxi(now, 1)
		Shed.adventure["ferry"] = ferry
		return "*The ferry's leaving." if riders_out().size() > 1 else ""
	return ""


## The route state in Shed.adventure, made whole (and kept there) to change.
static func _route() -> Dictionary:
	if not (Shed.adventure.get("route") is Dictionary):
		Shed.adventure["route"] = AdventureCrew.sanitize_route({})
	var route: Dictionary = Shed.adventure["route"]
	if not (route.get("call") is Dictionary):
		route["call"] = {}
	return route


## Settles the open call once its outcome is known (AdventureCrew.outcome); what to tell the crew ("*...") or "".
static func _settle_route(route: Dictionary) -> String:
	var c: Dictionary = route.get("call", {})
	if c.is_empty():
		return ""
	var said := AdventureCrew.settle(route, AdventureCrew.outcome(c, riders_out(), Time.get_ticks_msec()))
	return "*" + said if said != "" else ""


## Everyone's at the destination: the crew's photo (kept with the diary, which stands on the shed's
## bookshelf: Simon didn't want them on the walls) and XP for each of them (more for a longer ride).
## What to tell them.
static func _arrive(who: String) -> String:
	var ids := Shed.crew.keys()
	ids.sort()
	var names := ids.map(func(p): return str(Shed.crew[p].get("name", "Rider")))
	var photo := AdventureDest.make_photo(Shed.adventure, names)
	Shed.adventure["photo"] = photo
	var km := float(Shed.adventure.get("km", 0.0))
	for p in ids:
		Progress.award(int(p), "adventure_done", km / 100.0, "adventure:%d" % int(Shed.adventure["id"]))
	return "%s has reached %s! Photo time!" % [
		who, AdventureDest.name_of(str(Shed.adventure.get("dest", "")))]


## The bike `peer` takes: `preferred` (the one they were by) if it's free to ride, else the
## first free one that's ready. 0 when there's none.
static func _bike_for(peer: int, preferred: int, riders: Dictionary) -> int:
	var taken := riders.values()
	var order := [preferred] if preferred != 0 else []
	var ids := Shed.bikes.keys()
	ids.sort()
	order.append_array(ids)
	for id in order:
		if not Shed.bikes.has(id) or taken.has(id):
			continue
		if Shed.check(peer, {"a": "mount", "bike": id}) == "":
			return int(id)
	return 0


## The Esc menu's adventure button: opens the route planner (JourneyMap, the same board as the TVs' Route planner channel) to plan
## one, or the host ends the one on for everyone ("Ride home" once everyone's at the destination), or a guest leaves it.
static func menu_action() -> void:
	if active():
		Shed.request({"a": "adventure_end" if Shed.is_authority() else "adventure_leave"})
	elif AdventureTrip.current:
		AdventureTrip.current.open_journey.call_deferred()


## Starts a ride along `plan` (see AdventurePlans), its stops laid out by `seed` (the Debug tab and tests).
static func start(plan: Dictionary, seed := 1, title := "") -> void:
	Shed.request({"a": "adventure_start", "plan": plan, "seed": seed, "title": title})


## What the Esc menu's button says, and why it can't be pressed ("" when it can).
## The Esc menu's "Continue adventure" button: [text, why it can't be pressed], or [] when
## there's none put away (or one's on).
static func continue_text() -> Array:
	var save := Shed.adventure_save
	if active() or save.is_empty():
		return []
	var km := float((save["adventure"] as Dictionary).get("km", 0.0))
	return ["Continue adventure: %.1f of %d km done, %d %s in (host carries it on for everyone)" % [AdventureNeeds.save_s(save) / 1000.0,
		roundi(km), maxi(1, int(save.get("nights", 1))), "night" if int(save.get("nights", 1)) <= 1 else "nights"],
		"" if Shed.is_authority() else "The host carries the adventure on."]


static func menu_text() -> Array:
	var host := Shed.is_authority()
	if active() and not host:
		return ["Leave the adventure (just you back to the shed; the rest ride on)",
			"You've left this adventure." if has_left(Shed.me()) else ""]
	if active() and int(Shed.adventure.get("arrived", 0)) != 0:
		return ["Ride home (everyone back to the shed)", ""]
	if active():
		return ["End the adventure for everyone (everyone back to the shed)", ""]
	return ["Adventure ride: plan one on any TV's Route planner channel, or here (the host starts it for everyone)", ""]
